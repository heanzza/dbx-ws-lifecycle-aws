output "catalog_name" {
  description = "サンプルデータを置いた UC カタログ名 (新規作成または既存)"
  value       = local.target_catalog
}

output "schema_name" {
  description = "サンプルデータのスキーマ名"
  value       = databricks_schema.this.name
}

output "volume_path" {
  description = "ランディングボリュームのパス (/Volumes/...)"
  value       = databricks_volume.landing.volume_path
}

output "warehouse_id" {
  description = "SQL ウェアハウスID (サンプルデータ投入スクリプトに渡す)"
  value       = databricks_sql_endpoint.this.id
}

output "warehouse_name" {
  description = "SQL ウェアハウス名"
  value       = databricks_sql_endpoint.this.name
}

output "catalog_bucket" {
  description = "カタログ専用S3バケット名 (create_catalog_storage = true のとき)"
  value       = local.create_storage ? aws_s3_bucket.catalog[0].bucket : null
}
