# ops doctor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer `ops doctor`, un preflight check unique en PowerShell qui valide en une commande (`make doctor`) la sante infra (VPS + Docker), le statut du serveur MCP harness, la completude des `.env` par service, et l'avancement des backlogs actifs de l'ecosysteme Fadel OS.

**Architecture:** Un script PowerShell autonome (`scripts/ops/doctor.ps1`) qui accumule des findings `(Severity, Category, Message)` via une fonction `Add-Finding`, dans 4 sections independantes isolees par `try/catch` (Infra, MCP, Env, Backlog), puis affiche un resume console colore et ecrit un rapport Markdown horodate dans `meta/rex/`. Integre au Makefile existant via un nouveau target `doctor`.

**Tech Stack:** Windows PowerShell 5.1 (`powershell.exe`, pas `pwsh`), zero dependance externe. SSH natif Windows (`C:\Windows\System32\OpenSSH\ssh.exe`). Pas de suite Pester (coherent avec les 3 scripts d'audit existants du repo).

## Global Constraints

- V1 = CLI local uniquement. Pas de nouvelle UI web, pas de nouvelle base de donnees, pas de nouveau service permanent.
- Zero dependance externe nouvelle : uniquement des cmdlets PowerShell natives (`Get-Content`, `Test-Path`, `ConvertFrom-Json`, `Get-ChildItem`, l'operateur d'appel `&`).
- Les valeurs de variables d'environnement ne sont jamais lues au-dela du nom de la cle (regex `^([A-Z0-9_]+)=`, jamais la partie apres `=`) ; aucune valeur n'apparait jamais dans un finding, un log ou le rapport.
- SSH natif Windows uniquement : `C:\Windows\System32\OpenSSH\ssh.exe` (chemin complet, jamais un `ssh` resolu depuis le PATH qui pourrait pointer vers le binaire Git Bash/MSYS).
- Chaque section (Infra, MCP, Env, Backlog) est isolee par son propre `try/catch` : l'echec d'une section ne bloque jamais l'execution des autres.
- Si le VPS `seo-prod` est injoignable en SSH : un seul finding `FAIL`, la section Infra s'arrete la (pas de findings supplementaires pour cette section), les autres sections s'executent normalement.
- Pas de suite Pester en V1. Validation par execution manuelle du script et lecture des findings/rapport.
- `Get-Content` sur tout fichier Markdown contenant des caracteres accentues doit utiliser `-Encoding UTF8` explicitement (bug deja rencontre et corrige dans ce repo : commit `275e04a fix(notion): Get-Content -Encoding UTF8 pour eviter la corruption des accents`).
- Jamais de tiret cadratin (`—`) dans les commentaires, messages ou docs ecrits pour ce plan. Exception explicite : les constantes de chaine qui doivent matcher un titre Markdown existant contenant deja un tiret cadratin dans le fichier source (`ops-tools/meta/BACKLOG-META.md`) sont copiees telles quelles, car un changement de caractere casserait le parsing. Chaque cas est annote d'un commentaire `# NE PAS MODIFIER : doit matcher le titre exact du fichier source`.
- Avant tout commit : montrer le `git diff` et resumer les changements (regle du repo).

---

### Task 1 : Socle, moteur de findings et rapport

**Files:**
- Create: `ops-tools/scripts/ops/doctor.ps1`

**Interfaces:**
- Consumes : rien (premiere tache).
- Produces :
  - Parametre `$WorkspacesRoot` (string, racine du monorepo, resolu via `WORKSPACES_ROOT` env var ou fallback `$env:USERPROFILE\git\Workspaces`).
  - Variable script-scope `$WorkspacesRoot`, `$OpsToolsRoot` (= `$WorkspacesRoot\ops-tools`).
  - Fonction `Add-Finding($severity, $category, $message)` : ajoute `[pscustomobject]@{ Severity; Category; Message }` a `$script:findings` et incremente `$script:scores[$severity]`.
  - 4 blocs `try/catch` vides marques par des commentaires d'ancrage exacts : `# --- Section Infra ---` (Task 2), `# --- Section MCP ---` (Task 3), `# --- Section Env ---` (Task 4), `# --- Section Backlog ---` (Task 5). Chaque tache suivante localise son commentaire d'ancrage et remplace le corps du `try` (actuellement un commentaire `# Remplie par Task N`).
  - Bloc final "Report" qui trie `$findings` par `Severity, Category`, affiche en console colore (Green=pass, Yellow=warn, Red=fail), affiche le score `PASS/WARN/FAIL`, ecrit `meta/rex/doctor_<timestamp>.md` (timestamp UTC format `yyyyMMddTHHmmssZ`), et retourne le code de sortie (1 si au moins un FAIL, 0 sinon).

- [ ] **Step 1 : Creer le script avec le moteur de findings, le squelette des 4 sections, et le rapport**

Creer `ops-tools/scripts/ops/doctor.ps1` :

```powershell
# doctor.ps1
# Preflight check unique pour l'ecosysteme Fadel OS : infra, MCP, completude .env, avancement backlogs.
# Usage: & ".\scripts\ops\doctor.ps1"  (depuis ops-tools/)
#    ou: make doctor

param(
    [string]$WorkspacesRoot = $(if ($env:WORKSPACES_ROOT) { $env:WORKSPACES_ROOT } else { Join-Path $env:USERPROFILE "git\Workspaces" })
)

$ErrorActionPreference = "Continue"
$OpsToolsRoot = Join-Path $WorkspacesRoot "ops-tools"

$script:findings = @()
$script:scores = @{ pass = 0; warn = 0; fail = 0 }

function Add-Finding($severity, $category, $message) {
    $script:findings += [pscustomobject]@{ Severity = $severity; Category = $category; Message = $message }
    $script:scores[$severity]++
}

Write-Host "`n=== ops doctor ===" -ForegroundColor Cyan
Write-Host "Workspaces: $WorkspacesRoot`n"

if (Test-Path $WorkspacesRoot) {
    Add-Finding "pass" "bootstrap" "Workspaces root resolu : $WorkspacesRoot"
} else {
    Add-Finding "fail" "bootstrap" "Workspaces root introuvable : $WorkspacesRoot"
}

# --- Section Infra ---
Write-Host "--- Infra ---" -ForegroundColor Yellow
try {
    # Remplie par Task 2
} catch {
    Add-Finding "fail" "infra" "Section infra : erreur inattendue ($($_.Exception.Message))"
}

# --- Section MCP ---
Write-Host "`n--- MCP ---" -ForegroundColor Yellow
try {
    # Remplie par Task 3
} catch {
    Add-Finding "fail" "mcp" "Section mcp : erreur inattendue ($($_.Exception.Message))"
}

# --- Section Env ---
Write-Host "`n--- Env ---" -ForegroundColor Yellow
try {
    # Remplie par Task 4
} catch {
    Add-Finding "fail" "env" "Section env : erreur inattendue ($($_.Exception.Message))"
}

# --- Section Backlog ---
Write-Host "`n--- Backlog ---" -ForegroundColor Yellow
try {
    # Remplie par Task 5
} catch {
    Add-Finding "fail" "backlog" "Section backlog : erreur inattendue ($($_.Exception.Message))"
}

# --- Report ---
Write-Host "`n=== Findings ($($findings.Count)) ===" -ForegroundColor Cyan
$findings | Sort-Object Severity, Category | ForEach-Object {
    $color = switch ($_.Severity) { "pass" { "Green" } "warn" { "Yellow" } "fail" { "Red" } default { "White" } }
    Write-Host ("  [{0,4}] {1,-10} {2}" -f $_.Severity.ToUpper(), $_.Category, $_.Message) -ForegroundColor $color
}

Write-Host "`n=== Score ===" -ForegroundColor Cyan
Write-Host "  PASS: $($scores.pass)  WARN: $($scores.warn)  FAIL: $($scores.fail)"

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$outFile = Join-Path $OpsToolsRoot "meta\rex\doctor_$timestamp.md"
$md = @(
    "# ops doctor - $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "",
    "| Severity | Category | Message |",
    "|---|---|---|"
)
foreach ($f in ($findings | Sort-Object Severity, Category)) {
    $msg = $f.Message -replace '\|', '/'
    $md += "| $($f.Severity) | $($f.Category) | $msg |"
}
$md += ""
$md += "**Score:** PASS=$($scores.pass) WARN=$($scores.warn) FAIL=$($scores.fail)"
$md -join "`n" | Set-Content $outFile -Encoding UTF8
Write-Host "`nRapport: $outFile" -ForegroundColor Green

if ($scores.fail -gt 0) { exit 1 }
exit 0
```

- [ ] **Step 2 : Verifier que le squelette s'execute correctement**

Depuis `ops-tools/` :
```
powershell.exe -NoProfile -File scripts\ops\doctor.ps1
```
Sortie attendue : `=== ops doctor ===`, `Workspaces: C:\Users\delfa\git\Workspaces`, sections Infra/MCP/Env/Backlog vides (rien affiche entre les titres), `=== Findings (1) ===` avec la ligne `[PASS] bootstrap Workspaces root resolu : ...`, `=== Score ===` avec `PASS: 1  WARN: 0  FAIL: 0`, une ligne `Rapport: ...\meta\rex\doctor_<timestamp>.md`. Code de sortie `0` (verifier avec `echo $LASTEXITCODE` juste apres, doit afficher `0`).

- [ ] **Step 3 : Verifier le cas d'echec du bootstrap**

```
powershell.exe -NoProfile -File scripts\ops\doctor.ps1 -WorkspacesRoot "C:\chemin\bidon"
```
Sortie attendue : `[FAIL] bootstrap Workspaces root introuvable : C:\chemin\bidon`, score `FAIL: 1`, code de sortie `1` (`echo $LASTEXITCODE` doit afficher `1`).

- [ ] **Step 4 : Verifier le rapport Markdown genere**

Ouvrir le fichier `ops-tools\meta\rex\doctor_<timestamp>.md` du Step 2 (`Get-Content` ou lecture directe) : doit contenir un titre `# ops doctor - <date>`, une table avec l'en-tete `| Severity | Category | Message |`, une ligne `| pass | bootstrap | Workspaces root resolu : ... |`, et la ligne finale `**Score:** PASS=1 WARN=0 FAIL=0`.

- [ ] **Step 5 : Nettoyer les rapports de test et commit**

```bash
cd ops-tools
rm meta/rex/doctor_*.md
git add scripts/ops/doctor.ps1
git status
```
Afficher le `git diff --cached` avant de committer, puis :
```bash
git commit -m "$(cat <<'EOF'
feat(ops): socle ops doctor (moteur findings + squelette 4 sections)

Script scripts/ops/doctor.ps1 : fonction Add-Finding, resolution
WorkspacesRoot via WORKSPACES_ROOT (meme convention que
scripts/maintenance/*.sh), squelette try/catch pour les 4 sections
(Infra/MCP/Env/Backlog) rempli dans les taches suivantes, rapport
Markdown horodate dans meta/rex/doctor_<timestamp>.md + resume
console colore.
EOF
)"
```

---

### Task 2 : Section Infra (Docker via SSH)

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ps1` (remplace le commentaire `# Remplie par Task 2` sous `# --- Section Infra ---`)

**Interfaces:**
- Consumes : `Add-Finding` (Task 1), `$WorkspacesRoot` (Task 1).
- Produces : findings de categorie `infra` (aucune autre tache n'en depend directement).

- [ ] **Step 1 : Implementer la section Infra**

Dans `ops-tools/scripts/ops/doctor.ps1`, remplacer :
```powershell
try {
    # Remplie par Task 2
} catch {
    Add-Finding "fail" "infra" "Section infra : erreur inattendue ($($_.Exception.Message))"
}
```
(sous `# --- Section Infra ---`) par :
```powershell
try {
    $sshExe = "C:\Windows\System32\OpenSSH\ssh.exe"
    $dockerCmd = "docker ps --filter network=seo-prod-network --format '{{json .}}'"
    $sshOutput = & $sshExe -o BatchMode=yes -o ConnectTimeout=5 seo-prod $dockerCmd 2>&1
    $sshExitCode = $LASTEXITCODE

    if ($sshExitCode -ne 0) {
        Add-Finding "fail" "infra" "VPS seo-prod injoignable (ssh exit code $sshExitCode)"
    } else {
        $expectedContainers = @(
            "prod-traefik", "prod-n8n", "prod-seo-directus", "prod-seo-agents",
            "prod-seo-postgres", "prod-seo-redis", "prod-seo-qdrant", "prod-n8n-postgres",
            "profile-api"
        )

        $runningContainers = @{}
        foreach ($line in ($sshOutput -split "`n")) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            try {
                $obj = $trimmed | ConvertFrom-Json
                $runningContainers[$obj.Names] = $obj
            } catch {
                continue
            }
        }

        foreach ($name in $expectedContainers) {
            if (-not $runningContainers.ContainsKey($name)) {
                Add-Finding "fail" "infra" "$name : conteneur introuvable sur seo-prod-network"
                continue
            }
            $c = $runningContainers[$name]
            if ($c.State -ne "running") {
                Add-Finding "fail" "infra" "$name : arrete (etat=$($c.State))"
            } elseif ($c.Status -match "\(unhealthy\)") {
                Add-Finding "warn" "infra" "$name : running mais unhealthy"
            } else {
                Add-Finding "pass" "infra" "$name : running ($($c.Status))"
            }
        }
    }
} catch {
    Add-Finding "fail" "infra" "Section infra : erreur inattendue ($($_.Exception.Message))"
}
```

Note technique importante : `docker ps --format '{{json .}}'` produit du JSON Lines (un objet JSON par ligne de sortie), pas un tableau JSON unique. C'est pourquoi le code separe `$sshOutput` par `` `n `` et parse chaque ligne independamment. Le champ `Names` (pluriel, cle exacte de la sortie Docker) contient le nom du conteneur ; il n'y a pas de champ `Health` separe, l'info sante est encodee dans la chaine `Status` (ex. `"Up 3 days (healthy)"`).

