#!/bin/bash
# =============================================================================
# DR DELTA CLEANUP SCRIPT
# =============================================================================
# This script deletes resources that terraform destroy might not handle properly
# It should be run after 'terraform destroy' to clean up any remaining resources
# It focuses on:
# - Resources that might have dependency issues
# - Resources that might be protected or locked
# - Resources that might have been created outside of Terraform

# Set error handling
set -e
set -o pipefail

# Function to display status
status() {
  echo ""
  echo "===== $1 ====="
}

# Function to run command with error handling
run_cmd() {
  local cmd="$1"
  local msg="$2"
  
  eval "$cmd" 2>/dev/null || echo "$msg"
}

status "STARTING DR DELTA CLEANUP"

# Set project ID
PROJECT_ID=$(gcloud config get-value project)
status "Using project: $PROJECT_ID"

# Check for service account issues
status "Checking for service account issues"
SA_EXISTS=$(gcloud iam service-accounts list --filter="email:dr-service-account@$PROJECT_ID.iam.gserviceaccount.com" --format="value(email)" 2>/dev/null || echo "")
if [ ! -z "$SA_EXISTS" ]; then
  echo "Service account still exists after terraform destroy, cleaning up..."
  run_cmd "gcloud iam service-accounts delete dr-service-account@$PROJECT_ID.iam.gserviceaccount.com --quiet" "Failed to delete service account"
fi

# Check for disk issues
status "Checking for disk issues"
DISKS_TO_CHECK=("app-primary-boot-disk" "app-standby-boot-disk" "app-regional-disk" "app-standby-disk-failover")
ZONES=("us-central1-a" "us-central1-c")

for DISK in "${DISKS_TO_CHECK[@]}"; do
  # Check zonal disks
  for ZONE in "${ZONES[@]}"; do
    DISK_EXISTS=$(gcloud compute disks list --filter="name=$DISK zone:$ZONE" --format="value(name)" 2>/dev/null || echo "")
    if [ ! -z "$DISK_EXISTS" ]; then
      echo "Disk $DISK still exists in zone $ZONE after terraform destroy, cleaning up..."
      run_cmd "gcloud compute disks delete $DISK --zone=$ZONE --quiet" "Failed to delete disk $DISK in zone $ZONE"
    fi
  done
  
  # Check regional disk
  if [ "$DISK" == "app-regional-disk" ]; then
    REGIONAL_DISK_EXISTS=$(gcloud compute disks list --filter="name=$DISK region:us-central1" --format="value(name)" 2>/dev/null || echo "")
    if [ ! -z "$REGIONAL_DISK_EXISTS" ]; then
      echo "Regional disk $DISK still exists after terraform destroy, cleaning up..."
      run_cmd "gcloud compute disks delete $DISK --region=us-central1 --quiet" "Failed to delete regional disk $DISK"
    fi
  fi
done

# Check for snapshot schedule issues
status "Checking for snapshot schedule issues"
SCHEDULE_EXISTS=$(gcloud compute resource-policies list --filter="name:app-snapshot-schedule" --format="value(name)" 2>/dev/null || echo "")
if [ ! -z "$SCHEDULE_EXISTS" ]; then
  echo "Snapshot schedule still exists after terraform destroy, cleaning up..."
  for SCHEDULE in $SCHEDULE_EXISTS; do
    run_cmd "gcloud compute resource-policies delete $SCHEDULE --region=us-central1 --quiet" "Failed to delete snapshot schedule $SCHEDULE"
  done
fi

# Check for load balancer component issues
status "Checking for load balancer component issues"
# Check forwarding rules
FORWARDING_RULES=("app-http-forwarding-rule" "app-https-forwarding-rule" "app-forwarding-rule")
for RULE in "${FORWARDING_RULES[@]}"; do
  RULE_EXISTS=$(gcloud compute forwarding-rules list --filter="name=$RULE" --format="value(name)" 2>/dev/null || echo "")
  if [ ! -z "$RULE_EXISTS" ]; then
    echo "Forwarding rule $RULE still exists after terraform destroy, cleaning up..."
    run_cmd "gcloud compute forwarding-rules delete $RULE --global --quiet" "Failed to delete forwarding rule $RULE"
  fi
done

