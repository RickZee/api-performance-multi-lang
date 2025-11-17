#!/bin/bash
set -e

# Build script for Lambda deployment
# This script builds the Go Lambda function for AWS Lambda

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
LAMBDA_DIR="$PROJECT_ROOT/cmd/lambda"

echo "Building Lambda function for producer-api-go-rest..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build for Linux (Lambda runs on Amazon Linux)
echo "Compiling Go binary for Linux..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
  -tags lambda.norpc \
  -o "$BUILD_DIR/bootstrap" \
  "$LAMBDA_DIR/main.go"

if [ ! -f "$BUILD_DIR/bootstrap" ]; then
  echo "Error: Failed to build Lambda function"
  exit 1
fi

# Copy migrations directory if it exists
if [ -d "$PROJECT_ROOT/migrations" ]; then
  echo "Copying migrations directory..."
  cp -r "$PROJECT_ROOT/migrations" "$BUILD_DIR/"
fi

# Create deployment package
echo "Creating deployment package..."
cd "$BUILD_DIR"
zip -r "$PROJECT_ROOT/lambda-deployment.zip" . > /dev/null

echo "Build complete! Deployment package: $PROJECT_ROOT/lambda-deployment.zip"
echo "Binary size: $(du -h "$BUILD_DIR/bootstrap" | cut -f1)"

