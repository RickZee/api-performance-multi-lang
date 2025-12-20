#!/usr/bin/env python3
"""DSQL Load Test Script - Parallel Lambda invocations for load testing."""

import boto3
import json
import time
import argparse
import statistics
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Optional
from datetime import datetime


class DSQLLoadTest:
    """DSQL Load Test orchestrator."""
    
    def __init__(self, lambda_function_name: str, region: str = 'us-east-1'):
        """Initialize load test client.
        
        Args:
            lambda_function_name: Name of the Lambda function to invoke
            region: AWS region
        """
        self.lambda_client = boto3.client('lambda', region_name=region)
        self.function_name = lambda_function_name
        self.region = region
    
    def invoke_lambda(self, payload: Dict, lambda_index: int) -> Dict:
        """Invoke a single Lambda function.
        
        Args:
            payload: Payload to send to Lambda
            lambda_index: Index of this Lambda invocation (for tracking)
            
        Returns:
            Dict with response and metrics
        """
        start_time = time.time()
        try:
            response = self.lambda_client.invoke(
                FunctionName=self.function_name,
                InvocationType='RequestResponse',  # Synchronous for metrics
                Payload=json.dumps(payload)
            )
            
            duration_ms = (time.time() - start_time) * 1000
            
            # Parse response
            response_payload = json.loads(response['Payload'].read())
            
            if response.get('StatusCode') == 200:
                body = json.loads(response_payload.get('body', '{}')) if isinstance(response_payload.get('body'), str) else response_payload.get('body', {})
                result = body.get('result', {})
                
                return {
                    'success': True,
                    'lambda_index': lambda_index,
                    'duration_ms': duration_ms,
                    'lambda_duration_ms': result.get('duration_ms', 0),
                    'success_count': result.get('success_count', 0),
                    'error_count': result.get('error_count', 0),
                    'inserts_per_second': result.get('inserts_per_second', 0),
                    'total_inserts': result.get('total_inserts', 0),
                    'scenario': result.get('scenario', ''),
                    'iterations': result.get('iterations', 0),
                    'count': result.get('count', 0)
                }
            else:
                return {
                    'success': False,
                    'lambda_index': lambda_index,
                    'duration_ms': duration_ms,
                    'error': f"Lambda returned status {response.get('StatusCode')}",
                    'response': response_payload
                }
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            return {
                'success': False,
                'lambda_index': lambda_index,
                'duration_ms': duration_ms,
                'error': str(e)
            }
    
    def warm_up(self, num_invocations: int = 20):
        """Warm up Lambda functions to avoid cold starts affecting metrics.
        
        Args:
            num_invocations: Number of warm-up invocations
        """
        print(f"Warming up with {num_invocations} invocations...")
        warm_up_payload = {
            "scenario": "individual",
            "count": 1,
            "iterations": 1,
            "event_type": "CarCreated"
        }
        
        with ThreadPoolExecutor(max_workers=min(num_invocations, 20)) as executor:
            futures = [
                executor.submit(self.invoke_lambda, warm_up_payload, i)
                for i in range(num_invocations)
            ]
            
            for future in as_completed(futures):
                try:
                    result = future.result()
                    if result.get('success'):
                        print(f"  Warm-up invocation {result['lambda_index']} completed")
                except Exception as e:
                    print(f"  Warm-up error: {e}")
        
        print("Warm-up complete.\n")
        time.sleep(2)  # Brief pause after warm-up
    
    def run_scenario_1_individual(
        self, 
        num_lambdas: int = 1000, 
        iterations: int = 10, 
        inserts_per_iteration: int = 1,
        event_type: str = "CarCreated"
    ) -> Dict:
        """Run Scenario 1: Individual inserts with loop.
        
        Invokes num_lambdas Lambda functions in parallel, each performing
        a loop of 'iterations' times, each iteration executing 'inserts_per_iteration'
        individual INSERT statements (one row per statement).
        
        Args:
            num_lambdas: Number of parallel Lambda invocations
            iterations: Number of loop iterations per Lambda
            inserts_per_iteration: Number of inserts per iteration
            event_type: Type of event to generate
            
        Returns:
            Dict with aggregated metrics
        """
        print(f"\n{'='*60}")
        print(f"Scenario 1: Individual Inserts")
        print(f"{'='*60}")
        print(f"Parallel Lambdas: {num_lambdas}")
        print(f"Iterations per Lambda: {iterations}")
        print(f"Inserts per iteration: {inserts_per_iteration}")
        print(f"Total inserts per Lambda: {iterations * inserts_per_iteration}")
        print(f"Total inserts (all Lambdas): {num_lambdas * iterations * inserts_per_iteration}")
        print(f"Event type: {event_type}")
        print(f"{'='*60}\n")
        
        start_time = time.time()
        results = []
        completed = 0
        
        payload = {
            "scenario": "individual",
            "count": inserts_per_iteration,
            "iterations": iterations,
            "event_type": event_type
        }
        
        with ThreadPoolExecutor(max_workers=min(num_lambdas, 1000)) as executor:
            futures = {
                executor.submit(self.invoke_lambda, {**payload, "lambda_index": i}, i): i
                for i in range(num_lambdas)
            }
            
            for future in as_completed(futures):
                try:
                    result = future.result()
                    results.append(result)
                    completed += 1
                    
                    if completed % 100 == 0 or completed == num_lambdas:
                        print(f"Progress: {completed}/{num_lambdas} Lambdas completed")
                except Exception as e:
                    print(f"Error processing result: {e}")
                    results.append({
                        'success': False,
                        'lambda_index': futures[future],
                        'error': str(e)
                    })
        
        total_duration_ms = (time.time() - start_time) * 1000
        
        return self._aggregate_metrics(results, total_duration_ms, "individual")
    
    def run_scenario_2_batch(
        self, 
        num_lambdas: int = 1000, 
        iterations: int = 10, 
        batch_size: int = 100,
        event_type: str = "CarCreated"
    ) -> Dict:
        """Run Scenario 2: Batch inserts with loop.
        
        Invokes num_lambdas Lambda functions in parallel, each performing
        a loop of 'iterations' times, each iteration executing 1 batch INSERT
        statement with batch_size rows (multi-value INSERT).
        
        Args:
            num_lambdas: Number of parallel Lambda invocations
            iterations: Number of loop iterations per Lambda
            batch_size: Number of rows per batch
            event_type: Type of event to generate
            
        Returns:
            Dict with aggregated metrics
        """
        print(f"\n{'='*60}")
        print(f"Scenario 2: Batch Inserts")
        print(f"{'='*60}")
        print(f"Parallel Lambdas: {num_lambdas}")
        print(f"Iterations per Lambda: {iterations}")
        print(f"Rows per batch: {batch_size}")
        print(f"Total rows per Lambda: {iterations * batch_size}")
        print(f"Total rows (all Lambdas): {num_lambdas * iterations * batch_size}")
        print(f"Event type: {event_type}")
        print(f"{'='*60}\n")
        
        start_time = time.time()
        results = []
        completed = 0
        
        payload = {
            "scenario": "batch",
            "count": batch_size,
            "iterations": iterations,
            "event_type": event_type
        }
        
        with ThreadPoolExecutor(max_workers=min(num_lambdas, 1000)) as executor:
            futures = {
                executor.submit(self.invoke_lambda, {**payload, "lambda_index": i}, i): i
                for i in range(num_lambdas)
            }
            
            for future in as_completed(futures):
                try:
                    result = future.result()
                    results.append(result)
                    completed += 1
                    
                    if completed % 100 == 0 or completed == num_lambdas:
                        print(f"Progress: {completed}/{num_lambdas} Lambdas completed")
                except Exception as e:
                    print(f"Error processing result: {e}")
                    results.append({
                        'success': False,
                        'lambda_index': futures[future],
                        'error': str(e)
                    })
        
        total_duration_ms = (time.time() - start_time) * 1000
        
        return self._aggregate_metrics(results, total_duration_ms, "batch")
    
    def _aggregate_metrics(self, results: List[Dict], total_duration_ms: float, scenario: str) -> Dict:
        """Aggregate metrics from all Lambda invocations.
        
        Args:
            results: List of result dicts from Lambda invocations
            total_duration_ms: Total duration in milliseconds
            scenario: Scenario name ("individual" or "batch")
            
        Returns:
            Dict with aggregated metrics
        """
        successful = [r for r in results if r.get('success')]
        failed = [r for r in results if not r.get('success')]
        
        total_inserts = sum(r.get('success_count', 0) for r in successful)
        total_errors = sum(r.get('error_count', 0) for r in successful) + len(failed)
        
        # Latency metrics (invocation duration)
        latencies = [r.get('duration_ms', 0) for r in successful]
        lambda_durations = [r.get('lambda_duration_ms', 0) for r in successful]
        
        # Throughput
        total_seconds = total_duration_ms / 1000
        throughput = total_inserts / total_seconds if total_seconds > 0 else 0
        
        # Lambda-level throughput
        lambda_throughputs = [r.get('inserts_per_second', 0) for r in successful]
        
        metrics = {
            'scenario': scenario,
            'total_lambdas': len(results),
            'successful_lambdas': len(successful),
            'failed_lambdas': len(failed),
            'success_rate': (len(successful) / len(results) * 100) if results else 0,
            'total_inserts': total_inserts,
            'total_errors': total_errors,
            'total_duration_ms': total_duration_ms,
            'total_duration_seconds': total_seconds,
            'throughput_inserts_per_second': throughput,
            'latency_ms': {
                'min': min(latencies) if latencies else 0,
                'max': max(latencies) if latencies else 0,
                'avg': statistics.mean(latencies) if latencies else 0,
                'median': statistics.median(latencies) if latencies else 0,
                'p95': self._percentile(latencies, 95) if latencies else 0,
                'p99': self._percentile(latencies, 99) if latencies else 0
            },
            'lambda_duration_ms': {
                'min': min(lambda_durations) if lambda_durations else 0,
                'max': max(lambda_durations) if lambda_durations else 0,
                'avg': statistics.mean(lambda_durations) if lambda_durations else 0,
                'median': statistics.median(lambda_durations) if lambda_durations else 0,
                'p95': self._percentile(lambda_durations, 95) if lambda_durations else 0,
                'p99': self._percentile(lambda_durations, 99) if lambda_durations else 0
            },
            'lambda_throughput': {
                'min': min(lambda_throughputs) if lambda_throughputs else 0,
                'max': max(lambda_throughputs) if lambda_throughputs else 0,
                'avg': statistics.mean(lambda_throughputs) if lambda_throughputs else 0,
                'median': statistics.median(lambda_throughputs) if lambda_throughputs else 0
            },
            'errors': [{'lambda_index': r.get('lambda_index'), 'error': r.get('error')} for r in failed[:10]]  # First 10 errors
        }
        
        return metrics
    
    def _percentile(self, data: List[float], percentile: int) -> float:
        """Calculate percentile value.
        
        Args:
            data: List of values
            percentile: Percentile to calculate (0-100)
            
        Returns:
            Percentile value
        """
        if not data:
            return 0
        sorted_data = sorted(data)
        index = int(len(sorted_data) * percentile / 100)
        if index >= len(sorted_data):
            index = len(sorted_data) - 1
        return sorted_data[index]
    
    def print_summary(self, metrics: Dict):
        """Print formatted summary of metrics.
        
        Args:
            metrics: Aggregated metrics dict
        """
        print(f"\n{'='*60}")
        print(f"Results Summary - {metrics['scenario'].upper()} Scenario")
        print(f"{'='*60}")
        print(f"Total Lambdas: {metrics['total_lambdas']}")
        print(f"Successful: {metrics['successful_lambdas']}")
        print(f"Failed: {metrics['failed_lambdas']}")
        print(f"Success Rate: {metrics['success_rate']:.2f}%")
        print(f"\nTotal Inserts: {metrics['total_inserts']:,}")
        print(f"Total Errors: {metrics['total_errors']:,}")
        print(f"Total Duration: {metrics['total_duration_seconds']:.2f} seconds")
        print(f"Throughput: {metrics['throughput_inserts_per_second']:,.2f} inserts/second")
        print(f"\nInvocation Latency (ms):")
        print(f"  Min: {metrics['latency_ms']['min']:.2f}")
        print(f"  Max: {metrics['latency_ms']['max']:.2f}")
        print(f"  Avg: {metrics['latency_ms']['avg']:.2f}")
        print(f"  Median: {metrics['latency_ms']['median']:.2f}")
        print(f"  P95: {metrics['latency_ms']['p95']:.2f}")
        print(f"  P99: {metrics['latency_ms']['p99']:.2f}")
        print(f"\nLambda Execution Duration (ms):")
        print(f"  Min: {metrics['lambda_duration_ms']['min']:.2f}")
        print(f"  Max: {metrics['lambda_duration_ms']['max']:.2f}")
        print(f"  Avg: {metrics['lambda_duration_ms']['avg']:.2f}")
        print(f"  Median: {metrics['lambda_duration_ms']['median']:.2f}")
        print(f"  P95: {metrics['lambda_duration_ms']['p95']:.2f}")
        print(f"  P99: {metrics['lambda_duration_ms']['p99']:.2f}")
        print(f"\nLambda Throughput (inserts/second):")
        print(f"  Min: {metrics['lambda_throughput']['min']:.2f}")
        print(f"  Max: {metrics['lambda_throughput']['max']:.2f}")
        print(f"  Avg: {metrics['lambda_throughput']['avg']:.2f}")
        print(f"  Median: {metrics['lambda_throughput']['median']:.2f}")
        
        if metrics['errors']:
            print(f"\nErrors (showing first 10):")
            for error in metrics['errors']:
                print(f"  Lambda {error['lambda_index']}: {error['error']}")
        
        print(f"{'='*60}\n")


