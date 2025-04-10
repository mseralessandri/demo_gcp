# Outputs for the base infrastructure module

output "vm_name" {
  description = "Name of the VM"
  value       = google_compute_instance.app_web_server.name
}

output "vm_zone" {
  description = "Zone of the VM"
  value       = google_compute_instance.app_web_server.zone
}

output "vm_ip" {
  description = "External IP address of the VM"
  value       = google_compute_instance.app_web_server.network_interface[0].access_config[0].nat_ip
}

output "db_instance_name" {
  description = "Name of the database instance"
  value       = google_sql_database_instance.app_db_instance.name
}

output "db_connection_name" {
  description = "Connection name of the database instance"
  value       = google_sql_database_instance.app_db_instance.connection_name
}

output "db_public_ip" {
  description = "Public IP address of the database instance"
  value       = google_sql_database_instance.app_db_instance.public_ip_address
}

output "service_account_email" {
  description = "Email of the service account"
  value       = google_service_account.app_service_account.email
}
