# Disaster Recovery Plan: Active-Passive Zonal Warm Standby

## Overview

This document outlines the disaster recovery (DR) plan for the application infrastructure. The DR strategy implemented is an active-passive zonal warm standby approach, providing protection against zone-level failures within the us-central1 region.

## Architecture

The DR architecture consists of:

1. **Primary Zone (us-central1-a)**:
   - Running VM instance (app-web-server-dr) with dedicated disk
   - Hourly snapshots of the primary disk
   - Regional Cloud SQL instance with automatic failover

2. **DR Zone (us-central1-c)**:
   - Stopped VM instance (app-web-server-dr-standby) with dedicated disk
   - Cloud SQL standby instance (automatically managed)

3. **Region-Level Services**:
   - Internal load balancer with health checks
   - Secret Manager with regional replication
   - Cloud SQL automated backups
   - Disk snapshot schedule with 7-day retention

## Recovery Objectives

- **Recovery Time Objective (RTO)**: < 15 minutes
- **Recovery Point Objective (RPO)**: 1 hour for disk data, near-zero for database

## Failover Procedure

### Automatic Components

The following components will fail over automatically:

1. **Cloud SQL Database**: 
   - Regional instance automatically fails over to the standby in the DR zone
   - Typically completes within 1-2 minutes
   - No manual intervention required
   - Connection strings remain the same

### Manual Steps Required

1. **Create a new disk from the latest snapshot**:
   ```bash
   # Get the latest snapshot of the primary disk
   LATEST_SNAPSHOT=$(gcloud compute snapshots list --filter="sourceDisk=app-web-server-dr-primary-disk" --sort-by=~creationTimestamp --limit=1 --format="value(name)")
   
   # Create a new disk from the snapshot in the standby zone
   gcloud compute disks create app-web-server-dr-standby-disk-new \
     --source-snapshot=$LATEST_SNAPSHOT \
     --zone=us-central1-c
   ```

2. **Attach the new disk to the standby VM**:
   ```bash
   # Stop the standby VM if it's running
   gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c
   
   # Detach the current disk
   gcloud compute instances detach-disk app-web-server-dr-standby \
     --disk=app-web-server-dr-standby-disk \
     --zone=us-central1-c
   
   # Attach the new disk
   gcloud compute instances attach-disk app-web-server-dr-standby \
     --disk=app-web-server-dr-standby-disk-new \
     --boot \
     --zone=us-central1-c
   ```

3. **Start the DR VM**:
   ```bash
   gcloud compute instances start app-web-server-dr-standby --zone=us-central1-c
   ```

4. **Add the standby VM to the instance group**:
   ```bash
   # Add the standby VM to the DR instance group
   gcloud compute instance-groups unmanaged add-instances app-dr-group \
     --zone=us-central1-c \
     --instances=app-web-server-dr-standby
   ```

5. **Verify Application Functionality**:
   - Check that the application is responding on the DR VM
   - Verify database connectivity
   - Check application logs for errors

## Failback Procedure

Once the primary zone is available again:

1. **Start the Primary VM**:
   ```bash
   gcloud compute instances start app-web-server-dr --zone=us-central1-a
   ```

2. **Verify Application Functionality**:
   - Check that the application is responding on the primary VM
   - Verify database connectivity
   - Check application logs for errors

3. **Remove the standby VM from the instance group**:
   ```bash
   # Remove the standby VM from the DR instance group
   gcloud compute instance-groups unmanaged remove-instances app-dr-group \
     --zone=us-central1-c \
     --instances=app-web-server-dr-standby
   ```

4. **Stop the DR VM**:
   ```bash
   gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c
   ```

## Testing Schedule

- Full DR test: Quarterly
- Partial DR test (without application downtime): Monthly
- Use the provided `dr_test_script_zonal.sh` script for testing

## Monitoring and Alerting

### Monitoring Components

1. **VM Status Monitoring**:
   - Monitors VM uptime every 60 seconds
   - Alerts if the VM uptime is less than 60 seconds (indicating a restart or failure)

2. **Database Health Monitoring**:
   - Monitors database availability (uptime)
   - Monitors database CPU utilization
   - Alerts if database is down or CPU usage exceeds 80%

3. **Disk Snapshot Monitoring**:
   - Tracks successful creation of hourly snapshots
   - Ensures snapshot retention policy is enforced

4. **Log-Based Error Detection**:
   - Monitors application logs for error patterns
   - Alerts if more than 5 errors occur within a minute

5. **Custom Dashboard**:
   - Provides a single view of all DR-related metrics
   - Displays application uptime, database health, and VM performance

### Alert Notifications

- Email notifications are sent to the designated DR team
- Alerts include:
  - Application downtime
  - Database replication issues
  - High error rates in application logs

## DR Testing Procedure

1. **Preparation**:
   - Schedule the test during a maintenance window
   - Notify all stakeholders of the planned test
   - Ensure monitoring is active and functioning

2. **Execution**:
   - Run the DR test script:
     ```bash
     ./dr_test_script_zonal.sh failover
     ```
   - Monitor the failover process through the DR dashboard
   - Verify application functionality in the DR environment

3. **Validation**:
   - Confirm all application functions are working
   - Verify data integrity
   - Check monitoring metrics for any anomalies

4. **Failback**:
   - Run the failback portion of the test script:
     ```bash
     ./dr_test_script_zonal.sh failback
     ```
   - Verify successful return to the primary environment

5. **Documentation**:
   - Record the RTO achieved (actual time to recover)
   - Document any issues encountered
   - Update procedures based on lessons learned

## Roles and Responsibilities

| Role | Responsibilities |
|------|-----------------|
| DR Coordinator | Overall coordination of DR activities, decision-making authority for failover |
| Database Administrator | Monitoring database replication, resolving database issues |
| System Administrator | VM management, infrastructure monitoring |
| Application Support | Application testing, verification of functionality |

## Communication Plan

1. **During DR Event**:
   - Initial notification to DR team via email and phone
   - Status updates every 30 minutes
   - Final notification when recovery is complete

2. **Stakeholder Communication**:
   - Initial notification of service disruption
   - Estimated time to recovery
   - Final notification when service is restored

## Appendix

### Terraform Resources

The DR infrastructure is managed through Terraform with the following files:

- `app_dr_active_passive_zonal_warm.tf` - Main DR infrastructure
- `variables_dr_active_passive_zonal_warm.tf` - Variables specific to DR
- `outputs_dr_active_passive_zonal_warm.tf` - Outputs for DR resources
- `dr_test_script_zonal.sh` - Script to test DR functionality

### Useful Commands

**View DR VM Status**:
```bash
gcloud compute instances describe app-web-server-dr --zone=us-central1-a
gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c
```

**View Cloud SQL Status**:
```bash
gcloud sql instances describe app-db-instance-dr
```

**Check Application Logs**:
```bash
gcloud compute ssh app-web-server-dr --zone=us-central1-a -- "tail -f /home/goapp/dr-demo/app.log"
gcloud compute ssh app-web-server-dr-standby --zone=us-central1-c -- "tail -f /home/goapp/dr-demo/app.log"
```

**View Monitoring Dashboard**:
```bash
# Open the Google Cloud Console and navigate to:
# Monitoring > Dashboards > Disaster Recovery Dashboard
