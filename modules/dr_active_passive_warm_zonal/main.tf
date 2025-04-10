# =============================================================================
# DISASTER RECOVERY MODULE - ACTIVE-PASSIVE WARM STANDBY (ZONAL)
# =============================================================================
# This module implements a zonal disaster recovery solution using an 
# active-passive warm standby approach within a single GCP region.

# -----------------------------------------------------------------------------
# STORAGE RESOURCES
# -----------------------------------------------------------------------------
# The DR solution uses separate disks for primary and standby VMs with
# snapshot-based replication for data protection.

# Primary VM disk
resource "google_compute_disk" "primary_disk" {
  name  = "app-web-server-dr-primary-disk"
  type  = "pd-balanced"  # Balance of performance and recovery speed
  zone  = var.primary_zone
  size  = var.disk_size_gb
  image = var.vm_image
}

# Snapshot schedule for the primary disk
# Creates hourly snapshots to protect against data loss
resource "google_compute_resource_policy" "primary_disk_snapshot_schedule" {
  name   = "primary-disk-snapshot-schedule"
  region = var.region
  
  snapshot_schedule_policy {
    schedule {
      # Hourly snapshots provide RPO of 1 hour
      hourly_schedule {
        hours_in_cycle = 1
        start_time     = "00:00"
      }
    }
    
  retention_policy {
    # 1-day retention as per requirement
    max_retention_days    = 1
    on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
  }
    
    snapshot_properties {
      storage_locations = [var.region]
      guest_flush       = true  # Ensures data consistency
    }
  }
}

# Attach the snapshot schedule to the primary disk
resource "google_compute_disk_resource_policy_attachment" "primary_disk_snapshot_attachment" {
  name = google_compute_resource_policy.primary_disk_snapshot_schedule.name
  disk = google_compute_disk.primary_disk.name
  zone = var.primary_zone
}

# Standby VM disk
resource "google_compute_disk" "standby_disk" {
  name  = "app-web-server-dr-standby-disk"
  type  = "pd-balanced"
  zone  = var.standby_zone
  size  = var.disk_size_gb
  image = var.vm_image  # Initially created from the same image
}

# Create a regional Cloud SQL instance with automatic failover
resource "google_sql_database_instance" "app_db_instance_dr" {
  name             = "app-db-instance-dr"
  database_version = "MYSQL_8_0"
  region           = var.region
  deletion_protection = false

  root_password = var.db_root_password

  settings {
    tier = var.db_tier
    availability_type = "REGIONAL"  # This enables cross-zone replication

    backup_configuration {
      enabled            = true
      binary_log_enabled = true  # Enables point-in-time recovery
      start_time         = var.backup_start_time
    }

    ip_configuration {
      authorized_networks {
        name  = "Allowed Network"
        value = "0.0.0.0/0"
      }
    }
  }
}

# Create the database within the instance
resource "google_sql_database" "app_database_dr" {
  name     = "dr_demo"
  instance = google_sql_database_instance.app_db_instance_dr.name
  
  # Initialize the database using the database.sql file
  provisioner "local-exec" {
    command = <<-EOT
      # Create a temporary SQL file with the variables replaced
      cat ${var.database_sql_path} | sed -e 's/$${db_user}/${var.db_user}/g' -e 's/$${db_password}/${var.db_password}/g' > /tmp/init_db_dr.sql
      
      # Execute the SQL script against the Cloud SQL instance
      mysql -h ${google_sql_database_instance.app_db_instance_dr.public_ip_address} -u root -p${var.db_root_password} < /tmp/init_db_dr.sql
      
      # Remove the temporary file
      rm /tmp/init_db_dr.sql
    EOT
  }
}

# Create the database user
resource "google_sql_user" "app_db_user_dr" {
  name     = "dr_demo_user"
  instance = google_sql_database_instance.app_db_instance_dr.name
  password = var.db_password
  host     = "%"  # Allow connections from any host
}

# Create a service account for the VM
resource "google_service_account" "app_service_account_dr" {
  account_id   = "app-service-account-dr"
  display_name = "App Service Account for DR"
}

