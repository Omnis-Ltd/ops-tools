# Product & Architecture Roadmap v1.0 — Fadel OS

Rapport Fractional CTO. Généré 2026-07-15. Ton : trade-offs, pas de conseils carrière.

Sources vérifiées avant rédaction (pas d'invention) :
- `claude-trading-skills` (tradermonty) : toolkit de **Claude Skills** (YAML workflows + skill folders), PAS une app. Human-gated, aucune exécution auto d'ordre, intégration Alpaca/FMP/FINVIZ optionnelle, journalisation locale YAML.
- `PLFM_RADAR` / AERIS-10 (NawfalMotii79) : radar phased-array 10.5 GHz réel (FPGA XC7A50T, STM32F746, GaN 10W, réseau 32x16), portée 3-20km. C'est un projet hardware RF lourd, pas un gadget domestique.
- État réel `ops-tools` : Python (`scripts/devops`, `scripts/ops`, `scripts/notion`) + PowerShell + Makefile + YAML routines. **Pas encore** le CLI Bun/TS visé par le backlog — à traiter comme dette, pas comme acquis.
- État réel `harness/mcp-server` : Node/TS, MCP SDK, smoke tests `.mjs` (pas de Vitest). Router/supervisor/guardrails livrés (TECH-V2).

---

## AXE 1 — Évolution technique des projets existants

### SEOMNIX Empire

**Killer feature suivante :** pas l'evaluator seul (déjà backlogué) — la vraie feature différenciante est la **boucle de calibration juge-humain**. Sans elle, le LLM-as-judge n'est qu'une démo. Implémente `content_evals.human_override` (colonne booléenne + `human_score`) dès le départ, pas en V2. Ça transforme un pipeline de génération en système d'evals au sens propre : accord juge/humain mesurable, dérive détectable dans le temps.

**Choix d'architecture — DB des logs d'evals :** reste sur **Directus/Postgres**, le SSOT actuel. Ne pas introduire un store dédié (LangSmith, Langfuse, etc.) pour un seul pipeline : coût d'intégration et de compte tiers non justifié à ce volume. Une colonne JSONB `judge_feedback` + colonnes générées pour les scores suffit pour interroger et grapher (Grafana déjà en place ailleurs dans l'écosystème, réutilise-le). Bascule vers un store spécialisé seulement si tu evals plusieurs pipelines LLM en parallèle avec besoin de comparaison de runs — pas le cas aujourd'hui.

**Dette à purger en priorité :** le juge tourne actuellement sans baseline de fiabilité. C'est le risque n°1 : un evaluator non calibré donne une fausse confiance, pire qu'aucun evaluator. Bloque tout "Keep → Media" automatique tant que `human_score` vs `judge_score` n'a pas au moins 20 échantillons appariés.

### Harness

**Killer feature suivante :** transformer les guardrails d'un bloc de logique hardcodée en **moteur de policy déclaratif** (`guardrails.yaml` : règles de type `deny/allow/confirm` par action × contexte). Aujourd'hui c'est un frein interne à Harness ; en le rendant déclaratif et importable, c'est l'infra de sécurité que Trading App ET Omnis-Agri/Radar vont consommer telle quelle (voir Axe 3). C'est la feature qui fait le plus levier de tout l'écosystème.

**Choix d'architecture :** package le moteur en `@harness/guardrails` (workspace package interne, pas de publication npm publique pour l'instant — c'est un composant de sécurité, pas un produit vitrine). Stockage de l'audit log : **JSONL local d'abord** (append-only, zéro dépendance, cohérent avec le pattern télémétrie déjà prévu côté ops-tools), migration vers Postgres/Directus seulement si tu as besoin de dashboards cross-projet sur les refus/confirmations.

**Dette à purger :** `smoke-router.mjs` et les tests `.mjs` ne sont pas une suite de tests, ce sont des scripts de fumée. Dès que Harness devient le garde-fou d'un flux qui touche de l'argent (Trading) ou du matériel (Radar/Agri), l'absence de Vitest sur router/supervisor/guardrails devient un risque de sécurité, pas juste une dette de qualité. À traiter avant, pas après, de brancher Trading App dessus.

### Profile Engine

**Killer feature suivante :** pas une fonctionnalité CV de plus. La feature à fort ROI est un endpoint `/v1/changelog` construit depuis les commits/CI des projets déclarés (ce qui rejoint PIPELINE-1 déjà backlogué) : ça transforme le CV statique en "journal d'ingénierie vivant", exactement l'angle DX que le reste de l'écosystème doit vendre.

**Choix d'architecture :** rien de nouveau à inventer, l'archi (Elysia/Eden/Zod, statut `concept/building/live` déjà dans le schema) absorbe Trading App et Radar sans migration.

