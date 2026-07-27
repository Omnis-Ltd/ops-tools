# ops-tools packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Porter la logique métier de `ops doctor` (V1, PowerShell) en TypeScript pilotée par un manifeste JSON, packagée comme binaire Bun compilé, sans casser ni supprimer la V1.

**Architecture:** Un fichier `fadel-os.config.json` à la racine du monorepo comme source de vérité (conteneurs attendus, serveurs MCP, cibles `.env`, cibles de backlog), validé par un schéma Zod au chargement. Un script unique `ops-tools/scripts/ops/doctor.ts` (même granularité fichier que `doctor.ps1`) qui charge ce manifeste et exécute 4 sections isolées par `try/catch` (Infra, MCP, Env, Backlog), avec le même moteur de findings et le même format de rapport que la V1. Compilé en binaire autonome via `bun build --compile`.

**Tech Stack:** Bun 1.3.14 (runtime + shell `Bun.$` + compilateur), TypeScript strict, Zod pour la validation de schéma, `bun:test` pour les tests unitaires (aucune dépendance de test externe).

## Global Constraints

- **Variable d'environnement** : `WORKSPACES_ROOT` uniquement (jamais `FADEL_OS_ROOT`), avec repli sur `path.join(os.homedir(), "git", "Workspaces")` - même convention que `scripts/maintenance/*.sh` et `doctor.ps1`.
- **Chemins Windows dans `Bun.$`** : tout chemin interpolé dans un template `` $`...` `` doit utiliser des slashs (`C:/Windows/...`), jamais des backslashes - `Bun.$` traite `\` comme caractère d'échappement et corrompt silencieusement le chemin (vérifié par spike, voir le spec section "Résultats du spike"). Utiliser la fonction `toShellPath()` (Task 1) pour tout chemin dynamique construit via `path.join`.
- **`bun build --compile` élimine le bug WOW64 de la V1** : un binaire compilé cible x64 nativement, pas de contournement `Sysnative`/`Is64BitProcess` à porter en TypeScript - ne pas réintroduire cette complexité.
- **Portée** : `doctor.ts` reste un script autonome, pas de squelette CLI `commander.js`. Pas de retrait de `doctor.ps1` dans ce chantier. Pas de `npm publish` effectif (le `package.json` est prêt, la commande n'est jamais lancée). Pas de découverte automatique pour peupler le manifeste - listes explicites comme la V1.
- **Pas de fichier `fadel-os.config.schema.json` séparé dans ce plan** : le spec offrait "schéma Zod exporté OU JSON Schema" comme alternatives. Ce plan retient uniquement le schéma Zod, défini directement dans `doctor.ts` (même fichier, comme la V1 PowerShell contenait tout dans `doctor.ps1`) - dupliquer le schéma dans un second format sans consommateur (pas d'IDE JSON Schema configuré) serait du travail non justifié.
- **Sécurité Env** : les valeurs de variables d'environnement ne sont jamais lues au-delà du nom de clé (regex `^([A-Z0-9_]+)=`), jamais loggées.
- **Tests** : `bun test` uniquement sur les fonctions pures (schéma, parseurs, extraction de clés) - aucun mock pour SSH/Docker/git, ces checks restent vérifiés manuellement avec preuve dans un rapport, comme la V1.
- **`import.meta.main`** : le point d'entrée `main()` de `doctor.ts` doit être gardé par `if (import.meta.main) { await main(); }`, jamais appelé nu au niveau module - sinon importer `doctor.ts` depuis les tests déclenche une exécution complète (SSH, Docker, git réels) comme effet de bord de l'import.
- **Jamais de tiret cadratin dans la rédaction** (commentaires, messages, documentation). Exception explicite et unique : la valeur `sectionHeader` de l'entrée `ops-tools/meta/BACKLOG-META.md` dans `fadel-os.config.json` doit contenir le caractère tiret cadratin réel, copié tel quel depuis le titre existant du fichier source - c'est une donnée qui doit matcher un fichier réel, pas de la prose rédigée.
- Avant tout commit : montrer `git diff` et résumer les changements.

---

### Task 1 : Manifeste `fadel-os.config.json` + socle `doctor.ts`

**Files:**
- Create: `fadel-os.config.json` (racine du monorepo, PAS dans `ops-tools/`)
- Create: `ops-tools/scripts/ops/doctor.ts`
- Test: `ops-tools/scripts/ops/doctor.test.ts`

**Interfaces:**
- Consumes : rien (première tâche).
- Produces :
  - `type Severity = "pass" | "warn" | "fail"`, `interface Finding { severity: Severity; category: string; message: string }`
  - `addFinding(severity: Severity, category: string, message: string): void` (accumule dans un tableau module-scope `findings` et incrémente `scores`)
  - `FadelConfigSchema` (schéma Zod, exporté), `type FadelConfig = z.infer<typeof FadelConfigSchema>` (exporté)
  - `loadConfig(configPath: string): FadelConfig` (exporté, lève une erreur avec message clair si fichier absent, JSON invalide, ou schéma invalide)
  - `resolveWorkspacesRoot(): string`, `toShellPath(p: string): string`, `formatTimestamp(date: Date): string` (exportés)
  - 4 fonctions stub `checkInfra`, `checkMcp`, `checkEnv`, `checkBacklog`, chacune de signature `(config: FadelConfig, workspacesRoot: string) => Promise<void>` - corps vide (commentaire d'ancrage), remplies par les Tasks 2 à 5.
  - `main()` : orchestration complète (bootstrap, chargement config, boucle des 4 sections avec try/catch, génération du rapport, code de sortie), gardée par `if (import.meta.main)`.

- [ ] **Step 1 : Créer le manifeste `fadel-os.config.json`**

Créer `fadel-os.config.json` à la racine du monorepo (`c:\Users\delfa\git\Workspaces\fadel-os.config.json`, PAS sous `ops-tools/`) avec exactement ce contenu (valeurs copiées depuis les listes en dur de `ops-tools/scripts/ops/doctor.ps1`) :

```json
{
  "version": 1,
  "infra": {
    "sshHost": "seo-prod",
    "dockerNetwork": "seo-prod-network",
    "expectedContainers": [
      "prod-traefik",
      "prod-n8n",
      "prod-seo-directus",
      "prod-seo-agents",
      "prod-seo-postgres",
      "prod-seo-redis",
      "prod-seo-qdrant",
      "prod-n8n-postgres",
      "profile-api"
    ]
  },
  "mcp": [
    {
      "name": "harness",
      "serverRoot": "harness/mcp-server",
      "cursorConfigPath": "harness/.cursor/mcp.json",
      "serverKey": "harness"
    }
  ],
  "env": [
    { "name": "harness", "path": "harness" },
    { "name": "Infra/infra-local", "path": "Infra/infra-local" },
    { "name": "Infra/infra-prod", "path": "Infra/infra-prod" },
    { "name": "Interface/frontend-astro", "path": "Interface/frontend-astro" },
    { "name": "my-curriculum", "path": "my-curriculum" },
    { "name": "ops-tools", "path": "ops-tools" },
    { "name": "personal-tech-board", "path": "personal-tech-board" }
  ],
  "backlog": [
    {
      "type": "checklist",
      "name": "UPSKILLING.md",
      "path": "my-curriculum/docs/UPSKILLING.md"
    },
    {
      "type": "table",
      "name": "harness/BACKLOG.md",
      "path": "harness/BACKLOG.md",
      "sectionHeader": "## Vue priorisée (ordre d'exécution)",
      "statusColumnHeader": "Statut"
    },
    {
      "type": "table",
      "name": "ops-tools/meta/BACKLOG-META.md",
      "path": "ops-tools/meta/BACKLOG-META.md",
      "sectionHeader": "## Sprint S1 — Mise en service harness (juillet 2026)",
      "statusColumnHeader": "Statut"
    }
  ]
}
```

Important : la dernière valeur `sectionHeader` ci-dessus contient le caractère tiret cadratin réel entre "S1" et "Mise" - copiez-le exactement depuis ce bloc de code (ne le retapez pas à la main, un tiret normal ou un tiret cadratin différent ne matchera pas le titre réel de `ops-tools/meta/BACKLOG-META.md`).

- [ ] **Step 2 : Créer `doctor.ts` avec le moteur de findings, le chargement de config, et le squelette**

Créer `ops-tools/scripts/ops/doctor.ts` :

```typescript
// doctor.ts
// Preflight check unique pour l'ecosysteme Fadel OS : infra, MCP, completude .env, avancement backlogs.
// Usage : bun scripts/ops/doctor.ts   (depuis ops-tools/)
//    ou : make doctor (apres bun run build:doctor)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { z } from "zod";

