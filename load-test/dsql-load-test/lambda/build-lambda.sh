#!/bin/bash
set -e

# Build script for Lambda deployment
# This script builds the Python Lambda function for AWS Lambda

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PACKAGE_DIR="$BUILD_DIR/package"

echo "Building Lambda function for DSQL load test..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$PACKAGE_DIR"

# Install dependencies to package directory
# Use --platform to ensure Linux-compatible binaries for Lambda (runs on Amazon Linux ARM64)
echo "Installing Python dependencies (Linux ARM64 for Lambda)..."
TEMP_REQUIREMENTS=$(mktemp)
grep -v "^-e" "$SCRIPT_DIR/requirements.txt" > "$TEMP_REQUIREMENTS" || cp "$SCRIPT_DIR/requirements.txt" "$TEMP_REQUIREMENTS"
pip install -r "$TEMP_REQUIREMENTS" -t "$PACKAGE_DIR" --upgrade --platform manylinux2014_aarch64 --only-binary=:all: --python-version 3.11 --implementation cp || \
pip install -r "$TEMP_REQUIREMENTS" -t "$PACKAGE_DIR" --upgrade --no-binary=:all: || \
pip install -r "$TEMP_REQUIREMENTS" -t "$PACKAGE_DIR" --upgrade
rm -f "$TEMP_REQUIREMENTS"

# Copy application code
echo "Copying application code..."
find "$SCRIPT_DIR" -maxdepth 1 -name "*.py" -exec cp {} "$PACKAGE_DIR/" \;

# Remove unnecessary files
find "$PACKAGE_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$PACKAGE_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$PACKAGE_DIR" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find "$PACKAGE_DIR" -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Create deployment package
echo "Creating deployment package..."
cd "$PACKAGE_DIR"
zip -r "$SCRIPT_DIR/lambda-deployment.zip" . > /dev/null

echo "Build complete! Deployment package: $SCRIPT_DIR/lambda-deployment.zip"
echo "Package size: $(du -h "$SCRIPT_DIR/lambda-deployment.zip" | cut -f1)"
