variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the Aurora cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the Aurora subnet group"
  type        = list(string)
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "car_entities"
}

variable "database_user" {
  description = "Database master username"
  type        = string
  default     = "postgres"
}

variable "database_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.14"
}

variable "instance_class" {
  description = "Aurora instance class (cost-optimized default: db.t3.small)"
  type        = string
  default     = "db.t3.small"
}

variable "instance_count" {
  description = "Number of Aurora instances in the cluster"
  type        = number
  default     = 1
}

variable "publicly_accessible" {
  description = <<-EOT
    Make Aurora publicly accessible for Confluent Cloud.
    
    When true:
    - Aurora instances will have public IP addresses
    - Required for Confluent Cloud to connect via public internet
    - Security group should be configured with confluent_cloud_cidrs for better security
    
    When false:
    - Aurora is only accessible from within the VPC
    - Use AWS PrivateLink for Confluent Cloud connectivity instead
    
    Security considerations:
    - Always use SSL/TLS (sslmode=require) in connector configuration
    - Restrict security group to Confluent Cloud IP ranges when possible
    - For production, prefer PrivateLink over public access
  EOT
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = <<-EOT
    CIDR blocks allowed to access Aurora.
    
    Default: ["0.0.0.0/0"] (allows access from any IP)
    
    When publicly_accessible = true and confluent_cloud_cidrs is provided:
    - This variable is ignored; security group uses confluent_cloud_cidrs instead
    
    When publicly_accessible = true and confluent_cloud_cidrs is empty:
    - This variable is used for security group rules
    - Default allows all IPs (0.0.0.0/0) - not recommended for production
    
    When publicly_accessible = false:
    - This variable is used for VPC-internal access
    
    Security recommendation:
    - For public access, provide confluent_cloud_cidrs to restrict to Confluent Cloud IPs
    - For production, prefer PrivateLink over public access
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All allowed_cidr_blocks must be valid CIDR blocks (e.g., 10.0.0.0/16)."
  }
}

variable "confluent_cloud_cidrs" {
  description = <<-EOT
    CIDR blocks for Confluent Cloud egress IP ranges (optional, for security group).
    
    When publicly_accessible = true and this variable is provided:
    - Security group will restrict access to only these Confluent Cloud IP ranges (recommended)
    - Provides better security than allowing all IPs (0.0.0.0/0)
    
    When publicly_accessible = true and this variable is empty:
    - Security group will use allowed_cidr_blocks (defaults to 0.0.0.0/0)
    - Aurora will be accessible from all IPs - not recommended for production
    
    To find current Confluent Cloud egress IP ranges:
    1. Check documentation: https://docs.confluent.io/cloud/current/networking/ip-ranges.html
    2. Use Confluent CLI: confluent network egress-ip list
    3. Use helper script: terraform/scripts/get-confluent-cloud-ips.sh
    4. Contact Confluent support for region-specific IP ranges
    
    Example:
      confluent_cloud_cidrs = ["13.57.0.0/16", "52.0.0.0/16"]
    
    Note: IP ranges may change over time. Update this configuration periodically.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.confluent_cloud_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All confluent_cloud_cidrs must be valid CIDR blocks (e.g., 13.57.0.0/16)."
  }
}

variable "parameter_group_family" {
  description = "Parameter group family (e.g., aurora-postgresql15)"
  type        = string
  default     = "aurora-postgresql15"
}

variable "backup_retention_period" {
  description = "Backup retention period in days (cost-optimized default: 3 for dev/test, use 7+ for production)"
  type        = number
  default     = 3
}

variable "preferred_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "mon:04:00-mon:05:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_ipv6" {
  description = "Enable IPv6 support in security groups"
  type        = bool
  default     = true
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to allow access to Aurora (e.g., EKS node group)"
  type        = list(string)
  default     = []
}
