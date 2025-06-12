# =============================================================================
# MONITORING ALERTS FOR DR ACTIVE-PASSIVE COMPLETE ZONAL 
# =============================================================================
# -----------------------------------------------------------------------------

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


