#!/bin/bash
# =============================================================================
# RECREATE SECONDARY DATABASE AS REPLICA
# =============================================================================
# This script deletes the existing secondary database and recreates it as a replica

# Set the project ID
PROJECT_ID=$(gcloud config get-value project)

echo "Current project: $PROJECT_ID"
echo "This script will DELETE the existing secondary database and recreate it as a replica."
echo "WARNING: All data in the secondary database will be lost."
read -p "Are you sure you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

echo "Deleting secondary database instance..."
gcloud sql instances delete app-db-instance-dr-secondary --project=$PROJECT_ID --quiet

echo "Creating new secondary database instance as a replica..."
gcloud sql instances create app-db-instance-dr-secondary \
  --master-instance-name=app-db-instance-dr \
  --region=us-east1 \
  --tier=db-n1-standard-1 \
  --availability-type=REGIONAL \
  --project=$PROJECT_ID

echo "Verifying replication status..."
gcloud sql instances describe app-db-instance-dr-secondary \
  --project=$PROJECT_ID \
  --format="table(name,region,settings.availabilityType,masterInstanceName)"

echo "Done."
