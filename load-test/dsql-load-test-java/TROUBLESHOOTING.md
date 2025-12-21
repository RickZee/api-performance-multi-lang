# Java DSQL Load Test - Troubleshooting

## Current Status

✅ **Completed:**
- Java project structure with Maven
- DSQL connection manager with IAM authentication
- Event generators (CarCreated events)
- Scenario 1: Individual inserts implementation
- Scenario 2: Batch inserts implementation
- Dockerfile for containerization
- Deployment script to bastion host
- Bastion host IAM permissions granted

❌ **Issue:**
- IAM token authentication failing with "The security token included in the request is invalid"
- All connection attempts result in authentication errors

## Problem Analysis

The Java implementation uses manual SigV4 query string signing to generate DSQL IAM tokens, but the tokens are being rejected by DSQL. The error suggests:

1. **Token format mismatch**: The token format might not match what DSQL expects
2. **Signature validation failure**: The SigV4 signature might be incorrect
3. **Endpoint mismatch**: Token generation endpoint vs connection endpoint mismatch

## Current Token Generation

The Java code generates tokens in format: `{endpoint}:{port}/?{query_string}`

This matches the Python implementation format, but the tokens are still being rejected.

## Next Steps

1. **Verify token generation**: Compare Java-generated token with AWS CLI-generated token
2. **Check AWS SDK**: Investigate if AWS SDK v2 has a DSQL-specific token generation method
3. **Test with psql**: Verify if manually generated tokens work with psql on bastion
4. **Compare with working implementation**: Review debezium-connector-dsql token generation more carefully

## Files Created

- `pom.xml` - Maven project configuration
- `src/main/java/com/loadtest/dsql/DSQLLoadTest.java` - Main test class
- `src/main/java/com/loadtest/dsql/DSQLConnection.java` - Connection manager
- `src/main/java/com/loadtest/dsql/EventGenerator.java` - Event generators
- `src/main/java/com/loadtest/dsql/EventRepository.java` - Database repository
- `src/main/java/com/loadtest/dsql/auth/IamTokenGenerator.java` - IAM token generator
- `src/main/java/com/loadtest/dsql/auth/SigV4QueryStringSigner.java` - SigV4 signing
- `Dockerfile` - Container build file
- `deploy-to-bastion.sh` - Deployment script

## Test Configuration

- **Scenario 1**: 5 threads, 2 iterations, 1 insert per iteration (minimal test)
- **Scenario 2**: 5 threads, 2 iterations, 10 inserts per batch (minimal test)

## Connection Details

- **Host**: vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws
- **Port**: 5432
- **Database**: postgres
- **IAM User**: lambda_dsql_user
- **Region**: us-east-1