**Dette à purger :** `LocalizeDeep<T>` et les tests metrics manquants (déjà identifiés). Petit effort, signal fort ("zéro `any`" est un argument technique concret, pas un nice-to-have) — à faire avant d'ajouter de nouveaux projets au schema pour ne pas empiler la dette de typage sur plus de surface.

### ops-tools

**Constat direct :** ce n'est pas encore un CLI, c'est un ensemble de scripts Python/PowerShell hétérogènes. Le backlog "commander.js" est correct mais sous-estime l'écart réel.

**Killer feature suivante :** un `ops doctor` — preflight check unique sur tout l'écosystème (réseau Docker `seo-prod-network`, joignabilité SSH VPS, statut des serveurs MCP, complétude des `.env`). C'est la moins glamour mais la plus utile : c'est le premier outil qu'on montre pour prouver qu'on opère un vrai parc multi-projets, pas des scripts isolés.

**Choix d'architecture — packaging CLI :** deux cibles, pas une. (1) `bun build --compile` → binaire unique pour usage interne quotidien, disponible immédiatement, zéro friction de version Node. (2) Publication npm (`@fdiene/ops-tools`) uniquement après le passage gitleaks — c'est l'artefact public pour le portfolio, mais il ne doit pas sortir avant le nettoyage d'historique.

**Dette à purger :** le mélange Python/PowerShell non inventorié est la dette elle-même. La passe gitleaks + purge d'historique déjà en P0 du backlog est la bonne priorité — ne la contourne pas pour aller plus vite vers commander.js.

---

## AXE 2 — Design system des nouveaux projets

### Copy Trading App

**Réalité du repo source :** `claude-trading-skills` n'est pas une application, c'est un ensemble de Skills Claude + manifests YAML + gates de discipline (`pre-trade-discipline-gate`, `drawdown-circuit-breaker`), conçu pour ne **jamais** déléguer la décision d'ordre à l'IA. C'est une contrainte de conception à respecter, pas une inspiration esthétique : construire un "auto-trader IA" irait contre la philosophie même de la source et contre ta propre doctrine déterministe (Omnis-Agri).

**MVP strict (V1) :** un tableau de bord de régime de marché + journal de trade, en **paper trading Alpaca uniquement**, zéro capital réel. Pas de screener propriétaire, pas de multi-broker, pas d'exécution live. La V1 prouve la boucle : signal → gate déterministe → décision humaine → journalisation → post-mortem. Rien de plus.

