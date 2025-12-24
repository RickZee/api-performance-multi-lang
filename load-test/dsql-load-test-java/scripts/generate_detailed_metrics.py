#!/usr/bin/env python3
"""
Generate detailed metrics and charts from test results.
"""

import sys
import json
import os
import glob
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
from typing import Dict, List, Optional

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (14, 10)
plt.rcParams['font.size'] = 11

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))


def load_test_results(results_dir: str) -> pd.DataFrame:
    """Load all test result JSON files into a DataFrame."""
    results = []
    results_path = Path(results_dir)
    
    for json_file in results_path.glob("test-*.json"):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            if not data or data == {}:
                continue
                
            config = data.get('configuration', {})
            test_id = data.get('test_id', json_file.stem)
            
            # Extract scenario results
            results_data = data.get('results', {})
            
            for scenario_key in ['scenario_1', 'scenario_2']:
                if scenario_key in results_data:
                    scenario_num = 1 if scenario_key == 'scenario_1' else 2
                    scenario_result = results_data[scenario_key]
                    
                    # Extract latency metrics if available
                    latency_stats = scenario_result.get('latency_stats', {})
                    pool_metrics = scenario_result.get('pool_metrics', {})
                    
                    row = {
                        'test_id': test_id,
                        'scenario': scenario_num,
                        'threads': config.get('threads', 0),
                        'iterations': config.get('iterations', 0),
                        'count': config.get('count', 0),
                        'batch_size': config.get('batch_size'),
                        'payload_size': config.get('payload_size', 'default'),
                        'total_success': scenario_result.get('total_success', 0),
                        'total_errors': scenario_result.get('total_errors', 0),
                        'duration_ms': scenario_result.get('duration_ms', 0),
                        'throughput_inserts_per_sec': scenario_result.get('throughput_inserts_per_sec', 0),
                        'avg_inserts_per_sec': scenario_result.get('avg_inserts_per_sec', 0),
                        'expected_rows': scenario_result.get('expected_rows', 0),
                        'actual_rows': scenario_result.get('actual_rows', 0),
                        'p50_latency_ms': latency_stats.get('p50', 0),
                        'p95_latency_ms': latency_stats.get('p95', 0),
                        'p99_latency_ms': latency_stats.get('p99', 0),
                        'max_latency_ms': latency_stats.get('max', 0),
                        'min_latency_ms': latency_stats.get('min', 0),
                        'avg_latency_ms': latency_stats.get('avg', 0),
                        'pool_size': pool_metrics.get('pool_size', 0),
                        'active_connections': pool_metrics.get('active_connections', 0),
                        'error_rate': scenario_result.get('total_errors', 0) / max(scenario_result.get('total_success', 0) + scenario_result.get('total_errors', 0), 1) * 100,
                    }
                    results.append(row)
        except Exception as e:
            print(f"Warning: Failed to load {json_file}: {e}", file=sys.stderr)
    
    if not results:
        print(f"Error: No valid test results found in {results_dir}")
        return pd.DataFrame()
    
    return pd.DataFrame(results)


