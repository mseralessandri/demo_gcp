# =============================================================================
# MULTI-REGION DR EXTENSION
# =============================================================================
# This file extends the zonal DR solution to support multi-region failover

# -----------------------------------------------------------------------------
# SECONDARY REGION RESOURCES
# -----------------------------------------------------------------------------

# Secondary region primary boot disk
resource "google_compute_disk" "secondary_primary_boot_disk" {
  name  = "app-secondary-primary-boot-disk"
  zone  = var.secondary_primary_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
  
  # Reuse the same lifecycle configuration as primary boot disk
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

# Secondary region standby boot disk
resource "google_compute_disk" "secondary_standby_boot_disk" {
  name  = "app-secondary-standby-boot-disk"
  zone  = var.secondary_standby_zone
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

# Secondary region primary VM
resource "google_compute_instance" "secondary_primary_vm" {
  name         = "app-web-server-dr-secondary-primary"
  machine_type = var.vm_machine_type
  zone         = var.secondary_primary_zone
  tags         = ["web", "dr-secondary-primary"]
  
  depends_on = [
    google_sql_database_instance.secondary_db_instance
  ]

  boot_disk {
    source = google_compute_disk.secondary_primary_boot_disk.self_link
  }

  # Note: No regional disk attached by default - will be attached during failover
  
  network_interface {
    network = "default" # Reuse the same network as primary region
    access_config {} # Assign an external ephemeral public IP address
  }

  service_account {
    email  = google_service_account.dr_service_account.email # Reuse the same service account
    scopes = ["cloud-platform"]
  }

  # Reuse the same setup script but point to secondary DB
  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.secondary_db_instance.private_ip_address
    GO_VERSION = var.go_version
  })
  
  # Stop the VM after creation
  provisioner "local-exec" {
    command = "gcloud compute instances stop ${self.name} --zone=${self.zone} --quiet"
  }
  
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

# Secondary region standby VM
resource "google_compute_instance" "secondary_standby_vm" {
  name         = "app-web-server-dr-secondary-standby"
  machine_type = var.vm_machine_type
  zone         = var.secondary_standby_zone
  tags         = ["web", "dr-secondary-standby"]
  
  depends_on = [
    google_sql_database_instance.secondary_db_instance
  ]

  boot_disk {
    source = google_compute_disk.secondary_standby_boot_disk.self_link
  }
  
  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.dr_service_account.email
    scopes = ["cloud-platform"]
  }

  # Reuse the same setup script
  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.secondary_db_instance.private_ip_address
    GO_VERSION = var.go_version
  })
  
  provisioner "local-exec" {
    command = "gcloud compute instances stop ${self.name} --zone=${self.zone} --quiet"
  }
  
  lifecycle {
    ignore_changes = [
      desired_status,
      metadata_startup_script,
      labels,
      boot_disk,
      metadata
    ]
  }
}

# -----------------------------------------------------------------------------
# SECONDARY REGION DATABASE
# -----------------------------------------------------------------------------

# Secondary region read replica
resource "google_sql_database_instance" "secondary_db_instance" {
  name                 = "app-db-instance-dr-secondary"
  database_version     = "MYSQL_8_0"
  region               = var.secondary_region
  master_instance_name = google_sql_database_instance.db_instance.name
  
  replica_configuration {
    failover_target = false
  }
  
  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"  # Cross-zone HA within secondary region
    
    backup_configuration {
      enabled            = false  # Backups cannot be enabled for read replicas
      binary_log_enabled = true   # Binary logging is still required for replication
    }
    
    ip_configuration {
      authorized_networks {
        name  = "Allowed Network"
        value = "0.0.0.0/0"
      }
    }
  }
  
  deletion_protection = var.deletion_protection
}

# -----------------------------------------------------------------------------
# SECONDARY REGION NETWORKING
# -----------------------------------------------------------------------------

# Secondary region instance groups
resource "google_compute_instance_group" "secondary_primary_group" {
  name      = "app-secondary-primary-group"
  zone      = var.secondary_primary_zone
  instances = []  # Empty by default, will be populated during failover
  
  named_port {
    name = "http8080"
    port = 8080
  }
  
  lifecycle {
    ignore_changes = [instances]
  }
}

resource "google_compute_instance_group" "secondary_standby_group" {
  name      = "app-secondary-standby-group"
  zone      = var.secondary_standby_zone
  instances = []
  
  named_port {
    name = "http8080"
    port = 8080
  }
  
  lifecycle {
    ignore_changes = [instances]
  }
}

# Note: We're using the existing backend service defined in networking.tf
# During failover/failback, we'll dynamically update the backend service configuration
# through Cloud Workflows and the dr-manual.sh script to route traffic to the appropriate region

# -----------------------------------------------------------------------------
# CONSISTENCY GROUPS AND REPLICATION
# -----------------------------------------------------------------------------

# Consistency group for application-consistent snapshots
resource "google_compute_resource_policy" "consistency_group" {
  name   = "app-consistency-group"
  region = var.region
  
  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "04:00"
      }
    }
    
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    
    snapshot_properties {
      guest_flush       = true
      storage_locations = ["us"]
      labels = {
        "purpose" = "consistency-group"
      }
    }
  }
}

# Cross-region replication policy
resource "google_compute_resource_policy" "cross_region_replication" {
  name   = "app-cross-region-replication"
  region = var.region
  
  snapshot_schedule_policy {
    schedule {
      hourly_schedule {
        hours_in_cycle = 1
        start_time     = "00:00"
      }
    }
    
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    
    snapshot_properties {
      guest_flush       = true
      storage_locations = ["us"]  # Multi-regional location covering both us-central1 and us-east1
      labels = {
        "purpose" = "cross-region-replication"
      }
    }
  }
}

# Attach policies to disks
resource "google_compute_disk_resource_policy_attachment" "primary_boot_consistency" {
  name   = google_compute_resource_policy.consistency_group.name
  disk   = google_compute_disk.primary_boot_disk.name
  zone   = var.primary_zone
}

resource "google_compute_region_disk_resource_policy_attachment" "regional_disk_consistency" {
  name   = google_compute_resource_policy.consistency_group.name
  disk   = google_compute_region_disk.regional_disk.name
  region = var.region
}

resource "google_compute_region_disk_resource_policy_attachment" "regional_disk_replication" {
  name   = google_compute_resource_policy.cross_region_replication.name
  disk   = google_compute_region_disk.regional_disk.name
  region = var.region
}

# -----------------------------------------------------------------------------
# CLOUD WORKFLOWS
# -----------------------------------------------------------------------------

# Multi-region failover workflow
resource "google_workflows_workflow" "multiregion_failover_workflow" {
  name            = "dr-multiregion-failover-workflow"
  region          = var.region
  description     = "Multi-region DR failover workflow"
  service_account = google_service_account.dr_service_account.email
  source_contents = file(var.multiregion_failover_workflow_path)
}

# Multi-region failback workflow
resource "google_workflows_workflow" "multiregion_failback_workflow" {
  name            = "dr-multiregion-failback-workflow"
  region          = var.secondary_region  # Deploy to secondary region
  description     = "Multi-region DR failback workflow"
  service_account = google_service_account.dr_service_account.email
  source_contents = file(var.multiregion_failback_workflow_path)
}
