# BACKLOG META — Infrastructure & Harness Cross-Projet

Backlog transverse à tous les projets (SEOmnix, FluxGuard, Hermes, OpenClaw).

**Backlog d'exécution priorisé :** [`harness/BACKLOG.md`](../harness/BACKLOG.md) ← source de vérité sprint  
**Règles agent :** [`harness/RULES.md`](../harness/RULES.md)

Dernière mise à jour : 2026-08-23

---

## Sprint S1 — Mise en service harness (juillet 2026)

| P | ID | Statut | Action |
|---|---|---|---|
| **P0** | MCP-2 | 🔄 | `generate-mcp-from-env.ps1` OK — redémarrer Cursor |
| **P0** | PATH-1 | ✅ | Paths n8n = `AI_agents/seomnix/` (post DA-1) |
| **P0** | TOOLS-1 | 🔄 | Context7 dans `.cursor/mcp.json` — redémarrer Cursor |
| **P0** | MCP-TEST | ✅ | list_workflows (16) + get_workflow OPS-7 (13 nodes) |
| **P1** | DA-1 | ✅ | `migrate-da1.ps1` exécuté |
| **P1** | R-OPS | ✅ | `rex/2026-07-03-harness-s1.md` |
| **P1** | TOOLS-2 | ✅ | `benchmark-models.py` — model-landscape.json mis à jour |
| **P1** | TOOLS-3 | ✅ | `skills-curated.json` + `skills/INSTALL.md` |
| **P2** | INFRA-2 | ⬜ | Ollama local reviewer |
| **P2** | INFRA-1 | ⬜ | VPS DeepSeek R1 FluxGuard |
| **P2** | RD-MODELS | ⬜ | Cycle mensuel veille modèles |

### ✅ Déjà livré

MCP-1, MCP-3, TECH-V2 (router/supervisor/guardrails), R-ECON vampire, manifests (model-landscape, tool-ecosystem, skills-curated), RULES.md

---

## DÉCISIONS ARCHITECTURALES ACTÉES

### DA-1 — Restructuration AI_agents

**Statut : ✅ Exécuté (2026-07-03)**

```
AI_agents/                   ← AVANT : SEOmnix implicite
  ai-agents-core/
  n8n-projects/

AI_agents/                   ← APRÈS : multi-projet explicite
  seomnix/
    ai-agents-core/          ← FastAPI pipeline SEOmnix
    n8n-projects/            ← workflows n8n SEOmnix
  fluxguard/
    agents/
    n8n-projects/
  hermes/                    ← futur
  openclaw/                  ← futur
  _shared/                   ← libs communes (auth, llm-client, types)
```

**Actions :**
1. `mv AI_agents/ai-agents-core AI_agents/seomnix/ai-agents-core`
2. `mv AI_agents/n8n-projects AI_agents/seomnix/n8n-projects`
3. Créer dossiers vides `fluxguard/`, `_shared/`
4. Mettre à jour les imports et paths dans FastAPI si nécessaire

**Pourquoi maintenant :** coût de migration = 15 min. Dans 6 mois avec 3 projets = ingérable.

---

### DA-2 — Harness Cross-Projet (séparé de AI_agents)

**Statut : ✅ Implémenté (juillet 2026)**

```
Workspaces/
  harness/
    mcp-server/
      src/
        index.ts             ← MCP stdio entrypoint
        llm-router.ts        ← Cloud / VPS / Local routing
        supervisor.ts        ← Intelligent Tool Selection (anti-34k tokens)
        guardrails.ts        ← budget + destructive action check
        tools/
          n8n.ts             ← list/get/update/activate workflows
          git.ts             ← sync_to_git après chaque update
    manifests/
      seomnix.json           ← Tool Registry SEOmnix
      fluxguard.json         ← Tool Registry FluxGuard
    package.json
    tsconfig.json
```

---

## ROADMAP MCP (dans l'ordre)

