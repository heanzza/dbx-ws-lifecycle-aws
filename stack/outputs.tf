output "workspace_url" {
  description = "ワークスペースURL"
  value       = module.workspace.workspace_url
}

output "workspace_id" {
  description = "ワークスペースID"
  value       = module.workspace.workspace_id
}

output "catalog_name" {
  description = "サンプルデータのカタログ"
  value       = module.data.catalog_name
}

output "schema_name" {
  description = "サンプルデータのスキーマ"
  value       = module.data.schema_name
}

output "volume_path" {
  description = "ランディングボリュームのパス"
  value       = module.data.volume_path
}

output "warehouse_id" {
  description = "SQL ウェアハウスID"
  value       = module.data.warehouse_id
}

output "users_group_name" {
  description = "参加者グループ名"
  value       = module.users.users_group_name
}

output "user_names" {
  description = "登録したユーザー"
  value       = module.users.user_names
}

output "expires_at" {
  description = "この環境の有効期限 (RFC3339)"
  value       = local.expires_at
}

output "seed_command" {
  description = "サンプルデータ投入コマンド"
  value       = "python3 seed/seed.py --host ${module.workspace.workspace_url} --warehouse-id ${module.data.warehouse_id} --catalog ${module.data.catalog_name} --schema ${module.data.schema_name}"
}
