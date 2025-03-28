provider "google" {
  project = "microcloud-448817"  # GCP project ID
  region  = "us-central1"               # Region where resources will be created
}

resource "google_compute_network" "app_network" {
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

# Create a low-cost VM for the web application running Go app
resource "google_compute_instance" "app_web_server" {
  name         = "app-web-server"
  machine_type = "e2-micro"  # Lower-cost machine type
  zone         = "us-central1-a"
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"  # Ubuntu 24.04 as the OS
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app_subnet.id
    access_config {}  # Assign a public IP
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    # Update and install dependencies
    sudo apt update
    sudo apt install -y mysql-client golang git ufw

    # Clone the Go application repository
    git clone https://github.com/mseralessandri/demo_gcp.git ~/dr-demo
    cd ~/dr-demo

    # Retrieve secrets from Google Secret Manager
    DB_USER=$(gcloud secrets versions access latest --secret=db-user)
    DB_PASSWORD=$(gcloud secrets versions access latest --secret=db-password)
    DB_HOST=$(gcloud secrets versions access latest --secret=db-host)

    # Export secrets as environment variables
    echo "export DB_USER=$DB_USER" >> ~/.bashrc
    echo "export DB_PASSWORD=$DB_PASSWORD" >> ~/.bashrc
    echo "export DB_HOST=$DB_HOST" >> ~/.bashrc
    source ~/.bashrc

    # Build and run the Go app
    go mod tidy
    go build -o dr-demo main.go
    nohup ./dr-demo &

    # Optionally, open port for the Go app (if needed)
    sudo ufw allow 8080

  EOT
}

# Create a Cloud SQL database instance with minimal cost
resource "google_sql_database_instance" "app_db_instance" {
  name             = "app-db-instance"
  database_version = "MYSQL_8_0"  # Specify the database version
  region           = "us-central1"
  deletion_protection = false  

  settings {
    tier = "db-g1-small"  # Slightly larger instance for better performance while keeping costs low instead of db-f1-micro
    availability_type = "ZONAL"  # Reduce cost by avoiding high availability
  }
  lifecycle {
    prevent_destroy = false  # Terraform can destroy it
  }
}

# Create a firewall rule to allow HTTP traffic to the web server
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.app_network.id

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
  network = google_compute_network.app_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}
