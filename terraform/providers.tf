# =============================================================================
# TERRAFORM PROVIDERS CONFIGURATION
# =============================================================================

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
