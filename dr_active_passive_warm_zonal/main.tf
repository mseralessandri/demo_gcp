# DR infrastructure configuration

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

# Base module is not included to avoid creating duplicate resources
# The DR module should be used alongside the existing base infrastructure

# Use the DR module for disaster recovery infrastructure
module "dr" {
  source = "../modules/dr_active_passive_warm_zonal"
  
  # Project configuration
  project_id = var.project_id
  region     = var.region
  
  # Zone configuration
  primary_zone = var.primary_zone
  standby_zone = var.standby_zone
  
  # VM configuration
  vm_machine_type = var.vm_machine_type
  disk_size_gb    = var.disk_size_gb
  
  # Database configuration
  db_user          = var.db_user
  db_password      = var.db_password
  db_root_password = var.db_root_password
  db_tier          = var.db_tier
  
  # Application configuration
  setup_script_path = var.setup_script_path
  database_sql_path = var.database_sql_path
  go_version        = var.go_version
  
  # DR-specific configuration
  backup_start_time         = var.backup_start_time
  notification_email        = var.notification_email
  error_threshold           = var.error_threshold
  replication_lag_threshold_ms = var.replication_lag_threshold_ms
}
