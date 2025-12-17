#!/usr/bin/env python3
"""
Lambda Cost Calculator
Calculates AWS Lambda and API Gateway costs based on execution metrics
"""

from typing import Dict, Optional
import json


# AWS Lambda Pricing (us-east-1, as of 2024)
# Source: https://aws.amazon.com/lambda/pricing/
LAMBDA_PRICING = {
    # Compute cost: $0.0000166667 per GB-second
    'compute_per_gb_second': 0.0000166667,
    
    # Request cost: $0.20 per 1 million requests
    'requests_per_million': 0.20,
    
    # Free tier: 1M requests and 400,000 GB-seconds per month
    'free_tier_requests': 1000000,
    'free_tier_gb_seconds': 400000,
}

# API Gateway HTTP API Pricing (us-east-1, as of 2024)
# Source: https://aws.amazon.com/api-gateway/pricing/
API_GATEWAY_PRICING = {
    # HTTP API: $0.00085 per 1 million requests
    'http_api_requests_per_million': 0.00085,
    
    # Data transfer out: $0.09 per GB (first 10TB per month)
    'data_transfer_out_per_gb': 0.09,
    
    # Data transfer in: Free
    'data_transfer_in_per_gb': 0.0,
}


def calculate_lambda_compute_cost(
    billed_duration_ms: float,
    memory_size_mb: float,
    num_invocations: int = 1
) -> float:
    """
    Calculate Lambda compute cost based on GB-seconds.
    
    Args:
        billed_duration_ms: Billed duration in milliseconds (per invocation)
        memory_size_mb: Memory size allocated in MB
        num_invocations: Number of invocations
    
    Returns:
        Total compute cost in USD
    """
    # Convert to GB-seconds
    duration_seconds = (billed_duration_ms / 1000.0) * num_invocations
    memory_gb = memory_size_mb / 1024.0
    gb_seconds = duration_seconds * memory_gb
    
    # Calculate cost
    cost = gb_seconds * LAMBDA_PRICING['compute_per_gb_second']
    
    return max(cost, 0.0)


def calculate_lambda_request_cost(num_requests: int) -> float:
    """
    Calculate Lambda request cost.
    
    Args:
        num_requests: Number of requests
    
    Returns:
        Total request cost in USD
    """
    # Calculate cost per million requests
    cost = (num_requests / 1000000.0) * LAMBDA_PRICING['requests_per_million']
    
    return max(cost, 0.0)


def calculate_api_gateway_cost(
    num_requests: int,
    data_transfer_gb: float = 0.0
) -> Dict[str, float]:
    """
    Calculate API Gateway HTTP API cost.
    
    Args:
        num_requests: Number of API Gateway requests
        data_transfer_gb: Data transfer out in GB
    
    Returns:
        Dictionary with cost breakdown
    """
    # Request cost
    request_cost = (num_requests / 1000000.0) * API_GATEWAY_PRICING['http_api_requests_per_million']
    
    # Data transfer cost
    data_transfer_cost = data_transfer_gb * API_GATEWAY_PRICING['data_transfer_out_per_gb']
    
    return {
        'api_gateway_request_cost': max(request_cost, 0.0),
        'api_gateway_data_transfer_cost': max(data_transfer_cost, 0.0),
        'api_gateway_total_cost': max(request_cost + data_transfer_cost, 0.0),
    }


def calculate_provisioned_concurrency_cost(
    memory_size_mb: float,
    provisioned_capacity: int,
    duration_hours: float
) -> float:
    """
    Calculate Provisioned Concurrency cost.
    
    Args:
        memory_size_mb: Memory size in MB
        provisioned_capacity: Number of provisioned concurrent executions
        duration_hours: Duration in hours
    
    Returns:
        Total provisioned concurrency cost in USD
    """
    # Provisioned Concurrency: $0.0000041667 per GB-second
    memory_gb = memory_size_mb / 1024.0
    gb_seconds = memory_gb * provisioned_capacity * duration_hours * 3600.0
    cost = gb_seconds * 0.0000041667
    
    return max(cost, 0.0)


