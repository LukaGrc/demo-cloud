# APIs GCP requises par les ressources de ce module. run/artifactregistry/iam sont
# déjà activées par setup/setup.sh (bootstrap) ; secretmanager et monitoring sont
# nouvelles avec la gestion des secrets et l'observabilité, donc gérées ici.
resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}
