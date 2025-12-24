#!/usr/bin/env python3
"""
Comprehensive chart generation for DSQL load test results.
Creates multiple visualization types based on test data.
"""

import json
import glob
import os
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
import pandas as pd
from collections import defaultdict
import statistics

# Set style
plt.style.use('seaborn-v0_8-darkgrid')
matplotlib.rcParams['figure.figsize'] = (14, 8)
matplotlib.rcParams['font.size'] = 10

def load_test_results(results_dir):
    """Load all test result JSON files."""
    files = sorted(glob.glob(f"{results_dir}/*.json"))
    tests = []
    
    for f in files:
        try:
            with open(f) as jf:
                data = json.load(jf)
                tests.append(data)
        except Exception as e:
            print(f"Warning: Could not load {f}: {e}")
    
    return tests

def create_throughput_scaling_chart(tests, output_dir):
    """Chart 1: Throughput vs Thread Count (Scaling Analysis)"""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    # Scenario 1
    s1_tests = [t for t in tests if t.get('configuration', {}).get('scenario') == 1]
    s1_tests.sort(key=lambda x: x.get('configuration', {}).get('threads', 0))
    
    if s1_tests:
        threads_s1 = [t.get('configuration', {}).get('threads', 0) for t in s1_tests]
        throughput_s1 = [t.get('results', {}).get('scenario_1', {}).get('throughput_inserts_per_sec', 0) for t in s1_tests]
        
        ax1.plot(threads_s1, throughput_s1, 'o-', linewidth=2, markersize=8, label='Scenario 1 (Individual)')
        ax1.set_xlabel('Thread Count', fontsize=12, fontweight='bold')
        ax1.set_ylabel('Throughput (inserts/sec)', fontsize=12, fontweight='bold')
        ax1.set_title('Scenario 1: Individual Inserts - Throughput Scaling', fontsize=14, fontweight='bold')
        ax1.grid(True, alpha=0.3)
        ax1.legend()
    
    # Scenario 2
    s2_tests = [t for t in tests if t.get('configuration', {}).get('scenario') == 2]
    s2_tests.sort(key=lambda x: x.get('configuration', {}).get('threads', 0))
    
    if s2_tests:
        threads_s2 = [t.get('configuration', {}).get('threads', 0) for t in s2_tests]
        throughput_s2 = [t.get('results', {}).get('scenario_2', {}).get('throughput_inserts_per_sec', 0) for t in s2_tests]
        
        ax2.plot(threads_s2, throughput_s2, 's-', linewidth=2, markersize=8, color='green', label='Scenario 2 (Batch)')
        ax2.set_xlabel('Thread Count', fontsize=12, fontweight='bold')
        ax2.set_ylabel('Throughput (inserts/sec)', fontsize=12, fontweight='bold')
        ax2.set_title('Scenario 2: Batch Inserts - Throughput Scaling', fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3)
        ax2.legend()
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/throughput_scaling.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: throughput_scaling.png")

def create_efficiency_chart(tests, output_dir):
    """Chart 2: Efficiency (Ops/Thread) vs Thread Count"""
    fig, ax = plt.subplots(figsize=(12, 7))
    
    s2_tests = [t for t in tests if t.get('configuration', {}).get('scenario') == 2]
    s2_tests.sort(key=lambda x: x.get('configuration', {}).get('threads', 0))
    
    if s2_tests:
        threads = []
        efficiency = []
        
        for t in s2_tests:
            config = t.get('configuration', {})
            results = t.get('results', {}).get('scenario_2', {})
            thread_count = config.get('threads', 0)
            throughput = results.get('throughput_inserts_per_sec', 0)
            if thread_count > 0:
                threads.append(thread_count)
                efficiency.append(throughput / thread_count)
        
        ax.plot(threads, efficiency, 'o-', linewidth=2, markersize=10, color='purple')
        ax.set_xlabel('Thread Count', fontsize=12, fontweight='bold')
        ax.set_ylabel('Efficiency (ops/sec per thread)', fontsize=12, fontweight='bold')
        ax.set_title('Scenario 2: Efficiency vs Thread Count', fontsize=14, fontweight='bold')
        ax.grid(True, alpha=0.3)
        
        # Highlight peak
        if efficiency:
            max_idx = efficiency.index(max(efficiency))
            ax.plot(threads[max_idx], efficiency[max_idx], 'ro', markersize=15, label=f'Peak: {efficiency[max_idx]:.2f} ops/thread')
            ax.legend()
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/efficiency_analysis.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: efficiency_analysis.png")

