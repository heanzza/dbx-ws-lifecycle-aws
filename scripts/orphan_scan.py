#!/usr/bin/env python3
"""Terraform state から外れた "みなしご" 環境を洗い出す。

state を失った/手で消した等で reaper が効かなくなった場合の保険。
アカウント内のワークスペースを custom_tags の managed_by = dbx-ws-lifecycle で絞り、
expires_at を過ぎているものを報告する。

    python3 scripts/orphan_scan.py                   # 報告のみ
    python3 scripts/orphan_scan.py --delete          # ワークスペースとグループを削除
    python3 scripts/orphan_scan.py --delete --delete-users  # ユーザーも削除

認証は環境変数で渡す:
    DATABRICKS_ACCOUNT_ID / DATABRICKS_CLIENT_ID / DATABRICKS_CLIENT_SECRET
    (TF_VAR_* しか無い場合はそれも読む)
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone

try:
    from databricks.sdk import AccountClient
except ImportError:
    sys.exit("databricks-sdk が必要です: pip install 'databricks-sdk>=0.40'")

MANAGED_BY = "dbx-ws-lifecycle"


def parse_rfc3339(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def main() -> int:
    ap = argparse.ArgumentParser(description="state 外の期限切れ環境を洗い出す")
    ap.add_argument("--delete", action="store_true",
                    help="期限切れワークスペースと <env>-users / <env>-admins グループを削除する")
    ap.add_argument("--delete-users", action="store_true",
                    help="--delete と併用。グループに属していたユーザーもアカウントから削除する")
    ap.add_argument("--host", default=os.environ.get("DATABRICKS_ACCOUNT_HOST",
                                                     "https://accounts.cloud.databricks.com"))
    args = ap.parse_args()

    account_id = os.environ.get("DATABRICKS_ACCOUNT_ID") or os.environ.get("TF_VAR_databricks_account_id")
    client_id = os.environ.get("DATABRICKS_CLIENT_ID") or os.environ.get("TF_VAR_databricks_client_id")
    client_secret = os.environ.get("DATABRICKS_CLIENT_SECRET") or os.environ.get("TF_VAR_databricks_client_secret")

    missing = [n for n, v in (("DATABRICKS_ACCOUNT_ID", account_id),
                              ("DATABRICKS_CLIENT_ID", client_id),
                              ("DATABRICKS_CLIENT_SECRET", client_secret)) if not v]
    if missing:
        print(f"環境変数が未設定です: {', '.join(missing)}", file=sys.stderr)
        return 2

    a = AccountClient(host=args.host, account_id=account_id,
                      client_id=client_id, client_secret=client_secret)

    now = datetime.now(timezone.utc)
    managed, expired = [], []

    for ws in a.workspaces.list():
        tags = ws.custom_tags or {}
        if tags.get("managed_by") != MANAGED_BY:
            continue
        managed.append(ws)
        raw = tags.get("expires_at")
        try:
            is_expired = raw is not None and parse_rfc3339(raw) <= now
        except ValueError:
            is_expired = False
        status = "EXPIRED" if is_expired else "alive"
        print(f"[{status:7}] {ws.workspace_name:30} id={ws.workspace_id} "
              f"env={tags.get('env', '?')} expires_at={raw} owner={tags.get('owner', '?')}")
        if is_expired:
            expired.append((ws, tags))

    print(f"\n{MANAGED_BY} 管理のワークスペース: {len(managed)} / うち期限切れ: {len(expired)}")

    if not expired:
        return 0
    if not args.delete:
        print("削除するには --delete を付けてください。")
        print("注意: Terraform state が残っている環境は scripts/reap.py で消すこと "
              "(こちらで消すと state が不整合になります)")
        return 0

    groups_by_name = {g.display_name: g for g in a.groups.list()}
    rc = 0

    for ws, tags in expired:
        env = tags.get("env")
        print(f"\n=== 削除 {ws.workspace_name} (id={ws.workspace_id}) ===")
        try:
            a.workspaces.delete(workspace_id=ws.workspace_id)
            print("  [OK] ワークスペース削除")
        except Exception as exc:  # noqa: BLE001 - 1件の失敗で止めない
            print(f"  [NG] ワークスペース削除に失敗: {exc}", file=sys.stderr)
            rc = 1
            continue

        if not env:
            print("  [--] env タグが無いためグループは手動確認してください")
            continue

        for suffix in ("users", "admins"):
            name = f"{env}-{suffix}"
            group = groups_by_name.get(name)
            if not group:
                continue
            member_ids = [m.value for m in (group.members or [])]
            try:
                a.groups.delete(id=group.id)
                print(f"  [OK] グループ削除 {name}")
            except Exception as exc:  # noqa: BLE001
                print(f"  [NG] グループ削除に失敗 {name}: {exc}", file=sys.stderr)
                rc = 1
                continue

            if args.delete_users:
                for uid in member_ids:
                    try:
                        a.users.delete(id=uid)
                        print(f"    [OK] ユーザー削除 id={uid}")
                    except Exception as exc:  # noqa: BLE001
                        print(f"    [NG] ユーザー削除に失敗 id={uid}: {exc}", file=sys.stderr)
                        rc = 1

    return rc


if __name__ == "__main__":
    sys.exit(main())
