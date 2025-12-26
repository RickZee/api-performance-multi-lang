variable "registry_name" {
  description = "Name of the Glue Schema Registry"
  type        = string
  default     = "cdc-streaming-schema-registry"
}

variable "description" {
  description = "Description of the Glue Schema Registry"
  type        = string
  default     = "Schema registry for CDC streaming events"
}

variable "raw_event_schema_definition" {
  description = "JSON schema definition for raw event headers"
  type        = string
  default     = <<-EOT
{
  "type": "record",
  "name": "RawEventHeaders",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "event_name", "type": "string"},
    {"name": "event_type", "type": "string"},
    {"name": "created_date", "type": "string"},
    {"name": "saved_date", "type": "string"},
    {"name": "header_data", "type": "string"},
    {"name": "__op", "type": "string"},
    {"name": "__table", "type": "string"},
    {"name": "__ts_ms", "type": "long"}
  ]
}
EOT
}

variable "filtered_event_schema_definition" {
  description = "JSON schema definition for filtered events"
  type        = string
  default     = <<-EOT
{
  "type": "record",
  "name": "FilteredEvent",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "event_name", "type": "string"},
    {"name": "event_type", "type": "string"},
    {"name": "created_date", "type": "string"},
    {"name": "saved_date", "type": "string"},
    {"name": "header_data", "type": "string"},
    {"name": "__op", "type": "string"},
    {"name": "__table", "type": "string"}
  ]
}
EOT
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

