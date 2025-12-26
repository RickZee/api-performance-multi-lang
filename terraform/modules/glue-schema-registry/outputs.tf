output "registry_arn" {
  description = "ARN of the Glue Schema Registry"
  value       = aws_glue_registry.this.arn
}

output "registry_name" {
  description = "Name of the Glue Schema Registry"
  value       = aws_glue_registry.this.registry_name
}

output "raw_event_schema_arn" {
  description = "ARN of the raw event headers schema"
  value       = aws_glue_schema.raw_event_headers.arn
}

output "filtered_loan_events_schema_arn" {
  description = "ARN of the filtered loan events schema"
  value       = aws_glue_schema.filtered_loan_events.arn
}

output "filtered_loan_payment_events_schema_arn" {
  description = "ARN of the filtered loan payment events schema"
  value       = aws_glue_schema.filtered_loan_payment_events.arn
}

output "filtered_car_events_schema_arn" {
  description = "ARN of the filtered car events schema"
  value       = aws_glue_schema.filtered_car_events.arn
}

output "filtered_service_events_schema_arn" {
  description = "ARN of the filtered service events schema"
  value       = aws_glue_schema.filtered_service_events.arn
}