# Check proxies
PROXIES=("app-http-proxy" "app-https-proxy")
for PROXY in "${PROXIES[@]}"; do
  PROXY_EXISTS=$(gcloud compute target-http-proxies list --filter="name=$PROXY" --format="value(name)" 2>/dev/null || echo "")
  if [ ! -z "$PROXY_EXISTS" ]; then
    echo "Proxy $PROXY still exists after terraform destroy, cleaning up..."
    run_cmd "gcloud compute target-http-proxies delete $PROXY --quiet" "Failed to delete HTTP proxy $PROXY"
  fi
  
  HTTPS_PROXY_EXISTS=$(gcloud compute target-https-proxies list --filter="name=$PROXY" --format="value(name)" 2>/dev/null || echo "")
  if [ ! -z "$HTTPS_PROXY_EXISTS" ]; then
    echo "HTTPS proxy $PROXY still exists after terraform destroy, cleaning up..."
    run_cmd "gcloud compute target-https-proxies delete $PROXY --quiet" "Failed to delete HTTPS proxy $PROXY"
  fi
done

# Check SSL certificates
CERT_EXISTS=$(gcloud compute ssl-certificates list --filter="name:app-ssl-cert" --format="value(name)" 2>/dev/null || echo "")
if [ ! -z "$CERT_EXISTS" ]; then
  echo "SSL certificate still exists after terraform destroy, cleaning up..."
  run_cmd "gcloud compute ssl-certificates delete app-ssl-cert --quiet" "Failed to delete SSL certificate"
fi

# Check URL maps
URL_MAP_EXISTS=$(gcloud compute url-maps list --filter="name:app-url-map" --format="value(name)" 2>/dev/null || echo "")
if [ ! -z "$URL_MAP_EXISTS" ]; then
  echo "URL map still exists after terraform destroy, cleaning up..."
  run_cmd "gcloud compute url-maps delete app-url-map --quiet" "Failed to delete URL map"
fi

# Check backend services
BACKEND_EXISTS=$(gcloud compute backend-services list --filter="name:app-backend-service" --format="value(name)" 2>/dev/null || echo "")
if [ ! -z "$BACKEND_EXISTS" ]; then
  echo "Backend service still exists after terraform destroy, cleaning up..."
  run_cmd "gcloud compute backend-services delete app-backend-service --global --quiet" "Failed to delete backend service"
fi

# Check health checks
HEALTH_CHECK_EXISTS=$(gcloud compute health-checks list --filter="name:app-health-check" --format="value(name)" 2>/dev/null || echo "")
if [ ! -z "$HEALTH_CHECK_EXISTS" ]; then
  echo "Health check still exists after terraform destroy, cleaning up..."
  run_cmd "gcloud compute health-checks delete app-health-check --quiet" "Failed to delete health check"
fi

# Check for database issues
status "Checking for database issues"
DB_EXISTS=$(gcloud sql instances list --filter="name:app-db-instance-dr" --format="value(name)" 2>/dev/null || echo "")
if [ ! -z "$DB_EXISTS" ]; then
  echo "Database instance still exists after terraform destroy, cleaning up..."
  run_cmd "gcloud sql instances delete app-db-instance-dr --quiet" "Failed to delete database instance"
fi

# Check for storage bucket issues
status "Checking for storage bucket issues"
BUCKET_EXISTS=$(gsutil ls -b gs://microcloud-448817-dr-backups 2>/dev/null || echo "")
if [ ! -z "$BUCKET_EXISTS" ]; then
  echo "Storage bucket still exists after terraform destroy, cleaning up..."
  run_cmd "gsutil -m rm -r gs://microcloud-448817-dr-backups/**" "Failed to empty bucket"
  run_cmd "gsutil rb gs://microcloud-448817-dr-backups" "Failed to delete bucket"
fi

# Check for secret manager issues
status "Checking for secret manager issues"
SECRETS=("db_credentials" "ssl_cert" "ssl_key")
for SECRET in "${SECRETS[@]}"; do
  SECRET_EXISTS=$(gcloud secrets list --filter="name:$SECRET" --format="value(name)" 2>/dev/null || echo "")
  if [ ! -z "$SECRET_EXISTS" ]; then
    echo "Secret $SECRET still exists after terraform destroy, cleaning up..."
    run_cmd "gcloud secrets delete $SECRET --quiet" "Failed to delete secret $SECRET"
  fi
done

status "DELTA CLEANUP COMPLETE"
echo "All remaining resources have been cleaned up. You can now run terraform apply to recreate them."
