# Aurora DSQL Setup Guide

This guide explains how to set up two separate databases:
1. **Regular Aurora PostgreSQL** - for the standard Python REST Lambda API
2. **Aurora DSQL** - for the Python REST Lambda DSQL API (using IAM authentication)

## Architecture Overview

- **Regular Aurora PostgreSQL**: Traditional Aurora cluster with username/password authentication
- **Aurora DSQL**: Separate Aurora cluster configured for IAM database authentication
- **Two Lambda Functions**: 
  - `producer-api-python-rest-lambda` → connects to regular Aurora PostgreSQL
  - `producer-api-python-rest-lambda-dsql` → connects to Aurora DSQL using IAM authentication

## Configuration

### 1. Enable Both Databases in `terraform.tfvars`

```hcl
# Regular Aurora PostgreSQL (already configured)
enable_aurora = true
database_name = "car_entities"
database_user = "postgres"
database_password = "YOUR_PASSWORD"

# Aurora DSQL Cluster (new)
enable_aurora_dsql_cluster = true
aurora_dsql_instance_class = "db.t3.small"  # Cost-optimized
aurora_dsql_publicly_accessible = true
aurora_dsql_database_name = "car_entities"
aurora_dsql_database_user = "postgres"
aurora_dsql_database_password = "YOUR_PASSWORD"  # Can be same or different
aurora_dsql_engine_version = "15.14"

# Enable DSQL Lambda
enable_python_lambda_dsql = true

# IAM Database User (created manually after cluster is deployed)
iam_database_user = "lambda_dsql_user"
```

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Create IAM Database User

After the DSQL cluster is created, you need to create an IAM database user:

```bash
# Connect to the DSQL cluster using the master user
psql -h <DSQL_CLUSTER_ENDPOINT> -U postgres -d car_entities

# Create IAM database user
CREATE USER lambda_dsql_user;

# Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE car_entities TO lambda_dsql_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_dsql_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lambda_dsql_user;
```

### 4. Update Terraform Variables with Cluster Resource ID

After deployment, get the cluster resource ID:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier producer-api-aurora-dsql-cluster \
  --query 'DBClusters[0].DbClusterResourceId' \
  --output text
```

Update `terraform.tfvars`:

```hcl
aurora_dsql_cluster_resource_id = "cluster-xxxxx"  # From AWS Console or CLI
```

Then run `terraform apply` again to update the Lambda IAM permissions.

## IAM Permissions

The DSQL Lambda function needs the following IAM permissions:

1. **rds-db:connect** - To connect to the DSQL cluster using IAM authentication
   - Resource: `arn:aws:rds-db:REGION:ACCOUNT_ID:dbuser:CLUSTER_RESOURCE_ID/IAM_USERNAME`

2. **rds:GenerateDBAuthToken** - To generate IAM authentication tokens
   - This is automatically granted via the Lambda execution role's default permissions

## Connection Flow

### Regular Aurora PostgreSQL Lambda
1. Lambda connects using username/password from environment variables
2. Connection string: `postgresql://user:password@endpoint:5432/database`

### Aurora DSQL Lambda
1. Lambda generates IAM authentication token using `boto3` RDS client
2. Token is cached for 14 minutes (tokens valid for 15 minutes)
3. Connection string: `postgresql://iam_user:token@endpoint:5432/database`
4. Token is automatically refreshed when expired

## Cost Optimization

Both clusters are configured with cost-optimized settings:

- **Instance Class**: `db.t3.small` (cheapest option)
- **Backup Retention**: 3 days (dev/staging) or 7 days (production)
- **CloudWatch Logs Retention**: 1 day
- **Lambda Memory**: 256 MB
- **Lambda Timeout**: 30 seconds

## Troubleshooting

### Lambda Cannot Connect to DSQL

1. **Check IAM Permissions**:
   ```bash
   aws iam get-role-policy \
     --role-name producer-api-python-rest-lambda-dsql-execution \
     --policy-name producer-api-python-rest-lambda-dsql-rds-connect-policy
   ```

2. **Verify IAM Database User Exists**:
   ```sql
   SELECT usename FROM pg_user WHERE usename = 'lambda_dsql_user';
   ```

3. **Check Security Group**:
   - Ensure Lambda security group can access DSQL security group (if using VPC)
   - Or ensure DSQL is publicly accessible and security group allows connections

4. **Check CloudWatch Logs**:
   ```bash
   aws logs tail /aws/lambda/producer-api-python-rest-lambda-dsql --follow
   ```

### Token Generation Errors

If you see errors about token generation:
- Verify the Lambda execution role has permissions to call `rds:GenerateDBAuthToken`
- Check that `AWS_REGION` environment variable is set correctly
- Ensure the DSQL cluster endpoint is correct

## Terraform Outputs

After deployment, you can retrieve DSQL connection information using Terraform outputs:

### Available Outputs

```bash
# VPC Endpoint DNS (for connections from within VPC)
terraform output -raw aurora_dsql_endpoint
# Example: vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com

# DSQL Host (alternative hostname format)
terraform output -raw aurora_dsql_host
# Example: vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws

# Cluster Resource ID (for IAM permissions)
terraform output -raw aurora_dsql_cluster_resource_id
# Example: vftmkydwxvxys6asbsc6ih2the

# Port
terraform output -raw aurora_dsql_port
# Example: 5432
```

### When to Use Each Endpoint

- **`aurora_dsql_endpoint` (VPC Endpoint DNS)**: 
  - Use when connecting **from within the VPC** (EC2, Lambda, ECS, etc.)
  - Format: `vpce-<id>-<suffix>.dsql-<service-id>.<region>.vpce.amazonaws.com`
  - This is the primary endpoint for VPC-based connections

- **`aurora_dsql_host` (DSQL Host)**:
  - Alternative hostname format provided by AWS
  - Format: `<cluster-id>.<service-suffix>.<region>.on.aws`
  - May be useful for certain connection scenarios or external tools
  - Note: Still requires VPC access to resolve and connect

Both endpoints resolve to the same DSQL cluster and can be used interchangeably from within the VPC.

## API Endpoints

After deployment, you'll have two separate API endpoints:

- **Regular Aurora API**: `https://<api-id>.execute-api.us-east-1.amazonaws.com/`
- **DSQL API**: `https://<dsql-api-id>.execute-api.us-east-1.amazonaws.com/`

Both APIs have the same endpoints:
- `GET /cars` - List all cars
- `POST /cars` - Create a new car
- `GET /cars/{id}` - Get a specific car

## Next Steps

1. Deploy the infrastructure: `terraform apply`
2. Create the IAM database user in the DSQL cluster
3. Update `terraform.tfvars` with the cluster resource ID
4. Run `terraform apply` again to update IAM permissions
5. Test both API endpoints to verify connectivity

