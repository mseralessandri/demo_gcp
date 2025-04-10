# Base infrastructure configuration (without DR)

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Use the base module
module "base" {
  source = "../modules/base"
  
  # Project configuration
  project_id = var.project_id
  region     = var.region
  
  # VM configuration
  vm_machine_type  = var.vm_machine_type
  vm_image         = var.vm_image
  
  # Database configuration
  db_user          = var.db_user
  db_password      = var.db_password
  db_root_password = var.db_root_password
  db_tier          = var.db_tier
  
  # Application configuration
  setup_script_path = var.setup_script_path
  database_sql_path = var.database_sql_path
  go_version        = var.go_version
}
