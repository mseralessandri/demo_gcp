# Active-Passive Complete Zonal DR Solution

This module implements a comprehensive disaster recovery (DR) solution using Google Cloud's native services. It provides an active-passive zonal DR architecture with complete backup and point-in-time recovery capabilities.

## Architecture

```mermaid
graph LR
    Client[Client] -->|HTTPS:443| HTTPSFR[HTTPS Forwarding Rule]
    Client -->|HTTP:80| HTTPFR[HTTP Forwarding Rule]
    
    HTTPSFR --> HTTPSProxy[HTTPS Proxy]
    HTTPFR --> HTTPProxy[HTTP Proxy]
    
    HTTPSProxy -->|SSL Termination| SSLCert[SSL Certificate]
    SSLCert --> URLMap[URL Map]
    HTTPProxy --> URLMap
    
    URLMap --> BackendService[Backend Service<br>port_name: http8080]
    BackendService --> HC[Health Check<br>port: 8080<br>path: /web]
    
    BackendService --> PrimaryIG[Primary Instance Group<br>named_port: http8080:8080]
    BackendService --> StandbyIG[Standby Instance Group<br>named_port: http8080:8080]
    
    subgraph "Primary Zone (us-central1-a)"
        PrimaryIG --> PrimaryVM[Primary VM<br>app listening on 0.0.0.0:8080]
        PrimaryVM --> PrimaryBoot[Primary Boot Disk]
        PrimaryVM --> RegionalDisk[Regional Persistent Disk<br>Mounted at /mnt/regional-disk]
    end
    
    subgraph "Standby Zone (us-central1-c)"
        StandbyIG --> StandbyVM[Standby VM<br>app listening on 0.0.0.0:8080]
        StandbyVM --> StandbyBoot[Standby Boot Disk]
        StandbyVM -.->|Attached during failover| RegionalDisk
    end
    
    subgraph "Database (Regional)"
        PrimaryVM -->|Read/Write| CloudSQL[Cloud SQL with HA]
        StandbyVM -.->|Failover Only| CloudSQL
        CloudSQL --> PrimaryDB[(Primary DB<br>us-central1-a)]
        CloudSQL --> StandbyDB[(Standby DB<br>us-central1-c)]
        PrimaryDB <-->|Sync Replication| StandbyDB
    end
    
    subgraph "Backup & Recovery"
        CloudSQL -->|Automated Backups| Backups[(Cloud SQL Backups)]
        CloudSQL -->|Binary Logging| BinLogs[(Binary Logs)]
        RegionalDisk -->|Snapshots| DiskSnapshots[(Disk Snapshots)]
    end
    
    classDef https fill:#32CD32,stroke:#333,stroke-width:1px;
    classDef http fill:#FFD700,stroke:#333,stroke-width:1px;
    classDef shared fill:#4682B4,stroke:#333,stroke-width:1px;
    classDef primary fill:#6495ED,stroke:#333,stroke-width:1px;
    classDef standby fill:#20B2AA,stroke:#333,stroke-width:1px;
    classDef db fill:#DAA520,stroke:#333,stroke-width:1px;
    classDef backup fill:#DA70D6,stroke:#333,stroke-width:1px;
    
    class HTTPSFR,HTTPSProxy,SSLCert https;
    class HTTPFR,HTTPProxy http;
    class URLMap,BackendService,HC shared;
    class PrimaryIG,PrimaryVM,PrimaryBoot primary;
    class StandbyIG,StandbyVM,StandbyBoot standby;
    class CloudSQL,PrimaryDB,StandbyDB db;
    class Backups,BinLogs,DiskSnapshots backup;
```

### Failover Scenarios

