variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "ec2_instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}

variable "inactivity_hours" {
  description = "Number of hours of inactivity before stopping the instance (supports fractional hours, e.g., 0.5 for 30 minutes)"
  type        = number
  default     = 0.5  # 30 minutes default for bastion host cost optimization
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 1
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "bastion_role_arn" {
  description = "ARN of the bastion host IAM role (for detecting DSQL API calls)"
  type        = string
  default     = ""
}

variable "admin_email" {
  description = "Admin email address for EC2 auto-stop notifications (optional, leave empty to disable notifications)"
  type        = string
  default     = ""
}
