#!/usr/bin/env python3
"""
AWS EKS Cost Calculator
Calculates estimated AWS costs for running APIs on EKS based on resource usage
"""

from typing import Dict, Optional, List
from datetime import timedelta
import json


# AWS EKS Pricing (us-east-1, as of 2024)
# Source: https://aws.amazon.com/eks/pricing/
AWS_PRICING = {
    # EKS Cluster Management
    'eks_cluster_per_hour': 0.10,  # $0.10 per hour per cluster
    
    # EC2 Instance Pricing (On-Demand, us-east-1)
    # Assuming t3.medium instances (2 vCPU, 4GB RAM) for APIs with 2GB memory limit
    'ec2_t3_medium_per_hour': 0.0416,  # $0.0416 per hour
    'ec2_t3_small_per_hour': 0.0208,   # $0.0208 per hour (1 vCPU, 2GB RAM)
    'ec2_t3_large_per_hour': 0.0832,   # $0.0832 per hour (2 vCPU, 8GB RAM)
    
    # Application Load Balancer
    'alb_per_hour': 0.0225,  # $0.0225 per hour
    'alb_lcu_per_gb': 0.008,  # $0.008 per GB processed (simplified)
    
    # EBS Storage (gp3)
    'ebs_gp3_per_gb_month': 0.08,  # $0.08 per GB per month
    'ebs_gp3_per_gb_hour': 0.08 / (30 * 24),  # Convert to per hour
    
    # Data Transfer
    'data_transfer_out_per_gb': 0.09,  # First 10TB per month
    'data_transfer_in_per_gb': 0.00,   # Free for inbound
    
    # Network costs (simplified)
    'network_per_gb': 0.01,  # Simplified network cost
}


def select_instance_type(cpu_cores_per_pod: float, memory_gb_per_pod: float, num_pods: int = 1) -> Dict[str, any]:
    """
    Select appropriate EC2 instance type based on pod requirements
    
    Args:
        cpu_cores_per_pod: CPU cores per pod
        memory_gb_per_pod: Memory in GB per pod
        num_pods: Number of pods
    
    Returns:
        Dictionary with instance type details
    """
    # Instance specifications (vCPU, Memory GB, Hourly Cost)
    # Note: t3 instances have burstable CPU credits, but we use vCPU count for capacity planning
    instance_types = {
        't3.small': {'vcpu': 2, 'memory_gb': 2, 'cost_per_hour': 0.0208},
        't3.medium': {'vcpu': 2, 'memory_gb': 4, 'cost_per_hour': 0.0416},
        't3.large': {'vcpu': 2, 'memory_gb': 8, 'cost_per_hour': 0.0832},
        't3.xlarge': {'vcpu': 4, 'memory_gb': 16, 'cost_per_hour': 0.1664},
        't3.2xlarge': {'vcpu': 8, 'memory_gb': 32, 'cost_per_hour': 0.3328},
    }
    
    # Calculate total resources needed (with 20% overhead for system/kubelet)
    total_cpu_needed = cpu_cores_per_pod * num_pods * 1.2
    total_memory_needed = memory_gb_per_pod * num_pods * 1.2
    
    # Find smallest instance type that can fit all pods
    # In production, you'd use multiple instances, but for cost estimation we find the minimum
    best_instance = None
    min_cost = float('inf')
    
    for instance_name, specs in instance_types.items():
        # Calculate how many pods can fit on this instance
        pods_per_instance_cpu = int(specs['vcpu'] / cpu_cores_per_pod)
        pods_per_instance_memory = int(specs['memory_gb'] / memory_gb_per_pod)
        pods_per_instance = min(pods_per_instance_cpu, pods_per_instance_memory)
        
        if pods_per_instance > 0:
            # Calculate number of instances needed
            instances_needed = max(1, int((num_pods + pods_per_instance - 1) / pods_per_instance))
            total_cost = instances_needed * specs['cost_per_hour']
            
            if total_cost < min_cost:
                min_cost = total_cost
                best_instance = {
                    'name': instance_name,
                    'vcpu': specs['vcpu'],
                    'memory_gb': specs['memory_gb'],
                    'cost_per_hour': specs['cost_per_hour'],
                    'pods_per_instance': pods_per_instance,
                    'instances_needed': instances_needed,
                    'total_hourly_cost': total_cost
                }
    
    # Default to t3.medium if no suitable instance found
    if not best_instance:
        best_instance = {
            'name': 't3.medium',
            'vcpu': 2,
            'memory_gb': 4,
            'cost_per_hour': AWS_PRICING['ec2_t3_medium_per_hour'],
            'pods_per_instance': 1,
            'instances_needed': num_pods,
            'total_hourly_cost': AWS_PRICING['ec2_t3_medium_per_hour'] * num_pods
        }
    
    return best_instance


