# =============================================================================
# COMPUTE RESOURCES
# =============================================================================
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

# Regional persistent disk for application data
resource "google_compute_region_disk" "regional_disk" {
  name                      = "app-regional-disk"
  type                      = "pd-balanced" # Balanced Persistent Disk performance and cost
  region                    = var.region
  size                      = var.disk_size_gb
  replica_zones             = [var.primary_zone, var.standby_zone]
  physical_block_size_bytes = 4096
  
  lifecycle {
    ignore_changes = [
      # Ignore changes that don't require disk recreation
      physical_block_size_bytes,
      labels
    ]
  }
}

# Standby boot disk
resource "google_compute_disk" "standby_boot_disk" {
  name  = "app-standby-boot-disk"
  zone  = var.standby_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
  
  lifecycle {
    ignore_changes = [
      # Ignore image changes to prevent unnecessary recreation
      # This allows terraform destroy to work while preventing "already exists" errors
      image,
      labels,
      name
    ]
  }
}

# Primary boot disk
resource "google_compute_disk" "primary_boot_disk" {
  name  = "app-primary-boot-disk"
  zone  = var.primary_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
  
  lifecycle {
    ignore_changes = [
      # Ignore image changes to prevent unnecessary recreation
      # This allows terraform destroy to work while preventing "already exists" errors
      image,
      labels,
      name
    ]
  }
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
    source = google_compute_disk.primary_boot_disk.self_link # .self_link is used to reference the disk within GCP
  }

  attached_disk {
    source      = google_compute_region_disk.regional_disk.self_link
    device_name = "app-data-disk"
    mode        = "READ_WRITE"
  }

  network_interface {
    network = "default" # Use the default VPC network
    access_config {} # Assign an external ephemeral public IP address
  }

  service_account {
    email  = google_service_account.dr_service_account.email
    scopes = ["cloud-platform"] # Full access to all Google Cloud services APIs. Real filter on IAM roles to access a resource.
  }

  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.db_instance.private_ip_address
    GO_VERSION = var.go_version
  })
  
  lifecycle {
    ignore_changes = [
      # Ignore metadata changes that don't require VM recreation
      metadata_startup_script,
      labels
    ]
  }
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

  # Use the same setup script as primary VM
  # The script will detect if it's running on a restored VM and handle accordingly
  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.db_instance.private_ip_address
    GO_VERSION = var.go_version
  })
  
  # Stop the VM after creation
  provisioner "local-exec" {
    command = "gcloud compute instances stop ${self.name} --zone=${self.zone} --quiet"
  }
  
  # Prevent Terraform from trying to recreate the VM on subsequent applies
  lifecycle {
    ignore_changes = [
      # Ignore VM state changes and metadata updates to prevent recreation
      desired_status,
      metadata_startup_script,
      labels,
      boot_disk,
      # Ignore boot disk changes to prevent VM recreation when disk source changes
      # This is critical for DR scenarios where boot disk may be swapped
      metadata
    ]
  }
}
