#!/bin/bash
# =============================================================================
# COMPLETE DR PREREQUISITES SCRIPT
# =============================================================================
# This script sets up all prerequisites for the DR solution:
# - Enables required Google Cloud APIs
# - Creates a service account with necessary permissions

# Exit on error
set -e

# Get project ID from command line or use default
PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}
SERVICE_ACCOUNT_NAME=${2:-"dr-service-account"}

# Check if project ID is provided
if [ -z "$PROJECT_ID" ]; then
  echo "Error: Project ID is required."
  echo "Usage: $0 [project-id] [service-account-name]"
  exit 1
fi

echo "=== Setting up DR prerequisites for project: $PROJECT_ID ==="

# -----------------------------------------------------------------------------
# ENABLE APIS
# -----------------------------------------------------------------------------

echo "=== Enabling required Google Cloud APIs ==="
echo "This may take a few minutes..."

# List of required APIs
REQUIRED_APIS=(
  "compute.googleapis.com"           # Compute Engine API
  "sqladmin.googleapis.com"          # Cloud SQL Admin API
  "secretmanager.googleapis.com"     # Secret Manager API
  "monitoring.googleapis.com"        # Cloud Monitoring API
  "cloudscheduler.googleapis.com"    # Cloud Scheduler API
  "storage.googleapis.com"           # Cloud Storage API
  "iam.googleapis.com"               # Identity and Access Management API
  "logging.googleapis.com"           # Cloud Logging API
)

# Enable each API
for api in "${REQUIRED_APIS[@]}"; do
  echo "Enabling $api..."
  gcloud services enable $api --project=$PROJECT_ID
done

echo "All required APIs have been enabled."

# -----------------------------------------------------------------------------
# CREATE SERVICE ACCOUNT
# -----------------------------------------------------------------------------

echo "=== Creating service account ==="

# Service account email
SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# Check if service account already exists
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL --project=$PROJECT_ID &>/dev/null; then
  echo "Service account $SERVICE_ACCOUNT_EMAIL already exists."
else
  # Create service account
  echo "Creating service account $SERVICE_ACCOUNT_NAME..."
  gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
    --display-name="DR Service Account" \
    --project=$PROJECT_ID
  
  echo "Service account created: $SERVICE_ACCOUNT_EMAIL"
fi

# -----------------------------------------------------------------------------
# GRANT IAM ROLES
# -----------------------------------------------------------------------------

echo "=== Granting IAM roles ==="

# List of required roles
REQUIRED_ROLES=(
  "roles/compute.admin"                  # Compute Admin
  "roles/cloudsql.admin"                 # Cloud SQL Admin
  "roles/secretmanager.admin"            # Secret Manager Admin
  "roles/storage.admin"                  # Storage Admin
  "roles/monitoring.admin"               # Monitoring Admin
  "roles/cloudscheduler.admin"           # Cloud Scheduler Admin
  "roles/iam.serviceAccountUser"         # Service Account User
  "roles/resourcemanager.projectIamAdmin" # Project IAM Admin
)

# Grant each role
for role in "${REQUIRED_ROLES[@]}"; do
  echo "Granting $role to $SERVICE_ACCOUNT_EMAIL..."
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="$role"
done

echo "All required roles have been granted."

# -----------------------------------------------------------------------------
# COMPLETION
# -----------------------------------------------------------------------------

echo "=== Setup complete ==="
echo "Project ID: $PROJECT_ID"
echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
echo ""
echo "To use this service account with Terraform, you can create a key file:"
echo "gcloud iam service-accounts keys create key.json --iam-account=$SERVICE_ACCOUNT_EMAIL"
echo ""
echo "Then set the GOOGLE_APPLICATION_CREDENTIALS environment variable:"
echo "export GOOGLE_APPLICATION_CREDENTIALS=key.json"
echo ""
echo "Or update your terraform.tfvars file to use this service account."
