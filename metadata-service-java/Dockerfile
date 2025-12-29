FROM eclipse-temurin:17-jdk AS builder

WORKDIR /app

# Copy gradle files
COPY build.gradle .
COPY settings.gradle .

# Copy gradle wrapper
COPY gradle/ gradle/
COPY gradlew* ./

# Make gradlew executable
RUN chmod +x gradlew

# Download dependencies
RUN ./gradlew dependencies --no-daemon

# Copy source code
COPY src/ src/

# Build the application
RUN ./gradlew build -x test --no-daemon

# Runtime stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Install git for git sync operations
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Copy built JAR
COPY --from=builder /app/build/libs/metadata-service-java-1.0.0.jar app.jar

# Create directory for schema cache
RUN mkdir -p /tmp/schema-cache

# Expose port
EXPOSE 8080

# Run the application
CMD ["java", "-jar", "app.jar"]
