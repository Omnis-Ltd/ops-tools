# ops-tools

IT Maintenance & Ops : scripts, workflows, and automation for managing multiple repositories.

---

his repository contains reusable, non-destructive-by-default tools to:
- run maintenance tasks across multiple repositories,
- produce auditable reports (JSON / Markdown),
- publish maintenance results into Notion databases,
- serve as the operational backbone for higher-level orchestration (e.g. personal-tech-board).

This repo is designed to be:
- safe by default (dry-run first),
- traceable (logs, reports, Notion),
- automation-ready (Claude, cron, n8n).

---

## Scope

`ops-tools` focuses on execution, not planning.

It does not:
- decide priorities,
- manage backlog items,
- generate executive summaries.

---

## Repository structure

```
ops-tools/
├── scripts/
│   ├── maintenance/
│   ├── notion/
│   └── ops/
├── routines/
├── runbooks/
├── docs/
│   └── notion/
│       ├── templates/
│       ├── exports/
│       └── pages/
├── logs/
│   └── maintenance/
├── reports/
├── .claude/
│   └── commands/
└── README.md
```
---

## Core concepts

### Maintenance lifecycle
1. Dry-run
2. Apply (explicit)
3. Report (JSON + Markdown)
4. Publish to Notion (optional, non-blocking)

### Routines
Declarative YAML files describing maintenance intent.

### Notion integration
Used as an audit log and navigation layer, never as a source of truth.

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
export REPOS_ROOT=~/git/Workspaces
export OPS_TOOLS_PATH=~/git/Workspaces/ops-tools
export NOTION_API_KEY=secret_...
export NOTION_MAINTENANCE_DB_ID=...
export NOTION_REPOS_DB_ID=...
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
Refresh repos cache:
```
python scripts/notion/build_repos_map.py

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

## ops doctor

Preflight check unique pour l'ecosysteme (infra VPS/Docker, statut MCP, completude .env, avancement backlogs).

### Deux canaux de distribution

| Canal | Usage | Prerequis | Commande |
|---|---|---|---|
| **Binaire compile** | Usage interne quotidien | Aucun (binaire autonome) | `make doctor` |
| **Package npm** | Ecosysteme JS externe | [Bun](https://bun.sh) installe sur la machine | `npm install -g @fdiene/ops-tools` puis `fadel-ops` |

Le canal npm ne remplace pas le binaire compile : le shim genere par npm invoque `bun` directement au runtime (`bun` n'est pas une dependance npm resolue automatiquement). Sans `bun` installe, `fadel-ops` installe via npm ne demarre pas.

### Configuration

Les deux canaux lisent `fadel-os.config.json` a la racine du monorepo cible, localisee via la variable d'environnement `WORKSPACES_ROOT` (repli : `~/git/Workspaces`).

## Release (processus manuel)

1. Mettre a jour `CHANGELOG.md` : nouvelle section `## [X.Y.Z] - AAAA-MM-JJ` avec les changements notables.
2. Mettre a jour `"version"` dans `package.json` (semver manuel : patch/minor/major selon le changement).
3. `npm pack` et inspecter le contenu du tarball genere (voir section Security ci-dessous pour la liste exacte attendue).
4. `git commit` du bump de version + changelog, `git tag vX.Y.Z` (tag local, aucun workflow CI ne s'y declenche).
5. `npm publish --access public`.

---

## Security

- **Never commit secrets** : `.env` files are gitignored (`.env`, `.env.*`, `*.env`, minus explicit allowlist entries in `.gitignore`)
- **CI gitleaks scan** : `.github/workflows/gitleaks.yml` runs `gitleaks detect` (history + working tree) on every push/PR to `main`, pinned to v8.30.1 for reproducibility
- **Check before push**: `git grep -nE "(NOTION_API_KEY=|Bearer |sk-|api[_-]?key|token)"`
- Store sensitive values in environment variables only

---

## Design principles
- Explicit over implicit
- Dry-run first
- Non-blocking integrations
- Git is the source of truth
- Notion is a projection

## License

MIT
