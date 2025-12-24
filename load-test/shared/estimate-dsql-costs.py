#!/usr/bin/env python3
"""
DSQL Cost Estimation Tool
Estimates Aurora DSQL costs based on load patterns, CloudWatch metrics, or test configurations
"""

import json
import sys
from typing import Dict, Optional, List
from datetime import datetime, timedelta
import argparse

# AWS DSQL Pricing (us-east-1, as of 2024)
# Source: AWS Pricing
DSQL_PRICING = {
    'acu_per_hour': 0.12,  # $0.12 per ACU-hour
    'storage_per_gb_month': 0.10,  # $0.10 per GB per month
    'io_requests_per_million': 0.20,  # $0.20 per million I/O requests
}

# ACU scaling estimates based on load
# These are rough estimates - actual scaling depends on query complexity, data size, etc.
ACU_ESTIMATES = {
    'light': {
        'description': 'Light load: < 50 concurrent connections, simple queries',
        'min_acu': 1,
        'max_acu': 1,
        'typical_acu': 1,
    },
    'medium': {
        'description': 'Medium load: 50-200 concurrent connections, moderate queries',
        'min_acu': 1,
        'max_acu': 2,
        'typical_acu': 1.5,
    },
    'heavy': {
        'description': 'Heavy load: 200-500 concurrent connections, complex queries',
        'min_acu': 2,
        'max_acu': 4,
        'typical_acu': 2.5,
    },
    'extreme': {
        'description': 'Extreme load: 500-2000+ concurrent connections, batch operations',
        'min_acu': 4,
        'max_acu': 8,
        'typical_acu': 5,
    },
}


def estimate_acu_from_threads(threads: int, batch_size: Optional[int] = None) -> Dict[str, float]:
    """
    Estimate ACU capacity based on number of threads/connections
    
    Args:
        threads: Number of concurrent threads/connections
        batch_size: Optional batch size for operations (affects ACU scaling)
    
    Returns:
        Dictionary with min, max, and typical ACU estimates
    """
    # Base ACU on thread count
    if threads < 50:
        load_category = 'light'
    elif threads < 200:
        load_category = 'medium'
    elif threads < 500:
        load_category = 'heavy'
    else:
        load_category = 'extreme'
    
    base_estimate = ACU_ESTIMATES[load_category].copy()
    
    # Adjust for batch operations (batch operations require more ACU)
    if batch_size and batch_size > 100:
        # Large batch operations increase ACU requirements
        batch_multiplier = min(1.5, 1 + (batch_size / 1000))
        base_estimate['typical_acu'] *= batch_multiplier
        base_estimate['max_acu'] = max(base_estimate['max_acu'], base_estimate['typical_acu'] * 1.5)
    
    return base_estimate


def calculate_cost_from_acu(
    acu_hours: float,
    storage_gb: float = 0.0,
    duration_hours: float = 1.0
) -> Dict[str, float]:
    """
    Calculate DSQL cost from ACU usage
    
    Args:
        acu_hours: Total ACU-hours consumed (can be fractional, e.g., 2.5 ACU × 3 hours = 7.5 ACU-hours)
        storage_gb: Storage in GB
        duration_hours: Duration in hours (for storage cost calculation)
    
    Returns:
        Dictionary with cost breakdown
    """
    compute_cost = acu_hours * DSQL_PRICING['acu_per_hour']
    storage_cost = storage_gb * DSQL_PRICING['storage_per_gb_month'] * (duration_hours / 730)
    
    return {
        'compute_cost': compute_cost,
        'storage_cost': storage_cost,
        'total_cost': compute_cost + storage_cost,
        'acu_hours': acu_hours,
        'storage_gb': storage_gb,
    }


def estimate_test_run_cost(
    threads: int,
    duration_hours: float,
    batch_size: Optional[int] = None,
    storage_gb: float = 0.0
) -> Dict[str, any]:
    """
    Estimate cost for a test run based on load parameters
    
    Args:
        threads: Number of concurrent threads
        duration_hours: Test duration in hours
        batch_size: Optional batch size
        storage_gb: Storage in GB
    
    Returns:
        Dictionary with cost estimate and details
    """
    acu_estimate = estimate_acu_from_threads(threads, batch_size)
    
    # Use typical ACU for cost estimation
    typical_acu = acu_estimate['typical_acu']
    acu_hours = typical_acu * duration_hours
    
    costs = calculate_cost_from_acu(acu_hours, storage_gb, duration_hours)
    
    return {
        'threads': threads,
        'duration_hours': duration_hours,
        'batch_size': batch_size,
        'acu_estimate': acu_estimate,
        'estimated_acu': typical_acu,
        'acu_hours': acu_hours,
        **costs,
    }


