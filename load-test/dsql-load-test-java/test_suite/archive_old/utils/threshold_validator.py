"""
Threshold validation for test results.
"""

from typing import Dict, List, Optional, Tuple
import json
from pathlib import Path


class ThresholdValidator:
    """Validate test results against performance thresholds."""
    
    def __init__(self, thresholds: Optional[Dict] = None):
        """
        Initialize validator with thresholds.
        
        Args:
            thresholds: Dict with keys:
                - min_throughput: Minimum throughput in inserts/sec
                - max_p99_latency_ms: Maximum p99 latency in milliseconds
                - max_error_rate: Maximum error rate (0.0 to 1.0)
        """
        self.thresholds = thresholds or {}
        self.min_throughput = self.thresholds.get('min_throughput', 0)
        self.max_p99_latency_ms = self.thresholds.get('max_p99_latency_ms', float('inf'))
        self.max_error_rate = self.thresholds.get('max_error_rate', 1.0)
    
    def validate_result(self, result_data: Dict) -> Tuple[bool, List[str]]:
        """
        Validate a single test result against thresholds.
        
        Returns:
            Tuple of (passed: bool, failures: List[str])
        """
        failures = []
        results = result_data.get('results', {})
        
        # Check each scenario
        for scenario_key in ['scenario_1', 'scenario_2']:
            scenario_result = results.get(scenario_key)
            if not scenario_result:
                continue
            
            test_id = result_data.get('test_id', 'unknown')
            scenario_num = scenario_key.split('_')[1]
            
            # Check throughput
            throughput = scenario_result.get('throughput_inserts_per_sec', 0)
            if throughput < self.min_throughput:
                failures.append(
                    f"{test_id} Scenario {scenario_num}: Throughput {throughput:.2f} < {self.min_throughput} inserts/sec"
                )
            
            # Check p99 latency
            latency_stats = scenario_result.get('latency_stats', {})
            p99_latency = latency_stats.get('p99_latency_ms')
            if p99_latency is not None and p99_latency > self.max_p99_latency_ms:
                failures.append(
                    f"{test_id} Scenario {scenario_num}: P99 latency {p99_latency}ms > {self.max_p99_latency_ms}ms"
                )
            
            # Check error rate
            total_success = scenario_result.get('total_success', 0)
            total_errors = scenario_result.get('total_errors', 0)
            total_ops = total_success + total_errors
            if total_ops > 0:
                error_rate = total_errors / total_ops
                if error_rate > self.max_error_rate:
                    failures.append(
                        f"{test_id} Scenario {scenario_num}: Error rate {error_rate:.4f} > {self.max_error_rate}"
                    )
        
        return len(failures) == 0, failures
    
    def validate_results_directory(self, results_dir: Path) -> Tuple[bool, List[str]]:
        """
        Validate all results in a directory.
        
        Returns:
            Tuple of (all_passed: bool, all_failures: List[str])
        """
        all_failures = []
        all_passed = True
        
        for json_file in sorted(results_dir.glob('test-*.json')):
            try:
                with open(json_file, 'r') as f:
                    result_data = json.load(f)
                    passed, failures = self.validate_result(result_data)
                    if not passed:
                        all_passed = False
                        all_failures.extend(failures)
            except Exception as e:
                all_failures.append(f"Error validating {json_file.name}: {e}")
                all_passed = False
        
        return all_passed, all_failures
    
    @staticmethod
    def load_thresholds_from_config(config_path: Path) -> Optional[Dict]:
        """Load thresholds from test-config.json."""
        if not config_path.exists():
            return None
        
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
                return config.get('thresholds')
        except Exception:
            return None

