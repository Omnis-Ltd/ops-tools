from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from scripts.notion.notion_client import NotionClient, normalize_notion_id
from scripts.notion.utils import normalize_relpath

CACHE_PATH = Path(".cache/notion/repos_map.json").resolve()


def _load_repo_map() -> Dict[str, Any]:
    if not CACHE_PATH.exists():
        raise RuntimeError(
            f"Repo map cache not found: {CACHE_PATH}. "
            "Rebuild it: python -m scripts.notion.build_repos_map"
        )
    return json.loads(CACHE_PATH.read_text(encoding="utf-8"))


def _relpath(path_str: str, ops_root: Path) -> str:
    if not path_str:
        return ""
    p = Path(path_str)
    try:
        return str(p.resolve().relative_to(ops_root.resolve()))
    except Exception:
        return str(p)


def _pick_report_repos(report: Dict[str, Any]) -> List[str]:
    repos = report.get("repos")
    if isinstance(repos, list):
        return [str(x).strip() for x in repos if str(x).strip()]
    return []


def _status_from_exit_code(exit_code: Optional[int]) -> str:
    if exit_code is None:
        return "Pending..."
    return "Passed" if int(exit_code) == 0 else "Failed"


def _title_nom(task: str, repo: str, mode: str, status: str) -> str:
    return f"{task} — {repo} — {mode} — {status}"


def _resolve_repo_page_id(repo_map: Dict[str, Any], repo_key: str) -> Optional[str]:
    """
    Resolve repo_key against cache.

    Supports:
      - new format: {"by_slug": {...}, "by_relpath": {...}}
      - old format: flat {"contracts": "page_id", ...}
    """
    # normalize: handle "\" vs "/" etc. for relpaths
    repo_key_norm = normalize_relpath(repo_key)

    if isinstance(repo_map, dict) and "by_slug" in repo_map:
        by_slug = repo_map.get("by_slug", {}) or {}
        by_relpath = repo_map.get("by_relpath", {}) or {}

        # Try exact slug first (slugs shouldn't be path-like, but harmless)
        return by_slug.get(repo_key) or by_slug.get(repo_key_norm) or by_relpath.get(repo_key_norm)

    # old flat cache
    if isinstance(repo_map, dict):
        return repo_map.get(repo_key) or repo_map.get(repo_key_norm)

    return None


def main() -> None:
    maint_db_id = os.environ.get("NOTION_MAINTENANCE_DB_ID")
    if not maint_db_id:
        raise RuntimeError("NOTION_MAINTENANCE_DB_ID is not set")

    ops_root = Path(os.environ.get("OPS_ROOT", str(Path.cwd()))).resolve()

    report_path = os.environ.get("REPORT_JSON") or (os.sys.argv[1] if len(os.sys.argv) > 1 else "")
    if not report_path:
        raise RuntimeError(
            "Usage: REPORT_JSON=path/to/report.json python -m scripts.notion.push_maintenance  "
            "OR pass path as argv"
        )

    report = json.loads(Path(report_path).read_text(encoding="utf-8"))

    task = str(report.get("task") or "").strip() or "unknown-task"
    mode = str(report.get("mode") or "").strip() or "unknown-mode"
    host = str(report.get("host") or "").strip()
    exit_code = report.get("exit_code")
    status = _status_from_exit_code(exit_code)

    date_iso = str(report.get("date_utc") or report.get("date_local") or "").strip()
    json_path = _relpath(str(report.get("json_path") or ""), ops_root)
    md_path = _relpath(str(report.get("md_path") or ""), ops_root)
    log_path = _relpath(str(report.get("log_path") or ""), ops_root)
    ops_run_id = str(
        report.get("ops_run_id")
        or report.get("ops_run_id_git")
        or report.get("ops_run_id (git)")
        or ""
    ).strip()

    repos = _pick_report_repos(report)
    if not repos:
        raise RuntimeError(
            "Report does not contain 'repos' list. "
            "Design 2 requires report['repos'] = [repo_slug_or_relpath,...]."
        )

    repo_map = _load_repo_map()
    client = NotionClient()

    created = 0
    for repo in repos:
        repo_page_id = _resolve_repo_page_id(repo_map, repo)
        if not repo_page_id:
            # out-of-scope repo (tests, vendor, external). Keep run local, skip Notion entry.
            print(f"Skip out-of-scope repo: {repo}")
            continue
        
        nom = _title_nom(task, repo, mode, status)

        props: Dict[str, Any] = {
            "Nom": {"title": [{"type": "text", "text": {"content": nom}}]},
            "Host": {"rich_text": [{"type": "text", "text": {"content": host}}]} if host else {"rich_text": []},
            "Task": {"select": {"name": task}},
            "Mode": {"select": {"name": mode}},
            "État": {"status": {"name": status}},
            "Exit code": {"number": float(exit_code) if exit_code is not None else None},
            "Ops Run ID (git)": {"rich_text": [{"type": "text", "text": {"content": ops_run_id}}]} if ops_run_id else {"rich_text": []},
            "JSON path": {"rich_text": [{"type": "text", "text": {"content": json_path}}]} if json_path else {"rich_text": []},
            "MD path": {"rich_text": [{"type": "text", "text": {"content": md_path}}]} if md_path else {"rich_text": []},
            "Log path": {"rich_text": [{"type": "text", "text": {"content": log_path}}]} if log_path else {"rich_text": []},
            "Repo(s)": {"relation": [{"id": normalize_notion_id(repo_page_id)}]},
        }

        if date_iso:
            props["Date"] = {"date": {"start": date_iso}}

        payload = {
            "parent": {"database_id": normalize_notion_id(maint_db_id)},
            "properties": props,
        }

        client.create_page(payload)
        created += 1

    print(f"Created {created} Maintenance entries (Design 2).")


if __name__ == "__main__":
    main()