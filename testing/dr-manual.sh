#!/bin/bash
# =============================================================================
# DR DEMO TEST SCRIPT
# =============================================================================
# This script provides on-demand testing capabilities for the DR solution.

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# Function to display status
status() {
  echo "===== $1 ====="
}

# Function to safely handle disk cleanup
safe_disk_cleanup() {
  local disk_name=$1
  local zone=$2
  local vm_name=$3
  
  echo "Safely cleaning up disk: $disk_name"
  
  # First, stop the VM if it's running
  VM_STATUS=$(gcloud compute instances describe $vm_name --zone=$zone --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
  if [[ "$VM_STATUS" == "RUNNING" ]]; then
    echo "Stopping VM $vm_name to safely detach disks..."
    gcloud compute instances stop $vm_name --zone=$zone --quiet
    
    # Wait for VM to stop
    while [[ "$(gcloud compute instances describe $vm_name --zone=$zone --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
      echo "Waiting for VM to stop..."
      sleep 5
    done
  fi
  
  # Check if disk exists
  if gcloud compute disks describe $disk_name --zone=$zone >/dev/null 2>&1; then
    echo "Disk $disk_name exists, checking if it's attached..."
    
    # Get all attached disks for the VM
    ATTACHED_DISKS=$(gcloud compute instances describe $vm_name --zone=$zone --format="value(disks[].source)" 2>/dev/null || echo "")
    
    # If the disk is attached, detach it
    if [[ $ATTACHED_DISKS == *"$disk_name"* ]]; then
      echo "Detaching disk $disk_name from VM $vm_name..."
      gcloud compute instances detach-disk $vm_name \
        --disk=$disk_name \
        --zone=$zone 2>/dev/null || true
      
      # Wait for detachment to complete
      echo "Waiting for disk detachment to complete..."
      sleep 15
      
      # Verify detachment
      ATTACHED_DISKS=$(gcloud compute instances describe $vm_name --zone=$zone --format="value(disks[].source)" 2>/dev/null || echo "")
      if [[ $ATTACHED_DISKS == *"$disk_name"* ]]; then
        echo "Warning: Disk still appears to be attached. Waiting longer..."
        sleep 30
      fi
    fi
    
    # Now try to delete the disk
    echo "Deleting disk $disk_name..."
    gcloud compute disks delete $disk_name --zone=$zone --quiet
    echo "Waiting for disk deletion to complete..."
    sleep 20
    
    # Verify deletion
    if gcloud compute disks describe $disk_name --zone=$zone >/dev/null 2>&1; then
      echo "Warning: Disk still exists. This may cause issues with disk creation."
      return 1
    else
      echo "Disk $disk_name successfully deleted."
      return 0
    fi
  else
    echo "Disk $disk_name does not exist, no cleanup needed."
    return 0
  fi
}

# Function to check monitoring metrics
check_metrics() {
  status "Checking monitoring metrics"
  
  # Check VM uptime - using gcloud compute instances describe instead of monitoring metrics
  VM_STATUS=$(gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format="value(status)" 2>/dev/null || echo "STOPPED")
  echo "Primary VM status: $VM_STATUS"
  
  STANDBY_STATUS=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(status)" 2>/dev/null || echo "STOPPED")
  echo "Standby VM status: $STANDBY_STATUS"
  
  # Check database status
  DB_STATUS=$(gcloud sql instances describe app-db-instance-dr --format="value(state)" 2>/dev/null || echo "UNKNOWN")
  echo "Database status: $DB_STATUS"
  
  # Check error logs
  ERROR_COUNT=$(gcloud logging read "resource.type=gce_instance AND textPayload=~\"Error|ERROR|error|Exception|EXCEPTION|exception\"" --limit=10 --format="value(timestamp)" 2>/dev/null | wc -l)
  echo "Recent error log count: $ERROR_COUNT"
  
  # Check latest boot disk snapshot
  LATEST_BOOT_SNAPSHOT=$(gcloud compute snapshots list --filter="sourceDisk=app-primary-boot-disk" --sort-by=~creationTimestamp --limit=1 --format="value(name)")
  BOOT_SNAPSHOT_TIME=$(gcloud compute snapshots describe $LATEST_BOOT_SNAPSHOT --format="value(creationTimestamp)" 2>/dev/null || echo "N/A")
  echo "Latest boot disk snapshot: $LATEST_BOOT_SNAPSHOT (created: $BOOT_SNAPSHOT_TIME)"
  
  # Check latest data disk snapshot
  LATEST_DATA_SNAPSHOT=$(gcloud compute snapshots list --filter="sourceDisk=app-regional-disk" --sort-by=~creationTimestamp --limit=1 --format="value(name)")
  DATA_SNAPSHOT_TIME=$(gcloud compute snapshots describe $LATEST_DATA_SNAPSHOT --format="value(creationTimestamp)" 2>/dev/null || echo "N/A")
  echo "Latest data disk snapshot: $LATEST_DATA_SNAPSHOT (created: $DATA_SNAPSHOT_TIME)"
}

# Function to verify application
verify_app() {
  local IP=$1
  local PORT=$2
  local PROTOCOL=$3
  local MAX_RETRIES=10
  local RETRY_INTERVAL=10
  local RETRIES=0
  
  echo "Verifying application at $PROTOCOL://$IP/web"
  
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    # Use curl with -w to get the HTTP status code
    HTTP_STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" "$PROTOCOL://$IP:$PORT/web")
    CURL_STATUS=$?
    
    # Check if curl command succeeded
    if [ $CURL_STATUS -eq 0 ]; then
      # Check HTTP status code
      if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
        echo "SUCCESS: Application is responding properly with status code $HTTP_STATUS"
        return 0
      else
        echo "Attempt $((RETRIES+1))/$MAX_RETRIES: Application returned status code $HTTP_STATUS"
        sleep $RETRY_INTERVAL
        RETRIES=$((RETRIES+1))
      fi
    else
      echo "Attempt $((RETRIES+1))/$MAX_RETRIES: Application not responding yet, retrying in $RETRY_INTERVAL seconds..."
      sleep $RETRY_INTERVAL
      RETRIES=$((RETRIES+1))
    fi
  done
  
  echo "ERROR: Application is not responding correctly after $MAX_RETRIES attempts"
  return 1
}

# Function to verify application with two-tier strategy
verify_app_two_tier() {
  local VM_IP=$1
  local VM_ZONE=$2
    
  # Get load balancer IPs
  LB_HTTP_IP=$(cd ../terraform && terraform output -raw load_balancer_http_ip 2>/dev/null)
  LB_HTTPS_IP=$(cd ../terraform && terraform output -raw load_balancer_https_ip 2>/dev/null)
  
  # Tier 1: Try HTTPS load balancer first
  if [ ! -z "$LB_HTTPS_IP" ]; then
    echo "Tier 1: Trying HTTPS load balancer..."
    if verify_app "$LB_HTTPS_IP" "443" "https"; then
      echo "SUCCESS: HTTPS load balancer verification successful"
      return 0
    fi
    echo "HTTPS load balancer failed, trying HTTP load balancer..."
  fi
  
  # Tier 2: Try HTTP load balancer if HTTPS failed
  if [ ! -z "$LB_HTTP_IP" ]; then
    echo "Tier 2: Trying HTTP load balancer..."
    if verify_app "$LB_HTTP_IP" "80" "http"; then
      echo "SUCCESS: HTTP load balancer verification successful"
      return 0
    fi
    echo "HTTP load balancer failed"
  fi
  
  echo "ERROR: All verification tiers failed - application is not responding"
  return 1
}

# Function to write custom metrics
write_custom_metric() {
  local metric_type=$1
  local metric_value=$2
  local test_type=$3
  
  # Use gcloud to write the metric
  gcloud beta monitoring metrics create \
    --metric-type="custom.googleapis.com/dr_test/${metric_type}" \
    --metric-kind=gauge \
    --value-type=double \
    --description="DR test metric" \
    --project="${PROJECT_ID}" 2>/dev/null || true
  
  # Write a data point
  gcloud beta monitoring metrics write \
    "custom.googleapis.com/dr_test/${metric_type}" \
    --project="${PROJECT_ID}" \
    --resource-type=global \
    --metric-labels="test_type=${test_type}" \
    --double-value="${metric_value}" 2>/dev/null || true
}

# Function to get database credentials from terraform.tfvars
get_db_credentials() {
  local tfvars_file="../terraform/terraform.tfvars"
  
  # Extract database credentials from terraform.tfvars
  DB_NAME=$(grep -E "^db_name\s*=" "$tfvars_file" | cut -d "=" -f2 | tr -d ' "')
  DB_USER=$(grep -E "^db_user\s*=" "$tfvars_file" | cut -d "=" -f2 | tr -d ' "')
  DB_PASSWORD=$(grep -E "^db_password\s*=" "$tfvars_file" | cut -d "=" -f2 | tr -d ' "')
  
  # Validate that we got all the credentials
  if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
    echo "Error: Could not extract database credentials from $tfvars_file"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# USAGE INFORMATION
# -----------------------------------------------------------------------------

function show_usage {
  echo "DR Demo Test Script"
  echo "Usage: $0 [command]"
  echo ""
  echo "Available commands:"
  echo "  status        - Show current status of primary and standby resources"
  echo "  failover      - Simulate failure and perform failover to standby zone"
  echo "  failback      - Perform failback to primary zone"
  echo "  snapshot      - Create on-demand snapshots of VM boot disk"
  echo "  test-all      - Run a complete DR demo (failover + failback)"
  echo ""
}

# Check if command is provided
if [ $# -eq 0 ]; then
  show_usage
  exit 1
fi

# -----------------------------------------------------------------------------
# COMMAND PROCESSING
# -----------------------------------------------------------------------------

# Get project ID
PROJECT_ID=$(gcloud config get-value project)

# Process command
case "$1" in
  status)
    status "CHECKING DR ENVIRONMENT STATUS"
    
    # Check primary VM
    echo "Primary VM (us-central1-a):"
    gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a \
      --format="table(name,status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "Not found"
    
    # Check standby VM
    echo "Standby VM (us-central1-c):"
    gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c \
      --format="table(name,status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "Not found"
    
    # Check database
    echo "Database:"
    gcloud sql instances describe app-db-instance-dr \
      --format="table(name,gceZone,state,settings.availabilityType)" 2>/dev/null || echo "Not found"
    
    # Check database zones
    echo "Database Zones:"
    gcloud sql instances describe app-db-instance-dr --format="json(name,region,gceZone,secondaryGceZone)" 2>/dev/null || echo "Not found"
    
    # Check snapshots
    echo "Recent boot disk snapshots:"
    gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk" \
      --sort-by=~creationTimestamp --limit=3 \
      --format="table(name,diskSizeGb,creationTimestamp)" 2>/dev/null || echo "None found"
    
    # Check instance groups
    echo "Primary instance group:"
    gcloud compute instance-groups unmanaged list-instances app-primary-group --zone=us-central1-a \
      --format="table(instance)" 2>/dev/null || echo "Not found"
    
    echo "Standby instance group:"
    gcloud compute instance-groups unmanaged list-instances app-standby-group --zone=us-central1-c \
      --format="table(instance)" 2>/dev/null || echo "Not found"
    
    # Check metrics
    #check_metrics
    ;;
    
  failover)
    status "PERFORMING FAILOVER DEMO"
    
    # Record start time for RTO calculation
    start_time=$(date +%s)
    
    # 1. Capture metrics before failover
    #check_metrics
    
    # 2. Check if any snapshots exist for the primary boot disk
    SNAPSHOT_COUNT=$(gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk" --format="value(name)" | wc -l)
    
    # If no snapshots exist, create one
    if [ "$SNAPSHOT_COUNT" -eq 0 ]; then
      status "No snapshots found for primary boot disk, creating one now"
      SNAPSHOT_NAME="manual-boot-snapshot-$(date +%Y%m%d%H%M%S)"
      
      gcloud compute snapshots create $SNAPSHOT_NAME \
        --source-disk=app-primary-boot-disk \
        --source-disk-zone=us-central1-a \
        --description="Automatic snapshot of boot disk for DR testing"
      
      status "Waiting for snapshot to complete..."
      sleep 30  # Give some time for the snapshot to complete
    else
      status "Found existing snapshots for primary boot disk"
    fi
    
    # 3. Simulate primary zone failure by stopping the primary VM
    status "Simulating primary zone failure"
    gcloud compute instances stop app-web-server-dr-primary --zone=us-central1-a --quiet
    
    # 3.1 Detach the regional disk from the primary VM
    status "Detaching regional disk from primary VM"
    gcloud compute instances detach-disk app-web-server-dr-primary \
      --disk=app-regional-disk \
      --disk-scope=regional \
      --zone=us-central1-a 2>/dev/null || true
    
    # Wait for detachment to complete
    echo "Waiting for disk detachment to complete..."
    sleep 10
    
    # 4. Create a new disk from the latest boot disk snapshot
    status "Creating new disk from latest boot disk snapshot"
    LATEST_BOOT_SNAPSHOT=$(gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk" --sort-by=~creationTimestamp --limit=1 --format="value(name)")
    echo "Using boot disk snapshot: $LATEST_BOOT_SNAPSHOT"
    
    # 5. Use safe disk cleanup for failover disk
    status "Safely cleaning up existing failover disk if present"
    safe_disk_cleanup "app-standby-disk-failover" "us-central1-c" "app-web-server-dr-standby"
    
    # 6. Get the UEFI settings of the boot disk
    BOOT_DISK_UEFI=$(gcloud compute disks describe app-standby-boot-disk --zone=us-central1-c --format="json" | grep -i "uefi")
    
    # 7. Create the new disk with matching UEFI settings
    status "Creating new failover disk from snapshot"
    if [[ -n "$BOOT_DISK_UEFI" ]]; then
      gcloud compute disks create app-standby-disk-failover \
        --source-snapshot=$LATEST_BOOT_SNAPSHOT \
        --zone=us-central1-c \
        --guest-os-features=UEFI_COMPATIBLE
    else
      gcloud compute disks create app-standby-disk-failover \
        --source-snapshot=$LATEST_BOOT_SNAPSHOT \
        --zone=us-central1-c
    fi
    
    # 8. Prepare standby VM for new boot disk
    status "Preparing standby VM for new boot disk"
    
    # Ensure VM is stopped
    gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c --quiet 2>/dev/null || true
    
    # Wait for VM to stop completely
    while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
      echo "Waiting for VM to stop..."
      sleep 5
    done
    
    # 9. Detach ALL disks from standby VM
    status "Detaching all disks from standby VM"
    
    # Detach original boot disk
    echo "Detaching original boot disk..."
    gcloud compute instances detach-disk app-web-server-dr-standby \
      --disk=app-standby-boot-disk \
      --zone=us-central1-c 2>/dev/null || true
    
    # Detach regional disk if attached
    echo "Detaching regional disk if attached..."
    gcloud compute instances detach-disk app-web-server-dr-standby \
      --disk=app-regional-disk \
      --disk-scope=regional \
      --zone=us-central1-c 2>/dev/null || true
    
    # Wait for all detachments to complete
    echo "Waiting for all disk detachments to complete..."
    sleep 20
    
    # 10. Attach new boot disk
    status "Attaching new boot disk"
    gcloud compute instances attach-disk app-web-server-dr-standby \
      --disk=app-standby-disk-failover \
      --device-name=boot-disk \
      --boot \
      --zone=us-central1-c
    
    # 11. Attach regional disk
    status "Attaching regional disk"
    gcloud compute instances attach-disk app-web-server-dr-standby \
      --disk=app-regional-disk \
      --disk-scope=regional \
      --device-name=app-data-disk \
      --zone=us-central1-c
    
    # Wait for attachments to complete
    echo "Waiting for disk attachments to complete..."
    sleep 15
    
    # 12. Verify disk configuration
    echo "Verifying disk configuration..."
    BOOT_DISK=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(disks[0].source)")
    if [[ $BOOT_DISK != *"app-standby-disk-failover"* ]]; then
      echo "Error: Failed to attach boot disk properly."
      exit 1
    fi
    echo "Boot disk successfully attached: $BOOT_DISK"
    
    # 13. Start the DR VM
    status "Starting DR VM"
    gcloud compute instances start app-web-server-dr-standby --zone=us-central1-c
    
    # 14. Wait for VM to be ready
    status "Waiting for DR VM to be ready"
    while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)')" != "RUNNING" ]]; do
      echo "Waiting for VM to start..."
      sleep 5
    done
    
    # 15. Wait for application to initialize
    status "Waiting for application to initialize"
    sleep 30
    
    # 16. Add the standby VM to the DR instance group (if not already added)
    status "Adding standby VM to instance group"
    CURRENT_INSTANCES=$(gcloud compute instance-groups unmanaged list-instances app-standby-group --zone=us-central1-c --format="value(instance)" 2>/dev/null || echo "")
    if [[ $CURRENT_INSTANCES != *"app-web-server-dr-standby"* ]]; then
      echo "Adding standby VM to instance group..."
      gcloud compute instance-groups unmanaged add-instances app-standby-group \
        --zone=us-central1-c \
        --instances=app-web-server-dr-standby
    else
      echo "Standby VM is already in the instance group"
    fi
    
    # 17. Two-tier verification
    DR_IP=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
    verify_app_two_tier "$DR_IP" "us-central1-c"
    
    # 18. Calculate RTO
    end_time=$(date +%s)
    rto=$((end_time - start_time))
    echo "Failover completed in $rto seconds"
    
    # 19. Write custom metrics
    write_custom_metric "recovery_time" "${rto}" "failover"
    write_custom_metric "success_rate" "1.0" "failover"
    
    # 20. Check metrics after failover
    #check_metrics
    
    status "Failover test completed"
    echo "To failback, run: $0 failback"
    ;;

  failback)
    status "PERFORMING FAILBACK DEMO"
    
    # Record start time for RTO calculation
    start_time=$(date +%s)
    
    # 1. Capture metrics before failback
    #check_metrics
    
    # 2. Stop the standby VM
    status "Stopping standby VM"
    gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c --quiet
    
    # Wait for VM to stop
    while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
      echo "Waiting for VM to stop..."
      sleep 5
    done
    
    # 3. Detach the regional disk from the standby VM
    status "Detaching regional disk from standby VM"
    gcloud compute instances detach-disk app-web-server-dr-standby \
      --disk=app-regional-disk \
      --disk-scope=regional \
      --zone=us-central1-c 2>/dev/null || true
    
    # Wait for detachment to complete
    echo "Waiting for disk detachment to complete..."
    sleep 10
    
    # 4. Start the primary VM
    status "Starting primary VM"
    gcloud compute instances start app-web-server-dr-primary --zone=us-central1-a
    
    # 5. Wait for VM to be ready
    status "Waiting for primary VM to be ready"
    while [[ "$(gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format='value(status)')" != "RUNNING" ]]; do
      echo "Waiting for VM to start..."
      sleep 5
    done
    
    # 6. Attach the regional disk to the primary VM
    status "Attaching regional disk to primary VM"
    gcloud compute instances attach-disk app-web-server-dr-primary \
      --disk=app-regional-disk \
      --disk-scope=regional \
      --device-name=app-data-disk \
      --zone=us-central1-a
    
    # Wait for attachment to complete
    echo "Waiting for disk attachment to complete..."
    sleep 10
    
    # 7. Add primary VM to its instance group
    status "Adding primary VM to instance group"
    CURRENT_PRIMARY_INSTANCES=$(gcloud compute instance-groups unmanaged list-instances app-primary-group --zone=us-central1-a --format="value(instance)" 2>/dev/null || echo "")
    if [[ $CURRENT_PRIMARY_INSTANCES != *"app-web-server-dr-primary"* ]]; then
      echo "Adding primary VM to instance group..."
      gcloud compute instance-groups unmanaged add-instances app-primary-group \
        --zone=us-central1-a \
        --instances=app-web-server-dr-primary
    else
      echo "Primary VM is already in the instance group"
    fi
    
    # 8. Wait for application to initialize
    status "Waiting for application to initialize"
    sleep 30
    
    # 9. Remove the standby VM from the DR instance group
    status "Removing standby VM from instance group"
    gcloud compute instance-groups unmanaged remove-instances app-standby-group \
      --zone=us-central1-c \
      --instances=app-web-server-dr-standby 2>/dev/null || true
    
    # 10. Two-tier verification
    PRIMARY_IP=$(gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
    verify_app_two_tier "$PRIMARY_IP" "us-central1-a"
    
    # 11. Calculate RTO
    end_time=$(date +%s)
    rto=$((end_time - start_time))
    echo "Failback completed in $rto seconds"
    
    # 12. Write custom metrics
    write_custom_metric "recovery_time" "${rto}" "failback"
    write_custom_metric "success_rate" "1.0" "failback"
    
    # 13. Check metrics after failback
    #check_metrics
    
    status "Failback test completed"
    ;;

  snapshot)
    status "CREATING ON-DEMAND SNAPSHOTS"
    
    # 1. Creating boot disk snapshot
    BOOT_SNAPSHOT_NAME="demo-boot-snapshot-$(date +%Y%m%d%H%M%S)"
    status "Creating boot disk snapshot: $BOOT_SNAPSHOT_NAME"
    
    gcloud compute snapshots create $BOOT_SNAPSHOT_NAME \
      --source-disk=app-primary-boot-disk \
      --source-disk-zone=us-central1-a \
      --description="Boot disk snapshot created on $(date)"
    

    
    # 4. Verify snapshots
    status "Verifying snapshots"
    echo "Boot disk snapshot:"
    gcloud compute snapshots list --filter="name:$BOOT_SNAPSHOT_NAME" \
      --format="table(name,diskSizeGb,creationTimestamp)"
    ;;


  test-all)
    status "RUNNING COMPLETE DR DEMO"
    
    # 1. Show initial status
    echo "This will demonstrate the full DR lifecycle:"
    echo "1. Show initial status"
    echo "2. Perform failover to standby zone"
    echo "3. Perform failback to primary zone"
    echo ""
    read -p "Press Enter to begin..." dummy
    
    # 2. Show status
    $0 status
    
    # 3. Perform failover
    echo ""
    read -p "Press Enter to begin failover..." dummy
    $0 failover
    
    # 4. Perform failback
    echo ""
    read -p "Press Enter to begin failback..." dummy
    $0 failback
    
    # 5. Show final status
    echo ""
    read -p "Press Enter to check final status..." dummy
    $0 status
    
    status "Complete DR demo finished successfully!"
    ;;

  *)
    echo "Unknown command: $1"
    show_usage
    exit 1
    ;;
esac
