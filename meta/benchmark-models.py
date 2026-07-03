#!/usr/bin/env python3
"""
RD-MODELS benchmark — fit coût/perf avec lmfit.
Alimente harness/manifests/model-landscape.json.

Usage:
  pip install lmfit
  python ops-tools/meta/benchmark-models.py
  python ops-tools/meta/benchmark-models.py --input data/benchmark-samples.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from lmfit.models import LinearModel
except ImportError:
    raise SystemExit("Install lmfit: pip install lmfit")

WORKSPACES = Path(__file__).resolve().parents[2]
LANDSCAPE = WORKSPACES / "harness" / "manifests" / "model-landscape.json"
DEFAULT_SAMPLES = WORKSPACES / "ops-tools" / "meta" / "data" / "benchmark-samples.json"


def load_samples(path: Path) -> list[dict]:
    if not path.exists():
        return [
            {"vendor": "deepseek-v3", "tokens_m": 1, "cost_usd": 0.14, "score": 82},
            {"vendor": "deepseek-v3", "tokens_m": 5, "cost_usd": 0.70, "score": 84},
            {"vendor": "qwen-2.5-14b", "tokens_m": 1, "cost_usd": 0.12, "score": 80},
            {"vendor": "qwen-2.5-14b", "tokens_m": 5, "cost_usd": 0.58, "score": 81},
            {"vendor": "glm-4-flash", "tokens_m": 1, "cost_usd": 0.10, "score": 78},
            {"vendor": "glm-4-flash", "tokens_m": 5, "cost_usd": 0.48, "score": 79},
            {"vendor": "claude-haiku-4-5", "tokens_m": 1, "cost_usd": 0.80, "score": 88},
            {"vendor": "claude-haiku-4-5", "tokens_m": 5, "cost_usd": 3.50, "score": 89},
        ]
    return json.loads(path.read_text(encoding="utf-8"))


def fit_cost_per_million(samples: list[dict]) -> dict:
    """Linear fit: cost_usd = a * tokens_m + b per vendor aggregate."""
    tokens = [s["tokens_m"] for s in samples]
    costs = [s["cost_usd"] for s in samples]
    model = LinearModel(prefix="cost_")
    params = model.guess(data=costs, x=tokens)
    result = model.fit(costs, params, x=tokens)
    return {
        "slope_usd_per_m": float(result.params["cost_slope"].value),
        "intercept_usd": float(result.params["cost_intercept"].value),
        "r_squared": float(result.rsquared),
        "stderr_slope": float(result.params["cost_slope"].stderr or 0),
    }


def score_per_dollar(samples: list[dict]) -> list[dict]:
    ranked = []
    for s in samples:
        spd = s["score"] / s["cost_usd"] if s["cost_usd"] > 0 else 0
        ranked.append({**s, "score_per_dollar": round(spd, 2)})
    return sorted(ranked, key=lambda x: x["score_per_dollar"], reverse=True)


def update_landscape(fit: dict, ranking: list[dict]) -> None:
    if not LANDSCAPE.exists():
        print(f"Skip landscape update — not found: {LANDSCAPE}")
        return
    data = json.loads(LANDSCAPE.read_text(encoding="utf-8"))
    data["last_benchmark"] = {
        "cost_fit": fit,
        "ranking_score_per_dollar": ranking[:5],
    }
    data["updated"] = __import__("datetime").date.today().isoformat()
    LANDSCAPE.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Updated {LANDSCAPE}")


def main() -> None:
    parser = argparse.ArgumentParser(description="RD-MODELS lmfit benchmark")
    parser.add_argument("--input", type=Path, default=DEFAULT_SAMPLES)
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args()

    samples = load_samples(args.input)
    fit = fit_cost_per_million(samples)
    ranking = score_per_dollar(samples)

    print("=== Cost fit (linear) ===")
    print(json.dumps(fit, indent=2))
    print("\n=== Ranking score/$ ===")
    for r in ranking:
        print(f"  {r['vendor']:20s}  score/$={r['score_per_dollar']:6.1f}  score={r['score']}  cost=${r['cost_usd']}")

    best_execution = [r for r in ranking if "claude" not in r["vendor"].lower()][:3]
    print("\n=== Recommandation exécution (hors US) ===")
    for r in best_execution:
        print(f"  -> {r['vendor']}")

    if not args.no_write:
        update_landscape(fit, ranking)


if __name__ == "__main__":
    main()
