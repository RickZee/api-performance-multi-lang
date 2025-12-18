# Terraform Setup for Serverless APIs

This directory contains Terraform configuration to deploy the Python REST Lambda function with API Gateway HTTP API, using S3 for Lambda code deployment.

## Overview

The Terraform setup includes:
- **Lambda Functions**: Python REST Lambda function
- **API Gateway**: HTTP API with CORS configuration
- **S3 Bucket**: Versioned S3 bucket for Lambda deployment packages
- **VPC Support**: Optional VPC configuration with security groups
- **Aurora PostgreSQL**: Aurora cluster with logical replication enabled
- **Aurora DSQL**: Optional Aurora DSQL cluster with IAM authentication (see [Debezium DSQL Connector README](./debezium-connector-dsql/README.md))
- **EC2 Test Runner**: Optional EC2 instance for testing DSQL connector from within VPC (see [Debezium DSQL Connector README](./debezium-connector-dsql/README.md) and [README_EC2.md](./debezium-connector-dsql/README_EC2.md))
- **Schema Initialization**: Automatic database schema initialization from `data/schema.sql`

This setup works alongside the existing SAM templates, providing an alternative deployment method.

### Database Schema Management

The database schema is automatically initialized by Terraform when the Aurora cluster is created. The schema is defined in `data/schema.sql` and includes:
- `business_events` table - Primary table for event storage
- Entity tables (`car_entities`, `loan_entities`, etc.)
- All required indexes

**Important**: Schema initialization happens automatically during Terraform deployment. No manual schema setup is required. The schema is managed as Infrastructure as Code, ensuring consistency across deployments.

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- Python 3.11+ (for building Lambda functions)
- AWS account with appropriate permissions

## Terraform State Backend (S3)

This configuration supports storing Terraform state in S3 with DynamoDB locking for team collaboration and state safety.

### Initial Setup (First Time)

1. **Deploy with local state first** to create the S3 bucket and DynamoDB table:
   ```bash
   # Ensure enable_terraform_state_backend = true in terraform.tfvars (default)
   terraform init -backend=false
   terraform apply
   ```

2. **Migrate to S3 backend** after the first apply:
   ```bash
   ./scripts/setup-backend.sh
   ```
   
   This script will:
   - Get the S3 bucket and DynamoDB table names from Terraform outputs
   - Create `terraform.tfbackend` configuration file
   - Migrate your local state to S3

3. **Future operations** will automatically use the S3 backend.

### Using Existing Backend

If you're working with an existing Terraform setup that already has a backend configured:

```bash
# Copy the example backend config
cp terraform.tfbackend.example terraform.tfbackend

# Edit terraform.tfbackend with your bucket and table names
# Then initialize
terraform init -backend-config=terraform.tfbackend
```

### Backend Configuration

The backend uses:
- **S3 Bucket**: Stores Terraform state files (versioned and encrypted)
- **DynamoDB Table**: Provides state locking to prevent concurrent modifications
- **Auto-created**: Both resources are created automatically when `enable_terraform_state_backend = true` (default)

To disable backend creation:
```hcl
enable_terraform_state_backend = false
```

### Backend Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_terraform_state_backend` | Create S3 bucket and DynamoDB table for state | `true` |
| `terraform_state_bucket_name` | Custom S3 bucket name (auto-generated if empty) | `""` |
| `terraform_state_dynamodb_table_name` | Custom DynamoDB table name (auto-generated if empty) | `""` |

## Quick Start

### 1. Configure Variables

Create a `terraform.tfvars` file (optional, you can also use environment variables or command-line flags):

```hcl
project_name = "producer-api"
aws_region   = "us-east-1"
log_level    = "info"

# Database configuration (optional)
# Option 1: Full connection string
database_url = "postgresql://user:password@host:5432/dbname"

# Option 2: Aurora endpoint with separate credentials
aurora_endpoint = "your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com"
database_name   = "car_entities"
database_user   = "postgres"
database_password = "your-password"

# VPC configuration (optional)
enable_vpc = true
vpc_id     = "vpc-xxxxx"
subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

# Database creation (optional)
enable_database = false
```

### 2. Build and Upload Lambda Functions

Build the Lambda functions and upload them to S3:

```bash
cd terraform
./scripts/build-and-upload.sh
```

Or use the deploy script with the build flag:

```bash
./scripts/deploy.sh --build-upload
```

### 3. Deploy Infrastructure

Deploy the Terraform configuration:

```bash
# Interactive deployment (for first time)
./scripts/deploy.sh

# Auto-approve deployment
./scripts/deploy.sh --auto-approve

# Build, upload, and deploy in one command
./scripts/deploy.sh --build-upload --auto-approve
```

### 4. View Outputs

After deployment, view the outputs:

```bash
terraform output
```

