# Producer API - Java gRPC

Java gRPC API using Spring Boot and R2DBC.

## Overview

| Property | Value |
|----------|-------|
| Protocol | gRPC |
| Port | 9090 |
| Language | Java |
| Framework | Spring Boot |
| Database Driver | R2DBC |
| Proto File | `src/main/proto/event_service.proto` |

## Key Features

- Protocol Buffers for efficient serialization
- HTTP/2 support
- Type-safe generated code
- Spring Boot integration

## Build & Run

Configuration uses `application.yml`.

```bash
./gradlew bootRun    # Run locally
./gradlew test       # Run tests
./gradlew build      # Build JAR
```

For Docker usage, see the main [README.md](../README.md).