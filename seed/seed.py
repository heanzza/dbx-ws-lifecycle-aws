#!/usr/bin/env python3
"""UC カタログにサンプルデータを投入する。

CSV をローカル生成 -> UC ボリュームにアップロード -> read_files で Delta テーブル化する。
Terraform が作ったカタログ/スキーマ/ボリューム/ウェアハウスを前提にする。

使い方:
    python3 seed/seed.py \
        --host https://dbc-xxxx.cloud.databricks.com \
        --warehouse-id abc123 \
        --catalog workshop_sample_demo \
        --schema sample

認証は databricks-sdk の既定の順序で解決される:
    --profile <名前>                     (~/.databrickscfg)
    DATABRICKS_CLIENT_ID / _CLIENT_SECRET (OAuth M2M)
    DATABRICKS_TOKEN                      (PAT)
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import random
import sys
import time
from datetime import date, datetime, timedelta

try:
    from databricks.sdk import WorkspaceClient
    from databricks.sdk.service.sql import StatementState
except ImportError:
    sys.exit("databricks-sdk が必要です: pip install 'databricks-sdk>=0.40'")

PREFECTURES = [
    "東京都", "神奈川県", "大阪府", "愛知県", "埼玉県", "千葉県", "兵庫県",
    "北海道", "福岡県", "静岡県", "広島県", "京都府", "宮城県", "新潟県", "長野県",
]
SEGMENTS = ["プレミアム", "スタンダード", "ライト", "新規"]
CHANNELS = ["店舗", "EC", "アプリ", "電話"]
CATEGORIES = ["食品", "日用品", "家電", "衣料", "書籍", "化粧品"]
SURNAMES = ["佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤"]
GIVEN = ["太郎", "花子", "一郎", "美咲", "健太", "さくら", "翔", "結衣", "大輔", "陽子"]


def gen_customers(n: int, rng: random.Random) -> list[dict]:
    rows = []
    for i in range(1, n + 1):
        signup = date(2023, 1, 1) + timedelta(days=rng.randint(0, 1000))
        rows.append({
            "customer_id": f"C{i:06d}",
            "customer_name": f"{rng.choice(SURNAMES)} {rng.choice(GIVEN)}",
            "age": rng.randint(18, 85),
            "gender": rng.choice(["M", "F", "U"]),
            "prefecture": rng.choice(PREFECTURES),
            "segment": rng.choice(SEGMENTS),
            "signup_date": signup.isoformat(),
        })
    return rows


def gen_products(n: int, rng: random.Random) -> list[dict]:
    rows = []
    for i in range(1, n + 1):
        category = rng.choice(CATEGORIES)
        rows.append({
            "product_id": f"P{i:04d}",
            "product_name": f"{category}商品{i:04d}",
            "category": category,
            "unit_price": rng.choice([280, 480, 980, 1480, 2980, 4980, 9800, 19800]),
        })
    return rows


def gen_transactions(n: int, customers: list[dict], products: list[dict],
                     rng: random.Random) -> list[dict]:
    rows = []
    base = datetime(2026, 1, 1)
    price = {p["product_id"]: p["unit_price"] for p in products}
    for i in range(1, n + 1):
        cust = rng.choice(customers)
        prod = rng.choice(products)
        qty = rng.randint(1, 5)
        ts = base + timedelta(minutes=rng.randint(0, 365 * 24 * 60))
        rows.append({
            "transaction_id": f"T{i:08d}",
            "customer_id": cust["customer_id"],
            "product_id": prod["product_id"],
            "quantity": qty,
            "amount": qty * price[prod["product_id"]],
            "channel": rng.choice(CHANNELS),
            "transaction_ts": ts.strftime("%Y-%m-%d %H:%M:%S"),
        })
    return rows


def to_csv_bytes(rows: list[dict]) -> bytes:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
    return buf.getvalue().encode("utf-8")


def run_sql(w: WorkspaceClient, warehouse_id: str, statement: str, label: str) -> None:
    """ステートメントを実行し、終了まで待つ。"""
    resp = w.statement_execution.execute_statement(
        warehouse_id=warehouse_id, statement=statement, wait_timeout="50s",
    )
    statement_id = resp.statement_id
    deadline = time.time() + 900
    while resp.status and resp.status.state in (StatementState.PENDING, StatementState.RUNNING):
        if time.time() > deadline:
            w.statement_execution.cancel_execution(statement_id)
            raise RuntimeError(f"{label}: 15分でタイムアウトしました")
        time.sleep(3)
        resp = w.statement_execution.get_statement(statement_id)

    state = resp.status.state if resp.status else None
    if state != StatementState.SUCCEEDED:
        detail = ""
        if resp.status and resp.status.error:
            detail = f": {resp.status.error.message}"
        raise RuntimeError(f"{label} が失敗しました ({state}){detail}")
    print(f"  [OK] {label}")


def scalar(w: WorkspaceClient, warehouse_id: str, statement: str):
    resp = w.statement_execution.execute_statement(
        warehouse_id=warehouse_id, statement=statement, wait_timeout="50s",
    )
    while resp.status and resp.status.state in (StatementState.PENDING, StatementState.RUNNING):
        time.sleep(2)
        resp = w.statement_execution.get_statement(resp.statement_id)
    if not resp.result or not resp.result.data_array:
        return None
    return resp.result.data_array[0][0]


TABLES = ("customers", "products", "transactions")


def main() -> int:
    ap = argparse.ArgumentParser(description="UC にサンプルデータを投入する")
    ap.add_argument("--host", default=os.environ.get("DATABRICKS_HOST"),
                    help="ワークスペースURL (既定: $DATABRICKS_HOST)")
    ap.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"),
                    help="~/.databrickscfg のプロファイル名")
    ap.add_argument("--warehouse-id", help="SQL ウェアハウスID (--dry-run 以外では必須)")
    ap.add_argument("--catalog", help="投入先カタログ (--dry-run 以外では必須)")
    ap.add_argument("--schema", default="sample")
    ap.add_argument("--volume", default="landing")
    ap.add_argument("--scale", type=float, default=1.0,
                    help="データ量の倍率 (1.0 = 顧客2000/商品60/取引50000)")
    ap.add_argument("--seed", type=int, default=42, help="乱数シード (再現性のため固定)")
    ap.add_argument("--dry-run", metavar="DIR", default=None,
                    help="ワークスペースに接続せず、生成したCSVを DIR に書き出して終了する")
    args = ap.parse_args()

    rng = random.Random(args.seed)

    if args.dry_run:
        n_cust = max(10, int(2000 * args.scale))
        n_prod = max(5, int(60 * args.scale))
        n_txn = max(50, int(50000 * args.scale))
        customers = gen_customers(n_cust, rng)
        products = gen_products(n_prod, rng)
        transactions = gen_transactions(n_txn, customers, products, rng)
        os.makedirs(args.dry_run, exist_ok=True)
        for name, rows in (("customers", customers), ("products", products),
                           ("transactions", transactions)):
            path = os.path.join(args.dry_run, f"{name}.csv")
            with open(path, "wb") as fh:
                fh.write(to_csv_bytes(rows))
            print(f"  [OK] {path} ({len(rows):,} 行)")
        print("dry-run 完了 (ワークスペースへの接続なし)")
        return 0

    if not args.warehouse_id or not args.catalog:
        ap.error("--warehouse-id と --catalog は必須です (--dry-run 時を除く)")

    kwargs = {}
    if args.profile:
        kwargs["profile"] = args.profile
    if args.host:
        kwargs["host"] = args.host
    w = WorkspaceClient(**kwargs)

    fq_schema = f"`{args.catalog}`.`{args.schema}`"
    vol_root = f"/Volumes/{args.catalog}/{args.schema}/{args.volume}"

    n_cust = max(10, int(2000 * args.scale))
    n_prod = max(5, int(60 * args.scale))
    n_txn = max(50, int(50000 * args.scale))

    print(f"1) データ生成 (顧客 {n_cust} / 商品 {n_prod} / 取引 {n_txn})")
    customers = gen_customers(n_cust, rng)
    products = gen_products(n_prod, rng)
    transactions = gen_transactions(n_txn, customers, products, rng)

    print(f"2) ボリュームへアップロード -> {vol_root}")
    for name, rows in (("customers", customers), ("products", products),
                       ("transactions", transactions)):
        payload = to_csv_bytes(rows)
        target = f"{vol_root}/{name}/{name}.csv"
        w.files.upload(target, io.BytesIO(payload), overwrite=True)
        print(f"  [OK] {target} ({len(payload):,} bytes)")

    print("3) テーブル作成")
    for name in TABLES:
        run_sql(w, args.warehouse_id, f"""
            CREATE OR REPLACE TABLE {fq_schema}.`{name}`
            AS SELECT * FROM read_files(
                '{vol_root}/{name}/',
                format    => 'csv',
                header    => true,
                inferSchema => true
            )
        """, f"table {name}")

    print("4) 集計ビュー作成")
    run_sql(w, args.warehouse_id, f"""
        CREATE OR REPLACE VIEW {fq_schema}.`daily_sales_by_prefecture`
        COMMENT '都道府県別の日次売上'
        AS
        SELECT
            date(t.transaction_ts)      AS sales_date,
            c.prefecture                AS prefecture,
            p.category                  AS category,
            count(*)                    AS transaction_count,
            sum(t.amount)               AS total_amount
        FROM {fq_schema}.`transactions` t
        JOIN {fq_schema}.`customers`    c ON t.customer_id = c.customer_id
        JOIN {fq_schema}.`products`     p ON t.product_id  = p.product_id
        GROUP BY ALL
    """, "view daily_sales_by_prefecture")

    print("5) 件数検証")
    expected = {"customers": n_cust, "products": n_prod, "transactions": n_txn}
    failures = []
    for name, want in expected.items():
        got = scalar(w, args.warehouse_id, f"SELECT count(*) FROM {fq_schema}.`{name}`")
        got = int(got) if got is not None else -1
        mark = "OK" if got == want else "NG"
        print(f"  [{mark}] {name}: {got:,} 行 (期待 {want:,})")
        if got != want:
            failures.append(name)

    view_rows = scalar(w, args.warehouse_id,
                       f"SELECT count(*) FROM {fq_schema}.`daily_sales_by_prefecture`")
    print(f"  [OK] daily_sales_by_prefecture: {int(view_rows):,} 行")

    if failures:
        print(f"\n件数が一致しないテーブルがあります: {', '.join(failures)}", file=sys.stderr)
        return 1

    print(f"\n完了: {args.catalog}.{args.schema} に 3テーブル + 1ビュー")
    return 0


if __name__ == "__main__":
    sys.exit(main())
