# =============================================================================
# VARIABLES FOR DR ACTIVE-PASSIVE COMPLETE ZONAL IMPLEMENTATION
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
}

variable "primary_zone" {
  description = "Primary zone for zonal resources"
  type        = string
}

variable "standby_zone" {
  description = "Standby zone for zonal resources"
  type        = string
}

# -----------------------------------------------------------------------------
# VM CONFIGURATION
# -----------------------------------------------------------------------------

variable "vm_machine_type" {
  description = "Machine type for VMs"
  type        = string
}

variable "vm_image" {
  description = "Image for VM boot disks"
  type        = string
}

variable "disk_size_gb" {
  description = "Size of the regional disk in GB"
  type        = number
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB"
  type        = number
}

variable "setup_script_path" {
  description = "Path to the setup script for initial deployment"
  type        = string
}

variable "setup_failover_script_path" {
  description = "Path to the minimal failover/failback script"
  type        = string
}

variable "go_version" {
  description = "Version of Go to install"
  type        = string
}

# -----------------------------------------------------------------------------
# DATABASE CONFIGURATION
# -----------------------------------------------------------------------------

variable "db_tier" {
  description = "Machine tier for Cloud SQL"
  type        = string
}

variable "database_sql_path" {
  description = "Path to the database SQL file"
  type        = string
}

variable "db_root_password" {
  description = "Root password for the database instance"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_user" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "backup_start_time" {
  description = "Start time for database backups (24h format)"
  type        = string
}

variable "transaction_log_retention_days" {
  description = "Number of days to retain transaction logs"
  type        = number
}

variable "retained_backups" {
  description = "Number of database backups to retain"
  type        = number
}

variable "deletion_protection" {
  description = "Enable deletion protection for the database"
  type        = bool
}

# -----------------------------------------------------------------------------
# MAINTENANCE CONFIGURATION
# -----------------------------------------------------------------------------

variable "maintenance_day" {
  description = "Day of week for maintenance window (1-7)"
  type        = number
}

variable "maintenance_hour" {
  description = "Hour of day for maintenance window (0-23)"
  type        = number
}

# -----------------------------------------------------------------------------
# MONITORING CONFIGURATION
# -----------------------------------------------------------------------------

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
}

variable "error_threshold" {
  description = "Number of errors that trigger an alert"
  type        = number
}

variable "replication_lag_threshold_ms" {
  description = "Database replication lag threshold in milliseconds"
  type        = number
}

# -----------------------------------------------------------------------------
# WORKFLOW CONFIGURATION
# -----------------------------------------------------------------------------

variable "dr_failover_workflow_path" {
  description = "Path to the DR failover workflow YAML file"
  type        = string
}

variable "dr_failback_workflow_path" {
  description = "Path to the DR failback workflow YAML file"
  type        = string
}

# -----------------------------------------------------------------------------
# NETWORKING CONFIGURATION
# -----------------------------------------------------------------------------

variable "ssl_certificate_name" {
  description = "Name for the SSL certificate"
  type        = string
}

variable "ssl_private_key_path" {
  description = "Path to the SSL private key file"
  type        = string
}

variable "ssl_certificate_path" {
  description = "Path to the SSL certificate file"
  type        = string
}

variable "health_check_source_ranges" {
  description = "Source IP ranges for Google Cloud health checks"
  type        = list(string)
}