def calculate_instance_cost(
    cpu_cores_per_pod: float = 1.0,
    memory_gb_per_pod: float = 2.0,
    num_pods: int = 1,
    duration_hours: float = 1.0,
    avg_cpu_utilization: float = 50.0,
    avg_memory_utilization: float = 50.0
) -> Dict[str, float]:
    """
    Calculate EC2 instance cost based on pod requirements and utilization
    
    Args:
        cpu_cores_per_pod: CPU cores per pod
        memory_gb_per_pod: Memory in GB per pod
        num_pods: Number of pods
        duration_hours: Test duration in hours
        avg_cpu_utilization: Average CPU utilization percentage
        avg_memory_utilization: Average memory utilization percentage
    
    Returns:
        Dictionary with cost breakdown
    """
    # Select appropriate instance type
    instance_info = select_instance_type(cpu_cores_per_pod, memory_gb_per_pod, num_pods)
    
    # Calculate base cost for all instances
    base_cost = instance_info['total_hourly_cost'] * duration_hours
    
    # CPU efficiency factor (lower utilization = less efficient use of resources)
    cpu_efficiency = avg_cpu_utilization / 100.0
    memory_efficiency = avg_memory_utilization / 100.0
    
    # Effective cost considers resource efficiency
    # Lower utilization means we're paying for unused capacity
    # If efficiency is 0 (no metrics), use base cost (we still pay for the instance)
    if cpu_efficiency == 0.0 and memory_efficiency == 0.0:
        # No resource metrics available - use base cost as minimum
        effective_cost = base_cost
    else:
        effective_cost = base_cost * max(cpu_efficiency, memory_efficiency)
    
    return {
        'instance_type': instance_info['name'],
        'instances_needed': instance_info['instances_needed'],
        'pods_per_instance': instance_info['pods_per_instance'],
        'instance_base_cost': base_cost,
        'instance_effective_cost': effective_cost,
        'cpu_efficiency': cpu_efficiency,
        'memory_efficiency': memory_efficiency,
        'wasted_capacity_cost': base_cost - effective_cost,
        'num_pods': num_pods,
        'cpu_cores_per_pod': cpu_cores_per_pod,
        'memory_gb_per_pod': memory_gb_per_pod
    }


def calculate_eks_cluster_cost(duration_hours: float, num_clusters: int = 1) -> float:
    """Calculate EKS cluster management cost"""
    return AWS_PRICING['eks_cluster_per_hour'] * duration_hours * num_clusters


def calculate_load_balancer_cost(
    duration_hours: float,
    data_processed_gb: float = 0.0
) -> Dict[str, float]:
    """Calculate Application Load Balancer cost"""
    base_cost = AWS_PRICING['alb_per_hour'] * duration_hours
    lcu_cost = AWS_PRICING['alb_lcu_per_gb'] * data_processed_gb
    
    return {
        'alb_base_cost': base_cost,
        'alb_lcu_cost': lcu_cost,
        'alb_total_cost': base_cost + lcu_cost
    }


