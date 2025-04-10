# Outputs for the base infrastructure configuration

output "vm_name" {
  description = "Name of the VM"
  value       = module.base.vm_name
}

output "vm_zone" {
  description = "Zone of the VM"
  value       = module.base.vm_zone
}

output "vm_ip" {
  description = "External IP address of the VM"
  value       = module.base.vm_ip
}

output "db_instance_name" {
  description = "Name of the database instance"
  value       = module.base.db_instance_name
}

output "db_connection_name" {
  description = "Connection name of the database instance"
  value       = module.base.db_connection_name
}

output "db_public_ip" {
  description = "Public IP address of the database instance"
  value       = module.base.db_public_ip
}

output "service_account_email" {
  description = "Email of the service account"
  value       = module.base.service_account_email
}