def load_config(config_path: str = "config.json") -> Dict:
    """Load configuration from JSON file.
    
    Args:
        config_path: Path to config file
        
    Returns:
        Config dict
    """
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Config file {config_path} not found, using defaults")
        return {}


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='DSQL Load Test - Parallel Lambda invocations')
    parser.add_argument('--function-name', type=str, help='Lambda function name')
    parser.add_argument('--region', type=str, default='us-east-1', help='AWS region')
    parser.add_argument('--scenario', type=str, choices=['1', '2', 'both'], default='both', help='Scenario to run')
    parser.add_argument('--num-lambdas', type=int, help='Number of parallel Lambdas')
    parser.add_argument('--iterations', type=int, help='Number of loop iterations per Lambda')
    parser.add_argument('--count', type=int, help='Inserts per iteration (scenario 1) or rows per batch (scenario 2)')
    parser.add_argument('--event-type', type=str, help='Event type to generate')
    parser.add_argument('--warm-up', type=int, default=20, help='Number of warm-up invocations')
    parser.add_argument('--config', type=str, default='config.json', help='Path to config file')
    parser.add_argument('--no-warm-up', action='store_true', help='Skip warm-up phase')
    
    args = parser.parse_args()
    
    # Load config
    config = load_config(args.config)
    
    # Get Lambda function name
    function_name = args.function_name or config.get('lambda_function_name', 'dsql-load-test-lambda')
    region = args.region or config.get('region', 'us-east-1')
    
    # Initialize test client
    test = DSQLLoadTest(function_name, region)
    
    # Warm up
    if not args.no_warm_up:
        warm_up_count = args.warm_up or config.get('warm_up_invocations', 20)
        test.warm_up(warm_up_count)
    
    results = {}
    
    # Run Scenario 1
    if args.scenario in ['1', 'both']:
        scenario_1_config = config.get('scenario_1', {})
        num_lambdas = args.num_lambdas or scenario_1_config.get('num_lambdas', 1000)
        iterations = args.iterations or scenario_1_config.get('iterations', 10)
        inserts_per_iteration = args.count or scenario_1_config.get('inserts_per_iteration', 1)
        event_type = args.event_type or config.get('event_type', 'CarCreated')
        
        results['scenario_1'] = test.run_scenario_1_individual(
            num_lambdas=num_lambdas,
            iterations=iterations,
            inserts_per_iteration=inserts_per_iteration,
            event_type=event_type
        )
        test.print_summary(results['scenario_1'])
    
    # Run Scenario 2
    if args.scenario in ['2', 'both']:
        scenario_2_config = config.get('scenario_2', {})
        num_lambdas = args.num_lambdas or scenario_2_config.get('num_lambdas', 1000)
        iterations = args.iterations or scenario_2_config.get('iterations', 10)
        batch_size = args.count or scenario_2_config.get('rows_per_batch', 100)
        event_type = args.event_type or config.get('event_type', 'CarCreated')
        
        results['scenario_2'] = test.run_scenario_2_batch(
            num_lambdas=num_lambdas,
            iterations=iterations,
            batch_size=batch_size,
            event_type=event_type
        )
        test.print_summary(results['scenario_2'])
    
    # Comparison if both scenarios ran
    if args.scenario == 'both' and 'scenario_1' in results and 'scenario_2' in results:
        print(f"\n{'='*60}")
        print("Comparison: Individual vs Batch")
        print(f"{'='*60}")
        s1 = results['scenario_1']
        s2 = results['scenario_2']
        
        print(f"\nThroughput:")
        print(f"  Individual: {s1['throughput_inserts_per_second']:,.2f} inserts/second")
        print(f"  Batch:      {s2['throughput_inserts_per_second']:,.2f} inserts/second")
        print(f"  Ratio:      {s2['throughput_inserts_per_second'] / s1['throughput_inserts_per_second']:.2f}x" if s1['throughput_inserts_per_second'] > 0 else "  Ratio:      N/A")
        
        print(f"\nAverage Latency:")
        print(f"  Individual: {s1['latency_ms']['avg']:.2f} ms")
        print(f"  Batch:      {s2['latency_ms']['avg']:.2f} ms")
        
        print(f"\nP95 Latency:")
        print(f"  Individual: {s1['latency_ms']['p95']:.2f} ms")
        print(f"  Batch:      {s2['latency_ms']['p95']:.2f} ms")
        
        print(f"{'='*60}\n")
    
    # Save results to file
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    results_file = f"results_{timestamp}.json"
    with open(results_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"Results saved to {results_file}")


if __name__ == '__main__':
    main()