- [ ] **Step 2 : Verifier le cas VPS joignable**

Depuis `ops-tools/` :
```
powershell.exe -NoProfile -File scripts\ops\doctor.ps1
```
Verifier manuellement en parallele :
```
C:\Windows\System32\OpenSSH\ssh.exe -o BatchMode=yes -o ConnectTimeout=5 seo-prod "docker ps --filter network=seo-prod-network --format '{{.Names}}\t{{.Status}}'"
```
Comparer : chaque conteneur liste manuellement avec un statut `Up ...` doit apparaitre en `PASS` (ou `WARN` si `(unhealthy)` est present) dans la sortie de `doctor.ps1`, section Infra. Tout conteneur de la liste attendue absent de la sortie manuelle doit apparaitre en `FAIL` dans `doctor.ps1`.

- [ ] **Step 3 : Verifier le cas VPS injoignable (degradation)**

Simuler une indisponibilite en pointant temporairement vers un host SSH inconnu (modifier temporairement `seo-prod` en `seo-prod-test-unreachable` dans une copie locale de la ligne, sans commit) ou en coupant le VPN/reseau si applicable, puis relancer le script : verifier une seule ligne `[FAIL] infra VPS seo-prod injoignable (ssh exit code N)`, aucune autre ligne `infra`, et les sections MCP/Env/Backlog s'executent quand meme normalement (pas de `[FAIL] ... erreur inattendue` en cascade). Annuler la modification temporaire avant de continuer.

