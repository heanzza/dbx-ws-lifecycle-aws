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
provider "databricks" {
  alias = "account"

  host          = var.databricks_account_host
  account_id    = var.databricks_account_id
  client_id     = var.databricks_client_id
  client_secret = var.databricks_client_secret
}

# 作成直後のワークスペースを指すプロバイダ。
# host は apply 時まで未確定だが、データソースを使わない限り plan は通る。
provider "databricks" {
  alias = "workspace"

  host          = module.workspace.workspace_url
  client_id     = var.databricks_client_id
  client_secret = var.databricks_client_secret
}