```mermaid
graph LR
    subgraph "Normal Operation"
        Client1[Client] -->|HTTP/HTTPS| LB1[Load Balancer]
        LB1 -->|Active| Primary1[Primary VM<br>us-central1-a<br>RUNNING]
        LB1 -.->|Standby| Standby1[Standby VM<br>us-central1-c<br>STOPPED]
        Primary1 -->|Attached| Disk1[Regional Disk]
        Primary1 -->|Read/Write| DB1[Cloud SQL Primary<br>us-central1-a]
        DB1 -->|Replication| DBStandby1[Cloud SQL Standby<br>us-central1-c]
    end
    
    subgraph "During Failover"
        Client2[Client] -->|HTTP/HTTPS| LB2[Load Balancer]
        LB2 -.->|Failing| Primary2[Primary VM<br>us-central1-a<br>FAILING]
        LB2 -->|Starting| Standby2[Standby VM<br>us-central1-c<br>STARTING]
        Primary2 -.->|Detaching| Disk2[Regional Disk]
        Standby2 -.->|Attaching| Disk2
        DB2[Cloud SQL Primary<br>us-central1-a] -->|Failover| DBStandby2[Cloud SQL Standby<br>us-central1-c]
    end
    
    subgraph "After Failover"
        Client3[Client] -->|HTTP/HTTPS| LB3[Load Balancer]
        LB3 -.->|Inactive| Primary3[Primary VM<br>us-central1-a<br>STOPPED]
        LB3 -->|Active| Standby3[Standby VM<br>us-central1-c<br>RUNNING]
        Standby3 -->|Attached| Disk3[Regional Disk]
        Standby3 -->|Read/Write| DBStandby3[Cloud SQL Primary<br>us-central1-c]
        DBStandby3 -->|Replication| DB3[Cloud SQL Standby<br>us-central1-a]
    end
    
    classDef normal fill:#6495ED,stroke:#333,stroke-width:1px;
    classDef failing fill:#FF6347,stroke:#333,stroke-width:1px;
    classDef failover fill:#FFA500,stroke:#333,stroke-width:1px;
    classDef recovered fill:#20B2AA,stroke:#333,stroke-width:1px;
    
    class Client1,LB1,Primary1,Standby1,Disk1,DB1,DBStandby1 normal;
    class Client2,LB2,Primary2,Standby2,Disk2,DB2,DBStandby2 failover;
    class Client3,LB3,Primary3,Standby3,Disk3,DB3,DBStandby3 recovered;
```

## Disk Replication Demonstration

This module demonstrates two different replication methods:

1. **Synchronous Replication** using a regional persistent disk
   - Data is written to both zones simultaneously
   - Zero RPO (Recovery Point Objective)
   - Immediate availability during failover
   - Files are stored in `/mnt/regional-disk/`

2. **Snapshot-based Replication** for the root disk
   - Data is backed up periodically via snapshots
   - Non-zero RPO (depends on snapshot frequency)
   - Requires restoration during failover
   - Files are stored in the application directory

The web interface displays data from both disks to clearly show the difference in replication methods during failover testing.

## Key Components

### 1. Compute Resources
- **Primary VM**: Active VM in the primary zone (us-central1-a)
- **Standby VM**: Dormant VM in the standby zone (us-central1-c)
- **Regional Persistent Disk**: Synchronously replicates data between zones, mounted at `/mnt/regional-disk`

### 2. Database Resources
- **Cloud SQL with HA**: Primary instance with standby replica in different zone
- **Automated Backups**: Regular backups with binary logging for point-in-time recovery

### 3. Networking
- **Load Balancer**: Routes traffic to the active instance
  - Supports both HTTP (port 80) and HTTPS (port 443)
  - SSL termination at the load balancer level
  - Self-signed certificates for HTTPS
- **Health Checks**: Monitors instance health on port 8080
- **Named Ports**: Configured for port 8080 (http8080)

### 4. Backup & Recovery
- **Disk Snapshots**: Regular snapshots of persistent disks
- **Database Backups**: Automated backups with point-in-time recovery
- **Backup Retention**: Configurable retention policies

### 5. Monitoring & Alerting
- **Custom Dashboard**: Visualizes DR metrics
- **Alert Policies**: Notifies of potential issues
- **Hybrid Approach**: Leverages both default GCP dashboards and custom metrics
- **Separate Alerts Configuration**: See [MONITORING_ALERTS.md](MONITORING_ALERTS.md) for details on applying alert policies

## Usage

```hcl
module "dr_complete" {
  source = "../modules/dr_active_passive_complete_zonal"
  
  project_id        = "your-project-id"
  region            = "us-central1"
  primary_zone      = "us-central1-a"
  standby_zone      = "us-central1-c"
  
  vm_machine_type   = "e2-medium"
  disk_size_gb      = 50
  
  db_name           = "app_database"
  db_user           = "app_user"
  db_password       = var.db_password
  
  notification_email = "alerts@example.com"
  setup_script_path  = "../setup.sh"
}
```

## Testing

The module includes both scheduled and on-demand testing capabilities:

### Scheduled Testing
- **Weekly Status Check**: Runs every Monday at 8 AM
- **Monthly Backup Test**: Runs on the 1st of each month at 2 AM
- **Quarterly Failover Test**: Runs on the 1st of every 3rd month at 1 AM (requires approval)

### On-Demand Testing
Use the `dr_demo_test.sh` script for on-demand testing:

```bash
# Check current status
./dr_demo_test.sh status

# Test failover
./dr_demo_test.sh failover

# Test failback
./dr_demo_test.sh failback

# Create backups
./dr_demo_test.sh backup

# Test disk restore
./dr_demo_test.sh restore-disk

# Test database point-in-time recovery
./dr_demo_test.sh restore-db

# Run complete DR test
./dr_demo_test.sh test-all
```

## Monitoring

The module uses a hybrid monitoring approach:

