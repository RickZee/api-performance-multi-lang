#!/bin/bash
set -e

# Build script for Lambda deployment
# This script builds the Python Lambda function for AWS Lambda

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
PACKAGE_DIR="$BUILD_DIR/package"

echo "Building Lambda function for producer-api-python-rest-lambda-pg..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$PACKAGE_DIR"

# Install dependencies to package directory
# Use --platform to ensure Linux-compatible binaries for Lambda (runs on Amazon Linux)
echo "Installing Python dependencies (Linux x86_64 for Lambda)..."
# Create a temporary requirements file without editable installs
TEMP_REQUIREMENTS=$(mktemp)
grep -v "^-e" "$PROJECT_ROOT/requirements.txt" > "$TEMP_REQUIREMENTS" || cp "$PROJECT_ROOT/requirements.txt" "$TEMP_REQUIREMENTS"
pip install -r "$TEMP_REQUIREMENTS" -t "$PACKAGE_DIR" --upgrade --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11 --implementation cp || \
pip install -r "$TEMP_REQUIREMENTS" -t "$PACKAGE_DIR" --upgrade --no-binary=:all: || \
pip install -r "$TEMP_REQUIREMENTS" -t "$PACKAGE_DIR" --upgrade
rm -f "$TEMP_REQUIREMENTS"

# Copy application code
echo "Copying application code..."
# Copy all Python files from root
find "$PROJECT_ROOT" -maxdepth 1 -name "*.py" -exec cp {} "$PACKAGE_DIR/" \;
# Copy all directories
cp -r "$PROJECT_ROOT/models" "$PACKAGE_DIR/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/repository" "$PACKAGE_DIR/" 2>/dev/null || true
cp -r "$PROJECT_ROOT/service" "$PACKAGE_DIR/" 2>/dev/null || true

# Copy shared library (producer-api-shared)
SHARED_LIB_DIR="$PROJECT_ROOT/../producer-api-shared"
if [ -d "$SHARED_LIB_DIR" ]; then
    echo "Copying shared library (producer-api-shared)..."
    # Copy the producer_api_shared package directory
    if [ -d "$SHARED_LIB_DIR/producer_api_shared" ]; then
        cp -r "$SHARED_LIB_DIR/producer_api_shared" "$PACKAGE_DIR/" 2>/dev/null || true
        echo "  Copied producer_api_shared package"
    else
        echo "  Warning: producer_api_shared directory not found in $SHARED_LIB_DIR"
    fi
else
    echo "Warning: Shared library directory not found: $SHARED_LIB_DIR"
fi

# Note: Migrations are managed by Terraform infrastructure as code, not included in Lambda package

# Remove unnecessary files
find "$PACKAGE_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$PACKAGE_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$PACKAGE_DIR" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find "$PACKAGE_DIR" -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
# Remove editable install files (they interfere with Lambda imports)
find "$PACKAGE_DIR" -type f -name "__editable__*" -delete 2>/dev/null || true
find "$PACKAGE_DIR" -type f -name "*.pth" -delete 2>/dev/null || true
# Remove coverage files
find "$PACKAGE_DIR" -type f -name "*coverage*.pth" -delete 2>/dev/null || true

# Create deployment package
echo "Creating deployment package..."
cd "$PACKAGE_DIR"
zip -r "$PROJECT_ROOT/lambda-deployment.zip" . > /dev/null

echo "Build complete! Deployment package: $PROJECT_ROOT/lambda-deployment.zip"
echo "Package size: $(du -h "$PROJECT_ROOT/lambda-deployment.zip" | cut -f1)"
