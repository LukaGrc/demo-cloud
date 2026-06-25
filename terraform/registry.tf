resource "google_artifact_registry_repository" "notes_app" {
  location      = var.gcp_region
  repository_id = "notes-app"
  format        = "DOCKER"
  description   = "Images Docker des microservices notes-app (files-service, history-service, frontend)"
}
