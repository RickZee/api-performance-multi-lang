# Load Test Documentation

## AWS EKS Cost Analytics - Column Definitions

This document explains the columns in the AWS EKS Cost Analytics section of the performance test reports.

| Column | Meaning | Calculation |
|--------|---------|-------------|
| **Pods** | Number of pod replicas configured for this API | Configured in `pod_config.json` (currently all APIs use 1 pod for fair comparison) |
| **Pod Size** | CPU cores and memory allocated per pod | From `pod_config.json`: CPU cores per pod and memory (GB) per pod |
| **Instance Type** | EC2 instance type automatically selected based on pod requirements | Smallest cost-effective instance type that can fit all pods (considers 20% overhead for system/kubelet). Selected from t3.small, t3.medium, t3.large, t3.xlarge, t3.2xlarge. |
| **Instances** | Number of EC2 instances needed to run all pods | Calculated as: `ceil(num_pods / pods_per_instance)` where pods_per_instance is limited by CPU and memory capacity of the instance type |
| **Total Cost ($)** | Total cost for running this API during the test duration | Sum of: Instance Cost + Cluster Cost + ALB Cost + Storage Cost + Network Cost |
| **Cost/1K Requests ($)** | Cost per 1,000 requests processed | Calculated as: `(Total Cost / total_requests) × 1000`. Useful for comparing cost efficiency across APIs. |
| **Instance Cost ($)** | EC2 instance compute cost (adjusted for resource utilization) | Formula: `instance_hourly_cost × instances_needed × duration_hours × max(cpu_efficiency, memory_efficiency)`. If efficiency is 0% (no metrics), uses base cost. Efficiency = actual_utilization / allocated_resources. |
| **Cluster Cost ($)** | EKS cluster management cost | Calculated as: `$0.10/hour × duration_hours`. Fixed cost for EKS cluster management regardless of workload size. |
| **ALB Cost ($)** | Application Load Balancer cost | Calculated as: `($0.0225/hour × duration_hours) + ($0.008/GB × data_processed_gb)`. Includes base hourly cost and LCU (Load Balancer Capacity Unit) charges for data processed. |
| **Storage Cost ($)** | EBS storage cost for pod volumes | Calculated as: `$0.08/GB/month × (storage_gb_per_pod × num_pods) × (duration_hours / 720)`. Based on gp3 EBS storage pricing (converted to hourly rate). |
| **Network Cost ($)** | Data transfer out cost | Calculated as: `$0.09/GB × data_transfer_gb`. Estimated from request count (1KB per request). Only outbound data transfer is charged. |
| **CPU Efficiency** | Percentage of allocated CPU actually utilized | Calculated as: `(avg_cpu_percent / 100) × 100%`. Shows how efficiently CPU resources are used. 0% means no resource metrics were collected (common for short smoke tests). |
| **Memory Efficiency** | Percentage of allocated memory actually utilized | Calculated as: `(avg_memory_mb / memory_limit_mb) × 100%`. Shows how efficiently memory resources are used. 0% means no resource metrics were collected (common for short smoke tests). |

### Notes

**Note on Efficiency:** CPU and Memory efficiency are calculated based on actual resource utilization during the test. If efficiency shows 0%, it means resource metrics were not collected or the API had minimal resource usage during the test. This is common for very short smoke tests. For accurate efficiency metrics, run longer tests (full or saturation mode) with resource monitoring enabled.

**Note on Pricing:** All costs are estimated based on AWS us-east-1 on-demand pricing as of 2024. Actual costs may vary based on instance types, regions, reserved instances, spot instances, and other factors. These estimates assume a single EKS cluster shared across all APIs.

