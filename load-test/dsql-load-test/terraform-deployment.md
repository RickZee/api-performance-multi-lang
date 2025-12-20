# Terraform Deployment for DSQL Load Test Lambda

The DSQL load test Lambda can be deployed as an optional module in the main Terraform configuration.

## Prerequisites

1. **Build and upload Lambda package to S3:**

The Lambda code must be packaged and uploaded to the S3 bucket used by Terraform:

```bash
cd load-test/dsql-load-test/lambda

# Install dependencies
pip install -r requirements.txt -t .

# Create deployment package (excluding unnecessary files)
zip -r lambda-deployment.zip . \
  -x "*.pyc" \
  -x "__pycache__/*" \
  -x "*.pyc" \
  -x ".pytest_cache/*" \
  -x "tests/*" \
  -x "*.md"

# Upload to S3 (replace with your bucket name from terraform output)
aws s3 cp lambda-deployment.zip s3://YOUR-BUCKET-NAME/dsql-load-test/lambda-deployment.zip
```

Get the bucket name:
```bash
cd ../../../../terraform
terraform output s3_bucket_name
```

## Enable in Terraform

1. **Add to `terraform.tfvars`:**

```hcl
# Enable DSQL load test Lambda
enable_dsql_load_test_lambda = true

# Optional: Configure Lambda settings
dsql_load_test_lambda_memory_size = 1024
dsql_load_test_lambda_timeout = 900  # 15 minutes
dsql_load_test_lambda_reserved_concurrency = null  # null = no limit
```

2. **Apply Terraform:**

```bash
cd terraform
terraform plan
terraform apply
```

3. **Get the function name:**

```bash
terraform output dsql_load_test_lambda_function_name
```

4. **Update config.json:**

Update `load-test/dsql-load-test/config.json` with the deployed function name:

```json
{
  "lambda_function_name": "producer-api-dsql-load-test-lambda",
  ...
}
```

## Module Configuration

The module automatically uses:
- **DSQL cluster**: If `enable_aurora_dsql_cluster = true`, uses the created cluster
- **Manual DSQL**: If cluster is not created via Terraform, uses `aurora_dsql_endpoint` and related variables
- **VPC**: Automatically configured if DSQL cluster is created via Terraform
- **IAM permissions**: Automatically granted for DSQL connection

## Important: IAM User Mapping

After deployment, map the Lambda's IAM role to a database user in DSQL:

```sql
-- Connect to DSQL as a user with GRANT privileges
-- Get the role ARN from Terraform output:
-- terraform output dsql_load_test_lambda_role_arn

AWS IAM GRANT your_iam_database_user TO 'arn:aws:iam::ACCOUNT_ID:role/producer-api-dsql-load-test-lambda-execution-role';
```

## Updating the Lambda

After making code changes:

1. **Rebuild and upload:**

```bash
cd load-test/dsql-load-test/lambda
# ... rebuild package ...
aws s3 cp lambda-deployment.zip s3://YOUR-BUCKET-NAME/dsql-load-test/lambda-deployment.zip
```

2. **Apply Terraform:**

```bash
cd ../../../../terraform
terraform apply
```

Terraform detects the S3 object change and updates the Lambda function.

## Disable Module

To disable the load test Lambda:

```hcl
enable_dsql_load_test_lambda = false
```

Then run `terraform apply`.
