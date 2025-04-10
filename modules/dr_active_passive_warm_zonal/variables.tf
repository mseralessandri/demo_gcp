# Variables for the DR infrastructure module

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "primary_zone" {
  description = "Primary zone for DR resources"
  type        = string
  default     = "us-central1-a"
}

variable "standby_zone" {
  description = "Standby zone for DR resources"
  type        = string
  default     = "us-central1-c"
}

variable "vm_machine_type" {
  description = "Machine type for the VM"
  type        = string
  default     = "e2-small"
}

variable "vm_image" {
  description = "Boot disk image for the VM"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "disk_size_gb" {
  description = "Size of the disk in GB"
  type        = number
  default     = 10
}

variable "db_user" {
  description = "Database username for the application"
  type        = string
}

variable "db_password" {
  description = "Database password for the application"
  type        = string
}

variable "db_root_password" {
  description = "Root password for the database instance"
  type        = string
}

variable "db_tier" {
  description = "Database tier for Cloud SQL instance"
  type        = string
  default     = "db-g1-small"
}

variable "setup_script_path" {
  description = "Path to the setup script"
  type        = string
  default     = "setup.sh"
}

variable "database_sql_path" {
  description = "Path to the database SQL file"
  type        = string
  default     = "database.sql"
}

variable "go_version" {
  description = "Version of Go to install"
  type        = string
  default     = "1.24.1"
}

variable "backup_start_time" {
  description = "Start time for automated backups (24-hour format)"
  type        = string
  default     = "02:00"
}

variable "notification_email" {
  description = "Email address for DR alerts"
  type        = string
  default     = "alerts@example.com"
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
