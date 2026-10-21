# アカウントレベルのユーザー/グループと、ワークスペースへの割り当て。
# ワークスペース管理者を分けたいので、グループを users / admins の2つに分ける。

locals {
  users_by_name = { for u in var.users : u.user_name => u }

  member_users = { for k, u in local.users_by_name : k => u if !coalesce(u.admin, false) }
  admin_users  = { for k, u in local.users_by_name : k => u if coalesce(u.admin, false) }
}

resource "databricks_group" "users" {
  provider     = databricks.account
  display_name = "${var.prefix}-users"
}

resource "databricks_group" "admins" {
  provider     = databricks.account
  display_name = "${var.prefix}-admins"
}

resource "databricks_user" "this" {
  provider = databricks.account
  for_each = local.users_by_name

  user_name    = each.value.user_name
  display_name = each.value.display_name

  # 既存ユーザーの取り込み可否
  force = var.adopt_existing_users

  # destroy 時にアカウントから本当に削除するか、無効化で止めるか
  disable_as_user_deletion = !var.delete_users_on_destroy

  # 一時環境なので、削除時にホームディレクトリと Repos も片付ける
  force_delete_home_dir = var.delete_users_on_destroy
  force_delete_repos    = var.delete_users_on_destroy
}

resource "databricks_service_principal" "this" {
  provider = databricks.account
  for_each = toset(var.service_principals)

  display_name = each.value
  force        = var.adopt_existing_users
}

resource "databricks_group_member" "users" {
  provider = databricks.account
  for_each = local.member_users

  group_id  = databricks_group.users.id
  member_id = databricks_user.this[each.key].id
}

resource "databricks_group_member" "admins" {
  provider = databricks.account
  for_each = local.admin_users

  group_id  = databricks_group.admins.id
  member_id = databricks_user.this[each.key].id
}

resource "databricks_group_member" "service_principals" {
  provider = databricks.account
  for_each = toset(var.service_principals)

  group_id  = databricks_group.users.id
  member_id = databricks_service_principal.this[each.key].id
}

# ---------------------------------------------------------------------------
# ワークスペースへの割り当て (アカウントAPI)
# ---------------------------------------------------------------------------
resource "databricks_mws_permission_assignment" "users" {
  provider = databricks.account

  workspace_id = var.workspace_id
  principal_id = databricks_group.users.id
  permissions  = ["USER"]
}

resource "databricks_mws_permission_assignment" "admins" {
  provider = databricks.account

  workspace_id = var.workspace_id
  principal_id = databricks_group.admins.id
  permissions  = ["ADMIN"]
}

# ---------------------------------------------------------------------------
# エンタイトルメント (ワークスペースレベル)
# ---------------------------------------------------------------------------
resource "databricks_entitlements" "users" {
  provider = databricks.workspace

  group_id                   = databricks_group.users.id
  workspace_access           = var.entitlements.workspace_access
  databricks_sql_access      = var.entitlements.databricks_sql_access
  allow_cluster_create       = var.entitlements.allow_cluster_create
  allow_instance_pool_create = var.entitlements.allow_instance_pool_create

  depends_on = [databricks_mws_permission_assignment.users]
}
