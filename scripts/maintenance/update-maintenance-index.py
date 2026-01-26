import json
from pathlib import Path
from datetime import datetime

OPS_ROOT = Path(__file__).resolve().parents[2]
REPORTS_DIR = OPS_ROOT / "reports"
INDEX_PATH = OPS_ROOT / "docs" / "notion" / "pages" / "maintenance-index.md"

def load_reports():
    items = []
    for p in sorted(REPORTS_DIR.glob("*.json"), reverse=True):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        # expected keys
        task = data.get("task", "unknown")
        mode = data.get("mode", "unknown")
        date_local = data.get("date_local", "")
        exit_code = data.get("exit_code", None)
        status = "OK" if exit_code == 0 else f"KO (exit={exit_code})"

        # derive MD path if present by convention
        stamp = p.stem.split("_", 1)[-1]  # normalize-eol_2026...
        md = OPS_ROOT / "docs" / "notion" / "exports" / f"{task}_{stamp}.md"
        log = Path(data.get("log_path", ""))
        items.append({
            "date_local": date_local,
            "task": task,
            "mode": mode,
            "status": status,
            "md": md if md.exists() else None,
            "json": p,
            "log": log if log.exists() else None,
        })
    return items

def render(items):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = []
    lines.append("# Maintenance — Index des runs")
    lines.append("")
    lines.append(f"_Généré automatiquement. Dernière mise à jour : {now}_")
    lines.append("")
    lines.append("## Derniers runs")
    lines.append("")
    lines.append("| Date | Tâche | Mode | Statut | Export Notion | JSON | Log |")
    lines.append("|---|---|---|---|---|---|---|")

    for it in items[:50]:
        md = str(it["md"].relative_to(OPS_ROOT)) if it["md"] else ""
        js = str(it["json"].relative_to(OPS_ROOT)) if it["json"] else ""
        lg = str(it["log"]) if it["log"] else ""
        date = it["date_local"]
        lines.append(f"| {date} | {it['task']} | {it['mode']} | {it['status']} | {md} | {js} | {lg} |")

    lines.append("")
    lines.append("## Notes")
    lines.append("- Les chemins sont relatifs au repo `ops-tools`.")
    lines.append("- Les logs peuvent être ignorés par Git selon la stratégie choisie.")
    lines.append("")
    return "\n".join(lines)

def main():
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    items = load_reports()
    INDEX_PATH.write_text(render(items), encoding="utf-8")

if __name__ == "__main__":
    main()
