#!/bin/bash
# =============================================================================
# SIMPLE DR PREREQUISITES SCRIPT - FIX API ERRORS
# =============================================================================
# This script enables the required Google Cloud APIs that were causing errors

# Exit on error
set -e

# Get project ID from command line or use default
PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}

# Check if project ID is provided
if [ -z "$PROJECT_ID" ]; then
  echo "Error: Project ID is required."
  echo "Usage: $0 [project-id]"
  exit 1
fi

echo "=== Enabling required Google Cloud APIs for project: $PROJECT_ID ==="
echo "This may take a few minutes..."

# List of APIs that were causing errors
REQUIRED_APIS=(
  "compute.googleapis.com"           # Compute Engine API
  "sqladmin.googleapis.com"          # Cloud SQL Admin API
  "secretmanager.googleapis.com"     # Secret Manager API
  "cloudscheduler.googleapis.com"    # Cloud Scheduler API
  "storage.googleapis.com"           # Cloud Storage API
  "monitoring.googleapis.com"        # Cloud Monitoring API
  "iam.googleapis.com"               # Identity and Access Management API
)

# Enable each API
for api in "${REQUIRED_APIS[@]}"; do
  echo "Enabling $api..."
  gcloud services enable $api --project=$PROJECT_ID
done

echo "=== All required APIs have been enabled ==="
echo "You can now try deploying the DR module again."
