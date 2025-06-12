#!/bin/bash
# =============================================================================
# DR WORKFLOW TEST SCRIPT
# =============================================================================

# Function to display status
status() {
  echo "===== $1 ====="
}

# Function to execute workflow and wait for completion
execute_workflow() {
  local workflow_name=$1
  local arguments=$2
  local project_id=$(gcloud config get-value project)
  local region="us-central1"  # Use your region
  
  status "Executing workflow: $workflow_name"
  
    # Execute the workflow
    echo "Executing workflow with arguments: $arguments"
    EXECUTION_FULL_NAME=$(gcloud workflows run $workflow_name \
      --data="$arguments" \
      --location=$region \
      --format="value(name)")
  
  # Extract just the execution ID from the full name
  EXECUTION_ID=$(echo $EXECUTION_FULL_NAME | sed 's|.*/||')
  
  # Debug output
  echo "Full execution name: $EXECUTION_FULL_NAME"
  echo "Execution ID: $EXECUTION_ID"
  
  # Check if execution ID was extracted properly
  if [[ -z "$EXECUTION_ID" ]]; then
    echo "ERROR: Failed to extract execution ID"
    echo "Full response: $EXECUTION_FULL_NAME"
    return 1
  fi
  
  # Wait for workflow completion
  status "Waiting for workflow completion"
  while true; do
    STATE=$(gcloud workflows executions describe $EXECUTION_ID \
      --workflow=$workflow_name \
      --location=$region \
      --format="value(state)")
    
    if [[ "$STATE" == "SUCCEEDED" ]]; then
      status "Workflow completed successfully"
      break
    elif [[ "$STATE" == "FAILED" ]]; then
      status "Workflow failed"
      gcloud workflows executions describe $EXECUTION_ID \
        --workflow=$workflow_name \
        --location=$region
      return 1
    else
      echo "Workflow is still running (state: $STATE)..."
      sleep 5
    fi
  done
  
  # Get the workflow result
  RESULT=$(gcloud workflows executions describe $EXECUTION_ID \
    --workflow=$workflow_name \
    --location=$region \
    --format="value(result)")
  
  # Display the result
  echo $RESULT | jq .
  
  return 0
}

# Function to check environment status
check_status() {
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
}

# Function to show recent workflow executions
show_recent_executions() {
  local workflow_name=$1
  local region="us-central1"
  
  echo "Recent executions of $workflow_name:"
  gcloud workflows executions list \
    --workflow=$workflow_name \
    --limit=5 \
    --location=$region \
    --format="table(name.basename(), startTime, state, duration)"
}

# Function to open the monitoring dashboard
open_dashboard() {
  local project_id=$(gcloud config get-value project)
  echo "Opening DR Complete Dashboard..."
  open "https://console.cloud.google.com/monitoring/dashboards?project=$project_id"
}

# -----------------------------------------------------------------------------
# USAGE INFORMATION
# -----------------------------------------------------------------------------

# Show usage information
function show_usage {
  echo "DR Workflow Test Script"
  echo "Usage: $0 [command]"
  echo ""
  echo "Available commands:"
  echo "  status        - Show current status of primary and standby resources"
  echo "  failover      - Simulate failure and perform failover to standby zone"
  echo "  failback      - Perform failback to primary zone"
  echo "  monitor       - Show recent workflow executions and open monitoring dashboard"
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

# Process command
case "$1" in
  status)
    check_status
    ;;
    
  failover)
    # Check if snapshots exist
    echo "Checking for existing snapshots..."
    BOOT_SNAPSHOTS=$(gcloud compute snapshots list --filter="sourceDisk:app-primary-boot-disk" --limit=1 --format="value(name)" 2>/dev/null)
    
    if [[ -n "$BOOT_SNAPSHOTS" ]]; then
      echo "✓ Found existing boot disk snapshots - reusing for fast demo"
      execute_workflow "dr-failover-workflow" '{}'
    else
      echo "⚠ No existing snapshots found - creating new ones (this may take longer)"
      execute_workflow "dr-failover-workflow" '{}'
    fi
    ;;
    
  failback)
    execute_workflow "dr-failback-workflow" '{}'
    ;;
    
  monitor)
    status "MONITORING DR OPERATIONS"
    show_recent_executions "dr-failover-workflow"
    show_recent_executions "dr-failback-workflow"
    open_dashboard
    ;;
    
  test-all)
    status "RUNNING COMPLETE DR DEMO"
    
    # Show initial status
    echo "This will demonstrate the full DR lifecycle:"
    echo "1. Show initial status"
    echo "2. Perform failover to standby zone"
    echo "3. Perform failback to primary zone"
    echo ""
    read -p "Press Enter to begin..." dummy
    
    # Show status
    check_status
    
    # Perform failover
    echo ""
    read -p "Press Enter to begin failover..." dummy
    execute_workflow "dr-failover-workflow" '{}'
    
    # Perform failback
    echo ""
    read -p "Press Enter to begin failback..." dummy
    execute_workflow "dr-failback-workflow" '{}'
    
    # Show final status
    echo ""
    read -p "Press Enter to check final status..." dummy
    check_status
    
    status "Complete DR demo finished successfully!"
    ;;
    
  *)
    echo "Unknown command: $1"
    show_usage
    exit 1
    ;;
esac
