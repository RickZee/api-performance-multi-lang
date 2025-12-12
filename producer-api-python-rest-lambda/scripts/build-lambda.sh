#!/bin/bash
set -e

# Build script for Lambda deployment
# This script builds the Python Lambda function for AWS Lambda

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
PACKAGE_DIR="$BUILD_DIR/package"

echo "Building Lambda function for producer-api-python-rest-lambda..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$PACKAGE_DIR"

# Install dependencies to package directory
# Use --platform to ensure Linux-compatible binaries for Lambda (runs on Amazon Linux)
echo "Installing Python dependencies (Linux x86_64 for Lambda)..."
pip install -r "$PROJECT_ROOT/requirements.txt" -t "$PACKAGE_DIR" --upgrade --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11 --implementation cp || \
pip install -r "$PROJECT_ROOT/requirements.txt" -t "$PACKAGE_DIR" --upgrade --no-binary=:all: || \
pip install -r "$PROJECT_ROOT/requirements.txt" -t "$PACKAGE_DIR" --upgrade

# Copy application code
echo "Copying application code..."
# Copy all Python files from root
find "$PROJECT_ROOT" -maxdepth 1 -name "*.py" -exec cp {} "$PACKAGE_DIR/" \;
# Copy all directories
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
