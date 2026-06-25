# Secrets applicatifs gérés par Secret Manager : Cloud Run lit la valeur au démarrage
# du conteneur via secret_key_ref, jamais en clair dans la config du service.

resource "google_secret_manager_secret" "database_url" {
  secret_id = "notes-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = var.pg_dsn
}

resource "google_secret_manager_secret" "aws_access_key_id" {
  secret_id = "notes-aws-access-key-id"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "aws_access_key_id" {
  secret      = google_secret_manager_secret.aws_access_key_id.id
  secret_data = var.s3_key_id
}

resource "google_secret_manager_secret" "aws_secret_access_key" {
  secret_id = "notes-aws-secret-access-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "aws_secret_access_key" {
  secret      = google_secret_manager_secret.aws_secret_access_key.id
  secret_data = var.s3_key_secret
}

# Service account dédié à l'exécution des Cloud Run (principe du moindre privilège :
# seul ce SA peut lire les secrets, pas le SA de compute par défaut).
resource "google_service_account" "cloud_run_runtime" {
  account_id   = "notes-run-runtime"
  display_name = "Cloud Run runtime - notes-app"
}

resource "google_secret_manager_secret_iam_member" "database_url_access" {
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "aws_access_key_id_access" {
  secret_id = google_secret_manager_secret.aws_access_key_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "aws_secret_access_key_access" {
  secret_id = google_secret_manager_secret.aws_secret_access_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}
