# Scripts Documentation

This directory contains utility scripts for the project, including shared scripts used across multiple components.

## Overview

The scripts directory includes:
- **Shared Scripts** (`shared/`): Common utilities for building, deploying, and managing Lambda functions
- **Project Scripts**: Various utility scripts for database setup, connector management, test data generation, and more

## Shared Scripts

The `shared/` subdirectory contains shared scripts and utilities used across the project to reduce duplication and improve maintainability.

### Overview

The shared scripts provide common functionality for:
- Building Lambda functions
- Deploying Lambda functions
- Common shell functions
- Color output utilities

### Scripts

#### `shared/build-go-lambda.sh`

Shared build script for Go Lambda functions.

**Usage:**
```bash
./scripts/shared/build-go-lambda.sh <project-name> [--proto]
```

**Parameters:**
- `project-name`: Name of the Lambda project (e.g., `producer-api-go-grpc`)
- `--proto`: Optional flag to generate proto files before building

**Example:**
```bash
# Build without proto generation
./scripts/shared/build-go-lambda.sh producer-api-go-rest

# Build with proto generation
./scripts/shared/build-go-lambda.sh producer-api-go-grpc-lambda --proto
```

**What it does:**
1. Cleans the build directory
2. Optionally generates proto files (if `--proto` flag is provided)
3. Compiles Go binary for Linux (Lambda-compatible)
4. Copies migrations directory if it exists
5. Creates deployment package (zip file)

#### `shared/deploy-lambda.sh`

Shared deployment script for Lambda functions (both Go and Python).

**Usage:**
```bash
./scripts/shared/deploy-lambda.sh <project-name> [options]
```

**Parameters:**
- `project-name`: Name of the Lambda project
- Options: See below

**Options:**
- `--stack-name NAME`: CloudFormation stack name (defaults to project name)
- `--region REGION`: AWS region (defaults to `us-east-1`)
- `--s3-bucket BUCKET`: S3 bucket for deployment artifacts
- `--database-url URL`: Database connection URL
- `--aurora-endpoint ENDPOINT`: Aurora database endpoint
- `--database-name NAME`: Database name
- `--database-user USER`: Database username
- `--database-password PASSWORD`: Database password
- `--vpc-id VPC_ID`: VPC ID for Lambda
- `--subnet-ids SUBNET_IDS`: Comma-separated subnet IDs
- `--guided`: Use SAM guided deployment

**Example:**
```bash
# Deploy with guided mode
./scripts/shared/deploy-lambda.sh producer-api-go-rest-lambda --guided

# Deploy with specific parameters
./scripts/shared/deploy-lambda.sh producer-api-go-rest-lambda \
  --s3-bucket my-deployment-bucket \
  --aurora-endpoint my-aurora.cluster.amazonaws.com \
  --database-name car_entities \
  --database-user postgres \
  --database-password mypassword
```

**What it does:**
1. Detects project type (Go or Python) automatically
2. Builds the Lambda function
3. Deploys using AWS SAM CLI
4. Handles parameter passing for Go projects
5. Uses `--resolve-s3` for Python projects

#### `shared/common.sh`

Common shell functions library.

**Usage:**
```bash
source "$(dirname "$0")/../shared/common.sh"
```

**Available Functions:**
- `get_script_dir()`: Get the directory where the script is located
- `get_project_root()`: Get the project root directory
- `command_exists <cmd>`: Check if a command exists
- `is_numeric <value>`: Validate numeric input
- `is_valid_port <port>`: Validate port number (1-65535)
- `is_valid_host <host>`: Validate hostname/IP
- `check_connectivity <host> <port> [protocol]`: Check network connectivity
- `ensure_directory <dir>`: Create directory if it doesn't exist
- `get_timestamp()`: Get current timestamp
- `format_duration <seconds>`: Format duration as human-readable string
- `calculate_percentage <part> <total> [decimals]`: Calculate percentage
- `is_docker_environment()`: Check if running in Docker
- `show_script_header <name> [description]`: Show script header
- `show_script_footer <start_time>`: Show script footer
- `parse_args "$@"`: Parse command line arguments
- `require_command <cmd> [hint]`: Require command to be installed
- `require_file <file> [description]`: Require file to exist
- `require_directory <dir> [description]`: Require directory to exist