The outputs include:
- **API URLs**: HTTP API Gateway endpoints for Lambda functions
- **Aurora Endpoints**: Database connection endpoints
- **Aurora DSQL Endpoints**: DSQL cluster connection information (if enabled)
  - `aurora_dsql_endpoint`: VPC endpoint DNS (for connections from within VPC)
  - `aurora_dsql_host`: DSQL host format (alternative hostname)
  - `aurora_dsql_cluster_resource_id`: Cluster resource ID for IAM permissions
- **Test Runner**: EC2 instance information for DSQL testing (if enabled)
- `python_rest_api_url`: API Gateway endpoint for Python REST Lambda
- `s3_bucket_name`: S3 bucket name for Lambda deployments
- Other resource identifiers

## Manual Deployment Steps

If you prefer to run Terraform commands manually:

```bash
# Initialize Terraform
terraform init

# Format and validate
terraform fmt -recursive
terraform validate

# Plan changes
terraform plan

# Apply changes
terraform apply

# View outputs
terraform output
```

## Variables Reference

### Required Variables

None - all variables have defaults, but you should customize them for your environment.

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Project name prefix for resources | `producer-api` |
| `aws_region` | AWS region for deployment | `us-east-1` |
| `database_url` | Full database connection string | `""` |
| `aurora_endpoint` | Aurora Serverless endpoint | `""` |
| `database_name` | Database name | `car_entities` |
| `database_user` | Database user | `postgres` |
| `database_password` | Database password | `""` |
| `log_level` | Logging level (debug/info/warn/error) | `info` |
| `vpc_id` | VPC ID for Aurora access | `""` |
| `subnet_ids` | Subnet IDs for Aurora access | `[]` |
| `enable_database` | Create database infrastructure | `false` |
| `enable_vpc` | Enable VPC configuration | `false` |
| `aurora_instance_class` | Aurora instance class | `db.t3.small` (cost-optimized) |
| `backup_retention_period` | Aurora backup retention in days | `3` (dev/staging), `7` (prod) |
| `lambda_memory_size` | Lambda memory size in MB | `256` (cost-optimized) |
| `lambda_timeout` | Lambda timeout in seconds | `15` (cost-optimized) |
| `cloudwatch_logs_retention_days` | CloudWatch Logs retention | `7` (cost-optimized) |
| `environment` | Environment name (dev/staging/prod) | `dev` |
| `s3_bucket_name` | S3 bucket name (auto-generated if empty) | `""` |
| `tags` | Tags to apply to all resources | `{}` |

## Database Configuration

The setup supports two database configuration methods:

### Option 1: Full Connection String

Provide a complete PostgreSQL connection string:

```hcl
database_url = "postgresql://user:password@host:5432/dbname"
```

### Option 2: Aurora Endpoint with Separate Credentials

Provide Aurora endpoint and credentials separately:

```hcl
aurora_endpoint   = "your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com"
database_name     = "car_entities"
database_user     = "postgres"
database_password = "your-password"
```

If both are provided, `database_url` takes precedence.

## VPC Configuration

To enable VPC configuration for Lambda functions:

```hcl
enable_vpc = true
vpc_id     = "vpc-xxxxx"
subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
```

This creates a security group for Lambda functions with egress rules for PostgreSQL (port 5432).

## Database Creation

### Option 1: RDS PostgreSQL (Legacy)

To create an RDS PostgreSQL database:

```hcl
enable_database = true
vpc_id          = "vpc-xxxxx"
subnet_ids      = ["subnet-xxxxx", "subnet-yyyyy"]
database_name   = "car_entities"
database_user   = "postgres"
database_password = "your-secure-password"
```

**Note**: Database creation requires VPC configuration.

### Option 2: Aurora PostgreSQL (for Confluent Cloud)

To create Aurora PostgreSQL cluster with new VPC:

```hcl
enable_aurora = true
database_name = "car_entities"
database_user = "postgres"
database_password = "your-secure-password"

# Aurora configuration
aurora_instance_class = "db.t3.medium"  # Minimal provisioned instance
aurora_publicly_accessible = true        # Required for Confluent Cloud
```

This will automatically:
- Create a new VPC with public/private subnets
- Deploy Aurora PostgreSQL cluster with logical replication enabled
- Configure security groups for API and Confluent Cloud access

**Quick Deploy:**
```bash
cd terraform
./scripts/deploy-aurora.sh
```

For additional Aurora setup details, see [cdc-streaming/CONFLUENT_CLOUD_SETUP_GUIDE.md](../cdc-streaming/CONFLUENT_CLOUD_SETUP_GUIDE.md).

## Updating Lambda Functions

To update Lambda function code:

1. Build and upload new code:
   ```bash
   ./scripts/build-and-upload.sh
   ```

2. Update Lambda function code in Terraform:
   ```bash
   terraform apply -target=module.python_rest_lambda.aws_lambda_function.this
   ```

