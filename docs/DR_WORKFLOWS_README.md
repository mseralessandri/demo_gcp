# Disaster Recovery with Google Cloud Workflows

This implementation uses Google Cloud Workflows to orchestrate the disaster recovery process for the application. The workflows are triggered via shell scripts, providing a familiar interface while leveraging the reliability and monitoring capabilities of Google Cloud Workflows.

## Architecture

The disaster recovery solution consists of the following components:

1. **Google Cloud Workflows**: Serverless orchestration of the DR process
2. **Shell Scripts**: Interface for triggering workflows
3. **Terraform**: Infrastructure as code for deploying workflows
4. **Monitoring**: Dashboard and alerts for DR operations

## Deployment

The workflows are deployed using Terraform as part of the DR module. To deploy:

```bash
cd dr_active_passive_complete_zonal
terraform init
terraform apply
```

This will deploy:
- Failover workflow
- Failback workflow
- Monitoring dashboard
- Alert policies

## Usage

### Triggering Workflows

Use the provided shell script to trigger the workflows:

```bash
# Show current status
./dr_workflow_test.sh status

# Perform failover
./dr_workflow_test.sh failover

# Perform failback
./dr_workflow_test.sh failback

# Show monitoring information
./dr_workflow_test.sh monitor

# Run a complete DR test
./dr_workflow_test.sh test-all
```

### Monitoring

The implementation includes a comprehensive monitoring dashboard that shows:

#### Infrastructure Health
- Primary VM Status
- Standby VM Status
- Database Replication Lag
- Application Errors

#### DR Operations
- Workflow Executions
- Operation Latency
- Workflow Execution Status
- Recent Workflow Executions

#### Performance Metrics
- Recovery Time Objective (RTO) for both failover and failback
- DR Test Success Rate

To access the dashboard:
1. Go to the Google Cloud Console
2. Navigate to Monitoring > Dashboards
3. Select "DR Complete Dashboard"

Or run:
```bash
./dr_workflow_test.sh monitor
```

### Alerting

The implementation includes alerts for:
- Failed workflow executions
- High Recovery Time Objective (RTO)

Alerts are sent to the email address specified in the `notification_email` variable.

## Workflow Details

### Failover Workflow

The simplified failover workflow focuses on core operations:

1. **Create snapshot if needed** - Only creates a snapshot if explicitly requested
2. **Stop primary VM** - Stops the primary VM to prepare for failover
3. **Detach regional disk** - Detaches the regional disk from the primary VM
4. **Prepare standby VM** - Ensures the standby VM is stopped and ready
5. **Attach and start** - Attaches the regional disk to the standby VM and starts it
6. **Update load balancer** - Adds the standby VM to the instance group

### Failback Workflow

The simplified failback workflow focuses on essential operations:

1. **Stop standby VM** - Stops the standby VM and detaches the regional disk
2. **Start primary VM** - Starts the primary VM
3. **Attach regional disk** - Attaches the regional disk to the primary VM
4. **Update load balancer** - Removes the standby VM from the instance group

## Benefits Over Shell Scripts

This implementation offers several advantages over pure shell scripts:

1. **Reliability**: Automatic retries and error handling
2. **Monitoring**: Built-in execution history and metrics
3. **Alerting**: Notifications for failures and high RTO
4. **Auditability**: Complete execution history
5. **Serverless**: No need to maintain execution environments

## Customization

To customize the workflows:

1. Edit the workflow definitions in `modules/dr_active_passive_complete_zonal/workflows.tf`
2. Update the shell script in `dr_active_passive_complete_zonal/dr_workflow_test.sh`
3. Apply the changes with `terraform apply`

## Troubleshooting

If a workflow fails:

1. Check the workflow execution details in the Google Cloud Console
2. Run `./dr_workflow_test.sh monitor` to see recent executions
3. Check the logs for the workflow execution

Common issues:
- **Insufficient permissions**: The workflow service account may not have the necessary permissions
- **Resource not found**: Resources may have been deleted or renamed
- **API rate limits**: Too many API calls in a short period
- **Timeout**: Operations taking longer than expected

## Security Considerations

The workflows use a dedicated service account with the following permissions:
- Compute Admin: For managing VMs and disks
- Cloud SQL Admin: For managing database instances
- Monitoring Admin: For writing custom metrics

Ensure that this service account has only the necessary permissions and follows the principle of least privilege.

## Limitations

- Workflows are regional resources, so they must be deployed in the same region as the resources they manage
- The maximum execution time for a workflow is 1 year
- There are quotas for the number of workflow executions per minute

## Conclusion

This implementation provides a robust, reliable, and monitored disaster recovery solution using Google Cloud Workflows. By leveraging the serverless nature of workflows, you get the benefits of managed infrastructure while maintaining the familiar shell script interface.

The simplified workflows enhance this solution by reducing complexity, improving maintainability, and reducing execution time, all while maintaining the same functionality.