- [ ] **Step 4 : Commit**

```bash
cd ops-tools
git add scripts/ops/doctor.ps1
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section infra ops doctor (docker ps via SSH natif)

SSH natif Windows (ssh.exe, jamais celui de Git Bash) vers seo-prod,
docker ps filtre sur seo-prod-network, parsing JSON Lines. Liste des
9 conteneurs attendus codee en dur. VPS injoignable = 1 FAIL et skip
de la section, les autres sections continuent.
EOF
)"
```

---

### Task 3 : Section MCP (build + config harness)

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ps1` (remplace le commentaire `# Remplie par Task 3` sous `# --- Section MCP ---`)

**Interfaces:**
- Consumes : `Add-Finding` (Task 1), `$WorkspacesRoot` (Task 1).
- Produces : findings de categorie `mcp`.

- [ ] **Step 1 : Implementer la section MCP**

Dans `ops-tools/scripts/ops/doctor.ps1`, remplacer :
```powershell
try {
    # Remplie par Task 3
} catch {
    Add-Finding "fail" "mcp" "Section mcp : erreur inattendue ($($_.Exception.Message))"
}
```
(sous `# --- Section MCP ---`) par :
```powershell
try {
    $mcpServerRoot = Join-Path $WorkspacesRoot "harness\mcp-server"
    $distIndex = Join-Path $mcpServerRoot "dist\index.js"
    $srcDir = Join-Path $mcpServerRoot "src"

    if (-not (Test-Path $distIndex)) {
        Add-Finding "warn" "mcp" "harness : dist/index.js absent (build jamais lance)"
    } else {
        $distTime = (Get-Item $distIndex).LastWriteTimeUtc
        $srcFiles = Get-ChildItem -Path $srcDir -Recurse -File -ErrorAction SilentlyContinue
        $newestSrcTime = ($srcFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
        if ($newestSrcTime -and $newestSrcTime -gt $distTime) {
            Add-Finding "warn" "mcp" "harness : build obsolete (dist/ plus ancien que src/)"
        } else {
            Add-Finding "pass" "mcp" "harness : build a jour (dist/index.js)"
        }
    }

    $cursorMcpJson = Join-Path $WorkspacesRoot "harness\.cursor\mcp.json"
    if (Test-Path $cursorMcpJson) {
        $mcpConfig = Get-Content $cursorMcpJson -Raw | ConvertFrom-Json
        $harnessServer = $mcpConfig.mcpServers.harness
        $referencedPath = $null
        if ($harnessServer) {
            $referencedPath = $harnessServer.args | Where-Object { $_ -match "index\.js$" } | Select-Object -First 1
        }
        if ($referencedPath -and (Test-Path $referencedPath)) {
            Add-Finding "pass" "mcp" "harness : mcp.json pointe vers un dist/index.js existant ($referencedPath)"
        } elseif ($referencedPath) {
            Add-Finding "warn" "mcp" "harness : mcp.json pointe vers un chemin introuvable ($referencedPath)"
        } else {
            Add-Finding "warn" "mcp" "harness : mcp.json ne reference pas index.js pour le serveur harness"
        }
    } else {
        Add-Finding "warn" "mcp" "harness/.cursor/mcp.json absent"
    }

    $lastActivity = & git -C $mcpServerRoot log -1 --format=%cd -- . 2>$null
    if ($lastActivity) {
        Add-Finding "pass" "mcp" "harness : derniere activite $lastActivity"
    } else {
        Add-Finding "warn" "mcp" "harness : aucun historique git trouve pour mcp-server/"
    }
} catch {
    Add-Finding "fail" "mcp" "Section mcp : erreur inattendue ($($_.Exception.Message))"
}
```

