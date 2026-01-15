# EC2 Deployment Guide for CDC Streaming Subsystem

## Overview

This guide provides step-by-step instructions for deploying the CDC streaming subsystem (stream-processor-spring, metadata-service-java, and consumers) on an EC2 instance, connecting to existing AWS Aurora PostgreSQL and Confluent Cloud infrastructure.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    EC2 Instance                            │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Producer API Java REST (:8081)                     │  │
│  │  └─> Connects to Aurora PostgreSQL (R2DBC)          │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Metadata Service Java (:8080)                      │  │
│  │  └─> PostgreSQL (local or RDS)                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Spring Boot Stream Processor (:8083)                │  │
│  │  └─> Connects to Confluent Cloud Kafka               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  8 Consumer Applications                             │  │
│  │  - 4 Spring consumers (filtered-*-spring topics)     │  │
│  │  - 4 Flink consumers (filtered-*-flink topics)      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         │                    │
         │                    │
         ▼                    ▼
┌──────────────┐    ┌──────────────┐
│ AWS Aurora   │    │ Confluent    │
│ PostgreSQL   │    │ Cloud Kafka  │
│              │    │              │
└──────────────┘    └──────────────┘
```

## Prerequisites

### EC2 Instance Requirements

- **Instance Type**: t3.medium or larger (2+ vCPU, 4+ GB RAM recommended)
- **OS**: Amazon Linux 2023 or Ubuntu 22.04 LTS
- **Storage**: 20+ GB free space
- **Network**: Security group configured with:
  - Outbound to Confluent Cloud (port 9092)
  - Outbound to Aurora PostgreSQL (port 5432)
  - Inbound for health checks (ports 8080, 8081, 8083) - optional

### Required Software

- Docker 20.10+
- Docker Compose 2.0+
- Git
- jq
- curl
- Python 3.8+
- AWS CLI (for accessing Terraform outputs)

### Required Credentials/Information

- Confluent Cloud bootstrap servers
- Confluent Cloud API key and secret
- Aurora PostgreSQL endpoint (from Terraform or AWS Console)
- Aurora database credentials (from AWS Secrets Manager or Terraform)

## Step 1: Identify Files and Folders to Copy

### Required Directories

Copy these directories from the repository to EC2:

```
api-performance-multi-lang/
├── producer-api-java-rest/         # Complete directory (Event Producer)
│   ├── src/
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradle/
│   ├── Dockerfile
│   └── ...
│
├── metadata-service-java/          # Complete directory
│   ├── src/
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradle/
│   ├── Dockerfile
│   └── ...
│
├── cdc-streaming/
│   ├── stream-processor-spring/   # Complete directory
│   │   ├── src/
│   │   ├── build.gradle
│   │   ├── settings.gradle
│   │   ├── gradle/
│   │   ├── Dockerfile
│   │   └── ...
│   │
│   ├── consumers-confluent/        # Complete directory
│   │   ├── car-consumer/
│   │   ├── loan-consumer/
│   │   ├── loan-payment-consumer/
│   │   └── service-consumer/
│   │
│   ├── scripts/                    # Required scripts
│   │   ├── test-e2e-pipeline.sh
│   │   ├── submit-test-events.sh
│   │   ├── validate-consumers.sh
│   │   ├── validate-database-events.sh
│   │   ├── validate-kafka-topics.sh
│   │   └── clear-consumer-logs.sh
│   │
│   ├── docker-compose.yml          # Docker Compose configuration
│   └── config/                     # Optional: filter configs
│
└── data/                           # Schema files
    └── schemas/
        ├── v1/
        ├── v2/
        ├── event/
        └── entity/
```

### File Copy Commands

#### Option 1: Clone Repository on EC2 (Recommended)

```bash
# On EC2 instance
cd /opt
git clone <repository-url> api-performance-multi-lang
cd api-performance-multi-lang
```

#### Option 2: Copy Specific Directories via SCP

```bash
# From local machine
scp -r metadata-service-java ec2-user@<ec2-ip>:/opt/cdc-deployment/
scp -r cdc-streaming ec2-user@<ec2-ip>:/opt/cdc-deployment/
scp -r data ec2-user@<ec2-ip>:/opt/cdc-deployment/
```

#### Option 3: Create Tarball and Transfer

```bash
# From local machine (in project root)
tar -czf cdc-subsystem.tar.gz \
  producer-api-java-rest/ \
  metadata-service-java/ \
  cdc-streaming/ \
  data/