// --- Schema du manifeste ---

const InfraConfigSchema = z.object({
  sshHost: z.string(),
  dockerNetwork: z.string(),
  expectedContainers: z.array(z.string()).min(1),
});

const McpConfigSchema = z.object({
  name: z.string(),
  serverRoot: z.string(),
  cursorConfigPath: z.string(),
  serverKey: z.string(),
});

const EnvConfigSchema = z.object({
  name: z.string(),
  path: z.string(),
});

const BacklogChecklistSchema = z.object({
  type: z.literal("checklist"),
  name: z.string(),
  path: z.string(),
});

const BacklogTableSchema = z.object({
  type: z.literal("table"),
  name: z.string(),
  path: z.string(),
  sectionHeader: z.string(),
  statusColumnHeader: z.string().default("Statut"),
});

const BacklogEntrySchema = z.discriminatedUnion("type", [
  BacklogChecklistSchema,
  BacklogTableSchema,
]);

export const FadelConfigSchema = z.object({
  version: z.literal(1),
  infra: InfraConfigSchema,
  mcp: z.array(McpConfigSchema),
  env: z.array(EnvConfigSchema),
  backlog: z.array(BacklogEntrySchema),
});

export type FadelConfig = z.infer<typeof FadelConfigSchema>;

export function loadConfig(configPath: string): FadelConfig {
  if (!fs.existsSync(configPath)) {
    throw new Error(`fadel-os.config.json introuvable : ${configPath}`);
  }
  const raw = fs.readFileSync(configPath, "utf8");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(`fadel-os.config.json invalide (JSON malforme) : ${(err as Error).message}`);
  }
  const result = FadelConfigSchema.safeParse(parsed);
  if (!result.success) {
    const issues = result.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`fadel-os.config.json invalide : ${issues}`);
  }
  return result.data;
}

// --- Moteur de findings ---

export type Severity = "pass" | "warn" | "fail";

export interface Finding {
  severity: Severity;
  category: string;
  message: string;
}

const findings: Finding[] = [];
const scores: Record<Severity, number> = { pass: 0, warn: 0, fail: 0 };

export function addFinding(severity: Severity, category: string, message: string): void {
  findings.push({ severity, category, message });
  scores[severity]++;
}

// --- Utilitaires ---

export function resolveWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT ?? path.join(os.homedir(), "git", "Workspaces");
}

export function toShellPath(p: string): string {
  return p.replaceAll("\\", "/");
}

export function formatTimestamp(date: Date): string {
  const iso = date.toISOString(); // ex: 2026-07-24T08:59:29.123Z
  const [datePart, timePart] = iso.split("T");
  const compactDate = datePart.replaceAll("-", "");
  const compactTime = timePart.slice(0, 8).replaceAll(":", "");
  return `${compactDate}T${compactTime}Z`;
}

const colors = {
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  cyan: (s: string) => `\x1b[36m${s}\x1b[0m`,
};

// --- Sections (squelette, remplies par les taches suivantes) ---

async function checkInfra(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 2
}

async function checkMcp(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 3
}

async function checkEnv(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 4
}

async function checkBacklog(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 5
}

// --- Orchestration ---