- [ ] **Step 2 : Verifier le cas nominal**

Depuis `ops-tools/` :
```
powershell.exe -NoProfile -File scripts\ops\doctor.ps1
```
Verifier manuellement l'etat reel :
```
Get-Item ..\harness\mcp-server\dist\index.js | Select LastWriteTimeUtc
Get-ChildItem ..\harness\mcp-server\src -Recurse -File | Sort LastWriteTimeUtc -Descending | Select -First 1
```
Comparer avec la ligne `mcp` de `doctor.ps1` (PASS "build a jour" si dist plus recent que tous les fichiers src, WARN sinon). Verifier aussi que la ligne "derniere activite" affiche une date plausible (comparer avec `git -C ..\harness\mcp-server log -1 --format=%cd`).

- [ ] **Step 3 : Verifier le cas dist absent**

Renommer temporairement `harness\mcp-server\dist` en `dist.bak` (sans commit, juste local), relancer `doctor.ps1`, verifier `[WARN] mcp harness : dist/index.js absent (build jamais lance)`. Renommer `dist.bak` en `dist` pour restaurer l'etat.

- [ ] **Step 4 : Commit**

```bash
cd ops-tools
git add scripts/ops/doctor.ps1
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section MCP ops doctor (build + config harness)

Compare LastWriteTime dist/index.js vs src/ (build a jour ou non),
verifie que .cursor/mcp.json reference un index.js existant, et
recupere la derniere activite git de mcp-server/. Pas de smoke test
runtime en V1 (MCP tourne en stdio, pas de port a sonder).
EOF
)"
```

