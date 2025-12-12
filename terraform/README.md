# Terraform Setup for Serverless APIs

This directory contains Terraform configuration to deploy the Python REST Lambda function with API Gateway HTTP API, using S3 for Lambda code deployment.

## Overview

The Terraform setup includes:
- **Lambda Functions**: Python REST Lambda function
- **API Gateway**: HTTP API with CORS configuration
- **S3 Bucket**: Versioned S3 bucket for Lambda deployment packages
- **VPC Support**: Optional VPC configuration with security groups
- **Database Support**: Optional RDS PostgreSQL database

This setup works alongside the existing SAM templates, providing an alternative deployment method.

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
# Interactive deployment (recommended for first time)
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
| `lambda_memory_size` | Lambda memory size in MB | `512` |
| `lambda_timeout` | Lambda timeout in seconds | `30` |
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

### Option 2: Aurora PostgreSQL (Recommended)

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

- Lambda functions use provisioned concurrency only if needed
- S3 lifecycle policies clean up old versions after 30 days
- Database can be stopped when not in use (manual process)
- Consider using Aurora Serverless for variable workloads
