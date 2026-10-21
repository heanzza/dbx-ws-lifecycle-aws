variable "account_id" {
  description = "Databricks アカウントID"
  type        = string
}

variable "workspace_id" {
  description = "ユーザーを割り当てるワークスペースID"
  type        = string
}

variable "prefix" {
  description = "グループ名の接頭辞"
  type        = string
}

variable "users" {
  description = <<-EOT
    登録するユーザーの一覧。
      user_name    : メールアドレス (必須)
      display_name : 表示名 (省略可)
      admin        : true なら workspace admin として割り当て
  EOT
  type = list(object({
    user_name    = string
    display_name = optional(string)
    admin        = optional(bool, false)
  }))
  default = []
}

variable "service_principals" {
  description = "自動化用サービスプリンシパルの表示名一覧。ワークショップ参加者とは別に CI 用SPを足したい場合に使う"
  type        = list(string)
  default     = []
}

variable "adopt_existing_users" {
  description = <<-EOT
    true にすると、既にアカウントに存在するユーザーを Terraform の管理下に取り込む (force = true)。
    便利だが destroy 時にそのユーザーがアカウントから削除される点に注意。
    既存の社内ユーザーを混ぜる場合は delete_users_on_destroy = false と併用すること。
  EOT
  type        = bool
  default     = false
}

variable "delete_users_on_destroy" {
  description = "true: destroy でユーザーをアカウントから削除する。false: 無効化 (deactivate) のみ"
  type        = bool
  default     = true
}

variable "entitlements" {
  description = "ワークショップ用グループに付与するエンタイトルメント"
  type = object({
    workspace_access           = optional(bool, true)
    databricks_sql_access      = optional(bool, true)
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  })
  default = {}
}
