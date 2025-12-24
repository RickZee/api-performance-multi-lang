"""
Simple progress monitoring.
"""

import time
import json
from pathlib import Path
from typing import Optional


def monitor_progress(results_dir: Path, total_tests: Optional[int] = None, interval: int = 10):
    """
    Poll results directory and print progress.
    
    Args:
        results_dir: Directory containing test results
        total_tests: Total number of tests (if None, will try to infer from completed.json)
        interval: Check interval in seconds
    """
    results_dir = Path(results_dir)
    
    # Try to get total from manifest.json or completed.json if not provided
    if total_tests is None:
        # First try manifest.json
        manifest_file = results_dir / 'manifest.json'
        if manifest_file.exists():
            try:
                with open(manifest_file, 'r') as f:
                    data = json.load(f)
                    # Check for total_expected or total_tests
                    total_tests = data.get('total_expected') or data.get('total_tests') or data.get('total')
            except Exception:
                pass
        
        # If still None, try completed.json
        if total_tests is None:
            completed_file = results_dir / 'completed.json'
            if completed_file.exists():
                try:
                    with open(completed_file, 'r') as f:
                        data = json.load(f)
                        # Try to infer total from test IDs (find highest test number)
                        completed = data.get('completed', [])
                        if completed:
                            # Extract test numbers and find max
                            max_num = 0
                            for test_id in completed:
                                try:
                                    # Extract number from test-001-... format
                                    num_str = test_id.split('-')[1]
                                    num = int(num_str)
                                    max_num = max(max_num, num)
                                except (ValueError, IndexError):
                                    pass
                            # Estimate total as max_num (might be conservative)
                            total_tests = max_num
                except Exception:
                    pass
        
        # If still None, try to load from test-config.json to get total
        if total_tests is None:
            try:
                from test_suite.runner import TestConfigLoader
                config_path = results_dir.parent.parent / 'test-config.json'
                if config_path.exists():
                    loader = TestConfigLoader(str(config_path))
                    loader.load_config()
                    all_tests = loader.generate_test_matrix()
                    total_tests = len(all_tests)
            except Exception:
                pass
    
    if total_tests is None:
        print("Warning: Could not determine total tests, will show completed count only")
    
    start_time = time.time()
    
    try:
        while True:
            # Count completed tests
            completed = len(list(results_dir.glob("test-*.json")))
            
            elapsed = time.time() - start_time
            
            if total_tests:
                remaining = total_tests - completed
                progress_pct = (completed / total_tests * 100) if total_tests > 0 else 0
                
                # Estimate remaining time
                if completed > 0:
                    avg_per_test = elapsed / completed
                    est_remaining = avg_per_test * remaining
                else:
                    est_remaining = 0
                
                print(f"\rProgress: {completed}/{total_tests} ({progress_pct:.1f}%) | "
                      f"Elapsed: {elapsed/60:.1f}m | "
                      f"Est. remaining: {est_remaining/60:.1f}m", end="", flush=True)
                
                if completed >= total_tests:
                    print("\n✓ All tests completed!")
                    break
            else:
                print(f"\rCompleted: {completed} tests | Elapsed: {elapsed/60:.1f}m", end="", flush=True)
            
            time.sleep(interval)
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")

