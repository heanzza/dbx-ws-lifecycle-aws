# ---------------------------------------------------------------------------
# ワークショップ環境サンプル
# 認証情報はここに書かず環境変数で渡す:
#   export TF_VAR_databricks_account_id=...
#   export TF_VAR_databricks_client_id=...
#   export TF_VAR_databricks_client_secret=...
# ---------------------------------------------------------------------------

env_name   = "workshop-sample"
aws_region = "ap-northeast-1"
owner      = "owner@example.com"

# 7日後に reaper が自動削除する
lifetime_days = 7

# SERVERLESS: AWSリソース不要。HYBRID: クロスアカウントIAMロール + ルートS3を作成
compute_mode = "SERVERLESS"
pricing_tier = "PREMIUM"

# 参加者は envs/workshop-sample/users.csv から読む
users_csv_path = "../envs/workshop-sample/users.csv"

# CSV に加えて直接書くこともできる
users = [
  # { user_name = "lead@example.com", display_name = "講師", admin = true },
]

# 参加者グループのエンタイトルメント
entitlements = {
  workspace_access      = true
  databricks_sql_access = true
  allow_cluster_create  = false
}

# サンプルデータ
catalog_name             = "workshop_sample_demo"
warehouse_size           = "2X-Small"
warehouse_auto_stop_mins = 10

# メタストアが自動割当されないアカウントのみ指定
# metastore_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# メタストアにルートストレージが無い場合は true (専用S3 + UC IAMロールを作成)
create_catalog_storage = false

extra_tags = {
  cost_center = "field-eng"
  purpose     = "workshop"
}
