import os
import json
from pathlib import Path
import requests

NOTION_API_KEY = os.environ["NOTION_API_KEY"]
NOTION_DATABASE_ID = os.environ["NOTION_MAINTENANCE_DB_ID"]
REPORT_JSON = Path(os.environ["REPORT_JSON"])

# Notion requires a Notion-Version header (pick a fixed one for now).
# You can change it later; Notion API is versioned.  :contentReference[oaicite:5]{index=5}
NOTION_VERSION = os.environ.get("NOTION_VERSION", "2022-06-28")

data = json.loads(REPORT_JSON.read_text(encoding="utf-8"))

task = data.get("task", "unknown")
mode = data.get("mode", "unknown")
date_local = data.get("date_local", "")
host = data.get("host", "")
exit_code = int(data.get("exit_code", 1))
status = "OK" if exit_code == 0 else "KO"

title = f"{task} ({mode}) — {date_local}"

# Optional paths (depending on your repo strategy)
log_path = data.get("log_path", "")
json_path = str(REPORT_JSON)
md_path = data.get("notion_md_path", "")  # we'll set it from bash

headers = {
    "Authorization": f"Bearer {NOTION_API_KEY}",
    "Notion-Version": NOTION_VERSION,
    "Content-Type": "application/json",
}

payload = {
    "parent": {"database_id": NOTION_DATABASE_ID},
    "properties": {
        "Name": {"title": [{"text": {"content": title}}]},
        "Task": {"select": {"name": task}},
        "Mode": {"select": {"name": mode}},
        "Status": {"select": {"name": status}},
        "Date": {"date": {"start": date_local}} if date_local else {"date": None},
        "Host": {"rich_text": [{"text": {"content": host}}]},
        "Exit code": {"number": exit_code},
        "Ops Run ID": {"rich_text": [{"text": {"content": REPORT_JSON.stem}}]},
        "JSON path": {"rich_text": [{"text": {"content": json_path}}]},
        "MD path": {"rich_text": [{"text": {"content": md_path}}]},
        "Log path": {"rich_text": [{"text": {"content": log_path}}]},
    },
}

resp = requests.post("https://api.notion.com/v1/pages", headers=headers, json=payload, timeout=20)
resp.raise_for_status()
print(resp.json().get("id", "created"))
