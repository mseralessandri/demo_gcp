# Outputs for the DR infrastructure module

output "dr_primary_vm_name" {
  description = "Name of the primary DR VM"
  value       = google_compute_instance.app_web_server_dr.name
}

output "dr_primary_vm_zone" {
  description = "Zone of the primary DR VM"
  value       = google_compute_instance.app_web_server_dr.zone
}

output "dr_primary_vm_ip" {
  description = "External IP address of the primary DR VM"
  value       = google_compute_instance.app_web_server_dr.network_interface[0].access_config[0].nat_ip
}

output "dr_standby_vm_name" {
  description = "Name of the standby DR VM"
  value       = google_compute_instance.app_web_server_dr_standby.name
}

output "dr_standby_vm_zone" {
  description = "Zone of the standby DR VM"
  value       = google_compute_instance.app_web_server_dr_standby.zone
}

output "dr_standby_vm_ip" {
  description = "External IP address of the standby DR VM"
  value       = google_compute_instance.app_web_server_dr_standby.network_interface[0].access_config[0].nat_ip
}

output "dr_db_instance_name" {
  description = "Name of the DR database instance"
  value       = google_sql_database_instance.app_db_instance_dr.name
}

output "dr_db_connection_name" {
  description = "Connection name of the DR database instance"
  value       = google_sql_database_instance.app_db_instance_dr.connection_name
}

output "dr_db_public_ip" {
  description = "Public IP address of the DR database instance"
  value       = google_sql_database_instance.app_db_instance_dr.public_ip_address
}

output "dr_primary_disk_name" {
  description = "Name of the primary disk"
  value       = google_compute_disk.primary_disk.name
}

output "dr_primary_disk_zone" {
  description = "Zone of the primary disk"
  value       = google_compute_disk.primary_disk.zone
}

output "dr_standby_disk_name" {
  description = "Name of the standby disk"
  value       = google_compute_disk.standby_disk.name
}

output "dr_standby_disk_zone" {
  description = "Zone of the standby disk"
  value       = google_compute_disk.standby_disk.zone
}

output "dr_snapshot_schedule_name" {
  description = "Name of the snapshot schedule"
  value       = google_compute_resource_policy.primary_disk_snapshot_schedule.name
}

output "dr_dashboard_name" {
  description = "Name of the DR monitoring dashboard"
  value       = "Disaster Recovery Dashboard"
}

output "dr_vm_status_alert_name" {
  description = "Name of the DR VM status alert"
  value       = google_monitoring_alert_policy.vm_status_alert.display_name
}

output "dr_failover_command" {
  description = "Command to execute failover to the DR zone"
  value       = "cd dr_active_passive_warm_zonal && ./dr_test_script.sh failover"
}

output "dr_failback_command" {
  description = "Command to execute failback to the primary zone"
  value       = "cd dr_active_passive_warm_zonal && ./dr_test_script.sh failback"
}

output "dr_status_command" {
  description = "Command to check the status of the DR environment"
  value       = "cd dr_active_passive_warm_zonal && ./dr_test_script.sh status"
}
