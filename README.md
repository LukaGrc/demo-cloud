# markdown-notes

[![Pipeline](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci-cd.yml)

Application de gestion de notes Markdown déployée sur Google Cloud Run. Le frontend (Nginx) appelle un backend Flask qui stocke les fichiers sur AWS S3 et journalise chaque envoi dans une base PostgreSQL.

---

## Architecture

```
Navigateur → Frontend (Nginx · Cloud Run)
                  ↓
            Backend (Flask · Cloud Run)
                  ↓               ↓
           AWS S3 bucket     PostgreSQL
```

- **Frontend** : page HTML statique servie par Nginx. L'URL du backend est configurée dans `index.html` (`API_URL`).
- **Backend** : Flask + Gunicorn. Gère le stockage/lecture/export de fichiers `.md` sur S3, et enregistre chaque upload dans la table `file_records`.
- **Bucket S3** : configuré via la variable d'environnement `S3_BUCKET_NAME` (région `eu-west-1` par défaut).
- **PostgreSQL** : table `file_records (id, name, size, stored_at)`.

---

## Endpoints backend

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/health` | Healthcheck |
| GET | `/objects` | Liste les fichiers dans S3 |
| GET | `/object/<name>` | Contenu d'un fichier |
| PUT | `/object/<name>` | Mise à jour d'un fichier |
| GET | `/export/<name>` | Téléchargement d'un fichier |
| POST | `/store` | Upload + enregistrement en base |
| GET | `/history` | Liste les uploads enregistrés en base |

---

## Variables d'environnement (backend)

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | DSN PostgreSQL |
| `AWS_ACCESS_KEY_ID` | Credentials AWS |
| `AWS_SECRET_ACCESS_KEY` | Credentials AWS |
| `AWS_DEFAULT_REGION` | Région AWS (défaut : `eu-west-1`) |
| `S3_BUCKET_NAME` | Nom du bucket S3 |

En local : fichier `backend/.env`. Sur Cloud Run : variables injectées par Terraform.

---

## Développement local

```bash
# Backend
cd backend
pip install -r requirements.txt
python main.py
# → http://localhost:8080

# Frontend : ouvrir frontend/index.html dans le navigateur
# Vérifier que API_URL pointe sur http://localhost:8080
```

PostgreSQL en local via Minikube :

```bash
minikube start

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install pg bitnami/postgresql \
  --set auth.postgresPassword=devpassword \
  --set auth.database=appdb

kubectl port-forward svc/pg-postgresql 5432:5432
```

---

## CI/CD

Pipeline GitHub Actions : [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml).

| Événement | `quality` (lint + tests) | `containerize` | `release` |
|-----------|:---:|:---:|:---:|
| Pull request → `main` | ✅ | ❌ | ❌ |
| Push / merge → `main` | ✅ | ✅ | ✅ |

À chaque merge sur `main` : lint + tests → build des images Docker (taguées **SHA du commit** + `latest`) poussées vers Artifact Registry → `terraform apply` qui déploie une nouvelle révision Cloud Run.

- **Auth GCP keyless** via Workload Identity Federation (OIDC) — aucune clé JSON stockée.
- **Least privilege** : `permissions: contents: read` par défaut, `id-token: write` uniquement sur les jobs build/deploy.
- **State Terraform** stocké dans GCS (`gs://YOUR_GCP_PROJECT_ID-tfstate`).

### Secrets et variables GitHub requis

| Type | Nom | Description |
|------|-----|-------------|
| Secret | `TF_DATABASE_URL` | DSN PostgreSQL |
| Secret | `TF_AWS_ACCESS_KEY_ID` | Credentials AWS |
| Secret | `TF_AWS_SECRET_ACCESS_KEY` | Credentials AWS |
| Variable | `WIF_PROVIDER` | Ressource Workload Identity Federation |
| Variable | `WIF_SERVICE_ACCOUNT` | Email du service account GCP |
| Variable | `AWS_DEFAULT_REGION` | Région AWS (ex: `eu-west-1`) |
| Variable | `S3_BUCKET_NAME` | Nom du bucket S3 |

---

## Infrastructure Terraform

```
terraform/
├── providers.tf    # Providers GCP + Kubernetes
├── backend.tf      # State distant dans GCS
├── variables.tf    # Toutes les variables du projet
├── cloudrun.tf     # Services Cloud Run (notes-api + notes-ui)
└── kubernetes.tf   # PostgreSQL sur Minikube (dev local)
```

Avant le premier `terraform init`, créer le bucket GCS manuellement :

```bash
gcloud storage buckets create gs://YOUR_GCP_PROJECT_ID-tfstate --location=europe-west9
```

Puis mettre à jour `terraform/backend.tf` avec le vrai nom du bucket.
