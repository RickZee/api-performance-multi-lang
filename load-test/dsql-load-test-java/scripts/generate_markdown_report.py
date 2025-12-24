#!/usr/bin/env python3
"""
Generate a detailed markdown report with charts for test suite run.
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

from test_suite.utils.threshold_validator import ThresholdValidator
from test_suite.utils.baseline_comparison import BaselineComparison


def load_test_results(results_dir: Path) -> List[Dict]:
    """Load all test result JSON files."""
    results = []
    
    # Load all JSON files except manifest.json
    for json_file in sorted(results_dir.glob('*.json')):
        if json_file.name == 'manifest.json':
            continue
        
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
                # Only include if it has test structure
                if 'test_id' in data or 'configuration' in data:
                    results.append(data)
        except Exception as e:
            print(f"Warning: Failed to load {json_file}: {e}", file=sys.stderr)
    
    return results


def load_manifest(results_dir: Path) -> Dict:
    """Load manifest file if it exists."""
    manifest_file = results_dir / 'manifest.json'
    if manifest_file.exists():
        try:
            with open(manifest_file, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def format_duration(ms: float) -> str:
    """Format duration in milliseconds to human-readable string."""
    if ms < 1000:
        return f"{ms:.0f}ms"
    elif ms < 60000:
        return f"{ms/1000:.1f}s"
    else:
        minutes = int(ms / 60000)
        seconds = (ms % 60000) / 1000
        return f"{minutes}m {seconds:.1f}s"


def format_number(num: float) -> str:
    """Format number with appropriate precision."""
    if num >= 1000:
        return f"{num/1000:.2f}K"
    elif num >= 1:
        return f"{num:.2f}"
    else:
        return f"{num:.4f}"


def get_chart_files(results_dir: Path) -> Dict[str, Path]:
    """Get all chart files organized by type."""
    charts_dir = results_dir / 'charts'
    if not charts_dir.exists():
        return {}
    
    charts = {}
    chart_mapping = {
        'throughput_scaling': 'Throughput Scaling',
        'efficiency_analysis': 'Efficiency Analysis',
        'scenario_comparison': 'Scenario Comparison',
        'batch_size_impact': 'Batch Size Impact',
        'payload_impact': 'Payload Size Impact',
        'error_analysis': 'Error Analysis',
        'summary_dashboard': 'Summary Dashboard',
        'thread_distribution': 'Thread Distribution',
    }
    
    for chart_file in charts_dir.glob('*.png'):
        base_name = chart_file.stem
        charts[base_name] = chart_file
    
    return charts


def generate_summary_table(results: List[Dict]) -> str:
    """Generate summary table from results."""
    if not results:
        return "No test results available."
    
    rows = []
    for result in results:
        test_id = result.get('test_id', 'unknown')
        config = result.get('configuration', {})
        scenario = config.get('scenario', 'N/A')
        threads = config.get('threads', 'N/A')
        iterations = config.get('iterations', 'N/A')
        count = config.get('count', config.get('batch_size', 'N/A'))
        
        # Get results for the scenario
        results_data = result.get('results', {})
        scenario_key = f'scenario_{scenario}'
        scenario_result = results_data.get(scenario_key, {})
        
        success = scenario_result.get('total_success', 0)
        errors = scenario_result.get('total_errors', 0)
        duration = scenario_result.get('duration_ms', 0)
        throughput = scenario_result.get('throughput_inserts_per_sec', 0)
        
        rows.append({
            'Test ID': test_id,
            'Scenario': scenario,
            'Threads': threads,
            'Iterations': iterations,
            'Count': count,
            'Success': success,
            'Errors': errors,
            'Duration': format_duration(duration),
            'Throughput (ops/s)': format_number(throughput)
        })
    
    df = pd.DataFrame(rows)
    try:
        return df.to_markdown(index=False)
    except ImportError:
        # Fallback: manual markdown table generation
        if not rows:
            return "No test results available."
        
        headers = list(rows[0].keys())
        md = []
        md.append("| " + " | ".join(headers) + " |")
        md.append("| " + " | ".join(["---"] * len(headers)) + " |")
        
        for row in rows:
            values = [str(row.get(h, '')) for h in headers]
            md.append("| " + " | ".join(values) + " |")
        
        return "\n".join(md)


def generate_system_metrics_summary(results: List[Dict]) -> str:
    """Generate system metrics summary section."""
    md = []
    
    # Get system metrics from first result (should be same for all tests on same instance)
    if not results:
        return ""
    
    first_result = results[0]
    system_metrics = first_result.get('system_metrics', {})
    cloudwatch_metrics = first_result.get('cloudwatch_metrics', {})
    
    if system_metrics:
        hardware = system_metrics.get('hardware', {})
        cpu = system_metrics.get('cpu', {})
        memory = system_metrics.get('memory', {})
        disk = system_metrics.get('disk', {})
        
        md.append("### Hardware Configuration\n")
        md.append(f"- **Instance Type:** {cloudwatch_metrics.get('instance_metadata', {}).get('instance_type', 'N/A')}")
        md.append(f"- **Processors:** {hardware.get('processor_count', 'N/A')}")
        md.append(f"- **Architecture:** {hardware.get('architecture', 'N/A')}")
        md.append(f"- **OS:** {hardware.get('os_name', 'N/A')} {hardware.get('os_version', '')}")
        md.append(f"- **Java Version:** {hardware.get('java_version', 'N/A')}")
        
        total_mem = hardware.get('total_physical_memory_bytes')
        if total_mem:
            md.append(f"- **Total Memory:** {total_mem / (1024**3):.2f} GB")
        md.append("")
        
        md.append("### CPU Metrics\n")
        if cpu.get('process_cpu_load'):
            md.append(f"- **Process CPU Load:** {cpu.get('process_cpu_load', 0):.2f}%")
        if cpu.get('system_cpu_load'):
            md.append(f"- **System CPU Load:** {cpu.get('system_cpu_load', 0):.2f}%")
        md.append("")
        
        md.append("### Memory Metrics\n")
        heap_used = memory.get('heap_used_bytes', 0)
        heap_max = memory.get('heap_max_bytes', 0)
        if heap_max > 0:
            md.append(f"- **Heap Used:** {heap_used / (1024**2):.2f} MB / {heap_max / (1024**2):.2f} MB ({heap_used / heap_max * 100:.1f}%)")
        
        system_total = memory.get('system_total_bytes')
        system_used = memory.get('system_used_bytes')
        if system_total:
            md.append(f"- **System Memory Used:** {system_used / (1024**3):.2f} GB / {system_total / (1024**3):.2f} GB")
        md.append("")
        
        md.append("### Disk Metrics\n")
        disk_total = disk.get('total_bytes')
        disk_used = disk.get('used_bytes')
        if disk_total:
            md.append(f"- **Disk Used:** {disk_used / (1024**3):.2f} GB / {disk_total / (1024**3):.2f} GB")
        md.append("")
    
    # CloudWatch metrics
    if cloudwatch_metrics:
        instance_meta = cloudwatch_metrics.get('instance_metadata', {})
        cw_metrics = cloudwatch_metrics.get('cloudwatch_metrics', {})
        
        if instance_meta:
            md.append("### EC2 Instance Metadata\n")
            md.append(f"- **Instance ID:** {instance_meta.get('instance_id', 'N/A')}")
            md.append(f"- **Instance Type:** {instance_meta.get('instance_type', 'N/A')}")
            md.append(f"- **Availability Zone:** {instance_meta.get('availability_zone', 'N/A')}")
            md.append(f"- **VPC ID:** {instance_meta.get('vpc_id', 'N/A')}")
            md.append("")
        
        if cw_metrics:
            md.append("### CloudWatch Metrics (During Test)\n")
            cpu_util = cw_metrics.get('CPUUtilization', {})
            if cpu_util.get('average') is not None:
                md.append(f"- **Average CPU Utilization:** {cpu_util.get('average', 0):.2f}%")
                md.append(f"- **Max CPU Utilization:** {cpu_util.get('maximum', 0):.2f}%")
            
            net_in = cw_metrics.get('NetworkIn', {})
            net_out = cw_metrics.get('NetworkOut', {})
            if net_in.get('average') is not None:
                md.append(f"- **Average Network In:** {net_in.get('average', 0) / (1024**2):.2f} MB/s")
                md.append(f"- **Average Network Out:** {net_out.get('average', 0) / (1024**2):.2f} MB/s")
            
            disk_read = cw_metrics.get('DiskReadBytes', {})
            disk_write = cw_metrics.get('DiskWriteBytes', {})
            if disk_read.get('average') is not None:
                md.append(f"- **Average Disk Read:** {disk_read.get('average', 0) / (1024**2):.2f} MB/s")
                md.append(f"- **Average Disk Write:** {disk_write.get('average', 0) / (1024**2):.2f} MB/s")
            md.append("")
    
    return "\n".join(md)

def generate_scenario_comparison(results: List[Dict]) -> str:
    """Generate scenario comparison section."""
    scenario1_results = []
    scenario2_results = []
    
    for result in results:
        config = result.get('configuration', {})
        scenario = config.get('scenario')
        results_data = result.get('results', {})
        
        if scenario == 1:
            scenario_result = results_data.get('scenario_1', {})
            if scenario_result:
                scenario1_results.append(scenario_result)
        elif scenario == 2:
            scenario_result = results_data.get('scenario_2', {})
            if scenario_result:
                scenario2_results.append(scenario_result)
    
    if not scenario1_results and not scenario2_results:
        return "No scenario data available for comparison."
    
    md = []
    md.append("### Performance Comparison\n")
    
    if scenario1_results:
        avg_throughput_1 = sum(r.get('throughput_inserts_per_sec', 0) for r in scenario1_results) / len(scenario1_results)
        total_success_1 = sum(r.get('total_success', 0) for r in scenario1_results)
        total_errors_1 = sum(r.get('total_errors', 0) for r in scenario1_results)
        
        md.append(f"**Scenario 1 (Individual Inserts):**")
        md.append(f"- Average Throughput: {format_number(avg_throughput_1)} inserts/sec")
        md.append(f"- Total Success: {total_success_1:,} inserts")
        md.append(f"- Total Errors: {total_errors_1:,}")
        md.append("")
    
    if scenario2_results:
        avg_throughput_2 = sum(r.get('throughput_inserts_per_sec', 0) for r in scenario2_results) / len(scenario2_results)
        total_success_2 = sum(r.get('total_success', 0) for r in scenario2_results)
        total_errors_2 = sum(r.get('total_errors', 0) for r in scenario2_results)
        
        md.append(f"**Scenario 2 (Batch Inserts):**")
        md.append(f"- Average Throughput: {format_number(avg_throughput_2)} inserts/sec")
        md.append(f"- Total Success: {total_success_2:,} inserts")
        md.append(f"- Total Errors: {total_errors_2:,}")
        md.append("")
    
    if scenario1_results and scenario2_results:
        avg_throughput_1 = sum(r.get('throughput_inserts_per_sec', 0) for r in scenario1_results) / len(scenario1_results)
        avg_throughput_2 = sum(r.get('throughput_inserts_per_sec', 0) for r in scenario2_results) / len(scenario2_results)
        improvement = ((avg_throughput_2 - avg_throughput_1) / avg_throughput_1 * 100) if avg_throughput_1 > 0 else 0
        
        md.append(f"**Comparison:**")
        md.append(f"- Scenario 2 is {improvement:+.1f}% faster than Scenario 1")
        md.append("")
    
    return "\n".join(md)


def generate_markdown_report(results_dir: Path, output_file: Optional[Path] = None) -> str:
    """Generate markdown report from test results."""
    if not results_dir.exists():
        raise FileNotFoundError(f"Results directory not found: {results_dir}")
    
    # Load data
    results = load_test_results(results_dir)
    manifest = load_manifest(results_dir)
    charts = get_chart_files(results_dir)
    
    # Generate report
    md = []
    
    # Header
    md.append("# DSQL Performance Test Suite Report\n")
    
    # Test run information
    md.append("## Test Run Information\n")
    
    run_id = manifest.get('test_run_id', results_dir.name)
    start_time = manifest.get('start_time', '')
    end_time = manifest.get('end_time', '')
    
    md.append(f"- **Run ID:** `{run_id}`")
    md.append(f"- **Start Time:** {start_time}")
    if end_time:
        md.append(f"- **End Time:** {end_time}")
    md.append(f"- **Total Tests:** {len(results)}")
    md.append("")
    
    # Threshold Validation
    config_path = results_dir.parent / 'test-config.json'
    thresholds = ThresholdValidator.load_thresholds_from_config(config_path)
    if thresholds:
        md.append("## Threshold Validation\n")
        validator = ThresholdValidator(thresholds)
        all_passed, failures = validator.validate_results_directory(results_dir)
        
        if all_passed:
            md.append("✅ **All tests passed threshold validation**\n")
        else:
            md.append("❌ **Some tests failed threshold validation**\n")
            md.append("\n**Failures:**\n")
            for failure in failures:
                md.append(f"- {failure}\n")
        md.append("")
    
    # Baseline Comparison
    baseline_dir = results_dir.parent / 'baseline'
    if baseline_dir.exists():
        md.append("## Baseline Comparison\n")
        comparison = BaselineComparison(baseline_dir)
        comparison_results = comparison.compare_results_directory(results_dir)
        
        md.append(f"- **Tests with baseline:** {comparison_results['tests_with_baseline']}/{comparison_results['total_tests']}\n")
        md.append(f"- **Regressions detected:** {comparison_results['regressions']}\n")
        
        if comparison_results['regressions'] > 0:
            md.append("\n**Regression Details:**\n")
            for comp in comparison_results['comparisons']:
                if comp.get('is_regression'):
                    md.append(f"- **{comp['test_id']}:**\n")
                    for reason in comp.get('regression_reasons', []):
                        md.append(f"  - {reason}\n")
        md.append("")
    
    # Summary
    md.append("## Executive Summary\n")
    
    if results:
        total_success = sum(
            r.get('results', {}).get(f'scenario_{r.get("configuration", {}).get("scenario", 1)}', {}).get('total_success', 0)
            for r in results
        )
        total_errors = sum(
            r.get('results', {}).get(f'scenario_{r.get("configuration", {}).get("scenario", 1)}', {}).get('total_errors', 0)
            for r in results
        )
        
        md.append(f"- **Total Successful Inserts:** {total_success:,}")
        md.append(f"- **Total Errors:** {total_errors:,}")
        md.append(f"- **Success Rate:** {((total_success / (total_success + total_errors)) * 100):.2f}%" if (total_success + total_errors) > 0 else "N/A")
        md.append("")
    
    # System Metrics Summary
    if results:
        md.append("## System Metrics Summary\n")
        md.append(generate_system_metrics_summary(results))
        md.append("")
    
    # Test Results Summary Table
    md.append("## Test Results Summary\n")
    md.append(generate_summary_table(results))
    md.append("")
    
    # Scenario Comparison
    md.append("## Scenario Analysis\n")
    md.append(generate_scenario_comparison(results))
    md.append("")
    
    # Charts
    if charts:
        md.append("## Performance Charts\n")
        md.append("The following charts visualize the test results:\n")
        
        chart_descriptions = {
            'summary_dashboard': 'Comprehensive summary dashboard showing key metrics',
            'throughput_scaling': 'Throughput scaling analysis across different configurations',
            'efficiency_analysis': 'Efficiency metrics and resource utilization',
            'scenario_comparison': 'Direct comparison between Scenario 1 and Scenario 2',
            'batch_size_impact': 'Impact of batch size on performance',
            'payload_impact': 'Impact of payload size on performance',
            'error_analysis': 'Error rate analysis and failure patterns',
            'thread_distribution': 'Thread distribution and concurrency analysis',
            'duration_vs_threads': 'Duration analysis vs thread count',
            'scenario1_throughput_heatmap': 'Scenario 1 throughput heatmap',
            'scenario2_throughput_heatmap': 'Scenario 2 throughput heatmap',
        }
        
        # Summary dashboard first
        if 'summary_dashboard' in charts:
            md.append(f"### Summary Dashboard\n")
            md.append(f"![Summary Dashboard](charts/{charts['summary_dashboard'].name})\n")
            md.append(f"*{chart_descriptions.get('summary_dashboard', 'Summary dashboard')}*\n")
        
        # Other charts - sort by priority/name
        chart_priority = ['throughput_scaling', 'efficiency_analysis', 'scenario_comparison', 
                         'batch_size_impact', 'payload_impact', 'error_analysis', 
                         'thread_distribution', 'duration_vs_threads', 
                         'scenario1_throughput_heatmap', 'scenario2_throughput_heatmap']
        
        # Add priority charts first
        for chart_name in chart_priority:
            if chart_name in charts:
                chart_file = charts[chart_name]
                description = chart_descriptions.get(chart_name, 'Performance chart')
                title = description.replace(' analysis', '').replace(' metrics', '').replace(' analysis', '').title()
                
                md.append(f"### {title}\n")
                md.append(f"![{title}](charts/{chart_file.name})\n")
                md.append(f"*{description}*\n")
        
        # Add any remaining charts not in priority list
        for chart_name, chart_file in sorted(charts.items()):
            if chart_name not in chart_priority and chart_name != 'summary_dashboard':
                description = chart_descriptions.get(chart_name, 'Performance chart')
                title = chart_name.replace('_', ' ').title()
                
                md.append(f"### {title}\n")
                md.append(f"![{title}](charts/{chart_file.name})\n")
                md.append(f"*{description}*\n")
    else:
        # If no charts found, suggest generating them
        md.append("## Performance Charts\n")
        md.append("*No charts found. Generate charts using:*\n")
        md.append("```bash\n")
        md.append("python3 create-comprehensive-charts.py results/latest\n")
        md.append("```\n")
        md.append("Or:\n")
        md.append("```bash\n")
        md.append("python3 scripts/analyze_results.py results/latest\n")
        md.append("```\n")
    
    # Footer
    md.append("---\n")
    md.append(f"*Report generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n")
    
    report_content = "\n".join(md)
    
    # Write to file
    if output_file is None:
        output_file = results_dir / 'REPORT.md'
    
    with open(output_file, 'w') as f:
        f.write(report_content)
    
    return str(output_file)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Generate detailed markdown report with charts for test suite run',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate report for latest results
  python3 scripts/generate_markdown_report.py

  # Generate report for specific directory
  python3 scripts/generate_markdown_report.py results/2025-12-22_16-09-38

  # Custom output file
  python3 scripts/generate_markdown_report.py --output custom-report.md
        """
    )
    
    parser.add_argument(
        'results_dir',
        nargs='?',
        help='Results directory (default: results/latest)'
    )
    
    parser.add_argument(
        '--output',
        '-o',
        help='Output markdown file (default: results_dir/REPORT.md)'
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
    
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}", file=sys.stderr)
        sys.exit(1)
    
    # Determine output file
    output_file = None
    if args.output:
        output_file = Path(args.output)
    
    try:
        report_file = generate_markdown_report(results_dir, output_file)
        print(f"✅ Markdown report generated: {report_file}")
        
        # Check thresholds and exit with appropriate code
        config_path = results_dir.parent / 'test-config.json'
        thresholds = ThresholdValidator.load_thresholds_from_config(config_path)
        if thresholds:
            validator = ThresholdValidator(thresholds)
            all_passed, failures = validator.validate_results_directory(results_dir)
            if not all_passed:
                print(f"\n❌ Threshold validation failed: {len(failures)} violations", file=sys.stderr)
                sys.exit(1)
            else:
                print("\n✅ All threshold validations passed")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()

