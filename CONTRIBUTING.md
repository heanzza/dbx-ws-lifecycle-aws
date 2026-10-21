# このリポジトリの使い方 / 変更の流れ

## ローカルでの検証 (認証情報なしでできること)

```bash
make fmt        # terraform fmt -recursive
make validate   # terraform init -backend=false && terraform validate
python3 seed/seed.py --dry-run /tmp/seedtest --scale 0.01   # データ生成だけ試す
python3 scripts/reap.py                                      # 期限判定のドライラン
```

## 変更を入れるとき

1. `modules/` を変えたら必ず `make fmt && make validate` を通す
2. ダミー認証情報で `plan` が通ることを確認する (API は呼ばれない)

   ```bash
   TF_VAR_databricks_account_id=00000000-0000-0000-0000-000000000000 \
   TF_VAR_databricks_client_id=fake \
   TF_VAR_databricks_client_secret=fake \
   make plan ENV=workshop-sample
   ```

   `compute_mode = "HYBRID"` や `create_catalog_storage = true` を試す場合は、
   AWS プロバイダが実認証を要求するため実際の AWS 認証情報が必要になる。

3. プロバイダのバージョンを上げたら、全プラットフォーム分のロックを作り直す

   ```bash
   terraform -chdir=stack providers lock \
     -platform=linux_amd64 -platform=linux_arm64 \
     -platform=darwin_arm64 -platform=darwin_amd64
   ```

   (CI は Linux ランナーなので、ローカルの darwin だけのロックだとチェックサム不一致で落ちる)

## 絶対にコミットしないもの

- `*.tfstate` / `*.tfstate.*` (`.gitignore` 済み)
- 認証情報。`TF_VAR_databricks_client_secret` 等は環境変数で渡す
- `envs/*/terraform.tfvars` に実在するアカウントIDやメールアドレスを書かない
  (サンプルは `example.com` を使っている)
