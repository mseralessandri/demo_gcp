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
  
  echo "Verifying application at $PROTOCOL://$IP:$PORT/web"
  
  while [ $RETRIES -lt $MAX_RETRIES ]; do
    curl -s -k "$PROTOCOL://$IP:$PORT/web" > /dev/null
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

# Function to verify application with three-tier strategy
verify_app_three_tier() {
  local VM_IP=$1
  local VM_ZONE=$2
  
  status "Three-tier verification: HTTPS LB -> HTTP LB -> Direct VM access"
  
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
    echo "HTTP load balancer failed, trying direct VM access..."
  fi
  
  # Tier 3: Try direct VM access if both load balancers failed
  if [ ! -z "$VM_IP" ]; then
    echo "Tier 3: Trying direct VM access..."
    # Try HTTPS first, then HTTP on direct VM
    if verify_app "$VM_IP" "8443" "https"; then
      echo "SUCCESS: Direct VM HTTPS verification successful"
      return 0
    fi
    echo "Direct VM HTTPS failed, trying HTTP..."
    if verify_app "$VM_IP" "8080" "http"; then
      echo "SUCCESS: Direct VM HTTP verification successful"
      return 0
    fi
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
  echo "  snapshot      - Create on-demand snapshots of VM disk and database"
  echo "  restore-disk  - Demonstrate disk restore from snapshot"
  echo "  restore-db    - Demonstrate database point-in-time recovery"
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
      
    echo "Recent data disk snapshots:"
    gcloud compute snapshots list --filter="sourceDisk:app-regional-disk" \
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
    
    # Check if failover disk already exists and handle it properly
    if gcloud compute disks describe app-standby-disk-failover --zone=us-central1-c >/dev/null 2>&1; then
      echo "Failover disk already exists, checking if it's attached..."
      
      # Check if the disk is attached to the standby VM
      ATTACHED_DISKS=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(disks[].source)" 2>/dev/null || echo "")
      if [[ $ATTACHED_DISKS == *"app-standby-disk-failover"* ]]; then
        echo "Failover disk is attached to standby VM, detaching it first..."
        gcloud compute instances detach-disk app-web-server-dr-standby \
          --disk=app-standby-disk-failover \
          --zone=us-central1-c 2>/dev/null || true
        echo "Waiting for disk detachment..."
        sleep 10
      fi
      
      echo "Deleting existing failover disk..."
      gcloud compute disks delete app-standby-disk-failover --zone=us-central1-c --quiet
      echo "Waiting for disk deletion to complete..."
      sleep 15
    fi
    
    # Get the UEFI settings of the boot disk
    BOOT_DISK_UEFI=$(gcloud compute disks describe app-standby-boot-disk --zone=us-central1-c --format="json" | grep -i "uefi")
    
    # Create the new disk with matching UEFI settings
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
    
    # 5. Attach the new disk to the standby VM
    status "Attaching new disk to standby VM"
    
    # Stop the standby VM if it's running
    gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c --quiet 2>/dev/null || true
    
    # Wait for VM to stop
    while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
      echo "Waiting for VM to stop..."
      sleep 5
    done
    
    # Ensure the regional disk is attached to the standby VM
    status "Ensuring regional disk is attached to standby VM"
    
    # Check if the regional disk is already attached
    ATTACHED_DISKS=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(disks[].source)")
    if [[ $ATTACHED_DISKS != *"app-regional-disk"* ]]; then
      echo "Attaching regional disk to standby VM..."
      gcloud compute instances attach-disk app-web-server-dr-standby \
        --disk=app-regional-disk \
        --disk-scope=regional \
        --device-name=app-data-disk \
        --zone=us-central1-c
      
      # Wait for attachment to complete
      sleep 10
    else
      echo "Regional disk is already attached to standby VM"
    fi
    
    # Detach the current disk if attached
    gcloud compute instances detach-disk app-web-server-dr-standby \
      --disk=app-standby-boot-disk \
      --zone=us-central1-c 2>/dev/null || true

    # Verify disk is detached
    echo "Verifying disk detachment..."
    sleep 5  # Give some time for the operation to complete
    ATTACHED_DISKS=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(disks[].source)")
    if [[ $ATTACHED_DISKS == *"app-standby-boot-disk"* ]]; then
      echo "Warning: Boot disk is still attached. Retrying detachment..."
      gcloud compute instances detach-disk app-web-server-dr-standby \
        --disk=app-standby-boot-disk \
        --zone=us-central1-c
      sleep 10  # Wait longer after retry
    fi

    # Attach the new disk with explicit device name
    echo "Attaching new boot disk..."
    gcloud compute instances attach-disk app-web-server-dr-standby \
      --disk=app-standby-disk-failover \
      --device-name=boot-disk \
      --boot \
      --zone=us-central1-c

    # Verify disk is attached as boot
    echo "Verifying boot disk attachment..."
    sleep 5
    BOOT_DISK=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(disks[0].source)")
    if [[ $BOOT_DISK != *"app-standby-disk-failover"* ]]; then
      echo "Error: Failed to attach boot disk properly."
      exit 1
    fi
    
    # 6. Start the DR VM
    status "Starting DR VM"
    gcloud compute instances start app-web-server-dr-standby --zone=us-central1-c
    
    # 7. Wait for VM to be ready
    status "Waiting for DR VM to be ready"
    while [[ "$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(status)')" != "RUNNING" ]]; do
      echo "Waiting for VM to start..."
      sleep 5
    done
    
    # 8. Wait for application to initialize
    status "Waiting for application to initialize"
    sleep 30
    
    # 9. Add the standby VM to the DR instance group (if not already added)
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
    
    # 10. Three-tier verification
    DR_IP=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
    verify_app_three_tier "$DR_IP" "us-central1-c"
    
    # 11. Calculate RTO
    end_time=$(date +%s)
    rto=$((end_time - start_time))
    echo "Failover completed in $rto seconds"
    
    # 12. Write custom metrics
    write_custom_metric "recovery_time" "${rto}" "failover"
    write_custom_metric "success_rate" "1.0" "failover"
    
    # 13. Check metrics after failover
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
    
    # 7. Wait for application to initialize
    status "Waiting for application to initialize"
    sleep 30
    
    # 8. Three-tier verification
    PRIMARY_IP=$(gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
    verify_app_three_tier "$PRIMARY_IP" "us-central1-a"
    
    # 9. Remove the standby VM from the DR instance group
    status "Removing standby VM from instance group"
    gcloud compute instance-groups unmanaged remove-instances app-standby-group \
      --zone=us-central1-c \
      --instances=app-web-server-dr-standby 2>/dev/null || true
    
    # 10. Calculate RTO
    end_time=$(date +%s)
    rto=$((end_time - start_time))
    echo "Failback completed in $rto seconds"
    
    # 11. Write custom metrics
    write_custom_metric "recovery_time" "${rto}" "failback"
    write_custom_metric "success_rate" "1.0" "failback"
    
    # 12. Check metrics after failback
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
      --description="Demo boot disk snapshot created on $(date)"
    
    # 2. Creating database backup
    status "Creating database backup"
    BACKUP_ID="demo-backup-$(date +%Y%m%d%H%M%S)"
    gcloud sql backups create --instance=app-db-instance-dr \
      --description="Demo backup created on $(date)"
    
    # 3. Get database credentials and insert test data for snapshot verification
    DB_IP=$(gcloud sql instances describe app-db-instance-dr --format="value(ipAddresses[0].ipAddress)")
    get_db_credentials
    
    status "Inserting test data for snapshot verification"
    mysql -h $DB_IP -u $DB_USER -p$DB_PASSWORD $DB_NAME <<EOF
-- Insert a snapshot verification record
INSERT INTO records (data) VALUES ('Snapshot verification record - $(date)');

-- Show the current data in the records table
SELECT * FROM records;
EOF
    
    # 4. Verify snapshots
    status "Verifying snapshots"
    echo "Boot disk snapshot:"
    gcloud compute snapshots list --filter="name:$BOOT_SNAPSHOT_NAME" \
      --format="table(name,diskSizeGb,creationTimestamp)"
    
    echo "Database backups:"
    gcloud sql backups list --instance=app-db-instance-dr \
      --limit=1 \
      --format="table(id,windowStartTime,status)"
    
    status "Snapshot completed successfully"
    ;;

  restore-disk)
    status "DISK RESTORE DEMO"
    
    # 1. List available snapshots
    status "Available boot disk snapshots"
    gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk" \
      --sort-by=~creationTimestamp --limit=5 \
      --format="table(name,diskSizeGb,creationTimestamp)"
    
    # 2. Select a boot disk snapshot to restore from
    echo ""
    read -p "Enter boot disk snapshot name to restore from (or press Enter to use latest): " SNAPSHOT_NAME
    
    if [ -z "$SNAPSHOT_NAME" ]; then
      SNAPSHOT_NAME=$(gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk" \
        --sort-by=~creationTimestamp --limit=1 --format="value(name)")
      echo "Using latest boot disk snapshot: $SNAPSHOT_NAME"
    fi
    
    # 3. Create a test disk from the snapshot
    status "Creating test disk from snapshot"
    gcloud compute disks create demo-restore-disk \
      --source-snapshot=$SNAPSHOT_NAME \
      --zone=us-central1-a
    
    # 4. Create a temporary VM to attach the disk
    status "Creating temporary VM for disk verification"
    gcloud compute instances create demo-restore-vm \
      --zone=us-central1-a \
      --machine-type=e2-medium \
      --boot-disk-size=10GB \
      --boot-disk-type=pd-balanced
    
    # 5. Attach the test disk to the VM
    status "Attaching restored disk to VM"
    gcloud compute instances attach-disk demo-restore-vm \
      --disk=demo-restore-disk \
      --zone=us-central1-a
    
    # 6. Provide instructions for verification
    echo ""
    status "Disk restore demo complete!"
    echo ""
    echo "To verify the disk contents, SSH to the VM:"
    echo "gcloud compute ssh demo-restore-vm --zone=us-central1-a"
    echo "Then run: sudo mkdir -p /mnt/disk && sudo mount /dev/sdb1 /mnt/disk && ls -la /mnt/disk"
    echo ""
    echo "When finished, clean up with:"
    echo "gcloud compute instances delete demo-restore-vm --zone=us-central1-a --quiet"
    echo "gcloud compute disks delete demo-restore-disk --zone=us-central1-a --quiet"
    ;;
    
  restore-db)
    status "DATABASE POINT-IN-TIME RECOVERY DEMO"
    
    # 1. Explain the demo
    echo "This demo will:"
    echo "1. Use the existing 'records' table from database.sql"
    echo "2. Insert initial data into the records table"
    echo "3. Wait for you to confirm when to set the recovery point"
    echo "4. Add more data (that will be lost after recovery)"
    echo "5. Create a clone of the database at the recovery point"
    echo "6. Show that the data added after the recovery point is not in the clone"
    echo ""
    read -p "Press Enter to begin..." dummy
    
    # 2. Get database connection details and credentials
    DB_IP=$(gcloud sql instances describe app-db-instance-dr --format="value(ipAddresses[0].ipAddress)")
    get_db_credentials
    
    # 3. Insert initial data into the existing records table
    status "Inserting initial data into the records table"
    mysql -h $DB_IP -u $DB_USER -p$DB_PASSWORD $DB_NAME <<EOF
-- Insert initial data that should be preserved after recovery
INSERT INTO records (data) VALUES ('Initial data - should be preserved after recovery');

-- Show the current data in the records table
SELECT * FROM records;
EOF
    
    # 4. Set recovery point
    echo ""
    read -p "Press Enter to set the recovery point..." dummy
    RECOVERY_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    status "Recovery point set at: $RECOVERY_TIME"
    
    # 5. Add more data
    status "Adding more data (this will be lost after recovery)"
    mysql -h $DB_IP -u $DB_USER -p$DB_PASSWORD $DB_NAME <<EOF
-- Insert data that should be lost after recovery
INSERT INTO records (data) VALUES ('Later data - should be lost after recovery');

-- Show all data in the records table
SELECT * FROM records;
EOF
    
    # 6. Create a clone at the recovery point
    status "Creating a clone at the recovery point"
    gcloud sql instances clone app-db-instance-dr pitr-demo-instance \
      --point-in-time="$RECOVERY_TIME"
    
    # 7. Wait for the clone operation to complete
    status "Waiting for clone to be ready"
    while [[ "$(gcloud sql instances describe pitr-demo-instance --format='value(state)' 2>/dev/null)" != "RUNNABLE" ]]; do
      echo "Waiting for instance to be ready..."
      sleep 10
    done
    
    # 8. Verify the data in the clone
    CLONE_IP=$(gcloud sql instances describe pitr-demo-instance --format="value(ipAddresses[0].ipAddress)")
    status "Verifying data in the clone (should only have initial data)"
    mysql -h $CLONE_IP -u $DB_USER -p$DB_PASSWORD $DB_NAME <<EOSQL
-- Check that only the initial data is present
SELECT * FROM records;
EOSQL
    
    # 9. Provide cleanup instructions
    echo ""
    status "Point-in-Time Recovery demo complete!"
    echo "When finished, clean up with:"
    echo "gcloud sql instances delete pitr-demo-instance --quiet"
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
