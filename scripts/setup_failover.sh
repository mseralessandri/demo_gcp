#!/bin/bash
# =============================================================================
# MINIMAL FAILOVER/FAILBACK SCRIPT FOR DR IMPLEMENTATION
# =============================================================================
# This script is designed specifically for failover and failback operations.
# It assumes the VM is booting from a snapshot that already has all packages
# and the application installed. It only performs the minimal operations needed
# to start the application with updated configuration.

# Redirect all output to log file
exec > $HOME/startup-script-failover.log 2>&1
set -x

echo "=== FAILOVER/FAILBACK SCRIPT STARTED ==="
echo "Timestamp: $(date)"

# If running as root, handle minimal root tasks then switch to goapp user
if [ "$(id -u)" -eq 0 ]; then
  echo "Running as root - performing minimal root tasks for failover"
  
  # Ensure goapp user exists (should exist from snapshot)
  id -u goapp &>/dev/null || useradd -m -s /bin/bash goapp
  
  # Only mount the regional disk if it exists (critical for DR)
  DISK_DEVICE="/dev/disk/by-id/google-app-data-disk"
  MOUNT_POINT="/mnt/regional-disk"

  if [ -b "$DISK_DEVICE" ]; then
    echo "Regional disk found, mounting..."
    mkdir -p "$MOUNT_POINT"
    
    # Check if already mounted
    if ! mountpoint -q "$MOUNT_POINT"; then
      # Add to fstab if not already there
      if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        echo "$DISK_DEVICE $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
      fi
      
      # Mount the disk
      mount "$MOUNT_POINT"
      
      # Set permissions
      chown -R goapp:goapp "$MOUNT_POINT"
      chmod 755 "$MOUNT_POINT"
      
      echo "Regional disk mounted at $MOUNT_POINT"
    else
      echo "Regional disk already mounted at $MOUNT_POINT"
    fi
  else
    echo "Regional disk not found, skipping mount"
  fi
  
  # Switch to goapp user for application operations
  cp "$0" /home/goapp/setup_failover.sh
  chown goapp:goapp /home/goapp/setup_failover.sh
  chmod +x /home/goapp/setup_failover.sh
  sudo -u goapp -i /home/goapp/setup_failover.sh

  exit 0
fi

# ==== From here on, running as 'goapp' ====
echo "Running as goapp user - starting application operations"

# Navigate to application directory (should exist from snapshot)
cd ~/dr-demo || {
  echo "ERROR: Application directory ~/dr-demo not found!"
  echo "This script is designed for failover/failback where the application should already exist."
  exit 1
}

# Verify application binary exists (should exist from snapshot)
if [ ! -f dr-demo ] || [ ! -x dr-demo ]; then
  echo "ERROR: Application binary ~/dr-demo/dr-demo not found or not executable!"
  echo "This script is designed for failover/failback where the application should already exist."
  exit 1
fi

echo "Application binary found - proceeding with failover/failback configuration"

# Get DB host (this is the only thing that might change during DR operations)
DB_HOST="${db_host}"
if [ -z "$DB_HOST" ]; then
  echo "DB_HOST not provided via template, attempting to discover..."
  # Try all possible database instances
  for DB_INSTANCE in "app-db-instance" "app-db-instance-dr"; do
    DB_HOST=$(gcloud sql instances describe $DB_INSTANCE --format="value(ipAddresses[0].ipAddress)" 2>/dev/null)
    if [ ! -z "$DB_HOST" ]; then
      echo "Using database instance: $DB_INSTANCE with IP: $DB_HOST"
      break
    fi
  done
  
  # If no instance found, exit with error
  if [ -z "$DB_HOST" ]; then
    echo "ERROR: Cannot determine DB host from any database instance"
    exit 1
  fi
else
  echo "Using provided database host: $DB_HOST"
fi

# Update .env file with current DB_HOST (preserve existing credentials)
if [ -f .env ]; then
  echo "Updating existing .env file with new DB_HOST: $DB_HOST"
  sed -i "s/DB_HOST=.*/DB_HOST=$DB_HOST/" .env
  echo "Updated .env file contents:"
  cat .env
else
  echo "No .env file found, creating new one..."
  # Get credentials from Secret Manager
  set +x
  DB_CREDENTIALS=$(gcloud secrets versions access latest --secret=db_credentials 2>/dev/null)
  if [ $? -eq 0 ]; then
    DB_USER=$(echo "$DB_CREDENTIALS" | jq -r '.user')
    DB_PASSWORD=$(echo "$DB_CREDENTIALS" | jq -r '.password')
    echo "Retrieved credentials from combined secret"
  else
    echo "Combined secret not found, trying individual secrets..."
    DB_USER=$(gcloud secrets versions access latest --secret=db_user)
    DB_PASSWORD=$(gcloud secrets versions access latest --secret=db_password)
    echo "Retrieved credentials from individual secrets"
  fi
  set -x
  
  cat > .env <<EOF
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=$DB_HOST
EOF
  echo "Created new .env file"
fi

# Stop any existing application process
echo "Checking for existing application processes..."
if pgrep -f "./dr-demo" > /dev/null; then
  echo "Found existing application process, stopping it..."
  pkill -f "./dr-demo"
  sleep 3
  
  # Force kill if still running
  if pgrep -f "./dr-demo" > /dev/null; then
    echo "Process still running, force killing..."
    pkill -9 -f "./dr-demo"
    sleep 2
  fi
  echo "Existing application process stopped"
else
  echo "No existing application process found"
fi

# Start the application
echo "Starting application for failover/failback..."
nohup ./dr-demo > app.log 2>&1 &
APP_PID=$!

# Wait a moment and verify the application started
sleep 3
if ps -p $APP_PID > /dev/null; then
  echo "Application started successfully with PID: $APP_PID"
else
  echo "ERROR: Application failed to start"
  echo "Last few lines of app.log:"
  tail -10 app.log 2>/dev/null || echo "No app.log found"
  exit 1
fi

echo "=== FAILOVER/FAILBACK SCRIPT COMPLETED SUCCESSFULLY ==="
echo "Timestamp: $(date)"
echo "Application is running with PID: $APP_PID"
echo "Database host: $DB_HOST"
