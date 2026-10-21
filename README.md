# Databricks ワークスペース ライフサイクル自動化 (AWS / Terraform)

一時的な Databricks ワークスペースを **作成 → ユーザー自動追加 → サンプルデータ投入 → まとめて自動削除**
するための Terraform 雛形です。ワークショップ・PoC・検証環境の使い捨て運用を想定しています。

```
make up   ENV=workshop-sample    # 作成 + ユーザー追加 + データ投入 (1コマンド)
make down ENV=workshop-sample    # ワークスペース・ユーザー・データを全削除
make reap                        # 期限切れ環境を一覧 (削除は reap-apply)
```

## 何が作られるか

| レイヤ | リソース | 削除時の扱い |
|---|---|---|
| ワークスペース | `databricks_mws_workspaces` (+ HYBRID 時はクロスアカウントIAMロール / ルートS3) | destroy で削除。S3 は `force_destroy` で中身ごと |
| ユーザー | アカウントユーザー、`<env>-users` / `<env>-admins` グループ、ワークスペース割り当て、エンタイトルメント | destroy で削除 (ホームディレクトリ・Repos も削除) |
| データ | UC カタログ / スキーマ / ボリューム、SQL ウェアハウス、権限付与 | カタログは `force_destroy` なので投入したテーブルごと削除 |
| 期限管理 | ワークスペースの `custom_tags` と `envs/<ENV>/manifest.json` に `expires_at` を記録 | reaper が期限切れを検出して destroy |

サンプルデータは日本語の小売データ (顧客 2,000 / 商品 60 / 取引 50,000 + 都道府県別日次売上ビュー) です。

## 構成

```
.
├── Makefile                      # 入口。up / down / reap など
├── stack/                        # Terraform ルート (コードは1本)
│   ├── providers.tf              #   account / workspace の2段プロバイダ
│   ├── main.tf                   #   3モジュールの合成 + 期限 + manifest 出力
│   └── backend.tf                #   既定はローカルstate。CI では S3 に差し替え
├── modules/
│   ├── workspace/                # ワークスペース本体 (+ HYBRID 用 AWS リソース)
│   ├── users/                    # ユーザー・グループ・割り当て・エンタイトルメント
│   └── data/                     # UC カタログ/スキーマ/ボリューム/ウェアハウス/権限
├── envs/<ENV>/                   # 環境ごとの tfvars・users.csv・state・manifest.json
├── seed/seed.py                  # サンプルデータ投入 (CSV → ボリューム → Delta)
├── scripts/reap.py               # 期限切れ環境を terraform destroy
├── scripts/orphan_scan.py        # state から外れた環境の洗い出し
└── .github/workflows/reap.yml    # 期限切れ自動削除 (日次)
```

環境を増やすときは `envs/` 配下をコピーするだけで、Terraform コード自体は共通のまま使えます。
state は環境ごとに分かれます (`envs/<ENV>/terraform.tfstate`)。

## 事前準備

### 1. 必要なもの

- Terraform >= 1.5 (検証は 1.15.0)
- Python 3.9+ と `pip install "databricks-sdk>=0.40"`
- **アカウント管理者権限を持つサービスプリンシパル** (OAuth M2M の client_id / client_secret)
  - アカウントコンソール → User management → Service principals → OAuth secrets で発行
  - ワークスペース作成・ユーザー管理・権限割り当てに必要
- AWS 認証情報は **`compute_mode = "HYBRID"` または `create_catalog_storage = true` のときだけ** 必要
  (サーバーレス専用ワークスペースなら AWS 側にリソースを作らないため不要)

### 2. 認証情報を環境変数で渡す

```bash
export TF_VAR_databricks_account_id='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
export TF_VAR_databricks_client_id='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
export TF_VAR_databricks_client_secret='dose...'
```

tfvars には書かないでください (`.gitignore` 済みですが事故防止のため)。

### 3. 環境を定義する

```bash
cp -r envs/workshop-sample envs/my-workshop
vi envs/my-workshop/terraform.tfvars   # env_name, owner, lifetime_days など
vi envs/my-workshop/users.csv          # 参加者のメールアドレス
```

