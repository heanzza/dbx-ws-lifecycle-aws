# ---------------------------------------------------------------------------
# 認証 (環境変数での指定を推奨: TF_VAR_databricks_client_secret 等)
# ---------------------------------------------------------------------------
variable "databricks_account_host" {
  description = "Databricks アカウントコンソールのURL"
  type        = string
  default     = "https://accounts.cloud.databricks.com"
}

variable "databricks_account_id" {
  description = "Databricks アカウントID"
  type        = string
}

variable "databricks_client_id" {
  description = "アカウント管理者権限を持つサービスプリンシパルの client_id (OAuth M2M)。databricks_cli_profile を使う場合は不要"
  type        = string
  default     = null
}

variable "databricks_client_secret" {
  description = "同サービスプリンシパルの client_secret"
  type        = string
  default     = null
  sensitive   = true
}

variable "databricks_cli_profile" {
  description = <<-EOT
    ローカル検証用。~/.databrickscfg の「アカウントレベル」プロファイル名を指定すると、
    サービスプリンシパルを用意せずに自分のユーザー権限 (U2M OAuth) で実行できる。

      databricks auth login --host https://accounts.cloud.databricks.com \
        --account-id <ACCOUNT_ID> --profile <PROFILE>

    この場合、作成直後のワークスペースに使える認証情報が他に無いため、
    ワークスペース作成時に PAT を1本発行してワークスペースプロバイダに渡す。
    CI や恒久運用ではサービスプリンシパル (client_id/client_secret) を使うこと。
  EOT
  type        = string
  default     = null
}

variable "token_lifetime_seconds" {
  description = "databricks_cli_profile 利用時に発行する PAT の有効期間 (秒)"
  type        = number
  default     = 86400
}

# ---------------------------------------------------------------------------
# 環境の基本設定
# ---------------------------------------------------------------------------
variable "env_name" {
  description = "環境名。ワークスペース名・グループ名・カタログ名の素になる (英小文字/数字/ハイフン)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,29}$", var.env_name))
    error_message = "env_name は英小文字・数字・ハイフンで2〜30文字にしてください。"
  }
}

variable "aws_region" {
  description = "ワークスペースを作成する AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "owner" {
  description = "環境の管理者メールアドレス。タグと manifest に記録する"
  type        = string
}

variable "lifetime_days" {
  description = "環境の有効期間 (日)。経過すると reaper が destroy 対象にする"
  type        = number
  default     = 7

  validation {
    condition     = var.lifetime_days > 0 && var.lifetime_days <= 90
    error_message = "lifetime_days は 1〜90 で指定してください。"
  }
}

variable "extra_tags" {
  description = "追加タグ (コストセンター等)"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# ワークスペース
# ---------------------------------------------------------------------------
variable "compute_mode" {
  description = "SERVERLESS (推奨・AWSリソース不要) または HYBRID (クラシックコンピュート用にIAMロールとS3を作成)"
  type        = string
  default     = "SERVERLESS"
}

variable "pricing_tier" {
  description = "PREMIUM または ENTERPRISE"
  type        = string
  default     = "PREMIUM"
}

variable "deployment_name" {
  description = "ワークスペースURLのサブドメイン。null で自動採番"
  type        = string
  default     = null
}

variable "network_id" {
  description = "顧客管理VPC の network_id (HYBRID のみ)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# ユーザー
# ---------------------------------------------------------------------------
variable "users" {
  description = "ユーザー一覧を tfvars に直接書く場合に使う"
  type = list(object({
    user_name    = string
    display_name = optional(string)
    admin        = optional(bool, false)
  }))
  default = []
}

variable "users_csv_path" {
  description = <<-EOT
    ユーザー一覧CSVのパス (stack ディレクトリからの相対パス)。
    ヘッダは user_name,display_name,admin。var.users と併用可 (両方マージされる)。
  EOT
  type        = string
  default     = null
}

variable "service_principals" {
  description = "追加で作成するサービスプリンシパルの表示名一覧"
  type        = list(string)
  default     = []
}

variable "adopt_existing_users" {
  description = "既存アカウントユーザーを Terraform 管理下に取り込む (destroy で削除される点に注意)"
  type        = bool
  default     = false
}

variable "delete_users_on_destroy" {
  description = "true: destroy でユーザーをアカウントから削除。false: 無効化のみ"
  type        = bool
  default     = true
}

variable "entitlements" {
  description = "参加者グループのエンタイトルメント"
  type = object({
    workspace_access           = optional(bool, true)
    databricks_sql_access      = optional(bool, true)
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  })
  default = {}
}

# ---------------------------------------------------------------------------
# データ
# ---------------------------------------------------------------------------
variable "catalog_name" {
  description = "UC カタログ名。null なら <env_name のアンダースコア版>_demo"
  type        = string
  default     = null
}

variable "catalog_mode" {
  description = <<-EOT
    カタログの扱い方。

      create            : 新規カタログを作る (既定)
      workspace_default : ワークスペース作成時に自動生成される既定カタログ
                          (ワークスペース名のハイフンをアンダースコアにしたもの) を使う。
                          アカウントで Default Storage が有効な場合、API からは
                          Default Storage のカタログを新規作成できないためこちらを使う
      existing          : existing_catalog_name で指定した既存カタログを使う
  EOT
  type        = string
  default     = "create"
}

variable "existing_catalog_name" {
  description = "catalog_mode = \"existing\" のときに使うカタログ名"
  type        = string
  default     = null
}

variable "metastore_id" {
  description = "メタストアID。null なら自動割当に任せる"
  type        = string
  default     = null
}

variable "default_catalog_name" {
  description = "メタストア割り当て時の既定カタログ (metastore_id 指定時のみ)"
  type        = string
  default     = null
}

variable "create_catalog_storage" {
  description = "カタログ専用の S3 + UC IAMロール + 外部ロケーションを作る"
  type        = bool
  default     = false
}

variable "warehouse_size" {
  description = "SQL ウェアハウスサイズ"
  type        = string
  default     = "2X-Small"
}

variable "warehouse_auto_stop_mins" {
  description = "SQL ウェアハウスの自動停止 (分)"
  type        = number
  default     = 10
}

variable "uc_ready_wait_seconds" {
  description = "ワークスペース作成後、UC 初期化を待つ秒数 (初回 apply のみ)。0 で無効"
  type        = number
  default     = 90
}