### MCP-1 — Serveur MCP minimal n8n

**Priorité : P0 — débloquer la sync n8n/local**
**Statut : ✅ Fait**
**Effort estimé : 2-3h**

MCP server Node.js exposant 4 outils wrappant l'API n8n :

| Outil | Endpoint n8n | Description |
|---|---|---|
| `list_workflows` | GET /api/v1/workflows?limit=200 | Liste tous les workflows actifs |
| `get_workflow` | GET /api/v1/workflows/:id | Détail complet d'un workflow |
| `update_workflow` | PUT /api/v1/workflows/:id | Met à jour (nodes, connections) |
| `activate_workflow` | PATCH /api/v1/workflows/:id/activate | Active/désactive |

Variables d'env : `N8N_URL`, `N8N_API_KEY`
Transport : stdio (compatible Claude Code)

### MCP-2 — Connexion Cursor / Claude Code

**Priorité : P0 — suit MCP-1**
**Statut : ⬜ Config prête — activation manuelle**
**Effort estimé : 30 min**

Voir `harness/mcp-config/SETUP.md` et `cursor-mcp.json`.

Ajouter dans Cursor Settings → MCP (ou `%APPDATA%\Claude\claude_desktop_config.json`) :
```json
{
  "mcpServers": {
    "n8n": {
      "command": "node",
      "args": ["C:/Users/delfa/git/Workspaces/harness/mcp-server/dist/index.js"],
      "env": { "N8N_URL": "...", "N8N_API_KEY": "..." }
    }
  }
}
```
Test de validation : modifier OPS-7 brand rotation via Claude Code sans passer par l'UI n8n.

### MCP-3 — Outil sync_to_git

**Priorité : P1 — suit MCP-2**
**Statut : ✅ Fait**
**Effort estimé : 1h**

Après chaque `update_workflow` réussi : écrire le JSON local + `git add + git commit` automatique.
Garantit que le repo git = source de vérité n8n en permanence.

---

## TECH-V2 — Harness Agentic Complet

**Priorité : P1**
**Statut : ✅ Core livré** — supervisor Haiku live = INFRA-3
**Référence :** `harness/RULES.md`, `harness/BACKLOG.md`

### LLM Router

```typescript
// harness/src/llm-router.ts
function routeLLM(task: Task): LLMEndpoint {
  if (task.sensitivity === 'confidential')  return vps('deepseek-r1:8b')      // Safran/FluxGuard — données non exportables
  if (task.type === 'judge' && task.sensitivity === 'public')
                                            return api('gemini-2.5-flash')     // juge SEOmnix — contenu public, coût minimal
  if (task.type === 'judge')               return api('claude-haiku-4-5')     // juge données internes — provider US
  if (task.type === 'routing')             return api('claude-haiku-4-5')     // classification cheap
  if (task.type === 'review')             return local('ollama/mistral')      // reviewer gratuit
  if (task.type === 'generation')         return api('gemini-2.5-flash')      // batch contenu
  return api('claude-sonnet-5')                                               // analyse complexe
}
```

**Règle de sensibilité pour modèles chinois :**
- `sensitivity=public` : contenu public (articles SEO, code open-source) → modèles open mid-tier autorisés (Gemini, DeepSeek-V3, Qwen)
- `sensitivity=internal` : données business non publiées → provider US uniquement
- `sensitivity=confidential` : données client/contractuelles (FluxGuard/Safran) → VPS on-prem exclusivement

**Cas d'usage pilotes → harness.route() :**

| Projet | Fichier | task.type | sensitivity | Modèle attendu |
|---|---|---|---|---|
| SEOmnix evaluator | `ai-agents-core/src/evaluator.py` | `judge` | `public` | Gemini 2.5 Flash |
| SEOmnix pipeline | `ai-agents-core/src/pipeline.py` | `generation` | `public` | Gemini 2.5 Flash |
| FluxGuard analyse | à définir | `analysis` | `confidential` | VPS DeepSeek R1 |

