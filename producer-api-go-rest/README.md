# Producer API - Go REST

Go REST API using Gin framework and pgx.

## Overview

| Property | Value |
|----------|-------|
| Protocol | REST |
| Port | 9083 |
| Language | Go |
| Framework | Gin |
| Database Driver | pgx |
| Bulk Processing | Supported |

## Key Features

- Structured logging with zap
- Automatic migrations on startup
- Flexible date/time parsing (ISO 8601 and Unix timestamps)
- JSON merging for entity updates
- Bulk event processing support

## Build & Run

Configuration uses environment variables.

```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/car_entities"
export SERVER_PORT=9083
```

```bash
go run cmd/server/main.go    # Run locally
go build -o producer-api-go ./cmd/server    # Build binary
```

For Docker usage, see the main [README.md](../README.md).

## Lambda Version

A serverless Lambda version is also available: **[Producer API - Go REST Lambda](../producer-api-go-rest-lambda/README.md)**