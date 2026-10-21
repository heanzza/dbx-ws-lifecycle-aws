# UC カタログ/スキーマ/ボリューム/ウェアハウスと権限。
# カタログは force_destroy = true なので、投入したサンプルデータは destroy で一緒に消える。

locals {
  create_storage = var.create_catalog_storage

  bucket_name  = "${substr(var.prefix, 0, 40)}-uc-${random_string.suffix.result}"
  uc_role_name = "${var.prefix}-uc-access"
  storage_root = local.create_storage ? "s3://${aws_s3_bucket.catalog[0].bucket}/catalog" : null
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ---------------------------------------------------------------------------
# メタストア割り当て (自動割当されないアカウントのみ)
# ---------------------------------------------------------------------------
resource "databricks_metastore_assignment" "this" {
  provider = databricks.account
  count    = var.metastore_id == null ? 0 : 1

  workspace_id         = var.workspace_id
  metastore_id         = var.metastore_id
  default_catalog_name = var.default_catalog_name
}

# ---------------------------------------------------------------------------
# カタログ専用ストレージ (任意)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "catalog" {
  count = local.create_storage ? 1 : 0

  bucket        = local.bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "catalog" {
  count  = local.create_storage ? 1 : 0
  bucket = aws_s3_bucket.catalog[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "databricks_aws_unity_catalog_assume_role_policy" "this" {
  provider = databricks.account
  count    = local.create_storage ? 1 : 0

  aws_account_id = data.aws_caller_identity.current[0].account_id
  role_name      = local.uc_role_name
  external_id    = var.account_id
}

data "databricks_aws_unity_catalog_policy" "this" {
  provider = databricks.account
  count    = local.create_storage ? 1 : 0

  aws_account_id = data.aws_caller_identity.current[0].account_id
  bucket_name    = aws_s3_bucket.catalog[0].bucket
  role_name      = local.uc_role_name
}

# SERVERLESS かつ create_catalog_storage = false のときは AWS 認証情報を一切要求しないよう、
# このデータソースも条件付きで読む。
data "aws_caller_identity" "current" {
  count = local.create_storage ? 1 : 0
}

resource "aws_iam_role" "uc_access" {
  count = local.create_storage ? 1 : 0

  name               = local.uc_role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.this[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "uc_access" {
  count = local.create_storage ? 1 : 0

  name   = "${var.prefix}-uc-access-policy"
  role   = aws_iam_role.uc_access[0].id
  policy = data.databricks_aws_unity_catalog_policy.this[0].json
}

resource "time_sleep" "uc_iam_propagation" {
  count = local.create_storage ? 1 : 0

  create_duration = "${var.iam_propagation_seconds}s"
  depends_on      = [aws_iam_role_policy.uc_access]
}

resource "databricks_storage_credential" "this" {
  provider = databricks.workspace
  count    = local.create_storage ? 1 : 0

  name          = "${var.prefix}-cred"
  comment       = "Managed by ${var.prefix} (ephemeral environment)"
  force_destroy = true

  aws_iam_role {
    role_arn = aws_iam_role.uc_access[0].arn
  }

  depends_on = [time_sleep.uc_iam_propagation]
}

resource "databricks_external_location" "this" {
  provider = databricks.workspace
  count    = local.create_storage ? 1 : 0

  name            = "${var.prefix}-root"
  url             = "s3://${aws_s3_bucket.catalog[0].bucket}/catalog"
  credential_name = databricks_storage_credential.this[0].name
  comment         = "Managed by ${var.prefix} (ephemeral environment)"
  force_destroy   = true
}

# ---------------------------------------------------------------------------
# カタログ / スキーマ / ボリューム
# ---------------------------------------------------------------------------
resource "databricks_catalog" "this" {
  provider = databricks.workspace

  name         = var.catalog_name
  comment      = "Managed by ${var.prefix} (ephemeral environment)"
  storage_root = local.storage_root
  # 一時環境なので、中身のテーブルごと destroy できるようにする
  force_destroy = true

  properties = {
    managed_by = "dbx-ws-lifecycle"
    env        = var.prefix
  }

  depends_on = [
    databricks_metastore_assignment.this,
    databricks_external_location.this,
  ]
}

resource "databricks_schema" "this" {
  provider = databricks.workspace

  catalog_name  = databricks_catalog.this.name
  name          = var.schema_name
  comment       = "サンプルデータ"
  force_destroy = true
}

resource "databricks_volume" "landing" {
  provider = databricks.workspace

  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.this.name
  name         = var.volume_name
  volume_type  = "MANAGED"
  comment      = "CSV 取り込み用のランディング領域"
}

# ---------------------------------------------------------------------------
# 権限
# ---------------------------------------------------------------------------
resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  catalog  = databricks_catalog.this.name

  grant {
    principal  = var.admins_group_name
    privileges = ["ALL_PRIVILEGES"]
  }

  grant {
    principal = var.users_group_name
    privileges = [
      "USE_CATALOG",
      "USE_SCHEMA",
      "SELECT",
      "READ_VOLUME",
      "EXECUTE",
    ]
  }
}

# ---------------------------------------------------------------------------
# SQL ウェアハウス (データ投入 + 参加者のクエリ用)
# ---------------------------------------------------------------------------
resource "databricks_sql_endpoint" "this" {
  provider = databricks.workspace

  name                      = "${var.prefix}-wh"
  cluster_size              = var.warehouse_size
  auto_stop_mins            = var.warehouse_auto_stop_mins
  enable_serverless_compute = true
  warehouse_type            = "PRO"
  max_num_clusters          = 1

  tags {
    dynamic "custom_tags" {
      for_each = var.tags
      content {
        key   = custom_tags.key
        value = custom_tags.value
      }
    }
  }
}

resource "databricks_permissions" "warehouse" {
  provider        = databricks.workspace
  sql_endpoint_id = databricks_sql_endpoint.this.id

  access_control {
    group_name       = var.users_group_name
    permission_level = "CAN_USE"
  }

  access_control {
    group_name       = var.admins_group_name
    permission_level = "CAN_MANAGE"
  }
}