function printReportAndExit(opsToolsRoot: string): never {
  console.log(colors.cyan(`\n=== Findings (${findings.length}) ===`));
  const sorted = [...findings].sort((a, b) =>
    a.severity === b.severity ? a.category.localeCompare(b.category) : a.severity.localeCompare(b.severity)
  );
  for (const f of sorted) {
    const color = f.severity === "pass" ? colors.green : f.severity === "warn" ? colors.yellow : colors.red;
    console.log(color(`  [${f.severity.toUpperCase().padStart(4)}] ${f.category.padEnd(10)} ${f.message}`));
  }

  console.log(colors.cyan("\n=== Score ==="));
  console.log(`  PASS: ${scores.pass}  WARN: ${scores.warn}  FAIL: ${scores.fail}`);

  const timestamp = formatTimestamp(new Date());
  const outDir = path.join(opsToolsRoot, "meta", "rex");
  const outFile = path.join(outDir, `doctor_${timestamp}.md`);
  fs.mkdirSync(outDir, { recursive: true });

  const mdLines = [
    `# ops doctor - ${new Date().toISOString().slice(0, 16).replace("T", " ")}`,
    "",
    "| Severity | Category | Message |",
    "|---|---|---|",
    ...sorted.map((f) => `| ${f.severity} | ${f.category} | ${f.message.replaceAll("|", "/")} |`),
    "",
    `**Score:** PASS=${scores.pass} WARN=${scores.warn} FAIL=${scores.fail}`,
  ];
  fs.writeFileSync(outFile, mdLines.join("\n"), "utf8");
  console.log(colors.green(`\nRapport: ${outFile}`));

  process.exit(scores.fail > 0 ? 1 : 0);
}

async function main(): Promise<void> {
  const workspacesRoot = resolveWorkspacesRoot();
  const opsToolsRoot = path.join(workspacesRoot, "ops-tools");

  console.log(colors.cyan("\n=== ops doctor ==="));
  console.log(`Workspaces: ${workspacesRoot}\n`);

  if (fs.existsSync(workspacesRoot)) {
    addFinding("pass", "bootstrap", `Workspaces root resolu : ${workspacesRoot}`);
  } else {
    addFinding("fail", "bootstrap", `Workspaces root introuvable : ${workspacesRoot}`);
  }

  const configPath = path.join(workspacesRoot, "fadel-os.config.json");
  let config: FadelConfig;
  try {
    config = loadConfig(configPath);
  } catch (err) {
    addFinding("fail", "bootstrap", (err as Error).message);
    printReportAndExit(opsToolsRoot);
  }

  const sections: Array<{ name: string; fn: (c: FadelConfig, w: string) => Promise<void> }> = [
    { name: "infra", fn: checkInfra },
    { name: "mcp", fn: checkMcp },
    { name: "env", fn: checkEnv },
    { name: "backlog", fn: checkBacklog },
  ];

  for (const section of sections) {
    console.log(colors.yellow(`\n--- ${section.name} ---`));
    try {
      await section.fn(config, workspacesRoot);
    } catch (err) {
      addFinding("fail", section.name, `Section ${section.name} : erreur inattendue (${(err as Error).message})`);
    }
  }

  printReportAndExit(opsToolsRoot);
}

if (import.meta.main) {
  await main();
}
```

- [ ] **Step 3 : Écrire les tests du schéma et des utilitaires**

Créer `ops-tools/scripts/ops/doctor.test.ts` :

```typescript
import { describe, expect, test } from "bun:test";
import { FadelConfigSchema, formatTimestamp } from "./doctor";

describe("FadelConfigSchema", () => {
  const validConfig = {
    version: 1,
    infra: {
      sshHost: "seo-prod",
      dockerNetwork: "seo-prod-network",
      expectedContainers: ["prod-n8n"],
    },
    mcp: [
      {
        name: "harness",
        serverRoot: "harness/mcp-server",
        cursorConfigPath: "harness/.cursor/mcp.json",
        serverKey: "harness",
      },
    ],
    env: [{ name: "ops-tools", path: "ops-tools" }],
    backlog: [
      { type: "checklist", name: "UPSKILLING.md", path: "my-curriculum/docs/UPSKILLING.md" },
      {
        type: "table",
        name: "harness/BACKLOG.md",
        path: "harness/BACKLOG.md",
        sectionHeader: "## Vue priorisee",
      },
    ],
  };

  test("accepts a valid config", () => {
    const result = FadelConfigSchema.safeParse(validConfig);
    expect(result.success).toBe(true);
  });

  test("rejects a config with wrong version", () => {
    const result = FadelConfigSchema.safeParse({ ...validConfig, version: 2 });
    expect(result.success).toBe(false);
  });

  test("rejects a backlog entry with unknown type", () => {
    const bad = { ...validConfig, backlog: [{ type: "unknown", name: "x", path: "x" }] };
    const result = FadelConfigSchema.safeParse(bad);
    expect(result.success).toBe(false);
  });

  test("defaults statusColumnHeader to Statut when omitted", () => {
    const result = FadelConfigSchema.safeParse(validConfig);
    expect(result.success).toBe(true);
    if (result.success) {
      const table = result.data.backlog[1];
      expect(table.type).toBe("table");
      if (table.type === "table") {
        expect(table.statusColumnHeader).toBe("Statut");
      }
    }
  });
});

describe("formatTimestamp", () => {
  test("formats a UTC date as yyyyMMddTHHmmssZ", () => {
    const date = new Date(Date.UTC(2026, 6, 24, 8, 59, 29));
    expect(formatTimestamp(date)).toBe("20260724T085929Z");
  });
});
```

- [ ] **Step 4 : Installer les dépendances et lancer les tests**

Depuis `ops-tools/` :
```bash
bun add zod
bun add -d @types/node typescript
bun test scripts/ops/doctor.test.ts
```
Attendu : tous les tests passent (6 tests : 4 sur `FadelConfigSchema`, 1 sur `formatTimestamp`, plus le test implicite de compilation TypeScript au chargement).

- [ ] **Step 5 : Vérifier que le squelette s'exécute sans crasher**

Depuis `ops-tools/` :
```bash
WORKSPACES_ROOT="$(cd .. && pwd -W 2>/dev/null || cd .. && pwd)" bun scripts/ops/doctor.ts
```
Ou plus simplement, si `WORKSPACES_ROOT` n'est pas déjà positionné dans l'environnement, laisser le repli par défaut agir (fonctionne si le repo est bien sous `~/git/Workspaces`). Attendu : `=== ops doctor ===`, le bootstrap `PASS`, les 4 sections vides (rien entre les titres), `=== Findings (1) ===` avec uniquement la ligne bootstrap, score `PASS: 1  WARN: 0  FAIL: 0`, une ligne `Rapport: ...`. Code de sortie 0 (vérifier avec `echo $?`).

Nettoyer le rapport de test généré (`rm meta/rex/doctor_*.md`) avant de continuer.

- [ ] **Step 6 : Commit**

Vérifié : `Workspaces` (la racine du monorepo, parent de `ops-tools/`) n'est pas un dépôt git (`git -C .. rev-parse --is-inside-work-tree` échoue avec `fatal: not a git repository`). `fadel-os.config.json` reste donc un fichier non versionné à la racine du monorepo - aucun commit ne le concerne. Seul le travail dans `ops-tools/` est commité :

```bash
git add scripts/ops/doctor.ts scripts/ops/doctor.test.ts package.json bun.lock 2>/dev/null
git status
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): socle doctor.ts (schema Zod, moteur findings, squelette)

