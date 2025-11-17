# Producer API - Java REST

Spring Boot RESTful API using Spring WebFlux (reactive) and R2DBC for non-blocking I/O.

## Overview

| Property | Value |
|----------|-------|
| Protocol | REST |
| Port | 8081 |
| Language | Java |
| Framework | Spring Boot (WebFlux) |
| Database Driver | R2DBC |

## Key Features

- Reactive programming with Spring WebFlux
- Comprehensive Bean Validation
- Spring Data R2DBC for non-blocking database access

## Build & Run

Configuration uses `application.yml`.

```bash
./gradlew bootRun    # Run locally
./gradlew test       # Run tests
./gradlew build      # Build JAR
```

For Docker usage, see the main [README.md](../README.md).
