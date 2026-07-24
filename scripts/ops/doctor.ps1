# doctor.ps1
# Preflight check unique pour l'ecosysteme Fadel OS : infra, MCP, completude .env, avancement backlogs.
# Usage: & ".\scripts\ops\doctor.ps1"  (depuis ops-tools/)
#    ou: make doctor

# IMPORTANT : ce fichier doit conserver son BOM UTF-8. Sans BOM, Windows
# PowerShell 5.1 lit le fichier avec l'encodage systeme (cp1252) au lieu
# d'UTF-8, ce qui corrompt les caracteres non-ASCII (emoji, accents) et
# casse le parsing de tout le script, pas seulement la ligne concernee.

param(
    [string]$WorkspacesRoot = $(if ($env:WORKSPACES_ROOT) { $env:WORKSPACES_ROOT } else { Join-Path $env:USERPROFILE "git\Workspaces" })
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
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

# --- Section Infra ---
Write-Host "--- Infra ---" -ForegroundColor Yellow
try {
    $system32 = if ([Environment]::Is64BitProcess) { "$env:WINDIR\System32" } else { "$env:WINDIR\Sysnative" }
    $sshExe = Join-Path $system32 "OpenSSH\ssh.exe"
    $dockerCmd = "docker ps --filter network=seo-prod-network --format '{{json .}}'"
    $sshOutput = & $sshExe -o BatchMode=yes -o ConnectTimeout=5 seo-prod $dockerCmd
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

# --- Section MCP ---
Write-Host "`n--- MCP ---" -ForegroundColor Yellow
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

# --- Section Env ---
Write-Host "`n--- Env ---" -ForegroundColor Yellow
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

# --- Section Backlog ---
Write-Host "`n--- Backlog ---" -ForegroundColor Yellow
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
$outDir = Split-Path -Parent $outFile
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
$md -join "`n" | Set-Content $outFile -Encoding UTF8
Write-Host "`nRapport: $outFile" -ForegroundColor Green

if ($scores.fail -gt 0) { exit 1 }
exit 0