`users.csv` の形式:

```csv
user_name,display_name,admin
lead@example.com,講師 太郎,true
attendee01@example.com,参加者 01,false
```

`admin = true` のユーザーは `<env>-admins` グループ経由でワークスペース管理者になります。
tfvars の `users` に直接書くこともでき、CSV とマージされます (重複は tfvars 優先)。

## ローカルで試す (サービスプリンシパル不要)

自分のユーザー権限 (U2M OAuth) で動かせるので、サービスプリンシパルを用意する前に試せます。
**アカウント管理者権限を持つユーザー**で、対象アカウントにログインしてください。

```bash
# 1. アカウントレベルのプロファイルを作る (ブラウザが開きます)
databricks auth login \
  --host https://accounts.cloud.databricks.com \
  --account-id <ACCOUNT_ID> \
  --profile acct-test

# 2. 検証用の環境を用意する
cp -r envs/workshop-sample envs/local-test
cat >> envs/local-test/terraform.tfvars <<'EOT'
databricks_cli_profile = "acct-test"
databricks_account_id  = "<ACCOUNT_ID>"
EOT
# env_name / lifetime_days / users_csv_path も local-test 用に直す
# (検証なので lifetime_days = 1、ユーザーは架空のテスト用メールだけにする)

# 3. 実行
make plan ENV=local-test
make up   ENV=local-test
make down ENV=local-test
```

仕組み: アカウントAPI はプロファイルで認証し、作成直後のワークスペースに対しては
`databricks_mws_workspaces` の `token` ブロックで PAT を1本発行して、
ワークスペースプロバイダと `seed.py` の認証に使います (既定の有効期間 24時間)。

> 自分の実ユーザーを `users.csv` に入れないでください。`make down` でアカウントから
> 削除されてしまいます。架空のテスト用メールアドレスを使ってください。

CI や恒久運用ではサービスプリンシパル (`client_id` / `client_secret`) を使います。

### VS Code から実行する

`.vscode/tasks.json` を同梱しています。**Cmd+Shift+P → 「Tasks: Run Task」** で以下を選べます
(環境名を聞かれるので `local-test` 等を入力)。

| タスク | 中身 |
|---|---|
| `1. validate (認証不要)` | `make validate` |
| `2. plan` | `make plan ENV=<環境名>` |
| `3. up (作成 + ユーザー + データ投入)` | `make up ENV=<環境名>` |
| `4. outputs (URL等を表示)` | `make outputs ENV=<環境名>` |
| `5. seed のみ再実行` | `make seed ENV=<環境名>` |
| `9. down (全削除)` | `make down ENV=<環境名>` |
| `reap (期限切れ一覧)` | `make reap` |

推奨拡張 (`.vscode/extensions.json`): HashiCorp Terraform / Python / Makefile Tools / Databricks。
Terraform 拡張の補完を効かせるため、`stack/` をルートモジュールとして設定済みです。

## 使い方

```bash
# 差分確認
make plan ENV=my-workshop

# 作成 + ユーザー追加 + サンプルデータ投入
make up ENV=my-workshop

# データ量を変えたいとき (0.1 = 1/10)
make seed ENV=my-workshop SEED_SCALE=0.1

# 出力値 (ワークスペースURL、カタログ名、期限など)
make outputs ENV=my-workshop

# 全削除
make down ENV=my-workshop
```

`make up` 後の出力例:

```
workspace_url    = "https://dbc-xxxxxxxx-xxxx.cloud.databricks.com"
catalog_name     = "my_workshop_demo"
warehouse_id     = "abc123def456"
users_group_name = "my-workshop-users"
expires_at       = "2026-10-28T09:00:00Z"
```

## 自動削除 (reaper)

有効期限は `lifetime_days` (既定 7日) で決まり、apply 時刻から計算されて 2箇所に記録されます。

- ワークスペースの `custom_tags.expires_at`
- `envs/<ENV>/manifest.json`

### ローカル / cron から

