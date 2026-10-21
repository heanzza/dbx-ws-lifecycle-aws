# ワークスペース本体と、クラシックコンピュート用の AWS 側リソース。
# compute_mode = SERVERLESS の場合、IAMロールとルートS3バケットは一切作らない。

locals {
  is_hybrid = var.compute_mode == "HYBRID"

  # S3 バケット名はグローバル一意かつ63文字以内。prefix が長い場合に備えて切り詰める。
  root_bucket_name        = "${substr(var.prefix, 0, 40)}-root-${random_string.suffix.result}"
  cross_account_role_name = "${var.prefix}-crossaccount"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ---------------------------------------------------------------------------
# ルート S3 バケット (DBFS root) - HYBRID のみ
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "root" {
  count = local.is_hybrid ? 1 : 0

  bucket = local.root_bucket_name
  # teardown でバケット内のオブジェクトごと削除できるようにする (一時環境前提)
  force_destroy = true
  tags          = var.aws_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root" {
  count  = local.is_hybrid ? 1 : 0
  bucket = aws_s3_bucket.root[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "root" {
  count  = local.is_hybrid ? 1 : 0
  bucket = aws_s3_bucket.root[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket.root]
}

data "databricks_aws_bucket_policy" "root" {
  count = local.is_hybrid ? 1 : 0

  databricks_account_id = var.account_id
  bucket                = aws_s3_bucket.root[0].bucket
}

resource "aws_s3_bucket_policy" "root" {
  count = local.is_hybrid ? 1 : 0

  bucket = aws_s3_bucket.root[0].id
  policy = data.databricks_aws_bucket_policy.root[0].json

  depends_on = [aws_s3_bucket_public_access_block.root]
}

resource "databricks_mws_storage_configurations" "this" {
  count = local.is_hybrid ? 1 : 0

  account_id                 = var.account_id
  storage_configuration_name = "${var.prefix}-storage"
  bucket_name                = aws_s3_bucket.root[0].bucket
}

# ---------------------------------------------------------------------------
# クロスアカウント IAM ロール - HYBRID のみ
# ---------------------------------------------------------------------------
data "databricks_aws_assume_role_policy" "this" {
  count = local.is_hybrid ? 1 : 0

  databricks_account_id = var.account_id
  external_id           = var.account_id
}

resource "aws_iam_role" "cross_account" {
  count = local.is_hybrid ? 1 : 0

  name               = local.cross_account_role_name
  assume_role_policy = data.databricks_aws_assume_role_policy.this[0].json
  tags               = var.aws_tags
}

data "databricks_aws_crossaccount_policy" "this" {
  count = local.is_hybrid ? 1 : 0
}

resource "aws_iam_role_policy" "cross_account" {
  count = local.is_hybrid ? 1 : 0

  name   = "${var.prefix}-crossaccount-policy"
  role   = aws_iam_role.cross_account[0].id
  policy = data.databricks_aws_crossaccount_policy.this[0].json
}

# IAM は結果整合。作成直後に Databricks 側で検証すると失敗するため待機する。
resource "time_sleep" "iam_propagation" {
  count = local.is_hybrid ? 1 : 0

  create_duration = "${var.iam_propagation_seconds}s"
  depends_on      = [aws_iam_role_policy.cross_account]
}

resource "databricks_mws_credentials" "this" {
  count = local.is_hybrid ? 1 : 0

  account_id       = var.account_id
  credentials_name = "${var.prefix}-creds"
  role_arn         = aws_iam_role.cross_account[0].arn

  depends_on = [time_sleep.iam_propagation]
}

# ---------------------------------------------------------------------------
# ワークスペース
# ---------------------------------------------------------------------------
resource "databricks_mws_workspaces" "this" {
  account_id      = var.account_id
  workspace_name  = var.workspace_name
  deployment_name = var.deployment_name
  aws_region      = var.aws_region
  pricing_tier    = var.pricing_tier
  # プロバイダは compute_mode に "SERVERLESS" のみを許す。
  # クラシックコンピュート込み (HYBRID) のワークスペースは「未指定」で作る。
  compute_mode = local.is_hybrid ? null : "SERVERLESS"
  custom_tags  = var.custom_tags

  credentials_id           = local.is_hybrid ? databricks_mws_credentials.this[0].credentials_id : null
  storage_configuration_id = local.is_hybrid ? databricks_mws_storage_configurations.this[0].storage_configuration_id : null
  network_id               = local.is_hybrid ? var.network_id : null

  # CLI プロファイル認証のときだけ、ワークスペース用の PAT を発行する
  dynamic "token" {
    for_each = var.create_token ? [1] : []
    content {
      comment          = "Terraform (${var.prefix})"
      lifetime_seconds = var.token_lifetime_seconds
    }
  }

  timeouts {
    create = "60m"
  }
}
