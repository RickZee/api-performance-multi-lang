#!/usr/bin/env python3
"""
Analyze DSQL performance test results and generate charts.
"""

import json
import os
import sys
import glob
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from typing import List, Dict, Optional

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 8)


def load_test_results(results_dir: str) -> pd.DataFrame:
    """Load all test result JSON files into a DataFrame."""
    results = []
    
    for json_file in glob.glob(os.path.join(results_dir, "test-*.json")):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
                
            config = data.get('configuration', {})
            test_id = data.get('test_id', '')
            
            # Extract scenario results
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
                        'avg_inserts_per_sec': scenario_result.get('avg_inserts_per_sec', 0),
                        'expected_rows': scenario_result.get('expected_rows', 0),
                        'actual_rows': scenario_result.get('actual_rows', 0),
                    }
                    results.append(row)
        except Exception as e:
            print(f"Warning: Failed to load {json_file}: {e}", file=sys.stderr)
    
    return pd.DataFrame(results)


def parse_payload_size(payload_str: str) -> int:
    """Parse payload size string to bytes."""
    if not payload_str or payload_str == 'default':
        return 665  # Default size in bytes
    if 'KB' in payload_str:
        return int(float(payload_str.replace(' bytes (', '').replace(' KB)', '')) * 1024)
    if 'bytes' in payload_str:
        return int(payload_str.replace(' bytes', '').split('(')[0].strip())
    return 665