def generate_summary_metrics(df: pd.DataFrame, output_dir: Path) -> Dict:
    """Generate summary metrics and save to JSON."""
    metrics = {
        'summary': {
            'total_tests': len(df),
            'scenario1_tests': len(df[df['scenario'] == 1]),
            'scenario2_tests': len(df[df['scenario'] == 2]),
            'total_successful_operations': int(df['total_success'].sum()),
            'total_errors': int(df['total_errors'].sum()),
            'overall_error_rate_pct': float(df['error_rate'].mean()),
        },
        'throughput': {
            'scenario1_max_throughput': float(df[df['scenario'] == 1]['throughput_inserts_per_sec'].max()) if len(df[df['scenario'] == 1]) > 0 else 0,
            'scenario1_avg_throughput': float(df[df['scenario'] == 1]['throughput_inserts_per_sec'].mean()) if len(df[df['scenario'] == 1]) > 0 else 0,
            'scenario2_max_throughput': float(df[df['scenario'] == 2]['throughput_inserts_per_sec'].max()) if len(df[df['scenario'] == 2]) > 0 else 0,
            'scenario2_avg_throughput': float(df[df['scenario'] == 2]['throughput_inserts_per_sec'].mean()) if len(df[df['scenario'] == 2]) > 0 else 0,
        },
        'latency': {
            'scenario1_p50_ms': float(df[df['scenario'] == 1]['p50_latency_ms'].mean()) if len(df[df['scenario'] == 1]) > 0 else 0,
            'scenario1_p95_ms': float(df[df['scenario'] == 1]['p95_latency_ms'].mean()) if len(df[df['scenario'] == 1]) > 0 else 0,
            'scenario1_p99_ms': float(df[df['scenario'] == 1]['p99_latency_ms'].mean()) if len(df[df['scenario'] == 1]) > 0 else 0,
            'scenario2_p50_ms': float(df[df['scenario'] == 2]['p50_latency_ms'].mean()) if len(df[df['scenario'] == 2]) > 0 else 0,
            'scenario2_p95_ms': float(df[df['scenario'] == 2]['p95_latency_ms'].mean()) if len(df[df['scenario'] == 2]) > 0 else 0,
            'scenario2_p99_ms': float(df[df['scenario'] == 2]['p99_latency_ms'].mean()) if len(df[df['scenario'] == 2]) > 0 else 0,
        },
        'generated_at': datetime.now().isoformat()
    }
    
    metrics_file = output_dir / 'metrics_summary.json'
    with open(metrics_file, 'w') as f:
        json.dump(metrics, f, indent=2)
    
    print(f"✓ Metrics summary saved to: {metrics_file}")
    return metrics


