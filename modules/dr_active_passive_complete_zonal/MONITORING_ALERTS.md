# Monitoring Alerts for DR Module

This document explains how to apply the monitoring alerts for the DR active-passive complete zonal module.

## Background

The monitoring configuration includes custom metrics and alert policies. However, there's a timing issue with custom metrics in Google Cloud: when a custom metric is first created, it takes up to 10 minutes to become available for use in alert policies.

To work around this issue, we've separated the alert policies that depend on custom metrics into a separate Terraform configuration file (`monitoring_alerts.tf`).

## How to Apply

Follow these steps to apply the monitoring alerts:

1. First, apply the main Terraform configuration:

   ```bash
   cd dr_active_passive_complete_zonal
   terraform init
   terraform apply
   ```

2. Wait for at least 10 minutes to allow the custom metrics to become available in Google Cloud.

3. Apply the monitoring alerts configuration:

   ```bash
   cd dr_active_passive_complete_zonal
   terraform init
   terraform apply -target=module.dr_complete.google_monitoring_alert_policy.app_error_alert
   ```

   Note: The monitoring_alerts.tf file is designed to be applied within the same module context as the main configuration. It uses the same provider configuration and variables.

## Troubleshooting

If you encounter the error "Cannot find metric(s) that match type", it means the custom metric is not yet available. Wait longer (up to 10 minutes) and try again.

You can check if the metric is available using the Google Cloud Console:

1. Go to Monitoring > Metrics Explorer
2. In the "Select a metric" field, search for "dr_app_errors"
3. If the metric appears in the list, it's available for use in alert policies

## Alert Policies

The following alert policies are defined in the `monitoring_alerts.tf` file:

- **DR Application Error Alert**: Triggers when the application logs contain a high number of error messages.

## Variables

The `monitoring_alerts.tf` file uses variables defined in the main module:

- `error_threshold`: The number of errors that trigger an alert

When applying the configuration separately, you need to ensure that the same variable values are used:

```bash
terraform apply -var="error_threshold=5"
```

Or create a terraform.tfvars file in the alerts directory with the same values as the main configuration.