Schema Zod (FadelConfigSchema) valide fadel-os.config.json au
chargement (fichier a la racine du monorepo, non versionne - le
monorepo Workspaces n'est pas un depot git). Moteur de findings
identique a la V1 PowerShell (Add-Finding, scores PASS/WARN/FAIL).
Squelette des 4 sections (Infra/MCP/Env/Backlog), remplies dans les
taches suivantes. Rapport Markdown horodate + resume console colore,
meme format que doctor.ps1.

main() garde par import.meta.main pour permettre l'import du module
depuis les tests sans declencher d'appels reseau/systeme reels.
EOF
)"
```

---

### Task 2 : Section Infra

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ts` (ajoute l'import `{ $ }` depuis `"bun"`, remplace le corps de `checkInfra`)

**Interfaces:**
- Consumes : `addFinding`, `FadelConfig` (Task 1). Le chemin `ssh.exe` est un littéral déjà en slashs (`toShellPath` n'est pas nécessaire ici, il sert aux chemins dynamiques construits par `path.join` - voir Task 3).
- Produces : rien de nouveau consommé par les tâches suivantes.

- [ ] **Step 1 : Ajouter l'import Bun shell**

En haut de `ops-tools/scripts/ops/doctor.ts`, après les imports `node:*` existants, ajouter :
```typescript
import { $ } from "bun";
```

- [ ] **Step 2 : Implémenter `checkInfra`**

Remplacer :
```typescript
async function checkInfra(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 2
}
```
par :
```typescript
async function checkInfra(config: FadelConfig, workspacesRoot: string): Promise<void> {
  const sshExe = "C:/Windows/System32/OpenSSH/ssh.exe";
  const dockerCmd = `docker ps --filter network=${config.infra.dockerNetwork} --format '{{json .}}'`;

  let sshOutput: string;
  try {
    sshOutput = await $`${sshExe} -o BatchMode=yes -o ConnectTimeout=5 ${config.infra.sshHost} ${dockerCmd}`.text();
  } catch {
    addFinding("fail", "infra", `VPS ${config.infra.sshHost} injoignable`);
    return;
  }

  interface DockerPsEntry {
    Names: string;
    State: string;
    Status: string;
  }

  const runningContainers = new Map<string, DockerPsEntry>();
  for (const rawLine of sshOutput.split("\n")) {
    const trimmed = rawLine.trim();
    if (!trimmed) continue;
    try {
      const obj = JSON.parse(trimmed) as DockerPsEntry;
      runningContainers.set(obj.Names, obj);
    } catch {
      continue;
    }
  }

  for (const name of config.infra.expectedContainers) {
    const container = runningContainers.get(name);
    if (!container) {
      addFinding("fail", "infra", `${name} : conteneur introuvable sur ${config.infra.dockerNetwork}`);
      continue;
    }
    if (container.State !== "running") {
      addFinding("fail", "infra", `${name} : arrete (etat=${container.State})`);
    } else if (container.Status.includes("(unhealthy)")) {
      addFinding("warn", "infra", `${name} : running mais unhealthy`);
    } else {
      addFinding("pass", "infra", `${name} : running (${container.Status})`);
    }
  }
}
```

Note technique (héritée du spike, cf. Global Constraints) : `sshExe` utilise des slashs, pas des backslashes - c'est un chemin interpolé dans un template `` $`...` ``. `docker ps --format '{{json .}}'` produit du JSON Lines (un objet par ligne), pas un tableau JSON : d'où le split par `\n` et le parsing ligne par ligne, identique en logique à `doctor.ps1`. Pas de champ `Health` séparé dans la sortie Docker : l'état de santé est dans `Status` (ex. `"Up 3 days (healthy)"`).

- [ ] **Step 3 : Vérifier le cas nominal**

Depuis `ops-tools/` :
```bash
bun scripts/ops/doctor.ts
```
Vérifier manuellement en parallèle :
```bash
C:/Windows/System32/OpenSSH/ssh.exe -o BatchMode=yes -o ConnectTimeout=5 seo-prod "docker ps --filter network=seo-prod-network --format '{{.Names}}\t{{.Status}}'"
```
Comparer : chaque conteneur listé manuellement avec un statut `Up ...` doit apparaître en `PASS` (ou `WARN` si `(unhealthy)`) dans la sortie de `doctor.ts`, section Infra. Tout conteneur de la liste attendue absent de la sortie manuelle doit apparaître en `FAIL`.

- [ ] **Step 4 : Vérifier le cas VPS injoignable**

Simuler une indisponibilité temporaire dans `fadel-os.config.json` (changer `"sshHost": "seo-prod"` en `"sshHost": "seo-prod-test-unreachable"`, sans commit), relancer `bun scripts/ops/doctor.ts` : vérifier une seule ligne `[FAIL] infra VPS seo-prod-test-unreachable injoignable`, aucune autre ligne `infra`, et les autres sections (MCP/Env/Backlog, encore vides) s'exécutent normalement. Annuler la modification temporaire du manifeste avant de continuer (`git diff` sur `fadel-os.config.json` doit être vide).

Nettoyer les rapports de test générés avant de continuer.

- [ ] **Step 5 : Commit**

```bash
git add scripts/ops/doctor.ts
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section infra doctor.ts (docker ps via Bun.$ + ssh natif)

Meme logique que doctor.ps1 : parsing JSON Lines de docker ps,
classification running/healthy/unhealthy sur les champs State/Status
(pas de champ Health separe). Chemin ssh.exe en slashs (Bun.$ corrompt
les backslashes dans un template shell, voir spec). VPS injoignable =
1 FAIL, section arretee, les autres sections continuent.
EOF
)"
```

---

### Task 3 : Section MCP

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ts` (remplace le corps de `checkMcp`, ajoute un helper `listFilesRecursive`)

**Interfaces:**
- Consumes : `addFinding`, `toShellPath`, `$` depuis `"bun"` (Task 2), `FadelConfig`.
- Produces : `listFilesRecursive(dir: string): string[]` (nouveau helper, pas réutilisé par les tâches suivantes mais disponible).

- [ ] **Step 1 : Ajouter le helper `listFilesRecursive`**

Dans `ops-tools/scripts/ops/doctor.ts`, juste avant `async function checkInfra`, ajouter :
```typescript
function listFilesRecursive(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const results: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listFilesRecursive(fullPath));
    } else {
      results.push(fullPath);
    }
  }
  return results;
}
```

- [ ] **Step 2 : Implémenter `checkMcp`**

Remplacer :
```typescript
async function checkMcp(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 3
}
```
par :
```typescript
async function checkMcp(config: FadelConfig, workspacesRoot: string): Promise<void> {
  for (const server of config.mcp) {
    const serverRoot = path.join(workspacesRoot, ...server.serverRoot.split("/"));
    const distIndex = path.join(serverRoot, "dist", "index.js");
    const srcDir = path.join(serverRoot, "src");

    if (!fs.existsSync(distIndex)) {
      addFinding("warn", "mcp", `${server.name} : dist/index.js absent (build jamais lance)`);
    } else {
      const distTime = fs.statSync(distIndex).mtimeMs;
      const srcFiles = listFilesRecursive(srcDir);
      const newestSrcTime =
        srcFiles.length > 0 ? Math.max(...srcFiles.map((f) => fs.statSync(f).mtimeMs)) : null;
      if (newestSrcTime !== null && newestSrcTime > distTime) {
        addFinding("warn", "mcp", `${server.name} : build obsolete (dist/ plus ancien que src/)`);
      } else {
        addFinding("pass", "mcp", `${server.name} : build a jour (dist/index.js)`);
      }
    }

    const cursorConfigPath = path.join(workspacesRoot, ...server.cursorConfigPath.split("/"));
    if (fs.existsSync(cursorConfigPath)) {
      const mcpJson = JSON.parse(fs.readFileSync(cursorConfigPath, "utf8"));
      const serverEntry = mcpJson.mcpServers?.[server.serverKey];
      const referencedPath: string | undefined = serverEntry?.args?.find((a: string) =>
        /index\.js$/.test(a)
      );
      if (referencedPath && fs.existsSync(referencedPath)) {
        addFinding(
          "pass",
          "mcp",
          `${server.name} : mcp.json pointe vers un dist/index.js existant (${referencedPath})`
        );
      } else if (referencedPath) {
        addFinding("warn", "mcp", `${server.name} : mcp.json pointe vers un chemin introuvable (${referencedPath})`);
      } else {
        addFinding(
          "warn",
          "mcp",
          `${server.name} : mcp.json ne reference pas index.js pour le serveur ${server.serverKey}`
        );
      }
    } else {
      addFinding("warn", "mcp", `${server.cursorConfigPath} absent`);
    }

    let lastActivity: string | null = null;
    try {
      const out = await $`git -C ${toShellPath(serverRoot)} log -1 --format=%cd -- .`.text();
      lastActivity = out.trim() || null;
    } catch {
      lastActivity = null;
    }
    if (lastActivity) {
      addFinding("pass", "mcp", `${server.name} : derniere activite ${lastActivity}`);
    } else {
      addFinding("warn", "mcp", `${server.name} : aucun historique git trouve pour ${server.serverRoot}`);
    }
  }
}
```

Note technique : contrairement à `doctor.ps1` (où un `git` en échec sous `2>$null` retourne simplement une sortie vide sans exception), `Bun.$` lève une exception sur un code de sortie non nul (confirmé par le spike). Le comportement observable reste identique (WARN "aucun historique trouvé" en cas d'échec), mais obtenu via un `try/catch` explicite plutôt qu'une vérification de sortie vide - une adaptation nécessaire au runtime, pas une divergence de logique métier.

- [ ] **Step 3 : Vérifier le cas nominal**

Depuis `ops-tools/` :
```bash
bun scripts/ops/doctor.ts
```
Vérifier manuellement l'état réel :
```bash
ls -la --time-style=full-iso ../harness/mcp-server/dist/index.js
find ../harness/mcp-server/src -type f -printf '%T@ %p\n' | sort -rn | head -1
```
Comparer avec la ligne `mcp` de `doctor.ts` (PASS "build a jour" si dist plus récent que tous les fichiers src, WARN sinon). Vérifier aussi que la ligne "derniere activite" affiche une date plausible (comparer avec `git -C ../harness/mcp-server log -1 --format=%cd`).

- [ ] **Step 4 : Vérifier le cas dist absent**

Renommer temporairement `harness/mcp-server/dist` en `dist.bak` (sans commit), relancer `bun scripts/ops/doctor.ts`, vérifier `[WARN] mcp harness : dist/index.js absent (build jamais lance)`. Renommer `dist.bak` en `dist` pour restaurer l'état.

Nettoyer les rapports de test générés avant de continuer.

- [ ] **Step 5 : Commit**

```bash
git add scripts/ops/doctor.ts
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section MCP doctor.ts (build + config harness)

