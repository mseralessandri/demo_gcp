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

  # Install Go
  export GO_VERSION="1.24.1"
  curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
  tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
  rm go${GO_VERSION}.linux-amd64.tar.gz
  chown -R goapp:goapp /usr/local/go

  # Re-run this script as non-root user
  cp "$0" /home/goapp/setup.sh
  chown goapp:goapp /home/goapp/setup.sh
  chmod +x /home/goapp/setup.sh
  sudo -u goapp -i /home/goapp/setup.sh

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

# Start the app
nohup ./dr-demo > app.log 2>&1 &
