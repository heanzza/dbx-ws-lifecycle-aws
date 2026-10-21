terraform {
  required_version = ">= 1.5.0"

  required_providers {
    databricks = {
      source                = "databricks/databricks"
      version               = ">= 1.138.0"
      configuration_aliases = [databricks.account, databricks.workspace]
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}
