#!/bin/bash
# dr_test_script.sh
# Script to test the disaster recovery functionality

# Function to display status
status() {
  echo "===== $1 ====="
}

# Function to check monitoring metrics
check_metrics() {
  status "Checking monitoring metrics"
  
  # Check VM uptime
  VM_UPTIME=$(gcloud monitoring metrics list --filter="metric.type=compute.googleapis.com/instance/uptime resource.type=gce_instance" --format="value(points.value.double_value)" 2>/dev/null || echo "N/A")
  echo "VM uptime (seconds): $VM_UPTIME"
  
  # Check database uptime
  DB_UPTIME=$(gcloud monitoring metrics list --filter="metric.type=cloudsql.googleapis.com/database/up" --format="value(points.value.bool_value)" 2>/dev/null || echo "N/A")
  echo "Database uptime status: $DB_UPTIME"
  
  # Check database CPU
  DB_CPU=$(gcloud monitoring metrics list --filter="metric.type=cloudsql.googleapis.com/database/cpu/utilization" --format="value(points.value.double_value)" 2>/dev/null || echo "N/A")
  echo "Database CPU utilization: $DB_CPU"
  
  # Check error logs
  ERROR_COUNT=$(gcloud logging read "resource.type=gce_instance AND textPayload=~\"Error|ERROR|error|Exception|EXCEPTION|exception\"" --limit=10 --format="value(timestamp)" 2>/dev/null | wc -l)
  echo "Recent error log count: $ERROR_COUNT"
  
  # Check latest snapshot
  LATEST_SNAPSHOT=$(gcloud compute snapshots list --filter="sourceDisk=app-web-server-dr-primary-disk" --sort-by=~creationTimestamp --limit=1 --format="value(name)")
  SNAPSHOT_TIME=$(gcloud compute snapshots describe $LATEST_SNAPSHOT --format="value(creationTimestamp)" 2>/dev/null || echo "N/A")
  echo "Latest snapshot: $LATEST_SNAPSHOT (created: $SNAPSHOT_TIME)"
}

# Function to verify application
verify_app() {
  local IP=$1
  local MAX_RETRIES=10
  local RETRY_INTERVAL=10
  local RETRIES=0
  
  status "Verifying application at http://$IP:8080/web"
  
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    curl -s "http://$IP:8080/web" > /dev/null
    if [ $? -eq 0 ]; then
      echo "SUCCESS: Application is responding"
      return 0
    else
      echo "Attempt $((RETRIES+1))/$MAX_RETRIES: Application not responding yet, retrying in $RETRY_INTERVAL seconds..."
      sleep $RETRY_INTERVAL
      RETRIES=$((RETRIES+1))
    fi
  done
  
  echo "ERROR: Application is not responding after $MAX_RETRIES attempts"
  return 1
}

