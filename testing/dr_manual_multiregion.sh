#!/bin/bash
# =============================================================================
# MULTI-REGION DR DEMO TEST SCRIPT
# =============================================================================
# This script provides on-demand testing capabilities for the multi-region DR solution.

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# Function to display status
status() {
  echo "===== $1 ====="
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
    echo "Trying HTTPS load balancer..."
    if verify_app "$LB_HTTPS_IP" "443" "https"; then
      echo "SUCCESS: HTTPS load balancer verification successful"
      return 0
    fi
    echo "HTTPS load balancer failed, trying HTTP load balancer..."
  fi
  
  # Tier 2: Try HTTP load balancer if HTTPS failed
  if [ ! -z "$LB_HTTP_IP" ]; then
    echo "Trying HTTP load balancer..."
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

# Function for dynamic waiting with exponential backoff
wait_with_backoff() {
  local check_command="$1"
  local success_condition="$2"
  local max_attempts="${3:-30}"
  local initial_wait="${4:-2}"
  local max_wait="${5:-30}"
  local description="${6:-Operation}"
  
  local attempt=1
  local wait_time=$initial_wait
  
  echo "Waiting for $description to complete..."
  
  while [[ $attempt -le $max_attempts ]]; do
    local result=$(eval "$check_command" 2>/dev/null || echo "ERROR")
    
    if [[ "$result" == "$success_condition" ]]; then
      echo "$description completed successfully"
      return 0
    elif [[ "$result" == "ERROR" ]]; then
      echo "Error checking status of $description"
    else
      echo "$description in progress... Current status: $result (Attempt $attempt/$max_attempts)"
    fi
    
    sleep $wait_time
    
    # Exponential backoff with cap
    wait_time=$(( wait_time * 2 < max_wait ? wait_time * 2 : max_wait ))
    attempt=$((attempt + 1))
  done
  
  echo "WARNING: $description timed out after $max_attempts attempts"
  return 1
}

# Function to run commands in parallel and wait for completion
run_in_parallel() {
  local pids=()
  local results=()
  local commands=("$@")
  
  # Start all commands in background
  for cmd in "${commands[@]}"; do
    eval "$cmd" &
    pids+=($!)
  done
  
  # Wait for all commands to complete
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      results[$i]=0
    else
      results[$i]=$?
    fi
  done
  
  # Check if any command failed
  for i in "${!results[@]}"; do
    if [[ ${results[$i]} -ne 0 ]]; then
      return ${results[$i]}
    fi
  done
  
  return 0
}

# -----------------------------------------------------------------------------
# USAGE INFORMATION
# -----------------------------------------------------------------------------

function show_usage {
  echo "Multi-Region DR Demo Test Script"
  echo "Usage: $0 [command]"
  echo ""
  echo "Available commands:"
  echo "  status              - Show status of multi-region resources"
  echo "  failover            - Perform failover to secondary region"
  echo "  failback            - Perform failback from secondary region to primary region"
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

# Function to check multi-region status
check_multiregion_status() {
  status "CHECKING MULTI-REGION DR ENVIRONMENT STATUS"
  
  # Check primary region resources
  echo "PRIMARY REGION (us-central1):"
  echo "Primary VM (us-central1-a):"
  gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a \
    --format="table(name,status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "Not found"
  
  echo "Primary database:"
  gcloud sql instances describe app-db-instance-dr \
    --format="table(name,gceZone,state,settings.availabilityType)" 2>/dev/null || echo "Not found"
  
  # Check secondary region resources
  echo ""
  echo "SECONDARY REGION (us-east1):"
  echo "Secondary primary VM (us-east1-b):"
  gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b \
    --format="table(name,status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "Not found"
  
  echo "Secondary database:"
  gcloud sql instances describe app-db-instance-dr-secondary \
    --format="table(name,gceZone,state,settings.availabilityType)" 2>/dev/null || echo "Not found"
  
  # Check instance groups
  echo ""
  echo "Instance Groups:"
  echo "Primary region primary group:"
  gcloud compute instance-groups unmanaged list-instances app-primary-group --zone=us-central1-a \
    --format="table(instance)" 2>/dev/null || echo "Not found"
  
  echo "Secondary region primary group:"
  gcloud compute instance-groups unmanaged list-instances app-secondary-primary-group --zone=us-east1-b \
    --format="table(instance)" 2>/dev/null || echo "Not found"
  
  # Check backend service
  echo ""
  echo "Backend Service:"
  gcloud compute backend-services describe app-backend-service --global \
    --format="json(backends)" 2>/dev/null || echo "Not found"
}

# Function to execute multi-region failover
multiregion_failover() {
  status "PERFORMING MULTI-REGION FAILOVER"
  
  # Record start time for RTO calculation
  start_time=$(date +%s)
  
  # Step 1: Check if secondary DB exists and is a replica
  status "Checking secondary DB status"
  SECONDARY_DB_EXISTS=$(gcloud sql instances describe app-db-instance-dr-secondary --format="value(name)" 2>/dev/null || echo "")
  
  if [[ -z "$SECONDARY_DB_EXISTS" ]]; then
    echo "ERROR: Secondary DB instance does not exist. Aborting failover."
    echo "Run scripts/recreate_secondary_db.sh to create the secondary DB as a replica."
    exit 1
  fi
  
  # Check if it's a replica by looking for masterInstanceName
  SECONDARY_DB_MASTER=$(gcloud sql instances describe app-db-instance-dr-secondary --format="value(masterInstanceName)" 2>/dev/null || echo "")
  
  # Start parallel operations
  # Step 2: Promote secondary region DB to primary if it's a replica (in background)
  if [[ -n "$SECONDARY_DB_MASTER" ]]; then
    status "Secondary DB is a replica of $SECONDARY_DB_MASTER, promoting to primary"
    # Start DB promotion in background
    gcloud sql instances promote-replica app-db-instance-dr-secondary --quiet &
    DB_PROMOTION_PID=$!
    echo "DB promotion started in background (PID: $DB_PROMOTION_PID)"
  else
    status "Secondary DB is already a primary, skipping promotion"
    DB_PROMOTION_PID=""
  fi
  
  # Step 3: Create a consistency group snapshot (in parallel with DB promotion)
  status "Creating consistency group snapshot"
  CONSISTENCY_GROUP_NAME="app-consistency-group-$(date +%Y%m%d%H%M%S)"
  
  # Create snapshot directly using the existing consistency group policy
  echo "Creating snapshot from consistency group..."
  if ! gcloud compute snapshots create $CONSISTENCY_GROUP_NAME \
    --resource-policy=app-consistency-group \
    --region=us-central1 \
    --description="Consistency group snapshot for multi-region DR failover"; then
    echo "WARNING: Failed to create consistency group snapshot, falling back to individual snapshot..."
    
    # Fallback to individual snapshot
    SNAPSHOT_NAME="boot-snapshot-multiregion-$(date +%Y%m%d%H%M%S)"
    if ! gcloud compute snapshots create $SNAPSHOT_NAME \
      --source-disk=app-primary-boot-disk \
      --source-disk-zone=us-central1-a \
      --snapshot-type=STANDARD \
      --description="Snapshot for multi-region DR failover"; then
      echo "WARNING: Failed to create boot disk snapshot, continuing failover..."
    fi
    
    # Wait for snapshot to complete with exponential backoff
    wait_with_backoff "gcloud compute snapshots describe $SNAPSHOT_NAME --format='value(status)' 2>/dev/null || echo 'NOT_FOUND'" "READY" 10 2 10 "Snapshot creation"
  else
    # Wait for consistency group snapshot to complete with exponential backoff
    wait_with_backoff "gcloud compute snapshots describe $CONSISTENCY_GROUP_NAME --format='value(status)' 2>/dev/null || echo 'NOT_FOUND'" "READY" 10 2 10 "Consistency group snapshot creation"
  fi
  
  # Step 4: Stop asynchronous replication between regions
  status "Stopping asynchronous replication between regions"
  # Check if regional disk exists
  if gcloud compute disks describe app-regional-disk --region=us-central1 >/dev/null 2>&1; then
    # Check if replication policy exists
    if gcloud compute resource-policies describe app-cross-region-replication --region=us-central1 >/dev/null 2>&1; then
      # Check if the policy is actually attached to the disk
      DISK_POLICIES=$(gcloud compute disks describe app-regional-disk --region=us-central1 --format="value(resourcePolicies)" 2>/dev/null || echo "")
      
      if [[ $DISK_POLICIES == *"app-cross-region-replication"* ]]; then
        # Remove the cross-region replication policy from the regional disk
        if ! gcloud compute disks remove-resource-policies app-regional-disk \
          --resource-policies=app-cross-region-replication \
          --region=us-central1; then
          echo "WARNING: Failed to stop replication, continuing failover..."
        else
          echo "Asynchronous replication stopped successfully"
        fi
      else
        echo "Replication policy is not attached to the disk, skipping removal"
      fi
    else
      echo "WARNING: Cross-region replication policy not found, skipping replication stop"
    fi
  else
    echo "WARNING: Regional disk not found in primary region, skipping replication stop"
  fi
  
  # If we started DB promotion, wait for it to complete now
  if [[ -n "$DB_PROMOTION_PID" ]]; then
    status "Waiting for DB promotion to complete"
    # First wait for the background process to finish
    if wait $DB_PROMOTION_PID; then
      echo "DB promotion command completed successfully"
    else
      echo "ERROR: DB promotion command failed. Aborting failover."
      exit 1
    fi
    
    # Then verify the DB is actually promoted using exponential backoff
    if ! wait_with_backoff "gcloud sql instances describe app-db-instance-dr-secondary --format='value(state),value(masterInstanceName)' 2>/dev/null || echo 'NOT_FOUND,ERROR'" "RUNNABLE," 30 5 30 "DB promotion"; then
      echo "WARNING: DB promotion verification timed out, but continuing failover..."
    fi
  fi
  
  # Step 5: Check if secondary VM exists and prepare VM and disk in parallel
  status "Checking secondary VM status"
  if ! gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b >/dev/null 2>&1; then
    echo "ERROR: Secondary VM not found. Aborting failover."
    exit 1
  fi
  
  # Step 6: Check if secondary regional disk exists
  status "Checking for secondary regional disk"
  SECONDARY_DISK_EXISTS=false
  if gcloud compute disks describe app-secondary-regional-disk --region=us-east1 >/dev/null 2>&1; then
    SECONDARY_DISK_EXISTS=true
  elif gcloud compute disks describe app-secondary-regional-disk --zone=us-east1-b >/dev/null 2>&1; then
    SECONDARY_DISK_EXISTS=true
    SECONDARY_DISK_ZONE="--zone=us-east1-b"
  else
    echo "WARNING: Secondary regional disk not found, skipping attachment"
  fi
  
  # Start VM and attach disk operations in parallel
  PARALLEL_CMDS=()
  
  # Step 7: Ensure secondary VM has its regional disk attached if it exists
  if [[ "$SECONDARY_DISK_EXISTS" == "true" ]]; then
    status "Ensuring secondary VM has its regional disk attached"
    SECONDARY_VM_DISKS=$(gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b --format="value(disks[].source)" 2>/dev/null || echo "")
    
    if [[ $SECONDARY_VM_DISKS != *"app-secondary-regional-disk"* ]]; then
      echo "Attaching secondary regional disk to secondary VM..."
      if [[ -n "$SECONDARY_DISK_ZONE" ]]; then
        # Zonal disk
        ATTACH_CMD="gcloud compute instances attach-disk app-web-server-dr-secondary-primary --disk=app-secondary-regional-disk --device-name=app-data-disk --zone=us-east1-b"
      else
        # Regional disk
        ATTACH_CMD="gcloud compute instances attach-disk app-web-server-dr-secondary-primary --disk=app-secondary-regional-disk --disk-scope=regional --device-name=app-data-disk --zone=us-east1-b"
      fi
      PARALLEL_CMDS+=("$ATTACH_CMD")
    else
      echo "Secondary regional disk already attached to secondary VM"
    fi
  fi
  
  # Step 8: Start secondary region primary VM if not already running
  status "Starting secondary region primary VM"
  SECONDARY_VM_STATUS=$(gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
  
  if [[ "$SECONDARY_VM_STATUS" != "RUNNING" ]]; then
    PARALLEL_CMDS+=("gcloud compute instances start app-web-server-dr-secondary-primary --zone=us-east1-b")
  else
    echo "Secondary VM is already running"
  fi
  
  # Execute parallel commands if any
  if [[ ${#PARALLEL_CMDS[@]} -gt 0 ]]; then
    echo "Executing VM and disk operations in parallel..."
    run_in_parallel "${PARALLEL_CMDS[@]}"
    
    # Verify VM is running using exponential backoff
    wait_with_backoff "gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b --format='value(status)'" "RUNNING" 20 3 15 "VM startup"
    
    # Verify disk attachment if needed
    if [[ "$SECONDARY_DISK_EXISTS" == "true" && $SECONDARY_VM_DISKS != *"app-secondary-regional-disk"* ]]; then
      wait_with_backoff "gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b --format=\"value(disks[].source)\" | grep -q app-secondary-regional-disk && echo 'ATTACHED' || echo 'NOT_ATTACHED'" "ATTACHED" 10 2 10 "Disk attachment"
    fi
  fi
  
  # Step 9: Add VM to instance group if not already in it
  status "Adding VM to instance group"
  # Check if instance group exists
  if ! gcloud compute instance-groups unmanaged describe app-secondary-primary-group --zone=us-east1-b >/dev/null 2>&1; then
    echo "ERROR: Secondary instance group not found. Aborting failover."
    exit 1
  fi
  
  SECONDARY_IG_STATUS=$(gcloud compute instance-groups unmanaged list-instances app-secondary-primary-group --zone=us-east1-b --format="value(instance)" 2>/dev/null || echo "")
  
  if [[ $SECONDARY_IG_STATUS != *"app-web-server-dr-secondary-primary"* ]]; then
    echo "Adding secondary VM to instance group..."
    gcloud compute instance-groups unmanaged add-instances app-secondary-primary-group \
      --zone=us-east1-b \
      --instances=app-web-server-dr-secondary-primary
  else
    echo "Secondary VM is already in the instance group"
  fi
  
  # Step 10: Update backend service to route traffic to secondary region
  status "Updating backend service to route traffic to secondary region"
  
  # Check if backend service exists
  if ! gcloud compute backend-services describe app-backend-service --global >/dev/null 2>&1; then
    echo "ERROR: Backend service not found. Aborting failover."
    exit 1
  fi
  
  # Get current backends to check which instance groups are registered
  BACKEND_INFO=$(gcloud compute backend-services describe app-backend-service --global --format="json" 2>/dev/null)
  
  # Function to check if instance group is registered with backend service
  is_backend_registered() {
    local instance_group=$1
    local zone=$2
    
    # Check if the instance group is in the backend service
    if echo "$BACKEND_INFO" | grep -q "\"group\": \"https://www.googleapis.com/compute/v1/projects/$PROJECT_ID/zones/$zone/instanceGroups/$instance_group\""; then
      return 0  # True, it's registered
    else
      return 1  # False, it's not registered
    fi
  }
  
  # Function to add instance group to backend service if not already registered
  ensure_backend_registered() {
    local instance_group=$1
    local zone=$2
    
    if ! is_backend_registered "$instance_group" "$zone"; then
      echo "Adding instance group $instance_group in zone $zone to backend service..."
      if ! gcloud compute backend-services add-backend app-backend-service \
        --global \
        --instance-group=$instance_group \
        --instance-group-zone=$zone \
        --capacity-scaler=0.0; then
        echo "WARNING: Failed to add instance group $instance_group to backend service"
        return 1
      fi
      echo "Successfully added instance group $instance_group to backend service"
    fi
    return 0
  }
  
  # Update primary region backends (set to inactive)
  if gcloud compute instance-groups unmanaged describe app-primary-group --zone=us-central1-a >/dev/null 2>&1; then
    # Ensure the instance group is registered with the backend service
    ensure_backend_registered "app-primary-group" "us-central1-a"
    
    # Now update the capacity scaler
    if is_backend_registered "app-primary-group" "us-central1-a"; then
      if ! gcloud compute backend-services update-backend app-backend-service \
        --global \
        --instance-group=app-primary-group \
        --instance-group-zone=us-central1-a \
        --capacity-scaler=0.0; then
        echo "WARNING: Failed to update primary backend, continuing failover..."
      else
        echo "Successfully updated primary backend capacity to 0.0"
      fi
    else
      echo "Primary instance group not registered with backend service, skipping update"
    fi
  else
    echo "Primary instance group not found, skipping backend update"
  fi
  
  if gcloud compute instance-groups unmanaged describe app-standby-group --zone=us-central1-c >/dev/null 2>&1; then
    # Ensure the instance group is registered with the backend service
    ensure_backend_registered "app-standby-group" "us-central1-c"
    
    # Now update the capacity scaler
    if is_backend_registered "app-standby-group" "us-central1-c"; then
      if ! gcloud compute backend-services update-backend app-backend-service \
        --global \
        --instance-group=app-standby-group \
        --instance-group-zone=us-central1-c \
        --capacity-scaler=0.0; then
        echo "WARNING: Failed to update standby backend, continuing failover..."
      else
        echo "Successfully updated standby backend capacity to 0.0"
      fi
    else
      echo "Standby instance group not registered with backend service, skipping update"
    fi
  else
    echo "Standby instance group not found, skipping backend update"
  fi
  
  # Update secondary region backends (set to active)
  if gcloud compute instance-groups unmanaged describe app-secondary-primary-group --zone=us-east1-b >/dev/null 2>&1; then
    # Ensure the instance group is registered with the backend service
    if ! ensure_backend_registered "app-secondary-primary-group" "us-east1-b"; then
      echo "ERROR: Failed to register secondary primary group with backend service. Aborting failover."
      exit 1
    fi
    
    # Now update the capacity scaler
    if is_backend_registered "app-secondary-primary-group" "us-east1-b"; then
      if ! gcloud compute backend-services update-backend app-backend-service \
        --global \
        --instance-group=app-secondary-primary-group \
        --instance-group-zone=us-east1-b \
        --capacity-scaler=1.0; then
        echo "ERROR: Failed to update secondary backend. Aborting failover."
        exit 1
      else
        echo "Successfully updated secondary primary backend capacity to 1.0"
      fi
    else
      echo "ERROR: Secondary primary instance group not registered with backend service. Aborting failover."
      exit 1
    fi
  else
    echo "ERROR: Secondary primary instance group not found. Aborting failover."
    exit 1
  fi
  
  if gcloud compute instance-groups unmanaged describe app-secondary-standby-group --zone=us-east1-c >/dev/null 2>&1; then
    # Ensure the instance group is registered with the backend service
    ensure_backend_registered "app-secondary-standby-group" "us-east1-c"
    
    # Now update the capacity scaler
    if is_backend_registered "app-secondary-standby-group" "us-east1-c"; then
      if ! gcloud compute backend-services update-backend app-backend-service \
        --global \
        --instance-group=app-secondary-standby-group \
        --instance-group-zone=us-east1-c \
        --capacity-scaler=0.0; then
        echo "WARNING: Failed to update secondary standby backend, continuing failover..."
      else
        echo "Successfully updated secondary standby backend capacity to 0.0"
      fi
    else
      echo "Secondary standby instance group not registered with backend service, skipping update"
    fi
  else
    echo "Secondary standby instance group not found, skipping backend update"
  fi
  
  # Step 11: Wait for application to initialize (shorter wait with verification)
  status "Waiting for application to initialize"
  sleep 15
  
  # Step 12: Verify the failover
  status "Verifying failover"
  
  # Run verification checks in parallel
  echo "Running verification checks in parallel..."
  
  # Check if secondary VM is running
  SECONDARY_VM_STATUS=$(gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
  echo "Secondary VM status: $SECONDARY_VM_STATUS"
  
  # Check if secondary DB is primary
  SECONDARY_DB_STATUS=$(gcloud sql instances describe app-db-instance-dr-secondary --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
  echo "Secondary DB status: $SECONDARY_DB_STATUS"
  
  # Check if secondary VM is in instance group
  SECONDARY_IG_STATUS=$(gcloud compute instance-groups unmanaged list-instances app-secondary-primary-group --zone=us-east1-b --format="value(instance)" 2>/dev/null || echo "")
  if [[ $SECONDARY_IG_STATUS == *"app-web-server-dr-secondary-primary"* ]]; then
    echo "Secondary VM is in instance group"
  else
    echo "Secondary VM is NOT in instance group"
  fi
  
  # Verify application using two-tier approach
  SECONDARY_IP=$(gcloud compute instances describe app-web-server-dr-secondary-primary --zone=us-east1-b --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || echo "")
  if [[ -n "$SECONDARY_IP" ]]; then
    verify_app_two_tier "$SECONDARY_IP" "us-east1-b"
  else
    echo "Could not get secondary VM IP address"
  fi
  
  # Calculate RTO
  end_time=$(date +%s)
  rto=$((end_time - start_time))
  echo "Multi-region failover completed in $rto seconds"
  
  # Write custom metrics
  write_custom_metric "recovery_time" "${rto}" "multiregion-failover"
  write_custom_metric "success_rate" "1.0" "multiregion-failover"
  
  status "Multi-region failover test completed"
  echo "To failback, run: $0 failback"
}

# Function to execute multi-region failback
multiregion_failback() {
  status "PERFORMING MULTI-REGION FAILBACK"
  
  # Record start time for RTO calculation
  start_time=$(date +%s)
  
  # Step 1: Create consistency group snapshot of secondary boot disk
  status "Creating consistency group snapshot of secondary boot disk"
  CONSISTENCY_GROUP_NAME="app-secondary-consistency-group-$(date +%Y%m%d%H%M%S)"
  SNAPSHOT_NAME="snapshot-failback-$(date +%Y%m%d%H%M%S)"
  
  # Check if secondary boot disk exists
  if ! gcloud compute disks describe app-secondary-primary-boot-disk --zone=us-east1-b >/dev/null 2>&1; then
    echo "ERROR: Secondary boot disk not found. Aborting failback."
    exit 1
  fi
  
  # Create snapshot directly using the existing consistency group policy
  echo "Creating snapshot from consistency group..."
  if ! gcloud compute snapshots create $CONSISTENCY_GROUP_NAME \
    --resource-policy=app-secondary-consistency-group \
    --region=us-east1 \
    --description="Consistency group snapshot for multi-region DR failback"; then
    echo "WARNING: Failed to create consistency group snapshot, falling back to individual snapshot..."
    
    # Fallback to individual snapshot
    if ! gcloud compute snapshots create $SNAPSHOT_NAME \
      --source-disk=app-secondary-primary-boot-disk \
      --source-disk-zone=us-east1-b \
      --snapshot-type=STANDARD \
      --description="Snapshot for multi-region DR failback"; then
      echo "WARNING: Failed to create secondary boot disk snapshot, continuing failback..."
    fi
    
    # Wait for snapshot to complete with exponential backoff
    wait_with_backoff "gcloud compute snapshots describe $SNAPSHOT_NAME --format='value(status)' 2>/dev/null || echo 'NOT_FOUND'" "READY" 10 2 10 "Snapshot creation"
  else
    # Use the consistency group snapshot name
    SNAPSHOT_NAME=$CONSISTENCY_GROUP_NAME
    
    # Wait for consistency group snapshot to complete with exponential backoff
    wait_with_backoff "gcloud compute
