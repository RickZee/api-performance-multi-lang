#!/usr/bin/env python3
"""
Generate comprehensive test report from latest test runs.
"""

import sys
import json
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
import pandas as pd

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))


def load_test_results(results_dir: Path) -> List[Dict]:
    """Load all test result JSON files."""
    results = []
    
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        return results
    
    for json_file in sorted(results_dir.glob("test-*.json")):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            if not data or 'test_id' not in data:
                continue
            
            results.append(data)
        except Exception as e:
            print(f"Warning: Failed to load {json_file}: {e}")
    
    return results


def extract_test_metrics(result: Dict) -> Dict:
    """Extract key metrics from a test result."""
    config = result.get('configuration', {})
    test_id = result.get('test_id', 'unknown')
    timestamp = result.get('timestamp', '')
    
    metrics = {
        'test_id': test_id,
        'timestamp': timestamp,
        'scenario': config.get('scenario', 0),
        'threads': config.get('threads', 0),
        'iterations': config.get('iterations', 0),
        'count': config.get('count', 0),
        'batch_size': config.get('batch_size', 0),
        'payload_size': config.get('payload_size', 'default'),
    }
    
    # Extract results from both scenarios
    results_data = result.get('results', {})
    
    for scenario_key in ['scenario_1', 'scenario_2']:
        if scenario_key in results_data:
            scenario_result = results_data[scenario_key]
            scenario_num = 1 if scenario_key == 'scenario_1' else 2
            
            latency_stats = scenario_result.get('latency_stats', {})
            pool_metrics = scenario_result.get('pool_metrics', {})
            
            # Create scenario-specific metrics
            scenario_metrics = metrics.copy()
            scenario_metrics['scenario_result'] = scenario_num
            scenario_metrics['total_success'] = scenario_result.get('total_success', 0)
            scenario_metrics['total_errors'] = scenario_result.get('total_errors', 0)
            scenario_metrics['duration_ms'] = scenario_result.get('duration_ms', 0)
            scenario_metrics['duration_sec'] = scenario_metrics['duration_ms'] / 1000.0
            scenario_metrics['throughput_inserts_per_sec'] = scenario_result.get('throughput_inserts_per_sec', 0)
            scenario_metrics['avg_inserts_per_sec'] = scenario_result.get('avg_inserts_per_sec', 0)
            scenario_metrics['expected_rows'] = scenario_result.get('expected_rows', 0)
            scenario_metrics['actual_rows'] = scenario_result.get('actual_rows', 0)
            scenario_metrics['p50_latency_ms'] = latency_stats.get('p50_latency_ms', 0)
            scenario_metrics['p95_latency_ms'] = latency_stats.get('p95_latency_ms', 0)
            scenario_metrics['p99_latency_ms'] = latency_stats.get('p99_latency_ms', 0)
            scenario_metrics['min_latency_ms'] = latency_stats.get('min_latency_ms', 0)
            scenario_metrics['max_latency_ms'] = latency_stats.get('max_latency_ms', 0)
            scenario_metrics['avg_latency_ms'] = latency_stats.get('avg_latency_ms', 0)
            scenario_metrics['active_connections'] = pool_metrics.get('active_connections', 0)
            scenario_metrics['max_pool_size'] = pool_metrics.get('max_pool_size', 0)
            scenario_metrics['pool_utilization_pct'] = (scenario_metrics['active_connections'] / scenario_metrics['max_pool_size'] * 100) if scenario_metrics['max_pool_size'] > 0 else 0
            
            total_ops = scenario_metrics['total_success'] + scenario_metrics['total_errors']
            scenario_metrics['error_rate_pct'] = (scenario_metrics['total_errors'] / total_ops * 100) if total_ops > 0 else 0
            
            # Error breakdown
            errors_by_category = scenario_result.get('errors_by_category', {})
            scenario_metrics['connection_errors'] = errors_by_category.get('CONNECTION_ERROR', 0)
            scenario_metrics['query_errors'] = errors_by_category.get('QUERY_ERROR', 0)
            scenario_metrics['auth_errors'] = errors_by_category.get('AUTHENTICATION_ERROR', 0)
            scenario_metrics['unknown_errors'] = errors_by_category.get('UNKNOWN_ERROR', 0)
            
            yield scenario_metrics


