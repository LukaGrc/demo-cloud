#!/bin/bash
set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
B='\033[1;34m'
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
N='\033[0m'

header() { echo -e "\n${B}══ $1 ══${N}"; }
ok()     { echo -e "  ${G}✓${N} $1"; }
info()   { echo -e "  ${Y}→${N} $1"; }
skip()   { echo -e "  ${Y}⏭${N}  Étape $1 ignorée (START_FROM=${START_FROM})"; }
err()    { echo -e "\n${R}✗ $1${N}\n"; exit 1; }

# ── Variables ─────────────────────────────────────────────────────────────────
# Obligatoires :
#   -e PROJECT_ID=notes-lgarcia-1234   (identifiant GCP, globalement unique)
#   -e GITHUB_REPO=org/repo
# Optionnel :
#   -e START_FROM=7                    (reprendre à partir de l'étape N)

if [ -z "${PROJECT_ID:-}" ]; then
  SUFFIX=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
  err "PROJECT_ID non défini. Exemple : -e PROJECT_ID=notes-lgarcia-${SUFFIX}"
fi

[ -z "${GITHUB_REPO:-}" ] && err "GITHUB_REPO non défini. Ex: -e GITHUB_REPO=monorg/monrepo"

if ! echo "$PROJECT_ID" | grep -qE '^[a-z][a-z0-9-]{5,29}$'; then
  err "PROJECT_ID invalide (6-30 chars, minuscules/chiffres/tirets, commence par une lettre)"
fi

START_FROM=${START_FROM:-1}
REGION="europe-west9"
SA_NAME="github-actions"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"
BUCKET="${PROJECT_ID}-tfstate"
GITHUB_ORG="${GITHUB_REPO%%/*}"   # extrait "org" de "org/repo"

# step N → retourne 0 (run) si START_FROM <= N, 1 (skip) sinon
step() { [ "$START_FROM" -le "$1" ]; }

# ── Auth (toujours exécutée) ──────────────────────────────────────────────────
header "Auth · Authentification GCP"
info "Une URL va s'afficher — ouvre-la dans ton navigateur et colle le code ici."
gcloud auth login --no-launch-browser --quiet
gcloud config set project "$PROJECT_ID" --quiet
ok "Authentifié — projet actif : $PROJECT_ID"

# ── 2. Projet ─────────────────────────────────────────────────────────────────
if step 2; then
  header "2/7 · Projet GCP"
  if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    ok "Projet $PROJECT_ID déjà existant"
  else
    if ! gcloud projects create "$PROJECT_ID" --name="Markdown Notes" --quiet 2>&1; then
      SUFFIX=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
      err "L'ID '$PROJECT_ID' est déjà pris. Réessaie avec : -e PROJECT_ID=${PROJECT_ID}-${SUFFIX}"
    fi
    ok "Projet $PROJECT_ID créé"
  fi

  info "Active la facturation sur ce projet dans la console GCP si ce n'est pas encore fait :"
  info "console.cloud.google.com/billing/projects"
  echo ""
  read -rp "  Appuie sur Entrée quand c'est fait..."
else
  skip 2
fi

# ── 3. APIs ───────────────────────────────────────────────────────────────────
if step 3; then
  header "3/7 · Activation des APIs"
  gcloud services enable \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    storage.googleapis.com \
    --quiet
  ok "APIs activées"
else
  skip 3
fi

# ── 4. Bucket GCS (tfstate) ───────────────────────────────────────────────────
if step 4; then
  header "4/7 · Bucket GCS pour le state Terraform"
  if gcloud storage buckets describe "gs://${BUCKET}" &>/dev/null; then
    ok "Bucket gs://$BUCKET déjà existant"
  else
    gcloud storage buckets create "gs://${BUCKET}" \
      --location="$REGION" \
      --uniform-bucket-level-access \
      --quiet
    ok "Bucket gs://$BUCKET créé"
  fi
else
  skip 4
fi

# ── 5. Artifact Registry ──────────────────────────────────────────────────────
if step 5; then
  header "5/7 · Artifact Registry"
  if gcloud artifacts repositories describe notes-app --location="$REGION" &>/dev/null; then
    ok "Dépôt notes-app déjà existant"
  else
    gcloud artifacts repositories create notes-app \
      --repository-format=docker \
      --location="$REGION" \
      --quiet
    ok "Dépôt notes-app créé"
  fi
else
  skip 5
fi

# ── 6. Service account + rôles ────────────────────────────────────────────────
if step 6; then
  header "6/7 · Service account"
  if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
    ok "Service account $SA_EMAIL déjà existant"
  else
    gcloud iam service-accounts create "$SA_NAME" \
      --display-name="GitHub Actions CI/CD" \
      --quiet
    ok "Service account créé"
  fi

  info "Attribution des rôles..."
  for ROLE in \
    roles/run.admin \
    roles/storage.admin \
    roles/artifactregistry.writer \
    roles/iam.serviceAccountUser; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="$ROLE" \
      --quiet &>/dev/null
    ok "$ROLE"
  done
else
  skip 6
fi

# ── 7. Workload Identity Federation ───────────────────────────────────────────
if step 7; then
  header "7/7 · Workload Identity Federation"

  if gcloud iam workload-identity-pools describe "$POOL_NAME" --location=global &>/dev/null; then
    ok "Pool $POOL_NAME déjà existant"
  else
    gcloud iam workload-identity-pools create "$POOL_NAME" \
      --location=global \
      --quiet
    ok "Pool $POOL_NAME créé"
  fi

  if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
      --location=global \
      --workload-identity-pool="$POOL_NAME" &>/dev/null; then
    ok "Provider $PROVIDER_NAME déjà existant"
  else
    # attribute-condition obligatoire depuis 2024 — restreint au owner du repo GitHub
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
      --location=global \
      --workload-identity-pool="$POOL_NAME" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
      --attribute-condition="attribute.repository_owner == '${GITHUB_ORG}'" \
      --quiet
    ok "Provider $PROVIDER_NAME créé"
  fi

  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --role=roles/iam.workloadIdentityUser \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GITHUB_REPO}" \
    --quiet &>/dev/null
  ok "SA lié au pool pour $GITHUB_REPO"
else
  skip 7
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
fi

# ── Résultat ──────────────────────────────────────────────────────────────────
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"

echo ""
echo -e "${G}══════════════════════════════════════════════════════════════${N}"
echo -e "${G}  ✓  Configuration GCP terminée${N}"
echo -e "${G}══════════════════════════════════════════════════════════════${N}"
echo ""
echo "  Copie ces valeurs dans GitHub → Settings → Secrets and variables → Actions"
echo ""
echo -e "  ${Y}Variables :${N}"
echo "    WIF_PROVIDER         = $WIF_PROVIDER"
echo "    WIF_SERVICE_ACCOUNT  = $SA_EMAIL"
echo "    AWS_DEFAULT_REGION   = eu-west-1"
echo "    S3_BUCKET_NAME       = <nom de ton bucket S3>"
echo ""
echo -e "  ${Y}Secrets :${N}"
echo "    TF_DATABASE_URL          = <DSN PostgreSQL depuis Neon>"
echo "    TF_AWS_ACCESS_KEY_ID     = <depuis AWS IAM>"
echo "    TF_AWS_SECRET_ACCESS_KEY = <depuis AWS IAM>"
echo ""
echo -e "  ${Y}Fichiers à mettre à jour avec PROJECT_ID=${PROJECT_ID} :${N}"
echo "    terraform/backend.tf"
echo "    terraform/variables.tf"
echo "    .github/workflows/ci-cd.yml"
echo ""