```bash
make reap          # 一覧と判定のみ (ドライラン)
make reap-apply    # 期限切れを terraform destroy
```

cron 例 (毎朝3時):

```cron
0 3 * * * cd /path/to/dbx-ws-lifecycle-aws && \
  TF_VAR_databricks_account_id=... TF_VAR_databricks_client_id=... TF_VAR_databricks_client_secret=... \
  make reap-apply >> /tmp/dbx-reap.log 2>&1
```

### GitHub Actions から

`.github/workflows/reap.yml` が日次で走ります。CI から動かすには:

1. `stack/backend.tf` の `backend "local"` を `backend "s3"` に差し替える
   (ローカル state はコミットされないため、CI からは destroy できません)
2. `envs/<ENV>/backend.hcl` を用意し、`make init BACKEND_CONFIG=../envs/<ENV>/backend.hcl` で初期化
3. `envs/<ENV>/manifest.json` をコミットする (期限判定に使う)
4. Secrets に `DATABRICKS_ACCOUNT_ID` / `DATABRICKS_CLIENT_ID` / `DATABRICKS_CLIENT_SECRET` を設定
   (HYBRID を使う場合は Variables に `AWS_ROLE_TO_ASSUME` も)

### state を失った場合

```bash
python3 scripts/orphan_scan.py                  # managed_by タグで洗い出して報告
python3 scripts/orphan_scan.py --delete         # ワークスペースとグループを削除
python3 scripts/orphan_scan.py --delete --delete-users  # ユーザーも削除
```

state が残っている環境は必ず `make down` / `make reap-apply` で消してください。
`orphan_scan.py --delete` で消すと state が不整合になります。

## 主な設定項目

| 変数 | 既定値 | 説明 |
|---|---|---|
| `databricks_cli_profile` | `null` | 指定するとCLIプロファイル(U2M)で認証し、サービスプリンシパルが不要になる (ローカル検証用) |
| `compute_mode` | `SERVERLESS` | `SERVERLESS` はサーバーレス専用WSで AWS リソース不要。`HYBRID` はクラシックコンピュート用に IAM ロールとルート S3 を作成 |
| `lifetime_days` | `7` | 有効期間。1〜90 |
| `pricing_tier` | `PREMIUM` | UC を使うため PREMIUM 以上 |
| `deployment_name` | `null` | WS URL のサブドメイン。`null` で自動採番 |
| `catalog_mode` | `create` | `create` / `workspace_default` / `existing`。**アカウントで Default Storage が有効な場合は `workspace_default` が必要** (下記参照) |
| `existing_catalog_name` | `null` | `catalog_mode = "existing"` のときに使うカタログ名 |
| `metastore_id` | `null` | `null` なら既定メタストアの自動割当に任せる |
| `create_catalog_storage` | `false` | カタログ専用 S3 + UC IAM ロール + 外部ロケーションを作る |
| `adopt_existing_users` | `false` | 既存アカウントユーザーを管理下に取り込む |
| `delete_users_on_destroy` | `true` | `false` にすると destroy ではユーザーを無効化するだけ |
| `warehouse_auto_stop_mins` | `10` | コスト抑制のため短め |

## 設計上の注意点・ハマりどころ

- **`compute_mode` に `"HYBRID"` を直接渡せない。** プロバイダは `"SERVERLESS"` のみを許すため、
  クラシック構成では `compute_mode` を未指定 (null) にする必要がある。モジュール内でその変換をしている。
- **ワークスペース用プロバイダの `host` は apply 時まで未確定。** そのため
  ワークスペースプロバイダで **データソースを使ってはいけない** (plan が失敗する)。
  リソースのみなら plan は通ることを確認済み。
- **AWS プロバイダは未使用でも認証情報を要求する。** サーバーレス構成では AWS リソースを作らないので、
  `aws_unused` が真のときだけダミー認証情報と検証スキップを渡している (`stack/providers.tf`)。