def create_comparison_chart(tests, output_dir):
    """Chart 3: Scenario 1 vs Scenario 2 Comparison"""
    fig, ax = plt.subplots(figsize=(14, 8))
    
    # Group by thread count
    s1_by_threads = defaultdict(list)
    s2_by_threads = defaultdict(list)
    
    for t in tests:
        config = t.get('configuration', {})
        scenario = config.get('scenario', 0)
        threads = config.get('threads', 0)
        
        if scenario == 1:
            throughput = t.get('results', {}).get('scenario_1', {}).get('throughput_inserts_per_sec', 0)
            if throughput > 0:
                s1_by_threads[threads].append(throughput)
        elif scenario == 2:
            throughput = t.get('results', {}).get('scenario_2', {}).get('throughput_inserts_per_sec', 0)
            if throughput > 0:
                s2_by_threads[threads].append(throughput)
    
    # Get average throughput per thread count
    threads_s1 = sorted(s1_by_threads.keys())
    threads_s2 = sorted(s2_by_threads.keys())
    
    avg_s1 = [statistics.mean(s1_by_threads[t]) for t in threads_s1]
    avg_s2 = [statistics.mean(s2_by_threads[t]) for t in threads_s2]
    
    if threads_s1:
        ax.plot(threads_s1, avg_s1, 'o-', linewidth=2, markersize=10, label='Scenario 1 (Individual)', color='blue')
    if threads_s2:
        ax.plot(threads_s2, avg_s2, 's-', linewidth=2, markersize=10, label='Scenario 2 (Batch)', color='green')
    
    ax.set_xlabel('Thread Count', fontsize=12, fontweight='bold')
    ax.set_ylabel('Throughput (inserts/sec)', fontsize=12, fontweight='bold')
    ax.set_title('Performance Comparison: Individual vs Batch Inserts', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=11)
    ax.set_xscale('log')
    ax.set_yscale('log')
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/scenario_comparison.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: scenario_comparison.png")

def create_thread_distribution_chart(tests, output_dir):
    """Chart 4: Thread-Level Performance Distribution (for high-thread tests)"""
    # Find test with most threads
    max_threads_test = None
    max_threads = 0
    
    for t in tests:
        config = t.get('configuration', {})
        threads = config.get('threads', 0)
        if threads > max_threads:
            max_threads = threads
            max_threads_test = t
    
    if not max_threads_test or max_threads < 100:
        print("⚠️  Skipping thread distribution chart (no high-thread test found)")
        return
    
    results = max_threads_test.get('results', {})
    s2 = results.get('scenario_2', {})
    if not s2:
        s1 = results.get('scenario_1', {})
        if not s1:
            return
        thread_results = s1.get('thread_results', {})
    else:
        thread_results = s2.get('thread_results', {})
    
    if not thread_results:
        return
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    # Collect throughput data
    throughputs = []
    durations = []
    
    for thread_id, thread_data in thread_results.items():
        throughput = thread_data.get('inserts_per_sec', 0)
        duration = thread_data.get('duration_ms', 0)
        if throughput > 0:
            throughputs.append(throughput)
        if duration > 0:
            durations.append(duration)
    
    if throughputs:
        ax1.hist(throughputs, bins=50, edgecolor='black', alpha=0.7, color='steelblue')
        ax1.axvline(statistics.mean(throughputs), color='red', linestyle='--', linewidth=2, label=f'Mean: {statistics.mean(throughputs):.2f}')
        ax1.axvline(statistics.median(throughputs), color='green', linestyle='--', linewidth=2, label=f'Median: {statistics.median(throughputs):.2f}')
        ax1.set_xlabel('Throughput (inserts/sec per thread)', fontsize=12, fontweight='bold')
        ax1.set_ylabel('Frequency', fontsize=12, fontweight='bold')
        ax1.set_title(f'Thread Throughput Distribution\n({max_threads} threads)', fontsize=14, fontweight='bold')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
    
    if durations:
        ax2.hist(durations, bins=50, edgecolor='black', alpha=0.7, color='coral')
        ax2.axvline(statistics.mean(durations), color='red', linestyle='--', linewidth=2, label=f'Mean: {statistics.mean(durations):.2f}ms')
        ax2.axvline(statistics.median(durations), color='green', linestyle='--', linewidth=2, label=f'Median: {statistics.median(durations):.2f}ms')
        ax2.set_xlabel('Duration (ms per thread)', fontsize=12, fontweight='bold')
        ax2.set_ylabel('Frequency', fontsize=12, fontweight='bold')
        ax2.set_title(f'Thread Duration Distribution\n({max_threads} threads)', fontsize=14, fontweight='bold')
        ax2.legend()
        ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/thread_distribution.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: thread_distribution.png")

