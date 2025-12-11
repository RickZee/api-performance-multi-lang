# Confluent Cloud IP Range Management
# 
# This file manages Confluent Cloud egress IP ranges for public internet access.
# 
# To find current Confluent Cloud IP ranges:
# 1. Check Confluent Cloud documentation: https://docs.confluent.io/cloud/current/networking/ip-ranges.html
# 2. Use Confluent CLI: confluent network egress-ip list
# 3. Contact Confluent support for region-specific IP ranges
# 4. Use helper script: terraform/scripts/get-confluent-cloud-ips.sh
#
# Note: IP ranges may change over time. Update this configuration periodically.

locals {
  # Validate Confluent Cloud CIDR blocks
  # This ensures all provided CIDRs are valid format (basic validation)
  confluent_cloud_cidrs_validated = [
    for cidr in var.confluent_cloud_cidrs : cidr
    if can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
  ]

  # Determine effective CIDR blocks for security group
  # If publicly accessible and Confluent CIDRs provided, use those (restricted access)
  # Otherwise, use allowed_cidr_blocks (defaults to 0.0.0.0/0 for full public access)
  effective_cidr_blocks = var.publicly_accessible && length(local.confluent_cloud_cidrs_validated) > 0 ? local.confluent_cloud_cidrs_validated : var.allowed_cidr_blocks

  # Determine if we should use restricted access (Confluent Cloud IPs only)
  use_restricted_access = var.publicly_accessible && length(local.confluent_cloud_cidrs_validated) > 0

  # Common Confluent Cloud IP ranges by region (examples - update with actual ranges)
  # These are example values. Replace with actual IPs from Confluent documentation.
  confluent_cloud_ips_by_region = {
    "us-east-1" = [
      # Example IPs - replace with actual Confluent Cloud egress IPs for us-east-1
      # "13.57.0.0/16",
      # "52.0.0.0/16"
    ]
    "us-west-2" = [
      # Example IPs - replace with actual Confluent Cloud egress IPs for us-west-2
      # "13.57.0.0/16",
      # "52.0.0.0/16"
    ]
    "eu-west-1" = [
      # Example IPs - replace with actual Confluent Cloud egress IPs for eu-west-1
    ]
  }

  # Warning message if publicly accessible without IP restrictions
  security_warning = var.publicly_accessible && length(local.confluent_cloud_cidrs_validated) == 0 && var.allowed_cidr_blocks == ["0.0.0.0/0"] ? "WARNING: Aurora is publicly accessible with unrestricted access (0.0.0.0/0). Consider restricting to Confluent Cloud IP ranges for better security." : ""
}
