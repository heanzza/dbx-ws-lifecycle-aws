# Databricks ワークスペース ライフサイクル自動化 (AWS)
#
#   make up    ENV=workshop-sample   # WS作成 + ユーザー追加 + データ投入 (一括)
#   make down  ENV=workshop-sample   # WS/ユーザー/データを全削除
#   make reap                        # 期限切れ環境を自動削除 (ドライラン)
#   make reap-apply                  # 期限切れ環境を実際に削除

ENV            ?= workshop-sample
TF             := terraform -chdir=stack
ENV_DIR        := envs/$(ENV)
VAR_FILE       := ../envs/$(ENV)/terraform.tfvars
STATE_PATH     := ../envs/$(ENV)/terraform.tfstate
BACKEND_CONFIG ?=
SEED_SCALE     ?= 1.0

ifeq ($(BACKEND_CONFIG),)
  INIT_BACKEND := -backend-config="path=$(STATE_PATH)"
else
  INIT_BACKEND := -backend-config=$(BACKEND_CONFIG)
endif

.PHONY: help check-env check-creds init fmt validate plan apply seed up outputs down reap reap-apply orphans clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

check-env:
	@test -f "$(ENV_DIR)/terraform.tfvars" || { echo "ERROR: $(ENV_DIR)/terraform.tfvars がありません。envs/workshop-sample をコピーしてください。"; exit 1; }

# 認証はサービスプリンシパル (環境変数) か、tfvars の databricks_cli_profile のどちらか
check-creds:
	@if grep -qE '^[[:space:]]*databricks_cli_profile[[:space:]]*=' "$(ENV_DIR)/terraform.tfvars" 2>/dev/null; then \
		prof=$$(grep -E '^[[:space:]]*databricks_cli_profile[[:space:]]*=' "$(ENV_DIR)/terraform.tfvars" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/'); \
		if ! databricks auth env --profile "$$prof" >/dev/null 2>&1; then \
			echo "ERROR: CLIプロファイル '$$prof' が未認証です。次を実行してください:"; \
			echo "  databricks auth login --host https://accounts.cloud.databricks.com --account-id <ACCOUNT_ID> --profile $$prof"; \
			exit 1; \
		fi; \
		echo "認証: CLIプロファイル '$$prof' を使用"; \
	else \
		for v in TF_VAR_databricks_account_id TF_VAR_databricks_client_id TF_VAR_databricks_client_secret; do \
			eval "val=\$$$$v"; \
			if [ -z "$$val" ]; then echo "ERROR: 環境変数 $$v が未設定です (または tfvars に databricks_cli_profile を設定)"; exit 1; fi; \
		done; \
		echo "認証: サービスプリンシパル (OAuth M2M) を使用"; \
	fi

init: check-env ## Terraform を初期化する (環境ごとに state を分ける)
	$(TF) init -reconfigure -input=false $(INIT_BACKEND)

fmt: ## .tf を整形する
	terraform fmt -recursive .

validate: ## 構文と参照を検証する (認証情報不要)
	$(TF) init -backend=false -input=false >/dev/null
	$(TF) validate

plan: init check-creds ## 差分を表示する
	$(TF) plan -input=false -var-file=$(VAR_FILE)

apply: init check-creds ## WS・ユーザー・カタログを作成する (データ投入は含まない)
	$(TF) apply -auto-approve -input=false -var-file=$(VAR_FILE)

seed: ## サンプルデータを投入する (apply 済みが前提)
	@tok="$$($(TF) output -raw workspace_token 2>/dev/null || true)"; \
	if [ -n "$$tok" ] && [ "$$tok" != "null" ]; then \
		export DATABRICKS_TOKEN="$$tok"; \
		echo "seed 認証: apply 時に発行した PAT を使用"; \
	else \
		export DATABRICKS_CLIENT_ID="$${DATABRICKS_CLIENT_ID:-$$TF_VAR_databricks_client_id}"; \
		export DATABRICKS_CLIENT_SECRET="$${DATABRICKS_CLIENT_SECRET:-$$TF_VAR_databricks_client_secret}"; \
		echo "seed 認証: サービスプリンシパル (OAuth M2M) を使用"; \
	fi; \
	python3 seed/seed.py \
		--host "$$($(TF) output -raw workspace_url)" \
		--warehouse-id "$$($(TF) output -raw warehouse_id)" \
		--catalog "$$($(TF) output -raw catalog_name)" \
		--schema "$$($(TF) output -raw schema_name)" \
		--scale $(SEED_SCALE)

up: apply seed ## 作成からデータ投入まで一括 (おすすめ)
	@echo ""
	@echo "=== 環境ができました ==="
	@$(TF) output

outputs: ## 現在の出力値を表示する
	$(TF) output

down: check-env check-creds ## WS・ユーザー・グループ・カタログを全削除する
	$(TF) init -reconfigure -input=false $(INIT_BACKEND)
	$(TF) destroy -auto-approve -input=false -var-file=$(VAR_FILE)
	@rm -f $(ENV_DIR)/manifest.json
	@echo "削除しました: $(ENV)"

reap: ## 期限切れ環境を一覧表示する (削除しない)
	python3 scripts/reap.py

reap-apply: check-creds ## 期限切れ環境を実際に削除する
	python3 scripts/reap.py --yes $(if $(BACKEND_CONFIG),--backend-config $(BACKEND_CONFIG),)

orphans: ## state 外の期限切れワークスペースを洗い出す
	python3 scripts/orphan_scan.py

clean: ## ローカルの .terraform キャッシュを消す
	rm -rf stack/.terraform
