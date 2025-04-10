# Variables for the base infrastructure module

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region where resources will be created"
  type        = string
  default     = "us-central1"
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
  default     = "../setup.sh"
}

variable "database_sql_path" {
  description = "Path to the database SQL file"
  type        = string
  default     = "../database.sql"
}

variable "go_version" {
  description = "Version of Go to install"
  type        = string
  default     = "1.24.1"
}