Or simply run:
```bash
./scripts/deploy.sh --build-upload
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including the S3 bucket and its contents.

## Module Structure

```
terraform/
├── main.tf                 # Main configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── versions.tf             # Provider versions
├── modules/
│   ├── lambda/             # Lambda function module (includes API Gateway)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── database/           # Optional RDS database module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    ├── build-and-upload.sh # Build and upload Lambda functions
    └── deploy.sh           # Deployment script
```

## Differences from SAM Templates

This Terraform setup provides:
- **S3-based deployments**: Lambda code is stored in S3 with versioning
- **Modular structure**: Reusable modules for Lambda and database
- **Infrastructure as Code**: Full Terraform configuration
- **Flexible configuration**: More granular control over resources

The SAM templates remain available as an alternative deployment method.

## Troubleshooting

### Lambda Function Not Updating

If Lambda function code doesn't update after uploading to S3:
1. Ensure the S3 key matches the configuration
2. Use `terraform apply -replace` to force recreation
3. Check S3 bucket versioning is enabled

### VPC Configuration Issues

If Lambda functions can't connect to the database:
1. Verify security group rules allow outbound traffic on port 5432
2. Check subnet IDs are in the same VPC
3. Ensure database security group allows inbound from Lambda security group

### Database Connection Issues

If Lambda functions can't connect to the database:
1. Verify database endpoint is correct
2. Check database credentials
3. Ensure VPC configuration is correct if database is in VPC
4. Verify security group rules

## Security Considerations

- Database passwords are marked as sensitive in Terraform
- S3 bucket has encryption enabled
- Security groups follow least-privilege principles
- Consider using AWS Secrets Manager for database credentials in production

## Cost Optimization

This Terraform configuration includes several cost optimization features:

### Phase 1: Quick Wins (Implemented)
- **Aurora Instance**: Default `db.t3.small` instead of `db.t3.medium` (~50% cost reduction)
- **Backup Retention**: 3 days for dev/staging, 7 days for production (reduces backup storage costs)
- **Lambda Memory**: Default 256 MB instead of 512 MB (reduces compute costs)
- **Lambda Timeout**: Default 15 seconds instead of 30 seconds (reduces risk of long-running functions)
- **CloudWatch Logs**: 2-day retention (reduces log storage costs)
- **S3 Lifecycle**: 14-day retention for non-production, 30 days for production

### Phase 2: Medium-Term Optimizations (Implemented)
- **Environment-Based Defaults**: Automatic cost optimization based on `environment` variable (default: `dev`)
- **Aurora Start/Stop Script**: Use `scripts/aurora-start-stop.sh` to stop Aurora during off-hours for dev/staging
- **Aurora Auto-Stop Lambda**: Automatically stops Aurora if no API calls for 3 hours (dev/staging only)
- **S3 Intelligent-Tiering**: Lifecycle policies automatically transition old versions

### Cost Savings Summary
- **Estimated Monthly Savings**: ~$30-40/month (30-50% reduction)
- **Annual Savings**: ~$360-480/year

### Usage Examples

**Stop Aurora for dev environment during off-hours:**
```bash
cd terraform
./scripts/aurora-start-stop.sh stop
```

**Start Aurora when needed:**
```bash
./scripts/aurora-start-stop.sh start
```

**Check Aurora status:**
```bash
./scripts/aurora-start-stop.sh status
```

**Aurora Auto-Stop (Automatic):**
The Aurora auto-stop Lambda function automatically monitors API Gateway invocations and stops Aurora if there are no API calls for 3 hours. This feature:
- Runs every hour via EventBridge schedule
- Only enabled for dev/staging environments (not production)
- Only works when Python Lambda is enabled
- Checks CloudWatch metrics for API Gateway invocations
- Fails safely (won't stop if metrics can't be checked)
- **Email Notifications**: Optionally sends email notifications when the cluster is stopped (configure via `aurora_auto_stop_admin_email`)

**Email Notifications for Auto-Stop:**
To receive email notifications when Aurora is automatically stopped, set the `aurora_auto_stop_admin_email` variable in `terraform.tfvars`:
```hcl
aurora_auto_stop_admin_email = "admin@example.com"
```

**Important**: After setting the email address and running `terraform apply`, AWS SNS will send a confirmation email to the provided address. You must click the confirmation link in that email before notifications will be sent. This is a one-time setup step required by AWS SNS.

To disable email notifications, leave the variable empty (default) or remove it from your configuration.

**Production Configuration:**
For production, override defaults in `terraform.tfvars`:
```hcl
environment = "prod"
aurora_instance_class = "db.t3.medium"  # Larger instance for production
backup_retention_period = 7             # Longer retention for production
cloudwatch_logs_retention_days = 14      # Longer retention for production
```

### Additional Cost Optimization Tips
- Use Aurora Serverless v2 for variable workloads (requires manual configuration)
- Consider ARM-based instances (`db.t4g.medium`) for better price/performance
- Monitor actual usage and right-size resources accordingly
- Use AWS Cost Explorer to track spending and identify optimization opportunities
