# =============================================================================
# OUTPUTS FOR DR ACTIVE-PASSIVE COMPLETE ZONAL IMPLEMENTATION
# =============================================================================
# This file exposes the module outputs.

# -----------------------------------------------------------------------------
# COMPUTE OUTPUTS
# -----------------------------------------------------------------------------

output "primary_vm_name" {
  description = "Name of the primary VM"
  value       = module.dr_complete.primary_vm_name
}

output "primary_vm_zone" {
  description = "Zone of the primary VM"
  value       = module.dr_complete.primary_vm_zone
}

output "primary_vm_ip" {
  description = "External IP of the primary VM"
  value       = module.dr_complete.primary_vm_ip
}

output "standby_vm_name" {
  description = "Name of the standby VM"
  value       = module.dr_complete.standby_vm_name
}

output "standby_vm_zone" {
  description = "Zone of the standby VM"
  value       = module.dr_complete.standby_vm_zone
}

output "standby_vm_ip" {
  description = "External IP of the standby VM"
  value       = module.dr_complete.standby_vm_ip
}

# -----------------------------------------------------------------------------
# DATABASE OUTPUTS
# -----------------------------------------------------------------------------

output "database_name" {
  description = "Name of the Cloud SQL instance"
  value       = module.dr_complete.database_name
}

output "database_connection_name" {
  description = "Connection name of the Cloud SQL instance"
  value       = module.dr_complete.database_connection_name
}

output "database_ip" {
  description = "IP address of the Cloud SQL instance"
  value       = module.dr_complete.database_ip
}

# -----------------------------------------------------------------------------
# NETWORKING OUTPUTS
# -----------------------------------------------------------------------------

output "load_balancer_http_ip" {
  description = "HTTP IP address of the load balancer"
  value       = module.dr_complete.load_balancer_http_ip
}

output "load_balancer_https_ip" {
  description = "HTTPS IP address of the load balancer"
  value       = module.dr_complete.load_balancer_https_ip
}

output "app_http_url" {
  description = "HTTP URL of the application"
  value       = module.dr_complete.app_http_url
}

output "app_https_url" {
  description = "HTTPS URL of the application"
  value       = module.dr_complete.app_https_url
}

# -----------------------------------------------------------------------------
# BACKUP OUTPUTS
# -----------------------------------------------------------------------------

output "backup_bucket_name" {
  description = "Name of the backup storage bucket"
  value       = module.dr_complete.backup_bucket_name
}

output "snapshot_schedule_name" {
  description = "Name of the snapshot schedule"
  value       = module.dr_complete.snapshot_schedule_name
}

# -----------------------------------------------------------------------------
# MONITORING OUTPUTS
# -----------------------------------------------------------------------------

output "dashboard_url" {
  description = "URL to the monitoring dashboard"
  value       = module.dr_complete.dashboard_url
}

# -----------------------------------------------------------------------------
# TESTING OUTPUTS
# -----------------------------------------------------------------------------

output "test_schedule_weekly" {
  description = "Schedule for weekly DR tests"
  value       = module.dr_complete.test_schedule_weekly
}

output "test_schedule_monthly" {
  description = "Schedule for monthly DR tests"
  value       = module.dr_complete.test_schedule_monthly
}

output "test_schedule_quarterly" {
  description = "Schedule for quarterly DR tests"
  value       = module.dr_complete.test_schedule_quarterly
}
