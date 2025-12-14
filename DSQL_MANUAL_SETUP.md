# DSQL Manual Setup - Step by Step

## Current Status
- ✅ EC2 instance ready with k6 and psql installed
- ✅ IAM policy `dsql:DbConnectAdmin` added to EC2 role
- ⚠️ IAM permissions may need time to propagate (or use AWS Console)

## Option 1: Connect via SSM and Run Manually

```bash
# Connect to EC2
aws ssm start-session --target i-058cb2a0dc3fdcf3b --region us-east-1
```

Once connected, run:

```bash
export DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export AWS_REGION="us-east-1"
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)

# Test connection (may still fail due to IAM propagation delay)
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "SELECT version();"
```

If connection works, continue with:

```bash
# Create IAM user
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lambda_dsql_user') THEN
        CREATE ROLE lambda_dsql_user WITH LOGIN;
    END IF;
END $$;
GRANT rds_iam TO lambda_dsql_user;
\du
SQL

# Create database
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "CREATE DATABASE car_entities;"

# Create tables (see data/schema.sql or run the full schema)
```

## Option 2: Use AWS Console

1. Go to AWS Console → IAM → Roles → `producer-api-dsql-test-runner-role`
2. Verify the policy `producer-api-dsql-test-runner-dsql-admin` is attached
3. If needed, manually add inline policy with:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["dsql:DbConnectAdmin"],
         "Resource": "arn:aws:dsql:us-east-1:978300727880:cluster:vftmkydwxvxys6asbsc6ih2the"
       }
     ]
   }
   ```

## Option 3: Use Your Local AWS Credentials (If You Have Admin Access)

If your local AWS credentials have DSQL admin access, you can:

1. **Use AWS CloudShell** (has VPC access):
   - Go to AWS Console → CloudShell
   - Run the setup commands there

2. **Use AWS Systems Manager with your credentials**:
   - Modify the SSM command to use your AWS profile
   - Or create a temporary IAM user with admin access

## Quick Test: Lambda API

Once the IAM user is created, test the Lambda:

```bash
curl -X POST https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventHeader": {
      "uuid": "test-'$(date +%s)'",
      "eventName": "Car Created",
      "eventType": "CAR_CREATED",
      "createdDate": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "savedDate": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    },
    "entities": [{
      "entityHeader": {
        "entityId": "entity-test-'$(date +%s)'",
        "entityType": "CAR",
        "createdAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "updatedAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
      },
      "make": "Toyota",
      "model": "Camry"
    }]
  }'
```

## Next Steps After Setup

1. **Create tables** - Run the full schema from `data/schema.sql`
2. **Test Lambda** - Send events via API
3. **Run k6 tests** - Load test from EC2
4. **Verify data** - Check tables in DSQL

## Troubleshooting

If IAM permissions still don't work:
- Wait 5-10 minutes for propagation
- Check CloudTrail for permission denials
- Verify the policy resource ARN matches exactly
- Try using AWS Console to manually attach policy

