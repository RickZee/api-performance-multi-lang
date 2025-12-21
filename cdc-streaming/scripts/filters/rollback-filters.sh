#!/bin/bash
# Rollback filter configuration to a previous version

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

FILTERS_CONFIG="$PROJECT_ROOT/cdc-streaming/config/filters.json"
FILTER_HISTORY_DIR="$PROJECT_ROOT/cdc-streaming/config/filter-history"
BACKUP_DIR="$FILTER_HISTORY_DIR/backups"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Rollback Filter Configuration${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Check if filters.json exists
if [ ! -f "$FILTERS_CONFIG" ]; then
    echo -e "${RED}✗ Filters config not found: $FILTERS_CONFIG${NC}"
    exit 1
fi

# Function to create backup
create_backup() {
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="$BACKUP_DIR/filters-${timestamp}.json"
    cp "$FILTERS_CONFIG" "$backup_file"
    echo -e "${GREEN}✓${NC} Backup created: $backup_file"
    echo "$backup_file"
}

# Function to list available backups
list_backups() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}⚠${NC} No backups found in $BACKUP_DIR"
        return 1
    fi
    
    echo -e "${BLUE}Available backups:${NC}"
    ls -1t "$BACKUP_DIR"/*.json 2>/dev/null | while read -r backup; do
        filename=$(basename "$backup")
        timestamp=$(echo "$filename" | sed 's/filters-\(.*\)\.json/\1/')
        size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
        echo "  - $filename ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "${size} bytes"))"
    done
    return 0
}

# Check if git is available
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${BLUE}Option 1: Rollback using Git${NC}"
    echo ""
    
    # Show recent commits that modified filters.json
    echo -e "${BLUE}Recent commits affecting filters.json:${NC}"
    git log --oneline -10 -- "$FILTERS_CONFIG" 2>/dev/null || echo "  (no git history found)"
    echo ""
    
    read -p "Rollback to a specific git commit? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter commit hash (or 'HEAD~1' for previous commit): " COMMIT_HASH
        if [ -n "$COMMIT_HASH" ]; then
            # Create backup before rollback
            create_backup > /dev/null
            
            # Checkout the file from the specified commit
            if git show "${COMMIT_HASH}:cdc-streaming/config/filters.json" > "$FILTERS_CONFIG.tmp" 2>/dev/null; then
                mv "$FILTERS_CONFIG.tmp" "$FILTERS_CONFIG"
                echo -e "${GREEN}✓${NC} Rolled back to commit: $COMMIT_HASH"
                echo ""
                echo -e "${CYAN}Next steps:${NC}"
                echo "  1. Review the rolled back configuration"
                echo "  2. Regenerate filters: ./scripts/filters/generate-filters.sh"
                echo "  3. Redeploy: ./scripts/filters/deploy-flink-filters.sh and ./scripts/filters/deploy-spring-filters.sh"
                exit 0
            else
                echo -e "${RED}✗${NC} Failed to retrieve filters.json from commit: $COMMIT_HASH"
                exit 1
            fi
        fi
    fi
fi

# Option 2: Rollback from backup files
echo -e "${BLUE}Option 2: Rollback from backup files${NC}"
echo ""

# Create backup of current config before rollback
CURRENT_BACKUP=$(create_backup)
echo ""

# List available backups
if list_backups; then
    echo ""
    read -p "Enter backup filename to restore (or 'cancel' to abort): " BACKUP_FILE
    
    if [ "$BACKUP_FILE" = "cancel" ] || [ -z "$BACKUP_FILE" ]; then
        echo -e "${YELLOW}Rollback cancelled${NC}"
        exit 0
    fi
    
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILE"
    if [ ! -f "$BACKUP_PATH" ]; then
        # Try without .json extension
        BACKUP_PATH="$BACKUP_DIR/${BACKUP_FILE}.json"
    fi
    
    if [ -f "$BACKUP_PATH" ]; then
        cp "$BACKUP_PATH" "$FILTERS_CONFIG"
        echo -e "${GREEN}✓${NC} Rolled back to: $BACKUP_FILE"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Review the rolled back configuration"
        echo "  2. Regenerate filters: ./scripts/filters/generate-filters.sh"
        echo "  3. Redeploy: ./scripts/filters/deploy-flink-filters.sh and ./scripts/filters/deploy-spring-filters.sh"
    else
        echo -e "${RED}✗${NC} Backup file not found: $BACKUP_FILE"
        exit 1
    fi
else
    echo ""
    echo -e "${YELLOW}⚠${NC} No backup files available"
    echo -e "${BLUE}ℹ${NC} Backups are created automatically before deployments"
    echo -e "${BLUE}ℹ${NC} You can also use git to rollback if the file is version controlled"
fi

echo ""

