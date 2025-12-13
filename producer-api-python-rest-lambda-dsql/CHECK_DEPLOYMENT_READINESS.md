# Deployment Readiness Checklist for DSQL API

Use this checklist to verify you can deploy the DSQL API to AWS.

## ✅ Prerequisites Checklist

### 1. AWS Account Setup
- [ ] AWS CLI installed and configured (`aws --version`)
- [ ] AWS credentials configured (`aws sts get-caller-identity`)
- [ ] Terraform >= 1.0 installed (`terraform version`)
- [ ] Python 3.11+ installed (`python3 --version`)
- [ ] IAM permissions for: Lambda, API Gateway, S3, IAM, CloudWatch

### 2. Aurora DSQL Cluster (REQUIRED)
- [ ] DSQL cluster exists in AWS
- [ ] Cluster endpoint known: `___________________________`
- [ ] Cluster resource ID known: `cluster-xxxxx` → `_________________`
- [ ] Database name: `_________________`
- [ ] IAM database user created in cluster: `_________________`
- [ ] IAM user has database permissions (SELECT, INSERT, UPDATE, etc.)

### 3. Code Readiness
- [ ] Code is in `producer-api-python-rest-lambda-dsql/` directory
- [ ] `requirements.txt` includes `boto3>=1.28.0`
- [ ] `repository/iam_auth.py` exists
- [ ] `config.py` supports DSQL configuration
- [ ] `repository/connection_pool.py` supports IAM auth

### 4. Terraform Configuration
- [ ] `terraform/terraform.tfvars` file created
- [ ] DSQL variables configured:
  - [ ] `enable_aurora_dsql = true`
  - [ ] `aurora_dsql_endpoint` set
  - [ ] `iam_database_user` set
  - [ ] `aurora_dsql_cluster_resource_id` set
  - [ ] `database_name` set
- [ ] Cost optimization settings:
  - [ ] `lambda_memory_size = 256` (or lower)
  - [ ] `lambda_timeout = 15`
  - [ ] `cloudwatch_logs_retention_days = 1`
  - [ ] `environment = "dev"`
- [ ] Unnecessary resources disabled:
  - [ ] `enable_aurora = false` (using existing DSQL)
  - [ ] `enable_rds_proxy = false`
  - [ ] `enable_database = false`

## 🚀 Quick Deployment Test

### Step 1: Build Lambda Package
```bash
cd producer-api-python-rest-lambda-dsql
./scripts/build-lambda.sh
```
**Expected**: Creates `lambda-deployment.zip`

### Step 2: Verify Terraform Configuration
```bash
cd ../terraform
terraform init
terraform validate
```
**Expected**: No errors

### Step 3: Plan Deployment
```bash
terraform plan -out=tfplan
```
**Expected**: 
- Shows resources to be created (Lambda, API Gateway, S3, IAM)
- Shows DSQL configuration in environment variables
- No errors

### Step 4: Check Estimated Costs
Review the plan output for:
- Lambda function (256MB, 15s timeout)
- API Gateway HTTP API
- S3 bucket (minimal)
- CloudWatch Logs (1-day retention)
- **No VPC resources** (if DSQL supports public access)

## ⚠️ Common Issues & Solutions

### Issue: "DSQL cluster not found"
**Solution**: Verify cluster endpoint and resource ID are correct. Check AWS Console.

### Issue: "IAM user does not exist"
**Solution**: Create IAM database user in DSQL cluster:
```sql
CREATE USER your_iam_user;
GRANT CONNECT ON DATABASE your_db TO your_iam_user;
GRANT USAGE ON SCHEMA public TO your_iam_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO your_iam_user;
```

### Issue: "rds-db:connect permission denied"
**Solution**: Verify IAM policy in Terraform includes the correct cluster resource ID.

### Issue: "Connection timeout"
**Solution**: 
- Check if DSQL requires VPC access
- If yes, set `enable_vpc = true` and provide VPC/subnet IDs
- If no, ensure security groups allow Lambda → DSQL connection

### Issue: "Lambda package too large"
**Solution**: 
- Check `lambda-deployment.zip` size (should be < 50MB for direct upload)
- If larger, ensure S3 bucket is configured
- Remove unnecessary dependencies from `requirements.txt`

## 💰 Cost Verification

### Before Deployment
- [ ] Reviewed AWS Free Tier eligibility
- [ ] Estimated monthly cost: $5-10 (excluding DSQL cluster)
- [ ] Set up AWS Budget alerts (optional but recommended)

### After Deployment
- [ ] Monitor AWS Cost Explorer
- [ ] Check CloudWatch metrics for Lambda invocations
- [ ] Review API Gateway usage

## 📋 Deployment Commands

```bash
# 1. Build Lambda
cd producer-api-python-rest-lambda-dsql
./scripts/build-lambda.sh

# 2. Upload to S3 (if not using Terraform auto-upload)
# aws s3 cp lambda-deployment.zip s3://YOUR-BUCKET/python-rest/lambda-deployment.zip

# 3. Deploy with Terraform
cd ../terraform
terraform init
terraform plan
terraform apply

# 4. Get API URL
terraform output python_rest_api_url

# 5. Test
API_URL=$(terraform output -raw python_rest_api_url)
curl $API_URL/api/v1/events/health
```

## ✅ Post-Deployment Verification

- [ ] API Gateway endpoint returns 200 for health check
- [ ] Lambda function appears in AWS Console
- [ ] CloudWatch logs show successful IAM token generation
- [ ] Test event processing works
- [ ] IAM permissions are correctly configured
- [ ] No VPC-related errors (if not using VPC)

## 🧹 Cleanup (When Done Testing)

```bash
cd terraform
terraform destroy
```

**Note**: This does NOT delete the DSQL cluster.

## 📞 Need Help?

1. Check CloudWatch Logs: `/aws/lambda/producer-api-python-rest-lambda-dsql`
2. Review Terraform outputs: `terraform output`
3. Verify IAM permissions: AWS Console → IAM → Roles
4. Check DSQL cluster status: AWS Console → RDS → DSQL Clusters

