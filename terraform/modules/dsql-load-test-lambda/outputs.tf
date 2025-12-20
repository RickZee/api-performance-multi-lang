output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.dsql_load_test.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.dsql_load_test.arn
}

output "function_invoke_arn" {
  description = "Lambda function invoke ARN"
  value       = aws_lambda_function.dsql_load_test.invoke_arn
}

output "role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}

output "role_name" {
  description = "Lambda execution role name"
  value       = aws_iam_role.lambda_execution.name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda.name
}
