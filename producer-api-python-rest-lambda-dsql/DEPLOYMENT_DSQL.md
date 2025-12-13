# Deployment Guide: DSQL API with Cheapest Configuration

This guide explains how to deploy the DSQL-enabled Lambda API to AWS with the most cost-effective configuration.

## Prerequisites

### 1. Aurora DSQL Cluster (Required)

**Important**: Aurora DSQL cluster must be created separately (not via Terraform). You need:

- **DSQL Cluster Endpoint**: e.g., `your-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com`
- **Cluster Resource ID**: e.g., `cluster-xxxxx` (found in AWS Console or via AWS CLI)
- **IAM Database User**: Created in the DSQL cluster with appropriate permissions
- **Database Name**: The database name in your DSQL cluster

### 2. AWS Account Setup

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0 installed
- Python 3.11+ (for building Lambda package)
- IAM permissions to create Lambda, API Gateway, S3, and IAM resources

## Cheapest Configuration

### Cost-Optimized Settings

The following configuration minimizes costs:

```hcl
# terraform.tfvars
project_name = "producer-api-dsql"
aws_region   = "us-east-1"  # Use cheapest region for your use case
environment  = "dev"         # Enables cost optimizations
log_level    = "info"

# Enable Python Lambda
enable_python_lambda = true

# Lambda cost optimization (defaults are already optimized)
lambda_memory_size = 256      # Minimum: 128MB, default: 256MB (cost-optimized)
lambda_timeout     = 15       # Default: 15s (cost-optimized)

# CloudWatch Logs retention (cost optimization)
cloudwatch_logs_retention_days = 1  # Minimum: 1 day (cheapest), default: 3

# DSQL Configuration (REQUIRED)
enable_aurora_dsql = true
aurora_dsql_endpoint = "your-dsql-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
aurora_dsql_port = 5432
iam_database_user = "your-iam-db-user"
aurora_dsql_cluster_resource_id = "cluster-xxxxx"
database_name = "car_entities"

# Disable unnecessary resources
enable_aurora = false          # Don't create Aurora (using existing DSQL)
enable_rds_proxy = false       # Not needed for DSQL
enable_database = false        # Don't create separate database
enable_vpc = false             # DSQL may support public access (verify with AWS)

# Terraform state (optional - can disable to save S3 costs)
enable_terraform_state_backend = true  # Keep enabled for state management
```

### Cost Breakdown (Estimated Monthly)

**Lambda (Free Tier + Pay-as-you-go)**:
- First 1M requests: FREE
- Next requests: $0.20 per 1M requests
- Compute: $0.0000166667 per GB-second
  - 256MB = $0.0000041667 per second
  - Example: 1M requests × 1s = ~$4.17/month (after free tier)

**API Gateway HTTP API**:
- First 1M requests: FREE
- Next requests: $1.00 per 1M requests
- Data transfer: $0.09 per GB (outbound)

**S3 (Lambda deployments)**:
- Storage: $0.023 per GB/month (minimal - just deployment packages)
- Requests: Negligible

**CloudWatch Logs**:
- First 5GB: FREE
- Next: $0.50 per GB/month
- With 1-day retention: Minimal cost

**Aurora DSQL**:
- **Separate cost** - depends on DSQL cluster configuration
- Check AWS pricing for DSQL (serverless pricing model)

**Total Estimated Cost (excluding DSQL cluster)**:
- **~$5-10/month** for light usage (after free tier)
- **~$0-5/month** if within free tier limits

## Deployment Steps

### Step 1: Build Lambda Package

```bash
cd producer-api-python-rest-lambda-dsql
./scripts/build-lambda.sh
```

This creates `lambda-deployment.zip` in the project root.

### Step 2: Upload to S3

```bash
# Get S3 bucket name from Terraform (or create manually)
aws s3 cp lambda-deployment.zip s3://YOUR-BUCKET-NAME/python-rest/lambda-deployment.zip
```

Or let Terraform create the bucket and upload automatically.

### Step 3: Configure Terraform

Create `terraform/terraform.tfvars`:

```hcl
project_name = "producer-api-dsql"
aws_region   = "us-east-1"
environment  = "dev"
log_level    = "info"

enable_python_lambda = true
lambda_memory_size = 256
lambda_timeout = 15
cloudwatch_logs_retention_days = 1

# DSQL Configuration
enable_aurora_dsql = true
aurora_dsql_endpoint = "your-dsql-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
aurora_dsql_port = 5432
iam_database_user = "your-iam-db-user"
aurora_dsql_cluster_resource_id = "cluster-xxxxx"
database_name = "car_entities"

# Disable unnecessary resources
enable_aurora = false
enable_rds_proxy = false
enable_database = false
enable_vpc = false
```

### Step 4: Initialize Terraform

```bash
cd terraform
terraform init
```

### Step 5: Plan Deployment

```bash
terraform plan
```

Review the plan to ensure:
- Only necessary resources are created
- DSQL configuration is correct
- No VPC resources (if DSQL supports public access)

### Step 6: Deploy

```bash
terraform apply
```

### Step 7: Get API Endpoint

```bash
terraform output python_rest_api_url
```

## Verification

### Test Health Endpoint

```bash
API_URL=$(terraform output -raw python_rest_api_url)
curl $API_URL/api/v1/events/health
```

Expected response:
```json
{
  "status": "healthy",
  "message": "Producer API is healthy"
}
```

### Test Event Processing

```bash
curl -X POST $API_URL/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventHeader": {
      "uuid": "test-123",
      "eventName": "Test Event",
      "eventType": "Test",
      "createdDate": "2024-01-15T10:30:00Z"
    },
    "entities": [{
      "entityHeader": {
        "entityId": "TEST-001",
        "entityType": "Car",
        "createdAt": "2024-01-15T10:30:00Z",
        "updatedAt": "2024-01-15T10:30:00Z"
      },
      "id": "TEST-001",
      "make": "Test",
      "model": "Test Model"
    }]
  }'
```

## Important Notes

### DSQL Cluster Requirements

1. **Cluster must exist**: Terraform does NOT create the DSQL cluster
2. **IAM Database User**: Must be created in the DSQL cluster before deployment
3. **Permissions**: IAM user needs appropriate database permissions
4. **Network Access**: Verify if DSQL supports public access or requires VPC

### VPC Configuration

**If DSQL requires VPC access**:
- Set `enable_vpc = true` and provide `vpc_id` and `subnet_ids`
- Lambda will be deployed in VPC (adds ~100ms cold start penalty)
- Additional cost: NAT Gateway if needed (~$32/month)

**If DSQL supports public access**:
- Set `enable_vpc = false` (cheapest option)
- Lambda runs without VPC (faster cold starts)
- No NAT Gateway needed

### Cost Optimization Tips

1. **Use Free Tier**: First 1M Lambda requests and 1M API Gateway requests are free
2. **Minimal Memory**: 256MB is usually sufficient (can go down to 128MB if needed)
3. **Short Timeout**: 15s is default (adjust based on your needs)
4. **Log Retention**: 1 day minimum (3 days default, 7+ for production)
5. **Environment**: Set `environment = "dev"` for cost optimizations
6. **Region**: Choose cheapest region (us-east-1 is typically cheapest)

### Troubleshooting

**IAM Authentication Errors**:
- Verify IAM database user exists in DSQL cluster
- Check IAM permissions: `rds-db:connect`
- Verify cluster resource ID is correct

**Connection Errors**:
- Check DSQL endpoint is correct
- Verify network access (VPC vs public)
- Check security groups if using VPC

**Lambda Timeout**:
- Increase `lambda_timeout` if needed
- Check CloudWatch logs for errors
- Verify DSQL cluster is running

## Cleanup

To remove all resources and stop incurring costs:

```bash
cd terraform
terraform destroy
```

**Note**: This does NOT delete the DSQL cluster (created separately).

## Next Steps

1. Monitor costs in AWS Cost Explorer
2. Set up CloudWatch alarms for errors
3. Configure API Gateway throttling if needed
4. Review and optimize based on actual usage