def calculate_lambda_total_cost(
    num_invocations: int,
    avg_billed_duration_ms: float,
    memory_size_mb: float,
    data_transfer_gb: float = 0.0,
    include_api_gateway: bool = True,
    provisioned_concurrency: Optional[int] = None,
    duration_hours: Optional[float] = None
) -> Dict[str, any]:
    """
    Calculate total Lambda cost including compute, requests, and API Gateway.
    
    Args:
        num_invocations: Total number of Lambda invocations
        avg_billed_duration_ms: Average billed duration per invocation in milliseconds
        memory_size_mb: Memory size allocated in MB
        data_transfer_gb: Data transfer out in GB (for API Gateway)
        include_api_gateway: Whether to include API Gateway costs
        provisioned_concurrency: Optional provisioned concurrency capacity
        duration_hours: Optional duration in hours (for provisioned concurrency)
    
    Returns:
        Dictionary with detailed cost breakdown
    """
    # Lambda compute cost
    compute_cost = calculate_lambda_compute_cost(
        avg_billed_duration_ms,
        memory_size_mb,
        num_invocations
    )
    
    # Lambda request cost
    request_cost = calculate_lambda_request_cost(num_invocations)
    
    # API Gateway cost
    api_gateway_costs = {}
    if include_api_gateway:
        api_gateway_costs = calculate_api_gateway_cost(num_invocations, data_transfer_gb)
    
    # Provisioned Concurrency cost
    provisioned_cost = 0.0
    if provisioned_concurrency and duration_hours:
        provisioned_cost = calculate_provisioned_concurrency_cost(
            memory_size_mb,
            provisioned_concurrency,
            duration_hours
        )
    
    # Total cost
    total_cost = (
        compute_cost +
        request_cost +
        api_gateway_costs.get('api_gateway_total_cost', 0.0) +
        provisioned_cost
    )
    
    # Cost per 1K requests
    cost_per_1000_requests = (total_cost / num_invocations * 1000.0) if num_invocations > 0 else 0.0
    
    return {
        'num_invocations': num_invocations,
        'memory_size_mb': memory_size_mb,
        'avg_billed_duration_ms': avg_billed_duration_ms,
        'lambda_compute_cost': compute_cost,
        'lambda_request_cost': request_cost,
        'lambda_total_cost': compute_cost + request_cost,
        'api_gateway_request_cost': api_gateway_costs.get('api_gateway_request_cost', 0.0),
        'api_gateway_data_transfer_cost': api_gateway_costs.get('api_gateway_data_transfer_cost', 0.0),
        'api_gateway_total_cost': api_gateway_costs.get('api_gateway_total_cost', 0.0),
        'provisioned_concurrency_cost': provisioned_cost,
        'total_cost': total_cost,
        'cost_per_request': total_cost / num_invocations if num_invocations > 0 else 0.0,
        'cost_per_1000_requests': cost_per_1000_requests,
    }


def calculate_cost_for_lambda_api(
    api_name: str,
    num_invocations: int,
    avg_billed_duration_ms: float,
    memory_size_mb: float,
    data_transfer_gb: float = 0.0,
    include_api_gateway: bool = True,
    provisioned_concurrency: Optional[int] = None,
    duration_hours: Optional[float] = None
) -> Dict[str, any]:
    """
    Calculate cost for a specific Lambda API.
    
    Args:
        api_name: Name of the Lambda API
        num_invocations: Total number of invocations
        avg_billed_duration_ms: Average billed duration per invocation
        memory_size_mb: Memory size allocated
        data_transfer_gb: Data transfer out in GB
        include_api_gateway: Whether to include API Gateway costs
        provisioned_concurrency: Optional provisioned concurrency
        duration_hours: Optional duration for provisioned concurrency
    
    Returns:
        Dictionary with API name and cost breakdown
    """
    costs = calculate_lambda_total_cost(
        num_invocations=num_invocations,
        avg_billed_duration_ms=avg_billed_duration_ms,
        memory_size_mb=memory_size_mb,
        data_transfer_gb=data_transfer_gb,
        include_api_gateway=include_api_gateway,
        provisioned_concurrency=provisioned_concurrency,
        duration_hours=duration_hours
    )
    
    return {
        'api_name': api_name,
        **costs
    }


