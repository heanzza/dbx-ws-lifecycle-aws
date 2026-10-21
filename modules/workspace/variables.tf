variable "account_id" {
  description = "Databricks account ID (accounts.cloud.databricks.com のアカウントID)"
  type        = string
}

variable "prefix" {
  description = "全リソース名の接頭辞。環境を一意に識別する"
  type        = string
}

variable "workspace_name" {
  description = "作成するワークスペース名"
  type        = string
}

variable "deployment_name" {
  description = "ワークスペースURLのサブドメイン。null の場合 Databricks が自動採番 (dbc-xxxx)。利用にはアカウントで deployment name prefix の有効化が必要"
  type        = string
  default     = null
}

variable "aws_region" {
  description = "ワークスペースを作成する AWS リージョン"
  type        = string
}

variable "compute_mode" {
  description = "SERVERLESS = サーバーレス専用WS (IAMロール/S3不要)、HYBRID = 従来のクラシックコンピュート込みWS (クロスアカウントIAMロールとルートS3バケットを作成)"
  type        = string
  default     = "SERVERLESS"

  validation {
    condition     = contains(["SERVERLESS", "HYBRID"], var.compute_mode)
    error_message = "compute_mode は SERVERLESS または HYBRID を指定してください。"
  }
}

variable "pricing_tier" {
  description = "PREMIUM または ENTERPRISE。UC/ABAC を使うため PREMIUM 以上を推奨"
  type        = string
  default     = "PREMIUM"
}

variable "network_id" {
  description = "顧客管理VPC (databricks_mws_networks) の ID。null なら Databricks 管理VPC。compute_mode = HYBRID のときのみ有効"
  type        = string
  default     = null
}

variable "custom_tags" {
  description = "ワークスペースに付与するカスタムタグ。expires_at / managed_by を入れて reaper の判定に使う"
  type        = map(string)
  default     = {}
}

variable "aws_tags" {
  description = "作成する AWS リソース (IAMロール/S3) に付与するタグ"
  type        = map(string)
  default     = {}
}

variable "iam_propagation_seconds" {
  description = "IAMロール作成後、Databricks の credential 検証までに待つ秒数。短すぎると MALFORMED_REQUEST で失敗する"
  type        = number
  default     = 30
}

variable "create_token" {
  description = <<-EOT
    true にすると、ワークスペース作成時に PAT を1本発行する。
    アカウント側を CLI プロファイル (U2M OAuth) で認証する場合、
    作成直後のワークスペースに対して使える認証情報が他に無いため必要になる。
    サービスプリンシパル (OAuth M2M) で認証する場合は不要。
  EOT
  type        = bool
  default     = false
}

variable "token_lifetime_seconds" {
  description = "発行する PAT の有効期間 (秒)。環境の寿命に合わせる"
  type        = number
  default     = 86400
}