def generate_charts(df: pd.DataFrame, output_dir: Path):
    """Generate comprehensive performance charts."""
    charts_dir = output_dir / 'charts'
    charts_dir.mkdir(exist_ok=True)
    
    print(f"\nGenerating charts in: {charts_dir}")
    
    # 1. Throughput Comparison
    if len(df) > 0:
        fig, axes = plt.subplots(1, 2, figsize=(16, 6))
        
        for idx, scenario in enumerate([1, 2], 1):
            ax = axes[idx - 1]
            df_scenario = df[df['scenario'] == scenario]
            if len(df_scenario) > 0:
                if 'threads' in df_scenario.columns:
                    grouped = df_scenario.groupby('threads')['throughput_inserts_per_sec'].mean()
                    ax.plot(grouped.index, grouped.values, marker='o', linewidth=2, markersize=8)
                    ax.set_xlabel('Thread Count', fontsize=12)
                    ax.set_ylabel('Throughput (inserts/sec)', fontsize=12)
                    ax.set_title(f'Scenario {scenario}: Throughput vs Threads', fontsize=13, fontweight='bold')
                    ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(charts_dir / 'throughput_comparison.png', dpi=150, bbox_inches='tight')
        plt.close()
        print("  ✓ Throughput comparison chart")
    
    # 2. Latency Percentiles
    if len(df) > 0 and df['p50_latency_ms'].notna().any():
        fig, ax = plt.subplots(figsize=(14, 8))
        
        scenarios = df['scenario'].unique()
        x = range(len(scenarios))
        width = 0.25
        
        for scenario in sorted(scenarios):
            df_scenario = df[df['scenario'] == scenario]
            p50 = df_scenario['p50_latency_ms'].mean()
            p95 = df_scenario['p95_latency_ms'].mean()
            p99 = df_scenario['p99_latency_ms'].mean()
            
            idx = list(scenarios).index(scenario)
            ax.bar(idx - width, p50, width, label=f'S{int(scenario)} P50', alpha=0.8)
            ax.bar(idx, p95, width, label=f'S{int(scenario)} P95', alpha=0.8)
            ax.bar(idx + width, p99, width, label=f'S{int(scenario)} P99', alpha=0.8)
        
        ax.set_xlabel('Scenario', fontsize=12)
        ax.set_ylabel('Latency (ms)', fontsize=12)
        ax.set_title('Latency Percentiles by Scenario', fontsize=14, fontweight='bold')
        ax.set_xticks(range(len(scenarios)))
        ax.set_xticklabels([f'Scenario {int(s)}' for s in scenarios])
        ax.legend()
        ax.grid(True, alpha=0.3, axis='y')
        plt.tight_layout()
        plt.savefig(charts_dir / 'latency_percentiles.png', dpi=150, bbox_inches='tight')
        plt.close()
        print("  ✓ Latency percentiles chart")
    
    # 3. Error Rate Analysis
    if len(df) > 0:
        fig, ax = plt.subplots(figsize=(12, 8))
        
        for scenario in sorted(df['scenario'].unique()):
            df_scenario = df[df['scenario'] == scenario]
            if 'threads' in df_scenario.columns:
                grouped = df_scenario.groupby('threads')['error_rate'].mean()
                ax.plot(grouped.index, grouped.values, marker='o', linewidth=2, 
                       label=f'Scenario {int(scenario)}', markersize=8)
        
        ax.set_xlabel('Thread Count', fontsize=12)
        ax.set_ylabel('Error Rate (%)', fontsize=12)
        ax.set_title('Error Rate vs Thread Count', fontsize=14, fontweight='bold')
        ax.legend()
        ax.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(charts_dir / 'error_rate_analysis.png', dpi=150, bbox_inches='tight')
        plt.close()
        print("  ✓ Error rate analysis chart")
    
    # 4. Throughput vs Batch Size (Scenario 2)
    df2 = df[df['scenario'] == 2]
    if len(df2) > 0 and 'batch_size' in df2.columns and df2['batch_size'].notna().any():
        fig, ax = plt.subplots(figsize=(12, 8))
        batch_data = df2[df2['batch_size'].notna()].groupby('batch_size')['throughput_inserts_per_sec'].mean()
        ax.bar(batch_data.index, batch_data.values, color='steelblue', alpha=0.7, width=0.6)
        ax.set_xlabel('Batch Size', fontsize=12)
        ax.set_ylabel('Throughput (inserts/sec)', fontsize=12)
        ax.set_title('Scenario 2: Throughput vs Batch Size', fontsize=14, fontweight='bold')
        ax.grid(True, alpha=0.3, axis='y')
        plt.tight_layout()
        plt.savefig(charts_dir / 'throughput_vs_batch_size.png', dpi=150, bbox_inches='tight')
        plt.close()
        print("  ✓ Throughput vs batch size chart")
    
    # 5. Performance Summary Dashboard
    fig = plt.figure(figsize=(16, 12))
    gs = fig.add_gridspec(3, 2, hspace=0.3, wspace=0.3)
    
    # Throughput by scenario
    ax1 = fig.add_subplot(gs[0, 0])
    if len(df) > 0:
        scenario_throughput = df.groupby('scenario')['throughput_inserts_per_sec'].mean()
        ax1.bar(scenario_throughput.index, scenario_throughput.values, color=['#3498db', '#e74c3c'], alpha=0.7)
        ax1.set_xlabel('Scenario')
        ax1.set_ylabel('Avg Throughput (inserts/sec)')
        ax1.set_title('Average Throughput by Scenario')
        ax1.grid(True, alpha=0.3, axis='y')
    
    # Latency distribution
    ax2 = fig.add_subplot(gs[0, 1])
    if len(df) > 0 and df['p95_latency_ms'].notna().any():
        for scenario in sorted(df['scenario'].unique()):
            df_scenario = df[df['scenario'] == scenario]
            ax2.hist(df_scenario['p95_latency_ms'].dropna(), alpha=0.6, label=f'S{int(scenario)}', bins=10)
        ax2.set_xlabel('P95 Latency (ms)')
        ax2.set_ylabel('Frequency')
        ax2.set_title('P95 Latency Distribution')
        ax2.legend()
        ax2.grid(True, alpha=0.3, axis='y')
    
    # Success vs Errors
    ax3 = fig.add_subplot(gs[1, 0])
    if len(df) > 0:
        total_success = df['total_success'].sum()
        total_errors = df['total_errors'].sum()
        ax3.pie([total_success, total_errors], labels=['Success', 'Errors'], 
               autopct='%1.1f%%', colors=['#2ecc71', '#e74c3c'], startangle=90)
        ax3.set_title('Overall Success vs Errors')
    
    # Throughput over time (by test order)
    ax4 = fig.add_subplot(gs[1, 1])
    if len(df) > 0:
        df_sorted = df.sort_values('test_id')
        for scenario in sorted(df['scenario'].unique()):
            df_scenario = df_sorted[df_sorted['scenario'] == scenario]
            ax4.plot(range(len(df_scenario)), df_scenario['throughput_inserts_per_sec'], 
                    marker='o', label=f'S{int(scenario)}', linewidth=2, markersize=6)
        ax4.set_xlabel('Test Order')
        ax4.set_ylabel('Throughput (inserts/sec)')
        ax4.set_title('Throughput by Test Order')
        ax4.legend()
        ax4.grid(True, alpha=0.3)
    
    # Error rate by scenario
    ax5 = fig.add_subplot(gs[2, :])
    if len(df) > 0:
        error_by_scenario = df.groupby('scenario')['error_rate'].mean()
        ax5.bar(error_by_scenario.index, error_by_scenario.values, 
               color=['#3498db', '#e74c3c'], alpha=0.7, width=0.5)
        ax5.set_xlabel('Scenario')
        ax5.set_ylabel('Average Error Rate (%)')
        ax5.set_title('Average Error Rate by Scenario')
        ax5.grid(True, alpha=0.3, axis='y')
    
    plt.suptitle('Performance Test Dashboard', fontsize=16, fontweight='bold', y=0.995)
    plt.savefig(charts_dir / 'performance_dashboard.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  ✓ Performance dashboard")
    
    print(f"\n✓ All charts generated in: {charts_dir}")


def generate_csv_summary(df: pd.DataFrame, output_dir: Path):
    """Generate CSV summary of results."""
    csv_file = output_dir / 'results_summary.csv'
    df.to_csv(csv_file, index=False)
    print(f"✓ CSV summary saved to: {csv_file}")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate detailed metrics and charts from test results')
    parser.add_argument('results_dir', nargs='?', default='results/latest',
                       help='Results directory to analyze (default: results/latest)')
    parser.add_argument('--output-dir', help='Output directory for charts (default: same as results_dir)')
    
    args = parser.parse_args()
    
    results_dir = Path(args.results_dir)
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    output_dir = Path(args.output_dir) if args.output_dir else results_dir
    
    print("=" * 80)
    print("Generating Detailed Metrics and Charts")
    print("=" * 80)
    print(f"Results directory: {results_dir}")
    print(f"Output directory: {output_dir}")
    print()
    
    # Load results
    print("Loading test results...")
    df = load_test_results(str(results_dir))
    
    if df.empty:
        print("No test results found!")
        sys.exit(1)
    
    print(f"✓ Loaded {len(df)} test results")
    print(f"  Scenario 1: {len(df[df['scenario'] == 1])} tests")
    print(f"  Scenario 2: {len(df[df['scenario'] == 2])} tests")
    print()
    
    # Generate metrics
    print("Generating summary metrics...")
    metrics = generate_summary_metrics(df, output_dir)
    
    # Print key metrics
    print("\n" + "=" * 80)
    print("Key Metrics Summary")
    print("=" * 80)
    print(f"Total Tests: {metrics['summary']['total_tests']}")
    print(f"Total Successful Operations: {metrics['summary']['total_successful_operations']:,}")
    print(f"Total Errors: {metrics['summary']['total_errors']:,}")
    print(f"Overall Error Rate: {metrics['summary']['overall_error_rate_pct']:.2f}%")
    print()
    print("Throughput:")
    print(f"  Scenario 1 - Max: {metrics['throughput']['scenario1_max_throughput']:.0f} inserts/sec")
    print(f"  Scenario 1 - Avg: {metrics['throughput']['scenario1_avg_throughput']:.0f} inserts/sec")
    print(f"  Scenario 2 - Max: {metrics['throughput']['scenario2_max_throughput']:.0f} inserts/sec")
    print(f"  Scenario 2 - Avg: {metrics['throughput']['scenario2_avg_throughput']:.0f} inserts/sec")
    print()
    print("Latency (P95):")
    print(f"  Scenario 1: {metrics['latency']['scenario1_p95_ms']:.2f} ms")
    print(f"  Scenario 2: {metrics['latency']['scenario2_p95_ms']:.2f} ms")
    print()
    
    # Generate charts
    generate_charts(df, output_dir)
    
    # Generate CSV
    generate_csv_summary(df, output_dir)
    
    print()
    print("=" * 80)
    print("✓ Metrics and charts generation complete!")
    print("=" * 80)
    print(f"\nView charts in: {output_dir / 'charts'}")
    print(f"View metrics in: {output_dir / 'metrics_summary.json'}")
    print(f"View CSV in: {output_dir / 'results_summary.csv'}")


if __name__ == '__main__':
    main()

