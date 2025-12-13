# Local Development Setup

This directory contains the Python REST API that can be run locally using AWS SAM CLI with a dockerized PostgreSQL database.

## Quick Start

1. **Start PostgreSQL:**
   ```bash
   docker-compose up -d postgres
   ```

2. **Start SAM Local API:**
   ```bash
   ./scripts/start-local.sh
   ```

3. **Run k6 Tests:**
   ```bash
   ./scripts/test-local-api.sh
   ```

4. **Validate Entities:**
   ```bash
   ./scripts/validate-entities.sh
   ```

## Files Created

- `docker-compose.yml` - PostgreSQL database container
- `samconfig.toml` - SAM CLI configuration for local development
- `scripts/start-local.sh` - Start SAM local API with PostgreSQL
- `scripts/test-local-api.sh` - Run k6 tests against local API
- `scripts/validate-entities.sh` - Validate entities in database
- `LOCAL_DEVELOPMENT.md` - Detailed local development guide

## Database

- **Database Name:** `car_dealership`
- **User:** `postgres`
- **Password:** `postgres`
- **Port:** `5432`
- **Schema:** Automatically initialized from `../data/schema.sql`

## API Endpoints

Once SAM local API is running on port 3000:

- `POST http://localhost:3000/api/v1/events` - Process single event
- `POST http://localhost:3000/api/v1/events/bulk` - Process multiple events
- `GET http://localhost:3000/api/v1/events/health` - Health check

## Notes

- SAM local runs Lambda functions in Docker containers
- Uses `host.docker.internal` to connect from Lambda containers to PostgreSQL on host
- All database tables are created automatically when PostgreSQL starts
- Data persists in Docker volumes until explicitly removed

For detailed instructions, see [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md).