---

### Task 4 : Section Env (completude .env par service)

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ps1` (remplace le commentaire `# Remplie par Task 4` sous `# --- Section Env ---`)

**Interfaces:**
- Consumes : `Add-Finding` (Task 1), `$WorkspacesRoot` (Task 1).
- Produces : findings de categorie `env`.

- [ ] **Step 1 : Implementer la section Env**

Dans `ops-tools/scripts/ops/doctor.ps1`, remplacer :
```powershell
try {
    # Remplie par Task 4
} catch {
    Add-Finding "fail" "env" "Section env : erreur inattendue ($($_.Exception.Message))"
}
```
(sous `# --- Section Env ---`) par :
```powershell
try {
    $envTargets = @(
        @{ Name = "harness"; Path = "harness" },
        @{ Name = "Infra/infra-local"; Path = "Infra\infra-local" },
        @{ Name = "Infra/infra-prod"; Path = "Infra\infra-prod" },
        @{ Name = "Interface/frontend-astro"; Path = "Interface\frontend-astro" },
        @{ Name = "my-curriculum"; Path = "my-curriculum" },
        @{ Name = "ops-tools"; Path = "ops-tools" },
        @{ Name = "personal-tech-board"; Path = "personal-tech-board" }
    )

    foreach ($target in $envTargets) {
        $repoPath = Join-Path $WorkspacesRoot $target.Path
        $examplePath = Join-Path $repoPath ".env.example"
        $envPath = Join-Path $repoPath ".env"

        if (-not (Test-Path $examplePath)) {
            Add-Finding "warn" "env" "$($target.Name) : .env.example absent"
            continue
        }

        $exampleKeys = @(Get-Content $examplePath | ForEach-Object {
            if ($_ -match '^([A-Z0-9_]+)=') { $Matches[1] }
        } | Where-Object { $_ })

        if (-not (Test-Path $envPath)) {
            Add-Finding "fail" "env" "$($target.Name) : .env absent ($($exampleKeys.Count) cles attendues)"
            continue
        }

        $envKeys = @(Get-Content $envPath | ForEach-Object {
            if ($_ -match '^([A-Z0-9_]+)=') { $Matches[1] }
        } | Where-Object { $_ })

        $missingKeys = $exampleKeys | Where-Object { $_ -notin $envKeys }

        if ($missingKeys.Count -eq 0) {
            Add-Finding "pass" "env" "$($target.Name) : .env complet ($($exampleKeys.Count) cles)"
        } else {
            foreach ($key in $missingKeys) {
                Add-Finding "warn" "env" "$($target.Name) : cle manquante dans .env : $key"
            }
        }
    }
} catch {
    Add-Finding "fail" "env" "Section env : erreur inattendue ($($_.Exception.Message))"
}
```

- [ ] **Step 2 : Verifier le cas nominal sur ops-tools lui-meme**

Depuis `ops-tools/` :
```
powershell.exe -NoProfile -File scripts\ops\doctor.ps1
```
Verifier la ligne `env` pour `ops-tools` : comparer avec un diff manuel des cles entre `ops-tools\.env.example` et `ops-tools\.env` (`Get-Content .env.example`, `Get-Content .env`, comparer visuellement les noms de cles avant le premier `=`). Le resultat de `doctor.ps1` doit correspondre exactement (WARN par cle manquante, ou PASS si complet).