Meme logique que doctor.ps1 : comparaison mtime dist/index.js vs
src/, verification que mcp.json reference un index.js existant,
derniere activite git. git via Bun.$ leve une exception sur echec
(pas un LASTEXITCODE a verifier comme en PowerShell) : try/catch
explicite pour obtenir le meme comportement observable (WARN si
aucun historique). Pas de smoke test MCP runtime en V1/V2.
EOF
)"
```

---

### Task 4 : Section Env

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ts` (ajoute `extractEnvKeys`, remplace le corps de `checkEnv`)
- Modify: `ops-tools/scripts/ops/doctor.test.ts` (ajoute les tests de `extractEnvKeys`)

**Interfaces:**
- Consumes : `addFinding`, `FadelConfig` (Task 1).
- Produces : `extractEnvKeys(content: string): string[]` (exportée, fonction pure testable).

- [ ] **Step 1 : Écrire les tests de `extractEnvKeys` (avant l'implémentation)**

Dans `ops-tools/scripts/ops/doctor.test.ts`, ajouter après le bloc `describe("formatTimestamp", ...)` existant :
```typescript
describe("extractEnvKeys", () => {
  test("extracts key names, ignoring values and comments", () => {
    const content = ["# comment", "NOTION_API_KEY=secret_abc123", "", "PORT=3000", "not a valid line"].join(
      "\n"
    );
    expect(extractEnvKeys(content)).toEqual(["NOTION_API_KEY", "PORT"]);
  });

  test("returns an empty array for content with no valid keys", () => {
    expect(extractEnvKeys("# just a comment\n")).toEqual([]);
  });
});
```
Ajouter `extractEnvKeys` à l'import en haut du fichier :
```typescript
import { FadelConfigSchema, formatTimestamp, extractEnvKeys } from "./doctor";
```

- [ ] **Step 2 : Lancer les tests, vérifier qu'ils échouent (fonction pas encore exportée)**

```bash
bun test scripts/ops/doctor.test.ts
```
Attendu : échec à l'import (`extractEnvKeys` n'existe pas dans `./doctor`).

