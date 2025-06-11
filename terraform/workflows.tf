# =============================================================================
# WORKFLOW CONFIGURATION FOR DR ACTIVE-PASSIVE COMPLETE ZONAL MODULE
# =============================================================================
# This file contains the Google Cloud Workflows definitions for disaster recovery
# operations, including failover and failback processes.

# -----------------------------------------------------------------------------
# SERVICE ACCOUNT
# -----------------------------------------------------------------------------
# Service account for workflows to access GCP resources

resource "google_service_account" "dr_workflow_sa" {
  account_id   = "dr-workflow-sa"
  display_name = "DR Workflow Service Account"
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "workflow_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.dr_workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_sql_admin" {
  project = var.project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.dr_workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_monitoring_admin" {
  project = var.project_id
  role    = "roles/monitoring.admin"
  member  = "serviceAccount:${google_service_account.dr_workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dr_workflow_sa.email}"
}

# -----------------------------------------------------------------------------
# FAILOVER WORKFLOW
# -----------------------------------------------------------------------------
# Workflow that orchestrates the failover process from primary to standby zone

resource "google_workflows_workflow" "dr_failover" {
  name            = "dr-failover-workflow"
  region          = var.region
  description     = "Disaster recovery failover workflow"
  service_account = google_service_account.dr_workflow_sa.id
  
  source_contents = file(var.dr_failover_workflow_path)
}

# -----------------------------------------------------------------------------
# FAILBACK WORKFLOW
# -----------------------------------------------------------------------------
# Workflow that orchestrates the failback process from standby to primary zone

resource "google_workflows_workflow" "dr_failback" {
  name            = "dr-failback-workflow"
  region          = var.region
  description     = "Disaster recovery failback workflow"
  service_account = google_service_account.dr_workflow_sa.id
  
  source_contents = file(var.dr_failback_workflow_path)
}
