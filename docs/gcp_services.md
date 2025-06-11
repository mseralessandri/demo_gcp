# Google Cloud Platform Services Used in This Project

This document provides an overview of all Google Cloud Platform (GCP) services used in this disaster recovery implementation project, including their purpose, how they're used, and links to official documentation.

## Compute Services

### Compute Engine

**Description**: Google Compute Engine (GCE) is an Infrastructure as a Service (IaaS) offering that provides virtual machines running in Google's data centers.

**Usage in this project**: 
- Primary and standby virtual machines for the application
- Hosts the Go web application
- Configured with different zones for disaster recovery

**How it's implemented**:
```hcl
resource "google_compute_instance" "primary_vm" {
  name         = "app-web-server-dr-primary"
  machine_type = var.vm_machine_type
  zone         = var.primary_zone
  # ...
}

resource "google_compute_instance" "standby_vm" {
  name         = "app-web-server-dr-standby"
  machine_type = var.vm_machine_type
  zone         = var.standby_zone
  # ...
}
```

**Documentation**: [Google Compute Engine Documentation](https://cloud.google.com/compute/docs)

## Storage Services

### Persistent Disk

**Description**: Persistent Disk is a durable network storage device that virtual machines can access like a physical disk.

**Usage in this project**:
- Boot disks for primary and standby VMs
- Snapshot-based replication for disaster recovery

**How it's implemented**:
```hcl
resource "google_compute_disk" "primary_boot_disk" {
  name  = "app-primary-boot-disk"
  zone  = var.primary_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
}

resource "google_compute_disk" "standby_boot_disk" {
  name  = "app-standby-boot-disk"
  zone  = var.standby_zone
  image = var.vm_image
  size  = var.boot_disk_size_gb
}
```

**Documentation**: [Persistent Disk Documentation](https://cloud.google.com/compute/docs/disks)

### Regional Persistent Disk

**Description**: Regional Persistent Disk replicates data synchronously between two zones in the same region, providing higher availability for storage.

**Usage in this project**:
- Synchronous data replication between primary and standby zones
- Provides zero RPO (Recovery Point Objective) for critical data
- Mounted at `/mnt/regional-disk` for application data storage

**How it's implemented**:
```hcl
resource "google_compute_region_disk" "regional_disk" {
  name                      = "app-regional-disk"
  type                      = "pd-balanced"
  region                    = var.region
  size                      = var.disk_size_gb
  replica_zones             = [var.primary_zone, var.standby_zone]
  physical_block_size_bytes = 4096
}
```

**Documentation**: [Regional Persistent Disk Documentation](https://cloud.google.com/compute/docs/disks/regional-persistent-disk)

### Compute Engine Snapshots

**Description**: Snapshots are point-in-time copies of Persistent Disks that can be used for backup or to create new disks.

**Usage in this project**:
- Backup mechanism for boot disks and regional disks
- Used during failover to create new boot disks from snapshots
- Provides non-zero RPO disaster recovery capability

**How it's implemented**:
```bash
# In dr_demo_test.sh
gcloud compute snapshots create $SNAPSHOT_NAME \
  --source-disk=app-primary-boot-disk \
  --source-disk-zone=us-central1-a \
  --description="Automatic snapshot of boot disk for DR testing"
```

**Documentation**: [Compute Engine Snapshots Documentation](https://cloud.google.com/compute/docs/disks/create-snapshots)

## Database Services

### Cloud SQL

**Description**: Cloud SQL is a fully-managed database service that makes it easy to set up, maintain, and administer relational databases on Google Cloud.

**Usage in this project**:
- Hosts the application database with high availability configuration
- Configured with automatic failover between zones
- Provides point-in-time recovery capabilities

**How it's implemented**:
```hcl
resource "google_sql_database_instance" "db_instance" {
  name             = "app-db-instance-dr"
  database_version = "MYSQL_8_0"
  region           = var.region
  
  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"  # Enables cross-zone replication
    
    backup_configuration {
      enabled            = true
      binary_log_enabled = true  # Enables point-in-time recovery
      # ...
    }
  }
}
```

**Documentation**: [Cloud SQL Documentation](https://cloud.google.com/sql/docs)

## Networking Services

### Virtual Private Cloud (VPC)

**Description**: Google Virtual Private Cloud (VPC) provides networking functionality for Google Cloud resources, including Compute Engine VMs.

**Usage in this project**:
- Network connectivity for VMs and databases
- Default VPC network is used for simplicity

**How it's implemented**:
```hcl
network_interface {
  network = "default"
  access_config {}
}
```

**Documentation**: [VPC Documentation](https://cloud.google.com/vpc/docs)

### Cloud Load Balancing

**Description**: Google Cloud Load Balancing is a fully distributed, software-defined managed service for all your traffic.

**Usage in this project**:
- Distributes traffic between primary and standby VMs
- Provides seamless failover during disaster recovery
- Supports both HTTP and HTTPS traffic

**How it's implemented**:
```hcl
# Implementation details in networking.tf
# Includes HTTP and HTTPS load balancers, health checks, and backend services
```

**Documentation**: [Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)

### Cloud DNS

**Description**: Google Cloud DNS is a scalable, reliable, and managed authoritative Domain Name System (DNS) service.

**Usage in this project**:
- DNS resolution for the application
- Maps domain names to load balancer IP addresses

**Documentation**: [Cloud DNS Documentation](https://cloud.google.com/dns/docs)

## Security Services

### Secret Manager

**Description**: Secret Manager is a secure and convenient storage system for API keys, passwords, certificates, and other sensitive data.

**Usage in this project**:
- Stores database credentials securely
- Accessed by application VMs to retrieve database connection information

**How it's implemented**:
```hcl
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

resource "google_secret_manager_secret_version" "db_credentials_value" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    user     = var.db_user
    password = var.db_password
  })
}
```

**Documentation**: [Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)

### Identity and Access Management (IAM)

**Description**: IAM lets you grant granular access to specific Google Cloud resources and prevents unwanted access to other resources.

**Usage in this project**:
- Service account permissions for VMs to access other GCP services
- Role-based access control for Secret Manager and Cloud SQL

**How it's implemented**:
```hcl
resource "google_service_account" "dr_service_account" {
  account_id   = "dr-service-account"
  display_name = "DR Service Account"
}

resource "google_project_iam_binding" "secret_manager_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_service_account.dr_service_account.email}"
  ]
}
```

**Documentation**: [IAM Documentation](https://cloud.google.com/iam/docs)

## Monitoring and Management Services

### Cloud Monitoring

**Description**: Cloud Monitoring provides visibility into the performance, uptime, and overall health of cloud-powered applications.

**Usage in this project**:
- Monitors VM and database health
- Tracks custom metrics for disaster recovery testing
- Provides alerts for potential issues

**How it's implemented**:
```hcl
# Implementation in monitoring.tf and monitoring_alerts.tf
```

**Documentation**: [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)

### Cloud Logging

**Description**: Cloud Logging allows you to store, search, analyze, monitor, and alert on log data and events from Google Cloud and other sources.

**Usage in this project**:
- Collects and analyzes logs from VMs and databases
- Used for troubleshooting during disaster recovery events
- Integrated with monitoring for comprehensive observability

**How it's implemented**:
```bash
# In dr_demo_test.sh
ERROR_COUNT=$(gcloud logging read "resource.type=gce_instance AND textPayload=~\"Error|ERROR|error\"" --limit=10 --format="value(timestamp)" | wc -l)
```

**Documentation**: [Cloud Logging Documentation](https://cloud.google.com/logging/docs)

## Deployment and Infrastructure Management

### Terraform

**Description**: While not a GCP service, Terraform is used extensively in this project for infrastructure as code.

**Usage in this project**:
- Defines and provisions all GCP resources
- Manages infrastructure state
- Enables repeatable deployments

**How it's implemented**:
- Multiple Terraform files organized in modules
- Variables for configuration
- Outputs for resource information

**Documentation**: [Terraform Documentation](https://www.terraform.io/docs)

## Disaster Recovery Architecture

This project implements an active-passive disaster recovery architecture with the following characteristics:

1. **Primary Zone**: Contains the active VM and database instance
2. **Standby Zone**: Contains the standby VM (stopped by default) and database replica
3. **Synchronous Replication**: Regional disk provides synchronous data replication between zones
4. **Automated Failover**: Scripts handle the failover process when the primary zone fails
5. **Load Balancing**: Directs traffic to the active instance, whether primary or standby

The implementation provides:
- Near-zero RPO (Recovery Point Objective) using regional disks and database replication
- Low RTO (Recovery Time Objective) through automated failover procedures
- Testing capabilities to validate the disaster recovery process

**Documentation**: [Google Cloud Disaster Recovery Planning Guide](https://cloud.google.com/architecture/dr-scenarios-planning-guide)
