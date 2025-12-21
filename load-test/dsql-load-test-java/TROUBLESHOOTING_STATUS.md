# DSQL IAM Authentication Troubleshooting Status

## Completed Steps

✅ **IAM Grant Verified and Executed**
- Confirmed bastion role (`producer-api-bastion-role`) is mapped to IAM database user (`lambda_dsql_user`)
- Verified using `sys.iam_pg_role_mappings` table

✅ **Token Generation Implementation**
- Copied exact SigV4 implementation from working debezium connector
- Correctly uses `Action=DbConnect` for IAM users
- Includes session tokens in canonical request
- Token format: `{endpoint}:{port}/?Action=DbConnect&...`

✅ **System Clock Synchronized**
- Verified NTP is active and system clock is synchronized

✅ **Debug Logging Added**
- Token generation logs show correct format
- Token length: 1796 characters (matches expected size)

## Current Issue

**Status**: Still getting "access denied" errors despite:
- IAM grant being in place
- Token format matching debezium connector
- System clock synchronized
- Session tokens included

## Key Differences from Python Implementation

The Python implementation uses `botocore.auth.SigV4QueryAuth` which:
- Uses `https://` protocol in the signing URL
- Handles credential scope formatting automatically
- May have subtle differences in URL encoding

Our Java implementation:
- Manually implements SigV4 signing
- Matches debezium connector exactly (which works)
- Uses same credential scope format as debezium

## Next Investigation Steps

1. **Compare token byte-by-byte** with Python-generated token
2. **Test with AWS DSQL JDBC Connector** (if available) to bypass manual signing
3. **Check for credential scope format differences** - verify X-Amz-Credential format matches exactly
4. **Verify IAM policy conditions** - check if there are any IP-based or time-based restrictions

## Files Modified

- `src/main/java/com/loadtest/dsql/auth/IamTokenGenerator.java` - Added debug logging
- `src/main/java/com/loadtest/dsql/auth/SigV4QueryStringSigner.java` - Added session token support and action selection
- `deploy-to-bastion.sh` - Added IAM grant verification

## Connection Details

- DSQL Host: `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws`
- IAM Username: `lambda_dsql_user`
- Region: `us-east-1`
- Port: `5432`
- Database: `postgres`

