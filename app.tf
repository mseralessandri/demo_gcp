//https://github.com/gruntwork-io/terraform-google-sql/blob/master/examples/mysql-private-ip/main.tf
//https://registry.terraform.io/modules/GoogleCloudPlatform/sql-db/google/25.0.0/examples/mysql-private
provider "google" {
  project = "microcloud-448817"  # GCP project ID
  region  = "us-central1"        # Region where resources will be created
}

/* resource "google_compute_network" "app_network" {
  name                    = "app-network"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "app_subnet" {
  name          = "app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.app_network.id
} 

# Reserve a private IP range for Cloud SQL
resource "google_compute_global_address" "db_private_ip_address" {
  name          = "db-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16          
  network       = google_compute_network.app_network.id
}

resource "google_service_networking_connection" "db_connection" {
  //network                 = google_compute_network.app_network.id
  network = "projects/microcloud-448817/global/networks/default"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.db_private_ip_address.name]
  lifecycle {
    create_before_destroy = true  
  }

}*/

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
    //subnetwork = google_compute_subnetwork.app_subnet.id
    network= "default"
    access_config {}  # Assign a public IP
  }

  service_account {
    email  = google_service_account.app_service_account.email
    scopes = ["cloud-platform"]
  }

  # Use template_file to render the setup.sh script with the correct DB_HOST value
  metadata_startup_script = templatefile("${path.module}/setup.sh", {
    db_host = google_sql_database_instance.app_db_instance.public_ip_address
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

# Create Google Secret Manager secrets
/* resource "google_secret_manager_secret" "db_user" {
  secret_id = "db_user"
  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "db_password"
  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }
} */

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

# Populate secrets with sensitive variables
# resource "google_secret_manager_secret_version" "db_user_value" {
#   secret      = google_secret_manager_secret.db_user.id
#   secret_data = var.db_user
# }

# resource "google_secret_manager_secret_version" "db_password_value" {
#   secret      = google_secret_manager_secret.db_password.id
#   secret_data = var.db_password
# }

# Create a combined secret with all database credentials
resource "google_secret_manager_secret_version" "db_credentials_value" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    user     = var.db_user
    password = var.db_password
    host     = google_sql_database_instance.app_db_instance.public_ip_address
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

# Create the Cloud SQL instance
resource "google_sql_database_instance" "app_db_instance" {
  name             = "app-db-instance"
  database_version = "MYSQL_8_0"
  region           = "us-central1"
  deletion_protection = false  

  # Ensure the network connection is established before creating the instance
 // depends_on = [google_service_networking_connection.db_connection]

  settings {
    tier = "db-g1-small"  # Slightly larger instance for better performance
    availability_type = "ZONAL"

 // ip_configuration {
  //  ipv4_enabled     = false  # Disable public IP
   // private_network  = google_compute_network.app_network.id  # Same VPC as VM
 //  private_network = "projects/microcloud-448817/global/networks/default"
 // }
  ip_configuration {
        authorized_networks {
            name            = "Allowed Network"
            value           = "0.0.0.0/0"
            }
        }
    }
  }




/* resource "google_compute_network_peering_routes_config" "peering_routes" {
  peering              = google_service_networking_connection.db_connection.peering
  network              = google_compute_network.app_network.name
  import_custom_routes = true
  export_custom_routes = true
} */
 
# Create the database within the instance
resource "google_sql_database" "app_database" {
  name     = "dr_demo"
  instance = google_sql_database_instance.app_db_instance.name
}

# Create the database user
resource "google_sql_user" "app_db_user" {
  name     = "dr_demo_user"
  instance = google_sql_database_instance.app_db_instance.name
  password = var.db_password
  host     = "%"  # Allow connections from any host
}

# Create a firewall rule to allow HTTP traffic to the web server
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  //network = google_compute_network.app_network.id
  network = "default"  # Using the default network for SSH access


  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]  # Using the same tag as the web server
}

# Create a firewall rule to allow SSH traffic for management
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  //network = google_compute_network.app_network.id
  network = "default"  # Using the default network for SSH access

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}
