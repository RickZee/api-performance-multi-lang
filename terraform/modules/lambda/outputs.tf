output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.this.arn
}

output "function_invoke_arn" {
  description = "Lambda function invoke ARN"
  value       = aws_lambda_function.this.invoke_arn
}

output "api_id" {
  description = "API Gateway HTTP API ID"
  value       = aws_apigatewayv2_api.this.id
}

output "api_url" {
  description = "API Gateway HTTP API endpoint URL"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_execution_arn" {
  description = "API Gateway HTTP API execution ARN"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}

output "role_name" {
  description = "Lambda execution role name"
  value       = aws_iam_role.lambda_execution.name
}