# Transfer to EC2
scp cdc-subsystem.tar.gz ec2-user@<ec2-ip>:/opt/

# On EC2
cd /opt
tar -xzf cdc-subsystem.tar.gz
cd cdc-subsystem
```

## Step 2: EC2 Instance Setup

### Install Required Software

#### Amazon Linux 2023

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install other tools
sudo yum install -y git jq curl python3

# Install AWS CLI (if not already installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Logout and login again for docker group to take effect
```

#### Ubuntu 22.04

```bash
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ubuntu

# Install other tools
sudo apt-get install -y git jq curl python3 python3-pip

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Logout and login again for docker group to take effect
```

## Step 3: Configure Environment Variables

### Create .env File

Create a `.env` file in the `cdc-streaming/` directory:

```bash
cd /opt/api-performance-multi-lang/cdc-streaming
cat > .env <<'EOF'
# Confluent Cloud Configuration
CONFLUENT_BOOTSTRAP_SERVERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
CONFLUENT_CLOUD_API_KEY=your-api-key-here
CONFLUENT_CLOUD_API_SECRET=your-api-secret-here

# Metadata Service Configuration
GIT_REPOSITORY=file:///opt/api-performance-multi-lang/data
METADATA_DB_PASSWORD=secure-password-change-me
SCHEMA_VERSION=v1

# AWS Aurora Configuration (for Producer API and E2E testing)
AURORA_ENDPOINT=your-aurora-cluster.xxxxx.us-east-1.rds.amazonaws.com
AURORA_DB_NAME=car_entities
AURORA_DB_USER=postgres
AURORA_DB_PASSWORD=your-aurora-password
# R2DBC URL for Producer API (auto-constructed from above, or set explicitly)
AURORA_R2DBC_URL=r2dbc:postgresql://${AURORA_ENDPOINT}:5432/${AURORA_DB_NAME}

# Producer API URL (for E2E testing)
# Use localhost if running on same EC2, or EC2 public IP
PRODUCER_API_URL=http://localhost:8081
EOF
```

### Secure the .env File

```bash
chmod 600 .env
```

### Get Values from Terraform (Optional)

If you have Terraform outputs available:

```bash
# From terraform directory
cd /opt/api-performance-multi-lang/terraform

# Get Aurora endpoint
AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint)
echo "AURORA_ENDPOINT=$AURORA_ENDPOINT" >> ../cdc-streaming/.env

# Get database name
DB_NAME=$(terraform output -raw database_name)
echo "AURORA_DB_NAME=$DB_NAME" >> ../cdc-streaming/.env

# Construct R2DBC URL
echo "AURORA_R2DBC_URL=r2dbc:postgresql://${AURORA_ENDPOINT}:5432/${DB_NAME}" >> ../cdc-streaming/.env
```

## Step 4: Update Docker Compose for EC2

### Verify docker-compose.yml

Ensure `cdc-streaming/docker-compose.yml` is configured for Confluent Cloud (not local Redpanda). The file should reference environment variables from `.env`:

```yaml
environment:
  KAFKA_BOOTSTRAP_SERVERS: ${CONFLUENT_BOOTSTRAP_SERVERS}
  KAFKA_API_KEY: ${CONFLUENT_CLOUD_API_KEY}
  KAFKA_API_SECRET: ${CONFLUENT_CLOUD_API_SECRET}
  KAFKA_SECURITY_PROTOCOL: SASL_SSL
  KAFKA_SASL_MECHANISM: PLAIN
```

If the docker-compose.yml uses local Redpanda, update it to use Confluent Cloud environment variables.

## Step 5: Build Docker Images

### Build All Services

```bash
cd /opt/api-performance-multi-lang/cdc-streaming

# Build all images
docker-compose build

# This will build:
# - producer-api-java-rest (Event Producer)
# - metadata-service-java
# - stream-processor (Spring Boot)
# - car-consumer
# - loan-consumer
# - loan-payment-consumer
# - service-consumer
```

