#!/usr/bin/env python3
"""期限切れ環境を Terraform で自動削除する (reaper)。

envs/*/manifest.json の expires_at を見て、期限を過ぎた環境に対して
`terraform destroy` を実行する。state 経由で消すので、ワークスペース・ユーザー・
グループ・カタログ (サンプルデータ込み) が漏れなく消える。

既定はドライラン。実際に消すには --yes を付ける。

    python3 scripts/reap.py                  # 一覧と判定のみ
    python3 scripts/reap.py --yes            # 期限切れを destroy
    python3 scripts/reap.py --env foo --yes  # 特定環境のみ
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REQUIRED_TF_VARS = (
    "TF_VAR_databricks_account_id",
    "TF_VAR_databricks_client_id",
    "TF_VAR_databricks_client_secret",
)


def parse_rfc3339(value: str) -> datetime:
    # Terraform の timeadd は "2026-10-28T12:00:00Z" 形式を返す
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_manifests(env_filter: str | None) -> list[dict]:
    out = []
    for path in sorted((REPO_ROOT / "envs").glob("*/manifest.json")):
        env_name = path.parent.name
        if env_filter and env_name != env_filter:
            continue
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError) as exc:
            print(f"[WARN] {path} を読めません: {exc}", file=sys.stderr)
            continue
        data["_path"] = path
        data["_env_dir"] = path.parent
        data.setdefault("env_name", env_name)
        out.append(data)
    return out


def terraform(args: list[str], extra_env: dict | None = None) -> int:
    cmd = ["terraform", "-chdir=stack", *args]
    print(f"  $ {' '.join(cmd)}")
    env = {**os.environ, **(extra_env or {})}
    return subprocess.call(cmd, cwd=REPO_ROOT, env=env)


def destroy(env_name: str, backend_config: str | None) -> bool:
    state_path = f"../envs/{env_name}/terraform.tfstate"
    init_args = ["init", "-reconfigure", "-input=false"]
    if backend_config:
        init_args.append(f"-backend-config={backend_config}")
    else:
        init_args.append(f"-backend-config=path={state_path}")

    if terraform(init_args) != 0:
        print(f"[NG] {env_name}: terraform init が失敗しました", file=sys.stderr)
        return False

    rc = terraform([
        "destroy", "-auto-approve", "-input=false",
        f"-var-file=../envs/{env_name}/terraform.tfvars",
    ])
    if rc != 0:
        print(f"[NG] {env_name}: terraform destroy が失敗しました", file=sys.stderr)
        return False

    print(f"[OK] {env_name}: 削除しました")
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description="期限切れ環境を自動削除する")
    ap.add_argument("--yes", action="store_true", help="実際に destroy する (既定はドライラン)")
    ap.add_argument("--env", default=None, help="対象環境を1つに絞る")
    ap.add_argument("--grace-hours", type=float, default=0.0,
                    help="期限からさらに猶予を取る時間")
    ap.add_argument("--backend-config", default=None,
                    help="S3 backend 等を使う場合の -backend-config の値")
    args = ap.parse_args()

    manifests = load_manifests(args.env)
    if not manifests:
        print("対象の manifest.json が見つかりません (まだ apply していない環境のみ)")
        return 0

    now = datetime.now(timezone.utc)
    expired, alive = [], []

    print(f"{'ENV':24} {'EXPIRES_AT':22} {'残り':>12}  WORKSPACE")
    print("-" * 96)
    for m in manifests:
        raw = m.get("expires_at")
        try:
            exp = parse_rfc3339(raw)
        except (TypeError, ValueError):
            print(f"{m['env_name']:24} {'(expires_at 不正)':22} {'?':>12}  {m.get('workspace_url', '')}")
            continue
        remaining = exp - now
        hours = remaining.total_seconds() / 3600
        label = f"{hours:+.1f}h" if abs(hours) < 48 else f"{hours / 24:+.1f}d"
        print(f"{m['env_name']:24} {raw:22} {label:>12}  {m.get('workspace_url', '')}")
        if hours + args.grace_hours <= 0:
            expired.append(m)
        else:
            alive.append(m)

    print("-" * 96)
    print(f"期限切れ: {len(expired)} / 有効: {len(alive)}")

    if not expired:
        return 0

    if not args.yes:
        print("\nドライランです。削除するには --yes を付けてください。")
        print("削除対象: " + ", ".join(m["env_name"] for m in expired))
        return 0

    missing = [v for v in REQUIRED_TF_VARS if not os.environ.get(v)]
    if missing:
        print(f"\n環境変数が未設定です: {', '.join(missing)}", file=sys.stderr)
        return 2

    failed = []
    for m in expired:
        print(f"\n=== destroy {m['env_name']} ===")
        if not destroy(m["env_name"], args.backend_config):
            failed.append(m["env_name"])

    if failed:
        print(f"\n削除に失敗した環境: {', '.join(failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
