variable "account_id" {
  description = "Databricks アカウントID (UC 用IAMロールの外部IDに使用)"
  type        = string
}

variable "workspace_id" {
  description = "ワークスペースID"
  type        = string
}

variable "prefix" {
  description = "リソース名の接頭辞"
  type        = string
}

variable "catalog_name" {
  description = "作成する UC カタログ名 (catalog_mode = \"create\" のとき)"
  type        = string
}

variable "catalog_mode" {
  description = <<-EOT
    カタログの扱い方。

      create            : 新規カタログを作る (既定)。メタストアにルートストレージがあるか、
                          create_catalog_storage = true が必要
      workspace_default : ワークスペース作成時に自動生成される既定カタログを使う。
                          アカウントで Default Storage が有効な場合、API からは
                          Default Storage のカタログを新規作成できないため、こちらを使う
      existing          : existing_catalog_name で指定した既存カタログを使う

    create 以外では、カタログは作らずスキーマとボリュームだけをそのカタログ内に作る。
  EOT
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "workspace_default", "existing"], var.catalog_mode)
    error_message = "catalog_mode は create / workspace_default / existing のいずれかです。"
  }
}

variable "existing_catalog_name" {
  description = "catalog_mode が create 以外のときに使うカタログ名"
  type        = string
  default     = null
}

variable "schema_name" {
  description = "サンプルデータを置くスキーマ名"
  type        = string
  default     = "sample"
}

variable "volume_name" {
  description = "CSV 取り込み用のボリューム名"
  type        = string
  default     = "landing"
}

variable "metastore_id" {
  description = <<-EOT
    割り当てるメタストアID。
    null の場合は何もしない (アカウントで UC 自動有効化されており、新規WSに既定メタストアが自動割当される前提)。
    自動割当されない場合のみ指定する。
  EOT
  type        = string
  default     = null
}

variable "default_catalog_name" {
  description = "メタストア割り当て時に設定する既定カタログ。metastore_id を指定した場合のみ有効"
  type        = string
  default     = null
}

variable "create_catalog_storage" {
  description = <<-EOT
    true にすると、このカタログ専用の S3 バケット + UC 用IAMロール + ストレージ資格情報 + 外部ロケーションを作り、
    カタログの storage_root に設定する。
    メタストアにルートストレージが無い場合 (新しいアカウントの既定メタストア等) に必要。
    false の場合はメタストア/既定のマネージドストレージに格納される。
  EOT
  type        = bool
  default     = false
}

variable "warehouse_size" {
  description = "サンプルデータ投入と参加者クエリ用 SQL ウェアハウスのサイズ"
  type        = string
  default     = "2X-Small"
}

variable "warehouse_auto_stop_mins" {
  description = "SQL ウェアハウスの自動停止 (分)。コスト抑制のため短くする"
  type        = number
  default     = 10
}

variable "users_group_name" {
  description = "読み取り権限を与える参加者グループ名"
  type        = string
}

variable "admins_group_name" {
  description = "ALL PRIVILEGES を与える管理者グループ名"
  type        = string
}

variable "tags" {
  description = "AWS リソースおよびウェアハウスに付与するタグ"
  type        = map(string)
  default     = {}
}

variable "iam_propagation_seconds" {
  description = "UC 用IAMロール作成後に外部ロケーション検証まで待つ秒数"
  type        = number
  default     = 30
}

variable "uc_ready_wait_seconds" {
  description = <<-EOT
    ワークスペース作成直後は Unity Catalog の初期化 (既定メタストアの割り当てと
    既定カタログの作成) が完了していないことがあり、すぐにカタログを作ろうとすると失敗する。
    初回 apply のときだけこの秒数だけ待つ。0 で無効。
  EOT
  type        = number
  default     = 90
}