### Build Individual Services (if needed)

```bash
# Build producer API
docker-compose build producer-api-java-rest

# Build metadata service
docker-compose build metadata-service-java

# Build stream processor
docker-compose build stream-processor

# Build consumers
docker-compose build car-consumer loan-consumer loan-payment-consumer service-consumer
```

### Verify Images

```bash
docker images | grep -E "producer-api|metadata-service|stream-processor|consumer"
```

## Step 6: Start Services

### Start All Services

```bash
cd /opt/api-performance-multi-lang/cdc-streaming

# Start all services
docker-compose up -d

# Check status
docker-compose ps
```

### Start Services in Order (if dependencies matter)

```bash
# 1. Start PostgreSQL for metadata service
docker-compose up -d postgres-metadata

# Wait for PostgreSQL to be ready
sleep 10

# 2. Start producer API (connects to Aurora)
docker-compose up -d producer-api-java-rest

# Wait for producer API to be ready
sleep 10

# 3. Start metadata service
docker-compose up -d metadata-service-java

# Wait for metadata service to be ready
sleep 15

# 4. Start stream processor
docker-compose up -d stream-processor

# Wait for stream processor to be ready
sleep 10

# 5. Start all consumers
docker-compose up -d car-consumer loan-consumer loan-payment-consumer service-consumer \
  car-consumer-flink loan-consumer-flink loan-payment-consumer-flink service-consumer-flink
```

## Step 7: Verify Deployment

### Check Service Health

```bash
# Check producer API
curl http://localhost:8081/api/v1/events/health

# Check metadata service
curl http://localhost:8080/api/v1/health

# Check stream processor
curl http://localhost:8083/actuator/health

# Expected response: {"status":"UP"} or similar
```

### Check Container Status

```bash
# List all containers
docker-compose ps

# Check logs for any service
docker-compose logs metadata-service-java
docker-compose logs stream-processor
docker-compose logs car-consumer
```

### Verify Database Connection

```bash
# Check metadata service database
docker exec -it metadata-postgres psql -U postgres -d metadata_service -c "\dt"

# Should show: filters table

# Check producer API can connect to Aurora
docker-compose logs producer-api-java-rest | grep -i "database\|r2dbc\|connection"

# Should show successful connection to Aurora
```

### Verify Kafka Connection

```bash
# Check stream processor logs for Kafka connection
docker-compose logs stream-processor | grep -i kafka

# Should show successful connection to Confluent Cloud
```

## Step 8: Run E2E Pipeline Test

### Prerequisites for E2E Test

Ensure you have:
- Aurora cluster running and accessible
- Producer API Java REST running on EC2 (port 8081)
- Confluent Cloud CDC connector running
- Confluent Cloud topics created

### Run Full E2E Pipeline

```bash
cd /opt/api-performance-multi-lang/cdc-streaming

# Run complete E2E pipeline
./scripts/test-e2e-pipeline.sh

# This will:
# 1. Check prerequisites
# 2. Verify Aurora cluster status
# 3. Start consumers (if not running)
# 4. Submit test events to Lambda API
# 5. Validate events in database
# 6. Start stream processor
# 7. Wait for CDC propagation
# 8. Validate Kafka topics
# 9. Validate consumers
# 10. Generate report
```

### Run with Options

```bash
# Skip Aurora check (if already running)
./scripts/test-e2e-pipeline.sh --skip-aurora

# Fast mode (skip builds and prereqs)
./scripts/test-e2e-pipeline.sh --fast

# Skip Java service (if only testing consumers)
./scripts/test-e2e-pipeline.sh --skip-java-service

# Skip Confluent validation
./scripts/test-e2e-pipeline.sh --skip-confluent
```

## Step 9: Monitor Services

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f stream-processor
docker-compose logs -f metadata-service-java
docker-compose logs -f car-consumer

# Last 100 lines
docker-compose logs --tail=100 stream-processor
```

### Check Resource Usage

```bash
# Container stats
docker stats

