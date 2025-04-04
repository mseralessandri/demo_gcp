#!/bin/bash
# Update and install dependencies
exec > /var/log/startup-script.log 2>&1
set -x
sudo apt update
sudo apt install -y mysql-client golang ufw jq lynx

# Installa Go 1.24.1
export GO_VERSION="1.24.1"
wget https://go.dev/dl/go${"$"}{GO_VERSION}.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go${"$"}{GO_VERSION}.linux-amd64.tar.gz
rm go${"$"}{GO_VERSION}.linux-amd64.tar.gz

export GOROOT=/usr/local/go
export GOPATH=/root/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
export GOCACHE=/root/.cache/go-build  
export HOME=/root      
mkdir -p $GOPATH


# Setup Go application
mkdir -p ~/dr-demo
cd ~/dr-demo

# Clone the repository
git clone https://github.com/mseralessandri/demo_gcp.git .

# Retrieve secrets from Google Secret Manager
# First try to get the combined credentials for username and password
DB_CREDENTIALS=$(gcloud secrets versions access latest --secret=db_credentials 2>/dev/null)
if [ $? -eq 0 ]; then
  # Extract username and password from JSON
  DB_USER=$(echo $DB_CREDENTIALS | jq -r '.user')
  DB_PASSWORD=$(echo $DB_CREDENTIALS | jq -r '.password')
else
  # Fallback to individual secrets
  DB_USER=$(gcloud secrets versions access latest --secret=db_user)
  DB_PASSWORD=$(gcloud secrets versions access latest --secret=db_password)
fi

# Get the database host
# First try to use the template variable if provided by Terraform
DB_HOST="${db_host}"

if [ -n "$DB_HOST" ]; then
  echo "Using DB host from template: $DB_HOST"
else
  # Try to get the database host using gcloud
  echo "Falling back to fetching DB host via gcloud..."
  DB_HOST=$(gcloud sql instances describe app-db-instance --format="value(ipAddresses[0].ipAddress)" 2>/dev/null)
  
  # Check if DB_HOST is empty
  if [ -z "$DB_HOST" ]; then
    echo "Error: Could not determine database host. DB_HOST is not set."
    exit 1
  fi
fi

# Create .env file as a fallback if Secret Manager access fails
cat > .env << EOF
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=$DB_HOST
EOF

# Export database credentials
export DB_USER DB_PASSWORD DB_HOST

# Build and run the Go app
go get github.com/go-sql-driver/mysql
go get github.com/joho/godotenv
go get cloud.google.com/go/secretmanager/apiv1
go mod init dr-demo
go mod tidy
go build -o dr-demo main.go
nohup ./dr-demo &

# Optionally, open port for the Go app (if needed)
sudo ufw allow 8080
