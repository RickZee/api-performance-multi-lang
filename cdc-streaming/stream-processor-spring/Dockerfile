# Multi-stage build for optimized Spring Boot application
FROM eclipse-temurin:17-jdk AS build

WORKDIR /app

# Copy Gradle wrapper and build files
COPY gradle/ gradle/
COPY gradlew build.gradle settings.gradle ./

# Download dependencies (cached layer)
RUN ./gradlew dependencies --no-daemon || true

# Copy source code
COPY src/ src/

# Build application
RUN ./gradlew build -x test --no-daemon

# Runtime stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Install curl and getent (for DNS resolution) for health checks and startup
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r spring && useradd -r -g spring spring

# Copy built JAR from build stage
COPY --from=build /app/build/libs/*.jar app.jar

# Copy entrypoint script
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Switch to non-root user
USER spring:spring

# Expose actuator port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=5 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Run application with entrypoint script
ENTRYPOINT ["/app/docker-entrypoint.sh"]
