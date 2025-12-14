#!/usr/bin/env python3
"""
Migration script to move filters from separate files into event.json schema.

This script:
1. Reads all filter files from schemas/v1/filters/
2. Reads or creates event.json in schemas/v1/event/
3. Adds filters array to event.json
4. Optionally backs up the old filters directory
"""

import json
import os
import shutil
import sys
from pathlib import Path
from datetime import datetime

def main():
    # Base directory - adjust if needed
    base_dir = Path(__file__).parent.parent
    data_dir = base_dir / "data"
    
    version = "v1"
    filters_dir = data_dir / "schemas" / version / "filters"
    event_dir = data_dir / "schemas" / version / "event"
    event_json_path = event_dir / "event.json"
    
    # Base event schema (if v1/event doesn't exist, copy from base)
    base_event_schema = data_dir / "schemas" / "event" / "event.json"
    
    print(f"Migrating filters for version: {version}")
    print(f"Filters directory: {filters_dir}")
    print(f"Event JSON path: {event_json_path}")
    
    # Check if filters directory exists
    if not filters_dir.exists():
        print(f"Filters directory not found: {filters_dir}")
        print("No filters to migrate.")
        return 0
    
    # Get all filter files
    filter_files = list(filters_dir.glob("*.json"))
    if not filter_files:
        print("No filter files found to migrate.")
        return 0
    
    print(f"Found {len(filter_files)} filter files to migrate")
    
    # Read all filters
    filters = []
    for filter_file in filter_files:
        try:
            with open(filter_file, 'r') as f:
                filter_data = json.load(f)
                filters.append(filter_data)
                print(f"  - Loaded: {filter_file.name}")
        except Exception as e:
            print(f"  - ERROR loading {filter_file.name}: {e}")
            continue
    
    if not filters:
        print("No valid filters to migrate.")
        return 1
    
    # Ensure event directory exists
    event_dir.mkdir(parents=True, exist_ok=True)
    
    # Read or create event.json
    if event_json_path.exists():
        print(f"Reading existing event.json: {event_json_path}")
        with open(event_json_path, 'r') as f:
            event_schema = json.load(f)
    elif base_event_schema.exists():
        print(f"Copying base event schema from: {base_event_schema}")
        with open(base_event_schema, 'r') as f:
            event_schema = json.load(f)
    else:
        print("ERROR: No event schema found to use as base")
        return 1
    
    # Check if filters already exist in event.json
    existing_filters = event_schema.get("filters", [])
    if existing_filters:
        print(f"WARNING: event.json already contains {len(existing_filters)} filters")
        response = input("Do you want to merge with existing filters? (y/n): ")
        if response.lower() != 'y':
            print("Migration cancelled.")
            return 0
        
        # Merge filters (avoid duplicates by ID)
        existing_ids = {f.get("id") for f in existing_filters if isinstance(f, dict) and "id" in f}
        for filter_data in filters:
            filter_id = filter_data.get("id")
            if filter_id and filter_id not in existing_ids:
                existing_filters.append(filter_data)
                existing_ids.add(filter_id)
        filters = existing_filters
    
    # Add filters to event schema
    event_schema["filters"] = filters
    
    # Write updated event.json
    print(f"\nWriting updated event.json: {event_json_path}")
    with open(event_json_path, 'w') as f:
        json.dump(event_schema, f, indent=2)
    
    print(f"Successfully migrated {len(filters)} filters to event.json")
    
    # Backup old filters directory
    backup_dir = filters_dir.parent / f"filters.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    if filters_dir.exists():
        response = input(f"\nBackup old filters directory to {backup_dir.name}? (y/n): ")
        if response.lower() == 'y':
            shutil.move(str(filters_dir), str(backup_dir))
            print(f"Backed up to: {backup_dir}")
        else:
            print("Old filters directory kept (not backed up)")
    
    print("\nMigration completed successfully!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
