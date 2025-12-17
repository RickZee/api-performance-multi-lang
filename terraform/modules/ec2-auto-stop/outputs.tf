output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.ec2_auto_stop.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.ec2_auto_stop.arn
}

output "schedule_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.ec2_auto_stop_schedule.arn
}
