#!/usr/bin/env python3
"""
Unit tests for generate-filters.py script.
Tests filter generation with various status values and edge cases.
"""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, mock_open
import sys

# Add the scripts directory to path to import generate-filters
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

# Import the generator module
import generate_filters


class TestGenerateFilters(unittest.TestCase):

    def setUp(self):
        """Set up test fixtures."""
        self.test_filters = {
            "version": 1,
            "filters": [
                {
                    "id": "active-filter",
                    "name": "Active Filter",
                    "description": "Active filter",
                    "consumerId": "active-consumer",
                    "outputTopic": "filtered-active-events",
                    "enabled": True,
                    "status": "active",
                    "conditions": [
                        {
                            "field": "event_type",
                            "operator": "equals",
                            "value": "CarCreated",
                            "valueType": "string"
                        }
                    ],
                    "conditionLogic": "AND",
                    "version": 1
                },
                {
                    "id": "deprecated-filter",
                    "name": "Deprecated Filter",
                    "description": "Deprecated filter",
                    "consumerId": "deprecated-consumer",
                    "outputTopic": "filtered-deprecated-events",
                    "enabled": True,
                    "status": "deprecated",
                    "conditions": [
                        {
                            "field": "event_type",
                            "operator": "equals",
                            "value": "LoanCreated",
                            "valueType": "string"
                        }
                    ],
                    "conditionLogic": "AND",
                    "version": 1
                },
                {
                    "id": "deleted-filter",
                    "name": "Deleted Filter",
                    "description": "Deleted filter",
                    "consumerId": "deleted-consumer",
                    "outputTopic": "filtered-deleted-events",
                    "enabled": True,
                    "status": "deleted",
                    "conditions": [
                        {
                            "field": "event_type",
                            "operator": "equals",
                            "value": "ServiceDone",
                            "valueType": "string"
                        }
                    ],
                    "conditionLogic": "AND",
                    "version": 1
                },
                {
                    "id": "disabled-filter",
                    "name": "Disabled Filter",
                    "description": "Disabled filter",
                    "consumerId": "disabled-consumer",
                    "outputTopic": "filtered-disabled-events",
                    "enabled": False,
                    "status": "active",
                    "conditions": [
                        {
                            "field": "event_type",
                            "operator": "equals",
                            "value": "PaymentSubmitted",
                            "valueType": "string"
                        }
                    ],
                    "conditionLogic": "AND",
                    "version": 1
                },
                {
                    "id": "pending-deletion-filter",
                    "name": "Pending Deletion Filter",
                    "description": "Pending deletion filter",
                    "consumerId": "pending-consumer",
                    "outputTopic": "filtered-pending-events",
                    "enabled": True,
                    "status": "pending_deletion",
                    "conditions": [
                        {
                            "field": "event_type",
                            "operator": "equals",
                            "value": "TestEvent",
                            "valueType": "string"
                        }
                    ],
                    "conditionLogic": "AND",
                    "version": 1
                }
            ]
        }

    def test_deleted_filter_is_skipped(self):
        """Test that filters with status 'deleted' are excluded from generation."""
        filters = self.test_filters["filters"]
        deleted_filter = next(f for f in filters if f["status"] == "deleted")
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify deleted filter is not in output
        self.assertNotIn(deleted_filter["id"], sql_output)
        self.assertNotIn(deleted_filter["outputTopic"], sql_output)

    def test_disabled_filter_is_skipped(self):
        """Test that filters with enabled=False are excluded from generation."""
        filters = self.test_filters["filters"]
        disabled_filter = next(f for f in filters if not f.get("enabled", True))
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify disabled filter is not in output
        self.assertNotIn(disabled_filter["id"], sql_output)
        self.assertNotIn(disabled_filter["outputTopic"], sql_output)

    def test_pending_deletion_filter_is_skipped(self):
        """Test that filters with status 'pending_deletion' are excluded."""
        filters = self.test_filters["filters"]
        pending_filter = next(f for f in filters if f["status"] == "pending_deletion")
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify pending deletion filter is not in output
        self.assertNotIn(pending_filter["id"], sql_output)
        self.assertNotIn(pending_filter["outputTopic"], sql_output)

    def test_deprecated_filter_generates_warning(self):
        """Test that deprecated filters generate warnings but are included."""
        filters = self.test_filters["filters"]
        deprecated_filter = next(f for f in filters if f["status"] == "deprecated")
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify deprecated filter is included
        self.assertIn(deprecated_filter["id"], sql_output)
        self.assertIn(deprecated_filter["outputTopic"], sql_output)
        
        # Verify warning is present
        self.assertIn("WARNING", sql_output)
        self.assertIn("deprecated", sql_output.lower())
        self.assertIn(deprecated_filter["id"], sql_output)

    def test_active_filter_is_included(self):
        """Test that active filters are included in generation."""
        filters = self.test_filters["filters"]
        active_filter = next(f for f in filters if f["status"] == "active")
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify active filter is included
        self.assertIn(active_filter["id"], sql_output)
        self.assertIn(active_filter["outputTopic"], sql_output)

    def test_spring_yaml_deleted_filter_is_skipped(self):
        """Test that deleted filters are excluded from Spring YAML generation."""
        filters = self.test_filters["filters"]
        deleted_filter = next(f for f in filters if f["status"] == "deleted")
        
        # Generate YAML
        yaml_output = generate_filters.generate_spring_yaml(filters)
        
        # Verify deleted filter is not in output
        self.assertNotIn(deleted_filter["id"], yaml_output)
        self.assertNotIn(deleted_filter["outputTopic"], yaml_output)

    def test_spring_yaml_disabled_filter_is_skipped(self):
        """Test that disabled filters are excluded from Spring YAML generation."""
        filters = self.test_filters["filters"]
        disabled_filter = next(f for f in filters if not f.get("enabled", True))
        
        # Generate YAML
        yaml_output = generate_filters.generate_spring_yaml(filters)
        
        # Verify disabled filter is not in output
        self.assertNotIn(disabled_filter["id"], yaml_output)
        self.assertNotIn(disabled_filter["outputTopic"], yaml_output)

    def test_spring_yaml_deprecated_filter_generates_warning(self):
        """Test that deprecated filters generate warnings in Spring YAML."""
        filters = self.test_filters["filters"]
        deprecated_filter = next(f for f in filters if f["status"] == "deprecated")
        
        # Generate YAML
        yaml_output = generate_filters.generate_spring_yaml(filters)
        
        # Verify deprecated filter is included
        self.assertIn(deprecated_filter["id"], yaml_output)
        
        # Verify warning is present
        self.assertIn("WARNING", yaml_output)
        self.assertIn("deprecated", yaml_output.lower())

    def test_empty_filters_array(self):
        """Test handling of empty filters array."""
        filters = []
        
        # Should not raise exception
        sql_output = generate_filters.generate_flink_sql(filters)
        yaml_output = generate_filters.generate_spring_yaml(filters)
        
        # Output should still be valid (just headers)
        self.assertIsInstance(sql_output, str)
        self.assertIsInstance(yaml_output, str)

    def test_filter_without_status(self):
        """Test that filters without status field default to enabled."""
        filters = [
            {
                "id": "no-status-filter",
                "name": "No Status Filter",
                "consumerId": "test-consumer",
                "outputTopic": "filtered-no-status-events",
                "enabled": True,
                "conditions": [
                    {
                        "field": "event_type",
                        "operator": "equals",
                        "value": "TestEvent"
                    }
                ],
                "conditionLogic": "AND"
            }
        ]
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify filter is included (default behavior)
        self.assertIn("no-status-filter", sql_output)
        self.assertIn("filtered-no-status-events", sql_output)

    def test_filter_without_enabled_field(self):
        """Test that filters without enabled field default to enabled."""
        filters = [
            {
                "id": "no-enabled-filter",
                "name": "No Enabled Filter",
                "consumerId": "test-consumer",
                "outputTopic": "filtered-no-enabled-events",
                "status": "active",
                "conditions": [
                    {
                        "field": "event_type",
                        "operator": "equals",
                        "value": "TestEvent"
                    }
                ],
                "conditionLogic": "AND"
            }
        ]
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify filter is included (default enabled=True)
        self.assertIn("no-enabled-filter", sql_output)

    def test_multiple_deprecated_filters_generate_warnings(self):
        """Test that multiple deprecated filters all generate warnings."""
        filters = [
            {
                "id": "deprecated-1",
                "name": "Deprecated 1",
                "consumerId": "test-consumer",
                "outputTopic": "filtered-deprecated-1",
                "enabled": True,
                "status": "deprecated",
                "conditions": [{"field": "event_type", "operator": "equals", "value": "Test"}],
                "conditionLogic": "AND"
            },
            {
                "id": "deprecated-2",
                "name": "Deprecated 2",
                "consumerId": "test-consumer",
                "outputTopic": "filtered-deprecated-2",
                "enabled": True,
                "status": "deprecated",
                "conditions": [{"field": "event_type", "operator": "equals", "value": "Test"}],
                "conditionLogic": "AND"
            }
        ]
        
        # Generate SQL
        sql_output = generate_filters.generate_flink_sql(filters)
        
        # Verify both deprecated filters are in warning
        self.assertIn("deprecated-1", sql_output)
        self.assertIn("deprecated-2", sql_output)
        self.assertIn("WARNING", sql_output)


if __name__ == "__main__":
    unittest.main()