# Check if we're testing failover or failback
if [ "$1" == "failover" ]; then
  status "TESTING FAILOVER TO DR ZONE"
  
  # 1. Capture metrics before failover
  check_metrics
  
  # 2. Check if any snapshots exist for the primary disk
  SNAPSHOT_COUNT=$(gcloud compute snapshots list --filter="sourceDisk=app-web-server-dr-primary-disk" --format="value(name)" | wc -l)
  
  # If no snapshots exist, create one
  if [ "$SNAPSHOT_COUNT" -eq 0 ]; then
    status "No snapshots found for primary disk, creating one now"
    SNAPSHOT_NAME="manual-test-snapshot-$(date +%Y%m%d%H%M%S)"
    
    gcloud compute snapshots create $SNAPSHOT_NAME \
      --source-disk=app-web-server-dr-primary-disk \
      --source-disk-zone=us-central1-a \
      --description="Automatic snapshot for DR testing"
    
    status "Waiting for snapshot to complete..."
    sleep 30  # Give some time for the snapshot to complete
  else
    status "Found existing snapshots for primary disk"
  fi
  
  # 3. Simulate primary zone failure by stopping the primary VM
  status "Simulating primary zone failure"
  gcloud compute instances stop app-web-server-dr --zone=us-central1-a
  
  # 4. Create a new disk from the latest snapshot
  status "Creating new disk from latest snapshot"
  LATEST_SNAPSHOT=$(gcloud compute snapshots list --filter="sourceDisk=app-web-server-dr-primary-disk" --sort-by=~creationTimestamp --limit=1 --format="value(name)")
  echo "Using snapshot: $LATEST_SNAPSHOT"
  
  # Delete the new disk if it already exists from a previous test
  gcloud compute disks delete app-web-server-dr-standby-disk-new --zone=us-central1-c --quiet 2>/dev/null || true
  
  # Create the new disk
  gcloud compute disks create app-web-server-dr-standby-disk-new \
    --source-snapshot=$LATEST_SNAPSHOT \
    --zone=us-central1-c
  
  # 4. Attach the new disk to the standby VM
  status "Attaching new disk to standby VM"
  
  # Stop the standby VM if it's running
  gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c --quiet 2>/dev/null || true
  
  # Wait for VM to stop
  while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
    echo "Waiting for VM to stop..."
    sleep 5
  done
  
  # Detach the current disk
  gcloud compute instances detach-disk app-web-server-dr-standby \
    --disk=app-web-server-dr-standby-disk \
    --zone=us-central1-c
  
  # Attach the new disk
  gcloud compute instances attach-disk app-web-server-dr-standby \
    --disk=app-web-server-dr-standby-disk-new \
    --boot \
    --zone=us-central1-c
  
  # 5. Start the DR VM
  status "Starting DR VM"
  gcloud compute instances start app-web-server-dr-standby --zone=us-central1-c
  
  # 6. Wait for VM to be ready
  status "Waiting for DR VM to be ready"
  while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)')" != "RUNNING" ]]; do
    echo "Waiting for VM to start..."
    sleep 5
  done
  
  # 7. Wait for application to initialize
  status "Waiting for application to initialize"
  sleep 30
  
  # 8. Add the standby VM to the DR instance group
  status "Adding standby VM to instance group"
  gcloud compute instance-groups unmanaged add-instances app-dr-group \
    --zone=us-central1-c \
    --instances=app-web-server-dr-standby
  
  # 9. Verify application is responding
  DR_IP=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
  verify_app $DR_IP
  
  # 10. Check metrics after failover
  check_metrics
  
  status "Failover test completed"
  echo "To failback, run: $0 failback"

elif [ "$1" == "failback" ]; then
  status "TESTING FAILBACK TO PRIMARY ZONE"
  
  # 1. Capture metrics before failback
  check_metrics
  
  # 2. Start the primary VM
  status "Starting primary VM"
  gcloud compute instances start app-web-server-dr --zone=us-central1-a
  
  # 3. Wait for VM to be ready
  status "Waiting for primary VM to be ready"
  while [[ "$(gcloud compute instances describe app-web-server-dr --zone=us-central1-a --format='value(status)')" != "RUNNING" ]]; do
    echo "Waiting for VM to start..."
    sleep 5
  done
  
  # 4. Wait for application to initialize
  status "Waiting for application to initialize"
  sleep 30
  
  # 5. Verify application is responding
  PRIMARY_IP=$(gcloud compute instances describe app-web-server-dr --zone=us-central1-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
  verify_app $PRIMARY_IP
  
  # 6. Remove the standby VM from the DR instance group
  status "Removing standby VM from instance group"
  gcloud compute instance-groups unmanaged remove-instances app-dr-group \
    --zone=us-central1-c \
    --instances=app-web-server-dr-standby 2>/dev/null || true
  
  # 7. Stop the DR VM
  status "Stopping DR VM"
  gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c
  
  # 8. Check metrics after failback
  check_metrics
  
  status "Failback test completed"

elif [ "$1" == "status" ]; then
  status "CHECKING DR ENVIRONMENT STATUS"
  
  # Check primary VM status
  PRIMARY_STATUS=$(gcloud compute instances describe app-web-server-dr --zone=us-central1-a --format='value(status)' 2>/dev/null || echo "NOT_FOUND")
  echo "Primary VM status: $PRIMARY_STATUS"
  
  # Check DR VM status
  DR_STATUS=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)' 2>/dev/null || echo "NOT_FOUND")
  echo "DR VM status: $DR_STATUS"
  
  # Check database status
  DB_STATUS=$(gcloud sql instances describe app-db-instance-dr --format='value(state)' 2>/dev/null || echo "NOT_FOUND")
  echo "Database status: $DB_STATUS"
  
  # Check metrics
  check_metrics

else
  echo "Usage: $0 [failover|failback|status]"
  echo "  failover - Test failover to DR zone"
  echo "  failback - Test failback to primary zone"
  echo "  status   - Check status of DR environment"
  exit 1
fi
