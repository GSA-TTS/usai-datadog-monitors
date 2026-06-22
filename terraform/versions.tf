terraform {
  required_version = ">= 1.5"

  # Shared remote state in the aigov account, same bucket as the other
  # aigov-tenant Terraform configs (e.g. usai-github-config). S3-native locking
  # via use_lockfile (no DynamoDB table needed).
  backend "s3" {
    bucket       = "aigov-tenant-tfstate"
    key          = "datadog-monitors/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    profile      = "aigov"
  }

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.46"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
