# Producer API Go gRPC - Lambda Serverless

AWS Lambda serverless implementation of the Producer API Go gRPC using API Gateway HTTP API with gRPC-Web protocol support.

## Overview

This is the serverless Lambda version of the Producer API Go gRPC. It provides the same functionality as the containerized version but uses gRPC-Web protocol for browser compatibility and is optimized for AWS Lambda execution with Aurora Serverless PostgreSQL.

## Features

- **API Gateway HTTP API** integration
- **gRPC-Web protocol** support for browser compatibility
- **Aurora Serverless PostgreSQL** support with optimized connection pooling
- **All gRPC methods**: `ProcessEvent`, `HealthCheck`
- **Connection pooling** optimized for Lambda container reuse
- **Automatic migrations** on startup

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
  --stack-name producer-api-grpc-lambda \
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
- gRPC-Web protocol details
- Performance considerations
- Monitoring and troubleshooting

## Differences from Containerized Version

- Uses Lambda-specific connection pooling (singleton pattern)
- Handles API Gateway HTTP API v2 events
- Implements gRPC-Web protocol for browser compatibility
- Optimized for cold starts and container reuse
- No gRPC server (handles gRPC-Web requests via API Gateway)

## gRPC-Web Protocol

The Lambda implementation uses gRPC-Web to enable gRPC calls from browsers:
- Content-Type: `application/grpc-web+proto` (binary) or `application/grpc-web-text` (base64)
- Path format: `/com.example.grpc.EventService/ProcessEvent`
- Supports both binary and text (base64) encoding
