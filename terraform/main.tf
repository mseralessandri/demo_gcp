# =============================================================================
# DISASTER RECOVERY - ACTIVE-PASSIVE COMPLETE ZONAL
# =============================================================================
# This implements a comprehensive disaster recovery solution using 
# Google Cloud's native services for an active-passive zonal architecture.
#
# Resources are organized across multiple files:
# - providers.tf: Terraform and provider configuration
# - variables.tf: Variable declarations
# - terraform.tfvars: Variable values
# - database.tf: Cloud SQL database resources
# - compute.tf: VM instances and storage
# - networking.tf: VPC and firewall rules
# - monitoring.tf: Monitoring and alerting
# - workflows.tf: DR workflows
# - outputs.tf: Output values