# Grant the service account access to Secret Manager
resource "google_project_iam_binding" "secret_manager_access_dr" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_service_account.app_service_account_dr.email}"
  ]
}

# Grant the service account access to Cloud SQL
resource "google_project_iam_binding" "cloud_sql_access_dr" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  members = [
    "serviceAccount:${google_service_account.app_service_account_dr.email}"
  ]
}

# Grant the service account access to view Cloud SQL instances
resource "google_project_iam_binding" "cloud_sql_viewer_dr" {
  project = var.project_id
  role    = "roles/cloudsql.viewer"
  members = [
    "serviceAccount:${google_service_account.app_service_account_dr.email}"
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
resource "google_secret_manager_secret_version" "db_credentials_value_dr" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    user     = var.db_user
    password = var.db_password
  })
  
  # Ensure the database is created before the secret
  depends_on = [
    google_sql_database_instance.app_db_instance_dr,
    google_sql_database.app_database_dr,
    google_sql_user.app_db_user_dr
  ]
}

# Create the primary VM in the primary zone
resource "google_compute_instance" "app_web_server_dr" {
  name         = "app-web-server-dr"
  machine_type = var.vm_machine_type
  zone         = var.primary_zone
  tags         = ["web"]
  
  depends_on = [
    google_sql_database_instance.app_db_instance_dr,
    google_secret_manager_secret_version.db_credentials_value_dr
  ]

  boot_disk {
    source = google_compute_disk.primary_disk.id
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.app_service_account_dr.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.app_db_instance_dr.public_ip_address
    GO_VERSION = var.go_version
  })
}