# Disk usage
docker system df
```

### Monitor Consumer Processing

```bash
# Check consumer logs for event processing
docker-compose logs car-consumer | grep -i "event\|received\|processed"

# Count events processed
docker-compose logs car-consumer | grep -c "Event.*Received"
```

## Step 10: Troubleshooting

### Common Issues

#### 1. Producer API Won't Start

```bash
# Check logs
docker-compose logs producer-api-java-rest

# Common causes:
# - Aurora endpoint not accessible (check security group)
# - Database credentials incorrect (check .env AURORA_* variables)
# - R2DBC URL malformed (check AURORA_R2DBC_URL format)
# - Network connectivity issues (test: telnet $AURORA_ENDPOINT 5432)
```

#### 2. Metadata Service Won't Start

```bash
# Check logs
docker-compose logs metadata-service-java

# Common causes:
# - PostgreSQL not ready (wait longer)
# - Database connection error (check .env DATABASE_URL)
# - Git repository not accessible (check GIT_REPOSITORY path)
```

#### 3. Stream Processor Can't Connect to Kafka

```bash
# Check logs
docker-compose logs stream-processor | grep -i kafka

# Verify environment variables
docker-compose exec stream-processor env | grep KAFKA

# Test Confluent Cloud connection from EC2
telnet pkc-xxxxx.us-east-1.aws.confluent.cloud 9092
```

#### 4. Consumers Not Receiving Events

```bash
# Check consumer logs
docker-compose logs car-consumer

# Verify topic exists in Confluent Cloud
# Check consumer group status
# Verify stream processor is producing to topics
```

#### 5. Database Connection Issues

```bash
# Test Aurora connection from EC2
psql -h $AURORA_ENDPOINT -U $AURORA_DB_USER -d $AURORA_DB_NAME

# Check security group allows outbound to Aurora
# Verify credentials in .env file
```

### Restart Services

```bash
# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart stream-processor

# Recreate service (rebuild and restart)
docker-compose up -d --force-recreate stream-processor
```

### Clean Up and Rebuild

```bash
# Stop all services
docker-compose down

# Remove containers and volumes
docker-compose down -v

# Rebuild and start
docker-compose build
docker-compose up -d
```

## Step 11: Production Considerations

### Use RDS PostgreSQL Instead of Local Container

Update `.env`:

```bash
DATABASE_URL=jdbc:postgresql://your-rds-endpoint:5432/metadata_service
DATABASE_USERNAME=admin
DATABASE_PASSWORD=secure-password
```

Remove `postgres-metadata` service from docker-compose.yml.

### Set Up Logging

```bash
# Configure log rotation
sudo tee /etc/logrotate.d/docker-containers <<EOF
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=10M
    missingok
    delaycompress
    copytruncate
}
EOF
```

### Set Up Monitoring

- Use CloudWatch Logs for container logs
- Set up health check alarms
- Monitor Kafka consumer lag
- Track stream processor metrics

### Security Hardening

- Use AWS Secrets Manager for credentials
- Enable VPC endpoints for AWS services
- Use IAM roles instead of access keys
- Enable encryption in transit and at rest

## Quick Reference

### Essential Commands

```bash
# Navigate to project
cd /opt/api-performance-multi-lang/cdc-streaming

# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs -f

# Check status
docker-compose ps

# Restart service
docker-compose restart <service-name>

# Rebuild service
docker-compose build <service-name>
docker-compose up -d <service-name>

# Run E2E test
./scripts/test-e2e-pipeline.sh
```

### Service Ports

- Producer API: `8081`
- Metadata Service: `8080`
- Stream Processor: `8083` (Actuator)
- PostgreSQL: `5432` (local, if using container)

### Important Files

- `.env` - Environment variables
- `docker-compose.yml` - Service configuration
- `data/schemas/` - Schema definitions
- `scripts/test-e2e-pipeline.sh` - E2E test script

## Support

For issues or questions:
1. Check service logs: `docker-compose logs <service>`
2. Verify environment variables: `cat .env`
3. Test connectivity: `curl http://localhost:8080/api/v1/health`
4. Review documentation in `cdc-streaming/README.md`