def calculate_storage_cost(
    storage_gb_per_pod: float = 20.0,  # Default 20GB per pod
    num_pods: int = 1,
    duration_hours: float = 1.0
) -> float:
    """Calculate EBS storage cost for all pods"""
    total_storage_gb = storage_gb_per_pod * num_pods
    cost = AWS_PRICING['ebs_gp3_per_gb_hour'] * total_storage_gb * duration_hours
    # Ensure minimum cost to avoid zero (even for very short tests)
    return max(cost, 0.0000001)


def calculate_network_cost(
    data_transfer_gb: float = 0.0,
    direction: str = 'out'
) -> float:
    """Calculate data transfer cost"""
    if direction == 'out':
        cost = AWS_PRICING['data_transfer_out_per_gb'] * data_transfer_gb
    else:
        cost = AWS_PRICING['data_transfer_in_per_gb'] * data_transfer_gb
    # Ensure minimum cost to avoid zero (even for very small data transfers)
    return max(cost, 0.0000001)


def calculate_total_cost(
    duration_seconds: float,
    avg_cpu_percent: float = 0.0,
    avg_memory_mb: float = 0.0,
    memory_limit_mb: float = 2048.0,
    total_requests: int = 0,
    data_transfer_gb: float = 0.0,
    num_pods: int = 1,
    cpu_cores_per_pod: float = 1.0,
    memory_gb_per_pod: Optional[float] = None,
    storage_gb_per_pod: float = 20.0,
    include_cluster: bool = True,
    include_alb: bool = True,
    include_storage: bool = True
) -> Dict[str, float]:
    """
    Calculate total AWS EKS cost for a test run
    
    Args:
        duration_seconds: Test duration in seconds
        avg_cpu_percent: Average CPU utilization percentage
        avg_memory_mb: Average memory usage in MB
        memory_limit_mb: Memory limit in MB
        total_requests: Total number of requests processed
        data_transfer_gb: Data transfer in GB
        num_pods: Number of pods (replicas)
        cpu_cores_per_pod: CPU cores per pod (requests/limits)
        memory_gb_per_pod: Memory in GB per pod (if None, calculated from memory_limit_mb)
        storage_gb_per_pod: Storage in GB per pod
        include_cluster: Include EKS cluster cost
        include_alb: Include load balancer cost
        include_storage: Include storage cost
    
    Returns:
        Dictionary with detailed cost breakdown
    """
    duration_hours = duration_seconds / 3600.0
    
    # Determine memory per pod
    if memory_gb_per_pod is None:
        memory_gb_per_pod = memory_limit_mb / 1024.0
    
    avg_memory_percent = (avg_memory_mb / memory_limit_mb * 100.0) if memory_limit_mb > 0 else 0.0
    
    # Calculate component costs with pod configuration
    instance_costs = calculate_instance_cost(
        cpu_cores_per_pod=cpu_cores_per_pod,
        memory_gb_per_pod=memory_gb_per_pod,
        num_pods=num_pods,
        duration_hours=duration_hours,
        avg_cpu_utilization=avg_cpu_percent,
        avg_memory_utilization=avg_memory_percent
    )
    
    cluster_cost = calculate_eks_cluster_cost(duration_hours) if include_cluster else 0.0
    
    alb_costs = calculate_load_balancer_cost(
        duration_hours,
        data_transfer_gb
    ) if include_alb else {'alb_total_cost': 0.0}
    
    storage_cost = calculate_storage_cost(
        storage_gb_per_pod=storage_gb_per_pod,
        num_pods=num_pods,
        duration_hours=duration_hours
    ) if include_storage else 0.0
    
    network_cost = calculate_network_cost(data_transfer_gb, 'out')
    
    # Calculate per-request costs
    total_cost = (
        instance_costs['instance_effective_cost'] +
        cluster_cost +
        alb_costs['alb_total_cost'] +
        storage_cost +
        network_cost
    )
    
    cost_per_request = total_cost / total_requests if total_requests > 0 else 0.0
    cost_per_1000_requests = cost_per_request * 1000.0
    
    return {
        'duration_hours': duration_hours,
        'num_pods': num_pods,
        'cpu_cores_per_pod': cpu_cores_per_pod,
        'memory_gb_per_pod': memory_gb_per_pod,
        'instance_type': instance_costs['instance_type'],
        'instances_needed': instance_costs['instances_needed'],
        'pods_per_instance': instance_costs['pods_per_instance'],
        'instance_base_cost': instance_costs['instance_base_cost'],
        'instance_effective_cost': instance_costs['instance_effective_cost'],
        'cluster_cost': cluster_cost,
        'alb_cost': alb_costs['alb_total_cost'],
        'storage_cost': storage_cost,
        'network_cost': network_cost,
        'total_cost': total_cost,
        'cost_per_request': cost_per_request,
        'cost_per_1000_requests': cost_per_1000_requests,
        'total_requests': total_requests,
        'cpu_efficiency': instance_costs['cpu_efficiency'],
        'memory_efficiency': instance_costs['memory_efficiency'],
        'wasted_capacity_cost': instance_costs['wasted_capacity_cost']
    }


