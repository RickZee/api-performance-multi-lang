# DSQL Lambda Deployment Status

## ✅ Completed

1. **Lambda Package Built**: `lambda-deployment.zip` (27MB)
2. **Package Uploaded to S3**: `s3://producer-api-lambda-deployments-978300727880/python-rest-dsql/lambda-deployment.zip`
3. **Terraform Configuration Updated**:
   - New module: `python_rest_lambda_dsql`
   - Function name: `producer-api-python-rest-lambda-dsql`
   - API name: `producer-api-python-rest-dsql-http-api`
   - API URL will be: `https://{api-id}.execute-api.us-east-1.amazonaws.com`
4. **Terraform Initialized**: Ready to deploy
5. **Variables Added**: `enable_python_lambda_dsql` variable created

## ⚠️ Required Before Deployment

You need to provide your **Aurora DSQL cluster information** in `terraform.tfvars`:

```hcl
# Update these values in terraform/terraform.tfvars:
aurora_dsql_endpoint = "YOUR-DSQL-CLUSTER-ENDPOINT.cluster-xxxxx.us-east-1.rds.amazonaws.com"
iam_database_user = "YOUR-IAM-DB-USER"
aurora_dsql_cluster_resource_id = "cluster-xxxxx"
```

### How to Get DSQL Cluster Info

**Option 1: AWS Console**
1. Go to AWS Console → RDS → Databases
2. Find your DSQL cluster
3. Copy:
   - **Endpoint** (writer endpoint)
   - **Resource ID** (in cluster details, format: `cluster-xxxxx`)
   - **IAM Database User** (created in the cluster)

**Option 2: AWS CLI**
```bash
aws rds describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,Endpoint,DbClusterResourceId,Engine]' --output table
```

**Option 3: Use Helper Script**
```bash
cd terraform
./scripts/get-dsql-info.sh
```

## 🚀 Deployment Steps

Once you have the DSQL cluster information:

1. **Update terraform.tfvars**:
   ```bash
   # Edit terraform/terraform.tfvars
   # Replace the TODO placeholders with your DSQL cluster info
   ```

2. **Plan Deployment**:
   ```bash
   cd terraform
   terraform plan -out=tfplan
   ```

3. **Review Plan**:
   - Should show creation of:
     - Lambda function: `producer-api-python-rest-lambda-dsql`
     - API Gateway: `producer-api-python-rest-dsql-http-api`
     - IAM role and policies
     - CloudWatch log groups

4. **Deploy**:
   ```bash
   terraform apply tfplan
   ```

5. **Get API URL**:
   ```bash
   terraform output python_rest_dsql_api_url
   ```

6. **Test**:
   ```bash
   API_URL=$(terraform output -raw python_rest_dsql_api_url)
   curl $API_URL/api/v1/events/health
   ```

## 📋 Current Configuration

**Function Name**: `producer-api-python-rest-lambda-dsql`  
**API Name**: `producer-api-python-rest-dsql-http-api`  
**S3 Package**: `s3://producer-api-lambda-deployments-978300727880/python-rest-dsql/lambda-deployment.zip`  
**Memory**: 256MB (cost-optimized)  
**Timeout**: 15s (cost-optimized)  
**Runtime**: Python 3.11

## 🔍 Verification

After deployment, verify:
- [ ] Lambda function exists in AWS Console
- [ ] API Gateway endpoint is accessible
- [ ] Health check returns 200
- [ ] IAM permissions are correct
- [ ] CloudWatch logs show IAM token generation

## 💰 Estimated Cost

- **Lambda**: Free tier (1M requests) + ~$4-5/month after
- **API Gateway**: Free tier (1M requests) + ~$1/month after
- **S3**: ~$0.10/month
- **CloudWatch Logs**: ~$0.50/month (1-day retention)
- **Total**: ~$5-10/month (excluding DSQL cluster)

## 🆘 Troubleshooting

**State Lock Error**: If you see a state lock error:
```bash
terraform force-unlock <lock-id>
```

**Missing DSQL Cluster**: If you don't have a DSQL cluster yet:
- Create one via AWS Console/CLI first
- Or use regular Aurora temporarily

**IAM Permission Errors**: Verify:
- IAM database user exists in DSQL cluster
- Cluster resource ID is correct
- Lambda IAM role has `rds-db:connect` permission

