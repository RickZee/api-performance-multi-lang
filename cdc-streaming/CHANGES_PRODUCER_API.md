# Changes: Replaced Lambda API with Producer API Java REST

## Summary

The subsystem has been updated to use `producer-api-java-rest` instead of the Lambda API for event submission to PostgreSQL. This change makes the event producer part of the EC2 deployment rather than an external AWS service.

## What Changed

### 1. Architecture Changes

**Before:**
- Lambda API (external AWS service) → Aurora PostgreSQL
- EC2 deployment: stream-processor, metadata-service, consumers only

**After:**
- Producer API Java REST (on EC2) → Aurora PostgreSQL
- EC2 deployment: producer-api-java-rest, stream-processor, metadata-service, consumers

### 2. Files Updated

#### Plan Document
- `/Users/rickzakharov/.cursor/plans/minimum_configuration_for_cdc_streaming_and_metadata_service_cbe881a4.plan.md`
  - Updated architecture diagram
  - Added producer-api-java-rest to required components
  - Updated dependencies section
  - Updated .env configuration

#### Deployment Guide
- `cdc-streaming/EC2_DEPLOYMENT_GUIDE.md`
  - Updated architecture diagram
  - Added producer-api-java-rest to file copy list
  - Updated .env configuration
  - Added producer API to build/start instructions
  - Updated troubleshooting section
  - Updated service ports

#### Docker Compose
- `cdc-streaming/docker-compose.yml`
  - Added `producer-api-java-rest` service
  - Configured to connect to Aurora PostgreSQL via R2DBC
  - Port: 8081
  - Health check endpoint: `/api/v1/events/health`

#### E2E Pipeline Script
- `cdc-streaming/scripts/test-e2e-pipeline.sh`
  - Step 4: Changed from "Get Lambda API URL" to "Get Producer API URL"
  - Step 5: Changed from "Submit Events to Lambda API" to "Submit Events to Producer API"
  - Updated to use `PRODUCER_API_URL` instead of `LAMBDA_API_URL`
  - Updated pipeline flow message at end

#### Data Flow Documentation
- `cdc-streaming/DATA_FLOW_TO_POSTGRES.md`
  - Updated all references from Lambda API to Producer API Java REST
  - Updated code examples
  - Updated troubleshooting section
  - Updated EC2 deployment instructions

#### E2E Test Guide
- `cdc-streaming/E2E_TEST_PIPELINE_GUIDE.md`
  - Updated pipeline flow diagram
  - Updated prerequisites
  - Updated test scope descriptions

## New Requirements

### Additional Directory to Copy

When deploying to EC2, you must now also copy:
```
producer-api-java-rest/
├── src/
├── build.gradle
├── settings.gradle
├── gradle/
├── Dockerfile
└── ...
```

### New Environment Variables

Add to `.env` file:
```bash
# AWS Aurora Configuration (for Producer API)
AURORA_ENDPOINT=your-aurora-cluster.xxxxx.us-east-1.rds.amazonaws.com
AURORA_DB_NAME=car_entities
AURORA_DB_USER=postgres
AURORA_DB_PASSWORD=your-aurora-password
AURORA_R2DBC_URL=r2dbc:postgresql://${AURORA_ENDPOINT}:5432/${AURORA_DB_NAME}

# Producer API URL (for E2E testing)
PRODUCER_API_URL=http://localhost:8081
```

### New Service Port

- **Producer API**: Port `8081`
- Health endpoint: `http://localhost:8081/api/v1/events/health`

## Migration Steps

If you have an existing deployment:

1. **Copy producer-api-java-rest directory** to EC2
2. **Update .env file** with Aurora credentials and R2DBC URL
3. **Update docker-compose.yml** (already done if using updated version)
4. **Rebuild and restart services**:
   ```bash
   docker-compose build producer-api-java-rest
   docker-compose up -d producer-api-java-rest
   ```
5. **Update test scripts** to use `PRODUCER_API_URL` instead of `LAMBDA_API_URL`

## Benefits

1. **Simplified Architecture**: No need for separate Lambda deployment
2. **Better Control**: Producer API runs on same EC2 as other services
3. **Easier Debugging**: Can view logs directly with `docker-compose logs`
4. **Consistent Technology**: Uses Spring Boot like metadata-service
5. **Direct Database Connection**: Uses R2DBC for reactive database access

## Testing

After deployment, verify Producer API is working:

```bash
# Check health
curl http://localhost:8081/api/v1/events/health

# Submit test event
curl -X POST http://localhost:8081/api/v1/events \
  -H "Content-Type: application/json" \
  -d @data/schemas/event/samples/car-created-event.json

# Check logs
docker-compose logs producer-api-java-rest
```

## Rollback

If you need to revert to Lambda API:

1. Remove `producer-api-java-rest` service from docker-compose.yml
2. Update `test-e2e-pipeline.sh` Step 4 to get Lambda API URL from Terraform
3. Update `test-e2e-pipeline.sh` Step 5 to use `LAMBDA_API_URL`
4. Update `.env` to remove Aurora R2DBC configuration (if not needed elsewhere)
