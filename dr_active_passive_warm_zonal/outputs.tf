# Outputs for the DR infrastructure

# Note: Base infrastructure outputs are not included
# as the base module is not used in this configuration

# DR infrastructure outputs
output "dr_primary_vm_name" {
  description = "Name of the primary DR VM"
  value       = module.dr.dr_primary_vm_name
}

output "dr_primary_vm_zone" {
  description = "Zone of the primary DR VM"
  value       = module.dr.dr_primary_vm_zone
}

output "dr_primary_vm_ip" {
  description = "External IP address of the primary DR VM"
  value       = module.dr.dr_primary_vm_ip
}

output "dr_standby_vm_name" {
  description = "Name of the standby DR VM"
  value       = module.dr.dr_standby_vm_name
}

output "dr_standby_vm_zone" {
  description = "Zone of the standby DR VM"
  value       = module.dr.dr_standby_vm_zone
}

output "dr_standby_vm_ip" {
  description = "External IP address of the standby DR VM"
  value       = module.dr.dr_standby_vm_ip
}

output "dr_db_instance_name" {
  description = "Name of the DR database instance"
  value       = module.dr.dr_db_instance_name
}

output "dr_db_connection_name" {
  description = "Connection name of the DR database instance"
  value       = module.dr.dr_db_connection_name
}

output "dr_db_public_ip" {
  description = "Public IP address of the DR database instance"
  value       = module.dr.dr_db_public_ip
}

output "dr_primary_disk_name" {
  description = "Name of the primary disk"
  value       = module.dr.dr_primary_disk_name
}

output "dr_primary_disk_zone" {
  description = "Zone of the primary disk"
  value       = module.dr.dr_primary_disk_zone
}

output "dr_standby_disk_name" {
  description = "Name of the standby disk"
  value       = module.dr.dr_standby_disk_name
}

output "dr_standby_disk_zone" {
  description = "Zone of the standby disk"
  value       = module.dr.dr_standby_disk_zone
}

output "dr_snapshot_schedule_name" {
  description = "Name of the snapshot schedule"
  value       = module.dr.dr_snapshot_schedule_name
}

output "dr_dashboard_name" {
  description = "Name of the DR monitoring dashboard"
  value       = module.dr.dr_dashboard_name
}

output "dr_vm_status_alert_name" {
  description = "Name of the DR VM status alert"
  value       = module.dr.dr_vm_status_alert_name
}

output "dr_failover_command" {
  description = "Command to execute failover to the DR zone"
  value       = module.dr.dr_failover_command
}

output "dr_failback_command" {
  description = "Command to execute failback to the primary zone"
  value       = module.dr.dr_failback_command
}

output "dr_status_command" {
  description = "Command to check the status of the DR environment"
  value       = module.dr.dr_status_command
}