**Transition evaluator.py :**
Aujourd'hui `evaluator.py` hard-code `claude-haiku-3` → à remplacer par `harness.route(task="judge", sensitivity="public")`.
Rustine immédiate acceptable : passer à `claude-haiku-4-5` en attendant que l'interface harness soit stable.

### Intelligent Tool Selection (anti-34k tokens)

Supervisor LLM (Haiku) reçoit l'intent → sélectionne ≤ 3 outils parmi le Tool Registry → passe au Agent Exécutant avec contexte réduit.

Problème résolu : n8n global MCP expose tous les workflows = 34k tokens gaspillés à chaque appel.

### Tool Registry

```json
// manifests/seomnix.json
{
  "project": "seomnix",
  "tools": ["list_workflows", "get_workflow", "update_workflow", "activate_workflow", "sync_to_git"],
  "sensitivity": "public",
  "llm_preference": "gemini-2.5-flash"
}

// manifests/fluxguard.json
{
  "project": "fluxguard",
  "tools": ["..."],
  "sensitivity": "confidential",
  "llm_preference": "vps-deepseek"
}
```

### Guardrails

- Budget : aborter si > N tokens/session
- Destructive action check : `delete`, `deactivate`, `drop` → confirmation humaine obligatoire
- Agent reviewer (Ollama local) : relit chaque output avant livraison
- **R-SEC-1** : divulgation chaîne d'exécution complète avant toute commande setup fetchée à runtime

### Stratégie modèles (R-ECON)

**Principe vampire US :** modèles US (Haiku/Sonnet) pour cadrer et calibrer → modèles open mid-tier (Qwen, GLM, DeepSeek) pour exécuter en volume.

| Rôle | Tier | Modèles |
|---|---|---|
| Cadrage / calibration | US cheap | Haiku, Gemini Flash-Lite |
| Exécution bulk | Open mid-tier | Qwen 2.5, GLM-4-Flash, DeepSeek-V3 |
| Review | Self-hosted | Mistral local |
| Confidentiel | VPS | DeepSeek R1 |

**Liquidité contractuelle :** pay-as-you-go uniquement, pas de reserved capacity. Surcoût souplesse accepté (+20–40%).

**Registry :** `harness/manifests/model-landscape.json`

### RD-MODELS-1 — Agent R&D Modèles

**Priorité : P2 — continu**
**Effort :** 2h/mois récurrent

Veille écosystème mondial (GLM, Alibaba/Qwen, Moonshot/Kimi, DeepSeek, Mistral, Meta) :
1. Benchmark mensuel prix/perf (routing, génération, review)
2. Fiche concurrentielle par vendor
3. Mise à jour `model-landscape.json` → PR `llm-router.ts`

### R-OPS — Cartographie & efficience

**REX post-session** : intent → outils → modèle → durée → coût
**Règle 3×** : tâche répétée ≥ 3 fois → workflow n8n ou outil MCP dédié
**KPI 90j** : -30% temps session, >50% tâches scriptées

Voir `harness/RULES.md` pour le détail complet.

### R-TOOLS — Écosystème outils (lmfit, Context7, skills.sh)

**Priorité : P1 — transverse à toutes les sessions**
**Référence :** `harness/RULES.md` (R-TOOLS-1/2/3/4), `manifests/tool-ecosystem.json`

Pipeline optimal :
```
skills.sh → Context7 → US framing → lmfit (si quanti) → open mid-tier → review
```

