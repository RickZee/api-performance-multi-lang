#!/bin/bash
set -e

# Shared build script for Go Lambda functions
# Usage: build-go-lambda.sh <project-name> [--proto]

PROJECT_NAME="${1:-}"
GENERATE_PROTO=false

# Parse arguments
if [ "$2" = "--proto" ] || [ "$3" = "--proto" ]; then
    GENERATE_PROTO=true
fi

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Project name is required"
    echo "Usage: $0 <project-name> [--proto]"
    exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API_DIR="$PROJECT_ROOT/$PROJECT_NAME"

if [ ! -d "$API_DIR" ]; then
    echo "Error: Project directory not found: $API_DIR"
    exit 1
fi

cd "$API_DIR"

BUILD_DIR="$API_DIR/build"
LAMBDA_DIR="$API_DIR/cmd/lambda"

echo "Building Lambda function for $PROJECT_NAME..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Generate proto files if needed
if [ "$GENERATE_PROTO" = true ]; then
    if [ -d "$API_DIR/proto" ] && [ -f "$API_DIR/proto"/*.proto ] 2>/dev/null; then
        echo "Generating proto files..."
        if command -v protoc >/dev/null 2>&1; then
            # Ensure PATH includes Go bin for protoc-gen-go
            export PATH="${HOME}/go/bin:/opt/homebrew/bin:${PATH}"
            # Generate proto files in the proto directory
            protoc --proto_path=proto --go_out=proto --go_opt=paths=source_relative \
                   --go-grpc_out=proto --go-grpc_opt=paths=source_relative \
                   proto/*.proto
            if [ $? -eq 0 ]; then
                echo "Proto files generated successfully"
            else
                echo "Warning: Proto generation failed, but continuing..."
            fi
        else
            echo "Warning: protoc not found, proto files may not be generated"
        fi
    fi
fi

# Build for Linux ARM64 (Lambda runs on Amazon Linux ARM64/Graviton2)
echo "Compiling Go binary for Linux ARM64..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build \
  -tags lambda.norpc \
  -o "$BUILD_DIR/bootstrap" \
  "$LAMBDA_DIR/main.go"

if [ ! -f "$BUILD_DIR/bootstrap" ]; then
  echo "Error: Failed to build Lambda function"
  exit 1
fi

# Copy migrations directory if it exists
if [ -d "$API_DIR/migrations" ]; then
  echo "Copying migrations directory..."
  cp -r "$API_DIR/migrations" "$BUILD_DIR/"
fi

# Create deployment package
echo "Creating deployment package..."
cd "$BUILD_DIR"
zip -r "$API_DIR/lambda-deployment.zip" . > /dev/null

echo "Build complete! Deployment package: $API_DIR/lambda-deployment.zip"
echo "Binary size: $(du -h "$BUILD_DIR/bootstrap" | cut -f1)"