- [ ] **Step 3 : Verifier le cas .env absent**

Choisir un des 7 repos cibles dont le `.env` local n'existe pas (probable pour `personal-tech-board` ou `Interface/frontend-astro` si jamais configures localement) et verifier la ligne `[FAIL] env <repo> : .env absent (N cles attendues)`. Si tous les `.env` existent localement, renommer temporairement l'un d'eux (`.env` -> `.env.bak-test`) le temps du test puis le restaurer immediatement apres verification.

- [ ] **Step 4 : Commit**

```bash
cd ops-tools
git add scripts/ops/doctor.ps1
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section env ops doctor (completude .env par service)

7 couples repo/.env.example en dur, regex ^([A-Z0-9_]+)= pour
extraire les noms de cles (jamais les valeurs), comparaison avec le
.env local reel. FAIL si .env absent, WARN par cle manquante, PASS si
complet.
EOF
)"
```

---

### Task 5 : Section Backlog (2 parseurs Markdown)

**Files:**
- Modify: `ops-tools/scripts/ops/doctor.ps1` (ajoute une fonction `Get-BacklogTableProgress` avant le bloc `# --- Section Infra ---`, remplace le commentaire `# Remplie par Task 5` sous `# --- Section Backlog ---`)

**Interfaces:**
- Consumes : `Add-Finding` (Task 1), `$WorkspacesRoot` (Task 1).
- Produces :
  - Fonction `Get-BacklogTableProgress($FilePath, $SectionHeader, $StatusColumnHeader)` -> retourne `$null` si `$FilePath` introuvable, sinon `[pscustomobject]@{ Done; Total }`.
  - Findings de categorie `backlog`.

- [ ] **Step 1 : Ajouter la fonction `Get-BacklogTableProgress`**

Dans `ops-tools/scripts/ops/doctor.ps1`, juste avant la ligne `# --- Section Infra ---`, ajouter :

```powershell
function Get-BacklogTableProgress {
    param(
        [string]$FilePath,
        [string]$SectionHeader,
        [string]$StatusColumnHeader = "Statut"
    )

    if (-not (Test-Path $FilePath)) {
        return $null
    }

    $lines = Get-Content $FilePath -Encoding UTF8
    $active = $false
    $statusColIndex = -1
    $done = 0
    $total = 0

    foreach ($line in $lines) {
        if ($line.TrimEnd() -eq $SectionHeader) {
            $active = $true
            $statusColIndex = -1
            continue
        }
        if ($active -and $line -match '^##\s') {
            break
        }
        if (-not $active) { continue }
        if ($line -notmatch '^\s*\|') { continue }

        $cells = $line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() }

        if ($statusColIndex -eq -1) {
            $idx = 0
            foreach ($cell in $cells) {
                if ($cell -eq $StatusColumnHeader) { $statusColIndex = $idx; break }
                $idx++
            }
            continue
        }

        if ($cells[0] -match '^-+$') { continue }
        if ($statusColIndex -ge $cells.Count) { continue }

        $statusCell = $cells[$statusColIndex]
        if ($statusCell -match '✅') {
            $done++
            $total++
        } elseif ($statusCell -match '🔄|⬜|🔒') {
            $total++
        }
    }

    return [pscustomobject]@{ Done = $done; Total = $total }
}
```

Explication de la machine a etats : `$active` bascule a `$true` des que la ligne complete (apres `TrimEnd`) matche exactement `$SectionHeader`, puis re-bascule a `$false` (via `break`, sortie de boucle) des que la prochaine ligne commencant par `##` apparait. Tant que `$active` est vrai, chaque ligne de table (commence par `|`) est splittee en cellules ; la premiere ligne de table rencontree est traitee comme l'en-tete (recherche de l'index de la colonne `Statut`), la ligne de separation Markdown (`|---|---|`) est ignoree via le test `$cells[0] -match '^-+$'`.

- [ ] **Step 2 : Implementer la section Backlog**

