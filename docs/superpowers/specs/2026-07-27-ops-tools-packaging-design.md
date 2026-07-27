# ops-tools packaging : manifeste config-driven + doctor.ts + binaire Bun

Statut : décisions actées avec l'utilisateur le 2026-07-27 (Fractional CTO / Staff Architect, périmètre ops-tools). Fait suite à la V1 PowerShell de `ops doctor` (livrée et poussée le 2026-07-24, voir `2026-07-24-ops-doctor-design.md`).

## Décisions actées avant rédaction

- **Variable d'environnement** : `WORKSPACES_ROOT` (pas de nouveau nom `FADEL_OS_ROOT`). Même variable que `scripts/maintenance/*.sh` et `scripts/ops/doctor.ps1` : aucune migration, aucun doublon de sens.
- **Portée du rewrite** : `doctor.ts` reste un script autonome (`scripts/ops/doctor.ts`), pas le squelette d'un CLI `commander.js` complet (`ops run|repo|setup|doctor|dev`). Ce squelette reste un chantier ultérieur distinct, à faire quand les autres commandes existeront réellement.
- **Spike de dérisquage exécuté avant ce document** (voir section "Résultats du spike" ci-dessous) : deux découvertes concrètes qui conditionnent la conception, pas des suppositions.

## Résultats du spike (fait, pas supposé)

Un script `.ts` minimal appelant `ssh.exe` via `Bun.$`, compilé via `bun build --compile`, lancé directement et via `make` (le même `make.exe` 32-bit qui causait le bug WOW64 de la V1 PowerShell) :

