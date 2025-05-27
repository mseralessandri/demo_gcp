# =============================================================================
# DATABASE RESOURCES
# =============================================================================
# Cloud SQL instance with high availability for automatic failover between zones

# Cloud SQL instance with high availability
resource "google_sql_database_instance" "db_instance" {
  name             = "app-db-instance-dr"
  database_version = "MYSQL_8_0"
  region           = var.region
  root_password    = var.db_root_password
  
  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"  # Enables cross-zone replication
    
    backup_configuration {
      enabled            = true
      binary_log_enabled = true  # This enables point-in-time recovery for MySQL
      start_time         = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT" # Number of backups to retain
      }
    }
    
    ip_configuration {
      authorized_networks {
        name  = "Allowed Network"
        value = "0.0.0.0/0"
      }
    }
    
    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = "stable" # Use stable updates for production
    }
  }
  
  deletion_protection = var.deletion_protection
}

# Database and user
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
  
  # Add provisioner to initialize the database
  provisioner "local-exec" {
    command = <<-EOT
      # Create a temporary SQL file with the variables replaced
      cat ${var.database_sql_path} | sed -e 's/$${db_user}/${var.db_user}/g' -e 's/$${db_password}/${var.db_password}/g' > /tmp/init_db_dr_complete.sql
      
      # Execute the SQL script against the Cloud SQL instance
      mysql -h ${google_sql_database_instance.db_instance.public_ip_address} -u root -p${var.db_root_password} < /tmp/init_db_dr_complete.sql
      
      # Remove the temporary file
      rm /tmp/init_db_dr_complete.sql
    EOT
  }
}

resource "google_sql_user" "user" {
  name     = var.db_user
  instance = google_sql_database_instance.db_instance.name
  password = var.db_password
  host     = "%"  # Allow connections from any host
}

# Create a secret for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "db_credentials"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# Create a combined secret with all database credentials
resource "google_secret_manager_secret_version" "db_credentials_value" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    user     = var.db_user
    password = var.db_password
  })
  
  # Ensure the database is created before the secret
  depends_on = [
    google_sql_database_instance.db_instance,
    google_sql_database.database,
    google_sql_user.user
  ]
}
