#!/usr/bin/env python3
"""
Generate comprehensive HTML report from k6 test results
"""
import json
import sys
import os
from datetime import datetime
from pathlib import Path

def extract_metrics_from_json(json_file):
    """Extract metrics from k6 JSON file (supports both summary and NDJSON formats)"""
    if not json_file or not os.path.exists(json_file):
        return None
    
    try:
        # Try single JSON first (summary format)
        with open(json_file, 'r') as f:
            content = f.read().strip()
            try:
                data = json.loads(content)
                if 'metrics' in data:
                    metrics = data.get('metrics', {})
                    req_metric = metrics.get('http_reqs') or metrics.get('grpc_reqs')
                    duration_metric = metrics.get('http_req_duration') or metrics.get('grpc_req_duration')
                    failed_metric = metrics.get('http_req_failed') or metrics.get('grpc_req_failed')
                    
                    if req_metric:
                        values = req_metric.get('values', {})
                        duration_values = duration_metric.get('values', {}) if duration_metric else {}
                        failed_values = failed_metric.get('values', {}) if failed_metric else {}
                        
                        total_samples = int(values.get('count', 0))
                        throughput = float(values.get('rate', 0))
                        error_rate = float(failed_values.get('rate', 0) * 100) if failed_values else 0.0
                        success_samples = int(total_samples * (1 - (error_rate / 100))) if total_samples > 0 else 0
                        error_samples = total_samples - success_samples
                        
                        avg_response = float(duration_values.get('avg', 0)) if duration_values else 0.0
                        min_response = float(duration_values.get('min', 0)) if duration_values else 0.0
                        max_response = float(duration_values.get('max', 0)) if duration_values else 0.0
                        p95_response = float(duration_values.get('p(95)', 0)) if duration_values else 0.0
                        p99_response = float(duration_values.get('p(99)', 0)) if duration_values else 0.0
                        
                        root = data.get('root_group', {})
                        duration_ms = float(root.get('execution_duration', {}).get('total', 0))
                        duration_seconds = duration_ms / 1000.0 if duration_ms > 0 else 0.0
                        
                        return {
                            'total_samples': total_samples,
                            'success_samples': success_samples,
                            'error_samples': error_samples,
                            'duration_seconds': duration_seconds,
                            'throughput': throughput,
                            'avg_response': avg_response,
                            'min_response': min_response,
                            'max_response': max_response,
                            'p95_response': p95_response,
                            'p99_response': p99_response,
                            'error_rate': error_rate
                        }
            except json.JSONDecodeError:
                pass
        
        # Parse NDJSON format
        http_reqs = []
        grpc_reqs = []
        http_durations = []
        grpc_durations = []
        http_failed = []
        grpc_failed = []
        iterations = []
        iteration_durations = []
        start_time = None
        end_time = None
        
        with open(json_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    obj_type = obj.get('type', '')
                    metric_name = obj.get('metric', '')
                    data = obj.get('data', {})
                    
                    if 'time' in data:
                        time_str = data['time']
                        try:
                            # Handle both Z and +00:00 timezone formats
                            if time_str.endswith('Z'):
                                time_str = time_str[:-1] + '+00:00'
                            time_obj = datetime.fromisoformat(time_str)
                            if start_time is None or time_obj < start_time:
                                start_time = time_obj
                            if end_time is None or time_obj > end_time:
                                end_time = time_obj
                        except Exception:
                            pass
                    
                    if metric_name == 'http_reqs' and obj_type == 'Point':
                        http_reqs.append(data.get('value', 0))
                    elif metric_name == 'grpc_reqs' and obj_type == 'Point':
                        grpc_reqs.append(data.get('value', 0))
                    elif metric_name == 'http_req_duration' and obj_type == 'Point':
                        http_durations.append(data.get('value', 0))
                    elif metric_name == 'grpc_req_duration' and obj_type == 'Point':
                        grpc_durations.append(data.get('value', 0))
                    elif metric_name == 'http_req_failed' and obj_type == 'Point':
                        http_failed.append(data.get('value', 0))
                    elif metric_name == 'grpc_req_failed' and obj_type == 'Point':
                        grpc_failed.append(data.get('value', 0))
                    elif metric_name == 'iterations' and obj_type == 'Point':
                        iterations.append(data.get('value', 0))
                    elif metric_name == 'iteration_duration' and obj_type == 'Point':
                        iteration_durations.append(data.get('value', 0))
                except json.JSONDecodeError:
                    continue
        
        # For gRPC, if we don't have grpc_reqs, use grpc_req_duration points or iterations as request count
        if not http_reqs and not grpc_reqs:
            if grpc_durations:
                grpc_reqs = [1] * len(grpc_durations)
            elif iterations:
                total_iterations = sum(iterations)
                grpc_reqs = [1] * total_iterations
        
        reqs = http_reqs if http_reqs else grpc_reqs
        durations = http_durations if http_durations else grpc_durations
        failed = http_failed if http_failed else grpc_failed
        
        if not reqs:
            return None
        
        total_samples = len(reqs)
        success_samples = total_samples - sum(failed) if failed else total_samples
        error_samples = sum(failed) if failed else 0
        
        # Calculate duration - prefer actual time range, fall back to iteration durations
        if start_time and end_time and (end_time - start_time).total_seconds() > 0.01:
            duration_seconds = (end_time - start_time).total_seconds()
        elif iteration_durations:
            duration_seconds = sum(iteration_durations) / 1000.0 if iteration_durations else 0.0
        else:
            duration_seconds = max(0.1, total_samples * 0.1)
        
        duration_seconds = max(0.1, duration_seconds)
        throughput = total_samples / duration_seconds if duration_seconds > 0 else 0.0
        
        if durations:
            avg_response = sum(durations) / len(durations)
            min_response = min(durations)
            max_response = max(durations)
            # Calculate percentiles
            sorted_durations = sorted(durations)
            p95_idx = int(len(sorted_durations) * 0.95)
            p99_idx = int(len(sorted_durations) * 0.99)
            p95_response = sorted_durations[p95_idx] if p95_idx < len(sorted_durations) else sorted_durations[-1]
            p99_response = sorted_durations[p99_idx] if p99_idx < len(sorted_durations) else sorted_durations[-1]
        else:
            avg_response = 0.0
            min_response = 0.0
            max_response = 0.0
            p95_response = 0.0
            p99_response = 0.0
        
        error_rate = (error_samples / total_samples * 100) if total_samples > 0 else 0.0
        
        return {
            'total_samples': total_samples,
            'success_samples': success_samples,
            'error_samples': error_samples,
            'duration_seconds': duration_seconds,
            'throughput': throughput,
            'avg_response': avg_response,
            'min_response': min_response,
            'max_response': max_response,
            'p95_response': p95_response,
            'p99_response': p99_response,
            'error_rate': error_rate
        }
    except Exception as e:
        print(f"Error reading {json_file}: {e}", file=sys.stderr)
    
    return None

def generate_html_report(results_dir, test_mode, timestamp):
    """Generate comprehensive HTML report"""
    results_path = Path(results_dir)
    html_file = results_path / f"comparison-report-{timestamp}.html"
    
    # API configurations
    apis = [
        {'name': 'producer-api-java-rest', 'display': 'Java REST', 'port': 9081, 'protocol': 'REST'},
        {'name': 'producer-api-java-grpc', 'display': 'Java gRPC', 'port': 9090, 'protocol': 'gRPC'},
        {'name': 'producer-api-rust-rest', 'display': 'Rust REST', 'port': 9082, 'protocol': 'REST'},
        {'name': 'producer-api-rust-grpc', 'display': 'Rust gRPC', 'port': 9091, 'protocol': 'gRPC'},
        {'name': 'producer-api-go-rest', 'display': 'Go REST', 'port': 9083, 'protocol': 'REST'},
        {'name': 'producer-api-go-grpc', 'display': 'Go gRPC', 'port': 9092, 'protocol': 'gRPC'},
    ]
    
    # Collect metrics for all APIs
    api_results = []
    for api in apis:
        api_dir = results_path / api['name']
        if not api_dir.exists():
            api_results.append({**api, 'status': 'no_results'})
            continue
        
        # Find JSON file matching timestamp and test mode
        if timestamp:
            # Match files with specific timestamp and test mode
            if test_mode == 'smoke':
                json_pattern = f"*-throughput-smoke-{timestamp}.json"
            elif test_mode == 'saturation':
                json_pattern = f"*-throughput-saturation-{timestamp}.json"
            else:
                json_pattern = f"*-throughput-{timestamp}.json"
            
            json_files = list(api_dir.glob(json_pattern))
        else:
            # Find latest files (fallback)
            json_files = list(api_dir.glob("*-throughput-*.json"))
        
        if not json_files:
            api_results.append({**api, 'status': 'no_json'})
            continue
        
        # Use the first matching file if timestamp specified, otherwise use latest
        if timestamp:
            latest_json = json_files[0] if json_files else None
        else:
            latest_json = max(json_files, key=lambda p: p.stat().st_mtime)
        
        if not latest_json:
            api_results.append({**api, 'status': 'no_json'})
            continue
        
        metrics = extract_metrics_from_json(latest_json)
        
        if metrics:
            api_results.append({**api, 'status': 'success', 'metrics': metrics, 'json_file': latest_json.name})
        else:
            api_results.append({**api, 'status': 'parse_error'})
    
    # Generate HTML
    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API Performance Test Report - {test_mode.upper()}</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: #f5f5f5;
            padding: 40px 20px;
            color: #333;
            line-height: 1.6;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            padding: 40px;
        }}
        h1 {{
            color: #1a1a1a;
            font-size: 28px;
            font-weight: 600;
            margin-bottom: 10px;
            padding-bottom: 15px;
            border-bottom: 1px solid #e0e0e0;
        }}
        h2 {{
            color: #1a1a1a;
            font-size: 22px;
            font-weight: 600;
            margin-top: 40px;
            margin-bottom: 20px;
        }}
        .header-info {{
            background: #fafafa;
            padding: 20px;
            border-radius: 6px;
            margin-bottom: 30px;
            border: 1px solid #e8e8e8;
        }}
        .header-info p {{
            margin: 6px 0;
            color: #666;
            font-size: 14px;
        }}
        .header-info strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            font-size: 14px;
        }}
        th {{
            background: #f8f8f8;
            color: #1a1a1a;
            padding: 12px 15px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #e0e0e0;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}
        td strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        td {{
            padding: 12px 15px;
            border-bottom: 1px solid #f0f0f0;
        }}
        tr:hover {{
            background: #fafafa;
        }}
        .status-success {{
            color: #22c55e;
            font-weight: 600;
        }}
        .status-error {{
            color: #ef4444;
            font-weight: 600;
        }}
        .status-warning {{
            color: #f59e0b;
            font-weight: 600;
        }}
        .comparison-section {{
            margin: 30px 0;
            padding: 24px;
            background: #fafafa;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .comparison-section h3 {{
            color: #1a1a1a;
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
        }}
        .insight-box {{
            background: white;
            padding: 16px;
            margin: 12px 0;
            border-radius: 4px;
            border: 1px solid #e8e8e8;
        }}
        .insight-box h4 {{
            color: #1a1a1a;
            font-size: 15px;
            font-weight: 600;
            margin-bottom: 8px;
            margin-top: 0;
        }}
        .insight-box p {{
            margin: 6px 0;
            color: #555;
            font-size: 14px;
            line-height: 1.6;
        }}
        .ranking-list {{
            list-style: none;
            padding: 0;
            margin: 0;
        }}
        .ranking-list li {{
            padding: 10px 0;
            border-bottom: 1px solid #f0f0f0;
            color: #555;
            font-size: 14px;
        }}
        .ranking-list li:last-child {{
            border-bottom: none;
        }}
        .ranking-list li strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        .winner {{
            color: #22c55e;
            font-weight: 600;
        }}
        .api-details {{
            margin: 30px 0;
            padding: 24px;
            background: #fafafa;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .api-details h3 {{
            color: #1a1a1a;
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
        }}
        .api-details table {{
            margin: 10px 0;
        }}
        .footer {{
            margin-top: 50px;
            padding-top: 24px;
            border-top: 1px solid #e8e8e8;
            text-align: center;
            color: #999;
            font-size: 13px;
        }}
        .chart-container {{
            position: relative;
            height: 400px;
            margin: 20px 0;
            padding: 20px;
            background: white;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .chart-container h4 {{
            color: #1a1a1a;
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
        }}
        .resource-section {{
            margin: 30px 0;
            padding: 24px;
            background: #fafafa;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .resource-section h3 {{
            color: #1a1a1a;
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 20px;
            margin-top: 0;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 API Performance Test Report</h1>
        
        <div class="header-info">
            <p><strong>Test Mode:</strong> {test_mode.upper()}</p>
            <p><strong>Test Date:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p><strong>Test Type:</strong> Sequential (one API at a time)</p>
            <p><strong>Total APIs Tested:</strong> {len([r for r in api_results if r.get('status') == 'success'])}</p>
        </div>
        
        <h2>📊 Executive Summary</h2>
        <table>
            <thead>
                <tr>
                    <th>API</th>
                    <th>Protocol</th>
                    <th>Status</th>
                    <th>Total Requests</th>
                    <th>Success</th>
                    <th>Errors</th>
                    <th>Error Rate</th>
                    <th>Throughput (req/s)</th>
                    <th>Avg Response (ms)</th>
                    <th>Min (ms)</th>
                    <th>Max (ms)</th>
                    <th>P95 (ms)</th>
                </tr>
            </thead>
            <tbody>
"""
    
    # Add table rows
    for api in api_results:
        if api.get('status') == 'success' and 'metrics' in api:
            m = api['metrics']
            status_class = 'status-success' if m['error_rate'] < 1 else 'status-warning' if m['error_rate'] < 5 else 'status-error'
            status_text = '✅ PASS' if m['error_rate'] < 1 else '⚠️ WARN' if m['error_rate'] < 5 else '❌ FAIL'
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td class="{status_class}">{status_text}</td>
                    <td>{m['total_samples']}</td>
                    <td>{m['success_samples']}</td>
                    <td>{m['error_samples']}</td>
                    <td>{m['error_rate']:.2f}%</td>
                    <td><strong>{m['throughput']:.2f}</strong></td>
                    <td>{m['avg_response']:.2f}</td>
                    <td>{m['min_response']:.2f}</td>
                    <td>{m['max_response']:.2f}</td>
                    <td>{m['p95_response']:.2f}</td>
                </tr>
"""
        else:
            status_text = '❌ No Results' if api.get('status') == 'no_results' else '❌ No JSON' if api.get('status') == 'no_json' else '❌ Parse Error'
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td class="status-error">{status_text}</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                </tr>
"""
    
    html_content += """
            </tbody>
        </table>
"""
    
    # Generate comparison analysis
    successful_apis = [api for api in api_results if api.get('status') == 'success' and 'metrics' in api]
    
    if successful_apis:
        # Find winners
        highest_throughput = max(successful_apis, key=lambda x: x['metrics']['throughput'])
        lowest_latency = min(successful_apis, key=lambda x: x['metrics']['avg_response'])
        lowest_error = min(successful_apis, key=lambda x: x['metrics']['error_rate'])
        
        # Group by protocol
        rest_apis = [api for api in successful_apis if api['protocol'] == 'REST']
        grpc_apis = [api for api in successful_apis if api['protocol'] == 'gRPC']
        
        # Group by language
        java_apis = [api for api in successful_apis if 'Java' in api['display']]
        rust_apis = [api for api in successful_apis if 'Rust' in api['display']]
        go_apis = [api for api in successful_apis if 'Go' in api['display']]
        
        # Calculate averages
        def avg_metric(apis, metric_key):
            if not apis:
                return 0.0
            return sum(api['metrics'][metric_key] for api in apis) / len(apis)
        
        rest_avg_throughput = avg_metric(rest_apis, 'throughput')
        grpc_avg_throughput = avg_metric(grpc_apis, 'throughput')
        rest_avg_latency = avg_metric(rest_apis, 'avg_response')
        grpc_avg_latency = avg_metric(grpc_apis, 'avg_response')
        
        java_avg_throughput = avg_metric(java_apis, 'throughput')
        rust_avg_throughput = avg_metric(rust_apis, 'throughput')
        go_avg_throughput = avg_metric(go_apis, 'throughput')
        java_avg_latency = avg_metric(java_apis, 'avg_response')
        rust_avg_latency = avg_metric(rust_apis, 'avg_response')
        go_avg_latency = avg_metric(go_apis, 'avg_response')
        
        html_content += f"""
        <h2>📊 Comparison Analysis</h2>
        
        <div class="comparison-section">
            <h3>Performance Rankings</h3>
            <ul class="ranking-list">
                <li><strong>Highest Throughput:</strong> <span class="winner">{highest_throughput['display']}</span> with {highest_throughput['metrics']['throughput']:.2f} req/s</li>
                <li><strong>Lowest Latency:</strong> <span class="winner">{lowest_latency['display']}</span> with {lowest_latency['metrics']['avg_response']:.2f} ms average response time</li>
                <li><strong>Most Reliable:</strong> <span class="winner">{lowest_error['display']}</span> with {lowest_error['metrics']['error_rate']:.2f}% error rate</li>
            </ul>
        </div>
        
        <div class="comparison-section">
            <h3>Protocol Comparison</h3>
            <div class="insight-box">
                <h4>REST vs gRPC</h4>
                <p><strong>Throughput:</strong> REST APIs average {rest_avg_throughput:.2f} req/s, gRPC APIs average {grpc_avg_throughput:.2f} req/s</p>
                <p><strong>Latency:</strong> REST APIs average {rest_avg_latency:.2f} ms, gRPC APIs average {grpc_avg_latency:.2f} ms</p>
"""
        
        if rest_avg_throughput > 0 and grpc_avg_throughput > 0:
            throughput_diff = ((grpc_avg_throughput - rest_avg_throughput) / rest_avg_throughput) * 100
            latency_diff = ((rest_avg_latency - grpc_avg_latency) / rest_avg_latency) * 100 if rest_avg_latency > 0 else 0
            html_content += f"""
                <p><strong>Analysis:</strong> gRPC shows {abs(throughput_diff):.1f}% {'higher' if throughput_diff > 0 else 'lower'} throughput and {abs(latency_diff):.1f}% {'lower' if latency_diff > 0 else 'higher'} latency compared to REST</p>
"""
        
        html_content += """
            </div>
        </div>
        
        <div class="comparison-section">
            <h3>Language Comparison</h3>
            <div class="insight-box">
                <h4>Java vs Rust vs Go</h4>
"""
        
        html_content += f"""
                <p><strong>Throughput:</strong> Java ({java_avg_throughput:.2f} req/s), Rust ({rust_avg_throughput:.2f} req/s), Go ({go_avg_throughput:.2f} req/s)</p>
                <p><strong>Latency:</strong> Java ({java_avg_latency:.2f} ms), Rust ({rust_avg_latency:.2f} ms), Go ({go_avg_latency:.2f} ms)</p>
"""
        
        # Find language winners
        lang_throughput_winner = max([('Java', java_avg_throughput), ('Rust', rust_avg_throughput), ('Go', go_avg_throughput)], key=lambda x: x[1])
        lang_latency_winner = min([('Java', java_avg_latency), ('Rust', rust_avg_latency), ('Go', go_avg_latency)], key=lambda x: x[1])
        
        html_content += f"""
                <p><strong>Best Throughput:</strong> <span class="winner">{lang_throughput_winner[0]}</span> ({lang_throughput_winner[1]:.2f} req/s)</p>
                <p><strong>Best Latency:</strong> <span class="winner">{lang_latency_winner[0]}</span> ({lang_latency_winner[1]:.2f} ms)</p>
"""
        
        html_content += """
            </div>
        </div>
        
        <div class="comparison-section">
            <h3>Key Insights</h3>
"""
        
        # Generate insights
        insights = []
        
        # Throughput insights
        if highest_throughput['metrics']['throughput'] > 0:
            throughput_range = max(api['metrics']['throughput'] for api in successful_apis) - min(api['metrics']['throughput'] for api in successful_apis)
            throughput_variance = (throughput_range / max(api['metrics']['throughput'] for api in successful_apis)) * 100
            if throughput_variance > 20:
                insights.append(f"Significant throughput variation ({throughput_variance:.1f}%) across APIs, indicating performance differences")
            else:
                insights.append("Throughput is relatively consistent across APIs")
        
        # Latency insights
        if lowest_latency['metrics']['avg_response'] > 0:
            latency_range = max(api['metrics']['avg_response'] for api in successful_apis) - min(api['metrics']['avg_response'] for api in successful_apis)
            if latency_range > 10:
                fastest = min(successful_apis, key=lambda x: x['metrics']['avg_response'])
                slowest = max(successful_apis, key=lambda x: x['metrics']['avg_response'])
                latency_improvement = ((slowest['metrics']['avg_response'] - fastest['metrics']['avg_response']) / slowest['metrics']['avg_response']) * 100
                insights.append(f"{fastest['display']} is {latency_improvement:.1f}% faster than {slowest['display']} in terms of average latency")
        
        # Error rate insights
        if all(api['metrics']['error_rate'] == 0 for api in successful_apis):
            insights.append("All APIs achieved 0% error rate, demonstrating excellent reliability")
        else:
            max_error = max(api['metrics']['error_rate'] for api in successful_apis)
            if max_error > 5:
                insights.append(f"Some APIs show elevated error rates (max: {max_error:.2f}%), requiring attention")
        
        # Protocol-specific insights
        if rest_apis and grpc_apis:
            if grpc_avg_latency < rest_avg_latency * 0.8:
                insights.append("gRPC shows significantly lower latency compared to REST, making it better for latency-sensitive applications")
            elif rest_avg_throughput > grpc_avg_throughput * 1.2:
                insights.append("REST shows higher throughput, making it better for high-volume scenarios")
        
        for insight in insights:
            html_content += f"""
            <div class="insight-box">
                <p>{insight}</p>
            </div>
"""
        
        html_content += """
        </div>
        
        <div class="comparison-section">
            <h3>Recommendations</h3>
            <div class="insight-box">
                <ul class="ranking-list">
"""
        
        # Generate recommendations
        if highest_throughput['metrics']['throughput'] > 0:
            html_content += f"""
                    <li><strong>For Maximum Throughput:</strong> Choose <span class="winner">{highest_throughput['display']}</span> ({highest_throughput['metrics']['throughput']:.2f} req/s)</li>
"""
        
        if lowest_latency['metrics']['avg_response'] > 0:
            html_content += f"""
                    <li><strong>For Lowest Latency:</strong> Choose <span class="winner">{lowest_latency['display']}</span> ({lowest_latency['metrics']['avg_response']:.2f} ms average)</li>
"""
        
        if lowest_error['metrics']['error_rate'] == 0:
            html_content += f"""
                    <li><strong>For Reliability:</strong> All APIs show 0% error rate - excellent reliability across the board</li>
"""
        else:
            html_content += f"""
                    <li><strong>For Reliability:</strong> Choose <span class="winner">{lowest_error['display']}</span> ({lowest_error['metrics']['error_rate']:.2f}% error rate)</li>
"""
        
        html_content += """
                </ul>
            </div>
        </div>
"""
    
    # Add resource utilization section (for all test modes)
    if True:  # Always include resource metrics
        # Load resource metrics for all APIs
        import subprocess
        resource_data = {}
        
        for api in apis:
            api_dir = results_path / api['name']
            if not api_dir.exists():
                continue
            
            # Find JSON and metrics CSV files matching the timestamp and test mode
            if timestamp:
                # Match files with specific timestamp
                json_pattern = f"*-throughput-{timestamp}.json"
                csv_pattern = f"*-throughput-{timestamp}-metrics.csv"
                if test_mode == 'smoke':
                    json_pattern = f"*-throughput-smoke-{timestamp}.json"
                    csv_pattern = f"*-throughput-smoke-{timestamp}-metrics.csv"
                elif test_mode == 'saturation':
                    json_pattern = f"*-throughput-saturation-{timestamp}.json"
                    csv_pattern = f"*-throughput-saturation-{timestamp}-metrics.csv"
                
                json_files = list(api_dir.glob(json_pattern))
                metrics_csv_files = list(api_dir.glob(csv_pattern))
            else:
                # Find latest files
                json_files = list(api_dir.glob("*-throughput-*.json"))
                metrics_csv_files = list(api_dir.glob("*-throughput-*-metrics.csv"))
            
            if not json_files or not metrics_csv_files:
                continue
            
            # Match JSON and CSV files by timestamp
            if timestamp:
                latest_json = json_files[0] if json_files else None
                latest_metrics_csv = metrics_csv_files[0] if metrics_csv_files else None
            else:
                latest_json = max(json_files, key=lambda p: p.stat().st_mtime)
                latest_metrics_csv = max(metrics_csv_files, key=lambda p: p.stat().st_mtime)
            
            if not latest_json or not latest_metrics_csv:
                continue
            
            # Analyze resource metrics
            try:
                script_dir = Path(__file__).parent
                result = subprocess.run(
                    ['python3', str(script_dir / 'analyze-resource-metrics.py'), 
                     str(latest_json), str(latest_metrics_csv), test_mode],
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                if result.returncode == 0:
                    resource_data[api['name']] = json.loads(result.stdout)
            except Exception as e:
                print(f"Error loading resource metrics for {api['name']}: {e}", file=sys.stderr)
        
        if resource_data:
            html_content += """
        <h2>💻 Resource Utilization Metrics</h2>
        
        <div class="resource-section">
            <h3>Overall Resource Usage</h3>
            <table>
                <thead>
                    <tr>
                        <th>API</th>
                        <th>Avg CPU %</th>
                        <th>Max CPU %</th>
                        <th>Avg Memory %</th>
                        <th>Max Memory %</th>
                        <th>Avg Memory (MB)</th>
                        <th>Max Memory (MB)</th>
                    </tr>
                </thead>
                <tbody>
"""
            
            for api in apis:
                if api['name'] in resource_data:
                    r = resource_data[api['name']]['overall']
                    html_content += f"""
                    <tr>
                        <td><strong>{api['display']}</strong></td>
                        <td>{r['avg_cpu_percent']:.2f}</td>
                        <td>{r['max_cpu_percent']:.2f}</td>
                        <td>{r['avg_memory_percent']:.2f}</td>
                        <td>{r['max_memory_percent']:.2f}</td>
                        <td>{r['avg_memory_mb']:.2f}</td>
                        <td>{r['max_memory_mb']:.2f}</td>
                    </tr>
"""
            
            html_content += """
                </tbody>
            </table>
        </div>
        
        <div class="resource-section">
            <h3>Per-Phase CPU Usage Comparison</h3>
            <div class="chart-container">
                <canvas id="cpuPhaseChart"></canvas>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Per-Phase Memory Usage Comparison</h3>
            <div class="chart-container">
                <canvas id="memoryPhaseChart"></canvas>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Derived Metrics: CPU % per Request</h3>
            <div class="chart-container">
                <canvas id="cpuPerRequestChart"></canvas>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Derived Metrics: RAM MB per Request</h3>
            <div class="chart-container">
                <canvas id="ramPerRequestChart"></canvas>
            </div>
        </div>
        
        <script>
            // Prepare data for charts
            const resourceData = """ + json.dumps(resource_data) + """;
            
            // Get all phase numbers
            const allPhases = new Set();
            Object.values(resourceData).forEach(data => {
                Object.keys(data.phases || {}).forEach(phase => allPhases.add(parseInt(phase)));
            });
            const phases = Array.from(allPhases).sort((a, b) => a - b);
            
            // Get API names
            const apiNames = Object.keys(resourceData).map(name => {
                const api = """ + json.dumps(apis) + """.find(a => a.name === name);
                return api ? api.display : name;
            });
            
            // Color palette
            const colors = [
                'rgba(54, 162, 235, 0.8)',
                'rgba(255, 99, 132, 0.8)',
                'rgba(75, 192, 192, 0.8)',
                'rgba(255, 206, 86, 0.8)',
                'rgba(153, 102, 255, 0.8)',
                'rgba(255, 159, 64, 0.8)'
            ];
            
            // CPU Phase Chart
            const cpuPhaseCtx = document.getElementById('cpuPhaseChart');
            if (cpuPhaseCtx) {
                new Chart(cpuPhaseCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    return phaseData ? phaseData.avg_cpu_percent : 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'CPU %'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'Average CPU Usage by Phase'
                            }
                        }
                    }
                });
            }
            
            // Memory Phase Chart
            const memoryPhaseCtx = document.getElementById('memoryPhaseChart');
            if (memoryPhaseCtx) {
                new Chart(memoryPhaseCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    return phaseData ? phaseData.avg_memory_mb : 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'Memory (MB)'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'Average Memory Usage by Phase'
                            }
                        }
                    }
                });
            }
            
            // CPU per Request Chart
            const cpuPerRequestCtx = document.getElementById('cpuPerRequestChart');
            if (cpuPerRequestCtx) {
                new Chart(cpuPerRequestCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    return phaseData ? phaseData.cpu_percent_per_request : 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'CPU %-seconds per Request'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'CPU Efficiency: CPU % per Request (lower is better)'
                            }
                        }
                    }
                });
            }
            
            // RAM per Request Chart
            const ramPerRequestCtx = document.getElementById('ramPerRequestChart');
            if (ramPerRequestCtx) {
                new Chart(ramPerRequestCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    return phaseData ? phaseData.ram_mb_per_request : 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'RAM MB-seconds per Request'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'Memory Efficiency: RAM MB per Request (lower is better)'
                            }
                        }
                    }
                });
            }
        </script>
