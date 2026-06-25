variable "pg_dsn" {
  description = "Chaîne de connexion PostgreSQL"
  type        = string
  sensitive   = true
}

variable "s3_key_id" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "s3_key_secret" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "s3_region" {
  description = "Région AWS du bucket S3"
  type        = string
  default     = "eu-west-1"
}

variable "s3_bucket_name" {
  description = "Nom du bucket S3 utilisé pour le stockage des fichiers"
  type        = string
}

variable "gcp_project_id" {
  description = "Identifiant du projet GCP"
  type        = string
  default     = "notes-lgarcia-2847"
}

variable "gcp_region" {
  description = "Région GCP pour les services Cloud Run"
  type        = string
  default     = "europe-west9"
}

variable "app_version" {
  description = "Tag de l'image Docker à déployer. Positionné par la CI (SHA du commit)."
  type        = string
  default     = "latest"
}

variable "min_instance_count" {
  description = "Nombre minimal d'instances par service Cloud Run (0 = scale-to-zero)."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  description = "Nombre maximal d'instances par service Cloud Run (plafond du scaling horizontal)."
  type        = number
  default     = 3
}

variable "alert_notification_email" {
  description = "Adresse e-mail recevant les alertes Cloud Monitoring."
  type        = string
}