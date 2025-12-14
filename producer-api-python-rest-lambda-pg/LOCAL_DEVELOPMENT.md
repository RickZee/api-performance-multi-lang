# Local Development with SAM and Docker

This guide explains how to run the Python REST API locally using AWS SAM CLI with a dockerized PostgreSQL database.

## Prerequisites

- AWS SAM CLI installed (`brew install aws-sam-cli`)
- Docker Desktop running
- k6 installed for load testing (`brew install k6`)

## Quick Start

### 1. Start PostgreSQL Database

```bash
docker-compose up -d postgres
```

This will:
- Start PostgreSQL 15 in a Docker container
- Create the `car_dealership` database
- Initialize the schema from `../data/schema.sql`

### 2. Start SAM Local API

```bash
./scripts/start-local.sh
```

This script will:
- Ensure PostgreSQL is running
- Build the Lambda package if needed
- Start SAM local API on port 3000

The API will be available at: `http://localhost:3000`

### 3. Test the API

In another terminal, run k6 tests:

```bash
./scripts/test-local-api.sh
```

### 4. Validate Entities

After running tests, validate that entities were created:

```bash
./scripts/validate-entities.sh
```

## Manual Steps

### Start PostgreSQL Only

```bash
docker-compose up -d postgres
```

### Start SAM Local API Manually

```bash
# Build Lambda package first
./scripts/build-lambda.sh

# Start SAM local API
sam local start-api \
    --port 3000 \
    --warm-containers EAGER \
    --container-host host.docker.internal \
    --parameter-overrides \
        "DatabaseURL=postgresql://postgres:postgres@host.docker.internal:5432/car_dealership" \
        "LogLevel=info" \
    --docker-network bridge
```

### Run k6 Tests Manually

```bash
cd ../../load-test/k6

HOST=localhost \
PORT=3000 \
PATH=/api/v1/events \
k6 run rest-api-test.js
```

### Query Database Manually

```bash
# Connect to database
docker exec -it car_dealership_db psql -U postgres -d car_dealership

# Example queries:
SELECT COUNT(*) FROM business_events;
SELECT COUNT(*) FROM event_headers;
SELECT COUNT(*) FROM car_entities;
SELECT COUNT(*) FROM loan_entities;
SELECT COUNT(*) FROM loan_payment_entities;
SELECT COUNT(*) FROM service_record_entities;
```

## Configuration

### Database Connection

The SAM local API connects to PostgreSQL using:
- Host: `host.docker.internal` (allows Docker containers to access host services)
- Port: `5432`
- Database: `car_dealership`
- User: `postgres`
- Password: `postgres`

### Environment Variables

SAM local uses the following parameter overrides:
- `DatabaseURL`: PostgreSQL connection string
- `LogLevel`: Logging level (info, debug, warn, error)

## Troubleshooting

### PostgreSQL Not Starting

```bash
# Check container status
docker ps -a | grep car_dealership_db

# View logs
docker logs car_dealership_db

# Restart container
docker-compose restart postgres
```

### SAM Local API Not Starting

```bash
# Check if port 3000 is in use
lsof -i :3000

# Rebuild Lambda package
./scripts/build-lambda.sh

# Check SAM CLI version
sam --version
```

### Database Connection Issues

```bash
# Test database connection from host
docker exec car_dealership_db psql -U postgres -d car_dealership -c "SELECT 1;"

# Check if database exists
docker exec car_dealership_db psql -U postgres -l | grep car_dealership
```

### Clean Up

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (WARNING: deletes all data)
docker-compose down -v
```

## API Endpoints

Once SAM local API is running:

- **POST** `http://localhost:3000/api/v1/events` - Process single event
- **POST** `http://localhost:3000/api/v1/events/bulk` - Process multiple events
- **GET** `http://localhost:3000/api/v1/events/health` - Health check

## Notes

- SAM local runs the Lambda function in Docker containers
- The `host.docker.internal` hostname allows Lambda containers to access PostgreSQL on the host
- Database schema is automatically initialized when PostgreSQL container starts
- All data persists in Docker volumes until explicitly removed

