#!/bin/bash
# =============================================================================
# SETUP SCRIPT FOR DR IMPLEMENTATION
# =============================================================================
# This script sets up the application without Nginx, allowing direct access
# from the load balancer.

# Redirect all output to log file
exec > $HOME/startup-script.log 2>&1
set -x

# If running as root, do initial setup then re-run as 'goapp'
if [ "$(id -u)" -eq 0 ]; then
  # Create non-root user if it doesn't exist
  id -u goapp &>/dev/null || useradd -m -s /bin/bash goapp

  apt update
  apt install -y mysql-client ufw jq lynx curl git

  # Open firewall port for app (direct access from load balancer)
  ufw allow 8080

  # Mount the regional disk if it exists
  DISK_DEVICE="/dev/disk/by-id/google-app-data-disk"
  MOUNT_POINT="/mnt/regional-disk"

  if [ -b "$DISK_DEVICE" ]; then
    echo "Regional disk found, mounting..."
    mkdir -p "$MOUNT_POINT"
    
    # Check if disk is formatted
    if ! blkid "$DISK_DEVICE"; then
      echo "Formatting disk..."
      mkfs.ext4 "$DISK_DEVICE"
    fi
    
    # Add to fstab for persistent mounting with nofail option to prevent boot failures
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
    echo "Regional disk not found, skipping mount"
  fi

  # Install Go
  export GO_VERSION="1.24.1"
  curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
  tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
  rm go${GO_VERSION}.linux-amd64.tar.gz
  chown -R goapp:goapp /usr/local/go

  # Create systemd service file for the application
  cat > /etc/systemd/system/dr-demo.service <<EOF
[Unit]
Description=DR Demo Application
After=network.target mnt-regional\\x2ddisk.mount
Wants=mnt-regional\\x2ddisk.mount

[Service]
Type=simple
User=goapp
WorkingDirectory=/home/goapp/dr-demo/app
EnvironmentFile=/home/goapp/dr-demo/app/.env
ExecStart=/home/goapp/dr-demo/app/dr-demo
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  # Enable the service (it will be started after the goapp user completes setup)
  systemctl enable dr-demo.service

  # Re-run this script as non-root user
  cp "$0" /home/goapp/setup.sh
  chown goapp:goapp /home/goapp/setup.sh
  chmod +x /home/goapp/setup.sh
  
  # Remove startup script metadata
  echo "Removing startup script metadata..."
  INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
  INSTANCE_ZONE=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | cut -d/ -f4)
  gcloud compute instances remove-metadata $INSTANCE_NAME --zone=$INSTANCE_ZONE --keys=startup-script
  
  # Run as goapp user to build the application
  sudo -u goapp -i /home/goapp/setup.sh
  
  # Start the service after goapp user has completed setup
  systemctl start dr-demo.service
  
  # Verify service is running
  if systemctl is-active --quiet dr-demo.service; then
    echo "Application service started successfully!"
  else
    echo "WARNING: Service failed to start. Check logs with: journalctl -u dr-demo.service"
  fi

  exit 0
fi

# ==== From here on, running as 'goapp' ====

# Set Go environment
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GOCACHE=$HOME/.cache/go-build
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
mkdir -p "$GOPATH"

# Clone or update application
mkdir -p ~/dr-demo
cd ~/dr-demo
if [ -d ".git" ]; then
  # Repository already exists, pull latest changes
  git pull
else
  # Fresh clone
  git clone https://github.com/mseralessandri/demo_gcp.git . || exit 1
fi

# Navigate to the app directory where main.go is located
cd app

echo "Retrieve DB credentials..."
set +x
# Retrieve secrets
DB_CREDENTIALS=$(gcloud secrets versions access latest --secret=db_credentials 2>/dev/null)
if [ $? -eq 0 ]; then
  DB_USER=$(echo "$DB_CREDENTIALS" | jq -r '.user')
  DB_PASSWORD=$(echo "$DB_CREDENTIALS" | jq -r '.password')
else
  DB_USER=$(gcloud secrets versions access latest --secret=db_user)
  DB_PASSWORD=$(gcloud secrets versions access latest --secret=db_password)
fi
set -x

# Get DB host from Terraform or fallback to gcloud
DB_HOST="${db_host}"
if [ -z "$DB_HOST" ]; then
  # Try all possible database instances
  for DB_INSTANCE in "app-db-instance" "app-db-instance-dr"; do
    DB_HOST=$(gcloud sql instances describe $DB_INSTANCE --format="value(ipAddresses[0].ipAddress)" 2>/dev/null)
    if [ ! -z "$DB_HOST" ]; then
      echo "Using database instance: $DB_INSTANCE"
      break
    fi
  done
  
  # If no instance found, exit with error
  if [ -z "$DB_HOST" ]; then
    echo "Error: Cannot determine DB host from any database instance"
    exit 1
  fi
else
  echo "Using provided database host: $DB_HOST"
fi

# Write .env file
cat > .env <<EOF
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=$DB_HOST
EOF

# Export env vars
export DB_USER DB_PASSWORD DB_HOST

# Initialize and build the app
go mod init dr-demo 2>/dev/null || true
go get github.com/go-sql-driver/mysql
go get github.com/joho/godotenv
go get cloud.google.com/go/secretmanager/apiv1
go mod tidy
go build -o dr-demo main.go

# The app will be started by systemd from the root part of the script
echo "Application built successfully. Service will be started by systemd."
