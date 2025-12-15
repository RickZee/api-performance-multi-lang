#!/bin/bash
set -e

# Build script for Lambda deployment using Docker (ensures Linux-compatible binaries)
# This script builds the Python Lambda function for AWS Lambda using Docker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
PACKAGE_DIR="$BUILD_DIR/package"

echo "Building Lambda function for producer-api-python-rest-lambda-pg using Docker..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$PACKAGE_DIR"

# Use Docker to build with Linux-compatible binaries
# Use standard Python image to ensure we get Linux ARM64 binaries
echo "Installing Python dependencies in Docker (Linux ARM64)..."
docker run --rm --platform linux/arm64 -v "$PROJECT_ROOT:/var/task" -v "$PACKAGE_DIR:/package" \
  python:3.11-slim \
  /bin/bash -c "
    pip install -r /var/task/requirements.txt -t /package --upgrade --no-cache-dir --platform manylinux2014_aarch64 --only-binary=:all: || \
    pip install -r /var/task/requirements.txt -t /package --upgrade --no-cache-dir
  "

# Copy application code
echo "Copying application code..."
cp -r "$PROJECT_ROOT"/*.py "$PACKAGE_DIR/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/models" "$PACKAGE_DIR/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/repository" "$PACKAGE_DIR/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/service" "$PACKAGE_DIR/" 2>/dev/null || true
# Note: Migrations are managed by Terraform infrastructure as code, not included in Lambda package

# Remove unnecessary files
find "$PACKAGE_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$PACKAGE_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$PACKAGE_DIR" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find "$PACKAGE_DIR" -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Create deployment package
echo "Creating deployment package..."
cd "$PACKAGE_DIR"
zip -r "$PROJECT_ROOT/lambda-deployment.zip" . > /dev/null

echo "Build complete! Deployment package: $PROJECT_ROOT/lambda-deployment.zip"
echo "Package size: $(du -h "$PROJECT_ROOT/lambda-deployment.zip" | cut -f1)"
