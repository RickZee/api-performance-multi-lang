FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app

# Copy pom.xml and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build application
RUN mvn clean package -DskipTests

# Runtime stage - Use Amazon Corretto 21 (matches bastion host)
FROM amazoncorretto:21-alpine

WORKDIR /app

# Copy built JAR
COPY --from=build /app/target/dsql-load-test-1.0.0.jar app.jar

# Install AWS CLI for IAM authentication
RUN apk add --no-cache aws-cli

# Set entrypoint
ENTRYPOINT ["java", "-jar", "app.jar"]