1. **Piège réel trouvé** : `Bun.$` (le shell intégré de Bun) traite le backslash comme caractère d'échappement dans le template shell. Un chemin Windows interpolé tel quel (`C:\Windows\System32\OpenSSH\ssh.exe`) est corrompu avant exécution (`bun: command not found: C:WindowsSystem32OpenSSHssh.exe`, les backslashes sont avalés). **Règle actée pour tout le code de ce chantier : tout chemin Windows interpolé dans un template `` $`...` `` doit utiliser des slashs (`C:/Windows/System32/OpenSSH/ssh.exe`), jamais des backslashes.**
2. **Bug WOW64 de la V1 structurellement éliminé** : un binaire produit par `bun build --compile` cible x64 par défaut sur cette machine (vérifié par inspection de l'en-tête PE, champ machine `0x8664`). Invoqué par le `make.exe` 32-bit, il tourne comme un vrai process 64-bit (contrairement à `powershell.exe`, que `make` résolvait vers sa variante 32-bit sous redirection WOW64). `ssh.exe` se résout donc correctement sans contournement `Sysnative`/`[Environment]::Is64BitProcess` : ce correctif de la V1 PowerShell n'a pas d'équivalent nécessaire en V2.

Conséquence directe : les 4 bugs Windows-spécifiques trouvés en V1 (`ErrorActionPreference`, `2>&1` devenant une exception terminante, absence de BOM cassant le parsing PS 5.1, redirection WOW64) sont tous des pathologies propres à PowerShell 5.1 ou à l'invocation d'un interpréteur de script par un process 32-bit. Un binaire Bun compilé les élimine structurellement. Le seul piège Windows propre à Bun découvert par le spike (backslash dans `Bun.$`) est documenté et contourné ci-dessus.

---

## Pilier 1 : `fadel-os.config.json`

### Emplacement et rôle

Fichier JSON à la racine du monorepo (`$WORKSPACES_ROOT/fadel-os.config.json`), Single Source of Truth pour tout ce que `doctor.ts` (et les futures commandes `ops`) doit connaître sur la topologie du parc. Remplace les listes codées en dur de la V1 (les 9 conteneurs, les 7 couples repo/`.env.example`, les 2 cibles de backlog).

**Principe non négociable, hérité de la V1** : ce manifeste reste une liste explicite, pas une découverte automatique. La V1 a explicitement écarté l'auto-discovery pour les mêmes raisons (traçabilité, review possible en revue de code, pas de comportement surprise si un fichier apparaît/disparaît). Le manifeste externalise la donnée hors du code, il ne change pas la philosophie.

### Schéma

```json
{
  "$schema": "./fadel-os.config.schema.json",
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
      "sectionHeader": "## Sprint S1 [tiret cadratin réel] Mise en service harness (juillet 2026)",
      "statusColumnHeader": "Statut"
    }
  ]
}
```

Note sur le `sectionHeader` du dernier bloc : dans le fichier JSON réel, cette chaîne contient le caractère tiret cadratin tel quel (JSON gère nativement l'UTF-8, aucun contournement type `[char]0x2014` n'est nécessaire ici contrairement au PowerShell de la V1 - c'est de la donnée, pas du code source). Dans ce document, le caractère est décrit plutôt que reproduit littéralement, pour respecter la règle de rédaction du projet ; le fichier `fadel-os.config.json` réel, lui, doit contenir le caractère exact copié depuis `ops-tools/meta/BACKLOG-META.md`, sans quoi le parseur ne matchera rien (`Total: 0`, comme documenté en V1).

### Contraintes de schéma

- Toutes les valeurs `path` sont relatives à `$WORKSPACES_ROOT`.
- `backlog[].sectionHeader` doit matcher **exactement** (après `trim`) une ligne `##` réelle du fichier ciblé - aucune tolérance de casse ou d'espace, comme en V1 (le risque n'est pas une erreur bruyante mais un total silencieux à 0, déjà rencontré en V1 et corrigé en revue).
- `backlog[].type` détermine quel parseur s'applique (`checklist` = cases à cocher markdown, `table` = machine à états sur table ciblée par titre). Un troisième type n'est pas anticipé tant qu'aucun besoin réel ne le justifie (YAGNI).
- Validation du schéma au chargement via Zod (déjà utilisé dans `harness/mcp-server`, cohérent avec l'écosystème) : `doctor.ts` doit refuser de démarrer avec un message clair si le manifeste est structurellement invalide, plutôt que d'échouer plus loin avec une erreur opaque.

---

## Pilier 2 : `doctor.ts`

### Architecture

Fichier unique `ops-tools/scripts/ops/doctor.ts`, même granularité que la V1 (`doctor.ps1` était aussi un fichier unique, suivant la convention du repo). Mêmes 4 sections logiques (Infra, MCP, Env, Backlog), même moteur de findings, même sortie (résumé console coloré + rapport Markdown horodaté dans `meta/rex/doctor_<timestamp>.md`), même règle de sécurité (les valeurs de variables d'environnement ne sont jamais lues au-delà du nom de clé).

Différence structurelle : chaque section itère désormais sur les entrées du manifeste chargé, au lieu d'une liste codée en dur.

```typescript
type Severity = "pass" | "warn" | "fail";

interface Finding {
  severity: Severity;
  category: string;
  message: string;
}

const findings: Finding[] = [];
const scores = { pass: 0, warn: 0, fail: 0 };

function addFinding(severity: Severity, category: string, message: string) {
  findings.push({ severity, category, message });
  scores[severity]++;
}
```

### Simplification apportée par TypeScript (pas un simple portage 1:1)

En PowerShell 5.1, l'isolation par section dépendait d'un réglage global fragile (`$ErrorActionPreference = "Stop"`, corrigé en cours de route en V1) pour que les erreurs non-terminales déclenchent bien le `catch`. En JavaScript/TypeScript, une exception est toujours une exception : un `try/catch` par section fonctionne nativement, sans réglage global à retenir ni piège equivalent. C'est un vrai gain de robustesse du rewrite, pas seulement un changement de syntaxe.

```typescript
for (const section of ["infra", "mcp", "env", "backlog"] as const) {
  try {
    await runSection(section, config, workspacesRoot);
  } catch (err) {
    addFinding("fail", section, `Section ${section} : erreur inattendue (${(err as Error).message})`);
  }
}
```

### Section Infra

Utilise `Bun.$` pour l'appel SSH natif, avec la règle du spike (slashs, jamais de backslash dans le chemin interpolé) :

```typescript
async function checkInfra(config: FadelConfig): Promise<void> {
  const sshExe = "C:/Windows/System32/OpenSSH/ssh.exe";
  const dockerCmd = `docker ps --filter network=${config.infra.dockerNetwork} --format '{{json .}}'`;

  let sshOutput: string;
  try {
    sshOutput = await $`${sshExe} -o BatchMode=yes -o ConnectTimeout=5 ${config.infra.sshHost} ${dockerCmd}`.text();
  } catch {
    addFinding("fail", "infra", `VPS ${config.infra.sshHost} injoignable`);
    return; // le reste de la section s'arrete la, comme en V1
  }
  // ... parsing JSON Lines + classification, cf. paragraphe suivant
}
```

Parsing JSON Lines identique en logique à la V1 (un objet JSON par ligne, pas un tableau), classification `running`/`healthy`/`unhealthy` sur les mêmes champs `State`/`Status` (pas de champ `Health` séparé, confirmé en V1 et toujours vrai côté Docker CLI, indépendant du langage appelant).

### Section MCP, Env, Backlog

Logique métier identique à la V1 section par section (comparaison `mtime` build vs source pour MCP, diff de clés `.env.example` vs `.env` pour Env, les deux parseurs Markdown pour Backlog), portée en TypeScript, itérant sur `config.mcp[]` / `config.env[]` / `config.backlog[]` au lieu des listes en dur. Le parseur de table Markdown (machine à états) et le parseur de cases à cocher sont des fonctions pures testables indépendamment (voir Stratégie de test) - un gain direct par rapport à la V1, où `Get-BacklogTableProgress` n'était testable qu'en exécutant le script entier.

### Ce qui ne change pas

- Le rapport Markdown reste dans `meta/rex/doctor_<timestamp>.md`, même format de table, même ligne de score finale.
- Aucune valeur de variable d'environnement n'est jamais loggée, en Env comme en V1.
- Le script reste en lecture seule sur le parc (aucune écriture hors de son propre rapport).

---

## Pilier 3 : Packaging Bun

### Deux artefacts distincts, pas un seul

**Usage interne quotidien** : `bun build --compile --outfile dist/fadel-ops scripts/ops/doctor.ts`, binaire autonome (~95-100 Mo d'après le spike, le runtime Bun est embarqué), aucune installation requise, cible x64 Windows par défaut sur cette machine. C'est le binaire qu'on lance au quotidien via `make doctor`.

**Publication npm** (`@fdiene/ops-tools`) : un package normal, PAS le binaire compilé. Le champ `bin` du `package.json` pointe vers le fichier `.ts`/`.js` source, exécuté via Node ou Bun au runtime par qui installe le package (`npm install -g @fdiene/ops-tools`). Embarquer un binaire de ~100 Mo dans un package npm n'est pas idiomatique et alourdit inutilement le registre. Les deux artefacts partagent le même code source (`scripts/ops/doctor.ts`), mais leur mode de distribution diffère.

### Résolution de chemin au runtime

```typescript
import os from "node:os";
import path from "node:path";

const workspacesRoot =
  process.env.WORKSPACES_ROOT ?? path.join(os.homedir(), "git", "Workspaces");

const configPath = path.join(workspacesRoot, "fadel-os.config.json");
```

Même convention que `scripts/maintenance/*.sh` et `scripts/ops/doctor.ps1` (V1) : variable d'environnement avec repli sur le chemin par défaut de cette machine. Si `fadel-os.config.json` est absent à ce chemin, le script doit échouer immédiatement avec un message explicite (chemin recherché affiché), pas une erreur de parsing JSON opaque plus loin.

### `package.json` (extrait, cohérent avec le précédent `my-curriculum`)

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
  "devDependencies": {
    "@types/node": "^22.13.10",
    "typescript": "^5.8.2",
    "zod": "^3.24.2"
  },
  "engines": {
    "bun": ">=1.3.14"
  }
}
```

### Makefile

Le target `doctor` de la V1 (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/ops/doctor.ps1`) est remplacé par l'appel au binaire compilé :

```makefile
doctor:
	@dist/fadel-ops
```

`doctor.ps1` (V1) n'est pas supprimé tant que `doctor.ts` n'a pas tourné en parallèle sur au moins quelques exécutions réelles pour validation croisée (voir Stratégie de test) - cohérent avec la doctrine anti-scope-creep du projet (pas de rupture avant preuve que le remplacement tient).

---

## Fichiers impactés

| Fichier | Action |
|---|---|
| `fadel-os.config.json` | Créer (racine du monorepo, hors `ops-tools/`) |
| `fadel-os.config.schema.json` | Créer (schéma Zod exporté ou JSON Schema, pour validation IDE) |
| `ops-tools/scripts/ops/doctor.ts` | Créer |
| `ops-tools/package.json` | Créer |
| `ops-tools/tsconfig.json` | Créer (même structure que `harness/mcp-server/tsconfig.json`, `module`/`target` adaptés à Bun) |
| `ops-tools/scripts/ops/doctor.test.ts` | Créer (parseurs purs) |
| `ops-tools/Makefile` | Modifier (target `doctor` pointe vers le binaire compilé) |
| `ops-tools/scripts/ops/doctor.ps1` | Conserver en l'état, retrait différé (voir ci-dessus) |
| `ops-tools/.gitignore` | Modifier (ajouter `dist/`) |

---

## Stratégie de test

Gain direct du passage à TypeScript/Bun : `bun test` est un vrai test runner, contrairement à la V1 où l'absence de Pester était une convention assumée du repo, pas un choix scalable.

- **Unitaires (`bun test`)**, sur les fonctions pures uniquement, sans toucher au réseau ou au système de fichiers réel : le parseur de table Markdown (cas nominal, cas "table non trouvée", cas "colonne Statut absente", cas de la table non-pertinente à ignorer - le même cas `Zone | Verdict` que la V1 a dû vérifier manuellement), le parseur de cases à cocher, le diff de clés `.env.example`/`.env`, la validation Zod du manifeste (schéma valide / invalide).
- **Manuel, comme en V1**, pour tout ce qui touche un système réel (SSH+Docker sur le VPS, `git log`, lecture de fichiers réels du monorepo) : ce ne sont pas des comportements à mocker (cohérent avec la culture de revue de ce projet - "tests verify real behavior, not mocks"), mais à vérifier en conditions réelles, documenté dans un rapport comme en V1.
- **Validation croisée V1/V2** : avant de retirer `doctor.ps1`, lancer les deux sur le même état du parc et comparer les findings ligne à ligne. Divergence = bug dans l'un des deux, pas un cas à trancher à l'aveugle.

---

## Hors périmètre (ce chantier)

- Pas de squelette CLI `commander.js` complet (`ops run|repo|setup|doctor|dev`) - décision actée, `doctor.ts` reste autonome.
- Pas de renommage `WORKSPACES_ROOT` → `FADEL_OS_ROOT` - décision actée, une seule variable dans tout l'écosystème.
- Pas de retrait immédiat de `doctor.ps1` - retrait différé après validation croisée.
- Pas de publication npm effective dans ce chantier (le `package.json`/`bin` sont préparés, mais `npm publish` reste une étape manuelle explicite ultérieure, cohérente avec la doctrine "pas de publication sans revue finale" déjà appliquée à `ops doctor` V1).
- Pas de découverte automatique de conteneurs/`.env.example`/backlogs pour peupler le manifeste - reste une liste explicite maintenue à la main, comme en V1.
