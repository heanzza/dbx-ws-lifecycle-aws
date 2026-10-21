# ---------------------------------------------------------------------------
# 環境の有効期限
# time_static は apply 時に一度だけ値が決まるので、plan のたびに期限がずれない。
# ---------------------------------------------------------------------------
resource "time_static" "created" {}

locals {
  # CLI プロファイル認証か、サービスプリンシパル認証か
  use_profile_auth = var.databricks_cli_profile != null

  created_at = time_static.created.rfc3339
  expires_at = timeadd(time_static.created.rfc3339, "${var.lifetime_days * 24}h")

  # AWS リソースを 1つも作らない構成かどうか (プロバイダのダミー認証判定に使う)
  aws_unused = var.compute_mode == "SERVERLESS" && !var.create_catalog_storage

  prefix       = var.env_name
  catalog_name = coalesce(var.catalog_name, "${replace(var.env_name, "-", "_")}_demo")

  tags = merge(var.extra_tags, {
    managed_by = "dbx-ws-lifecycle"
    env        = var.env_name
    owner      = var.owner
    expires_at = local.expires_at
  })

  # CSV とtfvarsのユーザーをマージ。user_name が重複した場合は tfvars 側を優先。
  csv_users = var.users_csv_path == null ? [] : [
    for row in csvdecode(file(var.users_csv_path)) : {
      user_name    = trimspace(row.user_name)
      display_name = try(trimspace(row.display_name), null) == "" ? null : try(trimspace(row.display_name), null)
      admin        = try(lower(trimspace(row.admin)) == "true", false)
    }
    if trimspace(try(row.user_name, "")) != ""
  ]

  all_users = values(merge(
    { for u in local.csv_users : lower(u.user_name) => u },
    { for u in var.users : lower(u.user_name) => {
      user_name    = u.user_name
      display_name = u.display_name
      admin        = coalesce(u.admin, false)
    } },
  ))
}

# ---------------------------------------------------------------------------
# 1) ワークスペース
# ---------------------------------------------------------------------------
module "workspace" {
  source = "../modules/workspace"

  providers = {
    databricks = databricks.account
  }

  account_id      = var.databricks_account_id
  prefix          = local.prefix
  workspace_name  = "${var.env_name}-ws"
  deployment_name = var.deployment_name
  aws_region      = var.aws_region
  compute_mode    = var.compute_mode
  pricing_tier    = var.pricing_tier
  network_id      = var.network_id

  custom_tags = local.tags
  aws_tags    = local.tags

  # プロファイル認証のときだけ、ワークスペース用 PAT を発行する
  create_token           = local.use_profile_auth
  token_lifetime_seconds = var.token_lifetime_seconds
}

# ---------------------------------------------------------------------------
# 2) ユーザーとグループ
# ---------------------------------------------------------------------------
module "users" {
  source = "../modules/users"

  providers = {
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  account_id   = var.databricks_account_id
  workspace_id = module.workspace.workspace_id
  prefix       = local.prefix

  users                   = local.all_users
  service_principals      = var.service_principals
  adopt_existing_users    = var.adopt_existing_users
  delete_users_on_destroy = var.delete_users_on_destroy
  entitlements            = var.entitlements
}

# ---------------------------------------------------------------------------
# 3) データ置き場 (カタログ/スキーマ/ボリューム/ウェアハウス/権限)
# ---------------------------------------------------------------------------
module "data" {
  source = "../modules/data"

  providers = {
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  account_id   = var.databricks_account_id
  workspace_id = module.workspace.workspace_id
  prefix       = local.prefix

  catalog_name           = local.catalog_name
  metastore_id           = var.metastore_id
  default_catalog_name   = var.default_catalog_name
  create_catalog_storage = var.create_catalog_storage

  warehouse_size           = var.warehouse_size
  warehouse_auto_stop_mins = var.warehouse_auto_stop_mins

  users_group_name  = module.users.users_group_name
  admins_group_name = module.users.admins_group_name

  tags = local.tags
}

# ---------------------------------------------------------------------------
# 4) マニフェスト (期限切れ自動削除 = reaper が読むファイル)
# ---------------------------------------------------------------------------
resource "local_file" "manifest" {
  filename = "${path.module}/../envs/${var.env_name}/manifest.json"

  content = jsonencode({
    env_name       = var.env_name
    owner          = var.owner
    created_at     = local.created_at
    expires_at     = local.expires_at
    lifetime_days  = var.lifetime_days
    aws_region     = var.aws_region
    compute_mode   = var.compute_mode
    workspace_id   = module.workspace.workspace_id
    workspace_url  = module.workspace.workspace_url
    workspace_name = module.workspace.workspace_name
    catalog_name   = module.data.catalog_name
    schema_name    = module.data.schema_name
    volume_path    = module.data.volume_path
    warehouse_id   = module.data.warehouse_id
    users_group    = module.users.users_group_name
    admins_group   = module.users.admins_group_name
    user_count     = length(local.all_users)
  })
}

# ---------------------------------------------------------------------------
# 認証情報の指定漏れを apply 前に弾く
# ---------------------------------------------------------------------------
check "auth_configured" {
  assert {
    condition = var.databricks_cli_profile != null || (
      var.databricks_client_id != null && var.databricks_client_secret != null
    )
    error_message = join("", [
      "認証情報がありません。次のどちらかを設定してください: ",
      "(1) databricks_cli_profile にアカウントレベルのCLIプロファイル名、",
      "(2) TF_VAR_databricks_client_id と TF_VAR_databricks_client_secret。",
    ])
  }
}