- [ ] **Step 3 : Implémenter `extractEnvKeys` et `checkEnv`**

Dans `ops-tools/scripts/ops/doctor.ts`, ajouter juste avant `async function checkInfra` :
```typescript
export function extractEnvKeys(content: string): string[] {
  const keys: string[] = [];
  for (const line of content.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)=/);
    if (match) keys.push(match[1]);
  }
  return keys;
}
```

Remplacer :
```typescript
async function checkEnv(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 4
}
```
par :
```typescript
async function checkEnv(config: FadelConfig, workspacesRoot: string): Promise<void> {
  for (const target of config.env) {
    const repoPath = path.join(workspacesRoot, ...target.path.split("/"));
    const examplePath = path.join(repoPath, ".env.example");
    const envPath = path.join(repoPath, ".env");

    if (!fs.existsSync(examplePath)) {
      addFinding("warn", "env", `${target.name} : .env.example absent`);
      continue;
    }

    const exampleKeys = extractEnvKeys(fs.readFileSync(examplePath, "utf8"));

    if (!fs.existsSync(envPath)) {
      addFinding("fail", "env", `${target.name} : .env absent (${exampleKeys.length} cles attendues)`);
      continue;
    }

    const envKeys = new Set(extractEnvKeys(fs.readFileSync(envPath, "utf8")));
    const missingKeys = exampleKeys.filter((k) => !envKeys.has(k));

    if (missingKeys.length === 0) {
      addFinding("pass", "env", `${target.name} : .env complet (${exampleKeys.length} cles)`);
    } else {
      for (const key of missingKeys) {
        addFinding("warn", "env", `${target.name} : cle manquante dans .env : ${key}`);
      }
    }
  }
}
```

- [ ] **Step 4 : Lancer les tests, vérifier qu'ils passent**

```bash
bun test scripts/ops/doctor.test.ts
```
Attendu : tous les tests passent, y compris les 2 nouveaux sur `extractEnvKeys`.

- [ ] **Step 5 : Vérifier le comportement réel**

```bash
bun scripts/ops/doctor.ts
```
Vérifier la ligne `env` pour `ops-tools` : comparer avec un diff manuel des clés entre `ops-tools/.env.example` et `ops-tools/.env`. Le résultat doit correspondre exactement (WARN par clé manquante, ou PASS si complet). Vérifier qu'aucune valeur de variable n'apparaît jamais dans la sortie (uniquement des noms de clés).

Nettoyer les rapports de test générés avant de continuer.

- [ ] **Step 6 : Commit**

```bash
git add scripts/ops/doctor.ts scripts/ops/doctor.test.ts
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section env doctor.ts (completude .env par service)

extractEnvKeys() : fonction pure testee (regex ^([A-Z0-9_]+)=,
jamais la valeur). checkEnv() itere sur config.env[] (7 cibles dans
le manifeste), meme logique que doctor.ps1 : FAIL si .env absent,
WARN par cle manquante, PASS si complet.
EOF
)"
```

---

### Task 5 : Section Backlog

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ts` (ajoute `parseChecklist`, `parseBacklogTable`, remplace le corps de `checkBacklog`)
- Modify: `ops-tools/scripts/ops/doctor.test.ts` (ajoute les tests des deux parseurs)

**Interfaces:**
- Consumes : `addFinding`, `FadelConfig` (Task 1).
- Produces : `parseChecklist(content: string): Map<string, { done: number; total: number }>`, `parseBacklogTable(content: string, sectionHeader: string, statusColumnHeader?: string): { done: number; total: number }` (exportées, fonctions pures).

- [ ] **Step 1 : Écrire les tests des deux parseurs (avant l'implémentation)**

Dans `ops-tools/scripts/ops/doctor.test.ts`, ajouter à la fin du fichier :
```typescript
describe("parseChecklist", () => {
  test("counts checked and unchecked items per section", () => {
    const content = [
      "## Project A",
      "- [x] done task",
      "- [ ] pending task",
      "- [x] another done",
      "## Project B",
      "- [ ] only pending",
    ].join("\n");
    const result = parseChecklist(content);
    expect(result.get("Project A")).toEqual({ done: 2, total: 3 });
    expect(result.get("Project B")).toEqual({ done: 0, total: 1 });
  });

  test("ignores lines before the first section header", () => {
    const content = "- [x] orphan\n## Project A\n- [x] real";
    const result = parseChecklist(content);
    expect(result.has("Project A")).toBe(true);
    expect(result.get("Project A")).toEqual({ done: 1, total: 1 });
  });
});

