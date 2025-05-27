# Google Cloud CLI Commands Reference

This document provides a comprehensive list of useful `gcloud` commands for managing and troubleshooting the disaster recovery solution, including the commands used during our implementation and troubleshooting sessions.

## Table of Contents

1. [Compute Engine Commands](#compute-engine-commands)
2. [Load Balancer Commands](#load-balancer-commands)
3. [Cloud SQL Commands](#cloud-sql-commands)
4. [Networking Commands](#networking-commands)
5. [Monitoring and Logging Commands](#monitoring-and-logging-commands)
6. [Storage and Backup Commands](#storage-and-backup-commands)
7. [Troubleshooting Commands](#troubleshooting-commands)

## Compute Engine Commands

### VM Instance Management

```bash
# List all VM instances
gcloud compute instances list

# Describe a specific VM instance
gcloud compute instances describe [INSTANCE_NAME] --zone=[ZONE]
# Example:
gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a

# Start a VM instance
gcloud compute instances start [INSTANCE_NAME] --zone=[ZONE]
# Example:
gcloud compute instances start app-web-server-dr-primary --zone=us-central1-a

# Stop a VM instance
gcloud compute instances stop [INSTANCE_NAME] --zone=[ZONE]
# Example:
gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c

# Reset (restart) a VM instance
gcloud compute instances reset [INSTANCE_NAME] --zone=[ZONE]
# Example:
gcloud compute instances reset app-web-server-dr-primary --zone=us-central1-a

# SSH into a VM instance
gcloud compute ssh [INSTANCE_NAME] --zone=[ZONE]
# Example:
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a

# SSH into a VM and run a command
gcloud compute ssh [INSTANCE_NAME] --zone=[ZONE] --command="[COMMAND]"
# Example:
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="ps aux | grep dr-demo"

# Get serial port output (useful for debugging boot issues)
gcloud compute instances get-serial-port-output [INSTANCE_NAME] --zone=[ZONE]
# Example:
gcloud compute instances get-serial-port-output app-web-server-dr-primary --zone=us-central1-a | tail -n 50
```

### Disk Management

```bash
# List all disks
gcloud compute disks list

# Create a disk
gcloud compute disks create [DISK_NAME] --zone=[ZONE] --size=[SIZE]
# Example:
gcloud compute disks create app-standby-disk-failover --zone=us-central1-c --size=10GB

# Create a disk from a snapshot
gcloud compute disks create [DISK_NAME] --source-snapshot=[SNAPSHOT_NAME] --zone=[ZONE]
# Example:
gcloud compute disks create app-standby-disk-failover --source-snapshot=boot-snapshot-20250418 --zone=us-central1-c

# Attach a disk to a VM
gcloud compute instances attach-disk [INSTANCE_NAME] --disk=[DISK_NAME] --zone=[ZONE]
# Example:
gcloud compute instances attach-disk app-web-server-dr-standby --disk=app-standby-disk-failover --zone=us-central1-c

# Detach a disk from a VM
gcloud compute instances detach-disk [INSTANCE_NAME] --disk=[DISK_NAME] --zone=[ZONE]
# Example:
gcloud compute instances detach-disk app-web-server-dr-standby --disk=app-standby-boot-disk --zone=us-central1-c
```

### Snapshot Management

```bash
# List all snapshots
gcloud compute snapshots list

# Create a snapshot of a disk
gcloud compute snapshots create [SNAPSHOT_NAME] --source-disk=[DISK_NAME] --source-disk-zone=[ZONE]
# Example:
gcloud compute snapshots create boot-snapshot-20250418 --source-disk=app-primary-boot-disk --source-disk-zone=us-central1-a

# Create a snapshot of a regional disk
gcloud compute snapshots create [SNAPSHOT_NAME] --source-disk=[DISK_NAME] --source-disk-region=[REGION]
# Example:
gcloud compute snapshots create data-snapshot-20250418 --source-disk=app-regional-disk --source-disk-region=us-central1

# Delete a snapshot
gcloud compute snapshots delete [SNAPSHOT_NAME]
# Example:
gcloud compute snapshots delete boot-snapshot-20250418
```

### Instance Groups

```bash
# List all instance groups
gcloud compute instance-groups list

# List instances in an instance group
gcloud compute instance-groups unmanaged list-instances [GROUP_NAME] --zone=[ZONE]
# Example:
gcloud compute instance-groups unmanaged list-instances app-primary-group --zone=us-central1-a

# Add an instance to an instance group
gcloud compute instance-groups unmanaged add-instances [GROUP_NAME] --zone=[ZONE] --instances=[INSTANCE_NAME]
# Example:
gcloud compute instance-groups unmanaged add-instances app-primary-group --zone=us-central1-a --instances=app-web-server-dr-primary

# Remove an instance from an instance group
gcloud compute instance-groups unmanaged remove-instances [GROUP_NAME] --zone=[ZONE] --instances=[INSTANCE_NAME]
# Example:
gcloud compute instance-groups unmanaged remove-instances app-standby-group --zone=us-central1-c --instances=app-web-server-dr-standby

# Get named ports for an instance group
gcloud compute instance-groups unmanaged get-named-ports [GROUP_NAME] --zone=[ZONE]
# Example:
gcloud compute instance-groups unmanaged get-named-ports app-primary-group --zone=us-central1-a

# Set named ports for an instance group
gcloud compute instance-groups unmanaged set-named-ports [GROUP_NAME] --zone=[ZONE] --named-ports=[NAME:PORT]
# Example:
gcloud compute instance-groups unmanaged set-named-ports app-primary-group --zone=us-central1-a --named-ports=http8080:8080
```

## Load Balancer Commands

### Backend Services

```bash
# List all backend services
gcloud compute backend-services list

# Describe a backend service
gcloud compute backend-services describe [BACKEND_SERVICE_NAME] --global
# Example:
gcloud compute backend-services describe app-backend-service --global

# Update a backend service
gcloud compute backend-services update [BACKEND_SERVICE_NAME] --global --port-name=[PORT_NAME]
# Example:
gcloud compute backend-services update app-backend-service --global --port-name=http8080

# Get health status of backends
gcloud compute backend-services get-health [BACKEND_SERVICE_NAME] --global
# Example:
gcloud compute backend-services get-health app-backend-service --global
```

### Health Checks

```bash
# List all health checks
gcloud compute health-checks list

# Describe a health check
gcloud compute health-checks describe [HEALTH_CHECK_NAME]
# Example:
gcloud compute health-checks describe app-health-check

# Update an HTTP health check
gcloud compute health-checks update http [HEALTH_CHECK_NAME] --port=[PORT] --request-path=[PATH]
# Example:
gcloud compute health-checks update http app-health-check --port=8080 --request-path=/web
```

### URL Maps and Proxies

```bash
# List all URL maps
gcloud compute url-maps list

# Describe a URL map
gcloud compute url-maps describe [URL_MAP_NAME]
# Example:
gcloud compute url-maps describe app-url-map

# List all target HTTP proxies
gcloud compute target-http-proxies list

# List all target HTTPS proxies
gcloud compute target-https-proxies list

# Describe a target HTTP proxy
gcloud compute target-http-proxies describe [PROXY_NAME]
# Example:
gcloud compute target-http-proxies describe app-http-proxy

# Describe a target HTTPS proxy
gcloud compute target-https-proxies describe [PROXY_NAME]
# Example:
gcloud compute target-https-proxies describe app-https-proxy
```

### Forwarding Rules

```bash
# List all forwarding rules
gcloud compute forwarding-rules list

# List global forwarding rules
gcloud compute forwarding-rules list --global

# Describe a forwarding rule
gcloud compute forwarding-rules describe [RULE_NAME] --global
# Example:
gcloud compute forwarding-rules describe app-http-forwarding-rule --global

# List forwarding rules with specific filter and format
gcloud compute forwarding-rules list --filter="name:app-http-forwarding-rule OR name:app-https-forwarding-rule" --format="table(name,IPAddress)"
```

## Cloud SQL Commands

```bash
# List all Cloud SQL instances
gcloud sql instances list

# Describe a Cloud SQL instance
gcloud sql instances describe [INSTANCE_NAME]
# Example:
gcloud sql instances describe app-db-instance-dr

# Create a backup of a Cloud SQL instance
gcloud sql backups create --instance=[INSTANCE_NAME]
# Example:
gcloud sql backups create --instance=app-db-instance-dr

# List backups for a Cloud SQL instance
gcloud sql backups list --instance=[INSTANCE_NAME]
# Example:
gcloud sql backups list --instance=app-db-instance-dr

# Clone a Cloud SQL instance at a specific point in time
gcloud sql instances clone [SOURCE_INSTANCE] [DESTINATION_INSTANCE] --point-in-time=[TIMESTAMP]
# Example:
gcloud sql instances clone app-db-instance-dr pitr-demo-instance --point-in-time="2025-04-18T15:00:00Z"
```

## Networking Commands

### Firewall Rules

```bash
# List all firewall rules
gcloud compute firewall-rules list

# Describe a firewall rule
gcloud compute firewall-rules describe [RULE_NAME]
# Example:
gcloud compute firewall-rules describe allow-health-checks-dr

# Create a firewall rule
gcloud compute firewall-rules create [RULE_NAME] --network=[NETWORK] --allow=[PROTOCOL:PORT] --source-ranges=[RANGES] --target-tags=[TAGS]
# Example:
gcloud compute firewall-rules create allow-health-checks-dr --network=default --allow=tcp:8080 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=web
```

### Network Connectivity Testing

```bash
# Test connectivity to a specific endpoint
curl -v [URL]
# Example:
curl -v http://34.8.247.74/web

# Test HTTPS connectivity (ignore certificate warnings)
curl -k -v https://[URL]
# Example:
curl -k -v https://34.95.80.240/web

# Check HTTP status code only
curl -s -o /dev/null -w "%{http_code}" [URL]
# Example:
curl -s -o /dev/null -w "%{http_code}" http://34.8.247.74/web
```

## Monitoring and Logging Commands

```bash
# View logs for a specific resource type
gcloud logging read "resource.type=[RESOURCE_TYPE]"
# Example:
gcloud logging read "resource.type=gce_instance"

# View error logs
gcloud logging read "resource.type=gce_instance AND textPayload=~\"Error|ERROR|error|Exception|EXCEPTION|exception\""

# View logs for a specific instance
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id=[INSTANCE_ID]"

# View load balancer logs
gcloud logging read "resource.type=http_load_balancer"

# List available metrics
gcloud monitoring metrics list

# List metrics for a specific resource
gcloud monitoring metrics list --filter="metric.type=compute.googleapis.com/instance/uptime"
```

## Storage and Backup Commands

```bash
# List all storage buckets
gsutil ls

# List objects in a bucket
gsutil ls gs://[BUCKET_NAME]
# Example:
gsutil ls gs://dr-backup-bucket

# Copy files to a bucket
gsutil cp [LOCAL_FILE] gs://[BUCKET_NAME]/
# Example:
gsutil cp backup.tar.gz gs://dr-backup-bucket/

# Download files from a bucket
gsutil cp gs://[BUCKET_NAME]/[OBJECT_NAME] [LOCAL_PATH]
# Example:
gsutil cp gs://dr-backup-bucket/backup.tar.gz ./
```

## Troubleshooting Commands

### Network Troubleshooting

```bash
# Check if a port is open and a service is listening
gcloud compute ssh [INSTANCE_NAME] --zone=[ZONE] --command="sudo ss -tulpn | grep [PORT]"
# Example:
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="sudo ss -tulpn | grep 8080"

# Check if a process is running
gcloud compute ssh [INSTANCE_NAME] --zone=[ZONE] --command="ps aux | grep [PROCESS_NAME]"
# Example:
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="ps aux | grep dr-demo"

# Check network connectivity from the VM
gcloud compute ssh [INSTANCE_NAME] --zone=[ZONE] --command="curl -v [URL]"
# Example:
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="curl -v http://localhost:8080/web"
```

### Instance Metadata and Configuration

```bash
# Get instance metadata
gcloud compute instances describe [INSTANCE_NAME] --zone=[ZONE] --format="json"
# Example:
gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format="json"

# Get specific metadata value
gcloud compute instances describe [INSTANCE_NAME] --zone=[ZONE] --format="value(tags.items)"
# Example:
gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format="value(tags.items)"
```

### Load Balancer Troubleshooting

```bash
# Check backend health
gcloud compute backend-services get-health [BACKEND_SERVICE_NAME] --global
# Example:
gcloud compute backend-services get-health app-backend-service --global

# Check backend service configuration
gcloud compute backend-services describe [BACKEND_SERVICE_NAME] --global --format="json(port, portName)"
# Example:
gcloud compute backend-services describe app-backend-service --global --format="json(port, portName)"
```

### SSL Certificate Management

```bash
# List SSL certificates
gcloud compute ssl-certificates list

# Describe an SSL certificate
gcloud compute ssl-certificates describe [CERTIFICATE_NAME]
# Example:
gcloud compute ssl-certificates describe app-ssl-cert
```

## Command Combinations for Common Tasks

### Complete Health Check

```bash
# Check VM status
gcloud compute instances describe app-web-server-dr-primary --zone=us-central1-a --format="table(name,status,networkInterfaces[0].accessConfigs[0].natIP)"

# Check if application is running
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="ps aux | grep dr-demo"

# Check if port is listening
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="sudo ss -tulpn | grep 8080"

# Check application response
gcloud compute ssh app-web-server-dr-primary --zone=us-central1-a --command="curl -v http://localhost:8080/web"

# Check load balancer health
gcloud compute backend-services get-health app-backend-service --global

# Test load balancer endpoints
curl -v http://$(terraform output -raw load_balancer_http_ip)/web
curl -k -v https://$(terraform output -raw load_balancer_https_ip)/web
```

### Failover Preparation

```bash
# Create snapshots before failover
gcloud compute snapshots create boot-snapshot-$(date +%Y%m%d%H%M%S) --source-disk=app-primary-boot-disk --source-disk-zone=us-central1-a
gcloud compute snapshots create data-snapshot-$(date +%Y%m%d%H%M%S) --source-disk=app-regional-disk --source-disk-region=us-central1

# Stop primary VM
gcloud compute instances stop app-web-server-dr-primary --zone=us-central1-a

# Start standby VM
gcloud compute instances start app-web-server-dr-standby --zone=us-central1-c

# Update instance group
gcloud compute instance-groups unmanaged add-instances app-standby-group --zone=us-central1-c --instances=app-web-server-dr-standby
```

### Failback Procedure

```bash
# Start primary VM
gcloud compute instances start app-web-server-dr-primary --zone=us-central1-a

# Remove standby VM from instance group
gcloud compute instance-groups unmanaged remove-instances app-standby-group --zone=us-central1-c --instances=app-web-server-dr-standby

# Stop standby VM
gcloud compute instances stop app-web-server-dr-standby --zone=us-central1-c
```

This document provides a comprehensive reference for the most useful gcloud commands for managing and troubleshooting the disaster recovery solution. For more detailed information about any command, you can use the `--help` flag, for example: `gcloud compute instances --help`.