### Default GCP Dashboards
- VM Instances Dashboard
- Cloud SQL Dashboard
- Load Balancer Dashboard
- Persistent Disk Dashboard

### Custom DR Dashboard
A custom dashboard is created with the following widgets:
- Primary VM Status
- Standby VM Status
- Database Replication Lag
- DR Test Results
- Recovery Time

### Alert Policies
The module includes several alert policies:
- VM uptime alerts
- Database uptime alerts
- Database replication lag alerts
- Application error alerts (applied separately - see [MONITORING_ALERTS.md](MONITORING_ALERTS.md))

**Note**: Due to Google Cloud's limitations with custom metrics, some alert policies need to be applied separately after the main deployment. See [MONITORING_ALERTS.md](MONITORING_ALERTS.md) for detailed instructions.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | GCP project ID | string | n/a | yes |
| region | Region for regional resources | string | "us-central1" | no |
| primary_zone | Primary zone for zonal resources | string | "us-central1-a" | no |
| standby_zone | Standby zone for zonal resources | string | "us-central1-c" | no |
| vm_machine_type | Machine type for VMs | string | "e2-medium" | no |
| vm_image | Image for VM boot disks | string | "debian-cloud/debian-11" | no |
| disk_size_gb | Size of the regional disk in GB | number | 20 | no |
| boot_disk_size_gb | Size of the boot disk in GB | number | 10 | no |
| setup_script_path | Path to the setup script | string | "../setup.sh" | no |
| go_version | Version of Go to install | string | "1.24.1" | no |
| db_tier | Machine tier for Cloud SQL | string | "db-g1-small" | no |
| db_name | Database name | string | "app_database" | no |
| db_user | Database username | string | "app_user" | no |
| db_password | Database password | string | n/a | yes |
| backup_start_time | Start time for database backups (24h format) | string | "02:00" | no |
| transaction_log_retention_days | Number of days to retain transaction logs | number | 7 | no |
| retained_backups | Number of database backups to retain | number | 7 | no |
| deletion_protection | Enable deletion protection for the database | bool | false | no |
| maintenance_day | Day of week for maintenance window (1-7) | number | 7 | no |
| maintenance_hour | Hour of day for maintenance window (0-23) | number | 2 | no |
| notification_email | Email address for notifications | string | "admin@example.com" | no |
| error_threshold | Number of errors that trigger an alert | number | 5 | no |
| replication_lag_threshold_ms | Database replication lag threshold in milliseconds | number | 60000 | no |

## Outputs

| Name | Description |
|------|-------------|
| primary_vm_name | Name of the primary VM |
| primary_vm_zone | Zone of the primary VM |
| primary_vm_ip | External IP of the primary VM |
| standby_vm_name | Name of the standby VM |
| standby_vm_zone | Zone of the standby VM |
| standby_vm_ip | External IP of the standby VM |
| database_name | Name of the Cloud SQL instance |
| database_connection_name | Connection name of the Cloud SQL instance |
| database_ip | IP address of the Cloud SQL instance |
| load_balancer_http_ip | HTTP IP address of the load balancer |
| load_balancer_https_ip | HTTPS IP address of the load balancer |
| app_http_url | HTTP URL of the application |
| app_https_url | HTTPS URL of the application |
| backup_bucket_name | Name of the backup storage bucket |
| snapshot_schedule_name | Name of the snapshot schedule |
| dashboard_url | URL to the monitoring dashboard |
| service_account_email | Email of the service account |
| test_schedule_weekly | Schedule for weekly DR tests |
| test_schedule_monthly | Schedule for monthly DR tests |
| test_schedule_quarterly | Schedule for quarterly DR tests |

## Recovery Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| RTO (Recovery Time Objective) | < 15 minutes | Time to restore service |
| RPO (Recovery Point Objective) | 0 for disk, < 1 hour for VM | Potential data loss window |
| Failover Success Rate | > 99% | Percentage of successful failovers |
| Backup Success Rate | > 99.9% | Percentage of successful backups |

## SSL/TLS Implementation

This module includes HTTPS support with the following components:

- **SSL Certificate Resource**: `google_compute_ssl_certificate.app_ssl_cert`
- **HTTPS Proxy**: `google_compute_target_https_proxy.app_https_proxy`
- **HTTPS Forwarding Rule**: `google_compute_global_forwarding_rule.app_https_forwarding_rule`

The SSL certificate is expected to be provided as files:
- Private key: `certs/ssl.key`
- Certificate: `certs/ssl.crt`

The module is configured to use self-signed certificates by default, but you can replace them with certificates from a trusted Certificate Authority.

## Limitations

- This solution provides zonal DR within a single region
- For multi-region DR, additional components would be needed
- The standby VM is stopped by default to reduce costs
- Manual approval is required for scheduled failover tests