def estimate_from_cloudwatch_metrics(
    cluster_resource_id: str,
    start_time: datetime,
    end_time: datetime,
    region: str = 'us-east-1'
) -> Dict[str, any]:
    """
    Estimate cost from CloudWatch metrics (requires boto3)
    
    Args:
        cluster_resource_id: DSQL cluster resource ID
        start_time: Start time for metrics
        end_time: End time for metrics
        region: AWS region
    
    Returns:
        Dictionary with cost estimate from actual metrics
    """
    try:
        import boto3
        cloudwatch = boto3.client('cloudwatch', region_name=region)
        
        # Get ACU capacity metrics
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='ServerlessDatabaseCapacity',
            Dimensions=[
                {'Name': 'DBClusterIdentifier', 'Value': cluster_resource_id}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,  # 5-minute periods
            Statistics=['Average']
        )
        
        # Calculate total ACU-hours
        total_acu_hours = 0.0
        datapoints = response.get('Datapoints', [])
        
        if not datapoints:
            return {
                'error': 'No metrics found',
                'message': 'No CloudWatch metrics available for the specified time range'
            }
        
        # Calculate ACU-hours from datapoints
        # Each datapoint represents average ACU over a 5-minute period
        for point in datapoints:
            acu_value = point.get('Average', 0)
            # 5 minutes = 5/60 hours = 0.0833 hours
            acu_hours = acu_value * (5 / 60)
            total_acu_hours += acu_hours
        
        # Get storage metrics
        storage_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='VolumeBytesUsed',
            Dimensions=[
                {'Name': 'DBClusterIdentifier', 'Value': cluster_resource_id}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,  # 1-hour periods
            Statistics=['Average']
        )
        
        storage_datapoints = storage_response.get('Datapoints', [])
        avg_storage_gb = 0.0
        if storage_datapoints:
            # Get average storage (convert bytes to GB)
            storage_values = [p.get('Average', 0) / (1024**3) for p in storage_datapoints]
            avg_storage_gb = sum(storage_values) / len(storage_values) if storage_values else 0.0
        
        duration_hours = (end_time - start_time).total_seconds() / 3600.0
        costs = calculate_cost_from_acu(total_acu_hours, avg_storage_gb, duration_hours)
        
        return {
            'source': 'cloudwatch_metrics',
            'cluster_resource_id': cluster_resource_id,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'duration_hours': duration_hours,
            'datapoints_count': len(datapoints),
            'total_acu_hours': total_acu_hours,
            'avg_storage_gb': avg_storage_gb,
            **costs,
        }
        
    except ImportError:
        return {
            'error': 'boto3_not_installed',
            'message': 'boto3 is required for CloudWatch metrics. Install with: pip install boto3'
        }
    except Exception as e:
        return {
            'error': str(e),
            'message': f'Failed to retrieve CloudWatch metrics: {str(e)}'
        }


def estimate_from_test_config(test_config_path: str) -> List[Dict[str, any]]:
    """
    Estimate costs for all tests in a test configuration file
    
    Args:
        test_config_path: Path to test-config.json file
    
    Returns:
        List of cost estimates for each test configuration
    """
    with open(test_config_path, 'r') as f:
        config = json.load(f)
    
    estimates = []
    
    # Estimate baseline
    baseline = config.get('baseline', {})
    if baseline:
        estimate = estimate_test_run_cost(
            threads=baseline.get('threads', 10),
            duration_hours=0.5,  # Assume 30 minutes for baseline
            batch_size=baseline.get('batch_size'),
        )
        estimate['test_name'] = 'baseline'
        estimates.append(estimate)
    
    # Estimate for each test group
    test_groups = config.get('test_groups', {})
    for group_name, group_config in test_groups.items():
        threads_list = group_config.get('threads', [group_config.get('threads', 10)])
        if not isinstance(threads_list, list):
            threads_list = [threads_list]
        
        iterations_list = group_config.get('iterations', [group_config.get('iterations', 20)])
        if not isinstance(iterations_list, list):
            iterations_list = [iterations_list]
        
        count_list = group_config.get('count', [group_config.get('count', 1)])
        if not isinstance(count_list, list):
            count_list = [count_list]
        
        batch_size = group_config.get('batch_size')
        
        # Estimate for each combination (simplified - takes first of each)
        threads = threads_list[0] if threads_list else 10
        iterations = iterations_list[0] if iterations_list else 20
        count = count_list[0] if count_list else 1
        
        # Rough duration estimate: iterations × count × 0.1 seconds per operation
        # This is a rough estimate - actual duration depends on many factors
        estimated_seconds = iterations * count * 0.1
        duration_hours = max(0.1, estimated_seconds / 3600.0)  # Minimum 0.1 hours
        
        estimate = estimate_test_run_cost(
            threads=threads,
            duration_hours=duration_hours,
            batch_size=batch_size,
        )
        estimate['test_name'] = group_name
        estimate['iterations'] = iterations
        estimate['count'] = count
        estimates.append(estimate)
    
    return estimates


