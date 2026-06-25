# Monitoring et observabilité : chaque microservice a sa propre uptime check
# (sonde HTTPS sur /health depuis l'infra Google, indépendante du conteneur) et
# son alerte associée. Les logs structurés (stdout JSON) et métriques de requêtes
# Cloud Run (latence, taux d'erreur, instances actives) sont collectés
# automatiquement par Cloud Logging/Monitoring, sans config supplémentaire.

resource "google_monitoring_notification_channel" "email" {
  display_name = "notes-app alerts"
  type         = "email"

  labels = {
    email_address = var.alert_notification_email
  }

  depends_on = [google_project_service.monitoring]
}

locals {
  monitored_services = {
    history-api = google_cloud_run_v2_service.history_api.uri
    files-api   = google_cloud_run_v2_service.files_api.uri
    ui          = google_cloud_run_v2_service.ui.uri
  }
}

resource "google_monitoring_uptime_check_config" "service_health" {
  for_each     = local.monitored_services
  display_name = "notes-${each.key}-health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path    = each.key == "ui" ? "/" : "/health"
    port    = 443
    use_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = replace(each.value, "https://", "")
    }
  }
}

resource "google_monitoring_alert_policy" "service_down" {
  for_each     = local.monitored_services
  display_name = "notes-${each.key}-down"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failure - ${each.key}"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.service_health[each.key].uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "60s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}
