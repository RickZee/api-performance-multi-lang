"""
Collect CloudWatch metrics for EC2 instance.
"""

import boto3
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from botocore.exceptions import ClientError


class CloudWatchMetricsCollector:
    """Collect CloudWatch metrics for EC2 instance."""
    
    def __init__(self, instance_id: str, region: str):
        self.instance_id = instance_id
        self.region = region
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.ec2 = boto3.client('ec2', region_name=region)
    
    def get_instance_metadata(self) -> Dict:
        """Get EC2 instance metadata including instance type, etc."""
        try:
            response = self.ec2.describe_instances(InstanceIds=[self.instance_id])
            if not response['Reservations']:
                return {}
            
            instance = response['Reservations'][0]['Instances'][0]
            return {
                'instance_id': self.instance_id,
                'instance_type': instance.get('InstanceType', 'unknown'),
                'instance_state': instance['State']['Name'],
                'availability_zone': instance.get('Placement', {}).get('AvailabilityZone', 'unknown'),
                'vpc_id': instance.get('VpcId', 'unknown'),
                'subnet_id': instance.get('SubnetId', 'unknown'),
                'launch_time': instance.get('LaunchTime', '').isoformat() if instance.get('LaunchTime') else None,
                'architecture': instance.get('Architecture', 'unknown'),
                'platform': instance.get('Platform', 'linux/unix'),
                'cpu_options': instance.get('CpuOptions', {}),
            }
        except Exception as e:
            return {'error': str(e)}
    
    def get_metrics(
        self, 
        start_time: datetime, 
        end_time: datetime,
        metric_names: Optional[List[str]] = None
    ) -> Dict:
        """
        Get CloudWatch metrics for the instance during the specified time period.
        
        Args:
            start_time: Start of time period
            end_time: End of time period
            metric_names: List of metric names to collect (default: CPU, Network, Disk)
        
        Returns:
            Dict with metric data
        """
        if metric_names is None:
            metric_names = [
                'CPUUtilization',
                'NetworkIn',
                'NetworkOut',
                'NetworkPacketsIn',
                'NetworkPacketsOut',
                'DiskReadOps',
                'DiskWriteOps',
                'DiskReadBytes',
                'DiskWriteBytes',
            ]
        
        metrics_data = {}
        
        for metric_name in metric_names:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='AWS/EC2',
                    MetricName=metric_name,
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': self.instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=60,  # 1 minute periods
                    Statistics=['Average', 'Maximum', 'Minimum']
                )
                
                datapoints = response.get('Datapoints', [])
                if datapoints:
                    # Sort by timestamp
                    datapoints.sort(key=lambda x: x['Timestamp'])
                    
                    # Calculate statistics
                    values = [dp['Average'] for dp in datapoints]
                    max_values = [dp['Maximum'] for dp in datapoints]
                    min_values = [dp['Minimum'] for dp in datapoints]
                    
                    metrics_data[metric_name] = {
                        'average': sum(values) / len(values) if values else None,
                        'maximum': max(max_values) if max_values else None,
                        'minimum': min(min_values) if min_values else None,
                        'sample_count': len(datapoints),
                        'datapoints': [
                            {
                                'timestamp': dp['Timestamp'].isoformat(),
                                'average': dp['Average'],
                                'maximum': dp['Maximum'],
                                'minimum': dp['Minimum']
                            }
                            for dp in datapoints
                        ]
                    }
            except ClientError as e:
                metrics_data[metric_name] = {'error': str(e)}
            except Exception as e:
                metrics_data[metric_name] = {'error': str(e)}
        
        return metrics_data
    
    def collect_test_metrics(self, test_start_time: datetime, test_end_time: datetime) -> Dict:
        """
        Collect all metrics for a test run.
        
        Returns:
            Dict with instance_metadata and cloudwatch_metrics
        """
        return {
            'instance_metadata': self.get_instance_metadata(),
            'cloudwatch_metrics': self.get_metrics(test_start_time, test_end_time)
        }

