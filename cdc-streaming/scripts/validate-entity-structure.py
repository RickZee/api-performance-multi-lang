#!/usr/bin/env python3
"""
Validate Entity Structure Script
Validates generated events against schemas in data/schemas/
Ensures car entities match data/schemas/entity/car.json
Ensures loan created events match data/schemas/event/samples/loan-created-event.json
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, Any, List, Optional

try:
    import jsonschema
    from jsonschema import validate, ValidationError
except ImportError:
    print("Error: jsonschema is required. Install with: pip install jsonschema")
    sys.exit(1)


class EntityValidator:
    """Validates entity structures against JSON schemas."""
    
    def __init__(self, data_dir: Path):
        """Initialize the validator.
        
        Args:
            data_dir: Path to the data directory containing schemas
        """
        self.data_dir = Path(data_dir)
        self.schemas_dir = self.data_dir / "schemas"
        self.entities_dir = self.data_dir / "entities"
        self.samples_dir = self.schemas_dir / "event" / "samples"
        
        # Load schemas
        self.car_schema = self._load_schema("entity/car.json")
        self.loan_schema = self._load_schema("entity/loan.json")
        self.event_schema = self._load_schema("event/event.json")
        self.entity_header_schema = self._load_schema("entity/entity-header.json")
        self.event_header_schema = self._load_schema("event/event-header.json")
        
        # Load example files
        self.car_large_example = self._load_json("entities/car/car-large.json")
        self.loan_created_example = self._load_json("schemas/event/samples/loan-created-event.json")
    
    def _load_schema(self, schema_path: str) -> Dict[str, Any]:
        """Load a JSON schema file.
        
        Args:
            schema_path: Relative path to schema from data_dir
            
        Returns:
            Parsed JSON schema
        """
        full_path = self.data_dir / schema_path
        if not full_path.exists():
            raise FileNotFoundError(f"Schema not found: {full_path}")
        
        with open(full_path, 'r') as f:
            return json.load(f)
    
    def _load_json(self, json_path: str) -> Dict[str, Any]:
        """Load a JSON file.
        
        Args:
            json_path: Relative path to JSON file from data_dir
            
        Returns:
            Parsed JSON data
        """
        full_path = self.data_dir / json_path
        if not full_path.exists():
            raise FileNotFoundError(f"JSON file not found: {full_path}")
        
        with open(full_path, 'r') as f:
            return json.load(f)
    
    def validate_car_entity(self, car_entity: Dict[str, Any]) -> List[str]:
        """Validate a car entity against the car schema.
        
        Args:
            car_entity: Car entity to validate
            
        Returns:
            List of validation errors (empty if valid)
        """
        errors = []
        
        try:
            # Resolve schema references manually for car schema
            resolver = jsonschema.RefResolver(
                base_uri=f"file://{self.schemas_dir}/entity/",
                referrer=self.car_schema
            )
            validate(instance=car_entity, schema=self.car_schema, resolver=resolver)
        except ValidationError as e:
            errors.append(f"Car entity validation error: {e.message}")
            if e.path:
                errors.append(f"  Path: {'/'.join(str(p) for p in e.path)}")
        except Exception as e:
            errors.append(f"Unexpected error validating car entity: {str(e)}")
        
        return errors
    
    def validate_loan_entity(self, loan_entity: Dict[str, Any]) -> List[str]:
        """Validate a loan entity against the loan schema.
        
        Args:
            loan_entity: Loan entity to validate
            
        Returns:
            List of validation errors (empty if valid)
        """
        errors = []
        
        try:
            resolver = jsonschema.RefResolver(
                base_uri=f"file://{self.schemas_dir}/entity/",
                referrer=self.loan_schema
            )
            validate(instance=loan_entity, schema=self.loan_schema, resolver=resolver)
        except ValidationError as e:
            errors.append(f"Loan entity validation error: {e.message}")
            if e.path:
                errors.append(f"  Path: {'/'.join(str(p) for p in e.path)}")
        except Exception as e:
            errors.append(f"Unexpected error validating loan entity: {str(e)}")
        
        return errors
    
    def validate_event(self, event: Dict[str, Any]) -> List[str]:
        """Validate an event against the event schema.
        
        Args:
            event: Event to validate
            
        Returns:
            List of validation errors (empty if valid)
        """
        errors = []
        
        try:
            resolver = jsonschema.RefResolver(
                base_uri=f"file://{self.schemas_dir}/",
                referrer=self.event_schema
            )
            validate(instance=event, schema=self.event_schema, resolver=resolver)
        except ValidationError as e:
            errors.append(f"Event validation error: {e.message}")
            if e.path:
                errors.append(f"  Path: {'/'.join(str(p) for p in e.path)}")
        except Exception as e:
            errors.append(f"Unexpected error validating event: {str(e)}")
        
        return errors
    
    def validate_loan_created_event(self, event: Dict[str, Any]) -> List[str]:
        """Validate a loan created event specifically.
        
        Args:
            event: Loan created event to validate
            
        Returns:
            List of validation errors (empty if valid)
        """
        errors = []
        
        # First validate as a general event
        errors.extend(self.validate_event(event))
        
        # Check event type
        if event.get("eventHeader", {}).get("eventType") != "LoanCreated":
            errors.append("Event type is not 'LoanCreated'")
        
        if event.get("eventHeader", {}).get("eventName") != "Loan Created":
            errors.append("Event name is not 'Loan Created'")
        
        # Validate loan entity in the event
        entities = event.get("entities", [])
        if not entities:
            errors.append("Event has no entities")
        else:
            loan_entity = entities[0]
            if loan_entity.get("entityHeader", {}).get("entityType") != "Loan":
                errors.append("First entity is not of type 'Loan'")
            else:
                errors.extend(self.validate_loan_entity(loan_entity))
        
        return errors
    
    def validate_car_large_structure(self, car_entity: Dict[str, Any]) -> List[str]:
        """Validate that a car entity matches the large car entity structure.
        
        Args:
            car_entity: Car entity to validate
            
        Returns:
            List of validation errors (empty if valid)
        """
        errors = []
        
        # Validate against schema
        errors.extend(self.validate_car_entity(car_entity))
        
        # Check required fields from car-large.json example
        required_fields = ["id", "vin", "make", "model", "year", "color", "mileage", 
                          "lastServiceDate", "totalBalance", "lastLoanPaymentDate", "owner"]
        
        for field in required_fields:
            if field not in car_entity:
                errors.append(f"Missing required field: {field}")
        
        # Check entity header
        if "entityHeader" not in car_entity:
            errors.append("Missing entityHeader")
        else:
            entity_header = car_entity["entityHeader"]
            if entity_header.get("entityType") != "Car":
                errors.append("Entity type is not 'Car'")
        
        return errors
    
    def validate_examples(self) -> bool:
        """Validate the example files themselves.
        
        Returns:
            True if all examples are valid, False otherwise
        """
        print("Validating example files...")
        print(f"  - Car large entity: {self.data_dir / 'entities/car/car-large.json'}")
        print(f"  - Loan created event: {self.data_dir / 'schemas/event/samples/loan-created-event.json'}")
        print()
        
        all_valid = True
        
        # Validate car-large.json
        car_errors = self.validate_car_large_structure(self.car_large_example)
        if car_errors:
            print("❌ Car large entity validation failed:")
            for error in car_errors:
                print(f"    {error}")
            all_valid = False
        else:
            print("✓ Car large entity is valid")
        
        # Validate loan-created-event.json
        loan_errors = self.validate_loan_created_event(self.loan_created_example)
        if loan_errors:
            print("❌ Loan created event validation failed:")
            for error in loan_errors:
                print(f"    {error}")
            all_valid = False
        else:
            print("✓ Loan created event is valid")
        
        print()
        return all_valid


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Validate entity structures against schemas in data/schemas/"
    )
    parser.add_argument(
        "--data-dir",
        type=str,
        default=None,
        help="Path to data directory (default: auto-detect from script location)"
    )
    parser.add_argument(
        "--file",
        type=str,
        help="Path to JSON file to validate"
    )
    parser.add_argument(
        "--type",
        type=str,
        choices=["car", "loan", "loan-created-event", "event"],
        help="Type of entity/event to validate"
    )
    parser.add_argument(
        "--validate-examples",
        action="store_true",
        help="Validate the example files themselves (car-large.json, loan-created-event.json)"
    )
    
    args = parser.parse_args()
    
    # Determine data directory
    if args.data_dir:
        data_dir = Path(args.data_dir)
    else:
        # Auto-detect from script location
        script_dir = Path(__file__).parent
        project_root = script_dir.parent.parent
        data_dir = project_root / "data"
    
    if not data_dir.exists():
        print(f"Error: Data directory not found: {data_dir}")
        sys.exit(1)
    
    try:
        validator = EntityValidator(data_dir)
    except Exception as e:
        print(f"Error initializing validator: {e}")
        sys.exit(1)
    
    # Validate examples if requested
    if args.validate_examples:
        if validator.validate_examples():
            print("All example files are valid!")
            sys.exit(0)
        else:
            print("Some example files failed validation")
            sys.exit(1)
    
    # Validate a specific file
    if args.file:
        if not args.type:
            print("Error: --type is required when using --file")
            sys.exit(1)
        
        file_path = Path(args.file)
        if not file_path.exists():
            print(f"Error: File not found: {file_path}")
            sys.exit(1)
        
        with open(file_path, 'r') as f:
            data = json.load(f)
        
        errors = []
        if args.type == "car":
            errors = validator.validate_car_large_structure(data)
        elif args.type == "loan":
            errors = validator.validate_loan_entity(data)
        elif args.type == "loan-created-event":
            errors = validator.validate_loan_created_event(data)
        elif args.type == "event":
            errors = validator.validate_event(data)
        
        if errors:
            print(f"❌ Validation failed for {file_path}:")
            for error in errors:
                print(f"    {error}")
            sys.exit(1)
        else:
            print(f"✓ {file_path} is valid")
            sys.exit(0)
    else:
        # Default: validate examples
        if validator.validate_examples():
            print("All example files are valid!")
            sys.exit(0)
        else:
            print("Some example files failed validation")
            sys.exit(1)


if __name__ == "__main__":
    main()

