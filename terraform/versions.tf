terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0" # Updated to support Aurora DSQL (released May 2025)
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }

  # Backend configuration for S3 state storage
  # IMPORTANT: The S3 bucket must be created first before enabling this backend.
  # 
  # Steps to enable:
  # 1. Run `terraform apply` with local state to create the S3 bucket
  # 2. Get the bucket name from `terraform output terraform_state_bucket_name`
  # 3. Create terraform.tfbackend file with these values (see terraform.tfbackend.example)
  # 4. Run `terraform init -backend-config=terraform.tfbackend` to migrate state
  #
  # Note: Using S3 native state locking (use_lockfile) - no DynamoDB required!
  # This feature is available in Terraform 1.10+ and is the recommended approach.
  # DynamoDB-based locking is deprecated as of Terraform 1.11.
  #
  # S3 backend configuration (using terraform.tfbackend for values)
  backend "s3" {
    # Values are provided via -backend-config=terraform.tfbackend
    # This allows the backend to be configured without hardcoding values
  }
}

