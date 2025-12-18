variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "ec2_instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}

variable "inactivity_hours" {
  description = "Number of hours of inactivity before stopping the instance"
  type        = number
  default     = 3
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 3
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