describe("parseBacklogTable", () => {
  const fixture = [
    "## Other Section",
    "| # | Statut |",
    "|---|---|",
    "| 1 | ✅ |",
    "## Vue priorisee",
    "| # | ID | Statut |",
    "|---|---|---|",
    "| 1 | A | ✅ |",
    "| 2 | B | 🔄 |",
    "| 3 | C | ⬜ |",
    "## Next Section",
    "| # | Statut |",
    "|---|---|",
    "| 1 | ✅ |",
  ].join("\n");

  test("counts only the table under the exact target section header", () => {
    const result = parseBacklogTable(fixture, "## Vue priorisee");
    expect(result).toEqual({ done: 1, total: 3 });
  });

  test("returns done=0 total=0 when the section header is not found", () => {
    const result = parseBacklogTable(fixture, "## Nonexistent Section");
    expect(result).toEqual({ done: 0, total: 0 });
  });

  test("returns done=0 total=0 when the Statut column is not present in the table", () => {
    const content = "## Target\n| # | Other |\n|---|---|\n| 1 | x |";
    const result = parseBacklogTable(content, "## Target");
    expect(result).toEqual({ done: 0, total: 0 });
  });
});
```
Ajouter `parseChecklist, parseBacklogTable` à l'import existant en haut du fichier :
```typescript
import { FadelConfigSchema, formatTimestamp, extractEnvKeys, parseChecklist, parseBacklogTable } from "./doctor";
```

- [ ] **Step 2 : Lancer les tests, vérifier qu'ils échouent**

```bash
bun test scripts/ops/doctor.test.ts
```
Attendu : échec à l'import (`parseChecklist`/`parseBacklogTable` n'existent pas encore dans `./doctor`).

- [ ] **Step 3 : Implémenter les deux parseurs et `checkBacklog`**

Dans `ops-tools/scripts/ops/doctor.ts`, ajouter juste avant `async function checkInfra` :
```typescript
export function parseChecklist(content: string): Map<string, { done: number; total: number }> {
  const sections = new Map<string, { done: number; total: number }>();
  let currentSection: string | null = null;

  for (const line of content.split("\n")) {
    const headerMatch = line.match(/^##\s+(.+)$/);
    if (headerMatch) {
      currentSection = headerMatch[1].trim();
      if (!sections.has(currentSection)) {
        sections.set(currentSection, { done: 0, total: 0 });
      }
      continue;
    }
    if (!currentSection) continue;
    const counts = sections.get(currentSection)!;
    if (/^\s*-\s\[x\]/.test(line)) {
      counts.done++;
      counts.total++;
    } else if (/^\s*-\s\[\s\]/.test(line)) {
      counts.total++;
    }
  }

  return sections;
}

export function parseBacklogTable(
  content: string,
  sectionHeader: string,
  statusColumnHeader = "Statut"
): { done: number; total: number } {
  const lines = content.split("\n");
  let active = false;
  let statusColIndex = -1;
  let done = 0;
  let total = 0;

  for (const line of lines) {
    if (line.trimEnd() === sectionHeader) {
      active = true;
      statusColIndex = -1;
      continue;
    }
    if (active && /^##\s/.test(line)) {
      break;
    }
    if (!active) continue;
    if (!/^\s*\|/.test(line)) continue;

    const cells = line
      .trim()
      .replace(/^\||\|$/g, "")
      .split("|")
      .map((c) => c.trim());

    if (statusColIndex === -1) {
      statusColIndex = cells.indexOf(statusColumnHeader);
      continue;
    }

    if (/^-+$/.test(cells[0])) continue;
    if (statusColIndex >= cells.length) continue;

    const statusCell = cells[statusColIndex];
    if (statusCell.includes("✅")) {
      done++;
      total++;
    } else if (/🔄|⬜|🔒/.test(statusCell)) {
      total++;
    }
  }

  return { done, total };
}
```

Remplacer :
```typescript
async function checkBacklog(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 5
}
```
par :
```typescript
async function checkBacklog(config: FadelConfig, workspacesRoot: string): Promise<void> {
  for (const entry of config.backlog) {
    const filePath = path.join(workspacesRoot, ...entry.path.split("/"));

    if (!fs.existsSync(filePath)) {
      addFinding("fail", "backlog", `${entry.name} introuvable (${filePath})`);
      continue;
    }

    const content = fs.readFileSync(filePath, "utf8");

    if (entry.type === "checklist") {
      const sections = parseChecklist(content);
      for (const [section, counts] of sections) {
        if (counts.total === 0) continue;
        addFinding("pass", "backlog", `${entry.name} / ${section} : ${counts.done}/${counts.total} complete`);
      }
    } else {
      const result = parseBacklogTable(content, entry.sectionHeader, entry.statusColumnHeader);
      if (result.total === 0) {
        addFinding("warn", "backlog", `${entry.name} : table introuvable ou vide`);
      } else {
        addFinding("pass", "backlog", `${entry.name} : ${result.done}/${result.total} complete`);
      }
    }
  }
}
```

- [ ] **Step 4 : Lancer les tests, vérifier qu'ils passent**

```bash
bun test scripts/ops/doctor.test.ts
```
Attendu : tous les tests passent (le fixture `parseBacklogTable` vérifie explicitement que les tables "Other Section" et "Next Section" - l'équivalent synthétique du cas réel "Zone | Verdict" de `harness/BACKLOG.md" - ne sont jamais comptées : `total: 3`, pas `5`).

- [ ] **Step 5 : Vérifier le comportement réel sur les 3 fichiers cibles**

```bash
bun scripts/ops/doctor.ts
```
Comparer manuellement les 3 lignes `backlog` produites contre un comptage à la main dans `my-curriculum/docs/UPSKILLING.md`, `harness/BACKLOG.md` (table sous `## Vue priorisée (ordre d'exécution)` uniquement), et `ops-tools/meta/BACKLOG-META.md` (table sous le titre Sprint S1 avec tiret cadratin).

Nettoyer les rapports de test générés avant de continuer.

- [ ] **Step 6 : Commit**

```bash
git add scripts/ops/doctor.ts scripts/ops/doctor.test.ts
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section backlog doctor.ts (2 parseurs, testes)

parseChecklist() et parseBacklogTable() sont des fonctions pures
(separees de l'I/O, contrairement a Get-BacklogTableProgress en V1
qui melangeait lecture fichier et logique), couvertes par bun test
y compris le cas de la table non-pertinente ignoree. checkBacklog()
itere sur config.backlog[] et dispatch par entry.type.
EOF
)"
```

---

### Task 6 : Packaging (Bun compile, Makefile) + validation croisée finale

**Files:**
- Create: `ops-tools/tsconfig.json`
- Modify: `ops-tools/package.json` (ajoute `bin`, `scripts`, `engines`)
- Modify: `ops-tools/Makefile` (target `doctor` pointe vers le binaire compilé)
- Modify: `ops-tools/.gitignore` (ajoute `dist/`)

**Interfaces:**
- Consumes : `ops-tools/scripts/ops/doctor.ts` complet (Tasks 1 à 5).
- Produces : binaire `dist/fadel-ops` (généré, pas versionné), `make doctor` invocable.

- [ ] **Step 1 : Créer `tsconfig.json`**

Créer `ops-tools/tsconfig.json` :
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "types": ["bun"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["scripts/**/*.ts"]
}
```

- [ ] **Step 2 : Compléter `package.json`**

Lire `ops-tools/package.json` (créé par Task 1 via `bun add`), et s'assurer qu'il contient au minimum :
```json
{
  "name": "@fdiene/ops-tools",
  "version": "0.1.0",
  "packageManager": "bun@1.3.14",
  "type": "module",
  "bin": {
    "fadel-ops": "scripts/ops/doctor.ts"
  },
  "scripts": {
    "doctor": "bun scripts/ops/doctor.ts",
    "build:doctor": "bun build --compile --outfile dist/fadel-ops scripts/ops/doctor.ts",
    "test": "bun test"
  },
  "dependencies": {
    "zod": "^3.24.2"
  },
  "devDependencies": {
    "@types/node": "^22.13.10",
    "typescript": "^5.8.2"
  },
  "engines": {
    "bun": ">=1.3.14"
  }
}
```
Ajuster les champs `bin`/`scripts`/`engines`/`packageManager` sans supprimer les dépendances déjà installées par les tâches précédentes (`zod`, `@types/node`, `typescript`) : fusionner, pas écraser. Le package n'est PAS marqué `"private": true` (le spec prévoit un `npm publish` futur, même si non exécuté dans ce chantier).

- [ ] **Step 3 : Vérifier la compilation TypeScript**

```bash
cd ops-tools
bunx tsc --noEmit
```
Attendu : aucune erreur. Si des erreurs de types apparaissent liées à `Bun.$` ou aux globals Bun, vérifier que `@types/node` est bien installé et que `"types": ["bun"]` dans `tsconfig.json` résout correctement (Bun embarque ses propres types depuis la version installée sur cette machine, 1.3.14) - ajuster si nécessaire et documenter l'ajustement dans le rapport de tâche.

- [ ] **Step 4 : Ajouter `dist/` au `.gitignore`**

Dans `ops-tools/.gitignore`, ajouter une ligne `dist/` (section "Generated outputs" existante, à côté de `logs/`, `reports/`, `.cache/`).

- [ ] **Step 5 : Compiler le binaire et vérifier son architecture**

```bash
bun run build:doctor
ls -la dist/fadel-ops
```
Vérifier que le binaire est bien x64 (pas 32-bit) :
```bash
python3 -c "
import struct
with open('dist/fadel-ops','rb') as f:
    data = f.read(1024)
pe = struct.unpack('<I', data[0x3c:0x40])[0]
machine = struct.unpack('<H', data[pe+4:pe+6])[0]
print('machine field:', hex(machine), '(0x8664=x64 attendu)')
"
```

- [ ] **Step 6 : Mettre à jour le target `doctor` du Makefile**

Dans `ops-tools/Makefile`, remplacer :
```makefile
doctor:
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/ops/doctor.ps1
```
par :
```makefile
doctor:
	@dist/fadel-ops
```
Ne pas toucher au reste du Makefile (`.PHONY`, `help`, les autres targets restent identiques - `doctor` y figure déjà depuis la V1).

- [ ] **Step 7 : Validation croisée V1/V2 sur l'état réel du parc**

Lancer la V1 directement (comme documenté dans son propre plan) :
```bash
powershell.exe -NoProfile -File scripts/ops/doctor.ps1 > /tmp/doctor-v1-output.txt 2>&1
```
Lancer la V2 via le nouveau target Makefile :
```bash
make doctor > /tmp/doctor-v2-output.txt 2>&1
```
Comparer les findings des deux sorties (ignorer les horodatages de rapport et le chemin exact du fichier `.md`, qui diffèrent nécessairement) : pour chaque ligne `[SEVERITY] category message`, vérifier qu'elle a un équivalent dans l'autre sortie. Toute divergence de contenu (un conteneur PASS d'un côté et FAIL de l'autre, un ratio de backlog différent, une clé `.env` manquante signalée par l'un et pas l'autre) est un bug réel à identifier et corriger avant de considérer la tâche terminée - pas un écart à accepter tel quel.

Nettoyer les rapports de test générés par cette étape (V1 et V2) avant de continuer.

- [ ] **Step 8 : Commit**

```bash
git add tsconfig.json package.json Makefile .gitignore bun.lock 2>/dev/null
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): packaging doctor.ts (bun build --compile) + make doctor

