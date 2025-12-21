#!/usr/bin/env python3
"""
Generate HTML report with embedded charts and performance insights.
"""

import json
import os
import sys
import glob
from pathlib import Path
import pandas as pd
from datetime import datetime
from jinja2 import Template


def load_manifest(results_dir: str) -> dict:
    """Load test run manifest."""
    manifest_file = os.path.join(results_dir, 'manifest.json')
    if os.path.exists(manifest_file):
        with open(manifest_file, 'r') as f:
            return json.load(f)
    return {}


def load_summary(results_dir: str) -> pd.DataFrame:
    """Load summary CSV."""
    csv_file = os.path.join(results_dir, 'summary.csv')
    if os.path.exists(csv_file):
        return pd.read_csv(csv_file)
    return pd.DataFrame()


def generate_insights(df: pd.DataFrame) -> list:
    """Generate performance insights from data."""
    insights = []
    
    if df.empty:
        return insights
    
    # Find best throughput
    best_throughput = df.loc[df['throughput_inserts_per_sec'].idxmax()]
    insights.append({
        'type': 'best_performance',
        'title': 'Best Throughput',
        'description': f"Scenario {int(best_throughput['scenario'])} achieved {best_throughput['throughput_inserts_per_sec']:.2f} inserts/sec with {int(best_throughput['threads'])} threads, {int(best_throughput['iterations'])} iterations"
    })
    
    # Compare scenarios
    if len(df[df['scenario'] == 1]) > 0 and len(df[df['scenario'] == 2]) > 0:
        avg_scenario1 = df[df['scenario'] == 1]['throughput_inserts_per_sec'].mean()
        avg_scenario2 = df[df['scenario'] == 2]['throughput_inserts_per_sec'].mean()
        if avg_scenario2 > avg_scenario1:
            ratio = avg_scenario2 / avg_scenario1
            insights.append({
                'type': 'scenario_comparison',
                'title': 'Batch Inserts Outperform',
                'description': f"Scenario 2 (batch inserts) is {ratio:.2f}x faster than Scenario 1 (individual inserts) on average"
            })
    
    # Thread scaling analysis
    if len(df['threads'].unique()) > 1:
        thread_scaling = df.groupby('threads')['throughput_inserts_per_sec'].mean()
        if len(thread_scaling) > 1:
            scaling_factor = thread_scaling.iloc[-1] / thread_scaling.iloc[0]
            thread_increase = thread_scaling.index[-1] / thread_scaling.index[0]
            efficiency = scaling_factor / thread_increase
            insights.append({
                'type': 'scaling',
                'title': 'Thread Scaling Efficiency',
                'description': f"Throughput scales {scaling_factor:.2f}x with {thread_increase:.1f}x more threads ({efficiency*100:.1f}% efficiency)"
            })
    
    # Payload size impact
    if len(df['payload_size'].unique()) > 1:
        payload_impact = df.groupby('payload_size')['throughput_inserts_per_sec'].mean()
        if len(payload_impact) > 1:
            min_throughput = payload_impact.min()
            max_throughput = payload_impact.max()
            insights.append({
                'type': 'payload',
                'title': 'Payload Size Impact',
                'description': f"Throughput ranges from {min_throughput:.2f} to {max_throughput:.2f} inserts/sec across different payload sizes"
            })
    
    return insights


HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DSQL Performance Test Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
        }
        .header .meta {
            margin-top: 10px;
            opacity: 0.9;
            font-size: 0.9em;
        }
        .section {
            background: white;
            padding: 25px;
            margin-bottom: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .section h2 {
            color: #667eea;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
            margin-top: 0;
        }
        .insights {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .insight-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .insight-card h3 {
            margin-top: 0;
            color: #667eea;
        }
        .chart-container {
            text-align: center;
            margin: 20px 0;
        }
        .chart-container img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        .stat-card .value {
            font-size: 2em;
            font-weight: bold;
            margin: 10px 0;
        }
        .stat-card .label {
            opacity: 0.9;
            font-size: 0.9em;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #667eea;
            color: white;
            font-weight: 600;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>DSQL Performance Test Report</h1>
        <div class="meta">
            <p><strong>Test Run:</strong> {{ manifest.test_run_id }}</p>
            <p><strong>Start Time:</strong> {{ manifest.start_time }}</p>
            <p><strong>End Time:</strong> {{ manifest.end_time if manifest.end_time else 'In Progress' }}</p>
            <p><strong>Total Tests:</strong> {{ manifest.tests|length if manifest.tests else 0 }}</p>
        </div>
    </div>

    <div class="section">
        <h2>Summary Statistics</h2>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="label">Total Tests</div>
                <div class="value">{{ total_tests }}</div>
            </div>
            <div class="stat-card">
                <div class="label">Avg Throughput</div>
                <div class="value">{{ avg_throughput:.1f }}</div>
                <div class="label">inserts/sec</div>
            </div>
            <div class="stat-card">
                <div class="label">Max Throughput</div>
                <div class="value">{{ max_throughput:.1f }}</div>
                <div class="label">inserts/sec</div>
            </div>
            <div class="stat-card">
                <div class="label">Total Errors</div>
                <div class="value">{{ total_errors }}</div>
            </div>
        </div>
    </div>

    {% if insights %}
    <div class="section">
        <h2>Performance Insights</h2>
        <div class="insights">
            {% for insight in insights %}
            <div class="insight-card">
                <h3>{{ insight.title }}</h3>
                <p>{{ insight.description }}</p>
            </div>
            {% endfor %}
        </div>
    </div>
    {% endif %}

    <div class="section">
        <h2>Performance Charts</h2>
        {% for chart in charts %}
        <div class="chart-container">
            <h3>{{ chart.title }}</h3>
            <img src="{{ chart.path }}" alt="{{ chart.title }}">
        </div>
        {% endfor %}
    </div>

    <div class="section">
        <h2>Test Results Summary</h2>
        <table>
            <thead>
                <tr>
                    <th>Test ID</th>
                    <th>Scenario</th>
                    <th>Threads</th>
                    <th>Iterations</th>
                    <th>Count</th>
                    <th>Payload</th>
                    <th>Throughput (inserts/sec)</th>
                    <th>Duration (ms)</th>
                    <th>Success</th>
                    <th>Errors</th>
                </tr>
            </thead>
            <tbody>
                {% for row in summary_rows %}
                <tr>
                    <td>{{ row.test_id }}</td>
                    <td>{{ row.scenario }}</td>
                    <td>{{ row.threads }}</td>
                    <td>{{ row.iterations }}</td>
                    <td>{{ row.count }}</td>
                    <td>{{ row.payload_size }}</td>
                    <td>{{ "%.2f"|format(row.throughput_inserts_per_sec) }}</td>
                    <td>{{ row.duration_ms }}</td>
                    <td>{{ row.total_success }}</td>
                    <td>{{ row.total_errors }}</td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</body>
</html>
"""


def main():
    if len(sys.argv) < 2:
        print("Usage: generate-report.py <results_directory>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    if not os.path.isdir(results_dir):
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    print(f"Generating report from: {results_dir}")
    
    # Load data
    manifest = load_manifest(results_dir)
    df = load_summary(results_dir)
    
    if df.empty:
        print("No test results found!")
        sys.exit(1)
    
    # Calculate statistics
    total_tests = len(df)
    avg_throughput = df['throughput_inserts_per_sec'].mean()
    max_throughput = df['throughput_inserts_per_sec'].max()
    total_errors = df['total_errors'].sum()
    
    # Generate insights
    insights = generate_insights(df)
    
    # Find chart files
    charts_dir = os.path.join(results_dir, 'charts')
    chart_files = glob.glob(os.path.join(charts_dir, '*.png'))
    charts = []
    chart_titles = {
        'scenario1_throughput_vs_threads.png': 'Scenario 1: Throughput vs Thread Count',
        'scenario2_throughput_vs_threads.png': 'Scenario 2: Throughput vs Thread Count',
        'scenario2_throughput_vs_batch_size.png': 'Scenario 2: Throughput vs Batch Size',
        'throughput_vs_payload_size.png': 'Throughput vs Payload Size',
        'duration_vs_threads.png': 'Duration vs Thread Count',
        'scenario_comparison.png': 'Scenario 1 vs Scenario 2 Comparison',
        'error_rate_analysis.png': 'Error Rate Analysis',
        'scenario1_throughput_heatmap.png': 'Scenario 1: Throughput Heatmap'
    }
    
    for chart_file in sorted(chart_files):
        chart_name = os.path.basename(chart_file)
        charts.append({
            'title': chart_titles.get(chart_name, chart_name.replace('.png', '').replace('_', ' ').title()),
            'path': os.path.relpath(chart_file, results_dir)
        })
    
    # Prepare summary rows
    summary_rows = df.to_dict('records')
    
    # Generate HTML
    template = Template(HTML_TEMPLATE)
    html_content = template.render(
        manifest=manifest,
        total_tests=total_tests,
        avg_throughput=avg_throughput,
        max_throughput=max_throughput,
        total_errors=total_errors,
        insights=insights,
        charts=charts,
        summary_rows=summary_rows
    )
    
    # Save report
    report_file = os.path.join(results_dir, 'report.html')
    with open(report_file, 'w') as f:
        f.write(html_content)
    
    print(f"Report generated: {report_file}")
    print(f"Open in browser: file://{os.path.abspath(report_file)}")


if __name__ == '__main__':
    main()

