# Terraform-Based IAM Grant Solution

**Date**: December 19, 2025  
**Status**: ✅ **Implemented**

---

## Problem

Previously, we were using AWS CLI commands to grant IAM role access to DSQL users. This required manual execution and wasn't managed by Terraform.

## Solution

We've updated Terraform to use the existing `dsql-iam-grant` Lambda module to automatically grant IAM role access. This is fully managed by Terraform.

---

## Implementation

### 1. Lambda Module

The `terraform/modules/dsql-iam-grant/` module creates:
- **Lambda Function**: Executes SQL `AWS IAM GRANT` command
- **IAM Role**: For Lambda execution with DSQL admin permissions
- **Python Code**: Connects to DSQL and grants IAM role access

### 2. Terraform Integration

Updated `terraform/main.tf` to:
- **Create Lambda**: Via `module.dsql_iam_grant`
- **Invoke Lambda**: Via `null_resource` with `local-exec` provisioner
- **Handle Errors**: Gracefully handles case where Lambda role isn't mapped yet

---

## One-Time Setup

### Initial Lambda Role Mapping

Before Terraform can automatically grant access, the Lambda's IAM role must be mapped to the `postgres` user in DSQL:

```sql
AWS IAM GRANT postgres TO 'arn:aws:iam::ACCOUNT_ID:role/PROJECT_NAME-dsql-iam-grant-role';
```

**This is a one-time manual step** that requires DSQL admin access.

### After Initial Setup

Once the Lambda role is mapped, Terraform will automatically:
1. Create the Lambda function
2. Invoke it to grant bastion role access
3. Verify the grant succeeded

---

## Usage

### Apply Terraform

```bash
cd terraform
terraform apply
```

Terraform will:
1. Create the Lambda function
2. Attempt to grant IAM role access
3. If Lambda role isn't mapped, show instructions for one-time setup
4. If Lambda role is mapped, automatically grant bastion role access

### Manual Grant (Alternative)

If you prefer to grant directly without Lambda:

```sql
AWS IAM GRANT lambda_dsql_user TO 'arn:aws:iam::ACCOUNT_ID:role/producer-api-bastion-role';
```

---

## Benefits

### ✅ Terraform-Managed
- All infrastructure managed by Terraform
- No manual AWS CLI commands needed
- Idempotent (can run multiple times safely)

### ✅ Automatic
- Grants IAM access automatically after initial setup
- No manual intervention required
- Handles errors gracefully

### ✅ Maintainable
- Changes to grant logic in one place (Lambda)
- Easy to update or extend
- Version controlled

---

## Lambda Function Details

### Input Event
```json
{
  "dsql_host": "cluster-id.dsql-suffix.region.on.aws",
  "iam_user": "lambda_dsql_user",
  "role_arn": "arn:aws:iam::account:role/role-name",
  "region": "us-east-1"
}
```

### Output
```json
{
  "statusCode": 200,
  "body": {
    "message": "IAM role mapping granted successfully",
    "mappings": [
      {
        "role": "lambda_dsql_user",
        "arn": "arn:aws:iam::account:role/role-name"
      }
    ]
  }
}
```

---

## Troubleshooting

### Lambda Returns 500
- **Cause**: Lambda role not mapped to postgres user
- **Solution**: Run one-time setup command (see above)

### Lambda Returns 400
- **Cause**: Missing required parameters
- **Solution**: Check Terraform variables are set correctly

### Connection Errors
- **Cause**: DSQL host unreachable or security group issues
- **Solution**: Verify VPC configuration and security groups

---

## Files Modified

1. **terraform/main.tf**
   - Added `module.dsql_iam_grant`
   - Updated `null_resource.grant_bastion_iam_access` to invoke Lambda
   - Added data sources for region and account ID

---

## Next Steps

1. **Run Terraform Apply**
   ```bash
   cd terraform
   terraform apply
   ```

2. **If Lambda Role Not Mapped**
   - Follow one-time setup instructions
   - Re-run `terraform apply`

3. **Verify Grant**
   - Check Lambda logs in CloudWatch
   - Test connection from bastion host

---

## Summary

✅ **Solution**: Terraform-managed Lambda function  
✅ **Benefits**: Automatic, maintainable, idempotent  
✅ **Status**: Ready to use

**No more manual AWS CLI commands needed!** 🎉
