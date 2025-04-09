provider "google" {
  project = "microcloud-448817"  # GCP project ID
  region  = "us-central1"        # Region where resources will be created
}


# Create a cost-effective but faster VM for the web application running Go app
resource "google_compute_instance" "app_web_server" {
  name         = "app-web-server"
  machine_type = "e2-small"  # Upgraded to e2-small for better performance
  zone         = "us-central1-a"
  tags         = ["web"]
  
  # Ensure the database is created before the VM
  depends_on = [
    google_sql_database_instance.app_db_instance,
    google_secret_manager_secret_version.db_credentials_value
  ]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"  # Ubuntu 24.04 as the OS
    }
  }

  network_interface {
    network = "default"

    access_config {
      # Ephemeral public IP will be assigned
    }
  }

  service_account {
    email  = google_service_account.app_service_account.email
    scopes = ["cloud-platform"]
  }

  # Use template_file to render the setup.sh script with the correct DB_HOST value
  metadata_startup_script = templatefile("${path.module}/setup.sh", {
    db_host = google_sql_database_instance.app_db_instance.public_ip_address
    GO_VERSION = "1.24.1"

  })
  
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


resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "db_credentials"
  replication {
    user_managed {
      replicas {
        location = "us-central1"
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
    //host     = google_sql_database_instance.app_db_instance.public_ip_address
  })
  
  # Ensure the database is created before the secret
  depends_on = [
    google_sql_database_instance.app_db_instance,
    google_sql_database.app_database,
    google_sql_user.app_db_user
  ]
}

# Create a service account for the VM
resource "google_service_account" "app_service_account" {
  account_id   = "app-service-account"
  display_name = "App Service Account"
}

# Grant the service account access to Secret Manager
resource "google_project_iam_binding" "secret_manager_access" {
  project = "microcloud-448817"
  role    = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_service_account.app_service_account.email}"
  ]
}

# Grant the service account access to Cloud SQL
resource "google_project_iam_binding" "cloud_sql_access" {
  project = "microcloud-448817"
  role    = "roles/cloudsql.client"
  members = [
    "serviceAccount:${google_service_account.app_service_account.email}"
  ]
}

# Grant the service account access to view Cloud SQL instances
resource "google_project_iam_binding" "cloud_sql_viewer" {
  project = "microcloud-448817"
  role    = "roles/cloudsql.viewer"
  members = [
    "serviceAccount:${google_service_account.app_service_account.email}"
  ]
}

# Create the Cloud SQL instance
resource "google_sql_database_instance" "app_db_instance" {
  name             = "app-db-instance"
  database_version = "MYSQL_8_0"
  region           = "us-central1"
  deletion_protection = false  

  root_password = var.db_root_password

  settings {
    tier = "db-g1-small"  # Slightly larger instance for better performance
    availability_type = "ZONAL"

    ip_configuration {
        authorized_networks {
            name            = "Allowed Network"
            value           = "0.0.0.0/0"
        }
    }
    }
  }

 
# Create the database within the instance and initialize it
resource "google_sql_database" "app_database" {
  name     = "dr_demo"
  instance = google_sql_database_instance.app_db_instance.name
  
  # Initialize the database using the database.sql file
  provisioner "local-exec" {
    command = <<-EOT
      # Create a temporary SQL file with the variables replaced
      cat ${path.module}/database.sql | sed -e 's/$${db_user}/${var.db_user}/g' -e 's/$${db_password}/${var.db_password}/g' > /tmp/init_db.sql
      
      # Execute the SQL script against the Cloud SQL instance
      mysql -h ${google_sql_database_instance.app_db_instance.public_ip_address} -u root -p${var.db_root_password} < /tmp/init_db.sql
      
      # Remove the temporary file
      rm /tmp/init_db.sql
    EOT
  }
}

# Create the database user
resource "google_sql_user" "app_db_user" {
  name     = "dr_demo_user"
  instance = google_sql_database_instance.app_db_instance.name
  password = var.db_password
  host     = "%"  # Allow connections from any host
}

# Create a firewall rule to allow HTTP, HTTPS, and application traffic to the web server
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = "default"  # Using the default network for web access


  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]  # Using the same tag as the web server
}

# Create a firewall rule to allow SSH traffic for management
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = "default"  # Using the default network for SSH access

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}