"""
    
    html_content += """
        <h2>📋 Detailed Results</h2>
"""
    
    # Add detailed results for each API
    for api in api_results:
        if api.get('status') == 'success' and 'metrics' in api:
            m = api['metrics']
            html_content += f"""
        <div class="api-details">
            <h3>{api['display']} ({api['protocol']})</h3>
            <table>
                <tr>
                    <th>Metric</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td>Total Requests</td>
                    <td><strong>{m['total_samples']}</strong></td>
                </tr>
                <tr>
                    <td>Successful Requests</td>
                    <td class="status-success">{m['success_samples']}</td>
                </tr>
                <tr>
                    <td>Failed Requests</td>
                    <td class="status-error">{m['error_samples']}</td>
                </tr>
                <tr>
                    <td>Error Rate</td>
                    <td>{m['error_rate']:.2f}%</td>
                </tr>
                <tr>
                    <td>Test Duration</td>
                    <td>{m['duration_seconds']:.2f} seconds</td>
                </tr>
                <tr>
                    <td>Throughput</td>
                    <td><strong>{m['throughput']:.2f} req/s</strong></td>
                </tr>
                <tr>
                    <td>Average Response Time</td>
                    <td>{m['avg_response']:.2f} ms</td>
                </tr>
                <tr>
                    <td>Min Response Time</td>
                    <td>{m['min_response']:.2f} ms</td>
                </tr>
                <tr>
                    <td>Max Response Time</td>
                    <td>{m['max_response']:.2f} ms</td>
                </tr>
                <tr>
                    <td>P95 Response Time</td>
                    <td>{m['p95_response']:.2f} ms</td>
                </tr>
                <tr>
                    <td>P99 Response Time</td>
                    <td>{m['p99_response']:.2f} ms</td>
                </tr>
            </table>
            <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                Source: {api.get('json_file', 'N/A')}
            </p>
        </div>
"""
    
    html_content += f"""
        <div class="footer">
            <p>Generated by k6 Performance Testing Framework</p>
            <p>Report generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
    </div>
</body>
</html>
"""
    
    # Write HTML file
    with open(html_file, 'w') as f:
        f.write(html_content)
    
    return html_file

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: generate-html-report.py <results_dir> <test_mode> <timestamp>", file=sys.stderr)
        sys.exit(1)
    
    results_dir = sys.argv[1]
    test_mode = sys.argv[2]
    timestamp = sys.argv[3]
    
    html_file = generate_html_report(results_dir, test_mode, timestamp)
    print(f"HTML report generated: {html_file}")

