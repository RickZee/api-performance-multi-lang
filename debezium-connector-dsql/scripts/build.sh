#!/bin/bash
# Build script for DSQL connector

set -e

echo "Building Debezium DSQL Connector..."

# Check Java version
java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | sed '/^1\./s///' | cut -d'.' -f1)
if [ "$java_version" -lt 17 ]; then
    echo "Error: Java 17 or higher is required. Found: $java_version"
    exit 1
fi

# Build
./gradlew clean build

echo "Build complete!"
echo "JAR location: build/libs/debezium-connector-dsql-1.0.0.jar"

