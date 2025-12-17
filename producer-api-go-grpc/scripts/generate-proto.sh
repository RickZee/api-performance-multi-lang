#!/bin/bash

set -e

# Directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Proto file location
PROTO_FILE="$PROJECT_ROOT/proto/event_service.proto"

# Output directory for generated Go code
OUTPUT_DIR="$PROJECT_ROOT/proto"

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc is not installed. Please install Protocol Buffers compiler."
    echo "On macOS: brew install protobuf"
    echo "On Ubuntu: sudo apt-get install protobuf-compiler"
    exit 1
fi

# Check if protoc-gen-go is installed
if ! command -v protoc-gen-go &> /dev/null; then
    echo "Installing protoc-gen-go..."
    go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0
fi

# Check if protoc-gen-go-grpc is installed
if ! command -v protoc-gen-go-grpc &> /dev/null; then
    echo "Installing protoc-gen-go-grpc..."
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0
fi

# Generate Go code
echo "Generating Go code from $PROTO_FILE..."
protoc \
    --proto_path="$PROJECT_ROOT/proto" \
    --go_out="$OUTPUT_DIR" \
    --go_opt=paths=source_relative \
    --go-grpc_out="$OUTPUT_DIR" \
    --go-grpc_opt=paths=source_relative \
    "$PROTO_FILE"

echo "Proto code generation completed successfully!"
echo "Generated files are in: $OUTPUT_DIR"
