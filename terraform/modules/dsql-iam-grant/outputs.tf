output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.dsql_iam_grant.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.dsql_iam_grant.arn
}
