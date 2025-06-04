# =============================================================================
# BACKUP CONFIGURATION FOR DR ACTIVE-PASSIVE COMPLETE ZONAL MODULE
# =============================================================================
# This file contains the backup and recovery resources for the DR solution,
# including disk snapshots and database backups.

# -----------------------------------------------------------------------------
# DISK SNAPSHOTS
# -----------------------------------------------------------------------------
# Snapshot schedule for the regional disk

# Snapshot schedule policy
resource "google_compute_resource_policy" "snapshot_schedule" {
  name   = "app-snapshot-schedule"
  region = var.region
  
  snapshot_schedule_policy {
    schedule {
      hourly_schedule {
        hours_in_cycle = 1  # Take a snapshot every hour
        start_time     = "00:00"
      }
    }
    
    retention_policy {
      max_retention_days    = 7  # Keep snapshots for 7 days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    
    snapshot_properties {
      storage_locations = [var.region]
      guest_flush       = true  # Ensures data consistency
    }
  }
}

# Attach the snapshot schedule to the regional disk
resource "google_compute_region_disk_resource_policy_attachment" "snapshot_attachment" {
  name   = google_compute_resource_policy.snapshot_schedule.name
  disk   = google_compute_region_disk.regional_disk.name
  region = var.region
}

# -----------------------------------------------------------------------------
# DATABASE BACKUPS
# -----------------------------------------------------------------------------
# Cloud SQL backups are configured in the main.tf file as part of the
# database instance configuration. This includes:
# - Automated backups
# - Point-in-time recovery
# - Transaction log retention

# -----------------------------------------------------------------------------
# BACKUP STORAGE
# -----------------------------------------------------------------------------
# Storage bucket for backup metadata and test results

resource "google_storage_bucket" "dr_backup_bucket" {
  name     = "${var.project_id}-dr-backups"
  location = var.region
  
  # Configure lifecycle rules for automatic cleanup
  lifecycle_rule {
    condition {
      age = 30  # days
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for added protection
  versioning {
    enabled = true
  }
}

# IAM binding for the backup bucket
resource "google_storage_bucket_iam_binding" "backup_bucket_binding" {
  bucket = google_storage_bucket.dr_backup_bucket.name
  role   = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.dr_service_account.email}"
  ]
}

