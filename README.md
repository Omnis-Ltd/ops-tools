# ops-tools

IT Maintenance & Ops — scripts, workflows, and automation for managing multiple repositories.

---

## Quickstart

### Prerequisites

| Environment | Requirement |
|-------------|-------------|
| **Windows** | Git Bash (MINGW64) or WSL2 |
| **Python**  | Python 3.8+ accessible via `python` or set `PYTHON_BIN` |
| **Make**    | GNU Make (comes with Git Bash) |

```bash
# Clone
git clone https://github.com/<your-org>/ops-tools.git
cd ops-tools

# Verify
make help
```

### Environment variables (optional)

```bash
export WORKSPACES_ROOT="$HOME/git/Workspaces"   # default
export PYTHON_BIN=python                         # or python3
```

---

## Commands

### Make targets

| Target                          | Description |
|---------------------------------|-------------|
| `make help`                     | Show available targets |
| `make repo-health`              | Quick diagnostic of all repos under `WORKSPACES_ROOT` |
| `make normalize-eol-dry`        | Dry-run: list repos needing LF normalization |
| `make normalize-eol-apply`      | Apply `.gitattributes`, renormalize, commit (skips dirty repos) |
| `make maintenance-normalize-eol-dry`   | Full maintenance run (dry) with logs/reports |
| `make maintenance-normalize-eol-apply` | Full maintenance run (apply) with logs/reports/Notion push |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/maintenance/repo-health.sh` | List repos, branch, dirty status |
| `scripts/maintenance/normalize-eol-batch.sh` | Core EOL normalization logic |
| `scripts/maintenance/run-maintenance.sh` | Orchestrator: logs, JSON reports, Notion MD export |
| `scripts/maintenance/update-maintenance-index.py` | Update maintenance run index |
| `scripts/notion/push_report_to_db.py` | Push maintenance report to Notion database |

---

## Notion Integration

### Required environment variables

| Variable | Description |
|----------|-------------|
| `NOTION_API_KEY` | Notion integration token (secret) |
| `NOTION_MAINTENANCE_DB_ID` | Database ID for maintenance reports |
| `NOTION_BACKLOG_DB_ID` | Database ID for backlog items (optional) |

### Page IDs (for direct page updates)

Configure in your `.env` or export before running:

```bash
export NOTION_API_KEY="secret_..."
export NOTION_MAINTENANCE_DB_ID="..."
export NOTION_BACKLOG_DB_ID="..."
```

### Notion database schema (Maintenance)

| Property | Type | Example |
|----------|------|---------|
| Name | Title | `normalize-eol (apply) — 2026-01-26 14:30:00` |
| Task | Select | `normalize-eol` |
| Mode | Select | `dry` / `apply` |
| Status | Select | `OK` / `KO` |
| Date | Date | ISO date |
| Host | Text | hostname |
| Exit code | Number | 0 |
| Ops Run ID | Text | `normalize-eol_20260126T143000Z` |

---

## Maintenance Workflow

Standard flow: **dry → review → apply → push to Notion DB**

```
┌─────────────────────────────────────────────────────────────────┐
│  1. DRY-RUN                                                     │
│     make maintenance-normalize-eol-dry                          │
│     → logs/maintenance/<task>_<timestamp>.log                   │
│     → reports/<task>_<timestamp>.json                           │
│     → docs/notion/exports/<task>_<timestamp>.md                 │
├─────────────────────────────────────────────────────────────────┤
│  2. REVIEW                                                      │
│     - Check the generated log and JSON report                   │
│     - Verify which repos will be affected                       │
├─────────────────────────────────────────────────────────────────┤
│  3. APPLY                                                       │
│     make maintenance-normalize-eol-apply                        │
│     → Same outputs + actual commits in clean repos              │
├─────────────────────────────────────────────────────────────────┤
│  4. PUSH TO NOTION (automatic if env vars set)                  │
│     If NOTION_API_KEY and NOTION_MAINTENANCE_DB_ID are set,     │
│     the report is pushed to your Notion database.               │
└─────────────────────────────────────────────────────────────────┘
```

### Output structure

```
ops-tools/
├── logs/maintenance/          # Raw logs per run
├── reports/                   # JSON reports per run
└── docs/notion/exports/       # Markdown exports for Notion
```

---

## Claude Commands

Custom Claude Code commands in `.claude/commands/`:

| Command | Description |
|---------|-------------|
| `/maintenance-normalize-eol-dry` | Run dry-run maintenance |
| `/maintenance-normalize-eol-apply` | Run apply maintenance |
| `/prepush-readme` | Prepare push: update README, check secrets |

---

## Security

- **Never commit secrets** — `.env` files are gitignored
- **Check before push**: `git grep -nE "(NOTION_API_KEY=|Bearer |sk-|api[_-]?key|token)"`
- Store sensitive values in environment variables only

---

## License

MIT
