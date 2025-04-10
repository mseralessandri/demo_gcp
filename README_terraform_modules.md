# Terraform Modules for Infrastructure Management

This repository contains Terraform modules for managing infrastructure with and without disaster recovery capabilities.

## Directory Structure

```
/
├── modules/
│   ├── base/                  # Base infrastructure module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── dr_active_passive_warm_zonal/                    # Disaster recovery module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── base/                      # Base infrastructure (without DR)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
└── dr_active_passive_warm_zonal/    # DR infrastructure (with active-passive zonal warm standby)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

## Modules

### Base Module

The base module (`modules/base`) defines the base infrastructure components:

- VM instance for the web application
- Cloud SQL instance for the database
- Service account with appropriate permissions
- Secret Manager for storing credentials
- Firewall rules for network access

### DR Module

The DR module (`modules/dr_active_passive_warm_zonal`) defines the disaster recovery components:

- Regional persistent disk with synchronous replication
- Regional Cloud SQL instance with automatic failover
- Standby VM in a different zone
- Monitoring and alerting for DR components
- Custom dashboard for DR monitoring

## Root Modules

### Base Infrastructure

The base infrastructure (`base/`) uses only the base module to deploy the application without disaster recovery capabilities.

To deploy the base infrastructure:

```bash
cd base
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to set your values
terraform init
terraform apply
```

### DR Infrastructure

The DR infrastructure (`dr_active_passive_warm_zonal/`) uses both the base and DR modules to deploy the application with disaster recovery capabilities.

To deploy the DR infrastructure:

```bash
cd dr_active_passive_warm_zonal
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to set your values
terraform init
terraform apply
```

## Disaster Recovery Testing

A testing script (`dr_test_script.sh`) is provided to test the disaster recovery functionality:

```bash
# Test failover to DR zone
./dr_test_script.sh failover

# Test failback to primary zone
./dr_test_script.sh failback

# Check status of DR environment
./dr_test_script.sh status
```

## Important Notes

1. **Only deploy one version at a time**: Either deploy the base infrastructure or the DR infrastructure, not both simultaneously.

2. **State files**: Each root module maintains its own state file. If you switch between versions, you may need to destroy the resources from one version before deploying the other.

3. **Sensitive variables**: The `db_password` and `db_root_password` variables are marked as sensitive. Set these in your `terraform.tfvars` file or through environment variables.

4. **Path references**: The paths to `setup.sh` and `database.sql` are relative to the root module directory. Adjust these if needed.

5. **Customization**: Review and adjust the variables in `terraform.tfvars` to match your requirements before deploying.
