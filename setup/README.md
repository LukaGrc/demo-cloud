# Setup GCP

Script Docker qui configure tout le projet GCP en une commande — aucun outil à installer sur ta machine hormis Docker.

## Usage

```bash
cd setup

# 1. Build l'image (une seule fois)
docker build -t notes-gcp-setup .

# 2. Lance le setup
docker run -it \
  -e PROJECT_ID=ton-project-id-gcp \
  -e GITHUB_REPO=ton-org/ton-repo \
  notes-gcp-setup
```

## Ce que ça fait

1. Authentification GCP (via URL dans le navigateur)
2. Création du projet GCP
3. Activation des APIs nécessaires
4. Bucket GCS pour le state Terraform
5. Dépôt Artifact Registry `notes-app`
6. Service account `github-actions` avec les bons rôles
7. Workload Identity Federation (auth keyless GitHub → GCP)

À la fin, le script affiche les valeurs `WIF_PROVIDER` et `WIF_SERVICE_ACCOUNT` à copier dans GitHub.

## Pré-requis

- Docker installé
- Un compte Google Cloud (la facturation doit être activée sur le projet — le script fait une pause pour te laisser le faire)
- Un repo GitHub existant

## Idempotent

Le script peut être relancé sans risque — il vérifie si chaque ressource existe déjà avant de la créer.
