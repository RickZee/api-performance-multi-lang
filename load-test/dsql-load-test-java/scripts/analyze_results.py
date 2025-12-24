#!/usr/bin/env python3
"""
Analysis CLI wrapper - enhances existing analyze-results.py with auto-wait functionality.
"""

import sys
import argparse
import subprocess
from pathlib import Path

# Import the existing analyze-results module
script_dir = Path(__file__).parent.parent
sys.path.insert(0, str(script_dir))

# Import existing analysis functions
# Note: analyze-results.py uses hyphens, so we need to import it as a module
import importlib.util
analyze_results_path = script_dir / 'analyze-results.py'
if analyze_results_path.exists():
    spec = importlib.util.spec_from_file_location("analyze_results_module", analyze_results_path)
    analyze_results_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analyze_results_module)
    load_test_results = analyze_results_module.load_test_results
    generate_charts = analyze_results_module.generate_charts
    parse_payload_size = analyze_results_module.parse_payload_size
else:
    # Fallback: define minimal functions
    def load_test_results(results_dir: str):
        import pandas as pd
        import json
        import glob
        import os
        results = []
        for json_file in glob.glob(os.path.join(results_dir, "test-*.json")):
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)
                config = data.get('configuration', {})
                test_id = data.get('test_id', '')
                results_data = data.get('results', {})
                for scenario_key in ['scenario_1', 'scenario_2']:
                    if scenario_key in results_data:
                        scenario_num = 1 if scenario_key == 'scenario_1' else 2
                        scenario_result = results_data[scenario_key]
                        row = {
                            'test_id': test_id,
                            'scenario': scenario_num,
                            'threads': config.get('threads'),
                            'iterations': config.get('iterations'),
                            'count': config.get('count'),
                            'batch_size': config.get('batch_size'),
                            'payload_size': config.get('payload_size', 'default'),
                            'total_success': scenario_result.get('total_success', 0),
                            'total_errors': scenario_result.get('total_errors', 0),
                            'duration_ms': scenario_result.get('duration_ms', 0),
                            'throughput_inserts_per_sec': scenario_result.get('throughput_inserts_per_sec', 0),
                        }
                        results.append(row)
            except Exception:
                pass
        return pd.DataFrame(results)
    
    def generate_charts(df, output_dir: str):
        print("Chart generation requires analyze-results.py")
    
    def parse_payload_size(payload_str: str) -> int:
        return 665


def main():
    parser = argparse.ArgumentParser(
        description='Analyze DSQL performance test results',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze latest results
  python3 scripts/analyze_results.py

  # Analyze specific directory
  python3 scripts/analyze_results.py results/2025-12-22_14-37-03

  # Wait for completion then analyze
  python3 scripts/analyze_results.py --wait
        """
    )
    
    parser.add_argument(
        'results_dir',
        nargs='?',
        help='Results directory to analyze (default: results/latest)'
    )
    
    parser.add_argument(
        '--wait',
        action='store_true',
        help='Wait for tests to complete before analyzing'
    )
    
    parser.add_argument(
        '--wait-timeout',
        type=int,
        default=18000,  # 5 hours
        help='Wait timeout in seconds (default: 18000)'
    )
    
    args = parser.parse_args()
    
    # Determine results directory
    script_dir = Path(__file__).parent.parent
    if args.results_dir:
        results_dir = Path(args.results_dir)
    else:
        # Use latest
        latest_link = script_dir / 'results' / 'latest'
        if latest_link.exists() and latest_link.is_symlink():
            results_dir = latest_link.resolve()
        else:
            # Find most recent
            results_base = script_dir / 'results'
            if results_base.exists():
                dirs = sorted([d for d in results_base.iterdir() if d.is_dir()], reverse=True)
                if dirs:
                    results_dir = dirs[0]
                else:
                    print("Error: No results directory found", file=sys.stderr)
                    sys.exit(1)
            else:
                print("Error: No results directory found", file=sys.stderr)
                sys.exit(1)
    
    # Wait if requested
    if args.wait:
        print("Waiting for tests to complete...")
        # Import wait functionality
        from test_suite.monitoring.status_checker import StatusChecker
        from test_suite.config.aws_config import AWSConfig as ConfigLoader
        import time
        
        config_loader = ConfigLoader()
        infra_config = config_loader.get_all_config()
        
        status_checker = StatusChecker(
            infra_config['test_runner_instance_id'],
            infra_config['aws_region'],
            results_dir
        )
        
        start_time = time.time()
        while time.time() - start_time < args.wait_timeout:
            active_cmd = status_checker.get_active_command()
            if not active_cmd:
                # Check if we have enough results
                completed = status_checker.get_completed_tests()
                if len(completed) >= 8:  # At least some tests
                    print("Tests appear complete")
                    break
            
            time.sleep(60)  # Check every minute
    
    # Run analysis using existing script
    results_path = str(results_dir)
    
    # Load and analyze
    try:
        df = load_test_results(results_path)
        if df.empty:
            print("Warning: No test results found", file=sys.stderr)
            sys.exit(1)
        
        generate_charts(df, results_path)
        print(f"\nAnalysis complete! Results in: {results_path}")
        
        # Also run chart generation and report if available
        chart_script = script_dir / 'create-comprehensive-charts.py'
        if chart_script.exists():
            print("\nGenerating comprehensive charts...")
            subprocess.run([sys.executable, str(chart_script), results_path], check=False)
        
        report_script = script_dir / 'generate-report.py'
        if report_script.exists():
            print("\nGenerating HTML report...")
            subprocess.run([sys.executable, str(report_script), results_path], check=False)
        
    except Exception as e:
        print(f"Error during analysis: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()