# Create the DR VM in the standby zone (stopped)
resource "google_compute_instance" "app_web_server_dr_standby" {
  name         = "app-web-server-dr-standby"
  machine_type = var.vm_machine_type
  zone         = var.standby_zone
  tags         = ["web"]
  
  depends_on = [
    google_sql_database_instance.app_db_instance_dr,
    google_secret_manager_secret_version.db_credentials_value_dr
  ]

  boot_disk {
    source = google_compute_disk.standby_disk.id
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.app_service_account_dr.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile(var.setup_script_path, {
    db_host = google_sql_database_instance.app_db_instance_dr.public_ip_address
    GO_VERSION = var.go_version
  })
  
  # Stop the VM after creation
  provisioner "local-exec" {
    command = "gcloud compute instances stop ${self.name} --zone=${self.zone} --quiet"
    when    = create
  }
  
  # Prevent Terraform from trying to start the VM on subsequent applies
  lifecycle {
    ignore_changes = [desired_status]
  }
}

# Create a health check for the application
resource "google_compute_region_health_check" "app_health_check" {
  name               = "app-health-check"
  region             = var.region
  check_interval_sec = 5
  timeout_sec        = 5
  
  http_health_check {
    port         = 8080
    request_path = "/web"
  }
}

# Create instance groups for load balancing
resource "google_compute_instance_group" "primary_group" {
  name      = "app-primary-group"
  zone      = var.primary_zone
  instances = [google_compute_instance.app_web_server_dr.id]
  
  # Prevent Terraform from trying to update the instance group if the VM is stopped
  lifecycle {
    ignore_changes = [instances]
  }
}

resource "google_compute_instance_group" "dr_group" {
  name      = "app-dr-group"
  zone      = var.standby_zone
  instances = []  # Empty list - no instances in this group initially
}

# Create a backend service for load balancing
resource "google_compute_region_backend_service" "app_backend" {
  name                  = "app-backend"
  region                = var.region
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [google_compute_region_health_check.app_health_check.id]
  
  backend {
    group = google_compute_instance_group.primary_group.id
    balancing_mode = "UTILIZATION"
    # capacity_scaler defines the fraction of the load that this backend can handle
    # 1.0 means 100% of capacity, 0.5 would mean 50% of capacity
    # Required when using INTERNAL_MANAGED load balancing with UTILIZATION mode
    capacity_scaler = 1.0
  }
  
  backend {
    group = google_compute_instance_group.dr_group.id
    balancing_mode = "UTILIZATION"
    # Set capacity for the standby backend
    # During normal operation, this backend will receive traffic only if the primary fails
    capacity_scaler = 1.0
  }
}

# Create a firewall rule to allow HTTP, HTTPS, and application traffic to the web server
resource "google_compute_firewall" "allow_http_dr" {
  name    = "allow-http-dr"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

# Create a firewall rule to allow SSH traffic for management
resource "google_compute_firewall" "allow_ssh_dr" {
  name    = "allow-ssh-dr"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

# Observability Components

# Email notification channel
resource "google_monitoring_notification_channel" "email" {
  display_name = "DR Email Notification Channel"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
}

# Alert policy for VM instance status
resource "google_monitoring_alert_policy" "vm_status_alert" {
  display_name = "DR VM Status Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "VM Status"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/uptime\" resource.type=\"gce_instance\" resource.label.\"instance_id\"=\"${google_compute_instance.app_web_server_dr.instance_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_LT"
      threshold_value = 60  # Alert if VM uptime is less than 60 seconds (indicating a restart or failure)
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# -----------------------------------------------------------------------------
# MONITORING & ALERTING
# -----------------------------------------------------------------------------
# Comprehensive monitoring ensures quick detection of issues

# Database uptime monitoring
# Monitors database availability for quick detection of failures
resource "google_monitoring_alert_policy" "db_uptime_alert" {
  display_name = "DR Database Uptime Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Database Availability"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/up\" resource.type=\"cloudsql_database\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1  # Alert if database is down (0)
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Database CPU monitoring
# Helps detect performance issues that could affect recovery
resource "google_monitoring_alert_policy" "db_cpu_alert" {
  display_name = "DR Database CPU Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "High CPU Usage"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8  # Alert if CPU usage > 80%
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Log-based alerting for application errors
resource "google_logging_metric" "app_error_metric" {
  name        = "dr_app_errors"
  filter      = "resource.type=\"gce_instance\" AND (resource.labels.instance_id=\"${google_compute_instance.app_web_server_dr.instance_id}\" OR resource.labels.instance_id=\"${google_compute_instance.app_web_server_dr_standby.instance_id}\") AND textPayload=~\"Error|ERROR|error|Exception|EXCEPTION|exception\""
  description = "Count of error messages in DR application logs"
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key         = "severity"
      value_type  = "STRING"
      description = "Error severity"
    }
  }
  
  # Label extractors define how to extract label values from log entries
  # This extractor uses a regular expression to extract the severity level from the log message
  # It looks for ERROR, WARNING, or INFO in the log message and assigns it to the "severity" label
  # This is required when defining labels in the metric descriptor
  label_extractors = {
    "severity" = "REGEXP_EXTRACT(textPayload, \"(ERROR|WARNING|INFO)\")"
  }
}

resource "google_monitoring_alert_policy" "app_error_alert" {
  display_name = "DR Application Error Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "High Error Rate"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_error_metric.name}\" resource.type=\"gce_instance\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Custom dashboard for DR monitoring
resource "google_monitoring_dashboard" "dr_dashboard" {
  dashboard_json = <<EOF
{
  "displayName": "Disaster Recovery Dashboard",
  "gridLayout": {
    "widgets": [
      {
        "title": "VM Uptime",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"compute.googleapis.com/instance/uptime\" resource.type=\"gce_instance\" resource.label.\"instance_id\"=\"${google_compute_instance.app_web_server_dr.instance_id}\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "plotType": "LINE"
          }]
        }
      },
      {
        "title": "Database Uptime",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"cloudsql.googleapis.com/database/up\" resource.type=\"cloudsql_database\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "plotType": "LINE"
          }]
        }
      },
      {
        "title": "Database CPU Utilization",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "plotType": "LINE"
          }]
        }
      },
      {
        "title": "VM CPU Utilization",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\" resource.label.\"instance_id\"=\"${google_compute_instance.app_web_server_dr.instance_id}\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "plotType": "LINE"
          }]
        }
      }
    ]
  }
}
EOF
}
