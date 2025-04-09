#!/bin/bash
# Redirect all output to log file
exec > $HOME/startup-script.log 2>&1
set -x

# If running as root, do initial setup then re-run as 'goapp'
if [ "$(id -u)" -eq 0 ]; then
  # Create non-root user if it doesn't exist
  id -u goapp &>/dev/null || useradd -m -s /bin/bash goapp

  apt update
  apt install -y mysql-client ufw jq lynx curl git nginx

  # Open firewall ports for app and web
  ufw allow 8080
  ufw allow 80
  ufw allow 443

  # Generate self-signed certificate
  mkdir -p /etc/ssl/private
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google')"

  # Store certificate and key in Secret Manager
  gcloud secrets create ssl_cert --replication-policy="user-managed" \
    --locations="us-central1" --data-file="/etc/ssl/certs/nginx-selfsigned.crt" || \
    gcloud secrets versions add ssl_cert --data-file="/etc/ssl/certs/nginx-selfsigned.crt"
    
  gcloud secrets create ssl_key --replication-policy="user-managed" \
    --locations="us-central1" --data-file="/etc/ssl/private/nginx-selfsigned.key" || \
    gcloud secrets versions add ssl_key --data-file="/etc/ssl/private/nginx-selfsigned.key"

  # Create Nginx configuration
  cat > /etc/nginx/sites-available/app <<EOF
server {
    listen 80;
    server_name _;
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name _;
    
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  # Enable the site
  ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default

  # Restart Nginx
  systemctl restart nginx

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

# Clone application
mkdir -p ~/dr-demo
cd ~/dr-demo
git clone https://github.com/mseralessandri/demo_gcp.git . || exit 1

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
  DB_HOST=$(gcloud sql instances describe app-db-instance --format="value(ipAddresses[0].ipAddress)" 2>/dev/null)
  if [ -z "$DB_HOST" ]; then
    echo "Error: Cannot determine DB host"
    exit 1
  fi
fi

# Write .env file
cat > .env <<EOF
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=$DB_HOST
USE_SSL=true
EOF

# Export env vars
export DB_USER DB_PASSWORD DB_HOST USE_SSL=true

# Initialize and build the app
go mod init dr-demo 2>/dev/null || true
go get github.com/go-sql-driver/mysql
go get github.com/joho/godotenv
go get cloud.google.com/go/secretmanager/apiv1
go mod tidy
go build -o dr-demo main.go

# Start the app
nohup ./dr-demo > app.log 2>&1 &
