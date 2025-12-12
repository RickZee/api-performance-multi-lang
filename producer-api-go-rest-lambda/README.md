# Producer API Go REST - Lambda Serverless

AWS Lambda serverless implementation of the Producer API Go REST using API Gateway HTTP API.

## Overview

This is the serverless Lambda version of the Producer API Go REST. It provides the same functionality as the containerized version but is optimized for AWS Lambda execution with Aurora Serverless PostgreSQL.

## Features

- **API Gateway HTTP API** integration
- **Aurora Serverless PostgreSQL** support with optimized connection pooling
- **All REST endpoints**: `/api/v1/events`, `/api/v1/events/bulk`, `/api/v1/events/health`
- **Connection pooling** optimized for Lambda container reuse
- **Infrastructure as Code**: Database schema initialized automatically by Terraform

## Quick Start

### Prerequisites

- AWS CLI configured
- AWS SAM CLI installed
- Go 1.21+
- Aurora Serverless PostgreSQL cluster (or RDS PostgreSQL)

### Build

```bash
./scripts/build-lambda.sh
```

### Deploy

```bash
# Guided deployment (interactive)
./scripts/deploy-lambda.sh --guided

# Or with parameters
./scripts/deploy-lambda.sh \
  --stack-name producer-api-rest-lambda \
  --region us-east-1 \
  --s3-bucket your-sam-bucket \
  --aurora-endpoint your-aurora-cluster.region.rds.amazonaws.com \
  --database-name car_entities \
  --database-user postgres \
  --database-password your-password
```

## Configuration

See the main [README.md](../README.md) for detailed Lambda deployment instructions, including:
- Configuration options
- VPC setup
- Performance considerations
- Monitoring and troubleshooting

## Differences from Containerized Version

- Uses Lambda-specific connection pooling (singleton pattern)
- Handles API Gateway HTTP API v2 events
- Optimized for cold starts and container reuse
- No HTTP server (handles events directly)