**Example:**
```bash
#!/bin/bash
source "$(dirname "$0")/../shared/common.sh"

# Use common functions
if ! command_exists docker; then
    echo "Error: Docker is required"
    exit 1
fi

SCRIPT_DIR=$(get_script_dir)
PROJECT_ROOT=$(get_project_root "$SCRIPT_DIR")
```

#### `shared/color-output.sh`

Color output utilities for consistent terminal output.

**Usage:**
```bash
source "$(dirname "$0")/../shared/color-output.sh"
```

**Available Functions:**
- `print_status <message>`: Print info message (blue)
- `print_success <message>`: Print success message (green)
- `print_warning <message>`: Print warning message (yellow)
- `print_error <message>`: Print error message (red)
- `print_debug <message>`: Print debug message (purple)
- `print_header <title>`: Print header (bold blue)
- `print_separator`: Print separator line
- `print_test_result <name> <status> <details>`: Print test result
- `print_progress <current> <total> <description>`: Print progress bar

**Color Variables:**
- `RED`, `GREEN`, `YELLOW`, `BLUE`, `PURPLE`, `CYAN`, `WHITE`, `NC` (no color)
- `BOLD_RED`, `BOLD_GREEN`, `BOLD_YELLOW`, `BOLD_BLUE`

**Example:**
```bash
#!/bin/bash
source "$(dirname "$0")/../shared/color-output.sh"

print_header "My Script"
print_status "Starting process..."
print_success "Operation completed"
print_error "Something went wrong"
```

## Other Scripts

This directory also contains various utility scripts:

- **Database Setup**: `setup-aurora-connection.sh`, `setup-postgres-access.sh`
- **Schema Initialization**: `init-aurora-schema.sh` (legacy - schema now managed by Terraform)
- **Connector Management**: `setup-connector.sh`, `deploy-aurora-connector.sh`, `troubleshoot-cdc-connector.sh`
- **Test Data Generation**: `generate-test-data.sh`, `generate-test-data-from-examples.sh`
- **Kafka/Topic Management**: `create-topics.sh`, `cleanup-confluent-cloud.sh`
- **Testing**: `send-sample-events-with-k6.sh`, `run-k6-docker-compose.sh`
- **Validation**: `validate-entity-structure.py`, `verify-messages.py`

## Migration Guide

### Updating Existing Scripts

If you have existing scripts that duplicate functionality, update them to use shared scripts:

**Before:**
```bash
#!/bin/bash
# ... 50 lines of build logic ...
```

**After:**
```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_SCRIPT="$PROJECT_ROOT/../scripts/shared/build-go-lambda.sh"
exec "$SHARED_SCRIPT" "producer-api-go-grpc"
```

### Benefits

1. **Reduced Duplication**: Single source of truth for common logic
2. **Easier Maintenance**: Fix bugs and improvements in one place
3. **Consistency**: All scripts use same patterns and error handling
4. **Smaller Codebase**: Eliminated ~500+ lines of duplicate code
5. **Better Testing**: Shared utilities easier to test

## Contributing

When adding new shared functionality:

1. Place shared scripts in `scripts/shared/` or appropriate subdirectory
2. Make scripts executable: `chmod +x script.sh`
3. Add comprehensive error handling
4. Use color-output.sh for consistent output
5. Document usage in this README
6. Update individual scripts to use shared utilities

## See Also

- [CDC Streaming Documentation](../cdc-streaming/README.md)
- [Load Test Documentation](../load-test/README.md)