| Outil | Rôle harness | Remplace LLM pour |
|---|---|---|
| [lmfit](https://lmfit.github.io/lmfit-py/) | Calibration RD-MODELS, fit coût/perf, bounds routing | Régression, optimisation numérique |
| [Context7](https://context7.com/) | Doc fraîche avant codegen (mid-tier périmé) | Syntaxe API, versions, breaking changes |
| [skills.sh](https://www.skills.sh/) | Acquisition capabilities procédurales (R-OPS 3×) | Workflows TDD/debug/PR standardisés |

**Tickets :**
- `TOOLS-1` : MCP Context7 — config dans `harness/mcp-config/cursor-mcp.json` ⬜
- `TOOLS-2` : `ops-tools/meta/benchmark-models.py` avec lmfit 🔄
- `TOOLS-3` : `manifests/skills-curated.json` + `skills/INSTALL.md` ✅

**⚠ skills.sh :** `npx skills add` soumis à R-SEC-1 — chaîne d'exécution obligatoire.

---

## INFRASTRUCTURE

### INFRA-1 — VPS GPU (DeepSeek R1)

**Usage :**
- Données sensibles FluxGuard (contractuellement non exportables)
- Batch processing nuit (articles, embeddings)
- Toujours allumé, coût fixe vs API variable

**Modèle cible :** DeepSeek-R1 8B (nécessite ~16 GB VRAM)
**Stack :** Ollama on Linux VPS, exposé via API REST locale au harness

### INFRA-2 — PC Local (Ollama)

**Usage :**
- Agent reviewer SEOmnix (relecture emails, articles)
- Tests et prototypage sans coût API
- Latence locale = zéro cold start

**Modèles cibles :** Mistral 7B ou Llama 3.1 8B
**Stack :** Ollama, accessible via `localhost:11434`

### Grille de routing compute

| Cas | Modèle | Justification |
|---|---|---|
| FluxGuard (Safran data) | DeepSeek R1 VPS | Données non exportables |
| Agent reviewer GROWTH-1 | Ollama local | Gratuit, latence acceptable |
| Routing superviseur harness | Claude Haiku 4.5 | Pas de puissance nécessaire, juste tri |
| Articles SEOmnix (génération) | Gemini 2.5 Flash | 0.12$/article validé |
| Juge SEOmnix (evaluator.py) | Gemini 2.5 Flash | contenu public → open mid-tier autorisé |
| Analyse archi FluxGuard | Claude Sonnet 5 | Raisonnement complexe |
| Batch nuit | DeepSeek VPS | Toujours allumé, zéro coût marginal |

---

## ORDRE D'EXÉCUTION (réorganisé juillet 2026)

Voir le détail sprint par sprint dans [`harness/BACKLOG.md`](../harness/BACKLOG.md).

```
[Sprint S1 — EN COURS]
  P0  MCP-2    Activer harness + Context7 dans Cursor
  P0  MCP-TEST validate-harness.ps1 + list_workflows
  ──  (PATH-1 ✅, TOOLS-3 ✅, TECH-V2 ✅)

[Sprint S2]
  P1  DA-1     migrate-da1.ps1 (AI_agents/seomnix/)
  P1  R-OPS    REX post-session (template prêt)
  P1  TOOLS-2  benchmark-models.py → model-landscape.json

[Sprint S3 — infra]
  P2  INFRA-2  Ollama local reviewer
  P2  INFRA-1  VPS GPU DeepSeek R1
  P2  RD-MODELS cycle mensuel
```

**Session type :** `skills.sh → Context7 → US framing → lmfit → open mid-tier → review`

---

## CONTEXTE ARCHITECTURAL COMPLET

**Position du harness dans le monorepo :**

```
Workspaces/
  AI_agents/          ← business logic agents par projet
    seomnix/
    fluxguard/
    _shared/
  Interface/          ← frontend SEOmnix
  FluxGuard/          ← code métier FluxGuard
  ops-tools/          ← scripts cross-cutting
    meta/
      BACKLOG-META.md ← CE FICHIER
    n8n/
      export-workflows.ps1
    affiliates/
  harness/            ← orchestration cross-projet (MCP + Router + Guardrails)
```

**Principe fondamental :** `harness/` orchestrate, `AI_agents/*/` exécutent. Pas de couplage direct entre projets — tout passe par le harness via le Tool Registry.
