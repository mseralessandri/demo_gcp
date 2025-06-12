#!/bin/bash
# =============================================================================
# TERRAFORM STATE FIXER SCRIPT
# =============================================================================
# This script helps fix common Terraform state issues by importing existing
# resources into the Terraform state.

set -e

# Get the project ID from terraform.tfvars
PROJECT_ID=$(grep "project_id" terraform/terraform.tfvars | cut -d'"' -f2)
if [ -z "$PROJECT_ID" ]; then
  echo "Error: Could not determine project ID from terraform.tfvars"
  exit 1
fi

echo "Using project ID: $PROJECT_ID"

# Function to import a resource if it's not already in the state
import_if_not_exists() {
  local resource_type=$1
  local resource_name=$2
  local resource_id=$3
  
  echo "Checking if $resource_type.$resource_name is in Terraform state..."
  if ! terraform -chdir=terraform state list | grep -q "$resource_type.$resource_name"; then
    echo "Importing $resource_type.$resource_name..."
    terraform -chdir=terraform import "$resource_type.$resource_name" "$resource_id"
    echo "Import successful!"
  else
    echo "$resource_type.$resource_name is already in Terraform state."
  fi
}

# Main menu
show_menu() {
  echo "=== Terraform State Fixer ==="
  echo "1) Import service account"
  echo "2) Import all resources"
  echo "3) Exit"
  echo "Enter your choice: "
  read -r choice
  
  case $choice in
    1)
      import_service_account
      ;;
    2)
      import_all_resources
      ;;
    3)
      exit 0
      ;;
    *)
      echo "Invalid choice. Please try again."
      show_menu
      ;;
  esac
}

# Import service account
import_service_account() {
  echo "Importing service account..."
  import_if_not_exists "google_service_account" "dr_service_account" \
    "projects/$PROJECT_ID/serviceAccounts/dr-service-account@$PROJECT_ID.iam.gserviceaccount.com"
  
  echo "Done!"
  show_menu
}

# Import all resources
import_all_resources() {
  echo "Importing all resources..."
  
  # Service account
  import_if_not_exists "google_service_account" "dr_service_account" \
    "projects/$PROJECT_ID/serviceAccounts/dr-service-account@$PROJECT_ID.iam.gserviceaccount.com"
  
  # Add more resources here as needed
  
  echo "Done!"
  show_menu
}

# Start the script
echo "This script will help fix Terraform state issues by importing existing resources."
echo "Make sure you have the gcloud CLI configured and Terraform initialized."
echo ""
show_menu
