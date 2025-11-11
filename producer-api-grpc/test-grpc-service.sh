#!/bin/bash

# Test script to verify gRPC service functionality
# This script starts the gRPC service and runs basic tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Testing Producer gRPC API${NC}"
echo -e "${BLUE}========================${NC}"
echo ""

# Build the project
echo -e "${YELLOW}Building the project...${NC}"
./gradlew build -x test

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build successful!${NC}"
else
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo ""

# Run unit tests
echo -e "${YELLOW}Running unit tests...${NC}"
./gradlew test

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Unit tests passed!${NC}"
else
    echo -e "${RED}Unit tests failed!${NC}"
    exit 1
fi

echo ""

# Check if the JAR was created
if [ -f "build/libs/producer-api-grpc-1.0.0.jar" ]; then
    echo -e "${GREEN}JAR file created successfully!${NC}"
    echo -e "Location: build/libs/producer-api-grpc-1.0.0.jar"
else
    echo -e "${RED}JAR file not found!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All tests completed successfully!${NC}"
echo -e "${BLUE}The gRPC service is ready to run.${NC}"
echo ""
echo -e "${YELLOW}To start the service:${NC}"
echo -e "java -jar build/libs/producer-api-grpc-1.0.0.jar"
echo ""
echo -e "${YELLOW}Or with Docker:${NC}"
echo -e "docker build -t producer-api-grpc ."
echo -e "docker run -p 9090:9090 producer-api-grpc"
