#!/bin/bash
# One-time setup: GCS state bucket + Workload Identity Federation for GitHub Actions.
# Run locally after authenticating with: gcloud auth login
#
# Usage: ./scripts/bootstrap-ci.sh <project_id> <github_owner/repo>
#
# Example: ./scripts/bootstrap-ci.sh project-758068e8-e931-45df-ae8 strawgate/coder-infra
set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <project_id> <github_owner/repo>}"
GITHUB_REPO="${2:?Usage: $0 <project_id> <github_owner/repo>}"
REGION="us-central1"
BUCKET_NAME="${PROJECT_ID}-tfstate"
POOL_NAME="github-actions"
PROVIDER_NAME="github"
SA_NAME="github-actions-terraform"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=== Bootstrap CI for ${PROJECT_ID} ==="
echo "  GitHub repo:  ${GITHUB_REPO}"
echo "  State bucket: gs://${BUCKET_NAME}"
echo ""

# --- Enable required APIs ---
echo "Enabling APIs..."
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  sts.googleapis.com \
  storage.googleapis.com \
  --project="${PROJECT_ID}"

# --- Create GCS bucket for Terraform state ---
if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
  echo "State bucket gs://${BUCKET_NAME} already exists"
else
  echo "Creating state bucket gs://${BUCKET_NAME}..."
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" -b on "gs://${BUCKET_NAME}"
  gsutil versioning set on "gs://${BUCKET_NAME}"
fi

# --- Create service account for GitHub Actions ---
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "Service account ${SA_EMAIL} already exists"
else
  echo "Creating service account ${SA_NAME}..."
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="GitHub Actions Terraform" \
    --project="${PROJECT_ID}"
fi

# Grant roles to the service account
echo "Granting IAM roles (waiting for SA propagation)..."
sleep 5
for ROLE in roles/compute.admin roles/iam.serviceAccountUser roles/iam.serviceAccountAdmin \
            roles/resourcemanager.projectIamAdmin roles/storage.admin roles/iap.admin \
            roles/serviceusage.serviceUsageAdmin roles/compute.networkAdmin; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --quiet
done

# --- Workload Identity Federation ---
# Create the pool
if gcloud iam workload-identity-pools describe "${POOL_NAME}" \
  --location="global" --project="${PROJECT_ID}" &>/dev/null 2>&1; then
  echo "Workload identity pool ${POOL_NAME} already exists"
else
  echo "Creating workload identity pool..."
  gcloud iam workload-identity-pools create "${POOL_NAME}" \
    --location="global" \
    --display-name="GitHub Actions" \
    --project="${PROJECT_ID}"
fi

# Create the provider (maps GitHub OIDC tokens)
if gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
  --workload-identity-pool="${POOL_NAME}" \
  --location="global" --project="${PROJECT_ID}" &>/dev/null 2>&1; then
  echo "Workload identity provider ${PROVIDER_NAME} already exists"
else
  echo "Creating workload identity provider..."
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --display-name="GitHub" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository==\"${GITHUB_REPO}\"" \
    --project="${PROJECT_ID}"
fi

# Allow the GitHub repo to impersonate the service account
POOL_ID=$(gcloud iam workload-identity-pools describe "${POOL_NAME}" \
  --location="global" --project="${PROJECT_ID}" --format="value(name)")

echo "Binding service account to workload identity pool..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GITHUB_REPO}" \
  --project="${PROJECT_ID}" \
  --quiet

# --- Print outputs for GitHub Actions ---
WIF_PROVIDER=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
  --workload-identity-pool="${POOL_NAME}" \
  --location="global" --project="${PROJECT_ID}" --format="value(name)")

echo ""
echo "=== Setup complete ==="
echo ""
echo "Add these as GitHub repository secrets:"
echo "  GCP_PROJECT_ID:        ${PROJECT_ID}"
echo "  GCP_WIF_PROVIDER:      ${WIF_PROVIDER}"
echo "  GCP_SERVICE_ACCOUNT:   ${SA_EMAIL}"
echo "  TF_STATE_BUCKET:       ${BUCKET_NAME}"
echo ""
echo "Next steps:"
echo "  1. Add the secrets above to https://github.com/${GITHUB_REPO}/settings/secrets/actions"
echo "  2. Migrate local state to GCS:"
echo "     cd control-plane"
echo "     terraform init -migrate-state -backend-config=\"bucket=${BUCKET_NAME}\""
echo "  3. Push the workflows to trigger CI"