**Stack technique — dogmatique :**
- Orchestrateur en **Bun/TS** (cohérence avec Profile Engine/Harness/ops-tools, un seul runtime à maintenir).
- Connexion broker via le **serveur MCP Alpaca existant** (déjà utilisé par `portfolio-manager` dans le repo source) — ne pas réécrire une intégration broker, MCP est fait pour ça.
- Position sizing et circuit-breaker portés en **fonctions pures TS testées** (même pattern que `@profile/core` : logique déterministe séparée de l'orchestration, testable sans réseau).
- Stockage V1 : **JSONL/YAML local**, pas de DB. Un journal de trades n'a pas besoin de Postgres tant qu'il n'y a pas de multi-compte ou d'analytics de backtesting.

**Security & Guardrails :** applique exactement la doctrine Omnis-Agri ("aucune action physique sans validation") transposée à "aucun ordre sans confirmation humaine explicite". Concrètement : `@harness/guardrails` (Axe 1) devient le gate d'exécution — refuse tout appel `place_order` si `TRADING_LIVE` n'est pas explicitement `true` (défaut `false`, kill-switch), et journalise chaque refus/confirmation dans le même audit log que Harness. Le LLM reste cantonné à l'analyse et la rédaction du rationale, jamais à la décision finale — c'est le seul découpage qui tient face à un incident (perte financière = ta responsabilité contractuelle et légale, pas celle du modèle).

### Radar Domestique (PLFM)

**Réalité du repo source :** AERIS-10 est un radar phased-array RF réel à 10.5 GHz, FPGA + GaN 10W, portée 3-20km, projet hardware pluriannuel avec contraintes réglementaires (émission RF à cette fréquence/puissance = déclaration ANFR en France, pas un hobby weekend). Reproduire l'archi complète comme "V1 domestique" n'est pas réaliste ni légal sans démarche préalable.

**MVP strict (V1) — reformulation nécessaire :** ne construis pas le front-end RF (pas d'antenne réseau, pas de PA GaN). Utilise un **module mmWave commercial** (type TI IWR6843/IWR1642, FMCW intégré, radar-on-chip) pour détection de présence/mouvement domestique. C'est la même famille de traitement du signal (chirp FMCW, FFT Doppler, CFAR) que documente AERIS-10, mais sans le risque RF/réglementaire ni le coût de fabrication PCB RF. Le lien avec AERIS-10 reste réel et honnête à mentionner (pipeline de traitement du signal inspiré, pas le hardware).

**Stack technique — dogmatique :**
- **ESP32** (pas STM32) côté acquisition : cohérence directe avec le socle edge déjà choisi pour Omnis-Agri, un seul firmware/toolchain à maintenir sur les deux projets.
- Le module mmWave gère le FMCW et le FFT/CFAR on-chip (TI DSP intégré) — pas de FPGA à toi à programmer en V1. C'est un vrai gain de scope.
- Publication des détections en **MQTT**, sur le **même broker Mosquitto** que prévoit déjà Omnis-Agri.
- Ingestion : le **même endpoint FastAPI** qu'Omnis-Agri, le radar devient un type de capteur de plus dans le schéma Directus existant, pas un nouveau stack.

**Security & Guardrails :** même doctrine "Agent Juge" qu'Omnis-Agri : règles déterministes d'abord (seuils de distance/vitesse), LLM en second avis seulement pour la classification de contexte, aucune actuation (alarme, verrou, notification critique) sans le passage par le même gate `@harness/guardrails`. Si un jour tu montes en puissance RF réelle (vers un vrai FMCW longue portée ou un réseau à plusieurs antennes), traite la conformité ANFR comme un guardrail à part entière, au même titre que SecNumCloud/EBIOS ailleurs dans ton profil — c'est une compétence que tu as déjà, capitalise dessus plutôt que de la découvrir en incident.

---

## AXE 3 — L'effet Synergie (l'écosystème)

**Harness = le nucleus MCP/guardrails partagé.** Un seul moteur de policy (`@harness/guardrails`, Axe 1) consommé par trois domaines différents : contenu (SEOMNIX : publier ou non), argent (Trading : ordonner ou non), matériel (Omnis-Agri/Radar : actionner ou non). C'est la démonstration la plus forte de l'écosystème : une seule brique de sécurité déterministe, réutilisée, pas trois implémentations ad hoc. C'est aussi ce qui justifie d'investir dans les tests Vitest de Harness (Axe 1) avant de le brancher sur Trading — le nucleus doit être le composant le plus solide de tout le parc, pas le plus faible.

**Radar = capteur natif d'Omnis-Agri, pas un projet à part.** Même broker MQTT, même endpoint d'ingestion FastAPI, même schéma Directus, même pattern Agent Juge. Le radar n'ajoute aucune ligne d'architecture nouvelle à Omnis-Agri, seulement un type de capteur de plus et un cas d'usage de plus (sécurité domestique en plus de la serre). C'est la preuve que l'architecture Omnis-Agri est réellement générique, pas câblée à un seul cas d'usage.

**ops-tools = le déployeur de flotte.** Une fois `ops doctor` livré (Axe 1), l'extension naturelle est `ops deploy <service>` qui généralise le pattern Docker Compose + Traefik déjà validé en prod sur Profile Engine (VPS `seo-prod`, réseau `seo-prod-network`) à Trading App (sandbox paper-trading) et à l'API d'ingestion Radar. Un seul chemin de déploiement pour tout le parc, documenté une fois dans `ops-tools/routines/*.yaml` (le format existe déjà), réutilisé partout.

**SEOMNIX = la méthodologie evals, pas juste un pipeline de contenu.** La boucle de calibration juge/humain (Axe 1) n'est pas spécifique au contenu : c'est le même principe que doit utiliser Trading App pour fact-checker un rationale de trade contre les données de marché, et Omnis-Agri pour le second avis de l'Agent Juge. Une seule méthodologie d'evals, trois consommateurs — documente-la une fois comme composant partagé (pas de code partagé nécessaire, juste la même discipline appliquée trois fois).

**Profile Engine = la vitrine, sans coût de maintenance ajouté.** Le schema (`status: concept/building/live`) absorbe Trading App et Radar dès aujourd'hui sans migration. Aucune action requise ici avant qu'ils atteignent un statut réel à afficher.

---

## Ce qui ne doit PAS être fait maintenant (garde-fous anti-scope-creep)

- Pas de FPGA custom, pas de PCB RF pour le Radar en V1 — c'est un projet de plusieurs années si tu pars de là.
- Pas d'exécution d'ordre réelle pour Trading avant que Harness ait une vraie suite de tests sur ses guardrails.
- Pas de nouveau store de données (vector DB, plateforme evals SaaS) tant que Postgres/Directus suffit — actuellement le cas partout.
- Pas de publication npm d'ops-tools avant la purge gitleaks.
