# Pipeline CI/CD

Pipeline GitHub Actions : [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml).

## Déclencheurs

| Événement | `test` (lint + tests) | `build-push` | `deploy` |
|-----------|:---:|:---:|:---:|
| Pull request → `main` | ✅ | ❌ | ❌ |
| Push → `main`         | ✅ | ✅ | ✅ |

Sur une PR, seuls le linter et les tests tournent (gate de qualité, pas de déploiement).
Le build + déploiement n'ont lieu qu'après un merge/push sur `main`.

## Étapes

1. **test** — `ruff check` (linter) + `pytest` (tests unitaires) sur le backend Python 3.12.
2. **build-push** — build des images `backend` et `frontend` (matrix), taguées avec le **SHA du commit** + `latest`, poussées vers Google Artifact Registry (`europe-west1-docker.pkg.dev/cloud-ynov-494711/demo`).
3. **deploy** — `terraform apply` ciblé sur les services Cloud Run, en injectant `image_tag = <SHA>` → Cloud Run déploie une nouvelle révision avec l'image fraîchement poussée.

## Isolation & sécurité

- **Runners isolés** : `ubuntu-latest` GitHub-hosted = VM éphémère et jetable, recréée pour chaque job.
- **Least privilege** : `permissions: contents: read` par défaut ; seuls `build-push` et `deploy` ajoutent `id-token: write` (nécessaire à l'OIDC).
- **Secrets safe** : authentification GCP par **Workload Identity Federation** (keyless, OIDC) — aucune clé de service JSON long-terme stockée dans GitHub. Les secrets applicatifs (DB, AWS) sont des *GitHub Secrets* chiffrés, jamais loggés.
- **Pas de déploiement depuis un fork** : `build-push`/`deploy` sont conditionnés à `push` sur `main`, donc les PR externes ne peuvent pas accéder aux secrets ni déployer.
- **Concurrency** : un seul run actif par ref, les précédents sont annulés.

---

## Setup (une seule fois)

Variables utilisées ci-dessous — adapte si besoin :

```bash
export PROJECT_ID="cloud-ynov-494711"
export PROJECT_NUMBER="$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')"
export REGION="europe-west1"
export REPO_GH="<owner>/<repo>"          # ex: aymeric/ynov-cloud-run-demo
export SA_NAME="github-ci"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export POOL="github-pool"
export PROVIDER="github-provider"
export TFSTATE_BUCKET="${PROJECT_ID}-tfstate"
```

### 1. APIs requises

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  --project "$PROJECT_ID"
```

### 2. Dépôt Artifact Registry

```bash
gcloud artifacts repositories create demo \
  --repository-format=docker --location="$REGION" \
  --project "$PROJECT_ID"
```

### 3. Bucket GCS pour le tfstate (backend Terraform)

```bash
gcloud storage buckets create "gs://${TFSTATE_BUCKET}" \
  --project "$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
gcloud storage buckets update "gs://${TFSTATE_BUCKET}" --versioning
```

> Le nom du bucket est codé en dur dans [`terraform/backend.tf`](../terraform/backend.tf). S'il diffère, modifie ce fichier.

#### Migrer le state local existant vers GCS

Le state est aujourd'hui local. Une seule fois, depuis `terraform/` :

```bash
terraform init -migrate-state   # répond "yes" pour copier le state local vers GCS
```

### 4. Service Account pour la CI

```bash
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="GitHub Actions CI" --project "$PROJECT_ID"

# Rôles : push images, déployer Cloud Run, gérer l'IAM run, lire/écrire le tfstate
for ROLE in \
  roles/run.admin \
  roles/artifactregistry.writer \
  roles/iam.serviceAccountUser \
  roles/storage.admin ; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" --role="$ROLE"
done
```

> `roles/storage.admin` au niveau projet est large ; pour restreindre, ne le donner que sur le bucket tfstate.

### 5. Workload Identity Federation (keyless)

```bash
gcloud iam workload-identity-pools create "$POOL" \
  --location="global" --display-name="GitHub pool" --project "$PROJECT_ID"

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --location="global" --workload-identity-pool="$POOL" \
  --display-name="GitHub provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${REPO_GH}'" \
  --project "$PROJECT_ID"

# Autorise UNIQUEMENT ce dépôt à emprunter le service account
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${REPO_GH}" \
  --project "$PROJECT_ID"

# Valeur à mettre dans la variable GitHub WIF_PROVIDER :
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
echo "Service account : ${SA_EMAIL}"
```

### 6. Configurer GitHub (Settings → Secrets and variables → Actions)

**Variables** (onglet *Variables*, non chiffrées) :

| Nom | Valeur |
|-----|--------|
| `WIF_PROVIDER` | `projects/<NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `WIF_SERVICE_ACCOUNT` | `github-ci@cloud-ynov-494711.iam.gserviceaccount.com` |
| `AWS_DEFAULT_REGION` | `eu-west-3` |

**Secrets** (onglet *Secrets*, chiffrés) :

| Nom | Valeur |
|-----|--------|
| `TF_DATABASE_URL` | DSN PostgreSQL de prod |
| `TF_AWS_ACCESS_KEY_ID` | clé AWS |
| `TF_AWS_SECRET_ACCESS_KEY` | secret AWS |

C'est tout : pousser sur `main` déclenche tests → build/push → déploiement.

---

## Lancer les tests / le linter en local

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
ruff check .
pytest -q
```
