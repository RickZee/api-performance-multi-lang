FROM eclipse-temurin:17-jdk AS builder

WORKDIR /app

# Copy gradle files (if they exist)
COPY build.gradle .
COPY settings.gradle .

# Install gradle if gradlew doesn't exist
RUN if [ ! -f gradlew ]; then \
        apt-get update && apt-get install -y gradle && \
        gradle wrapper --gradle-version 8.5; \
    fi

# Copy gradle wrapper if it exists
COPY gradle/ gradle/ 2>/dev/null || true
COPY gradlew* . 2>/dev/null || true

# Make gradlew executable
RUN chmod +x gradlew || true

# Download dependencies
RUN ./gradlew dependencies --no-daemon || gradle dependencies --no-daemon

# Copy source code
COPY src/ src/

# Build the application
RUN ./gradlew build -x test --no-daemon || gradle build -x test --no-daemon

# Runtime stage
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Install git for git sync operations
RUN apk add --no-cache git

# Copy built JAR
COPY --from=builder /app/build/libs/metadata-service-java-1.0.0.jar app.jar

# Create directory for schema cache
RUN mkdir -p /tmp/schema-cache

# Expose port
EXPOSE 8080

# Run the application
CMD ["java", "-jar", "app.jar"]
