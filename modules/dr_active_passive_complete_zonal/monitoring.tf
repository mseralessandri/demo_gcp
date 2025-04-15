# =============================================================================
# MONITORING CONFIGURATION FOR DR ACTIVE-PASSIVE COMPLETE ZONAL MODULE
# =============================================================================
# This file contains the monitoring and alerting resources for the DR solution,
# using a hybrid approach that leverages both default GCP dashboards and
# custom metrics.

# -----------------------------------------------------------------------------
# NOTIFICATION CHANNELS
# -----------------------------------------------------------------------------
# Email notification channel for alerts

resource "google_monitoring_notification_channel" "email" {
  display_name = "DR Email Notification Channel"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
}

# -----------------------------------------------------------------------------
# ALERT POLICIES
# -----------------------------------------------------------------------------
# Alert policies for critical DR components

# VM uptime alert
resource "google_monitoring_alert_policy" "vm_uptime_alert" {
  display_name = "DR Primary VM Down Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "VM is down"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/uptime\" resource.type=\"gce_instance\" resource.label.\"instance_id\"=\"${google_compute_instance.primary_vm.instance_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_LT"
      threshold_value = 60  # Alert if VM uptime is less than 60 seconds
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Database uptime alert
resource "google_monitoring_alert_policy" "db_uptime_alert" {
  display_name = "DR Database Uptime Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Database is down"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/up\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"${google_sql_database_instance.db_instance.name}\""
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

# Database replication lag alert
resource "google_monitoring_alert_policy" "db_replication_lag_alert" {
  display_name = "DR Database Replication Lag Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "High replication lag"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/replication/replica_lag\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"${google_sql_database_instance.db_instance.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.replication_lag_threshold_ms  # Alert if replication lag exceeds threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Application error alert
resource "google_logging_metric" "app_error_metric" {
  name        = "dr_app_errors_complete"
  filter      = "resource.type=\"gce_instance\" AND (resource.labels.instance_id=\"${google_compute_instance.primary_vm.instance_id}\" OR resource.labels.instance_id=\"${google_compute_instance.standby_vm.instance_id}\") AND textPayload=~\"Error|ERROR|error|Exception|EXCEPTION|exception\""
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
  
  label_extractors = {
    "severity" = "REGEXP_EXTRACT(textPayload, \"(ERROR|WARNING|INFO)\")"
  }
  
  # Add lifecycle rule
  lifecycle {
    create_before_destroy = true
  }
}

# Note: The alert policy has been moved to a separate file (monitoring_alerts.tf)
# Apply the main configuration first, wait 10 minutes for the metric to be available,
# then apply the monitoring_alerts.tf configuration.

# -----------------------------------------------------------------------------
# CUSTOM METRICS
# -----------------------------------------------------------------------------
# Custom metrics for DR testing and monitoring

# Recovery time metric descriptor
resource "google_monitoring_metric_descriptor" "recovery_time" {
  description   = "Time taken to complete DR failover"
  display_name  = "DR Recovery Time"
  type          = "custom.googleapis.com/dr_test/recovery_time"
  metric_kind   = "GAUGE"
  value_type    = "DOUBLE"
  unit          = "s"
  
  labels {
    key         = "test_type"
    value_type  = "STRING"
    description = "Type of DR test"
  }
}

# Success rate metric descriptor
resource "google_monitoring_metric_descriptor" "success_rate" {
  description   = "Success rate of DR tests"
  display_name  = "DR Test Success Rate"
  type          = "custom.googleapis.com/dr_test/success_rate"
  metric_kind   = "GAUGE"
  value_type    = "DOUBLE"
  unit          = "1"
  
  labels {
    key         = "test_type"
    value_type  = "STRING"
    description = "Type of DR test"
  }
}

# -----------------------------------------------------------------------------
# CUSTOM DASHBOARD
# -----------------------------------------------------------------------------
# Custom dashboard for DR monitoring using the hybrid approach

resource "google_monitoring_dashboard" "dr_dashboard" {
  dashboard_json = <<EOF
{
  "displayName": "DR Health Dashboard",
  "gridLayout": {
    "widgets": [
      {
        "title": "Primary VM Status",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"compute.googleapis.com/instance/uptime\" resource.type=\"gce_instance\" resource.label.\"instance_id\"=\"${google_compute_instance.primary_vm.instance_id}\"",
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
        "title": "Standby VM Status",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"compute.googleapis.com/instance/uptime\" resource.type=\"gce_instance\" resource.label.\"instance_id\"=\"${google_compute_instance.standby_vm.instance_id}\"",
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
        "title": "Database Replication Lag",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"cloudsql.googleapis.com/database/replication/replica_lag\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"${google_sql_database_instance.db_instance.name}\"",
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
        "title": "DR Test Results",
        "scorecard": {
          "timeSeriesQuery": {
            "timeSeriesFilter": {
              "filter": "metric.type=\"custom.googleapis.com/dr_test/success_rate\"",
              "aggregation": {
                "alignmentPeriod": "604800s",
                "perSeriesAligner": "ALIGN_MEAN"
              }
            }
          },
          "thresholds": [
            {
              "value": 0.9,
              "color": "RED",
              "direction": "BELOW"
            },
            {
              "value": 0.99,
              "color": "YELLOW",
              "direction": "BELOW"
            }
          ],
          "sparkChartView": {
            "sparkChartType": "SPARK_LINE"
          }
        }
      },
      {
        "title": "Recovery Time",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"custom.googleapis.com/dr_test/recovery_time\"",
                "aggregation": {
                  "alignmentPeriod": "604800s",
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

# -----------------------------------------------------------------------------
# SCHEDULED MONITORING
# -----------------------------------------------------------------------------
# Cloud Scheduler jobs for regular monitoring checks

# Weekly status check
resource "google_cloud_scheduler_job" "weekly_status_check" {
  name        = "dr-weekly-status-check"
  description = "Weekly DR status check"
  schedule    = "0 8 * * 1"  # Every Monday at 8 AM
  
  http_target {
    uri         = "https://cloudfunction-placeholder-url/runDrTest"
    http_method = "POST"
    body        = base64encode("{\"testType\": \"status\"}")
    
    # In a real implementation, this would point to an actual Cloud Function
    # that executes the DR test script
  }
}

# Monthly backup test
resource "google_cloud_scheduler_job" "monthly_backup_test" {
  name        = "dr-monthly-backup-test"
  description = "Monthly DR backup test"
  schedule    = "0 2 1 * *"  # 1st day of each month at 2 AM
  
  http_target {
    uri         = "https://cloudfunction-placeholder-url/runDrTest"
    http_method = "POST"
    body        = base64encode("{\"testType\": \"backup\"}")
  }
}

# Quarterly failover test (requires approval)
resource "google_cloud_scheduler_job" "quarterly_failover_test" {
  name        = "dr-quarterly-failover-test"
  description = "Quarterly DR failover test (requires approval)"
  schedule    = "0 1 1 */3 *"  # 1st day of every 3rd month at 1 AM
  
  http_target {
    uri         = "https://cloudfunction-placeholder-url/runDrTest"
    http_method = "POST"
    body        = base64encode("{\"testType\": \"test-all\", \"requireApproval\": true}")
  }
}