def create_batch_size_impact_chart(tests, output_dir):
    """Chart 5: Batch Size Impact on Throughput"""
    s2_tests = [t for t in tests if t.get('configuration', {}).get('scenario') == 2]
    
    if not s2_tests:
        print("⚠️  Skipping batch size chart (no Scenario 2 tests)")
        return
    
    # Group by batch size
    batch_data = defaultdict(list)
    
    for t in s2_tests:
        config = t.get('configuration', {})
        batch_size = config.get('batch_size') or config.get('count', 0)
        throughput = t.get('results', {}).get('scenario_2', {}).get('throughput_inserts_per_sec', 0)
        if batch_size > 0 and throughput > 0:
            batch_data[batch_size].append(throughput)
    
    if not batch_data:
        return
    
    batch_sizes = sorted(batch_data.keys())
    avg_throughput = [statistics.mean(batch_data[bs]) for bs in batch_sizes]
    
    fig, ax = plt.subplots(figsize=(12, 7))
    
    ax.bar(batch_sizes, avg_throughput, color='teal', alpha=0.7, edgecolor='black')
    ax.set_xlabel('Batch Size', fontsize=12, fontweight='bold')
    ax.set_ylabel('Average Throughput (inserts/sec)', fontsize=12, fontweight='bold')
    ax.set_title('Batch Size Impact on Throughput (Scenario 2)', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/batch_size_impact.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: batch_size_impact.png")

def create_error_analysis_chart(tests, output_dir):
    """Chart 6: Error Rate Analysis"""
    fig, ax = plt.subplots(figsize=(12, 7))
    
    test_ids = []
    error_rates = []
    success_rates = []
    
    for t in sorted(tests, key=lambda x: x.get('test_id', '')):
        test_id = t.get('test_id', 'unknown')
        results = t.get('results', {})
        s1 = results.get('scenario_1', {})
        s2 = results.get('scenario_2', {})
        scenario_results = s2 if s2 else s1
        
        total_success = scenario_results.get('total_success', 0)
        total_errors = scenario_results.get('total_errors', 0)
        total = total_success + total_errors
        
        if total > 0:
            error_rate = (total_errors / total) * 100
            success_rate = (total_success / total) * 100
            test_ids.append(test_id)
            error_rates.append(error_rate)
            success_rates.append(success_rate)
    
    if test_ids:
        x = np.arange(len(test_ids))
        width = 0.35
        
        ax.bar(x - width/2, success_rates, width, label='Success Rate (%)', color='green', alpha=0.7)
        ax.bar(x + width/2, error_rates, width, label='Error Rate (%)', color='red', alpha=0.7)
        
        ax.set_xlabel('Test ID', fontsize=12, fontweight='bold')
        ax.set_ylabel('Rate (%)', fontsize=12, fontweight='bold')
        ax.set_title('Success vs Error Rates by Test', fontsize=14, fontweight='bold')
        ax.set_xticks(x)
        ax.set_xticklabels(test_ids, rotation=45, ha='right')
        ax.legend()
        ax.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/error_analysis.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: error_analysis.png")

def create_summary_dashboard(tests, output_dir):
    """Chart 7: Summary Dashboard with Key Metrics"""
    fig = plt.figure(figsize=(16, 10))
    gs = fig.add_gridspec(3, 3, hspace=0.3, wspace=0.3)
    
    # Calculate summary statistics
    total_tests = len(tests)
    total_success = sum(
        (t.get('results', {}).get('scenario_1', {}).get('total_success', 0) +
         t.get('results', {}).get('scenario_2', {}).get('total_success', 0))
        for t in tests
    )
    total_errors = sum(
        (t.get('results', {}).get('scenario_1', {}).get('total_errors', 0) +
         t.get('results', {}).get('scenario_2', {}).get('total_errors', 0))
        for t in tests
    )
    
    # Get throughputs
    throughputs_s1 = [t.get('results', {}).get('scenario_1', {}).get('throughput_inserts_per_sec', 0) 
                      for t in tests if t.get('results', {}).get('scenario_1', {})]
    throughputs_s2 = [t.get('results', {}).get('scenario_2', {}).get('throughput_inserts_per_sec', 0) 
                      for t in tests if t.get('results', {}).get('scenario_2', {})]
    
    # 1. Summary text
    ax1 = fig.add_subplot(gs[0, :])
    ax1.axis('off')
    summary_text = f"""
    TEST SUITE SUMMARY
    =================
    Total Tests: {total_tests}
    Total Operations: {total_success:,}
    Total Errors: {total_errors:,}
    Success Rate: {(total_success/(total_success+total_errors)*100) if (total_success+total_errors) > 0 else 100:.2f}%
    
    Peak Throughput (Scenario 1): {max(throughputs_s1) if throughputs_s1 else 0:,.0f} ops/sec
    Peak Throughput (Scenario 2): {max(throughputs_s2) if throughputs_s2 else 0:,.0f} ops/sec
    """
    ax1.text(0.1, 0.5, summary_text, fontsize=14, verticalalignment='center', 
             family='monospace', fontweight='bold')
    
    # 2. Throughput comparison pie
    ax2 = fig.add_subplot(gs[1, 0])
    if throughputs_s1 and throughputs_s2:
        max_s1 = max(throughputs_s1)
        max_s2 = max(throughputs_s2)
        ax2.pie([max_s1, max_s2], labels=['Scenario 1', 'Scenario 2'], 
                autopct='%1.1f%%', startangle=90, colors=['lightblue', 'lightgreen'])
        ax2.set_title('Peak Throughput Comparison', fontweight='bold')
    
    # 3. Success/Error pie
    ax3 = fig.add_subplot(gs[1, 1])
    if total_success + total_errors > 0:
        ax3.pie([total_success, total_errors], labels=['Success', 'Errors'], 
                autopct='%1.2f%%', startangle=90, colors=['green', 'red'])
        ax3.set_title('Overall Success Rate', fontweight='bold')
    
    # 4. Test count by scenario
    ax4 = fig.add_subplot(gs[1, 2])
    s1_count = len([t for t in tests if t.get('configuration', {}).get('scenario') == 1])
    s2_count = len([t for t in tests if t.get('configuration', {}).get('scenario') == 2])
    ax4.bar(['Scenario 1', 'Scenario 2'], [s1_count, s2_count], 
            color=['lightblue', 'lightgreen'], edgecolor='black')
    ax4.set_ylabel('Number of Tests', fontweight='bold')
    ax4.set_title('Tests by Scenario', fontweight='bold')
    ax4.grid(True, alpha=0.3, axis='y')
    
    # 5. Throughput distribution
    ax5 = fig.add_subplot(gs[2, :])
    all_throughputs = throughputs_s1 + throughputs_s2
    if all_throughputs:
        ax5.hist(all_throughputs, bins=30, edgecolor='black', alpha=0.7, color='steelblue')
        ax5.axvline(statistics.mean(all_throughputs), color='red', linestyle='--', 
                   linewidth=2, label=f'Mean: {statistics.mean(all_throughputs):,.0f}')
        ax5.set_xlabel('Throughput (inserts/sec)', fontweight='bold')
        ax5.set_ylabel('Frequency', fontweight='bold')
        ax5.set_title('Throughput Distribution (All Tests)', fontweight='bold')
        ax5.legend()
        ax5.grid(True, alpha=0.3)
    
    plt.suptitle('DSQL Load Test Suite - Summary Dashboard', fontsize=16, fontweight='bold', y=0.98)
    plt.savefig(f"{output_dir}/summary_dashboard.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: summary_dashboard.png")

def create_latency_percentile_chart(tests, output_dir):
    """Chart: Latency Percentiles (P50, P95, P99) across tests"""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    # Scenario 1
    s1_tests = [t for t in tests if t.get('configuration', {}).get('scenario') == 1]
    s1_tests.sort(key=lambda x: x.get('configuration', {}).get('threads', 0))
    
    if s1_tests:
        threads_s1 = [t.get('configuration', {}).get('threads', 0) for t in s1_tests]
        p50_s1 = []
        p95_s1 = []
        p99_s1 = []
        
        for t in s1_tests:
            latency_stats = t.get('results', {}).get('scenario_1', {}).get('latency_stats', {})
            p50_s1.append(latency_stats.get('p50_latency_ms', 0))
            p95_s1.append(latency_stats.get('p95_latency_ms', 0))
            p99_s1.append(latency_stats.get('p99_latency_ms', 0))
        
        ax1.plot(threads_s1, p50_s1, 'o-', linewidth=2, markersize=6, label='P50', color='blue')
        ax1.plot(threads_s1, p95_s1, 's-', linewidth=2, markersize=6, label='P95', color='orange')
        ax1.plot(threads_s1, p99_s1, '^-', linewidth=2, markersize=6, label='P99', color='red')
        ax1.set_xlabel('Thread Count', fontsize=12, fontweight='bold')
        ax1.set_ylabel('Latency (ms)', fontsize=12, fontweight='bold')
        ax1.set_title('Scenario 1: Latency Percentiles', fontsize=14, fontweight='bold')
        ax1.grid(True, alpha=0.3)
        ax1.legend()
        ax1.set_yscale('log')
    
    # Scenario 2
    s2_tests = [t for t in tests if t.get('configuration', {}).get('scenario') == 2]
    s2_tests.sort(key=lambda x: x.get('configuration', {}).get('threads', 0))
    
    if s2_tests:
        threads_s2 = [t.get('configuration', {}).get('threads', 0) for t in s2_tests]
        p50_s2 = []
        p95_s2 = []
        p99_s2 = []
        
        for t in s2_tests:
            latency_stats = t.get('results', {}).get('scenario_2', {}).get('latency_stats', {})
            p50_s2.append(latency_stats.get('p50_latency_ms', 0))
            p95_s2.append(latency_stats.get('p95_latency_ms', 0))
            p99_s2.append(latency_stats.get('p99_latency_ms', 0))
        
        ax2.plot(threads_s2, p50_s2, 'o-', linewidth=2, markersize=6, label='P50', color='blue')
        ax2.plot(threads_s2, p95_s2, 's-', linewidth=2, markersize=6, label='P95', color='orange')
        ax2.plot(threads_s2, p99_s2, '^-', linewidth=2, markersize=6, label='P99', color='red')
        ax2.set_xlabel('Thread Count', fontsize=12, fontweight='bold')
        ax2.set_ylabel('Latency (ms)', fontsize=12, fontweight='bold')
        ax2.set_title('Scenario 2: Latency Percentiles', fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3)
        ax2.legend()
        ax2.set_yscale('log')
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/latency_percentiles.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: latency_percentiles.png")

def create_latency_histogram_chart(tests, output_dir):
    """Chart: Latency Distribution Histogram"""
    # Collect latency data from thread results
    all_latencies = []
    scenario_labels = []
    
    for t in tests:
        config = t.get('configuration', {})
        scenario = config.get('scenario', 0)
        results = t.get('results', {})
        
        scenario_key = f'scenario_{scenario}'
        scenario_result = results.get(scenario_key, {})
        thread_results = scenario_result.get('thread_results', {})
        
        for thread_idx, thread_result in thread_results.items():
            # We don't have per-operation latencies in JSON, so we'll use thread-level stats
            # For a proper histogram, we'd need raw latency data, but we can show distribution
            # of thread-level p50 latencies
            p50 = thread_result.get('p50_latency_ms', 0)
            if p50 > 0:
                all_latencies.append(p50)
                scenario_labels.append(f'Scenario {scenario}')
    
    if not all_latencies:
        print("⚠️  No latency data available for histogram")
        return
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    # Overall histogram
    ax1.hist(all_latencies, bins=50, edgecolor='black', alpha=0.7, color='steelblue')
    ax1.set_xlabel('Latency (ms)', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Frequency', fontsize=12, fontweight='bold')
    ax1.set_title('Latency Distribution (All Tests)', fontsize=14, fontweight='bold')
    ax1.grid(True, alpha=0.3, axis='y')
    
    # By scenario
    s1_latencies = [l for l, s in zip(all_latencies, scenario_labels) if s == 'Scenario 1']
    s2_latencies = [l for l, s in zip(all_latencies, scenario_labels) if s == 'Scenario 2']
    
    if s1_latencies and s2_latencies:
        ax2.hist([s1_latencies, s2_latencies], bins=30, label=['Scenario 1', 'Scenario 2'], 
                alpha=0.7, edgecolor='black')
        ax2.set_xlabel('Latency (ms)', fontsize=12, fontweight='bold')
        ax2.set_ylabel('Frequency', fontsize=12, fontweight='bold')
        ax2.set_title('Latency Distribution by Scenario', fontsize=14, fontweight='bold')
        ax2.legend()
        ax2.grid(True, alpha=0.3, axis='y')
    elif s1_latencies:
        ax2.hist(s1_latencies, bins=30, alpha=0.7, edgecolor='black', color='blue')
        ax2.set_xlabel('Latency (ms)', fontsize=12, fontweight='bold')
        ax2.set_ylabel('Frequency', fontsize=12, fontweight='bold')
        ax2.set_title('Latency Distribution - Scenario 1', fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3, axis='y')
    elif s2_latencies:
        ax2.hist(s2_latencies, bins=30, alpha=0.7, edgecolor='black', color='green')
        ax2.set_xlabel('Latency (ms)', fontsize=12, fontweight='bold')
        ax2.set_ylabel('Frequency', fontsize=12, fontweight='bold')
        ax2.set_title('Latency Distribution - Scenario 2', fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/latency_histogram.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✅ Created: latency_histogram.png")

def main():
    if len(sys.argv) < 2:
        print("Usage: create-comprehensive-charts.py <results_directory>")
        print("Example: create-comprehensive-charts.py results/latest")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    if not os.path.isdir(results_dir):
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    # Create charts directory
    charts_dir = f"{results_dir}/charts"
    os.makedirs(charts_dir, exist_ok=True)
    
    print(f"Loading test results from: {results_dir}")
    tests = load_test_results(results_dir)
    
    if not tests:
        print("Error: No test results found")
        sys.exit(1)
    
    print(f"Loaded {len(tests)} test results")
    print(f"Creating charts in: {charts_dir}")
    print()
    
    # Create all charts
    create_throughput_scaling_chart(tests, charts_dir)
    create_efficiency_chart(tests, charts_dir)
    create_comparison_chart(tests, charts_dir)
    create_thread_distribution_chart(tests, charts_dir)
    create_batch_size_impact_chart(tests, charts_dir)
    create_error_analysis_chart(tests, charts_dir)
    create_latency_percentile_chart(tests, charts_dir)
    create_latency_histogram_chart(tests, charts_dir)
    create_summary_dashboard(tests, charts_dir)
    
    print()
    print("=" * 70)
    print("✅ All charts created successfully!")
    print(f"📊 Charts saved to: {charts_dir}/")
    print("=" * 70)

if __name__ == '__main__':
    main()

