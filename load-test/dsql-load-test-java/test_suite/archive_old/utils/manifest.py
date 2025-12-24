"""
Manifest file management for test runs.
"""

import json
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime


class ManifestManager:
    """Manage test run manifest files."""
    
    def __init__(self, manifest_path: str):
        self.manifest_path = Path(manifest_path)
        self.manifest: Dict[str, Any] = {
            'start_time': datetime.utcnow().isoformat() + 'Z',
            'total_expected': 0,
            'test_groups': [],
            'tests': []
        }
    
    def load(self) -> Dict[str, Any]:
        """Load existing manifest."""
        if self.manifest_path.exists():
            with open(self.manifest_path, 'r') as f:
                self.manifest = json.load(f)
        return self.manifest
    
    def save(self) -> None:
        """Save manifest to file."""
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.manifest_path, 'w') as f:
            json.dump(self.manifest, f, indent=2)
    
    def add_test(self, test_id: str, scenario: int, threads: int, 
                 iterations: int, count: int, payload_size: str, 
                 status: str = "completed") -> None:
        """Add a test entry to manifest."""
        test_entry = {
            'test_id': test_id,
            'scenario': scenario,
            'threads': threads,
            'iterations': iterations,
            'count': count,
            'payload_size': payload_size,
            'status': status
        }
        
        # Remove existing entry if present
        self.manifest['tests'] = [
            t for t in self.manifest['tests'] 
            if t.get('test_id') != test_id
        ]
        
        self.manifest['tests'].append(test_entry)
        self.save()
    
    def set_end_time(self) -> None:
        """Set end time in manifest."""
        self.manifest['end_time'] = datetime.utcnow().isoformat() + 'Z'
        self.save()
    
    def get_completed_tests(self) -> List[str]:
        """Get list of completed test IDs."""
        return [
            t['test_id'] 
            for t in self.manifest.get('tests', [])
            if t.get('status') == 'completed'
        ]
    
    def get_failed_tests(self) -> List[str]:
        """Get list of failed test IDs."""
        return [
            t['test_id'] 
            for t in self.manifest.get('tests', [])
            if t.get('status') in ['failed', 'error']
        ]
    
    def set_total_expected(self, total: int) -> None:
        """Set total expected number of tests."""
        self.manifest['total_expected'] = total
        self.save()
    
    def set_test_groups(self, groups: List[str]) -> None:
        """Set test groups being run."""
        self.manifest['test_groups'] = groups
        self.save()
    
    def update_status(self, test_id: str, status: str) -> None:
        """Update status of a test."""
        for test in self.manifest.get('tests', []):
            if test.get('test_id') == test_id:
                test['status'] = status
                self.save()
                return
    
    def get_running_test(self) -> Optional[Dict[str, Any]]:
        """Get currently running test from manifest."""
        for test in self.manifest.get('tests', []):
            if test.get('status') == 'running':
                return test
        return None
    
    def get_pending_tests(self) -> List[Dict[str, Any]]:
        """Get list of pending tests."""
        return [
            t for t in self.manifest.get('tests', [])
            if t.get('status') == 'pending'
        ]