def generate_charts(df: pd.DataFrame, output_dir: str):
    """Generate all performance charts."""
    charts_dir = os.path.join(output_dir, 'charts')
    os.makedirs(charts_dir, exist_ok=True)
    
    # Normalize payload size for analysis
    df['payload_bytes'] = df['payload_size'].apply(parse_payload_size)
    
    # 1. Throughput vs Thread Count (Scenario 1)
    if len(df[df['scenario'] == 1]) > 0:
        fig, ax = plt.subplots(figsize=(12, 8))
        df1 = df[df['scenario'] == 1]
        for iterations in sorted(df1['iterations'].unique()):
            subset = df1[df1['iterations'] == iterations]
            ax.plot(subset['threads'], subset['throughput_inserts_per_sec'], 
                   marker='o', label=f'{iterations} iterations', linewidth=2)
        ax.set_xlabel('Thread Count', fontsize=12)
        ax.set_ylabel('Throughput (inserts/second)', fontsize=12)
        ax.set_title('Scenario 1: Throughput vs Thread Count', fontsize=14, fontweight='bold')
        ax.legend()
        ax.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(charts_dir, 'scenario1_throughput_vs_threads.png'), dpi=150)
        plt.close()
    
    # 2. Throughput vs Thread Count (Scenario 2)
    if len(df[df['scenario'] == 2]) > 0:
        fig, ax = plt.subplots(figsize=(12, 8))
        df2 = df[df['scenario'] == 2]
        for iterations in sorted(df2['iterations'].unique()):
            subset = df2[df2['iterations'] == iterations]
            ax.plot(subset['threads'], subset['throughput_inserts_per_sec'], 
                   marker='o', label=f'{iterations} iterations', linewidth=2)
        ax.set_xlabel('Thread Count', fontsize=12)
        ax.set_ylabel('Throughput (inserts/second)', fontsize=12)
        ax.set_title('Scenario 2: Throughput vs Thread Count', fontsize=14, fontweight='bold')
        ax.legend()
        ax.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(charts_dir, 'scenario2_throughput_vs_threads.png'), dpi=150)
        plt.close()
    
    # 3. Throughput vs Batch Size (Scenario 2)
    if len(df[df['scenario'] == 2]) > 0:
        df2 = df[df['scenario'] == 2]
        if 'batch_size' in df2.columns and df2['batch_size'].notna().any():
            fig, ax = plt.subplots(figsize=(12, 8))
            batch_data = df2[df2['batch_size'].notna()]
            ax.bar(batch_data['batch_size'], batch_data['throughput_inserts_per_sec'], 
                  color='steelblue', alpha=0.7)
            ax.set_xlabel('Batch Size', fontsize=12)
            ax.set_ylabel('Throughput (inserts/second)', fontsize=12)
            ax.set_title('Scenario 2: Throughput vs Batch Size', fontsize=14, fontweight='bold')
            ax.grid(True, alpha=0.3, axis='y')
            plt.tight_layout()
            plt.savefig(os.path.join(charts_dir, 'scenario2_throughput_vs_batch_size.png'), dpi=150)
            plt.close()
    
    # 4. Throughput vs Payload Size
    fig, ax = plt.subplots(figsize=(12, 8))
    for scenario in [1, 2]:
        subset = df[df['scenario'] == scenario]
        if len(subset) > 0:
            payload_data = subset.groupby('payload_bytes')['throughput_inserts_per_sec'].mean()
            ax.plot(payload_data.index, payload_data.values, 
                   marker='o', label=f'Scenario {scenario}', linewidth=2)
    ax.set_xlabel('Payload Size (bytes)', fontsize=12)
    ax.set_ylabel('Throughput (inserts/second)', fontsize=12)
    ax.set_title('Throughput vs Payload Size', fontsize=14, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_xscale('log')
    plt.tight_layout()
    plt.savefig(os.path.join(charts_dir, 'throughput_vs_payload_size.png'), dpi=150)
    plt.close()
    
    # 5. Duration vs Thread Count
    fig, ax = plt.subplots(figsize=(12, 8))
    for scenario in [1, 2]:
        subset = df[df['scenario'] == scenario]
        if len(subset) > 0:
            duration_data = subset.groupby('threads')['duration_ms'].mean() / 1000  # Convert to seconds
            ax.plot(duration_data.index, duration_data.values, 
                   marker='o', label=f'Scenario {scenario}', linewidth=2)
    ax.set_xlabel('Thread Count', fontsize=12)
    ax.set_ylabel('Duration (seconds)', fontsize=12)
    ax.set_title('Duration vs Thread Count', fontsize=14, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(charts_dir, 'duration_vs_threads.png'), dpi=150)
    plt.close()
    
    # 6. Scenario 1 vs Scenario 2 Comparison
    if len(df[df['scenario'] == 1]) > 0 and len(df[df['scenario'] == 2]) > 0:
        fig, ax = plt.subplots(figsize=(12, 8))
        comparison_data = df.groupby(['scenario', 'threads'])['throughput_inserts_per_sec'].mean().unstack()
        comparison_data.plot(kind='bar', ax=ax, width=0.8)
        ax.set_xlabel('Thread Count', fontsize=12)
        ax.set_ylabel('Throughput (inserts/second)', fontsize=12)
        ax.set_title('Scenario 1 vs Scenario 2: Throughput Comparison', fontsize=14, fontweight='bold')
        ax.legend(title='Scenario')
        ax.grid(True, alpha=0.3, axis='y')
        plt.xticks(rotation=0)
        plt.tight_layout()
        plt.savefig(os.path.join(charts_dir, 'scenario_comparison.png'), dpi=150)
        plt.close()
    
    # 7. Error Rate Analysis
    if df['total_errors'].sum() > 0:
        fig, ax = plt.subplots(figsize=(12, 8))
        error_data = df.groupby(['scenario', 'threads'])['total_errors'].sum().unstack()
        error_data.plot(kind='bar', ax=ax, width=0.8, color=['red', 'orange'])
        ax.set_xlabel('Thread Count', fontsize=12)
        ax.set_ylabel('Total Errors', fontsize=12)
        ax.set_title('Error Rate vs Thread Count', fontsize=14, fontweight='bold')
        ax.legend(title='Scenario')
        ax.grid(True, alpha=0.3, axis='y')
        plt.xticks(rotation=0)
        plt.tight_layout()
        plt.savefig(os.path.join(charts_dir, 'error_rate_analysis.png'), dpi=150)
        plt.close()
    
    # 8. Heatmap: Throughput (Threads × Iterations) - Scenario 1
    if len(df[df['scenario'] == 1]) > 0:
        df1 = df[df['scenario'] == 1]
        pivot_data = df1.pivot_table(values='throughput_inserts_per_sec', 
                                     index='iterations', columns='threads', aggfunc='mean')
        if not pivot_data.empty:
            fig, ax = plt.subplots(figsize=(12, 8))
            sns.heatmap(pivot_data, annot=True, fmt='.1f', cmap='YlOrRd', ax=ax, cbar_kws={'label': 'Throughput (inserts/sec)'})
            ax.set_title('Scenario 1: Throughput Heatmap (Iterations × Threads)', fontsize=14, fontweight='bold')
            ax.set_xlabel('Thread Count', fontsize=12)
            ax.set_ylabel('Iterations', fontsize=12)
            plt.tight_layout()
            plt.savefig(os.path.join(charts_dir, 'scenario1_throughput_heatmap.png'), dpi=150)
            plt.close()
    
    print(f"Generated {len(glob.glob(os.path.join(charts_dir, '*.png')))} charts in {charts_dir}")


def main():
    if len(sys.argv) < 2:
        print("Usage: analyze-results.py <results_directory>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    if not os.path.isdir(results_dir):
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    print(f"Loading test results from: {results_dir}")
    df = load_test_results(results_dir)
    
    if df.empty:
        print("No test results found!")
        sys.exit(1)
    
    print(f"Loaded {len(df)} test result records")
    print(f"Scenarios: {sorted(df['scenario'].unique().tolist())}")
    print(f"Thread counts: {sorted(df['threads'].unique().tolist())}")
    print(f"Iterations: {sorted(df['iterations'].unique().tolist())}")
    print()
    
    # Generate summary CSV
    csv_file = os.path.join(results_dir, 'summary.csv')
    df.to_csv(csv_file, index=False)
    print(f"Summary CSV saved to: {csv_file}")
    
    # Generate charts
    print("\nGenerating charts...")
    generate_charts(df, results_dir)
    
    print("\nAnalysis complete!")


if __name__ == '__main__':
    main()