- **Default Storage が有効なアカウントでは、カタログを API から新規作成できない。**
  メタストアにルートストレージが無く Default Storage が使われている場合、カタログ作成は
  次のエラーになる (実機で確認):

  ```
  cannot create catalog: Metastore storage root URL does not exist.
  Default Storage is enabled in your account. You can use the UI to create a new catalog
  using Default Storage, or please provide a storage location for the catalog
  ```

  既定ストレージのパスを `storage_root` に明示しても `Please use the UI to create a catalog
  with Default Storage.` で拒否されます。UI 専用の操作なので、Terraform からは次のどちらかを選びます。

  | 選択肢 | 設定 | 備考 |
  |---|---|---|
  | ワークスペース既定カタログを使う | `catalog_mode = "workspace_default"` | **推奨。** ワークスペース作成時に `<ワークスペース名>` のカタログが Default Storage 付きで自動生成されるので、その中にスキーマとボリュームを作る。AWS 認証情報は不要 |
  | 自前のS3を用意する | `create_catalog_storage = true` | カタログ専用の S3 + UC IAMロールを作る。AWS 認証情報が必要 |

  `workspace_default` のとき、カタログには `databricks_grant` (単数) で `USE_CATALOG` だけを
  追加します。`databricks_grants` (複数) は securable 上の付与を総入れ替えしてしまうため、
  自分が作ったものではないカタログには使いません。

- **ワークスペース作成直後は UC の初期化が終わっていない。** 既定メタストアの割り当てと既定カタログの
  作成が完了する前にカタログを作ろうとすると失敗するため、`time_sleep.uc_ready` で既定90秒待つ
  (`uc_ready_wait_seconds` で調整、0で無効)。`triggers` に workspace_id を入れているので
  2回目以降の apply では待ち直さない。
- **IAM は結果整合。** HYBRID / UC ストレージ構成では IAM ロール作成後に `time_sleep` を挟んでいる
  (省くと credential 検証が `MALFORMED_REQUEST` で落ちる)。既定 30秒。
- **`adopt_existing_users = true` は destroy でそのユーザーをアカウントから消す。**
  既存の社内ユーザーを混ぜる場合は `delete_users_on_destroy = false` と併用すること。
- **`force_destroy` を多用している。** 一時環境前提のため、カタログ・S3・外部ロケーションは
  中身ごと消える設定になっている。本番用に流用する場合は必ず外すこと。
- **プロファイル認証では PAT が1本発行される。** アカウント側はプロファイルで認証できても、
  作成直後のワークスペースに使える認証情報が他に無いため。アカウント設定で PAT が禁止されている
  場合はこの経路は使えないので、サービスプリンシパルを使うこと。
- **ワークスペースの削除は数分かかる。** destroy が途中で止まった場合は同じ `make down` を再実行すれば続行できる。

## 検証状況

- `terraform validate`: PASS
- `terraform plan` (ダミー認証情報、API 呼び出しなし):
  - `SERVERLESS` + `create_catalog_storage = false` → 24 リソース、エラーなし
  - `HYBRID` → 33 リソース、エラーなし
  - `create_catalog_storage = true` → 31 リソース (`aws_caller_identity` の読み取りのみ実 AWS 認証が必要)
- `seed/seed.py --dry-run`: データ生成と CSV 出力を確認済み
- `scripts/reap.py`: 期限判定とドライラン出力を確認済み
実アカウント (AWS / ap-northeast-1 / サーバーレス専用WS) での `apply` 実機確認:

- ワークスペース作成 → OK (Provisioning から Running まで約10分)
- アカウントユーザー2名・グループ2つ・ワークスペース割り当て・エンタイトルメント → OK
- SQL ウェアハウス + 権限 → OK
- CLI プロファイル (U2M) 認証と、そこから発行した PAT によるワークスペースAPI操作 → OK
- カタログ新規作成 → **Default Storage 有効アカウントでは不可**。`catalog_mode = "workspace_default"`
  で既定カタログ内にスキーマ/ボリュームを作る経路に切り替えて解決
- **未実施**: `destroy` の通し実行、`seed` の実機実行、HYBRID 構成、`create_catalog_storage = true`
