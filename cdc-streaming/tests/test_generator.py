#!/usr/bin/env python3
"""
Unit tests for Flink SQL code generator.
"""

import unittest
import tempfile
import shutil
from pathlib import Path
import sys

# Add parent directory to path to import generator
script_dir = Path(__file__).parent.parent
sys.path.insert(0, str(script_dir))

# Import generator module
import importlib.util
spec = importlib.util.spec_from_file_location(
    "generate_flink_sql",
    script_dir / "scripts" / "generate-flink-sql.py"
)
generate_flink_sql = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generate_flink_sql)

SQLGenerator = generate_flink_sql.SQLGenerator
FilterConfigError = generate_flink_sql.FilterConfigError


class TestSQLGenerator(unittest.TestCase):
    """Test cases for SQLGenerator class."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.test_dir = Path(tempfile.mkdtemp())
        self.template_dir = self.test_dir / 'templates'
        self.template_dir.mkdir()
        
        # Create a simple test template
        template_content = """-- Test Template
CREATE TABLE raw_business_events (
    `eventHeader` ROW<`eventName` STRING>
) WITH ('connector' = 'kafka');

{% for filter in filters %}
INSERT INTO {{ filter.outputTopic|replace('-', '_') }}
SELECT `eventHeader`
FROM raw_business_events
WHERE {{ generator.generate_where_clause(filter) }};
{% endfor %}
"""
        (self.template_dir / 'routing.sql.j2').write_text(template_content)
        
        self.generator = SQLGenerator(
            template_dir=str(self.template_dir),
            schema_path=None  # Skip validation for unit tests
        )
    
    def tearDown(self):
        """Clean up test fixtures."""
        shutil.rmtree(self.test_dir)
    
    def test_translate_field_path_simple(self):
        """Test simple field path translation."""
        result = self.generator.translate_field_path("eventHeader.eventName")
        self.assertEqual(result, "`eventHeader`.`eventName`")
    
    def test_translate_field_path_with_array(self):
        """Test field path with array index."""
        result = self.generator.translate_field_path("eventBody.entities[0].entityType")
        self.assertEqual(result, "`eventBody`.`entities`[1].`entityType`")
    
    def test_translate_map_access(self):
        """Test map access translation."""
        result = self.generator.translate_map_access(
            "eventBody.entities[0].updatedAttributes.loan.loanAmount"
        )
        self.assertIn("`updatedAttributes`", result)
        self.assertIn("['loan.loanAmount']", result)
    
    def test_generate_condition_equals(self):
        """Test equals condition generation."""
        condition = {
            'field': 'eventHeader.eventName',
            'operator': 'equals',
            'value': 'LoanCreated',
            'valueType': 'string'
        }
        result = self.generator.generate_condition(condition, is_first=True)
        self.assertIn("=", result)
        self.assertIn("LoanCreated", result)
    
    def test_generate_condition_in(self):
        """Test IN condition generation."""
        condition = {
            'field': 'eventHeader.eventName',
            'operator': 'in',
            'values': ['LoanCreated', 'LoanPaymentSubmitted'],
            'valueType': 'string'
        }
        result = self.generator.generate_condition(condition, is_first=True)
        self.assertIn("IN", result)
        self.assertIn("LoanCreated", result)
        self.assertIn("LoanPaymentSubmitted", result)
    
    def test_generate_condition_greater_than(self):
        """Test greaterThan condition generation."""
        condition = {
            'field': 'eventBody.entities[0].updatedAttributes.loan.loanAmount',
            'operator': 'greaterThan',
            'value': 50000,
            'valueType': 'number'
        }
        result = self.generator.generate_condition(condition, is_first=True)
        self.assertIn(">", result)
        self.assertIn("50000", result)
    
    def test_generate_where_clause_single(self):
        """Test WHERE clause generation with single condition."""
        filter_config = {
            'conditions': [
                {
                    'field': 'eventHeader.eventName',
                    'operator': 'equals',
                    'value': 'LoanCreated',
                    'valueType': 'string'
                }
            ]
        }
        result = self.generator.generate_where_clause(filter_config)
        self.assertIn("eventHeader", result)
        self.assertIn("LoanCreated", result)
    
    def test_generate_where_clause_multiple(self):
        """Test WHERE clause generation with multiple conditions."""
        filter_config = {
            'conditions': [
                {
                    'field': 'eventHeader.eventName',
                    'operator': 'equals',
                    'value': 'LoanCreated',
                    'valueType': 'string'
                },
                {
                    'field': 'eventBody.entities[0].entityType',
                    'operator': 'equals',
                    'value': 'Loan',
                    'valueType': 'string'
                }
            ],
            'conditionLogic': 'AND'
        }
        result = self.generator.generate_where_clause(filter_config)
        self.assertIn("AND", result)
        self.assertIn("LoanCreated", result)
        self.assertIn("Loan", result)
    
    def test_generate_where_clause_or_logic(self):
        """Test WHERE clause with OR logic."""
        filter_config = {
            'conditions': [
                {
                    'field': 'eventHeader.eventName',
                    'operator': 'equals',
                    'value': 'LoanCreated',
                    'valueType': 'string',
                    'logicalOperator': 'OR'
                },
                {
                    'field': 'eventHeader.eventName',
                    'operator': 'equals',
                    'value': 'LoanPaymentSubmitted',
                    'valueType': 'string'
                }
            ],
            'conditionLogic': 'OR'
        }
        result = self.generator.generate_where_clause(filter_config)
        # Should have OR between conditions
        self.assertIn("OR", result)


class TestIntegration(unittest.TestCase):
    """Integration tests for full SQL generation."""
    
    def setUp(self):
        """Set up test fixtures."""
        script_dir = Path(__file__).parent.parent
        self.template_dir = script_dir / 'scripts' / 'templates'
        self.schema_path = script_dir / 'schemas' / 'filter-schema.json'
        self.test_fixtures = script_dir / 'tests' / 'test_fixtures'
        
        self.generator = SQLGenerator(
            template_dir=str(self.template_dir),
            schema_path=str(self.schema_path) if self.schema_path.exists() else None
        )
    
    def test_generate_from_sample_filters(self):
        """Test generating SQL from sample filter configuration."""
        config_path = self.test_fixtures / 'sample-filters.yaml'
        if not config_path.exists():
            self.skipTest("Sample filters file not found")
        
        output_path = self.test_fixtures / 'test-output.sql'
        
        try:
            self.generator.generate_sql(
                config_path=str(config_path),
                output_path=str(output_path),
                kafka_bootstrap='test-kafka:9092',
                schema_registry_url='http://test-schema:8081'
            )
            
            # Verify output file was created
            self.assertTrue(output_path.exists())
            
            # Verify content
            content = output_path.read_text()
            self.assertIn("CREATE TABLE", content)
            self.assertIn("INSERT INTO", content)
            # Should have 3 enabled filters
            self.assertEqual(content.count("INSERT INTO"), 3)
            # Should not have disabled filter
            self.assertNotIn("test-filtered-disabled", content)
            
        finally:
            # Clean up
            if output_path.exists():
                output_path.unlink()


if __name__ == '__main__':
    unittest.main()