def main():
    parser = argparse.ArgumentParser(description='Estimate DSQL costs')
    parser.add_argument('--threads', type=int, help='Number of concurrent threads')
    parser.add_argument('--duration-hours', type=float, help='Duration in hours')
    parser.add_argument('--batch-size', type=int, help='Batch size for operations')
    parser.add_argument('--storage-gb', type=float, default=0.0, help='Storage in GB')
    parser.add_argument('--test-config', type=str, help='Path to test-config.json file')
    parser.add_argument('--cloudwatch', action='store_true', help='Use CloudWatch metrics')
    parser.add_argument('--cluster-id', type=str, help='DSQL cluster resource ID (for CloudWatch)')
    parser.add_argument('--start-time', type=str, help='Start time (ISO format) for CloudWatch metrics')
    parser.add_argument('--end-time', type=str, help='End time (ISO format) for CloudWatch metrics')
    parser.add_argument('--region', type=str, default='us-east-1', help='AWS region')
    parser.add_argument('--format', type=str, choices=['json', 'table'], default='json', help='Output format')
    
    args = parser.parse_args()
    
    if args.cloudwatch:
        if not args.cluster_id or not args.start_time or not args.end_time:
            print("Error: --cluster-id, --start-time, and --end-time are required for CloudWatch metrics", file=sys.stderr)
            sys.exit(1)
        
        start_time = datetime.fromisoformat(args.start_time.replace('Z', '+00:00'))
        end_time = datetime.fromisoformat(args.end_time.replace('Z', '+00:00'))
        
        result = estimate_from_cloudwatch_metrics(
            args.cluster_id,
            start_time,
            end_time,
            args.region
        )
        
        if args.format == 'json':
            print(json.dumps(result, indent=2))
        else:
            if 'error' in result:
                print(f"Error: {result['error']}")
                print(f"Message: {result['message']}")
            else:
                print(f"DSQL Cost Estimate (CloudWatch Metrics)")
                print(f"Cluster: {result['cluster_resource_id']}")
                print(f"Duration: {result['duration_hours']:.2f} hours")
                print(f"Total ACU-hours: {result['total_acu_hours']:.2f}")
                print(f"Average Storage: {result['avg_storage_gb']:.2f} GB")
                print(f"Compute Cost: ${result['compute_cost']:.4f}")
                print(f"Storage Cost: ${result['storage_cost']:.4f}")
                print(f"Total Cost: ${result['total_cost']:.4f}")
    
    elif args.test_config:
        estimates = estimate_from_test_config(args.test_config)
        
        if args.format == 'json':
            print(json.dumps(estimates, indent=2))
        else:
            print("DSQL Cost Estimates from Test Configuration")
            print("=" * 80)
            total_cost = 0.0
            for est in estimates:
                print(f"\nTest: {est['test_name']}")
                print(f"  Threads: {est['threads']}")
                print(f"  Duration: {est['duration_hours']:.2f} hours")
                print(f"  Estimated ACU: {est['estimated_acu']:.2f}")
                print(f"  ACU-hours: {est['acu_hours']:.2f}")
                print(f"  Cost: ${est['total_cost']:.4f}")
                total_cost += est['total_cost']
            print("\n" + "=" * 80)
            print(f"Total Estimated Cost: ${total_cost:.4f}")
    
    elif args.threads and args.duration_hours:
        result = estimate_test_run_cost(
            args.threads,
            args.duration_hours,
            args.batch_size,
            args.storage_gb
        )
        
        if args.format == 'json':
            print(json.dumps(result, indent=2))
        else:
            print("DSQL Cost Estimate")
            print("=" * 80)
            print(f"Threads: {result['threads']}")
            print(f"Duration: {result['duration_hours']:.2f} hours")
            if result['batch_size']:
                print(f"Batch Size: {result['batch_size']}")
            print(f"\nACU Estimate:")
            print(f"  Min: {result['acu_estimate']['min_acu']} ACU")
            print(f"  Max: {result['acu_estimate']['max_acu']} ACU")
            print(f"  Typical: {result['estimated_acu']:.2f} ACU")
            print(f"  Description: {result['acu_estimate']['description']}")
            print(f"\nCost Breakdown:")
            print(f"  ACU-hours: {result['acu_hours']:.2f}")
            print(f"  Compute Cost: ${result['compute_cost']:.4f}")
            print(f"  Storage Cost: ${result['storage_cost']:.4f}")
            print(f"  Total Cost: ${result['total_cost']:.4f}")
    
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()

