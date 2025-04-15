# =============================================================================
# DR ACTIVE-PASSIVE COMPLETE ZONAL IMPLEMENTATION
# =============================================================================
# This file implements the DR active-passive complete zonal module.

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

# Use the DR module for disaster recovery infrastructure
module "dr_complete" {
  source = "../modules/dr_active_passive_complete_zonal"
  
  # Project configuration
  project_id = var.project_id
  region     = var.region
  
  # Zone configuration
  primary_zone = var.primary_zone
  standby_zone = var.standby_zone
  
  # VM configuration
  vm_machine_type = var.vm_machine_type
  vm_image        = var.vm_image
  disk_size_gb    = var.disk_size_gb
  boot_disk_size_gb = var.boot_disk_size_gb
  
  # Database configuration
  db_tier          = var.db_tier
  database_sql_path = var.database_sql_path
  db_root_password = var.db_root_password
  db_name          = var.db_name
  db_user          = var.db_user
  db_password      = var.db_password
  
  # Backup configuration
  backup_start_time = var.backup_start_time
  transaction_log_retention_days = var.transaction_log_retention_days
  retained_backups = var.retained_backups
  
  # Maintenance configuration
  maintenance_day  = var.maintenance_day
  maintenance_hour = var.maintenance_hour
  
  # Monitoring configuration
  notification_email = var.notification_email
  error_threshold    = var.error_threshold
  replication_lag_threshold_ms = var.replication_lag_threshold_ms
  
  # Application configuration
  setup_script_path = var.setup_script_path
  go_version        = var.go_version
}