Dans `ops-tools/scripts/ops/doctor.ps1`, remplacer :
```powershell
try {
    # Remplie par Task 5
} catch {
    Add-Finding "fail" "backlog" "Section backlog : erreur inattendue ($($_.Exception.Message))"
}
```
(sous `# --- Section Backlog ---`) par :
```powershell
try {
    # Parseur A : cases a cocher markdown
    $upskillingPath = Join-Path $WorkspacesRoot "my-curriculum\docs\UPSKILLING.md"
    if (-not (Test-Path $upskillingPath)) {
        Add-Finding "fail" "backlog" "UPSKILLING.md introuvable ($upskillingPath)"
    } else {
        $lines = Get-Content $upskillingPath -Encoding UTF8
        $currentSection = $null
        $sectionCounts = @{}
        foreach ($line in $lines) {
            if ($line -match '^##\s+(.+)$') {
                $currentSection = $Matches[1].Trim()
                if (-not $sectionCounts.ContainsKey($currentSection)) {
                    $sectionCounts[$currentSection] = @{ done = 0; total = 0 }
                }
                continue
            }
            if (-not $currentSection) { continue }
            if ($line -match '^\s*-\s\[x\]') {
                $sectionCounts[$currentSection].done++
                $sectionCounts[$currentSection].total++
            } elseif ($line -match '^\s*-\s\[\s\]') {
                $sectionCounts[$currentSection].total++
            }
        }
        foreach ($section in $sectionCounts.Keys) {
            $c = $sectionCounts[$section]
            if ($c.total -eq 0) { continue }
            Add-Finding "pass" "backlog" "UPSKILLING.md / $section : $($c.done)/$($c.total) complete"
        }
    }

    # Parseur B : statuts en table, cible precisement sur une table par fichier
    # NE PAS MODIFIER : doit matcher le titre exact du fichier source (contient un tiret cadratin d'origine)
    $backlogMetaSectionHeader = "## Sprint S1 " + [char]0x2014 + " Mise en service harness (juillet 2026)"
    $harnessBacklog = Join-Path $WorkspacesRoot "harness\BACKLOG.md"
    $harnessResult = Get-BacklogTableProgress -FilePath $harnessBacklog -SectionHeader "## Vue priorisée (ordre d'exécution)"
    if ($null -eq $harnessResult) {
        Add-Finding "fail" "backlog" "harness/BACKLOG.md introuvable"
    } elseif ($harnessResult.Total -eq 0) {
        Add-Finding "warn" "backlog" "harness/BACKLOG.md : table 'Vue priorisée' introuvable ou vide"
    } else {
        Add-Finding "pass" "backlog" "harness/BACKLOG.md : $($harnessResult.Done)/$($harnessResult.Total) complete"
    }

    $metaBacklog = Join-Path $WorkspacesRoot "ops-tools\meta\BACKLOG-META.md"
    $metaResult = Get-BacklogTableProgress -FilePath $metaBacklog -SectionHeader $backlogMetaSectionHeader
    if ($null -eq $metaResult) {
        Add-Finding "fail" "backlog" "ops-tools/meta/BACKLOG-META.md introuvable"
    } elseif ($metaResult.Total -eq 0) {
        Add-Finding "warn" "backlog" "BACKLOG-META.md : table Sprint S1 introuvable ou vide"
    } else {
        Add-Finding "pass" "backlog" "ops-tools/meta/BACKLOG-META.md : $($metaResult.Done)/$($metaResult.Total) complete"
    }
} catch {
    Add-Finding "fail" "backlog" "Section backlog : erreur inattendue ($($_.Exception.Message))"
}
```

Note sur `$backlogMetaSectionHeader` : construit via `[char]0x2014` (le caractere tiret cadratin Unicode) plutot qu'ecrit litteralement, pour respecter la regle du repo tout en produisant la chaine exacte necessaire au match contre le titre reel de `ops-tools/meta/BACKLOG-META.md` (`## Sprint S1 — Mise en service harness (juillet 2026)`).

- [ ] **Step 3 : Verifier le Parseur A (UPSKILLING.md)**

