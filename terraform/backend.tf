# L'état Terraform est stocké à distance pour être partagé entre la CI et les machines locales.
# Le bucket GCS doit être créé manuellement avant le premier `terraform init`.
# Note : le bloc backend n'accepte pas de variables Terraform — valeurs en dur obligatoires.
terraform {
  backend "gcs" {
    bucket = "notes-lgarcia-2847-tfstate"
    prefix = "notes-app"
  }
}