package.json avec bin fadel-ops et script build:doctor (bun build
--compile), tsconfig.json pour le typecheck. Makefile : target
doctor pointe desormais vers le binaire compile dist/fadel-ops
(verifie x64, elimine le bug WOW64 de la V1 structurellement).
doctor.ps1 conserve tel quel (pas de retrait dans ce chantier).

Validation croisee effectuee : doctor.ps1 et doctor.ts produisent
les memes findings sur le meme etat reel du parc.
EOF
)"
```

---

## Self-Review (effectué par l'auteur du plan avant remise)

**Couverture du spec** : les 3 piliers (manifeste + schéma Zod, `doctor.ts` avec les 4 sections et la même logique métier que la V1, packaging Bun + Makefile) sont chacun couverts par au moins une tâche. Le point du spec sur la distinction entre l'artefact `bun build --compile` (usage interne) et l'artefact npm (`bin` pointant vers la source, pas le binaire) est respecté : le `package.json` de la Task 6 configure `bin` vers `scripts/ops/doctor.ts`, jamais vers `dist/fadel-ops`. Le fichier `fadel-os.config.schema.json` (JSON Schema séparé) mentionné dans le spec n'est délibérément pas créé dans ce plan - décision documentée dans les Global Constraints, pas un oubli.

**Cohérence des types/noms** : `FadelConfig`, `Severity`, `Finding`, `addFinding`, `toShellPath`, `resolveWorkspacesRoot`, `formatTimestamp` sont définis une seule fois (Task 1) et réutilisés à l'identique (même nom, même signature) dans toutes les tâches suivantes. `parseChecklist`/`parseBacklogTable`/`extractEnvKeys` sont chacune définies et testées dans la tâche qui les introduit, puis consommées uniquement par la fonction `check*` correspondante dans la même tâche - pas de dépendance croisée inattendue entre sections.

**Pas de placeholder** : chaque step contient du code complet et exécutable. Le seul texte entre crochets dans le manifeste JSON (Task 1) est une note explicative hors du bloc de code lui-même, pas un placeholder dans le code à exécuter.
