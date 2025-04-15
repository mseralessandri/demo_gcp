# =============================================================================
# DISASTER RECOVERY MODULE - ACTIVE-PASSIVE COMPLETE ZONAL
# =============================================================================
# This module implements a comprehensive disaster recovery solution using 
# Google Cloud's native services for an active-passive zonal architecture.

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# STORAGE RESOURCES
# -----------------------------------------------------------------------------
# The DR solution uses regional persistent disks for synchronous replication
# between zones, providing zero RPO for disk data.

# Regional persistent disk for application data
resource "google_compute_region_disk" "regional_disk" {
  name                      = "app-regional-disk"
  type                      = "pd-balanced"
  region                    = var.region
  size                      = var.disk_size_gb
  replica_zones             = [var.primary_zone, var.standby_zone]
  physical_block_size_bytes = 4096
}

# Standby boot disk
resource "google_compute_disk" "standby_boot_disk" {
  name  = "app-standby-boot-disk"
  zone  = var.standby_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
}

# Primary boot disk
resource "google_compute_disk" "primary_boot_disk" {
  name  = "app-primary-boot-disk"
  zone  = var.primary_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
}

# -----------------------------------------------------------------------------
# DATABASE RESOURCES
# -----------------------------------------------------------------------------
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
        retention_unit   = "COUNT"
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
      update_track = "stable"
    }
  }
  
  deletion_protection = var.deletion_protection
}

# Database and user
resource "google_sql_database" "database" {
  name     = "dr_demo"  # Change to match the other module
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
  name     = var.db_user  # Use the variable instead of hardcoding
  instance = google_sql_database_instance.db_instance.name
  password = var.db_password
  host     = "%"  # Allow connections from any host
}

# -----------------------------------------------------------------------------
# COMPUTE RESOURCES
# -----------------------------------------------------------------------------
# Primary VM in the primary zone and standby VM in the standby zone

# Create a service account for the VMs
resource "google_service_account" "dr_service_account" {
  account_id   = "dr-service-account"
  display_name = "DR Service Account"
}

# Grant the service account access to Secret Manager
resource "google_project_iam_binding" "secret_manager_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_service_account.dr_service_account.email}"
  ]
}

# Grant the service account access to Cloud SQL
resource "google_project_iam_binding" "cloud_sql_access" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  members = [
    "serviceAccount:${google_service_account.dr_service_account.email}"
  ]
}

# Grant the service account access to view Cloud SQL instances
resource "google_project_iam_binding" "cloud_sql_viewer" {
  project = var.project_id
  role    = "roles/cloudsql.viewer"
  members = [
    "serviceAccount:${google_service_account.dr_service_account.email}"
  ]
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

# Primary VM in the primary zone
resource "google_compute_instance" "primary_vm" {
  name         = "app-web-server-dr-primary"
  machine_type = var.vm_machine_type
  zone         = var.primary_zone
  tags         = ["web", "dr-primary"]
  
  depends_on = [
    google_sql_database_instance.db_instance,
    google_secret_manager_secret_version.db_credentials_value
  ]

  boot_disk {
    source = google_compute_disk.primary_boot_disk.self_link
  }

  attached_disk {
    source      = google_compute_region_disk.regional_disk.self_link
    device_name = "app-data-disk"
    mode        = "READ_WRITE"
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.dr_service_account.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.db_instance.private_ip_address
    GO_VERSION = var.go_version
  })
}

# Standby VM in the standby zone (stopped by default)
resource "google_compute_instance" "standby_vm" {
  name         = "app-web-server-dr-standby"
  machine_type = var.vm_machine_type
  zone         = var.standby_zone
  tags         = ["web", "dr-standby"]
  
  depends_on = [
    google_sql_database_instance.db_instance,
    google_secret_manager_secret_version.db_credentials_value
  ]

  boot_disk {
    source = google_compute_disk.standby_boot_disk.self_link
  }

  # Note: The regional disk will be attached during failover
  # It's not attached by default to avoid conflicts with the primary VM

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.dr_service_account.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.db_instance.private_ip_address
    GO_VERSION = var.go_version
  })
  
  # Stop the VM after creation
  provisioner "local-exec" {
    command = "gcloud compute instances stop ${self.name} --zone=${self.zone} --quiet"
  }
  
  # Prevent Terraform from trying to start the VM on subsequent applies
  lifecycle {
    ignore_changes = [desired_status]
  }
}