def compare_lambda_memory_configs(
    num_invocations: int,
    duration_ms_by_memory: Dict[int, float],  # memory_mb -> avg_duration_ms
    data_transfer_gb: float = 0.0,
    include_api_gateway: bool = True
) -> Dict[int, Dict[str, any]]:
    """
    Compare costs across different memory configurations.
    
    Args:
        num_invocations: Number of invocations
        duration_ms_by_memory: Dictionary mapping memory size (MB) to average duration (ms)
        data_transfer_gb: Data transfer out in GB
        include_api_gateway: Whether to include API Gateway costs
    
    Returns:
        Dictionary mapping memory size to cost breakdown
    """
    results = {}
    
    for memory_mb, avg_duration_ms in duration_ms_by_memory.items():
        # Calculate billed duration (rounded up to nearest 100ms)
        billed_duration_ms = ((avg_duration_ms + 99) // 100) * 100
        
        costs = calculate_lambda_total_cost(
            num_invocations=num_invocations,
            avg_billed_duration_ms=billed_duration_ms,
            memory_size_mb=memory_mb,
            data_transfer_gb=data_transfer_gb,
            include_api_gateway=include_api_gateway
        )
        
        results[memory_mb] = costs
    
    return results


if __name__ == '__main__':
    # Example usage
    import sys
    
    if len(sys.argv) > 1:
        # CLI mode
        if sys.argv[1] == 'compare-memory':
            # Compare memory configurations
            # Usage: python calculate-lambda-costs.py compare-memory <invocations> <memory1>:<duration1> [<memory2>:<duration2> ...]
            if len(sys.argv) < 4:
                print("Usage: calculate-lambda-costs.py compare-memory <invocations> <memory1>:<duration1> [<memory2>:<duration2> ...]", file=sys.stderr)
                sys.exit(1)
            
            num_invocations = int(sys.argv[2])
            duration_by_memory = {}
            
            for arg in sys.argv[3:]:
                memory_str, duration_str = arg.split(':')
                duration_by_memory[int(memory_str)] = float(duration_str)
            
            results = compare_lambda_memory_configs(num_invocations, duration_by_memory)
            print(json.dumps(results, indent=2))
        
        else:
            # Calculate cost for single configuration
            # Usage: python calculate-lambda-costs.py <invocations> <avg_duration_ms> <memory_mb> [data_transfer_gb]
            if len(sys.argv) < 5:
                print("Usage: calculate-lambda-costs.py <invocations> <avg_duration_ms> <memory_mb> [data_transfer_gb]", file=sys.stderr)
                sys.exit(1)
            
            num_invocations = int(sys.argv[1])
            avg_duration_ms = float(sys.argv[2])
            memory_mb = float(sys.argv[3])
            data_transfer_gb = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
            
            costs = calculate_lambda_total_cost(
                num_invocations=num_invocations,
                avg_billed_duration_ms=avg_duration_ms,
                memory_size_mb=memory_mb,
                data_transfer_gb=data_transfer_gb
            )
            
            print(json.dumps(costs, indent=2))
    else:
        # Default example
        costs = calculate_lambda_total_cost(
            num_invocations=100000,
            avg_billed_duration_ms=200.0,
            memory_size_mb=512.0,
            data_transfer_gb=1.0
        )
        print(json.dumps(costs, indent=2))
