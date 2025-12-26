# AWS Glue Schema Registry Module
# Creates a Glue Schema Registry for schema management

# Glue Schema Registry
resource "aws_glue_registry" "this" {
  registry_name = var.registry_name

  description = var.description

  tags = merge(
    var.tags,
    {
      Name = var.registry_name
    }
  )
}

# Glue Schema for raw event headers
resource "aws_glue_schema" "raw_event_headers" {
  schema_name       = "raw-event-headers-value"
  registry_arn      = aws_glue_registry.this.arn
  data_format       = "JSON"
  compatibility     = "BACKWARD"
  schema_definition = var.raw_event_schema_definition

  tags = var.tags
}

# Glue Schema for filtered loan events
resource "aws_glue_schema" "filtered_loan_events" {
  schema_name       = "filtered-loan-created-events-msk-value"
  registry_arn      = aws_glue_registry.this.arn
  data_format       = "JSON"
  compatibility     = "BACKWARD"
  schema_definition = var.filtered_event_schema_definition

  tags = var.tags
}

# Glue Schema for filtered loan payment events
resource "aws_glue_schema" "filtered_loan_payment_events" {
  schema_name       = "filtered-loan-payment-submitted-events-msk-value"
  registry_arn      = aws_glue_registry.this.arn
  data_format       = "JSON"
  compatibility     = "BACKWARD"
  schema_definition = var.filtered_event_schema_definition

  tags = var.tags
}

# Glue Schema for filtered car events
resource "aws_glue_schema" "filtered_car_events" {
  schema_name       = "filtered-car-created-events-msk-value"
  registry_arn      = aws_glue_registry.this.arn
  data_format       = "JSON"
  compatibility     = "BACKWARD"
  schema_definition = var.filtered_event_schema_definition

  tags = var.tags
}

# Glue Schema for filtered service events
resource "aws_glue_schema" "filtered_service_events" {
  schema_name       = "filtered-service-events-msk-value"
  registry_arn      = aws_glue_registry.this.arn
  data_format       = "JSON"
  compatibility     = "BACKWARD"
  schema_definition = var.filtered_event_schema_definition

  tags = var.tags
}

