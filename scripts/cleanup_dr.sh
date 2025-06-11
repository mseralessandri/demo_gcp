#!/bin/bash
# =============================================================================
# DR CLEANUP SCRIPT
# =============================================================================
# This script deletes all DR-related resources to ensure a clean slate
# It includes deletion of:
# - Compute instances
# - Disks
# - Snapshots and snapshot schedules
# - Instance groups
# - Load balancer components
# - Firewall rules
# - Database instances and backups
# - Storage buckets and contents
# - Service accounts
# - Monitoring resources

# Set error handling
set -e
set -o pipefail

# Function to display status
status() {
  echo ""
  echo "===== $1 ====="
}

# Function to run command with error handling
run_cmd() {
  local cmd="$1"
  local msg="$2"
  
  eval "$cmd" 2>/dev/null || echo "$msg"
}

status "STARTING DR RESOURCE CLEANUP"

# Set project ID
PROJECT_ID=$(gcloud config get-value project)
status "Using project: $PROJECT_ID"

# Delete compute instances
status "Deleting compute instances"
run_cmd "gcloud compute instances delete app-web-server-dr-primary --zone=us-central1-a --quiet" "Primary VM not found or already deleted"
run_cmd "gcloud compute instances delete app-web-server-dr-standby --zone=us-central1-c --quiet" "Standby VM not found or already deleted"

# Delete disks
status "Deleting disks"
run_cmd "gcloud compute disks delete app-primary-boot-disk --zone=us-central1-a --quiet" "Primary boot disk not found or already deleted"
run_cmd "gcloud compute disks delete app-standby-boot-disk --zone=us-central1-c --quiet" "Standby boot disk not found or already deleted"
run_cmd "gcloud compute disks delete app-regional-disk --region=us-central1 --quiet" "Regional disk not found or already deleted"
run_cmd "gcloud compute disks delete app-standby-disk-failover --zone=us-central1-c --quiet" "Failover disk not found or already deleted"

