terraform {
  # 既定はローカルstate。state ファイルのパスは init 時に渡す:
  #   terraform -chdir=stack init -backend-config="path=../envs/<ENV>/terraform.tfstate"
  # (Makefile が自動で渡します)
  backend "local" {}

  # チーム運用/CI で自動削除を回す場合は S3 backend に差し替える:
  #
  # backend "s3" {}
  #
  # で、envs/<ENV>/backend.hcl に以下を書いて
  #   terraform -chdir=stack init -backend-config=../envs/<ENV>/backend.hcl
  # とする (Makefile の BACKEND_CONFIG 変数)。
  #
  #   bucket       = "my-tfstate"
  #   key          = "dbx-ws-lifecycle/workshop-sample.tfstate"
  #   region       = "ap-northeast-1"
  #   use_lockfile = true
}
