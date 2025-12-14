# Debezium Connector for Amazon Aurora DSQL

A production-ready Kafka Connect source connector for Amazon Aurora DSQL that captures database changes and streams them to Kafka, with full IAM authentication, multi-region support, and Confluent Cloud compatibility.

## 📚 Documentation

**Complete deployment and setup documentation:**

- **[DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)** - Step-by-step deployment guide for bastion host with Kafka Connect
- **[INFRASTRUCTURE_SETUP.md](./INFRASTRUCTURE_SETUP.md)** - Infrastructure migration from test runner to bastion host
- **[IAM_AUTHENTICATION.md](./IAM_AUTHENTICATION.md)** - IAM authentication setup, challenges, and solutions
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and their solutions
- **[REAL_DSQL_TESTING.md](./REAL_DSQL_TESTING.md)** - Testing against real DSQL cluster

> **Note**: This documentation covers the complete deployment work including infrastructure migration, Kafka Connect setup, connector deployment, and IAM authentication configuration.

## Overview

This connector enables Change Data Capture (CDC) from Amazon Aurora DSQL databases to Kafka topics. It uses timestamp-based polling to detect changes (since DSQL's internal journals are not publicly accessible) and provides:

- **IAM Authentication**: Automatic token generation and refresh using AWS IAM
- **Multi-Region Support**: Automatic failover between primary and secondary endpoints
- **Connection Pooling**: HikariCP-based connection pool with automatic recovery
- **CDC Compatibility**: Output format compatible with existing Debezium connectors
- **Production Ready**: Error handling, retry logic, and monitoring support

## Architecture

```
┌─────────────────┐
│  Aurora DSQL    │
│  (Multi-Region) │
└────────┬────────┘
         │
         │ IAM Auth + JDBC
         ▼
┌─────────────────┐
│ DSQL Connector  │
│  - IAM Tokens   │
│  - Polling      │
│  - Schema Gen   │
└────────┬────────┘
         │
         │ SourceRecords
         ▼
┌─────────────────┐
│  Kafka Topics   │
│  (Confluent)    │
└─────────────────┘
```

## Prerequisites

- **Java 11** (required for Kafka Connect 7.4.0 compatibility - connector must be built with Java 11)
- Gradle 8.5 or higher
- Amazon Aurora DSQL cluster with IAM authentication enabled
- AWS credentials configured (via IAM role, credentials file, or environment variables)
- Kafka Connect cluster (Confluent Cloud or self-managed)
- Bastion host in same VPC as DSQL (for recommended deployment)

## Building

```bash
cd debezium-connector-dsql
./gradlew build
```

This will create a fat JAR at `build/libs/debezium-connector-dsql-1.0.0.jar` that includes all dependencies.

## Configuration

### Required Configuration Properties

| Property | Description | Example |
|----------|-------------|---------|
| `dsql.endpoint.primary` | Primary DSQL endpoint (hostname) | `dsql-primary.cluster-xyz.us-east-1.rds.amazonaws.com` |
| `dsql.database.name` | Database name | `mortgage_db` |
| `dsql.region` | AWS region for IAM token generation | `us-east-1` |
| `dsql.iam.username` | IAM database username | `admin` |
| `dsql.tables` | Comma-separated list of tables | `event_headers,business_events` |

### Optional Configuration Properties

| Property | Default | Description |
|----------|---------|-------------|
| `dsql.endpoint.secondary` | None | Secondary endpoint for failover |
| `dsql.port` | `5432` | Database port |
| `dsql.poll.interval.ms` | `1000` | Polling interval in milliseconds |
| `dsql.batch.size` | `1000` | Maximum records per poll |
| `dsql.pool.max.size` | `10` | Maximum connection pool size |
| `dsql.pool.min.idle` | `1` | Minimum idle connections |
| `dsql.pool.connection.timeout.ms` | `30000` | Connection timeout in milliseconds |
| `topic.prefix` | `dsql-cdc` | Prefix for Kafka topic names |

### Example Configuration

See `config/dsql-connector.json` for a complete example configuration.

## Deployment

> **Important**: For complete deployment instructions, see [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md). This includes step-by-step instructions for deploying on a bastion host with Kafka Connect and Confluent Cloud.

### Quick Start

1. **Build the connector JAR**:
   ```bash
   ./gradlew build
   ```

2. **Follow the complete deployment guide**: See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for:
   - Infrastructure setup
   - Kafka Connect installation
   - Connector deployment
   - IAM authentication configuration
   - Verification steps

### Deployment Options

#### Option 1: Bastion Host with Kafka Connect (Recommended)

Deploy Kafka Connect on a bastion host in the same VPC as DSQL. This is the current production setup.

**See**: [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for complete instructions.

#### Option 2: Confluent Cloud (Custom Connector)

1. **Build the connector JAR**:
   ```bash
   ./gradlew build
   ```

2. **Upload to Confluent Cloud**:
   - Navigate to Confluent Cloud Console → Connectors
   - Click "Add Connector" → "Custom Connector"
   - Upload the JAR file from `build/libs/debezium-connector-dsql-1.0.0.jar`

3. **Configure the connector**:
   - Use the configuration from `config/dsql-connector.json`
   - Replace environment variables with actual values

4. **Deploy**:
   - Review configuration
   - Click "Deploy"

**Note**: This option requires network connectivity from Confluent Cloud to your DSQL cluster (VPC peering or PrivateLink).

#### Option 3: Self-Managed Kafka Connect

1. **Copy JAR to Kafka Connect plugins directory**:
   ```bash
   cp build/libs/debezium-connector-dsql-1.0.0.jar \
      /path/to/kafka-connect/plugins/debezium-connector-dsql/
   ```

2. **Restart Kafka Connect**:
   ```bash
   systemctl restart kafka-connect
   ```

3. **Create connector via REST API**:
   ```bash
   curl -X POST http://localhost:8083/connectors \
     -H "Content-Type: application/json" \
     -d @config/dsql-connector.json
   ```

## Documentation

- **[DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)** - Complete step-by-step deployment guide
- **[INFRASTRUCTURE_SETUP.md](./INFRASTRUCTURE_SETUP.md)** - Infrastructure migration and setup details
- **[IAM_AUTHENTICATION.md](./IAM_AUTHENTICATION.md)** - IAM authentication setup and challenges
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and solutions
- **[REAL_DSQL_TESTING.md](./REAL_DSQL_TESTING.md)** - Testing against real DSQL cluster

## IAM Authentication Setup

> **Important**: See [IAM_AUTHENTICATION.md](./IAM_AUTHENTICATION.md) for complete IAM authentication setup, including the chicken-and-egg problem and required manual steps.

The connector requires IAM database authentication. Set up IAM authentication as follows:

1. **Create IAM database user in DSQL cluster**:
   ```sql
   CREATE USER admin;
   GRANT CONNECT ON DATABASE mortgage_db TO admin;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO admin;
   ```

2. **Configure IAM policy** (for the IAM role/user running the connector):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": [
         "rds-db:connect"
       ],
       "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-xyz/admin"
     }]
   }
   ```

3. **Ensure AWS credentials are available**:
   - IAM role (for EC2/EKS)
   - AWS credentials file (`~/.aws/credentials`)
   - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

## Change Detection Strategy

Since DSQL's journals/Crossbar are not publicly accessible, the connector uses **timestamp-based polling**:

1. Queries tables for records where `saved_date > last_offset_timestamp`
2. Orders results by `saved_date ASC`
3. Limits results to `batch.size`
4. Updates offset with latest `saved_date` and `id`

**Important**: Tables must have a `saved_date` column (or similar timestamp column) for change detection to work.

## Output Format

The connector generates records in a format compatible with existing Debezium connectors:

```json
{
  "id": "event-123",
  "event_name": "LoanCreated",
  "event_type": "LoanCreated",
  "created_date": "2024-01-15T10:30:00Z",
  "saved_date": "2024-01-15T10:30:05Z",
  "header_data": "{...}",
  "__op": "c",
  "__table": "event_headers",
  "__ts_ms": 1705312205000
}
```

CDC metadata fields:
- `__op`: Operation type (`c`=create, `u`=update, `d`=delete)
- `__table`: Source table name
- `__ts_ms`: Timestamp in milliseconds

## Multi-Region Failover

The connector supports automatic failover between primary and secondary endpoints:

1. **Primary endpoint** is used by default
2. On connection failure, automatically fails over to **secondary endpoint**
3. Periodically attempts to failback to primary (health check every 60 seconds)
4. Connection pool is invalidated and recreated on failover

Configure both endpoints for high availability:
```json
{
  "dsql.endpoint.primary": "dsql-primary.us-east-1.rds.amazonaws.com",
  "dsql.endpoint.secondary": "dsql-secondary.us-west-2.rds.amazonaws.com"
}
```

## Monitoring

### Metrics

The connector exposes standard Kafka Connect metrics:
- `source-record-poll-total`: Total records polled
- `source-record-write-total`: Total records written
- `source-record-poll-rate`: Polling rate (records/second)
- `source-record-write-rate`: Write rate (records/second)

### Logging

Enable debug logging for troubleshooting:
```properties
log4j.logger.io.debezium.connector.dsql=DEBUG
```

### Common Issues

**Connection failures**:
- Verify IAM authentication is configured correctly
- Check AWS credentials are available
- Ensure security groups allow connections from Kafka Connect

**No records polled**:
- Verify table has `saved_date` column
- Check table has data with `saved_date > offset`
- Enable debug logging to see query execution

**Token expiration**:
- Tokens are automatically refreshed every 13 minutes
- Check logs for token refresh errors
- Verify IAM permissions for `rds-db:connect`

## Testing

### Unit Tests

```bash
./gradlew test
```

### Integration Tests

Integration tests use Testcontainers with PostgreSQL (as a proxy for DSQL):

```bash
./gradlew test --tests "*IT"
```

**Note**: Integration tests require Docker to be running.

## Development

### Project Structure

```
debezium-connector-dsql/
├── src/
│   ├── main/java/io/debezium/connector/dsql/
│   │   ├── DsqlConnector.java          # Main connector
│   │   ├── DsqlConnectorConfig.java    # Configuration
│   │   ├── DsqlSourceTask.java         # Source task
│   │   ├── auth/                       # IAM authentication
│   │   ├── connection/                 # Connection pooling
│   │   └── transforms/                 # Record transforms
│   └── test/                           # Tests
├── config/                              # Configuration examples
└── scripts/                             # Build/deploy scripts
```

### Building from Source

```bash
# Clone repository
git clone <repository-url>
cd debezium-connector-dsql

# Build
./gradlew build

# Run tests
./gradlew test

# Create distribution package
./gradlew connectorPackage
```

## Integration with Existing CDC Pipeline

The connector output is compatible with existing Flink SQL jobs. No changes are required to downstream consumers:

1. Deploy the connector alongside existing PostgreSQL connector
2. Configure Flink to consume from `raw-event-headers` topic (same as current)
3. Existing filtering/routing logic works unchanged

## Limitations

- **Timestamp-based polling**: Not true real-time CDC (polling interval determines latency)
- **No WAL access**: Cannot access DSQL's internal journals/Crossbar
- **Single table per task**: Each task monitors one table (can be parallelized with multiple tasks)
- **PostgreSQL compatibility**: Uses PostgreSQL JDBC driver (DSQL is PostgreSQL-compatible)

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

This project is licensed under the Apache License 2.0.

## Support

For issues and questions:
- Open an issue on GitHub
- Check existing documentation
- Review logs with debug logging enabled

## References

- [Amazon Aurora DSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-dsql.html)
- [Kafka Connect Documentation](https://kafka.apache.org/documentation/#connect)
- [Debezium Documentation](https://debezium.io/documentation/)

