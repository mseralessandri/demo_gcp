# DR Active-Passive Complete Zonal Implementation

This directory contains the implementation of the DR active-passive complete zonal module, which provides a comprehensive disaster recovery solution using Google Cloud's native services.

## Architecture

![DR Architecture](architecture_diagram.png)

The architecture includes:

- **Primary VM** in the primary zone (us-central1-a)
- **Standby VM** in the standby zone (us-central1-c)
- **Regional Persistent Disk** for synchronous replication between zones
- **Cloud SQL with HA** for database high availability with binary logging for point-in-time recovery
- **Load Balancer** for traffic routing
- **Backup and Recovery** capabilities
- **Monitoring and Alerting** with a hybrid approach

## Setup Instructions

### Prerequisites

- Google Cloud project with billing enabled
- Terraform installed
- gcloud CLI configured
- Required Google Cloud APIs enabled (see [PREREQUISITES.md](PREREQUISITES.md))
- Service account with necessary permissions (see [PREREQUISITES.md](PREREQUISITES.md))

You can use the provided script to set up all prerequisites:
```bash
# Complete script to set up all prerequisites
./setup_dr_prerequisites.sh your-project-id
```

### Deployment Steps

1. **Initialize Terraform**:
   ```bash
   cd dr_active_passive_complete_zonal
   terraform init
   ```

2. **Configure Variables**:
   Edit `terraform.tfvars` with your specific values:
   ```hcl
   project_id = "your-project-id"
   region = "us-central1"
   primary_zone = "us-central1-a"
   standby_zone = "us-central1-c"
   notification_email = "your-email@example.com"
   db_password = "your-secure-password"
   ```

3. **Deploy the Infrastructure**:
   ```bash
   terraform apply
   ```

4. **Verify Deployment**:
   ```bash
   ./dr_demo_test.sh status
   ```

## Testing the DR Solution

### On-Demand Testing

Use the `dr_demo_test.sh` script for on-demand testing:

```bash
# Check current status
./dr_demo_test.sh status

# Test failover
./dr_demo_test.sh failover

# Test failback
./dr_demo_test.sh failback

# Create backups
./dr_demo_test.sh backup

# Test disk restore
./dr_demo_test.sh restore-disk

# Test database point-in-time recovery
./dr_demo_test.sh restore-db

# Run complete DR test
./dr_demo_test.sh test-all
```

### Scheduled Testing

The solution includes automated scheduled tests:

1. **Weekly Status Check**: Runs every Monday at 8 AM
2. **Monthly Backup Test**: Runs on the 1st of each month at 2 AM
3. **Quarterly Failover Test**: Runs on the 1st of every 3rd month at 1 AM (requires approval)

Test results are stored in Cloud Storage and notifications are sent via email.

## Monitoring

### Default GCP Dashboards

Access the default GCP dashboards for comprehensive metrics:

1. **VM Instances Dashboard**:
   - Go to Google Cloud Console > Compute Engine > VM Instances
   - Click on the VM name > Monitoring tab

2. **Cloud SQL Dashboard**:
   - Go to Google Cloud Console > SQL > Instance
   - Click on the instance name > Monitoring tab

3. **Load Balancer Dashboard**:
   - Go to Google Cloud Console > Network Services > Load Balancing
   - Click on the load balancer name > Monitoring tab

### Custom DR Dashboard

Access the custom DR dashboard for focused DR metrics:

1. Go to Google Cloud Console > Monitoring > Dashboards
2. Look for "DR Health Dashboard" in the list
3. Or use the direct URL from the Terraform output:
   ```bash
   terraform output dashboard_url
   ```

## Demo Steps

### Basic Demo (15 minutes)

1. **Introduction** (2 minutes):
   - Explain the DR architecture using the diagram
   - Highlight key components and their roles

2. **Status Check** (2 minutes):
   ```bash
   ./dr_demo_test.sh status
   ```
   - Show the current state of primary and standby resources
   - Explain the active-passive setup

3. **Failover Demo** (5 minutes):
   ```bash
   ./dr_demo_test.sh failover
   ```
   - Explain each step as it happens
   - Show the application running in the standby zone
   - Highlight the automatic database failover

4. **Failback Demo** (5 minutes):
   ```bash
   ./dr_demo_test.sh failback
   ```
   - Explain the failback process
   - Show the application running in the primary zone again
   - Discuss RTO and RPO achieved

5. **Q&A** (1 minute)

### Comprehensive Demo (30 minutes)

1. **Introduction** (3 minutes)
2. **Status Check** (2 minutes)
3. **Failover Demo** (5 minutes)
4. **Backup Creation** (3 minutes):
   ```bash
   ./dr_demo_test.sh backup
   ```

5. **Disk Restore Demo** (7 minutes):
   ```bash
   ./dr_demo_test.sh restore-disk
   ```
   - Show how to restore data from a snapshot
   - Verify the restored data

6. **Database Point-in-Time Recovery** (7 minutes):
   ```bash
   ./dr_demo_test.sh restore-db
   ```
   - Demonstrate recovering to a specific point in time
   - Verify the data consistency

7. **Failback Demo** (3 minutes)
8. **Q&A** (5 minutes)

## Cleanup

To destroy the infrastructure when no longer needed:

```bash
terraform destroy
```

## Additional Resources

- [Google Cloud Disaster Recovery Planning Guide](https://cloud.google.com/architecture/dr-scenarios-planning-guide)
- [Cloud SQL High Availability](https://cloud.google.com/sql/docs/mysql/high-availability)
- [Regional Persistent Disks](https://cloud.google.com/compute/docs/disks/regional-persistent-disk)
- [Module Documentation](../modules/dr_active_passive_complete_zonal/README.md)
