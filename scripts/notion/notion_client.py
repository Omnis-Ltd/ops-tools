from __future__ import annotations

import os
import requests
from typing import Any, Dict, List, Optional

NOTION_API_BASE = "https://api.notion.com/v1"
NOTION_VERSION = os.environ.get("NOTION_VERSION", "2022-06-28")


def normalize_notion_id(raw: str) -> str:
    s = raw.strip().replace("-", "")
    if len(s) == 32:
        return f"{s[0:8]}-{s[8:12]}-{s[12:16]}-{s[16:20]}-{s[20:32]}"
    return raw


class NotionClient:
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.environ.get("NOTION_API_KEY")
        if not self.api_key:
            raise RuntimeError("NOTION_API_KEY is not set")

        self.headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        }

    def _get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        r = requests.get(f"{NOTION_API_BASE}{path}", headers=self.headers, params=params, timeout=30)
        r.raise_for_status()
        return r.json()

    def _post(self, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        r = requests.post(f"{NOTION_API_BASE}{path}", headers=self.headers, json=payload, timeout=30)
        r.raise_for_status()
        return r.json()

    def retrieve_page(self, page_id: str) -> Dict[str, Any]:
        return self._get(f"/pages/{normalize_notion_id(page_id)}")

    def query_database(self, database_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self._post(f"/databases/{normalize_notion_id(database_id)}/query", payload)

    def query_database_all(self, database_id: str, payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Collect all pages from a DB query with pagination."""
        results: List[Dict[str, Any]] = []
        start_cursor: Optional[str] = None

        while True:
            p = dict(payload)
            if start_cursor:
                p["start_cursor"] = start_cursor

            data = self.query_database(database_id, p)
            results.extend(data.get("results") or [])

            if not data.get("has_more"):
                break
            start_cursor = data.get("next_cursor")

        return results

    def create_page(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self._post("/pages", payload)

