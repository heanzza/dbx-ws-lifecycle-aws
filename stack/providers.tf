# SERVERLESS かつ create_catalog_storage = false のときは AWS リソースを 1つも作らない。
# それでも AWS プロバイダは初期化時に認証情報を解決しようとして失敗するため、
# 使わない場合だけダミー値を入れて認証解決と検証を飛ばす。
provider "aws" {
  region = var.aws_region

  access_key                  = local.aws_unused ? "dummy" : null
  secret_key                  = local.aws_unused ? "dummy" : null
  skip_credentials_validation = local.aws_unused
  skip_requesting_account_id  = local.aws_unused
  skip_metadata_api_check     = local.aws_unused ? "true" : null

  default_tags {
    tags = local.tags
  }
}

# アカウントレベル API (ワークスペース作成・ユーザー・権限割り当て)
#
# 認証は2通り:
#   1) サービスプリンシパル (OAuth M2M) ... CI / 恒久運用向け。既定
#   2) CLI プロファイル (U2M OAuth)      ... ローカル検証向け。databricks_cli_profile を指定
provider "databricks" {
  alias = "account"

  profile       = var.databricks_cli_profile
  host          = local.use_profile_auth ? null : var.databricks_account_host
  account_id    = local.use_profile_auth ? null : var.databricks_account_id
  client_id     = local.use_profile_auth ? null : var.databricks_client_id
  client_secret = local.use_profile_auth ? null : var.databricks_client_secret
}

# 作成直後のワークスペースを指すプロバイダ。
# host は apply 時まで未確定だが、データソースを使わない限り plan は通る。
# プロファイル認証の場合は、プロファイルが別ホスト (アカウントコンソール) を指しているため
# そのままでは使えない。作成時に発行した PAT で認証する。
provider "databricks" {
  alias = "workspace"

  host          = module.workspace.workspace_url
  token         = local.use_profile_auth ? module.workspace.workspace_token : null
  client_id     = local.use_profile_auth ? null : var.databricks_client_id
  client_secret = local.use_profile_auth ? null : var.databricks_client_secret
}
