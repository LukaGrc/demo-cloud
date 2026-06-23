locals {
  registry_prefix = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/notes-app"
  api_image       = "${local.registry_prefix}/backend:${var.app_version}"
  ui_image        = "${local.registry_prefix}/frontend:${var.app_version}"
}

resource "google_cloud_run_v2_service" "api" {
  name     = "notes-api"
  location = var.gcp_region

  template {
    containers {
      image = local.api_image

      env {
        name  = "DATABASE_URL"
        value = "postgresql://bad_user:bad_pass@127.0.0.1:5432/nonexistent"
      }
      env {
        name  = "AWS_ACCESS_KEY_ID"
        value = var.s3_key_id
      }
      env {
        name  = "AWS_SECRET_ACCESS_KEY"
        value = var.s3_key_secret
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
      # tant que cette probe ne répond pas 200. Si la DB est cassée → déploiement
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

resource "google_cloud_run_v2_service" "ui" {
  name     = "notes-ui"
  location = var.gcp_region

  template {
    containers {
      image = local.ui_image
      env {
        name  = "API_URL"
        value = google_cloud_run_v2_service.api.uri
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_service.api.name
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