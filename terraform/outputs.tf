# =============================================================================
# OUTPUTS FOR DR ACTIVE-PASSIVE COMPLETE ZONAL 
# =============================================================================
# -----------------------------------------------------------------------------
# COMPUTE OUTPUTS
# -----------------------------------------------------------------------------
# Information about the primary and standby VMs

output "primary_vm_name" {
  description = "Name of the primary VM"
  value       = google_compute_instance.primary_vm.name
}

output "primary_vm_zone" {
  description = "Zone of the primary VM"
  value       = google_compute_instance.primary_vm.zone
}

output "primary_vm_ip" {
  description = "External IP of the primary VM"
  value       = google_compute_instance.primary_vm.network_interface[0].access_config[0].nat_ip
}

output "standby_vm_name" {
  description = "Name of the standby VM"
  value       = google_compute_instance.standby_vm.name
}

output "standby_vm_zone" {
  description = "Zone of the standby VM"
  value       = google_compute_instance.standby_vm.zone
}

output "standby_vm_ip" {
  description = "External IP of the standby VM"
  value       = google_compute_instance.standby_vm.network_interface[0].access_config[0].nat_ip
}

# -----------------------------------------------------------------------------
# DATABASE OUTPUTS
# -----------------------------------------------------------------------------
# Information about the database instance

output "database_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.db_instance.name
}

output "database_connection_name" {
  description = "Connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.db_instance.connection_name
}

output "database_ip" {
  description = "IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.db_instance.ip_address.0.ip_address
}

output "database_self_link" {
  description = "Self link of the Cloud SQL instance"
  value       = google_sql_database_instance.db_instance.self_link
}

# -----------------------------------------------------------------------------
# NETWORKING OUTPUTS
# -----------------------------------------------------------------------------
# Information about the load balancer and networking resources

output "load_balancer_ip" {
  description = "Static IP address of the load balancer (used for both HTTP and HTTPS)"
  value       = google_compute_global_address.app_lb_ip.address
}

output "load_balancer_http_ip" {
  description = "HTTP IP address of the load balancer (same as load_balancer_ip)"
  value       = google_compute_global_address.app_lb_ip.address
}

output "load_balancer_https_ip" {
  description = "HTTPS IP address of the load balancer (same as load_balancer_ip)"
  value       = google_compute_global_address.app_lb_ip.address
}

output "app_http_url" {
  description = "HTTP URL of the application"
  value       = "http://${google_compute_global_address.app_lb_ip.address}/web"
}

output "app_https_url" {
  description = "HTTPS URL of the application"
  value       = "https://${google_compute_global_address.app_lb_ip.address}/web"
}

# -----------------------------------------------------------------------------
# BACKUP OUTPUTS
# -----------------------------------------------------------------------------
# Information about backup resources

output "backup_bucket_name" {
  description = "Name of the backup storage bucket"
  value       = google_storage_bucket.dr_backup_bucket.name
}

output "snapshot_schedule_name" {
  description = "Name of the snapshot schedule"
  value       = google_compute_resource_policy.snapshot_schedule.name
}

# -----------------------------------------------------------------------------
# MONITORING OUTPUTS
# -----------------------------------------------------------------------------
# Information about monitoring resources

output "dashboard_name" {
  description = "Name of the monitoring dashboard"
  value       = google_monitoring_dashboard.dr_dashboard.dashboard_json
}

output "dashboard_url" {
  description = "URL to the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${substr(google_monitoring_dashboard.dr_dashboard.id, length("projects/${var.project_id}/dashboards/"), -1)}"
}

# -----------------------------------------------------------------------------
# SERVICE ACCOUNT OUTPUTS
# -----------------------------------------------------------------------------
# Information about the service account

output "service_account_email" {
  description = "Email of the service account"
  value       = google_service_account.dr_service_account.email
}

# -----------------------------------------------------------------------------
# TESTING OUTPUTS
# -----------------------------------------------------------------------------
# Information about testing resources

output "test_schedule_weekly" {
  description = "Schedule for weekly DR tests"
  value       = google_cloud_scheduler_job.weekly_status_check.schedule
}

output "test_schedule_monthly" {
  description = "Schedule for monthly DR tests"
  value       = google_cloud_scheduler_job.monthly_backup_test.schedule
}

output "test_schedule_quarterly" {
  description = "Schedule for quarterly DR tests"
  value       = google_cloud_scheduler_job.quarterly_failover_test.schedule
}
