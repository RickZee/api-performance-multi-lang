# Producer API Python REST - Lambda Serverless

AWS Lambda serverless implementation of the Producer API Python REST using API Gateway HTTP API.

## Overview

This is the serverless Lambda version of the Producer API Python REST. It provides the same functionality as the containerized versions but is optimized for AWS Lambda execution with Aurora PostgreSQL.

## Features

- **API Gateway HTTP API** integration
- **Aurora PostgreSQL** support with optimized connection pooling
- **All REST endpoints**: `/api/v1/events`, `/api/v1/events/bulk`, `/api/v1/events/health`
- **Connection pooling** optimized for Lambda container reuse (singleton pattern)
- **Async/await** for non-blocking I/O with asyncpg
- **Pydantic** for data validation and models

## Quick Start

### Prerequisites

- AWS CLI configured
- AWS SAM CLI installed
- Python 3.11+
- Aurora PostgreSQL cluster (or RDS PostgreSQL)

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
  --stack-name producer-api-python-rest-lambda \
  --region us-east-1 \
  --parameter-overrides \
    AuroraEndpoint=your-aurora-cluster.region.rds.amazonaws.com \
    DatabaseName=car_entities \
    DatabaseUser=postgres \
    DatabasePassword=your-password
```

## Configuration

See the main [README.md](../README.md) for detailed Lambda deployment instructions, including:
- Configuration options
- VPC setup
- Performance considerations
- Monitoring and troubleshooting

## Project Structure

```
producer-api-python-rest-lambda/
├── lambda_handler.py      # Lambda handler entry point
├── config.py             # Configuration management
├── constants.py           # API constants
├── models/                # Data models (Pydantic)
│   ├── event.py
│   └── entity.py
├── repository/            # Database repository layer
│   ├── connection_pool.py
│   └── car_entity_repo.py
├── service/               # Event processing service
│   └── event_processing.py
├── migrations/            # Database migrations
│   └── 001_initial_schema.sql
├── scripts/               # Build and deployment scripts
│   ├── build-lambda.sh
│   └── deploy-lambda.sh
├── sam-template.yaml      # SAM deployment template
├── requirements.txt       # Python dependencies
└── README.md             # This file
```

## Differences from Containerized Version

- Uses Lambda-specific connection pooling (singleton pattern)
- Handles API Gateway HTTP API v2 events
- Async/await pattern for database operations
- Pydantic for request/response validation
- No web framework overhead (direct Lambda handler)

## Dependencies

- `asyncpg>=0.29.0` - Async PostgreSQL driver
- `pydantic>=2.0.0` - Data validation and models
- `python-dateutil>=2.8.0` - Date parsing utilities

## Runtime

- **Python 3.11** (AWS Lambda runtime)
- **Memory**: 512MB (configurable)
- **Timeout**: 30 seconds (configurable)

## API Endpoints

All endpoints match the containerized versions:

- **POST `/api/v1/events`** - Process a single event
- **POST `/api/v1/events/bulk`** - Process multiple events
- **GET `/api/v1/events/health`** - Health check

## Environment Variables

- `DATABASE_URL` - PostgreSQL connection string (optional if using Aurora components)
- `AURORA_ENDPOINT` - Aurora endpoint (used if DATABASE_URL not provided)
- `DATABASE_NAME` - Database name
- `DATABASE_USER` - Database user
- `DATABASE_PASSWORD` - Database password
- `LOG_LEVEL` - Logging level (debug, info, warn, error)

## Testing

For testing instructions, see the main [README.md](../README.md).
