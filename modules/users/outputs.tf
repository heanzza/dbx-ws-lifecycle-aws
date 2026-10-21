output "users_group_name" {
  description = "参加者グループ名"
  value       = databricks_group.users.display_name
}

output "users_group_id" {
  description = "参加者グループID"
  value       = databricks_group.users.id
}

output "admins_group_name" {
  description = "管理者グループ名"
  value       = databricks_group.admins.display_name
}

output "user_names" {
  description = "登録したユーザーのメールアドレス一覧"
  value       = sort([for u in databricks_user.this : u.user_name])
}

output "service_principal_application_ids" {
  description = "作成したサービスプリンシパルの application_id"
  value       = { for k, sp in databricks_service_principal.this : k => sp.application_id }
}