Depuis `ops-tools/` :
```
powershell.exe -NoProfile -File scripts\ops\doctor.ps1
```
Ouvrir `my-curriculum\docs\UPSKILLING.md`, compter manuellement les `- [x]` et `- [ ]` sous `## ops-tools` (section connue au moment de l'ecriture de ce plan : 0 `[x]`, 5 `[ ]`). Comparer avec la ligne `[PASS] backlog UPSKILLING.md / ops-tools : 0/5 complete` (ou le ratio courant si le fichier a change depuis).

- [ ] **Step 4 : Verifier le Parseur B (tables)**

Comparer manuellement `harness\BACKLOG.md` : compter les `✅` dans la colonne Statut de la table sous `## Vue priorisée (ordre d'exécution)` (14 lignes au moment de l'ecriture de ce plan, 13 `✅` + 1 `⬜`) contre la ligne `[PASS] backlog harness/BACKLOG.md : 13/14 complete` (ou le ratio courant). Meme verification pour `ops-tools\meta\BACKLOG-META.md` section `## Sprint S1 — Mise en service harness (juillet 2026)`.

- [ ] **Step 5 : Verifier qu'aucune table non pertinente n'est comptee**

Confirmer que le score de `harness/BACKLOG.md` ne prend pas en compte la table "Zone | Verdict" de la section `## Post DA-1 — Vérifier références legacy` (colonnes differentes, pas de colonne `Statut`) : le total du finding `backlog` pour ce fichier doit correspondre uniquement a la table "Vue priorisée", pas a un chiffre plus eleve qui inclurait d'autres tables du fichier.

- [ ] **Step 6 : Commit**

```bash
cd ops-tools
git add scripts/ops/doctor.ps1
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): section backlog ops doctor (2 parseurs markdown)

Parseur A : cases a cocher (UPSKILLING.md), un ratio par section
##. Parseur B : machine a etats sur table cible par titre exact
(harness/BACKLOG.md § Vue priorisee, BACKLOG-META.md § Sprint S1),
compte les statuts emoji dans la colonne Statut. Un ratio par fichier,
jamais d'agregat invente entre les deux formats.
EOF
)"
```

---

### Task 6 : Integration Makefile et validation finale

**Files:**
- Modify: `ops-tools/Makefile`

**Interfaces:**
- Consumes : `ops-tools/scripts/ops/doctor.ps1` complet (Tasks 1 a 5).
- Produces : target `make doctor` invocable.

- [ ] **Step 1 : Ajouter le target `doctor` au Makefile**

Dans `ops-tools/Makefile`, remplacer :
```makefile
.PHONY: help repo-health normalize-eol-dry normalize-eol-apply

help:
	@echo "Targets:"
	@echo "  repo-health           - Diagnostic rapide des repos"
	@echo "  normalize-eol-dry     - Dry-run normalisation LF"
	@echo "  normalize-eol-apply   - Apply + renormalize + commit (skip dirty)"
```
par :
```makefile
.PHONY: help repo-health normalize-eol-dry normalize-eol-apply doctor

help:
	@echo "Targets:"
	@echo "  repo-health           - Diagnostic rapide des repos"
	@echo "  normalize-eol-dry     - Dry-run normalisation LF"
	@echo "  normalize-eol-apply   - Apply + renormalize + commit (skip dirty)"
	@echo "  doctor                - Preflight check ecosysteme (infra/mcp/env/backlogs)"
```

Puis, apres le target `normalize-eol-apply:` existant (avant le second bloc `.PHONY: maintenance-normalize-eol-dry maintenance-normalize-eol-apply`), ajouter :
```makefile

doctor:
	@powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/ops/doctor.ps1
```

- [ ] **Step 2 : Verifier `make help` et `make doctor`**

Depuis `ops-tools/` :
```bash
make help
```
Verifier que la ligne `doctor                - Preflight check ecosysteme (infra/mcp/env/backlogs)` apparait.

```bash
make doctor
```
Verifier que la sortie est identique a un appel direct de `powershell.exe -NoProfile -File scripts/ops/doctor.ps1` (memes sections, meme score, meme ligne de rapport final).

- [ ] **Step 3 : Smoke test final sur le parc reel**

Lancer `make doctor` et lire integralement la sortie console. Verifier que le score global reflete l'etat reel connu au moment de l'execution :
- Infra : `PASS` sur tous les conteneurs si le VPS est joignable et le parc en bon etat.
- MCP : `PASS` sur le build si `harness/mcp-server/dist/index.js` a ete build recemment.
- Env : `WARN`/`FAIL` uniquement sur des cles reellement absentes (verifier au moins un cas manuellement).
- Backlog : les ratios correspondent aux totaux comptes manuellement dans les 3 fichiers.

Nettoyer le rapport de test genere si non souhaite : `rm meta/rex/doctor_<timestamp-du-smoke-test>.md` (optionnel, garder si represente un etat utile a archiver).

- [ ] **Step 4 : Commit**

```bash
cd ops-tools
git add Makefile
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): integration make doctor

Nouveau target doctor dans le Makefile, invoque powershell.exe
-NoProfile -ExecutionPolicy Bypass (pwsh non installe sur cette
machine). Ajoute a .PHONY et a l'echo du target help, coherent avec
les targets existants.
EOF
)"
```

---

## Self-Review (effectue par l'auteur du plan avant remise)

**Couverture du spec** : les 4 sections (Infra/MCP/Env/Backlog), le moteur Add-Finding, le rapport Markdown horodate, le resume console colore, la resilience try/catch par section, le cas VPS injoignable degrade, l'integration Makefile, et l'absence de suite Pester sont tous couverts par une tache. Rien du spec `2026-07-24-ops-doctor-design.md` n'est laisse sans tache correspondante.

**Coherence des types/noms** : `Add-Finding($severity, $category, $message)` utilise le meme nom et la meme signature dans les 4 sections. `$WorkspacesRoot` (Task 1) est reference identiquement dans toutes les taches suivantes. `Get-BacklogTableProgress` (Task 5) a une signature unique utilisee deux fois avec des `$SectionHeader` differents. Corrige pendant la redaction : la variable pour le titre de section de BACKLOG-META.md s'appelait initialement `$harnessSectionHeader` (nom trompeur), renommee en `$backlogMetaSectionHeader` directement dans le code de la Task 5.

**Pas de placeholder** : chaque step contient du code complet et executable, aucun TBD/TODO, aucune reference a une fonction non definie dans une tache anterieure.
