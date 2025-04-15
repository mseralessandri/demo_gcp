# Architecture Diagram Instructions

The architecture diagram for the DR solution is defined in the README.md file using Mermaid syntax. To generate the diagram:

## Option 1: Using Mermaid Live Editor

1. Copy the Mermaid code from the README.md file:

```mermaid
graph TD
    subgraph "Primary Zone (us-central1-a)"
        PVM[Primary VM<br>ACTIVE]
        RPDisk1[Regional Persistent Disk<br>Primary Replica]
        PGroup[Primary Instance Group]
    end
    
    subgraph "Standby Zone (us-central1-c)"
        SVM[Standby VM<br>DORMANT]
        RPDisk2[Regional Persistent Disk<br>Secondary Replica]
        SGroup[Standby Instance Group]
    end
    
    RPDisk1 -- "Synchronous Replication" --> RPDisk2
    
    subgraph "Database (Regional)"
        PDB[(Primary DB<br>us-central1-c)]
        SDB[(Standby DB<br>us-central1-f)]
        PDB -- "Auto Failover" --> SDB
    end
    
    subgraph "Backup & Recovery"
        Snapshots[(Disk Snapshots)]
        DBBackups[(Database Backups)]
        PITR[Point-in-Time Recovery]
        
        RPDisk1 -- "Regular Snapshots" --> Snapshots
        PDB -- "Automated Backups" --> DBBackups
        DBBackups -- "Enables" --> PITR
    end
    
    subgraph "Testing & Monitoring"
        TestScript[DR Test Script]
        CloudFunc[Cloud Function]
        CloudSched[Cloud Scheduler]
        Dashboard[Monitoring Dashboard]
        Alerts[Alert Policies]
        
        CloudSched -- "Triggers" --> CloudFunc
        CloudFunc -- "Executes" --> TestScript
        TestScript -- "Tests" --> PVM
        TestScript -- "Tests" --> SVM
        TestScript -- "Tests" --> PDB
        
        Dashboard -- "Visualizes" --> PVM
        Dashboard -- "Visualizes" --> SVM
        Dashboard -- "Visualizes" --> PDB
    end
    
    LB[Load Balancer]
    LB -- "Routes to" --> PGroup
    LB -- "Routes to (during failover)" --> SGroup
    
    Users[Users] --> LB
```

2. Go to [Mermaid Live Editor](https://mermaid.live/)
3. Paste the code into the editor
4. Click "Download SVG" or "Download PNG" to save the diagram
5. Place the downloaded file in the `dr_active_passive_complete_zonal` directory with the name `architecture_diagram.png`

## Option 2: Using GitHub Markdown

If you're using GitHub, the Mermaid diagram will render automatically in the README.md file when viewed on GitHub.

## Option 3: Using VS Code Extension

1. Install the "Markdown Preview Mermaid Support" extension for VS Code
2. Open the README.md file
3. Right-click and select "Open Preview"
4. The diagram will render in the preview
5. Right-click on the diagram and select "Save as image"
6. Save the image as `architecture_diagram.png` in the `dr_active_passive_complete_zonal` directory
