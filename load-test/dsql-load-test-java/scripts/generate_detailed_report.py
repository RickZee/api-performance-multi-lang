#!/usr/bin/env python3
"""
Generate a detailed markdown report from test results.
Works with any JSON result files (test-*.json, smoke-test-*.json, local-test-*.json, etc.)
"""

import sys
import json
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional

def load_all_results(results_dir: Path) -> List[Dict]:
    """Load all test result JSON files."""
    results = []
    
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        return results
    
    # Look for all JSON files except manifest.json and completed.json
    for json_file in sorted(results_dir.glob("*.json")):
        if json_file.name in ['manifest.json', 'completed.json']:
            continue
        
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            if not data or ('test_id' not in data and 'configuration' not in data):
                continue
            
            results.append(data)
        except Exception as e:
            print(f"Warning: Failed to load {json_file}: {e}")
    
    return results


def format_duration(ms: float) -> str:
    """Format duration in milliseconds."""
    if ms < 1000:
        return f"{ms:.0f}ms"
    elif ms < 60000:
        return f"{ms/1000:.2f}s"
    else:
        minutes = int(ms / 60000)
        seconds = (ms % 60000) / 1000
        return f"{minutes}m {seconds:.1f}s"


def format_number(num: float) -> str:
    """Format number with commas."""
    return f"{num:,.0f}"