# Delete compute engine snapshots
status "Deleting Compute Engine snapshots"
echo "Deleting boot disk snapshots..."
BOOT_SNAPSHOTS=$(gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk OR sourceDisk:app-standby-boot-disk" --format="value(name)" 2>/dev/null || echo "")
for SNAPSHOT in $BOOT_SNAPSHOTS; do
  run_cmd "gcloud compute snapshots delete $SNAPSHOT --quiet" "Snapshot $SNAPSHOT not found or already deleted"
done

echo "Deleting regional disk snapshots..."
REGIONAL_SNAPSHOTS=$(gcloud compute snapshots list --filter="sourceDisk:app-regional-disk" --format="value(name)" 2>/dev/null || echo "")
for SNAPSHOT in $REGIONAL_SNAPSHOTS; do
  run_cmd "gcloud compute snapshots delete $SNAPSHOT --quiet" "Snapshot $SNAPSHOT not found or already deleted"
done

# Delete snapshot schedules
status "Deleting snapshot schedules"
SCHEDULES=$(gcloud compute resource-policies list --filter="name:app-snapshot-schedule" --format="value(name)" 2>/dev/null || echo "")
for SCHEDULE in $SCHEDULES; do
  run_cmd "gcloud compute resource-policies delete $SCHEDULE --region=us-central1 --quiet" "Snapshot schedule $SCHEDULE not found or already deleted"
done

# Delete instance groups
status "Deleting instance groups"
run_cmd "gcloud compute instance-groups unmanaged delete app-primary-group --zone=us-central1-a --quiet" "Primary instance group not found or already deleted"
run_cmd "gcloud compute instance-groups unmanaged delete app-standby-group --zone=us-central1-c --quiet" "Standby instance group not found or already deleted"

# Delete load balancer components
status "Deleting load balancer components"
echo "Deleting forwarding rules..."
run_cmd "gcloud compute forwarding-rules delete app-http-forwarding-rule --global --quiet" "HTTP forwarding rule not found or already deleted"
run_cmd "gcloud compute forwarding-rules delete app-https-forwarding-rule --global --quiet" "HTTPS forwarding rule not found or already deleted"
run_cmd "gcloud compute forwarding-rules delete app-forwarding-rule --global --quiet" "Legacy forwarding rule not found or already deleted"

echo "Deleting proxies..."
run_cmd "gcloud compute target-http-proxies delete app-http-proxy --quiet" "HTTP proxy not found or already deleted"
run_cmd "gcloud compute target-https-proxies delete app-https-proxy --quiet" "HTTPS proxy not found or already deleted"

echo "Deleting SSL certificates..."
run_cmd "gcloud compute ssl-certificates delete app-ssl-cert --quiet" "SSL certificate not found or already deleted"

echo "Deleting URL maps..."
run_cmd "gcloud compute url-maps delete app-url-map --quiet" "URL map not found or already deleted"

echo "Deleting backend services..."
run_cmd "gcloud compute backend-services delete app-backend-service --global --quiet" "Backend service not found or already deleted"

echo "Deleting health checks..."
run_cmd "gcloud compute health-checks delete app-health-check --quiet" "Health check not found or already deleted"

# Delete firewall rules
status "Deleting firewall rules"
run_cmd "gcloud compute firewall-rules delete allow-http-dr --quiet" "HTTP firewall rule not found or already deleted"
run_cmd "gcloud compute firewall-rules delete allow-ssh-dr --quiet" "SSH firewall rule not found or already deleted"
run_cmd "gcloud compute firewall-rules delete allow-health-checks-dr --quiet" "Health checks firewall rule not found or already deleted"

# Delete database instance and backups
status "Deleting database instance and backups"
echo "Listing database backups..."
BACKUP_IDS=$(gcloud sql backups list --instance=app-db-instance-dr --format="value(id)" 2>/dev/null || echo "")
for BACKUP_ID in $BACKUP_IDS; do
  run_cmd "gcloud sql backups delete $BACKUP_ID --instance=app-db-instance-dr --quiet" "Backup $BACKUP_ID not found or already deleted"
done

echo "Deleting database instance..."
run_cmd "gcloud sql instances delete app-db-instance-dr --quiet" "Database instance not found or already deleted"

# Delete storage buckets
status "Deleting storage buckets"
echo "Emptying backup bucket..."
run_cmd "gsutil -m rm -r gs://microcloud-448817-dr-backups/**" "Backup bucket empty or not found"

echo "Deleting backup bucket..."
run_cmd "gsutil rb gs://microcloud-448817-dr-backups" "Backup bucket not found or already deleted"

# Delete service accounts
status "Deleting service accounts"
run_cmd "gcloud iam service-accounts delete dr-service-account@$PROJECT_ID.iam.gserviceaccount.com --quiet" "DR service account not found or already deleted"
run_cmd "gcloud iam service-accounts delete dr-workflow-sa@$PROJECT_ID.iam.gserviceaccount.com --quiet" "DR workflow service account not found or already deleted"

# Delete secrets
status "Deleting secrets"
run_cmd "gcloud secrets delete db_credentials --quiet" "DB credentials secret not found or already deleted"
run_cmd "gcloud secrets delete ssl_cert --quiet" "SSL cert secret not found or already deleted"
run_cmd "gcloud secrets delete ssl_key --quiet" "SSL key secret not found or already deleted"

# Delete Cloud Scheduler jobs
status "Deleting Cloud Scheduler jobs"
run_cmd "gcloud scheduler jobs delete dr-backup-verification --location=us-central1 --quiet" "Backup verification job not found or already deleted"
run_cmd "gcloud scheduler jobs delete dr-weekly-status-check --location=us-central1 --quiet" "Weekly status check job not found or already deleted"
run_cmd "gcloud scheduler jobs delete dr-monthly-backup-test --location=us-central1 --quiet" "Monthly backup test job not found or already deleted"
run_cmd "gcloud scheduler jobs delete dr-quarterly-failover-test --location=us-central1 --quiet" "Quarterly failover test job not found or already deleted"

# Delete Cloud Workflows
status "Deleting Cloud Workflows"
run_cmd "gcloud workflows delete dr-failover-workflow --location=us-central1 --quiet" "Failover workflow not found or already deleted"
run_cmd "gcloud workflows delete dr-failback-workflow --location=us-central1 --quiet" "Failback workflow not found or already deleted"

# Delete monitoring resources
status "Deleting monitoring resources"
echo "Deleting dashboards..."
DASHBOARDS=$(gcloud monitoring dashboards list --filter="displayName:DR Health Dashboard" --format="value(name)" 2>/dev/null || echo "")
for DASHBOARD in $DASHBOARDS; do
  run_cmd "gcloud monitoring dashboards delete $DASHBOARD --quiet" "Dashboard not found or already deleted"
done

echo "Deleting alert policies..."
POLICIES=$(gcloud alpha monitoring policies list --filter="displayName~DR" --format="value(name)" 2>/dev/null || echo "")
for POLICY in $POLICIES; do
  run_cmd "gcloud alpha monitoring policies delete $POLICY --quiet" "Alert policy not found or already deleted"
done

echo "Deleting notification channels..."
CHANNELS=$(gcloud alpha monitoring channels list --filter="displayName~DR" --format="value(name)" 2>/dev/null || echo "")
for CHANNEL in $CHANNELS; do
  run_cmd "gcloud alpha monitoring channels delete $CHANNEL --quiet" "Notification channel not found or already deleted"
done

echo "Deleting metrics..."
run_cmd "gcloud beta monitoring metrics descriptors delete custom.googleapis.com/dr_test/success_rate" "Success rate metric not found or already deleted"
run_cmd "gcloud beta monitoring metrics descriptors delete custom.googleapis.com/dr_test/recovery_time" "Recovery time metric not found or already deleted"
run_cmd "gcloud beta monitoring metrics descriptors delete custom.googleapis.com/dr_app_errors_complete" "App errors metric not found or already deleted"
run_cmd "gcloud logging metrics delete dr_app_errors_complete --quiet" "Logging metric not found or already deleted"

status "CLEANUP COMPLETE"
echo "All DR resources have been deleted. You can now run terraform apply to recreate them."
