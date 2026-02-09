from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, Any

from scripts.notion.utils import normalize_relpath
from scripts.notion.notion_client import NotionClient

CACHE_DIR = Path(".cache/notion").resolve()
CACHE_PATH = CACHE_DIR / "repos_map.json"


def _extract_title_slug(page: Dict[str, Any]) -> str:
    props = page.get("properties") or {}

    # Title property in your Repos DB is "Slug" (type=title)
    p = props.get("Slug")
    if p and p.get("type") == "title":
        items = p.get("title") or []
        return "".join(x.get("plain_text", "") for x in items).strip()

    # fallback: first title property
    for _name, prop in props.items():
        if prop.get("type") == "title":
            items = prop.get("title") or []
            return "".join(x.get("plain_text", "") for x in items).strip()

    return ""


def _extract_relative_path(page: Dict[str, Any]) -> str:
    """
    Extract Repos DB property 'Relative Path' (Text / Rich text).
    """
    props = page.get("properties") or {}
    p = props.get("Relative Path")

    if not p:
        return ""

    ptype = p.get("type")

    # Most Notion text props come as rich_text
    if ptype == "rich_text":
        items = p.get("rich_text") or []
        rel = "".join(x.get("plain_text", "") for x in items).strip()
        return rel

    # Some wrappers/tooling may expose as text
    if ptype == "text":
        items = p.get("text") or []
        rel = "".join(x.get("plain_text", "") for x in items).strip()
        return rel

    return ""


def main() -> None:
    repos_db_id = os.environ.get("NOTION_REPOS_DB_ID")
    if not repos_db_id:
        raise RuntimeError("NOTION_REPOS_DB_ID is not set")

    client = NotionClient()

    pages = client.query_database_all(
        repos_db_id,
        {
            "page_size": 100,
            "sorts": [{"timestamp": "last_edited_time", "direction": "descending"}],
        },
    )

    by_slug: Dict[str, str] = {}
    by_relpath: Dict[str, str] = {}

    for pg in pages:
        page_id = pg.get("id")
        if not page_id:
            continue

        slug = _extract_title_slug(pg).strip()
        if slug:
            by_slug[slug] = page_id

        rel = _extract_relative_path(pg).strip()
        rel = normalize_relpath(rel)
        if rel:
            by_relpath[rel] = page_id

    payload = {"by_slug": by_slug, "by_relpath": by_relpath}

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Wrote {CACHE_PATH} ({len(by_slug)} repos, {len(by_relpath)} relpaths)")


if __name__ == "__main__":
    main()