def calculate_cost_for_api(
    api_name: str,
    duration_seconds: float,
    total_requests: int,
    avg_cpu_percent: float = 0.0,
    avg_memory_mb: float = 0.0,
    memory_limit_mb: float = 2048.0,
    data_transfer_gb: float = 0.0,
    num_pods: int = 1,
    cpu_cores_per_pod: float = 1.0,
    memory_gb_per_pod: Optional[float] = None,
    storage_gb_per_pod: float = 20.0
) -> Dict[str, any]:
    """
    Calculate cost for a specific API test run
    
    Args:
        api_name: Name of the API
        duration_seconds: Test duration in seconds
        total_requests: Total number of requests
        avg_cpu_percent: Average CPU utilization percentage
        avg_memory_mb: Average memory usage in MB
        memory_limit_mb: Memory limit in MB
        data_transfer_gb: Data transfer in GB
        num_pods: Number of pods (replicas) - default 1
        cpu_cores_per_pod: CPU cores per pod - default 1.0
        memory_gb_per_pod: Memory in GB per pod (if None, calculated from memory_limit_mb)
        storage_gb_per_pod: Storage in GB per pod - default 20.0
    
    Returns:
        Dictionary with API name and cost breakdown
    """
    costs = calculate_total_cost(
        duration_seconds=duration_seconds,
        avg_cpu_percent=avg_cpu_percent,
        avg_memory_mb=avg_memory_mb,
        memory_limit_mb=memory_limit_mb,
        total_requests=total_requests,
        data_transfer_gb=data_transfer_gb,
        num_pods=num_pods,
        cpu_cores_per_pod=cpu_cores_per_pod,
        memory_gb_per_pod=memory_gb_per_pod,
        storage_gb_per_pod=storage_gb_per_pod
    )
    
    return {
        'api_name': api_name,
        **costs
    }


if __name__ == '__main__':
    # Example usage
    import sys
    if len(sys.argv) > 1:
        duration = float(sys.argv[1])
        requests = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
        cpu = float(sys.argv[3]) if len(sys.argv) > 3 else 50.0
        memory = float(sys.argv[4]) if len(sys.argv) > 4 else 1024.0
        
        costs = calculate_total_cost(
            duration_seconds=duration,
            total_requests=requests,
            avg_cpu_percent=cpu,
            avg_memory_mb=memory
        )
        
        print(json.dumps(costs, indent=2))
    else:
        # Default test
        costs = calculate_total_cost(
            duration_seconds=3600,  # 1 hour
            total_requests=100000,
            avg_cpu_percent=50.0,
            avg_memory_mb=1024.0
        )
        import json
        print(json.dumps(costs, indent=2))
