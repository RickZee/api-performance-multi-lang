"""
Load and normalize test configuration from JSON.
Handles arrays and single values uniformly.
"""

import json
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from pathlib import Path


@dataclass
class TestDefinition:
    """Represents a single test configuration."""
    test_id: str
    scenario: int
    threads: int
    iterations: int
    count: int
    batch_size: Optional[int] = None
    payload_size: Optional[str] = None
    event_type: str = "CarCreated"
    tags: List[str] = None
    
    def __post_init__(self):
        if self.tags is None:
            self.tags = []


class TestConfigLoader:
    """Load and normalize test configuration from JSON."""
    
    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.config: Dict[str, Any] = {}
    
    def load_config(self) -> Dict[str, Any]:
        """Load test-config.json with proper array/single value handling."""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_path}")
        
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
        
        return self.config
    
    def normalize_value(self, value: Any) -> List[Any]:
        """Convert single values to lists for uniform processing."""
        if value is None:
            return [None]
        if isinstance(value, list):
            return value
        return [value]
    
    def generate_test_matrix(self, test_groups: Optional[List[str]] = None) -> List[TestDefinition]:
        """Generate all test combinations from config."""
        if not self.config:
            self.load_config()
        
        baseline = self.config.get('baseline', {})
        test_groups_config = self.config.get('test_groups', {})
        
        # If specific groups requested, filter
        if test_groups:
            test_groups_config = {k: v for k, v in test_groups_config.items() if k in test_groups}
        
        tests: List[TestDefinition] = []
        test_counter = 1
        
        for group_name, group_config in test_groups_config.items():
            # Normalize all values to lists
            threads_list = self.normalize_value(
                group_config.get('threads', baseline.get('threads', 10))
            )
            iterations_list = self.normalize_value(
                group_config.get('iterations', baseline.get('iterations', 20))
            )
            count_list = self.normalize_value(
                group_config.get('count', group_config.get('batch_size', baseline.get('batch_size', 10)))
            )
            payload_list = self.normalize_value(
                group_config.get('payload_size', baseline.get('payload_size'))
            )
            scenario = group_config.get('scenario', 1)
            event_type = group_config.get('event_type', baseline.get('event_type', 'CarCreated'))
            tags = group_config.get('tags', baseline.get('tags', []))
            if not isinstance(tags, list):
                tags = [tags] if tags else []
            
            # Generate all combinations
            for threads in threads_list:
                for iterations in iterations_list:
                    for count in count_list:
                        for payload_size in payload_list:
                            # Determine batch_size based on scenario
                            batch_size = None
                            if scenario == 2:
                                batch_size = count
                            
                            # Generate test ID with all parameter values after group name
                            # Format: test-NNN-groupname-threads{threads}-loops{iterations}-count{count}-batch{batch_size}-payload{payload}
                            test_id = f"test-{test_counter:03d}-{group_name}-threads{threads}-loops{iterations}-count{count}"
                            
                            # Add batch_size for scenario 2 (explicit parameter value)
                            if scenario == 2 and batch_size:
                                test_id += f"-batch{batch_size}"
                            
                            # Add payload size
                            if payload_size:
                                test_id += f"-payload{payload_size}"
                            else:
                                test_id += "-payloaddefault"
                            
                            test_def = TestDefinition(
                                test_id=test_id,
                                scenario=scenario,
                                threads=threads,
                                iterations=iterations,
                                count=count,
                                batch_size=batch_size,
                                payload_size=payload_size if payload_size else 'default',
                                event_type=event_type,
                                tags=tags
                            )
                            
                            tests.append(test_def)
                            test_counter += 1
        
        return tests

