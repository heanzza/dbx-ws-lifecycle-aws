output "workspace_id" {
  description = "ワークスペースID (数値)"
  value       = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  description = "ワークスペースURL (https://...)"
  value       = databricks_mws_workspaces.this.workspace_url
}

output "workspace_name" {
  description = "ワークスペース名"
  value       = databricks_mws_workspaces.this.workspace_name
}

output "root_bucket" {
  description = "ルートS3バケット名 (HYBRID のみ)"
  value       = local.is_hybrid ? aws_s3_bucket.root[0].bucket : null
}

output "cross_account_role_arn" {
  description = "クロスアカウントIAMロールARN (HYBRID のみ)"
  value       = local.is_hybrid ? aws_iam_role.cross_account[0].arn : null
}