def generate_report(results: List[Dict], output_file: Path):
    """Generate detailed markdown report."""
    if not results:
        print("No test results found to generate report.")
        return
    
    md = []
    md.append("# Performance Test Report")
    md.append("")
    md.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    md.append(f"**Total Tests:** {len(results)}")
    md.append("")
    
    # Summary section
    md.append("## Executive Summary")
    md.append("")
    
    total_success = 0
    total_errors = 0
    total_duration = 0
    throughputs = []
    
    for result in results:
        results_data = result.get('results', {})
        for scenario_key in ['scenario_1', 'scenario_2']:
            if scenario_key in results_data:
                scenario_result = results_data[scenario_key]
                total_success += scenario_result.get('total_success', 0)
                total_errors += scenario_result.get('total_errors', 0)
                total_duration += scenario_result.get('duration_ms', 0)
                throughput = scenario_result.get('throughput_inserts_per_sec', 0)
                if throughput > 0:
                    throughputs.append(throughput)
    
    md.append(f"- **Total Operations:** {format_number(total_success)} successful, {format_number(total_errors)} errors")
    md.append(f"- **Total Duration:** {format_duration(total_duration)}")
    if throughputs:
        md.append(f"- **Average Throughput:** {sum(throughputs)/len(throughputs):.2f} inserts/second")
        md.append(f"- **Peak Throughput:** {max(throughputs):.2f} inserts/second")
    md.append("")
    
    # Detailed test results
    md.append("## Test Results")
    md.append("")
    
    for i, result in enumerate(results, 1):
        test_id = result.get('test_id', f'test-{i}')
        timestamp = result.get('timestamp', '')
        config = result.get('configuration', {})
        results_data = result.get('results', {})
        
        md.append(f"### Test {i}: {test_id}")
        md.append("")
        if timestamp:
            md.append(f"**Timestamp:** {timestamp}")
            md.append("")
        
        md.append("**Configuration:**")
        md.append(f"- Scenario: {config.get('scenario', 'N/A')}")
        md.append(f"- Threads: {config.get('threads', 'N/A')}")
        md.append(f"- Iterations: {config.get('iterations', 'N/A')}")
        md.append(f"- Count: {config.get('count', 'N/A')}")
        if config.get('batch_size'):
            md.append(f"- Batch Size: {config.get('batch_size')}")
        md.append(f"- Event Type: {config.get('event_type', 'N/A')}")
        md.append(f"- Payload Size: {config.get('payload_size', 'default')}")
        md.append("")
        
        # Scenario results
        for scenario_key in ['scenario_1', 'scenario_2']:
            if scenario_key in results_data:
                scenario_num = scenario_key.replace('scenario_', '')
                scenario_result = results_data[scenario_key]
                latency_stats = scenario_result.get('latency_stats', {})
                thread_results = scenario_result.get('thread_results', {})
                
                md.append(f"#### Scenario {scenario_num}: {'Individual Inserts' if scenario_num == '1' else 'Batch Inserts'}")
                md.append("")
                md.append("**Performance Metrics:**")
                md.append(f"- **Success:** {format_number(scenario_result.get('total_success', 0))} inserts")
                md.append(f"- **Errors:** {format_number(scenario_result.get('total_errors', 0))} ({scenario_result.get('total_errors', 0) / (scenario_result.get('total_success', 0) + scenario_result.get('total_errors', 0)) * 100 if (scenario_result.get('total_success', 0) + scenario_result.get('total_errors', 0)) > 0 else 0:.2f}%)")
                md.append(f"- **Duration:** {format_duration(scenario_result.get('duration_ms', 0))}")
                md.append(f"- **Throughput:** {scenario_result.get('throughput_inserts_per_sec', 0):.2f} inserts/second (overall)")
                md.append(f"- **Avg per Thread:** {scenario_result.get('avg_inserts_per_sec', 0):.2f} inserts/second")
                md.append("")
                
                if latency_stats:
                    md.append("**Latency Percentiles:**")
                    md.append(f"- **P50:** {latency_stats.get('p50_latency_ms', 0):.2f}ms")
                    md.append(f"- **P95:** {latency_stats.get('p95_latency_ms', 0):.2f}ms")
                    md.append(f"- **P99:** {latency_stats.get('p99_latency_ms', 0):.2f}ms")
                    md.append(f"- **Min:** {latency_stats.get('min_latency_ms', 0):.2f}ms")
                    md.append(f"- **Max:** {latency_stats.get('max_latency_ms', 0):.2f}ms")
                    md.append("")
                
                # Thread breakdown
                if thread_results:
                    md.append("**Thread Performance:**")
                    md.append("")
                    md.append("| Thread | Success | Errors | Duration | Throughput |")
                    md.append("|--------|---------|--------|----------|-----------|")
                    for thread_id, thread_data in sorted(thread_results.items(), key=lambda x: int(x[0])):
                        md.append(f"| {thread_id} | {thread_data.get('success_count', 0)} | {thread_data.get('error_count', 0)} | {format_duration(thread_data.get('duration_ms', 0))} | {thread_data.get('inserts_per_sec', 0):.2f} inserts/sec |")
                    md.append("")
                
                # Database validation
                db_validation = result.get('database_validation', {})
                if db_validation:
                    expected = db_validation.get('expected', 0)
                    actual = db_validation.get('actual', 0)
                    status = db_validation.get('status', 'UNKNOWN')
                    md.append(f"**Database Validation:**")
                    md.append(f"- Expected: {format_number(expected)} rows")
                    md.append(f"- Actual: {format_number(actual)} rows")
                    md.append(f"- Status: {status}")
                    if actual != expected:
                        md.append(f"- **Note:** Difference may be due to previous test runs")
                    md.append("")
        
        # Connection pool metrics
        pool_metrics = result.get('pool_metrics', {})
        if pool_metrics:
            md.append("**Connection Pool Metrics:**")
            md.append(f"- Active: {pool_metrics.get('active_connections', 0)}")
            md.append(f"- Idle: {pool_metrics.get('idle_connections', 0)}")
            md.append(f"- Waiting: {pool_metrics.get('waiting_threads', 0)}")
            md.append(f"- Total: {pool_metrics.get('total_connections', 0)}")
            md.append(f"- Max Pool Size: {pool_metrics.get('max_pool_size', 0)}")
            md.append("")
        
        # System metrics
        system_metrics = result.get('system_metrics', {})
        if system_metrics:
            hardware = system_metrics.get('hardware', {})
            if hardware:
                md.append("**System Information:**")
                md.append(f"- CPU Cores: {hardware.get('processor_count', 'N/A')}")
                md.append(f"- Architecture: {hardware.get('architecture', 'N/A')}")
                md.append(f"- OS: {hardware.get('os_name', 'N/A')} {hardware.get('os_version', '')}")
                md.append(f"- Java: {hardware.get('java_version', 'N/A')} ({hardware.get('java_vendor', 'N/A')})")
                md.append("")
        
        md.append("---")
        md.append("")
    
    # Comparison section if multiple scenarios
    scenario1_results = []
    scenario2_results = []
    
    for result in results:
        results_data = result.get('results', {})
        if 'scenario_1' in results_data:
            scenario1_results.append(results_data['scenario_1'])
        if 'scenario_2' in results_data:
            scenario2_results.append(results_data['scenario_2'])
    
    if scenario1_results and scenario2_results:
        md.append("## Scenario Comparison")
        md.append("")
        md.append("| Metric | Scenario 1 (Individual) | Scenario 2 (Batch) |")
        md.append("|--------|------------------------|-------------------|")
        
        s1_avg_throughput = sum(s.get('throughput_inserts_per_sec', 0) for s in scenario1_results) / len(scenario1_results)
        s2_avg_throughput = sum(s.get('throughput_inserts_per_sec', 0) for s in scenario2_results) / len(scenario2_results)
        md.append(f"| Avg Throughput | {s1_avg_throughput:.2f} inserts/sec | {s2_avg_throughput:.2f} inserts/sec |")
        
        s1_avg_duration = sum(s.get('duration_ms', 0) for s in scenario1_results) / len(scenario1_results)
        s2_avg_duration = sum(s.get('duration_ms', 0) for s in scenario2_results) / len(scenario2_results)
        md.append(f"| Avg Duration | {format_duration(s1_avg_duration)} | {format_duration(s2_avg_duration)} |")
        
        s1_total_success = sum(s.get('total_success', 0) for s in scenario1_results)
        s2_total_success = sum(s.get('total_success', 0) for s in scenario2_results)
        md.append(f"| Total Success | {format_number(s1_total_success)} | {format_number(s2_total_success)} |")
        
        md.append("")
        md.append(f"**Performance Ratio:** Scenario 2 is {s2_avg_throughput/s1_avg_throughput:.2f}x faster than Scenario 1")
        md.append("")
    
    # Write report
    report_content = "\n".join(md)
    
    with open(output_file, 'w') as f:
        f.write(report_content)
    
    print(f"✅ Detailed report generated: {output_file}")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Generate detailed markdown report from test results',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate report for latest results
  python3 scripts/generate_detailed_report.py

  # Generate report for specific directory
  python3 scripts/generate_detailed_report.py results/smoke-test-local-20260106_133844

  # Specify output file
  python3 scripts/generate_detailed_report.py --output custom-report.md
        """
    )
    
    parser.add_argument(
        'results_dir',
        nargs='?',
        type=str,
        help='Results directory (default: results/latest)'
    )
    parser.add_argument(
        '--output', '-o',
        type=str,
        help='Output markdown file (default: results_dir/REPORT.md)'
    )
    
    args = parser.parse_args()
    
    # Determine results directory
    script_dir = Path(__file__).parent.parent
    if args.results_dir:
        results_dir = Path(args.results_dir)
        if not results_dir.is_absolute():
            results_dir = script_dir / results_dir
    else:
        # Try latest symlink, then latest directory
        latest_link = script_dir / 'results' / 'latest'
        if latest_link.exists() and latest_link.is_symlink():
            results_dir = script_dir / 'results' / latest_link.readlink()
        else:
            # Find most recent directory
            results_base = script_dir / 'results'
            if results_base.exists():
                dirs = [d for d in results_base.iterdir() if d.is_dir()]
                if dirs:
                    results_dir = max(dirs, key=lambda d: d.stat().st_mtime)
                else:
                    print("Error: No results directory found")
                    sys.exit(1)
            else:
                print("Error: Results directory not found")
                sys.exit(1)
    
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    # Determine output file
    if args.output:
        output_file = Path(args.output)
        if not output_file.is_absolute():
            output_file = script_dir / output_file
    else:
        output_file = results_dir / 'REPORT.md'
    
    # Load results and generate report
    print(f"Loading test results from: {results_dir}")
    results = load_all_results(results_dir)
    
    if not results:
        print("No test results found.")
        sys.exit(1)
    
    print(f"Found {len(results)} test result(s)")
    generate_report(results, output_file)
    print(f"\nReport saved to: {output_file}")


if __name__ == '__main__':
    main()

