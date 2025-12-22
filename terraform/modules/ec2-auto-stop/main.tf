# EC2 Auto-Stop Lambda Module
# Monitors SSM logins and EC2 activity, stops EC2 if no activity for specified time period
# Default: 30 minutes (0.5 hours) for bastion host cost optimization

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

# IAM policy for SSM and CloudTrail
resource "aws_iam_role_policy" "ec2_auto_stop_ssm_cloudtrail" {
  name = "${var.function_name}-ssm-cloudtrail-policy"
  role = aws_iam_role.ec2_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeSessions",
          "ssm:DescribeInstanceInformation",
          "cloudtrail:LookupEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for SNS notifications
resource "aws_iam_role_policy" "ec2_auto_stop_sns" {
  count = var.admin_email != "" ? 1 : 0
  name  = "${var.function_name}-sns-policy"
  role  = aws_iam_role.ec2_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.ec2_auto_stop_notifications[0].arn
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

# SNS Topic for EC2 auto-stop notifications
resource "aws_sns_topic" "ec2_auto_stop_notifications" {
  count = var.admin_email != "" ? 1 : 0
  name  = "${var.function_name}-notifications"

  tags = merge(
    var.tags,
    {
      Name = "${var.function_name}-notifications"
    }
  )
}

# SNS Email Subscription (requires confirmation)
resource "aws_sns_topic_subscription" "ec2_auto_stop_email" {
  count     = var.admin_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.ec2_auto_stop_notifications[0].arn
  protocol  = "email"
  endpoint  = var.admin_email
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
    Check EC2 instance activity (SSM sessions, DSQL API calls, CloudWatch metrics) 
    and stop EC2 if no activity for specified time period (supports fractional hours, e.g., 0.5 for 30 minutes)
    """
    instance_id = os.environ['EC2_INSTANCE_ID']
    region = os.environ['AWS_REGION']
    inactivity_hours = float(os.environ.get('INACTIVITY_HOURS', '3'))  # Support fractional hours (e.g., 0.5 for 30 minutes)
    bastion_role_arn = os.environ.get('BASTION_ROLE_ARN', '')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '')
    
    ec2 = boto3.client('ec2', region_name=region)
    cloudwatch = boto3.client('cloudwatch', region_name=region)
    logs = boto3.client('logs', region_name=region)
    ssm = boto3.client('ssm', region_name=region)
    cloudtrail = boto3.client('cloudtrail', region_name=region)
    sns = boto3.client('sns', region_name=region) if sns_topic_arn else None
    
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
    
    # Check for activity in the last N hours
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=inactivity_hours)
    
    ssm_activity = False
    dsql_activity = False
    
    # Method 1: Check for active SSM sessions
    try:
        response = ssm.describe_sessions(
            State='Active',
            MaxResults=50
        )
        for session in response.get('Sessions', []):
            if session.get('Target') == instance_id:
                ssm_activity = True
                print(f"Found active SSM session {session.get('SessionId')} for instance {instance_id}")
                break
    except Exception as e:
        print(f"Warning: Could not check active SSM sessions: {str(e)}")
    
    # Method 2: Check SSM Session Manager logs (historical)
    if not ssm_activity:
        try:
            log_group_name = "/aws/ssm/sessions"
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
            print(f"Warning: Could not check SSM logs: {str(e)}")
    
    # Method 3: Check CloudTrail for DSQL API calls from bastion role
    if bastion_role_arn:
        try:
            # Look for DSQL API calls (DbConnect, DbConnectAdmin) in the last N hours
            dsql_event_names = ['DbConnect', 'DbConnectAdmin']
            for event_name in dsql_event_names:
                try:
                    response = cloudtrail.lookup_events(
                        LookupAttributes=[
                            {
                                'AttributeKey': 'EventName',
                                'AttributeValue': event_name
                            }
                        ],
                        StartTime=start_time,
                        EndTime=end_time,
                        MaxResults=50
                    )
                    
                    # Check if any events are from the bastion role
                    for event in response.get('Events', []):
                        try:
                            event_data = json.loads(event.get('CloudTrailEvent', '{}'))
                            user_identity = event_data.get('userIdentity', {})
                            user_arn = user_identity.get('arn', '')
                            
                            # Check if event is from bastion role
                            if bastion_role_arn in user_arn or bastion_role_arn.split('/')[-1] in user_arn:
                                dsql_activity = True
                                print(f"Found DSQL API call ({event_name}) from bastion role at {event.get('EventTime')}")
                                break
                        except Exception as parse_error:
                            # Skip events that can't be parsed
                            continue
                    
                    if dsql_activity:
                        break
                except Exception as lookup_error:
                    # Continue to next event name if lookup fails
                    print(f"Warning: Could not lookup {event_name} events: {str(lookup_error)}")
                    continue
        except Exception as e:
            print(f"Warning: Could not check CloudTrail for DSQL activity: {str(e)}")
    
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
        # Increased CPU threshold to 5% to avoid false positives from baseline system activity
        # Network threshold increased to 20MB (over 3 hours) to avoid false positives from
        # baseline system activity (CloudWatch agent, SSM agent, health checks, etc.)
        # Typical baseline: ~2-3MB/hour = ~6-9MB over 3 hours
        cpu_values = [point['Average'] for point in cpu_response.get('Datapoints', [])]
        network_in_values = [point['Sum'] for point in network_in_response.get('Datapoints', [])]
        network_out_values = [point['Sum'] for point in network_out_response.get('Datapoints', [])]
        
        max_cpu = max(cpu_values) if cpu_values else 0
        total_network_in = sum(network_in_values) if network_in_values else 0
        total_network_out = sum(network_out_values) if network_out_values else 0
        
        # 20MB = 20971520 bytes (over 3 hours)
        # This allows for baseline system activity (~6-9MB) while catching real usage
        # CPU threshold: 5% to distinguish real usage from baseline activity
        network_threshold_bytes = 20971520  # 20MB
        if max_cpu > 5.0 or total_network_in > network_threshold_bytes or total_network_out > network_threshold_bytes:
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
    if ssm_activity or dsql_activity or metrics_activity:
        print(f"Activity detected (SSM: {ssm_activity}, DSQL: {dsql_activity}, Metrics: {metrics_activity}), keeping instance running")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Activity detected, instance kept running',
                'ssm_activity': ssm_activity,
                'dsql_activity': dsql_activity,
                'metrics_activity': metrics_activity
            })
        }
    
    # No activity detected, stop the instance
    try:
        print(f"No activity detected for {inactivity_hours} hours, stopping instance {instance_id}")
        ec2.stop_instances(InstanceIds=[instance_id])
        
        # Send email notification if SNS topic is configured
        if sns and sns_topic_arn:
            try:
                timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
                # Format inactivity period for display
                if inactivity_hours < 1:
                    inactivity_display = f"{int(inactivity_hours * 60)} minutes"
                elif inactivity_hours == 1:
                    inactivity_display = "1 hour"
                else:
                    inactivity_display = f"{inactivity_hours} hours"
                
                subject = f"Bastion Host Stopped - {instance_id}"
                message = f"""The bastion host EC2 instance '{instance_id}' has been automatically stopped due to inactivity.

Details:
- Instance ID: {instance_id}
- Stopped at: {timestamp}
- Reason: No activity detected for {inactivity_display}
- Activity check results:
  * SSM sessions: {ssm_activity}
  * DSQL API calls: {dsql_activity}
  * CloudWatch metrics: {metrics_activity}
- Region: {region}

The instance can be started manually via AWS Console or CLI when needed."""
                
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Subject=subject,
                    Message=message
                )
                print(f"Notification sent to SNS topic: {sns_topic_arn}")
            except Exception as e:
                # Log error but don't fail the Lambda execution
                print(f"Warning: Failed to send notification: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Instance stopped due to {inactivity_hours} hours of inactivity',
                'instance_id': instance_id,
                'ssm_activity': ssm_activity,
                'dsql_activity': dsql_activity,
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
    variables = merge(
      {
        EC2_INSTANCE_ID = var.ec2_instance_id
        # AWS_REGION is automatically provided by Lambda runtime
        INACTIVITY_HOURS = var.inactivity_hours
        BASTION_ROLE_ARN = var.bastion_role_arn
      },
      var.admin_email != "" ? {
        SNS_TOPIC_ARN = aws_sns_topic.ec2_auto_stop_notifications[0].arn
      } : {}
    )
  }

  depends_on = [
    aws_iam_role_policy.ec2_auto_stop_logs,
    aws_iam_role_policy.ec2_auto_stop_ssm_cloudtrail,
    aws_cloudwatch_log_group.ec2_auto_stop
  ]

  tags = var.tags
}

# EventBridge rule to trigger Lambda every hour
resource "aws_cloudwatch_event_rule" "ec2_auto_stop_schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger EC2 auto-stop check every 15 minutes"
  schedule_expression = "rate(15 minutes)"  # Check every 15 minutes for 30-minute inactivity threshold

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
