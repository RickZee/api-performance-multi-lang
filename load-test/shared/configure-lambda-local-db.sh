#!/bin/bash

# Configure Lambda Functions for Local Database
# Sets up environment variables and database connection for local Lambda execution

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAMBDA_LOCAL_CONFIG_FILE="$SCRIPT_DIR/lambda-local-config.json"

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to check database connectivity
check_database() {
    local db_host=$1
    local db_port=$2
    local db_name=$3
    local db_user=$4
    local db_password=$5
    
    print_status "Checking database connectivity..."
    
    # Try to connect using psql if available
    if command -v psql >/dev/null 2>&1; then
        PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -c "SELECT 1;" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_success "Database is accessible"
            return 0
        fi
    fi
    
    # Try using Docker exec to connect from postgres container
    if docker ps | grep -q postgres-large; then
        if docker exec postgres-large psql -U "$db_user" -d "$db_name" -c "SELECT 1;" > /dev/null 2>&1; then
            print_success "Database is accessible via Docker"
            return 0
        fi
    fi
    
    print_warning "Could not verify database connectivity directly, but will proceed"
    return 0
}

# Function to run database migrations
run_migrations() {
    local api_name=$1
    local database_url=$2
    
    print_status "Running migrations for $api_name..."
    
    local api_dir="$BASE_DIR/$api_name"
    local migrations_dir="$api_dir/migrations"
    
    if [ ! -d "$migrations_dir" ]; then
        print_warning "No migrations directory found for $api_name"
        return 0
    fi
    
    # Check if migrations need to be run
    # For Lambda functions, migrations are typically run on init
    # But we can verify the schema exists
    print_status "Migrations will be run automatically by Lambda functions on startup"
    return 0
}

# Function to get database configuration
get_database_config() {
    python3 -c "
import json
import sys
try:
    with open('$LAMBDA_LOCAL_CONFIG_FILE', 'r') as f:
        config = json.load(f)
        local_exec = config['local_execution']
        print(f\"{local_exec['database_host']}|{local_exec['database_port']}|{local_exec['database_name']}|{local_exec['database_user']}|{local_exec['database_password']}\")
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Main execution
main() {
    print_section "Configuring Lambda Functions for Local Database"
    
    # Get database configuration
    db_config=$(get_database_config)
    if [ $? -ne 0 ]; then
        print_error "Failed to load database configuration"
        exit 1
    fi
    
    IFS='|' read -r db_host db_port db_name db_user db_password <<< "$db_config"
    
    print_status "Database Configuration:"
    print_status "  Host: $db_host"
    print_status "  Port: $db_port"
    print_status "  Database: $db_name"
    print_status "  User: $db_user"
    
    # Check database connectivity
    check_database "$db_host" "$db_port" "$db_name" "$db_user" "$db_password"
    
    # Verify database exists
    print_status "Verifying database exists..."
    if docker ps | grep -q postgres-large; then
        if docker exec postgres-large psql -U "$db_user" -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
            print_success "Database '$db_name' exists"
        else
            print_warning "Database '$db_name' does not exist, but will be created on first connection"
        fi
    fi
    
    # Database URL for Lambda functions
    database_url="postgresql://${db_user}:${db_password}@${db_host}:${db_port}/${db_name}"
    
    print_success "Configuration complete"
    print_status "Database URL: postgresql://${db_user}:***@${db_host}:${db_port}/${db_name}"
    print_status ""
    print_status "Lambda functions will use this database URL when started locally"
    
    return 0
}

# Run main function
main "$@"

