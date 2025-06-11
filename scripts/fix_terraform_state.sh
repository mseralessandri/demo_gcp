#!/bin/bash

# =============================================================================
# FIX TERRAFORM STATE SCRIPT
# =============================================================================
# This script removes conflicting resources from Terraform state and re-imports them

set -e

PROJECT_ID="microcloud-448817"

echo "Fixing Terraform state for project: $PROJECT_ID"

# Remove resources from state first
echo "Removing resources from Terraform state..."

terraform state rm module.dr_complete.google_compute_disk.primary_boot_disk 2>/dev/null || echo "Primary boot disk not in state"
terraform state rm module.dr_complete.google_compute_disk.standby_boot_disk 2>/dev/null || echo "Standby boot disk not in state"
terraform state rm module.dr_complete.google_compute_region_disk.regional_disk 2>/dev/null || echo "Regional disk not in state"
terraform state rm module.dr_complete.google_compute_instance.primary_vm 2>/dev/null || echo "Primary VM not in state"
terraform state rm module.dr_complete.google_compute_instance.standby_vm 2>/dev/null || echo "Standby VM not in state"
terraform state rm module.dr_complete.google_sql_database_instance.db_instance 2>/dev/null || echo "Database instance not in state"

echo "Re-importing existing resources..."

# Check if primary boot disk exists
if gcloud compute disks describe app-primary-boot-disk --zone=us-central1-a --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Importing primary boot disk..."
    terraform import module.dr_complete.google_compute_disk.primary_boot_disk projects/$PROJECT_ID/zones/us-central1-a/disks/app-primary-boot-disk
else
    echo "Primary boot disk does not exist, will be created."
fi

# Check if standby boot disk exists
if gcloud compute disks describe app-standby-boot-disk --zone=us-central1-c --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Importing standby boot disk..."
    terraform import module.dr_complete.google_compute_disk.standby_boot_disk projects/$PROJECT_ID/zones/us-central1-c/disks/app-standby-boot-disk
else
    echo "Standby boot disk does not exist, will be created."
fi

# Check if regional disk exists
if gcloud compute disks describe app-regional-disk --region=us-central1 --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Importing regional disk..."
    terraform import module.dr_complete.google_compute_region_disk.regional_disk projects/$PROJECT_ID/regions/us-central1/disks/app-regional-disk
else
    echo "Regional disk does not exist, will be created."
fi

# Check if VMs exist
if gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Importing primary VM..."
    terraform import module.dr_complete.google_compute_instance.primary_vm projects/$PROJECT_ID/zones/us-central1-a/instances/app-web-server-dr-primary
else
    echo "Primary VM does not exist, will be created."
fi

if gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Importing standby VM..."
    terraform import module.dr_complete.google_compute_instance.standby_vm projects/$PROJECT_ID/zones/us-central1-c/instances/app-web-server-dr-standby
else
    echo "Standby VM does not exist, will be created."
fi

# Check if database instance exists
if gcloud sql instances describe app-db-instance-dr --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "Importing database instance..."
    terraform import module.dr_complete.google_sql_database_instance.db_instance projects/$PROJECT_ID/instances/app-db-instance-dr
else
    echo "Database instance does not exist, will be created."
fi

echo "State fix completed. You can now run 'terraform plan' to see what changes are needed."
