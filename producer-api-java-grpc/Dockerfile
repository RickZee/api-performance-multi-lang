FROM eclipse-temurin:17-jdk

WORKDIR /app

# Copy gradle files
COPY gradle/ gradle/
COPY gradlew .
COPY build.gradle .
COPY settings.gradle .

# Copy source code
COPY src/ src/

# Build the application
RUN ./gradlew build -x test

# Expose gRPC port
EXPOSE 9090

# Run the application
# JAVA_OPTS will be passed from docker-compose environment
CMD sh -c 'java $JAVA_OPTS -jar build/libs/producer-api-grpc-1.0.0.jar'
