# Load Test Infrastructure and Cost Documentation

## Overview

This document describes the infrastructure required for load testing, associated costs, and the cost optimization features that are implemented.

## Required Infrastructure

### 1. EC2 Test Runner Instance

**Purpose**: Executes DSQL load tests from within the VPC with direct network access to the DSQL database.

**Configuration**:

- **Instance Type**: `m5a.2xlarge` (recommended for 1000-2000 thread tests)
  - **Specs**: 8 vCPU, 32 GB RAM
  - **Cost**: $0.344/hour (~$8.26/day)
  - **Cost Efficiency**: $0.0430/vCPU
- **Alternative Instance Types**:
  - **500-1000 threads**: `t3.xlarge` (4 vCPU, 16 GB RAM) - $0.17/hour
    - Better: `m5a.xlarge` (4 vCPU, 16 GB RAM) - $0.17/hour (dedicated CPU)
  - **2000-5000 threads**: `m5a.4xlarge` (16 vCPU, 64 GB RAM) - $0.69/hour
- **Network**: Private subnet (no public IP, access via SSM Session Manager)
- **Access**: AWS Systems Manager (SSM) Session Manager only (no SSH)
- **IAM Permissions**: DSQL database authentication, S3 read/write access
- **Software**: Java 21, Maven, Docker, PostgreSQL client, AWS CLI

**Terraform Variable**: `enable_dsql_test_runner_ec2` (default: `false`)

### 2. Bastion Host (Optional, Alternative to Test Runner)

**Purpose**: Alternative EC2 instance for database access and testing (smaller, not used for load tests).

**Configuration**:

- **Instance Type**: `t4g.nano` (default)
  - **Specs**: 2 vCPU, 0.5 GB RAM
  - **Cost**: ~$0.0034/hour (~$0.08/day)
- **Network**: Public subnet (with optional Elastic IP)
- **Access**: SSM Session Manager or SSH (optional)

**Terraform Variable**: `enable_bastion_host` (default: `false`)

### 3. Aurora DSQL Cluster

**Purpose**: Serverless PostgreSQL-compatible database for load testing.

**Configuration**:

- **Type**: Aurora DSQL (serverless)
- **Scaling**: Auto-scales based on demand (min/max capacity configurable)
- **Network**: Private subnets within VPC
- **Access**: IAM database authentication
- **Cost**: Pay-per-use (ACU - Aurora Capacity Units)
  - Scales to 0 ACU when paused (storage costs only)
  - Typical cost: $0.12-0.15 per ACU-hour

**Terraform Variable**: `enable_aurora_dsql_cluster` (default: `false`)

### 4. S3 Bucket

**Purpose**: Stores deployment packages and test results.

**Configuration**:

- **Name**: `producer-api-lambda-deployments-{account-id}` (auto-generated)
- **Usage**:
  - Deployment package uploads (`dsql-load-test-java.tar.gz`)
  - Test result storage (`test-results/*.json`)
- **Cost**:
  - Storage: $0.023/GB/month (Standard storage)
  - PUT requests: $0.005 per 1,000 requests
  - GET requests: $0.0004 per 1,000 requests
  - Data transfer out: $0.09/GB (first 10TB/month)

**Terraform Variable**: Created automatically when Lambda functions are enabled

### 5. VPC and Networking

**Purpose**: Isolated network environment for secure database access.

**Components**:

- **VPC**: Custom VPC with public and private subnets
- **Security Groups**: Restrictive egress rules (DSQL port 5432, HTTPS, HTTP)
- **VPC Endpoints**: S3 Gateway endpoint (free, no data transfer charges)
- **Internet Gateway**: For public subnet access (bastion host)

**Cost**:

- VPC: Free
- VPC Endpoints: S3 Gateway endpoint is free
- Data Transfer: $0.01/GB for inter-AZ transfer (if applicable)

### 6. AWS Systems Manager (SSM)

**Purpose**: Secure access to EC2 instances without SSH.

**Components**:

- **SSM Session Manager**: For EC2 instance access
- **SSM Parameter Store**: For configuration (optional)

**Cost**:

- Session Manager: Free
- Parameter Store: Free for standard parameters (up to 10,000)

## Cost Breakdown

### EC2 Test Runner Costs

**Per Test Run** (typical 2-4 hour test suite):

- **Instance Cost**: $0.344/hour × 3 hours = **$1.03 per test run**
- **Storage**: EBS gp3 volume (~20GB) = $0.08/GB/month × 20GB × (3 hours / 720 hours) = **~$0.007**
- **Total per test run**: **~$1.04**

