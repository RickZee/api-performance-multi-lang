#!/bin/bash
# Shared Flink statement management script
# Usage: flink-manager.sh <action> [options]

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/shared/color-output.sh" 2>/dev/null || true

ACTION="${1:-}"

if [ -z "$ACTION" ]; then
    print_error "Action is required"
    echo "Usage: $0 <action> [options]"
    echo ""
    echo "Actions:"
    echo "  cleanup              - Remove COMPLETED and FAILED statements"
    echo "  delete-failed        - Delete FAILED and COMPLETED statements (with confirmation)"
    echo "  list                 - List all statements"
    echo "  status <name>        - Get status of a specific statement"
    echo "  delete <name>        - Delete a specific statement"
    exit 1
fi

COMPUTE_POOL_ID="${FLINK_COMPUTE_POOL_ID:-lfcp-2xqo0m}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-lkc-rno3vp}"

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    print_error "Confluent CLI is not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed"
    exit 1
fi

# List all statements
list_statements() {
    local status_filter="${1:-}"
    local statements_json=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null || echo "[]")
    
    if [ -z "$statements_json" ] || [ "$statements_json" = "[]" ]; then
        print_warning "No Flink statements found"
        return 0
    fi
    
    if [ -n "$status_filter" ]; then
        echo "$statements_json" | jq -r ".[] | select(.status == \"$status_filter\") | \"\(.name): \(.status)\""
    else
        echo "$statements_json" | jq -r '.[] | "\(.name): \(.status)"'
    fi
}

# Delete statements by status
delete_by_status() {
    local statuses=("$@")
    local force="${FORCE:-false}"
    
    print_header "Delete Flink Statements"
    print_status "Compute Pool: $COMPUTE_POOL_ID"
    echo ""
    
    local statements_json=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null || echo "[]")
    
    if [ -z "$statements_json" ] || [ "$statements_json" = "[]" ]; then
        print_warning "No Flink statements found"
        return 0
    fi
    
    # Build jq filter for statuses
    local status_filter=""
    for status in "${statuses[@]}"; do
        if [ -z "$status_filter" ]; then
            status_filter=".status == \"$status\""
        else
            status_filter="$status_filter or .status == \"$status\""
        fi
    done
    
    local statements_to_delete=$(echo "$statements_json" | jq -r ".[] | select($status_filter) | \"\(.name)|\(.status)\"" || echo "")
    
    if [ -z "$statements_to_delete" ]; then
        print_success "No statements with status ${statuses[*]} found"
        return 0
    fi
    
    local count=$(echo "$statements_to_delete" | wc -l | tr -d ' ')
    print_warning "Found $count statement(s) to delete:"
    echo ""
    
    # Display statements to be deleted
    echo "$statements_to_delete" | while IFS='|' read -r name status; do
        if [ "$status" = "FAILED" ]; then
            echo -e "  ${RED}✗ $name${NC} (FAILED)"
        elif [ "$status" = "COMPLETED" ]; then
            echo -e "  ${YELLOW}○ $name${NC} (COMPLETED)"
        else
            echo -e "  ${BLUE}• $name${NC} ($status)"
        fi
    done
    
    echo ""
    
    if [ "$force" != "true" ]; then
        read -p "Delete these statements? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cancelled."
            return 0
        fi
    fi
    
    # Delete statements
    print_status "Deleting statements..."
    local deleted=0
    local failed=0
    
    while IFS='|' read -r name status; do
        if [ -n "$name" ]; then
            echo -n "  Deleting $name... "
            if confluent flink statement delete "$name" --force 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
                deleted=$((deleted + 1))
            else
                echo -e "${RED}✗${NC}"
                failed=$((failed + 1))
            fi
            sleep 1
        fi
    done <<< "$statements_to_delete"
    
    echo ""
    print_success "Deleted $deleted statement(s)"
    if [ $failed -gt 0 ]; then
        print_warning "Failed to delete $failed statement(s)"
    fi
    
    # Show remaining statements
    echo ""
    print_status "Remaining statements:"
    list_statements
    echo ""
}

# Main action handler
case "$ACTION" in
    cleanup)
        # Quick cleanup without confirmation
        FORCE=true delete_by_status "COMPLETED" "FAILED"
        ;;
    
    delete-failed)
        # Delete with confirmation
        delete_by_status "FAILED" "COMPLETED"
        ;;
    
    list)
        print_header "Flink Statements"
        print_status "Compute Pool: $COMPUTE_POOL_ID"
        echo ""
        list_statements
        echo ""
        ;;
    
    status)
        local statement_name="$2"
        if [ -z "$statement_name" ]; then
            print_error "Statement name is required"
            echo "Usage: $0 status <statement-name>"
            exit 1
        fi
        
        local statements_json=$(confluent flink statement list --compute-pool "$COMPUTE_POOL_ID" --output json 2>/dev/null || echo "[]")
        local statement_info=$(echo "$statements_json" | jq -r ".[] | select(.name == \"$statement_name\")" || echo "")
        
        if [ -z "$statement_info" ]; then
            print_error "Statement not found: $statement_name"
            exit 1
        fi
        
        echo "$statement_info" | jq '.'
        ;;
    
    delete)
        local statement_name="$2"
        if [ -z "$statement_name" ]; then
            print_error "Statement name is required"
            echo "Usage: $0 delete <statement-name>"
            exit 1
        fi
        
        print_status "Deleting statement: $statement_name"
        if confluent flink statement delete "$statement_name" --force 2>/dev/null; then
            print_success "Statement deleted: $statement_name"
        else
            print_error "Failed to delete statement: $statement_name"
            exit 1
        fi
        ;;
    
    *)
        print_error "Unknown action: $ACTION"
        echo "Use: cleanup, delete-failed, list, status, or delete"
        exit 1
        ;;
esac
