# Back-End Implementation Guide

This document covers the back-end infrastructure components including AWS Lambda functions, Aurora PostgreSQL, and RDS Proxy for the CDC streaming architecture.

## Table of Contents

1. [Aurora PostgreSQL Database](#aurora-postgresql-database)
2. [RDS Proxy for Connection Pooling](#rds-proxy-for-connection-pooling)
3. [Aurora Auto-Start/Stop for Cost Optimization](#aurora-auto-startstop-for-cost-optimization)
4. [Lambda Functions](#lambda-functions)
5. [Configuration and Deployment](#configuration-and-deployment)

## Aurora PostgreSQL Database

### Overview

Aurora PostgreSQL serves as the source of truth for business events stored in the `business_events` table. The database uses a hybrid data model combining relational columns for efficient filtering and a JSONB column for full event data.

### Database Schema

The `business_events` table schema uses a hybrid approach:

```sql
CREATE TABLE business_events (
    -- Relational columns for efficient filtering and querying
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    
    -- JSONB column for full event structure
    event_data JSONB NOT NULL  -- Contains: {eventHeader: {...}, eventBody: {...}}
);
```

**Benefits of This Approach**:

1. **Efficient Filtering**: Relational columns (`event_type`, `event_name`) enable fast filtering in Flink SQL without JSON parsing
2. **Full Data Preservation**: JSONB `event_data` column preserves complete nested event structure
3. **Index Support**: PostgreSQL can index relational columns for fast queries
4. **Flexibility**: Consumers can access both relational metadata and nested entity data
5. **CDC Compatibility**: CDC connectors can efficiently capture both column values and JSONB content

### Logical Replication Configuration

For CDC to work, logical replication must be enabled:

```sql
-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Create replication slot (done by connector)
SELECT pg_create_logical_replication_slot('business_events_cdc_slot', 'pgoutput');
```

### How It Works

- Producer APIs insert events into `business_events` table with both relational columns and full JSONB data
- PostgreSQL Write-Ahead Log (WAL) records all changes
- Logical replication slots enable CDC capture without impacting database performance
- CDC connector captures both relational column values and the `event_data` JSONB content
- Relational columns enable efficient filtering in Flink SQL
- JSONB column preserves full event structure for consumers

## RDS Proxy for Connection Pooling

### Overview

For high-throughput write operations from serverless Lambda functions, **RDS Proxy** is deployed to enable connection pooling and multiplexing.

### Purpose

Manages database connections efficiently for Lambda functions writing events to `business_events` table.

### Benefits

- **Connection Multiplexing**: 2000+ concurrent Lambda instances share a pool of 1,442 actual connections to Aurora (80% of max)
- **Reduced Connection Overhead**: Eliminates "too many clients already" errors by pooling connections
- **Automatic Failover**: Handles connection health checks and automatic failover
- **Improved Latency**: Reuses connections, avoiding connection setup overhead

### Architecture

- Lambda functions connect to RDS Proxy endpoint (not directly to Aurora)
- RDS Proxy maintains a connection pool to Aurora PostgreSQL
- Each Lambda uses 1-2 connections (reduced from 5), with RDS Proxy managing the pool
- CDC connectors continue to connect directly to Aurora (not through proxy)

### Configuration

- **Managed via Terraform**: `terraform/modules/rds-proxy/`
- **Enabled by default**: When both Aurora and Python Lambda are enabled
- **Can be disabled**: Via `enable_rds_proxy = false` variable

### Capacity

- Supports 2000+ concurrent Lambda executions vs ~16 without proxy

### Monitoring

Monitor CloudWatch metrics to detect saturation:

- `ConnectionBorrowedWaitTime`: Time waiting for available connections
- `DatabaseConnections`: Number of active database connections
- `CPUUtilization`: Proxy CPU usage

## Aurora Auto-Start/Stop for Cost Optimization

### Overview

For dev/staging environments, **Aurora Auto-Start/Stop** functionality is deployed to automatically manage database lifecycle and reduce costs during periods of inactivity.

### Purpose

Automatically stops Aurora cluster when inactive and starts it when API requests arrive.

### Benefits

- **Cost Savings**: Reduces compute costs by stopping the database during off-hours or low-activity periods
- **User Experience**: Provides seamless experience with automatic startup on first request
- **Environment**: Only enabled for non-production environments (dev/staging)

### Auto-Stop Lambda

**Purpose**: Monitors API Gateway invocations and automatically stops Aurora cluster after a period of inactivity.

**How It Works**:

1. **Scheduled Execution**: Runs every hour via EventBridge (rate: 1 hour)
2. **Activity Monitoring**: Checks CloudWatch metrics for API Gateway invocations in the last N hours (default: 3 hours)
3. **Decision Logic**:
   - If API invocations detected → Keeps cluster running
   - If no invocations for 3+ hours → Stops Aurora cluster
4. **Fail-Safe**: If metrics cannot be checked, keeps cluster running (prevents accidental shutdowns)

**Configuration**:

- **Trigger**: EventBridge schedule (every 1 hour)
- **Inactivity Threshold**: 3 hours (configurable via `inactivity_hours` variable)
- **Monitoring**: API Gateway `Count` metric from CloudWatch
- **Actions**: `rds:DescribeDBClusters`, `rds:StopDBCluster`, `rds:StartDBCluster`
- **Terraform Module**: `terraform/modules/aurora-auto-stop/`

**Example Flow**:

```text
Hour 0: API receives requests → Cluster running
Hour 1: No requests → Auto-stop Lambda checks → Activity detected → Keeps running
Hour 2: No requests → Auto-stop Lambda checks → Activity detected → Keeps running
Hour 3: No requests → Auto-stop Lambda checks → No activity for 3 hours → Stops cluster
Hour 4: Cluster stopped (saving compute costs)
```

### Auto-Start Lambda

**Purpose**: Automatically starts Aurora cluster when API requests arrive and database is stopped.

**How It Works**:

1. **Trigger**: Invoked by API Lambda when database connection fails
2. **Status Check**: Checks Aurora cluster status via RDS API
3. **Start Logic**:
   - If cluster is `stopped` → Starts cluster immediately
   - If cluster is `available` or `starting` → Returns current status
   - If cluster is in transition → Returns status without action
4. **Response**: Returns status information for API Lambda to provide user feedback

**Integration with API Lambda**:

The Python REST Lambda handler includes automatic database startup logic:

1. **Connection Error Detection**: Catches database connection errors during API requests
2. **Auto-Start Invocation**: Invokes auto-start Lambda to check/start database
3. **User-Friendly Response**: Returns HTTP 503 with retry guidance:

   ```json
   {
     "error": "Service Temporarily Unavailable",
     "message": "The database is currently starting. Please retry your request in 1-2 minutes.",
     "status": 503,
     "retry_after": 120
   }
   ```

4. **Retry Header**: Includes `Retry-After: 120` header for client guidance

**Example Flow**:

```text
1. User submits event to API
2. API Lambda attempts database connection → Fails (database stopped)
3. API Lambda detects connection error
4. API Lambda invokes auto-start Lambda
5. Auto-start Lambda checks status → Cluster is stopped
6. Auto-start Lambda starts cluster
7. API Lambda returns 503: "Database is starting, please retry in 1-2 minutes"
8. User retries after 1-2 minutes → Database is available → Request succeeds
```

**Configuration**:

- **Trigger**: Invoked by API Lambda on connection failure
- **Actions**: `rds:DescribeDBClusters`, `rds:StartDBCluster`
- **Terraform Module**: `terraform/modules/aurora-auto-start/`
- **IAM Permissions**: API Lambda has permission to invoke auto-start Lambda
- **Environment Variable**: `AURORA_AUTO_START_FUNCTION_NAME` set in API Lambda

### Cost Optimization Benefits

**Cost Savings**:

- **Compute Costs**: Aurora compute charges only apply when cluster is running
- **Storage Costs**: Storage charges continue (minimal compared to compute)
- **Typical Savings**: 50-70% cost reduction for dev/staging environments with intermittent usage
- **Example**: If database is stopped 12 hours/day → ~50% cost savings

**When Auto-Start/Stop is Enabled**:

- **Environments**: Only dev/staging (not production)
- **Conditions**:
  - `enable_aurora = true`
  - `enable_python_lambda = true`
  - `environment != "prod"`
- **Terraform**: Automatically deployed when conditions are met

### Monitoring

Key CloudWatch metrics to monitor:

```bash
# Auto-Stop Lambda Metrics
- Invocations: Should be ~24/day (once per hour)
- Duration: Should be < 5 seconds typically
- Errors: Should be 0 (fail-safe keeps cluster running on errors)

# Auto-Start Lambda Metrics
- Invocations: Varies based on API usage patterns
- Duration: Should be < 5 seconds typically
- Errors: Monitor for RDS API errors

# Aurora Metrics
- DBClusterStatus: Monitor transitions (available → stopped → starting → available)
- DatabaseConnections: Should be 0 when stopped

# API Lambda Metrics
- 503 Responses: Track when database is starting
- Connection Errors: Should decrease after auto-start implementation
```

### Best Practices

1. **Confluent Cloud Environments**: Auto-start/stop is disabled for Confluent Cloud to ensure availability
2. **CDC Connectors**: CDC connectors connect directly to Aurora (not through RDS Proxy)
   - **Note**: If database is stopped, CDC connectors will fail until database restarts
   - **Recommendation**: For production CDC pipelines, keep database running or use separate production database
3. **Startup Time**: Aurora typically takes 1-2 minutes to start from stopped state
   - API returns 503 with retry guidance during this period
   - Clients should implement exponential backoff retry logic
4. **Monitoring**: Set up CloudWatch alarms for:
   - Auto-start Lambda errors
   - Excessive 503 responses from API
   - Database startup failures

### Configuration Files

- **Auto-Stop Module**: `terraform/modules/aurora-auto-stop/`
  - `main.tf`: Lambda function and EventBridge schedule
  - `variables.tf`: Configuration variables
  - `outputs.tf`: Function name and ARN
- **Auto-Start Module**: `terraform/modules/aurora-auto-start/`
  - `main.tf`: Lambda function code
  - `variables.tf`: Configuration variables
  - `outputs.tf`: Function name and ARN
- **API Lambda Handler**: `producer-api-python-rest-lambda/lambda_handler.py`
  - Includes connection error detection
  - Invokes auto-start Lambda on connection failure
  - Returns user-friendly 503 responses

### Disabling Auto-Start/Stop

To disable auto-start/stop functionality:

1. **Via Terraform Variables**: Set `environment = "prod"` (auto-start/stop only enabled for non-production)
2. **Manual Override**: Comment out auto-start/stop modules in `terraform/main.tf`
3. **Keep Database Running**: Manually start database and disable auto-stop Lambda schedule

## Lambda Functions

### Producer API Lambda

The producer API Lambda functions handle incoming event requests and write them to the `business_events` table in Aurora PostgreSQL.

**Python REST Lambda** (`producer-api-python-rest-lambda/`):

- **Purpose**: REST API endpoint for creating business events
- **Database Connection**: Uses RDS Proxy endpoint for connection pooling
- **Auto-Start Integration**: Automatically invokes auto-start Lambda on connection failures
- **Error Handling**: Returns user-friendly 503 responses when database is starting

**Key Features**:

- Connection pooling via RDS Proxy
- Automatic database startup on connection failure
- User-friendly error responses with retry guidance
- Support for both local and Aurora PostgreSQL

**Configuration**:

- Environment variables:
  - `DATABASE_URL`: Database connection string (RDS Proxy endpoint)
  - `AURORA_AUTO_START_FUNCTION_NAME`: Auto-start Lambda function name
- IAM Permissions:
  - `rds-db:connect` for database access
  - `lambda:InvokeFunction` for auto-start Lambda invocation

## Configuration and Deployment

### Terraform Modules

All back-end infrastructure is managed via Terraform:

- **Aurora PostgreSQL**: `terraform/modules/aurora/`
- **RDS Proxy**: `terraform/modules/rds-proxy/`
- **Auto-Stop Lambda**: `terraform/modules/aurora-auto-stop/`
- **Auto-Start Lambda**: `terraform/modules/aurora-auto-start/`
- **Lambda Functions**: `terraform/modules/lambda/`

### Deployment Steps

1. **Configure Terraform Variables**:
   ```hcl
   enable_aurora = true
   enable_python_lambda = true
   enable_rds_proxy = true
   environment = "dev"  # or "staging" (not "prod" for auto-start/stop)
   ```

2. **Deploy Infrastructure**:
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

3. **Verify Deployment**:
   - Check Aurora cluster status
   - Verify RDS Proxy endpoint
   - Test Lambda function connectivity
   - Monitor CloudWatch metrics

### Environment-Specific Configuration

**Development/Staging**:
- Auto-start/stop enabled
- RDS Proxy enabled
- Cost optimization features active

**Production**:
- Auto-start/stop disabled
- RDS Proxy enabled
- Database always running
- Enhanced monitoring and alerting

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): Overall system architecture
- [CONFLUENT_CLOUD_SETUP_GUIDE.md](CONFLUENT_CLOUD_SETUP_GUIDE.md): Confluent Cloud setup and Flink configuration
- [README.md](README.md): Main documentation and quick start guide

