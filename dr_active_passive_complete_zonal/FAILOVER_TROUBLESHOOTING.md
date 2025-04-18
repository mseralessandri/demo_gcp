# Failover Troubleshooting Guide

This document provides troubleshooting steps for common issues encountered during the failover process, particularly when you see a "502 Server Error" message or when the load balancer doesn't properly route traffic to the standby instance.

## Common Error: "502 Server Error"

If you see the following error after failover:
```
Error: Server Error
The server encountered a temporary error and could not complete your request.
Please try again in 30 seconds.
```

This typically indicates that the load balancer is unable to successfully route traffic to the standby instance. Here's a systematic approach to troubleshoot and resolve this issue:

## Step 1: Verify Standby VM Status

First, check if the standby VM is running:

```bash
gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="table(name,status,networkInterfaces[0].accessConfigs[0].natIP)"
```

Expected output should show `RUNNING` status. If not, start the VM:

```bash
gcloud compute instances start app-web-server-dr-standby --zone=us-central1-c
```

## Step 2: Verify Application Status on Standby VM

Check if the application is running on the standby VM:

```bash
gcloud compute ssh app-web-server-dr-standby --zone=us-central1-c --command="ps aux | grep dr-demo"
```

If the application is not running, you may need to start it manually:

```bash
gcloud compute ssh app-web-server-dr-standby --zone=us-central1-c --command="cd /home/goapp/dr-demo && ./dr-demo &"
```

## Step 3: Check Network Listening Status

Verify that the application is listening on the correct port and interface:

```bash
gcloud compute ssh app-web-server-dr-standby --zone=us-central1-c --command="sudo ss -tulpn | grep 8080"
```

Expected output should show something like:
```
tcp   LISTEN 0      128    127.0.0.1:8080       0.0.0.0:*    users:(("dr-demo",pid=1234,fd=3))
```

If it's only listening on `127.0.0.1` (localhost) instead of `0.0.0.0` (all interfaces), you need to update the application to listen on all interfaces. See the main.go file for the correct configuration.

## Step 4: Test Direct Application Access

Try to access the application directly on the standby VM:

```bash
# Get the external IP of the standby VM
STANDBY_IP=$(gcloud compute instances describe app-web-server-dr-standby --zone=us-central1-c --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

# Test direct access
curl -v http://$STANDBY_IP:8080/web
```

If this works but the load balancer still shows an error, proceed to the next steps.

## Step 5: Check Instance Group Configuration

Verify that the standby VM is properly added to the standby instance group:

```bash
gcloud compute instance-groups unmanaged list-instances app-standby-group --zone=us-central1-c
```

If the standby VM is not in the group, add it:

```bash
gcloud compute instance-groups unmanaged add-instances app-standby-group --zone=us-central1-c --instances=app-web-server-dr-standby
```

## Step 6: Check Named Ports Configuration

Verify that the instance group has the correct named port configuration:

```bash
gcloud compute instance-groups unmanaged get-named-ports app-standby-group --zone=us-central1-c
```

Expected output should show:
```
NAME      PORT
http8080  8080
```

If not, set the named port:

```bash
gcloud compute instance-groups unmanaged set-named-ports app-standby-group --zone=us-central1-c --named-ports=http8080:8080
```

## Step 7: Check Backend Service Configuration

Verify that the backend service is configured to use the correct port name:

```bash
gcloud compute backend-services describe app-backend-service --global --format="json(port, portName)"
```

Expected output should show:
```json
{
  "port": 80,
  "portName": "http8080"
}
```

