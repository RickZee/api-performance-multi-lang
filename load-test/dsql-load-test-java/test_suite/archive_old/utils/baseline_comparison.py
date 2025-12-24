"""
Baseline comparison for test results.
"""

from typing import Dict, List, Optional, Tuple
import json
from pathlib import Path


class BaselineComparison:
    """Compare current test results against baseline."""
    
    def __init__(self, baseline_dir: Path, regression_threshold: float = 0.10):
        """
        Initialize baseline comparison.
        
        Args:
            baseline_dir: Directory containing baseline results
            regression_threshold: Percentage change threshold for regression (default 10%)
        """
        self.baseline_dir = baseline_dir
        self.regression_threshold = regression_threshold
        self.baseline_results = self._load_baseline_results()
    
    def _load_baseline_results(self) -> Dict[str, Dict]:
        """Load all baseline results into a dictionary keyed by test_id."""
        baseline_results = {}
        
        if not self.baseline_dir.exists():
            return baseline_results
        
        for json_file in self.baseline_dir.glob('test-*.json'):
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)
                    test_id = data.get('test_id')
                    if test_id:
                        # Normalize test_id (remove timestamp if present)
                        normalized_id = self._normalize_test_id(test_id)
                        baseline_results[normalized_id] = data
            except Exception:
                continue
        
        return baseline_results
    
    def _normalize_test_id(self, test_id: str) -> str:
        """Normalize test ID by removing timestamp/run-specific parts."""
        # Extract the core test parameters (scenario, threads, loops, count, payload)
        # Format: test-001-scenario1-threads10-loops20-count1-payloaddefault
        parts = test_id.split('-')
        if len(parts) >= 6:
            # Keep: scenario, threads, loops, count, payload
            return '-'.join(parts[2:])  # Skip test-001 prefix
        return test_id
    
    def compare_result(self, current_result: Dict) -> Dict:
        """
        Compare a current result against baseline.
        
        Returns:
            Dict with comparison metrics:
                - has_baseline: bool
                - throughput_change_pct: float
                - latency_change_pct: float
                - error_rate_change_pct: float
                - is_regression: bool
                - regression_reasons: List[str]
        """
        test_id = current_result.get('test_id', '')
        normalized_id = self._normalize_test_id(test_id)
        
        baseline = self.baseline_results.get(normalized_id)
        if not baseline:
            return {
                'has_baseline': False,
                'is_regression': False,
                'regression_reasons': []
            }
        
        comparison = {
            'has_baseline': True,
            'is_regression': False,
            'regression_reasons': []
        }
        
        # Compare each scenario
        current_results = current_result.get('results', {})
        baseline_results = baseline.get('results', {})
        
        for scenario_key in ['scenario_1', 'scenario_2']:
            current_scenario = current_results.get(scenario_key)
            baseline_scenario = baseline_results.get(scenario_key)
            
            if not current_scenario or not baseline_scenario:
                continue
            
            # Compare throughput
            current_throughput = current_scenario.get('throughput_inserts_per_sec', 0)
            baseline_throughput = baseline_scenario.get('throughput_inserts_per_sec', 0)
            if baseline_throughput > 0:
                throughput_change = ((current_throughput - baseline_throughput) / baseline_throughput) * 100
                comparison[f'{scenario_key}_throughput_change_pct'] = throughput_change
                
                if throughput_change < -self.regression_threshold * 100:
                    comparison['is_regression'] = True
                    comparison['regression_reasons'].append(
                        f"{scenario_key}: Throughput decreased by {abs(throughput_change):.1f}%"
                    )
            
            # Compare p99 latency
            current_latency_stats = current_scenario.get('latency_stats', {})
            baseline_latency_stats = baseline_scenario.get('latency_stats', {})
            
            current_p99 = current_latency_stats.get('p99_latency_ms')
            baseline_p99 = baseline_latency_stats.get('p99_latency_ms')
            
            if current_p99 is not None and baseline_p99 is not None and baseline_p99 > 0:
                latency_change = ((current_p99 - baseline_p99) / baseline_p99) * 100
                comparison[f'{scenario_key}_latency_change_pct'] = latency_change
                
                if latency_change > self.regression_threshold * 100:
                    comparison['is_regression'] = True
                    comparison['regression_reasons'].append(
                        f"{scenario_key}: P99 latency increased by {latency_change:.1f}%"
                    )
            
            # Compare error rate
            current_success = current_scenario.get('total_success', 0)
            current_errors = current_scenario.get('total_errors', 0)
            current_total = current_success + current_errors
            current_error_rate = (current_errors / current_total) if current_total > 0 else 0
            
            baseline_success = baseline_scenario.get('total_success', 0)
            baseline_errors = baseline_scenario.get('total_errors', 0)
            baseline_total = baseline_success + baseline_errors
            baseline_error_rate = (baseline_errors / baseline_total) if baseline_total > 0 else 0
            
            if baseline_error_rate >= 0:
                error_rate_change = current_error_rate - baseline_error_rate
                comparison[f'{scenario_key}_error_rate_change'] = error_rate_change
                
                if error_rate_change > self.regression_threshold:
                    comparison['is_regression'] = True
                    comparison['regression_reasons'].append(
                        f"{scenario_key}: Error rate increased by {error_rate_change:.4f}"
                    )
        
        return comparison
    
    def compare_results_directory(self, current_dir: Path) -> Dict:
        """
        Compare all results in a directory against baseline.
        
        Returns:
            Dict with:
                - total_tests: int
                - tests_with_baseline: int
                - regressions: int
                - comparisons: List[Dict]
        """
        comparisons = []
        regressions = 0
        
        for json_file in sorted(current_dir.glob('test-*.json')):
            try:
                with open(json_file, 'r') as f:
                    current_result = json.load(f)
                    comparison = self.compare_result(current_result)
                    comparison['test_id'] = current_result.get('test_id', '')
                    comparisons.append(comparison)
                    
                    if comparison.get('is_regression', False):
                        regressions += 1
            except Exception:
                continue
        
        tests_with_baseline = sum(1 for c in comparisons if c.get('has_baseline', False))
        
        return {
            'total_tests': len(comparisons),
            'tests_with_baseline': tests_with_baseline,
            'regressions': regressions,
            'comparisons': comparisons
        }
    
    @staticmethod
    def set_baseline(results_dir: Path, baseline_dir: Optional[Path] = None):
        """
        Set current results as baseline by copying to baseline directory.
        
        Args:
            results_dir: Directory containing current results
            baseline_dir: Baseline directory (default: results/baseline)
        """
        if baseline_dir is None:
            baseline_dir = results_dir.parent / 'baseline'
        
        baseline_dir.mkdir(parents=True, exist_ok=True)
        
        # Copy all test result files
        copied = 0
        for json_file in results_dir.glob('test-*.json'):
            try:
                import shutil
                dest_file = baseline_dir / json_file.name
                shutil.copy2(json_file, dest_file)
                copied += 1
            except Exception as e:
                print(f"Warning: Failed to copy {json_file.name}: {e}")
        
        print(f"✅ Set baseline: Copied {copied} test results to {baseline_dir}")

