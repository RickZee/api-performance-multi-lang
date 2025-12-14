variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "dsql_host" {
  description = "DSQL cluster host"
  type        = string
}

variable "dsql_cluster_resource_id" {
  description = "DSQL cluster resource ID"
  type        = string
}

variable "iam_user" {
  description = "IAM database user name"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN to grant access"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}

