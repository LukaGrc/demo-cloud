# markdown-notes

[![Pipeline](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci-cd.yml)

Application de gestion de notes Markdown déployée sur Google Cloud Run, découpée en
3 conteneurs applicatifs indépendants (1 frontend + 2 microservices backend) qui
communiquent entre eux.

---

## Architecture

```
Navigateur → Frontend (Nginx · Cloud Run)
                  ↓
          files-service (Flask · Cloud Run) ──HTTP──→ history-service (Flask · Cloud Run)
                  ↓                                          ↓
            AWS S3 bucket                                PostgreSQL
```

- **Frontend** (`frontend/`) : page HTML statique servie par Nginx. Seul service exposé
  au navigateur ; l'URL de `files-service` est injectée au démarrage du conteneur
  (`API_URL`).
- **files-service** (`files-service/`) : microservice « Core ». Gère le
  stockage/lecture/export de fichiers `.md` sur S3. À chaque upload (`/store`), il
  appelle `history-service` en HTTP pour journaliser l'événement, et proxy `/history`
  vers `history-service` pour la lecture.
- **history-service** (`history-service/`) : microservice « Auth/Data ». Seul service à
  parler à PostgreSQL ; expose `/records` (écriture/lecture) consommé uniquement par
  `files-service`.
- **Bucket S3** : configuré via `S3_BUCKET_NAME` (région `eu-west-1` par défaut).
- **PostgreSQL** : table `file_records (id, name, size, stored_at)`, possédée par
  `history-service`.

Les deux microservices backend sont déployés, scalés et observés indépendamment l'un
de l'autre.

---

## Endpoints

### files-service (exposé au frontend via `API_URL`)

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/health` | Healthcheck |
| GET | `/healthz/ready` | Readiness (S3 accessible) |
| GET | `/objects` | Liste les fichiers dans S3 |
| GET | `/object/<name>` | Contenu d'un fichier |
| PUT | `/object/<name>` | Mise à jour d'un fichier |
| GET | `/export/<name>` | Téléchargement d'un fichier |
| POST | `/store` | Upload S3 + appel `history-service` pour journaliser |
| GET | `/history` | Proxy vers `history-service` |

### history-service (interne, appelé par files-service)

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/health` | Healthcheck |
| GET | `/healthz/ready` | Readiness (PostgreSQL accessible) |
| POST | `/records` | Enregistre un upload `{name, size}` |
| GET | `/records` | Liste les enregistrements |

---

## Variables d'environnement

### files-service

| Variable | Description |
|----------|--------------|
| `HISTORY_SERVICE_URL` | URL du `history-service` (injectée par Terraform via `google_cloud_run_v2_service.history_api.uri`) |
| `AWS_ACCESS_KEY_ID` | Credentials AWS (Secret Manager en prod) |
| `AWS_SECRET_ACCESS_KEY` | Credentials AWS (Secret Manager en prod) |
| `AWS_DEFAULT_REGION` | Région AWS (défaut : `eu-west-1`) |
| `S3_BUCKET_NAME` | Nom du bucket S3 |

### history-service

| Variable | Description |
|----------|--------------|
| `DATABASE_URL` | DSN PostgreSQL (Secret Manager en prod) |

En local : fichier `.env` dans chaque dossier de service. Sur Cloud Run : variables et
secrets injectés par Terraform (`terraform/cloudrun.tf`, `terraform/secrets.tf`).

---

## Développement local

```bash
# history-service
cd history-service
pip install -r requirements.txt
python main.py
# → http://localhost:8080

# files-service (terminal séparé)
cd files-service
HISTORY_SERVICE_URL=http://localhost:8080 python main.py
# → http://localhost:8081 (adapter le port si besoin)

# Frontend : ouvrir frontend/index.html dans le navigateur
# Vérifier que API_URL pointe sur l'URL de files-service
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

| Événement | `quality` (lint + tests, par service) | `containerize` | `release` |
|-----------|:---:|:---:|:---:|
| Pull request → `main` | ✅ | ❌ | ❌ |
| Push / merge → `main` | ✅ | ✅ | ✅ |

À chaque merge sur `main` : lint + tests de `files-service` et `history-service` →
build des 3 images Docker (`files-service`, `history-service`, `frontend`, taguées
**SHA du commit** + `latest`) poussées vers Artifact Registry → `terraform apply` qui
déploie une nouvelle révision pour chacun des 3 services Cloud Run.

- **Auth GCP keyless** via Workload Identity Federation (OIDC) — aucune clé JSON stockée.
- **Least privilege** : `permissions: contents: read` par défaut, `id-token: write`
  uniquement sur les jobs build/deploy.
- **State Terraform** stocké dans GCS (`gs://YOUR_GCP_PROJECT_ID-tfstate`).

### Secrets et variables GitHub requis

| Type | Nom | Description |
|------|-----|--------------|
| Secret | `TF_DATABASE_URL` | DSN PostgreSQL |
| Secret | `TF_AWS_ACCESS_KEY_ID` | Credentials AWS |
| Secret | `TF_AWS_SECRET_ACCESS_KEY` | Credentials AWS |
| Variable | `WIF_PROVIDER` | Ressource Workload Identity Federation |
| Variable | `WIF_SERVICE_ACCOUNT` | Email du service account GCP |
| Variable | `AWS_DEFAULT_REGION` | Région AWS (ex: `eu-west-1`) |
| Variable | `S3_BUCKET_NAME` | Nom du bucket S3 |
| Variable | `ALERT_NOTIFICATION_EMAIL` | Email destinataire des alertes Cloud Monitoring |

---

## Infrastructure Terraform

```
terraform/
├── providers.tf    # Providers GCP + Kubernetes
├── backend.tf      # State distant dans GCS
├── variables.tf     # Toutes les variables du projet
├── apis.tf          # Activation des APIs Secret Manager / Monitoring
├── registry.tf       # Dépôt Artifact Registry (notes-app)
├── secrets.tf         # Secret Manager (DB + AWS) + SA d'exécution Cloud Run
├── cloudrun.tf         # Services Cloud Run (notes-files-api, notes-history-api, notes-ui)
├── monitoring.tf        # Uptime checks + alertes par microservice
└── kubernetes.tf         # PostgreSQL sur Minikube (dev local uniquement)
```

L'intégralité des composants cloud (registre, secrets, IAM, Cloud Run, monitoring)
est provisionnée par Terraform — seul le bootstrap initial (compte GCP, premier
bucket de state, Workload Identity Federation) reste en dehors, dans `setup/setup.sh`,
car il s'agit d'un problème d'œuf et de poule (il faut un backend pour stocker le
state avant de pouvoir l'utiliser).

Avant le premier `terraform init`, créer le bucket GCS manuellement :

```bash
gcloud storage buckets create gs://YOUR_GCP_PROJECT_ID-tfstate --location=europe-west9
```

Puis mettre à jour `terraform/backend.tf` avec le vrai nom du bucket.

### Scaling

Chaque service Cloud Run déclare un bloc `scaling { min_instance_count, max_instance_count }`
(variables `min_instance_count` / `max_instance_count`, défauts 0/3). Cloud Run gère un
**scaling horizontal** : il démarre ou arrête des instances du même conteneur (taille
CPU/mémoire fixe) selon le nombre de requêtes concurrentes reçues par révision — il n'y
a pas de scaling vertical (pas de changement de CPU/RAM à chaud). Avec `min_instance_count
= 0`, le service peut scale-to-zero en l'absence de trafic.

### Monitoring & observabilité

`terraform/monitoring.tf` crée, pour chacun des 3 services :
- une **uptime check** HTTPS sur `/health` (ou `/` pour le frontend), exécutée par
  l'infrastructure Google indépendamment du conteneur ;
- une **alerte** déclenchée si la sonde échoue, envoyée par email
  (`google_monitoring_notification_channel`).

Les logs (stdout des conteneurs) et métriques de requêtes (latence, taux d'erreur,
instances actives) sont collectés automatiquement par Cloud Logging / Cloud Monitoring
pour chaque service Cloud Run, sans configuration additionnelle.
