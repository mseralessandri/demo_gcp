# =============================================================================
# VARIABLES FOR DR ACTIVE-PASSIVE COMPLETE ZONAL MODULE
# =============================================================================

# -----------------------------------------------------------------------------
# PROJECT CONFIGURATION
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "primary_zone" {
  description = "Primary zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "standby_zone" {
  description = "Standby zone for zonal resources"
  type        = string
  default     = "us-central1-c"
}

# -----------------------------------------------------------------------------
# VM CONFIGURATION
# -----------------------------------------------------------------------------

variable "vm_machine_type" {
  description = "Machine type for VMs"
  type        = string
  default     = "e2-medium"
}

variable "vm_image" {
  description = "Image for VM boot disks"
  type        = string
  default     = "debian-cloud/debian-11"
}

variable "disk_size_gb" {
  description = "Size of the regional disk in GB"
  type        = number
  default     = 20
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 10
}

variable "setup_script_path" {
  description = "Path to the setup script"
  type        = string
  default     = "../setup.sh"
}

variable "go_version" {
  description = "Version of Go to install"
  type        = string
  default     = "1.24.1"
}

# -----------------------------------------------------------------------------
# DATABASE CONFIGURATION
# -----------------------------------------------------------------------------

variable "db_tier" {
  description = "Machine tier for Cloud SQL"
  type        = string
  default     = "db-g1-small"
}

variable "database_sql_path" {
  description = "Path to the database SQL file"
  type        = string
  default     = "../database.sql"
}

variable "db_root_password" {
  description = "Root password for the database instance"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "app_database"
}

variable "db_user" {
  description = "Database username"
  type        = string
  default     = "app_user"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "backup_start_time" {
  description = "Start time for database backups (24h format)"
  type        = string
  default     = "02:00"
}

variable "transaction_log_retention_days" {
  description = "Number of days to retain transaction logs"
  type        = number
  default     = 7
}

variable "retained_backups" {
  description = "Number of database backups to retain"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection for the database"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# MAINTENANCE CONFIGURATION
# -----------------------------------------------------------------------------

variable "maintenance_day" {
  description = "Day of week for maintenance window (1-7)"
  type        = number
  default     = 7  # Sunday
}

variable "maintenance_hour" {
  description = "Hour of day for maintenance window (0-23)"
  type        = number
  default     = 2  # 2 AM
}

# -----------------------------------------------------------------------------
# MONITORING CONFIGURATION
# -----------------------------------------------------------------------------

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = "admin@example.com"
}

variable "error_threshold" {
  description = "Number of errors that trigger an alert"
  type        = number
  default     = 5
}

variable "replication_lag_threshold_ms" {
  description = "Database replication lag threshold in milliseconds"
  type        = number
  default     = 60000  # 60 seconds
}
