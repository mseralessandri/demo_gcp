#!/bin/bash
# Update and install dependencies
sudo apt update
sudo apt install -y mysql-client golang ufw jq lynx

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

# Always dynamically retrieve the database host using gcloud
# This ensures we always have the current IP address
#DB_HOST=${db_host}
DB_HOST=$(gcloud sql instances describe app-db-instance --format="value(ipAddresses[0].ipAddress)")

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
