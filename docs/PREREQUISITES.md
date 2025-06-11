# DR Module Prerequisites

This directory contains a script to set up the prerequisites for the DR active-passive complete zonal module. This script helps you enable the required Google Cloud APIs and set up the necessary permissions.

## Prerequisites Script (`setup_dr_prerequisites.sh`)

This script sets up all prerequisites for the DR solution, including enabling required APIs, creating a service account, and granting necessary permissions.

#### Usage

```bash
./setup_dr_prerequisites.sh [project-id] [service-account-name]
```

Example:
```bash
./setup_dr_prerequisites.sh my-project-id my-dr-service-account
```

If you don't provide a project ID, the script will use the default project from your gcloud configuration. If you don't provide a service account name, it will use "dr-service-account".

#### What it does

1. Enables all required Google Cloud APIs
2. Creates a service account (if it doesn't exist)
3. Grants the following IAM roles to the service account:
   - Compute Admin
   - Cloud SQL Admin
   - Secret Manager Admin
   - Storage Admin
   - Monitoring Admin
   - Cloud Scheduler Admin
   - Service Account User
   - Project IAM Admin
4. Provides instructions for using the service account with Terraform

## Using the Service Account with Terraform

After running the `setup_dr_prerequisites.sh` script, you can use the service account with Terraform in one of the following ways:

### Option 1: Create a key file

```bash
gcloud iam service-accounts keys create key.json --iam-account=SERVICE_ACCOUNT_EMAIL
export GOOGLE_APPLICATION_CREDENTIALS=key.json
```

Replace `SERVICE_ACCOUNT_EMAIL` with the email of the service account created by the script.

### Option 2: Update your terraform.tfvars file

Add the following to your `terraform.tfvars` file:

```hcl
# Service account configuration
service_account_email = "SERVICE_ACCOUNT_EMAIL"
```

Replace `SERVICE_ACCOUNT_EMAIL` with the email of the service account created by the script.

## Troubleshooting

If you encounter permission errors when running the scripts, make sure you have the necessary permissions to:

1. Enable APIs in the project
2. Create service accounts
3. Grant IAM roles

You may need to be a project owner or have the appropriate IAM roles to perform these actions.

If you're still encountering errors after running the scripts, check the error messages and ensure that all required APIs are enabled and the service account has the necessary permissions.
