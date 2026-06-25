locals {
  registry_prefix     = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/notes-app"
  history_api_image   = "${local.registry_prefix}/history-service:${var.app_version}"
  files_api_image     = "${local.registry_prefix}/files-service:${var.app_version}"
  ui_image            = "${local.registry_prefix}/frontend:${var.app_version}"
}

# ── history-api : possède PostgreSQL, expose /records et /history ──────────────
resource "google_cloud_run_v2_service" "history_api" {
  name     = "notes-history-api"
  location = var.gcp_region

  template {
    service_account = google_service_account.cloud_run_runtime.email

    # Scaling horizontal géré par Cloud Run : entre min_instance_count et
    # max_instance_count instances du conteneur sont démarrées/arrêtées selon
    # le nombre de requêtes concurrentes (pas de scaling vertical, le conteneur
    # garde toujours la même taille CPU/mémoire).
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      image = local.history_api_image

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz/ready"
        }
        initial_delay_seconds = 0
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/healthz/ready"
        }
        period_seconds    = 30
        timeout_seconds   = 3
        failure_threshold = 2
      }
    }
  }
}

# ── files-api : possède S3, expose /objects /object /export /store, appelle
#    history-api en HTTP pour journaliser chaque upload et lire l'historique ──
resource "google_cloud_run_v2_service" "files_api" {
  name     = "notes-files-api"
  location = var.gcp_region

  template {
    service_account = google_service_account.cloud_run_runtime.email

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      image = local.files_api_image

      env {
        name  = "HISTORY_SERVICE_URL"
        value = google_cloud_run_v2_service.history_api.uri
      }
      env {
        name = "AWS_ACCESS_KEY_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.aws_access_key_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "AWS_SECRET_ACCESS_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.aws_secret_access_key.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "AWS_DEFAULT_REGION"
        value = var.s3_region
      }
      env {
        name  = "S3_BUCKET_NAME"
        value = var.s3_bucket_name
      }

      # Zero-downtime: Cloud Run ne route pas le trafic vers la nouvelle révision
      # tant que cette probe ne répond pas 200. Si S3 est inaccessible → déploiement
      # bloqué, ancienne révision reste active.
      startup_probe {
        http_get {
          path = "/healthz/ready"
        }
        initial_delay_seconds = 0
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/healthz/ready"
        }
        period_seconds    = 30
        timeout_seconds   = 3
        failure_threshold = 2
      }
    }
  }
}

# ── ui : frontend statique Nginx, seul service exposé au navigateur ────────────
resource "google_cloud_run_v2_service" "ui" {
  name     = "notes-ui"
  location = var.gcp_region

  template {
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      image = local.ui_image
      env {
        name  = "API_URL"
        value = google_cloud_run_v2_service.files_api.uri
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "history_api_public" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.history_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "files_api_public" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.files_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "ui_public" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.ui.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
