# EC2 Auto-Stop Lambda Module
# Monitors SSM logins and EC2 activity, stops EC2 if no activity for 3 hours

# IAM role for Lambda execution
resource "aws_iam_role" "ec2_auto_stop" {
  name = "${var.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for CloudWatch Logs
resource "aws_iam_role_policy" "ec2_auto_stop_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.ec2_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM policy for EC2 operations
resource "aws_iam_role_policy" "ec2_auto_stop_ec2" {
  name = "${var.function_name}-ec2-policy"
  role = aws_iam_role.ec2_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for CloudWatch metrics
resource "aws_iam_role_policy" "ec2_auto_stop_cloudwatch" {
  name = "${var.function_name}-cloudwatch-policy"
  role = aws_iam_role.ec2_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ec2_auto_stop" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Lambda function code (inline)
data "archive_file" "ec2_auto_stop_zip" {
  type        = "zip"
  output_path = "${path.module}/ec2_auto_stop.zip"
  source {
    content  = <<-EOF
import boto3
import os
from datetime import datetime, timedelta
import json

def handler(event, context):
    """
    Check EC2 instance activity (SSM logins and CloudWatch metrics) 
    and stop EC2 if no activity for specified hours
    """
    instance_id = os.environ['EC2_INSTANCE_ID']
    region = os.environ['AWS_REGION']
    inactivity_hours = int(os.environ.get('INACTIVITY_HOURS', '3'))
    
    ec2 = boto3.client('ec2', region_name=region)
    cloudwatch = boto3.client('cloudwatch', region_name=region)
    logs = boto3.client('logs', region_name=region)
    
    # Check current instance status
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        if not response['Reservations']:
            print(f"Instance {instance_id} not found")
            return {
                'statusCode': 404,
                'body': json.dumps({'error': f'Instance {instance_id} not found'})
            }
        
        instance = response['Reservations'][0]['Instances'][0]
        instance_state = instance['State']['Name']
        
        if instance_state in ['stopped', 'stopping', 'terminated', 'terminating']:
            print(f"Instance {instance_id} is already {instance_state}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Instance already {instance_state}',
                    'status': instance_state
                })
            }
    except Exception as e:
        print(f"Error checking instance status: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Failed to check instance status: {str(e)}'})
        }
    
    # Check for SSM Session Manager logins in the last N hours
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=inactivity_hours)
    
    ssm_activity = False
    try:
        # Check SSM Session Manager logs
        # SSM sessions are logged to /aws/ssm/sessions
        log_group_name = "/aws/ssm/sessions"
        
        # Filter logs for this instance
        response = logs.filter_log_events(
            logGroupName=log_group_name,
            startTime=int(start_time.timestamp() * 1000),
            endTime=int(end_time.timestamp() * 1000),
            filterPattern=f'"{instance_id}"'
        )
        
        if response.get('events'):
            ssm_activity = True
            print(f"Found {len(response['events'])} SSM session events for instance {instance_id}")
    except Exception as e:
        # If log group doesn't exist or no permissions, continue to check metrics
        print(f"Warning: Could not check SSM logs: {str(e)}")
    
    # Check EC2 CloudWatch metrics for activity
    metrics_activity = False
    try:
        # Check CPU utilization
        cpu_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[
                {'Name': 'InstanceId', 'Value': instance_id}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,  # 1 hour periods
            Statistics=['Average']
        )
        
        # Check NetworkIn
        network_in_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkIn',
            Dimensions=[
                {'Name': 'InstanceId', 'Value': instance_id}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Sum']
        )
        
        # Check NetworkOut
        network_out_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkOut',
            Dimensions=[
                {'Name': 'InstanceId', 'Value': instance_id}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Sum']
        )
        
        # Check if there was any significant activity
        # CPU > 1% or network activity > 1MB
        cpu_values = [point['Average'] for point in cpu_response.get('Datapoints', [])]
        network_in_values = [point['Sum'] for point in network_in_response.get('Datapoints', [])]
        network_out_values = [point['Sum'] for point in network_out_response.get('Datapoints', [])]
        
        max_cpu = max(cpu_values) if cpu_values else 0
        total_network_in = sum(network_in_values) if network_in_values else 0
        total_network_out = sum(network_out_values) if network_out_values else 0
        
        # 1MB = 1048576 bytes
        if max_cpu > 1.0 or total_network_in > 1048576 or total_network_out > 1048576:
            metrics_activity = True
            print(f"Instance {instance_id} activity detected: CPU={max_cpu:.2f}%, NetworkIn={total_network_in:.0f} bytes, NetworkOut={total_network_out:.0f} bytes")
    except Exception as e:
        print(f"Warning: Could not check CloudWatch metrics: {str(e)}")
        # If we can't check metrics, don't stop the instance (fail-safe)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Could not check metrics, keeping instance running',
                'error': str(e)
            })
        }
    
    # Check if there was any activity
    if ssm_activity or metrics_activity:
        print(f"Activity detected (SSM: {ssm_activity}, Metrics: {metrics_activity}), keeping instance running")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Activity detected, instance kept running',
                'ssm_activity': ssm_activity,
                'metrics_activity': metrics_activity
            })
        }
    
    # No activity detected, stop the instance
    try:
        print(f"No activity detected for {inactivity_hours} hours, stopping instance {instance_id}")
        ec2.stop_instances(InstanceIds=[instance_id])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Instance stopped due to {inactivity_hours} hours of inactivity',
                'instance_id': instance_id,
                'ssm_activity': ssm_activity,
                'metrics_activity': metrics_activity
            })
        }
    except Exception as e:
        error_msg = str(e)
        if 'InvalidInstanceID' in error_msg or 'InvalidInstanceState' in error_msg:
            print(f"Instance is already stopped or stopping: {error_msg}")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Instance already stopped or stopping'})
            }
        print(f"Error stopping instance: {error_msg}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Failed to stop instance: {error_msg}'})
        }
EOF
    filename = "index.py"
  }
}

# Lambda function (inline Python code)
resource "aws_lambda_function" "ec2_auto_stop" {
  function_name = var.function_name
  role          = aws_iam_role.ec2_auto_stop.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.ec2_auto_stop_zip.output_path
  source_code_hash = data.archive_file.ec2_auto_stop_zip.output_base64sha256

  environment {
    variables = {
      EC2_INSTANCE_ID = var.ec2_instance_id
      # AWS_REGION is automatically provided by Lambda runtime
      INACTIVITY_HOURS = var.inactivity_hours
    }
  }

  depends_on = [
    aws_iam_role_policy.ec2_auto_stop_logs,
    aws_cloudwatch_log_group.ec2_auto_stop
  ]

  tags = var.tags
}

# EventBridge rule to trigger Lambda every hour
resource "aws_cloudwatch_event_rule" "ec2_auto_stop_schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger EC2 auto-stop check every hour"
  schedule_expression = "rate(1 hour)"

  tags = var.tags
}

# EventBridge target
resource "aws_cloudwatch_event_target" "ec2_auto_stop_target" {
  rule      = aws_cloudwatch_event_rule.ec2_auto_stop_schedule.name
  target_id = "${var.function_name}-target"
  arn       = aws_lambda_function.ec2_auto_stop.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "ec2_auto_stop_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_auto_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_auto_stop_schedule.arn
}