def generate_report(results: List[Dict], output_file: Path):
    """Generate comprehensive report."""
    
    # Extract all metrics
    all_metrics = []
    for result in results:
        for metrics in extract_test_metrics(result):
            all_metrics.append(metrics)
    
    if not all_metrics:
        print("Error: No metrics extracted from results")
        return
    
    df = pd.DataFrame(all_metrics)
    
    # Generate report
    report_lines = []
    report_lines.append("=" * 100)
    report_lines.append("COMPREHENSIVE TEST REPORT")
    report_lines.append("=" * 100)
    report_lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report_lines.append(f"Total Tests: {len(results)}")
    report_lines.append(f"Total Scenarios: {len(df)}")
    report_lines.append("")
    
    # Summary Statistics
    report_lines.append("=" * 100)
    report_lines.append("SUMMARY STATISTICS")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    report_lines.append(f"Total Operations:")
    report_lines.append(f"  Success: {df['total_success'].sum():,}")
    report_lines.append(f"  Errors: {df['total_errors'].sum():,}")
    report_lines.append(f"  Total: {df['total_success'].sum() + df['total_errors'].sum():,}")
    report_lines.append(f"  Overall Error Rate: {df['error_rate_pct'].mean():.2f}%")
    report_lines.append("")
    
    report_lines.append(f"Throughput:")
    report_lines.append(f"  Average: {df['throughput_inserts_per_sec'].mean():.0f} inserts/sec")
    report_lines.append(f"  Maximum: {df['throughput_inserts_per_sec'].max():.0f} inserts/sec")
    report_lines.append(f"  Minimum: {df['throughput_inserts_per_sec'].min():.0f} inserts/sec")
    report_lines.append("")
    
    report_lines.append(f"Latency (P95):")
    report_lines.append(f"  Average: {df['p95_latency_ms'].mean():.0f} ms")
    report_lines.append(f"  Maximum: {df['p95_latency_ms'].max():.0f} ms")
    report_lines.append(f"  Minimum: {df['p95_latency_ms'].min():.0f} ms")
    report_lines.append("")
    
    report_lines.append(f"Latency (P99):")
    report_lines.append(f"  Average: {df['p99_latency_ms'].mean():.0f} ms")
    report_lines.append(f"  Maximum: {df['p99_latency_ms'].max():.0f} ms")
    report_lines.append(f"  Minimum: {df['p99_latency_ms'].min():.0f} ms")
    report_lines.append("")
    
    # Test Breakdown by Scenario
    report_lines.append("=" * 100)
    report_lines.append("TEST BREAKDOWN BY SCENARIO")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    for scenario in [1, 2]:
        scenario_df = df[df['scenario'] == scenario]
        if len(scenario_df) == 0:
            continue
        
        report_lines.append(f"Scenario {scenario}: {'Individual Inserts' if scenario == 1 else 'Batch Inserts'}")
        report_lines.append("-" * 100)
        report_lines.append(f"  Tests: {len(scenario_df)}")
        report_lines.append(f"  Total Operations: {scenario_df['total_success'].sum():,}")
        report_lines.append(f"  Average Throughput: {scenario_df['throughput_inserts_per_sec'].mean():.0f} inserts/sec")
        report_lines.append(f"  Max Throughput: {scenario_df['throughput_inserts_per_sec'].max():.0f} inserts/sec")
        report_lines.append(f"  Average P95 Latency: {scenario_df['p95_latency_ms'].mean():.0f} ms")
        report_lines.append(f"  Average P99 Latency: {scenario_df['p99_latency_ms'].mean():.0f} ms")
        report_lines.append(f"  Error Rate: {scenario_df['error_rate_pct'].mean():.2f}%")
        report_lines.append("")
    
    # Thread Scaling Analysis
    report_lines.append("=" * 100)
    report_lines.append("THREAD SCALING ANALYSIS")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    thread_groups = df.groupby(['scenario', 'threads']).agg({
        'throughput_inserts_per_sec': ['mean', 'max', 'min'],
        'p95_latency_ms': 'mean',
        'p99_latency_ms': 'mean',
        'error_rate_pct': 'mean'
    }).round(0)
    
    for (scenario, threads), group in thread_groups.iterrows():
        report_lines.append(f"Scenario {scenario}, {threads} threads:")
        report_lines.append(f"  Throughput: {group[('throughput_inserts_per_sec', 'mean')]:.0f} inserts/sec (max: {group[('throughput_inserts_per_sec', 'max')]:.0f})")
        report_lines.append(f"  P95 Latency: {group[('p95_latency_ms', 'mean')]:.0f} ms")
        report_lines.append(f"  P99 Latency: {group[('p99_latency_ms', 'mean')]:.0f} ms")
        report_lines.append(f"  Error Rate: {group[('error_rate_pct', 'mean')]:.2f}%")
        report_lines.append("")
    
    # Top Performers
    report_lines.append("=" * 100)
    report_lines.append("TOP PERFORMERS")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    top_throughput = df.nlargest(5, 'throughput_inserts_per_sec')[['test_id', 'scenario', 'threads', 'throughput_inserts_per_sec', 'p95_latency_ms']]
    report_lines.append("Highest Throughput:")
    for _, row in top_throughput.iterrows():
        report_lines.append(f"  {row['test_id'][:60]}")
        report_lines.append(f"    Throughput: {row['throughput_inserts_per_sec']:.0f} inserts/sec, P95: {row['p95_latency_ms']:.0f} ms")
    report_lines.append("")
    
    # Error Analysis
    report_lines.append("=" * 100)
    report_lines.append("ERROR ANALYSIS")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    total_errors = df['total_errors'].sum()
    if total_errors > 0:
        report_lines.append(f"Total Errors: {total_errors:,}")
        report_lines.append(f"  Connection Errors: {df['connection_errors'].sum():,}")
        report_lines.append(f"  Query Errors: {df['query_errors'].sum():,}")
        report_lines.append(f"  Auth Errors: {df['auth_errors'].sum():,}")
        report_lines.append(f"  Unknown Errors: {df['unknown_errors'].sum():,}")
        report_lines.append("")
        
        # Tests with errors
        error_tests = df[df['total_errors'] > 0]
        if len(error_tests) > 0:
            report_lines.append("Tests with Errors:")
            for _, row in error_tests.iterrows():
                report_lines.append(f"  {row['test_id'][:60]}")
                report_lines.append(f"    Errors: {row['total_errors']:,} ({row['error_rate_pct']:.2f}%)")
    else:
        report_lines.append("✅ No errors detected in any tests")
    report_lines.append("")
    
    # Connection Pool Analysis
    report_lines.append("=" * 100)
    report_lines.append("CONNECTION POOL ANALYSIS")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    pool_df = df[df['max_pool_size'] > 0]
    if len(pool_df) > 0:
        report_lines.append(f"Average Pool Utilization: {pool_df['pool_utilization_pct'].mean():.1f}%")
        report_lines.append(f"Maximum Pool Utilization: {pool_df['pool_utilization_pct'].max():.1f}%")
        report_lines.append(f"Average Active Connections: {pool_df['active_connections'].mean():.0f}")
        report_lines.append(f"Maximum Active Connections: {pool_df['active_connections'].max():.0f}")
    report_lines.append("")
    
    # Detailed Test Results
    report_lines.append("=" * 100)
    report_lines.append("DETAILED TEST RESULTS")
    report_lines.append("=" * 100)
    report_lines.append("")
    
    for _, row in df.iterrows():
        report_lines.append(f"Test: {row['test_id']}")
        report_lines.append(f"  Scenario: {row['scenario']} | Threads: {row['threads']} | Iterations: {row['iterations']} | Count: {row['count']}")
        if row['batch_size'] > 0:
            report_lines.append(f"  Batch Size: {row['batch_size']}")
        report_lines.append(f"  Duration: {row['duration_sec']:.1f}s")
        report_lines.append(f"  Throughput: {row['throughput_inserts_per_sec']:.0f} inserts/sec")
        report_lines.append(f"  Latency: P50={row['p50_latency_ms']:.0f}ms, P95={row['p95_latency_ms']:.0f}ms, P99={row['p99_latency_ms']:.0f}ms")
        report_lines.append(f"  Success: {row['total_success']:,} | Errors: {row['total_errors']:,} ({row['error_rate_pct']:.2f}%)")
        report_lines.append("")
    
    # Write report
    report_text = "\n".join(report_lines)
    
    with open(output_file, 'w') as f:
        f.write(report_text)
    
    print(f"✅ Comprehensive report generated: {output_file}")
    print(f"   Total tests analyzed: {len(results)}")
    print(f"   Total scenarios: {len(df)}")
    
    # Also save CSV
    csv_file = output_file.with_suffix('.csv')
    df.to_csv(csv_file, index=False)
    print(f"✅ Detailed metrics CSV saved: {csv_file}")


def main():
    """Main function."""
    script_dir = Path(__file__).parent.parent
    results_dir = script_dir / 'results' / 'latest'
    
    # Try to find results directory
    if not results_dir.exists():
        # Look for most recent results directory
        results_base = script_dir / 'results'
        if results_base.exists():
            dirs = sorted([d for d in results_base.iterdir() if d.is_dir()], reverse=True)
            if dirs:
                results_dir = dirs[0]
            else:
                print(f"Error: No results directory found")
                sys.exit(1)
        else:
            print(f"Error: Results directory not found: {results_dir}")
            sys.exit(1)
    
    print(f"Loading test results from: {results_dir}")
    
    results = load_test_results(results_dir)
    
    if not results:
        print("Error: No test results found")
        sys.exit(1)
    
    # Generate report
    output_file = results_dir / 'comprehensive_report.txt'
    generate_report(results, output_file)
    
    print(f"\nReport saved to: {output_file}")
    print(f"View with: cat {output_file}")


if __name__ == '__main__':
    main()

