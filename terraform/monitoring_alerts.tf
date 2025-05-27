# =============================================================================
# MONITORING ALERTS FOR DR ACTIVE-PASSIVE COMPLETE ZONAL MODULE
# =============================================================================
# This file contains alert policies that depend on custom metrics.
# Apply this configuration after the main configuration and after waiting
# for the custom metrics to become available (about 10 minutes).

# Note: The required providers are already defined in the main.tf file
# This file should be applied in the same module context

# -----------------------------------------------------------------------------
# ALERT POLICIES
# -----------------------------------------------------------------------------
# Alert policies that depend on custom metrics

# Application error alert
resource "google_monitoring_alert_policy" "app_error_alert" {
  display_name = "DR Application Error Alert"
  combiner     = "OR"
  
  # Add explicit dependency
  depends_on = [google_logging_metric.app_error_metric]
  
  conditions {
    display_name = "High Error Rate"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/dr_app_errors_complete\" resource.type=\"gce_instance\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  
  # Directly reference the notification channel ID
  notification_channels = [google_monitoring_notification_channel.email.id]
  
  # Add lifecycle rule
  lifecycle {
    create_before_destroy = false
  }
}

# -----------------------------------------------------------------------------
# VARIABLES
# -----------------------------------------------------------------------------
# Variables needed for this configuration

# Note: The error_threshold variable is already defined in the main variables.tf file
# and will be passed to this configuration when applied.