**Monthly Cost** (if running 24/7):

- **Instance**: $0.344/hour × 730 hours = **$251.12/month**
- **Storage**: $0.08/GB/month × 20GB = **$1.60/month**
- **Total**: **~$252.72/month**

### Aurora DSQL Costs

**Pricing**:

- **Compute**: $0.12 per ACU-hour (Aurora Capacity Unit)
- **Storage**: $0.10 per GB per month
- **I/O Requests**: $0.20 per million requests (typically minimal)

**ACU Scaling Estimates** (based on load - see also [ACU Estimation Guidelines](#acu-estimation-guidelines) below):

- **Light load** (< 50 connections): 1 ACU
- **Medium load** (50-200 connections): 1-2 ACU (typical: 1.5 ACU)
- **Heavy load** (200-500 connections): 2-4 ACU (typical: 2.5 ACU)
- **Extreme load** (500-2000+ connections): 4-8 ACU (typical: 5 ACU)

**Per Test Run** (typical 2-4 hour test suite):

- **Compute**: Varies based on load (typically 2-4 ACU during tests)
  - Light/Medium (100 threads): 1.5 ACU × 3 hours × $0.12 = **$0.54**
  - Heavy (500 threads): 2.5 ACU × 3 hours × $0.12 = **$0.90**
  - Extreme (1000+ threads): 5 ACU × 3 hours × $0.12 = **$1.80**
- **Storage**: ~$0.10/GB/month (minimal for test data, ~0.01 GB)
- **Total per test run**: **~$0.55-$1.85** (varies by load)

**Monthly Cost** (if running 24/7 with auto-pause):

- **Compute**: Depends on usage patterns
  - Typical active usage: $0.12/ACU-hour × 2 ACU × 12 hours/day × 30 days = **$86.40/month**
  - With auto-pause: Typically paused 12+ hours/day, reducing costs significantly
- **Storage**: **~$1-5/month** (depends on data volume)

**Better Cost Estimation**:
Use the `estimate-dsql-costs.py` tool for more accurate estimates based on:

- Test configuration (threads, duration, batch size)
- CloudWatch metrics (actual ACU usage)
- Load patterns (light/medium/heavy/extreme)

See [DSQL Cost Estimation](#dsql-cost-estimation) section below for details.

### S3 Costs

**Per Test Run**:

- **Storage**: Minimal (~10MB deployment package + ~1-10MB test results) = **~$0.0002**
- **PUT requests**: ~2 requests × $0.005/1000 = **~$0.00001**
- **GET requests**: ~10 requests × $0.0004/1000 = **~$0.000004**
- **Total per test run**: **~$0.0002**

**Monthly Cost**:

- **Storage**: ~100MB × $0.023/GB = **~$0.002/month**
- **Requests**: Negligible

### Total Cost Summary

**Per Test Run** (2-4 hour comprehensive test suite):

- **EC2 Test Runner**: $1.03
- **Aurora DSQL**: $0.72-$1.44
- **S3**: $0.0002
- **Total**: **~$1.75-$2.47 per test run**

**Monthly Cost** (with auto-stop/pause optimizations enabled):

- **EC2 Test Runner**: ~$1-5 (only during test runs)
- **Aurora DSQL**: ~$1-5 (paused most of the time)
- **S3**: $0.002
- **CloudWatch Logs**: $0.10-0.50
- **Total**: **~$2-10/month**

## Cost Optimization Features

### 1. EC2 Auto-Stop Lambda

**Purpose**: Automatically stops EC2 instances (test runner, bastion) when inactive.

**How It Works**:

- **Monitoring**: Checks for activity every 15 minutes
- **Activity Detection**:
  - Active SSM sessions
  - SSM session logs (historical)
  - DSQL API calls from instance role (via CloudTrail)
  - CloudWatch metrics (CPU > 5%, Network > 20MB over 3 hours)
- **Inactivity Threshold**: 30 minutes (0.5 hours) for bastion host
- **Action**: Stops instance if no activity detected
- **Notifications**: Optional email notifications via SNS

**Current Cost Impact**:

- **EC2 running only during test runs**: ~$1-5/month (typically 2-4 hours per test run)
- **Instance cost per test run**: $0.344/hour × 3 hours = ~$1.03

**Configuration**:

- **Terraform Module**: `terraform/modules/ec2-auto-stop/`
- **Schedule**: EventBridge rule runs every 15 minutes
- **Lambda**: Python 3.11, 128 MB memory, 60 second timeout
- **Enabled**: Automatically for bastion host when `enable_bastion_host = true`

### 2. DSQL Auto-Pause Lambda

**Purpose**: Automatically scales down DSQL cluster to minimum capacity (0 ACU) when inactive.

**How It Works**:

- **Monitoring**: Checks API Gateway invocations every hour
- **Activity Detection**: CloudWatch metrics for API Gateway `Count` metric
- **Inactivity Threshold**: 3 hours (configurable)
- **Action**: Scales down to minimum capacity (0 ACU) if no activity
- **Notifications**: Optional email notifications via SNS

**Current Cost Impact**:

- **DSQL paused most of the time**: ~$1-5/month (storage only when paused)
- **DSQL cost per test run**: 2-4 ACU × 3 hours × $0.12/ACU-hour = ~$0.72-$1.44

**Configuration**:

- **Terraform Module**: `terraform/modules/dsql-auto-pause/`
- **Schedule**: EventBridge rule runs every hour
- **Lambda**: Python 3.11, 128 MB memory, 60 second timeout
- **Enabled**: Only for test/dev environments (`environment = "test"` or `"dev"`)

### 3. DSQL Auto-Resume Lambda

**Purpose**: Automatically resumes DSQL cluster when API requests arrive.

**How It Works**:

- **Trigger**: Invoked by API Lambda when database connection fails (cluster is paused)
- **Action**: Checks cluster status and starts it if stopped
- **Response**: API returns 503 with retry instruction

**Cost Impact**:

- **No additional cost**: Only runs when needed (on-demand)
- **User Experience**: Seamless automatic startup (1-2 minute delay on first request)

**Configuration**:

- **Terraform Module**: `terraform/modules/dsql-auto-resume/`
- **Trigger**: Invoked by API Lambda functions
- **Lambda**: Python 3.11, 128 MB memory, 60 second timeout
- **Enabled**: Only for test/dev environments

### 4. EC2 Instance Lifecycle Management

**Purpose**: Test scripts automatically start/stop EC2 instances for test runs.

**How It Works**:

- **Before Tests**: Script checks instance status and starts if stopped
- **After Tests**: Script stops instance immediately (via EXIT trap)
- **Manual Control**: Can be started/stopped manually via AWS CLI

**Current Cost Impact**:

- **Automatic start/stop**: Instances only run during test execution
- **Typical usage**: ~$1-5/month (2-4 test runs per month)

**Implementation**:

- **Script**: Test scripts in `load-test/dsql-load-test-java/scripts/` (e.g., `run_test_suite.py`)
- **Logic**: Checks instance state, starts if stopped, stops after completion

### 5. ARM/Graviton Instance Types

**Purpose**: Use ARM-based instances for 20% cost savings and better performance.

**Configuration**:

- **Test Runner**: Can use `t4g` or `m6g` instances (ARM/Graviton2)
- **Bastion**: Default `t4g.nano` (ARM-based)
- **Cost Savings**: ~20% compared to x86 instances

**Example**:

- `m5a.2xlarge` (x86): $0.344/hour
- `m6g.2xlarge` (ARM): ~$0.275/hour (20% savings)

**Terraform Variable**: `dsql_test_runner_instance_type` (default: `t4g.small`)

### 6. S3 Lifecycle Policies

**Purpose**: Automatically transition old test results to cheaper storage tiers.

**Configuration**:

- **Standard Storage**: First 14-30 days
- **Intelligent-Tiering**: Automatic transition to cheaper tiers
- **Retention**: 14 days for non-production, 30 days for production

**Cost Savings**: Minimal but reduces long-term storage costs

### 7. CloudWatch Logs Retention

**Purpose**: Reduce log storage costs by limiting retention periods.

**Configuration**:

- **Default**: 2 days retention (dev/test)
- **Production**: 7-30 days retention
- **Cost**: $0.50/GB/month

**Current Cost Impact**:

- **2-day retention (dev/test)**: ~$0.10-0.50/month
- **7-30 day retention (production)**: ~$1-5/month

## Current Infrastructure Costs

### Monthly Costs (With Auto-Stop/Pause Enabled)

| Component | Monthly Cost | Notes |
|-----------|--------------|-------|
| EC2 Test Runner | $1-5 | Only running during test runs (2-4 hours each) |
| Aurora DSQL | $1-5 | Paused most of the time, only active during tests |
| S3 | $0.002 | Minimal storage for deployment packages and results |
| CloudWatch Logs | $0.10-0.50 | 2-day retention for dev/test environments |
| **Total** | **~$2-10/month** | Typical monthly cost with optimizations enabled |

### Per Test Run Costs

| Component | Cost per Test Run | Notes |
|-----------|-------------------|-------|
| EC2 Test Runner | $1.03 | $0.344/hour × 3 hours (typical test duration) |
| Aurora DSQL | $0.55-$1.85 | Varies by load: Light (1 ACU) to Extreme (5 ACU) × 3 hours × $0.12/ACU-hour |
| S3 | $0.0002 | Minimal storage and request costs |
| **Total** | **~$1.58-$2.88** | Cost for a typical 2-4 hour test suite (varies by load) |

**DSQL Cost Breakdown by Load**:

- **Light/Medium** (50-200 threads): ~$0.55 per test run
- **Heavy** (200-500 threads): ~$0.90 per test run
- **Extreme** (500-2000+ threads): ~$1.80 per test run

## DSQL Cost Estimation

### Using the Cost Estimation Tool

A Python tool is available to estimate DSQL costs more accurately: `load-test/shared/estimate-dsql-costs.py`

#### Estimate from Test Parameters

```bash
# Estimate cost for a specific test run
python3 load-test/shared/estimate-dsql-costs.py \
  --threads 500 \
  --duration-hours 3 \
  --batch-size 100

# Output:
# DSQL Cost Estimate
# Threads: 500
# Duration: 3.00 hours
# Estimated ACU: 2.50
# ACU-hours: 7.50
# Total Cost: $0.9000
```

#### Estimate from Test Configuration

```bash
# Estimate costs for all tests in test-config.json
python3 load-test/shared/estimate-dsql-costs.py \
  --test-config load-test/dsql-load-test-java/test-config.json \
  --format table
```

#### Estimate from CloudWatch Metrics (Most Accurate)

```bash
# Get actual costs from CloudWatch metrics
python3 load-test/shared/estimate-dsql-costs.py \
  --cloudwatch \
  --cluster-id <cluster-resource-id> \
  --start-time "2024-01-01T00:00:00Z" \
  --end-time "2024-01-01T03:00:00Z" \
  --region us-east-1
```

**Prerequisites for CloudWatch**:

- `boto3` installed: `pip install boto3`
- AWS credentials configured
- CloudWatch metrics enabled for DSQL cluster

### ACU Estimation Guidelines

**Based on Concurrent Connections** (see also [ACU Scaling Estimates](#aurora-dsql-costs) above):

- **< 50 connections**: 1 ACU (light load)
- **50-200 connections**: 1-2 ACU (medium load, typical: 1.5 ACU)
- **200-500 connections**: 2-4 ACU (heavy load, typical: 2.5 ACU)
- **500-2000+ connections**: 4-8 ACU (extreme load, typical: 5 ACU)

**Adjustments**:

- **Batch operations**: Large batch sizes (>100 rows) may increase ACU by 20-50%
- **Complex queries**: JOINs, aggregations, and complex queries may require more ACU
- **Data volume**: Larger datasets may require more ACU for the same query patterns

### CloudWatch Metrics for Cost Tracking

Monitor these CloudWatch metrics to track actual costs:

**Key Metrics** (Namespace: `AWS/RDS`):

- **`ServerlessDatabaseCapacity`**: Current ACU capacity (average over time period)
- **`VolumeBytesUsed`**: Storage usage in bytes
- **`DatabaseConnections`**: Number of active connections
- **`CPUUtilization`**: CPU usage percentage

**Calculating Costs from Metrics**:

1. Query `ServerlessDatabaseCapacity` for your time period
2. Calculate ACU-hours: `sum(average_acu × period_hours)` for each datapoint
3. Multiply by $0.12/ACU-hour for compute cost
4. Query `VolumeBytesUsed` for storage cost

**Example AWS CLI Command**:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=<cluster-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T03:00:00Z \
  --period 300 \
  --statistics Average
```

### Query-Level Cost Estimation

For detailed query-level cost analysis, use `EXPLAIN ANALYZE VERBOSE`:

```sql
EXPLAIN ANALYZE VERBOSE SELECT * FROM events WHERE id = 1;
```

The output includes:

- **DPU (Distributed Processing Unit) usage**: Breakdown by compute, read, write
- **Resource consumption**: Helps identify expensive queries
- **Optimization opportunities**: Focus optimization on high-cost queries

### Cost Estimation Examples

**Example 1: Light Load Test**

- Threads: 50
- Duration: 1 hour
- Estimated ACU: 1 ACU
- Cost: 1 ACU × 1 hour × $0.12 = **$0.12**

**Example 2: Heavy Load Test**

- Threads: 500
- Duration: 3 hours
- Estimated ACU: 2.5 ACU
- Cost: 2.5 ACU × 3 hours × $0.12 = **$0.90**

**Example 3: Extreme Load Test**

- Threads: 2000
- Duration: 2 hours
- Batch size: 1000
- Estimated ACU: 5 ACU (adjusted for batch operations)
- Cost: 5 ACU × 2 hours × $0.12 = **$1.20**

### Tips for Accurate Estimation

1. **Use CloudWatch metrics** for actual costs (most accurate)
2. **Monitor during test runs** to understand actual ACU scaling
3. **Consider query complexity** - complex queries may require more ACU
4. **Account for warm-up time** - DSQL may scale up gradually
5. **Factor in auto-pause** - Costs are zero when paused (storage only)

## Best Practices

### 1. Enable Auto-Stop/Pause for Non-Production

Always enable auto-stop/pause features for dev and test environments:

- Set `environment = "test"` or `"dev"` in Terraform
- Auto-stop/pause is automatically enabled

### 2. Use Appropriate Instance Types

- **Test Runner**: Use `m5a.2xlarge` or `m6g.2xlarge` for load tests
- **Bastion**: Use `t4g.nano` or `t4g.small` (small, ARM-based)
- **Avoid**: Over-provisioning with larger instances than needed

### 3. Monitor Costs

- **AWS Cost Explorer**: Monitor monthly costs
- **CloudWatch Billing Alarms**: Set up alerts for unexpected costs
- **Tag Resources**: Use tags to track costs by environment/project

### 4. Clean Up Test Data

- **S3 Lifecycle**: Automatically clean up old test results
- **Database**: Clear test data after test runs
- **CloudWatch Logs**: Use retention policies

### 5. Schedule Test Runs

- **Off-Peak Hours**: Run tests during off-peak hours to reduce impact
- **Batch Tests**: Run multiple tests in sequence to maximize instance utilization
- **Stop After Tests**: Always stop instances after test completion

## Configuration Examples

### Terraform Configuration

```hcl
# Enable test runner with auto-stop
enable_dsql_test_runner_ec2 = true
dsql_test_runner_instance_type = "m5a.2xlarge"  # or "m6g.2xlarge" for ARM

# Enable DSQL with auto-pause
enable_aurora_dsql_cluster = true
aurora_dsql_auto_pause = true
environment = "test"  # Auto-pause only enabled for test/dev

# Enable bastion with auto-stop
enable_bastion_host = true
bastion_instance_type = "t4g.nano"  # ARM-based, small instance
```

### Manual Instance Management

```bash
# Start test runner
aws ec2 start-instances --instance-ids i-xxxxx

# Stop test runner (after tests)
aws ec2 stop-instances --instance-ids i-xxxxx

# Check instance status
aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[0].Instances[0].State.Name'
```

## Monitoring and Alerts

### CloudWatch Metrics

Monitor the following metrics:

- **EC2 Instance State**: `State` (running/stopped)
- **DSQL Capacity**: `MinCapacity`, `MaxCapacity`
- **Lambda Invocations**: Auto-stop/pause Lambda invocation counts
- **Cost**: AWS Cost Explorer

### SNS Notifications

Configure email notifications for:

- **EC2 Auto-Stop**: When bastion/test runner is stopped
- **DSQL Auto-Pause**: When DSQL cluster is scaled down

Set `aurora_auto_stop_admin_email` in Terraform variables.

## Troubleshooting

### EC2 Instance Not Starting

1. Check instance state: `aws ec2 describe-instances --instance-ids i-xxxxx`
2. Check IAM permissions for SSM access
3. Verify security group allows outbound HTTPS (for SSM)

### DSQL Cluster Not Pausing

1. Check CloudWatch metrics for API Gateway invocations
2. Verify auto-pause Lambda is running (check EventBridge schedule)
3. Check Lambda logs for errors

### High Costs Unexpectedly

1. Check AWS Cost Explorer for cost breakdown
2. Verify auto-stop/pause Lambdas are running
3. Check instance states (should be stopped when not in use)
4. Review CloudWatch Logs retention settings

## References

- [Terraform README](../terraform/README.md) - Infrastructure setup and configuration
- [DSQL Performance Test Suite README](dsql-load-test-java/PERFORMANCE_TEST_SUITE_README.md) - Test execution details
- [AWS Pricing Calculator](https://calculator.aws/) - Current AWS pricing
- [Aurora DSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html) - DSQL features and pricing
