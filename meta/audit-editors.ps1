# audit-editors.ps1
# Inventaire multi-editeur (Cursor, VS Code, Claude Code) vs harness/manifests/editor-policy.json
# Usage: & ".\ops-tools\meta\audit-editors.ps1" [-WorkspaceRoot C:\...\Workspaces]

param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Continue"
$policyPath = Join-Path $WorkspaceRoot "harness\manifests\editor-policy.json"
$policy = Get-Content $policyPath -Raw | ConvertFrom-Json
$userHome = $env:USERPROFILE

$findings = @()
$scores = @{ pass = 0; warn = 0; fail = 0 }

function Add-Finding($severity, $category, $message) {
    $script:findings += [pscustomobject]@{ Severity = $severity; Category = $category; Message = $message }
    $script:scores[$severity]++
}

function Test-PathReport($label, $path) {
    $exists = Test-Path $path
    if ($exists) { Add-Finding "pass" "paths" "$label : $path" }
    else { Add-Finding "warn" "paths" "$label absent : $path" }
    return $exists
}

function Count-Glob($pattern, $root, [int]$maxDepth = 3) {
    if (-not (Test-Path $root)) { return 0 }
    return (Get-ChildItem -Path $root -Filter $pattern -Recurse -File -Depth $maxDepth -ErrorAction SilentlyContinue | Measure-Object).Count
}

function Get-CursorProjectSlug([string]$projectPath) {
    $full = (Resolve-Path $projectPath -ErrorAction SilentlyContinue).Path
    if (-not $full) { return $null }
    if ($full -match '^([A-Za-z]):\\(.+)$') {
        return ('{0}-{1}' -f $Matches[1].ToLower(), ($Matches[2] -replace '\\', '-'))
    }
    return ($full -replace '[/\\:]', '-').ToLower()
}

function Test-NotionMention([string]$content, $patterns) {
    foreach ($pat in $patterns) {
        if ($content -match $pat) { return $true }
    }
    return $false
}

Write-Host "`n=== Harness editor audit ===" -ForegroundColor Cyan
Write-Host "Workspace: $WorkspaceRoot"
Write-Host "Policy:    $policyPath`n"

# --- Cursor ---
Write-Host "--- Cursor ---" -ForegroundColor Yellow
$cursorSettings = Join-Path $env:APPDATA "Cursor\User\settings.json"
Test-PathReport "Cursor user settings" $cursorSettings | Out-Null

$mcpHarness = Join-Path $WorkspaceRoot "harness\.cursor\mcp.json"
if (Test-Path $mcpHarness) {
    $mcp = Get-Content $mcpHarness -Raw | ConvertFrom-Json
    $count = @($mcp.mcpServers.PSObject.Properties).Count
    Add-Finding "pass" "mcp" "Cursor MCP harness: $count serveur(s) dans harness/.cursor/mcp.json"
    if ($count -gt $policy.limits.max_mcp_servers) {
        Add-Finding "fail" "mcp" "Trop de MCP ($count > $($policy.limits.max_mcp_servers))"
    }
    foreach ($srv in $mcp.mcpServers.PSObject.Properties) {
        $args = $srv.Value.args -join " "
        if ($args -match "@latest") {
            Add-Finding "warn" "mcp" "MCP $($srv.Name) utilise @latest (R-SEC-1 / reproductibilite)"
        }
        if ($srv.Name -eq "harness" -and $srv.Value.env.N8N_API_KEY) {
            Add-Finding "pass" "secrets" "N8N_API_KEY present (fichier gitignore attendu)"
        }
    }
} else {
    Add-Finding "warn" "mcp" "harness/.cursor/mcp.json absent - lancer generate-mcp-from-env.ps1"
}

$cursorRules = Get-ChildItem (Join-Path $WorkspaceRoot "harness\.cursor\rules\*.mdc") -ErrorAction SilentlyContinue
$alwaysOn = @($cursorRules | Where-Object { (Get-Content $_.FullName -Raw) -match "alwaysApply:\s*true" })
Add-Finding "pass" "rules" "Cursor rules harness: $($cursorRules.Count) fichier(s), $($alwaysOn.Count) alwaysApply"
if ($alwaysOn.Count -gt $policy.limits.max_always_on_rules) {
    Add-Finding "warn" "rules" "alwaysApply=$($alwaysOn.Count) > limite $($policy.limits.max_always_on_rules)"
}

$cursorSkills = Join-Path $userHome ".cursor\skills-cursor"
$skillCount = Count-Glob "SKILL.md" $cursorSkills
Add-Finding "pass" "skills" "Cursor skills globaux: $skillCount SKILL.md"
foreach ($high in $policy.skills.high_cost_cursor_skills) {
    $p = Join-Path $cursorSkills $high
    if (Test-Path $p) {
        Add-Finding "warn" "skills" "Skill Cursor a cout eleve disponible: $high (subagents/loops)"
    }
}

# --- Plugin MCP Notion (projets dependants) ---
Write-Host "`n--- Plugin MCP Notion ---" -ForegroundColor Yellow
$notionPolicy = $policy.plugin_mcp.notion
$notionPluginDir = Join-Path $userHome ".cursor\plugins\cache\cursor-public"
$notionPluginInstalled = $false
if (Test-Path $notionPluginDir) {
    $notionPluginInstalled = @(Get-ChildItem $notionPluginDir -Directory -Filter "*notion-workspace*" -ErrorAction SilentlyContinue).Count -gt 0
}
if ($notionPluginInstalled) {
    Add-Finding "pass" "notion" "Plugin Notion installe (cache cursor-public/notion-workspace)"
} else {
    Add-Finding "fail" "notion" "Plugin Notion absent du cache - reinstaller depuis Cursor Marketplace"
}

$userMcpGlobal = Join-Path $userHome ".cursor\mcp.json"
if (Test-Path $userMcpGlobal) {
    $userMcp = Get-Content $userMcpGlobal -Raw | ConvertFrom-Json
    $hasPlaceholders = $false
    foreach ($srv in $userMcp.mcpServers.PSObject.Properties) {
        $envJson = $srv.Value.env | ConvertTo-Json -Compress
        if ($envJson -match '\$\{') { $hasPlaceholders = $true }
    }
    if ($hasPlaceholders) {
        Add-Finding "warn" "mcp" "~/.cursor/mcp.json contient des placeholders env non resolus (Connection closed)"
    }
}

$notionDependentProjects = @()
foreach ($rootName in $notionPolicy.scan_roots) {
    $projRoot = Join-Path $WorkspaceRoot $rootName
    if (-not (Test-Path $projRoot)) { continue }
    foreach ($relGlob in $notionPolicy.scan_files) {
        $globPath = Join-Path $projRoot $relGlob
        $parent = Split-Path $globPath -Parent
        $filter = Split-Path $globPath -Leaf
        if (-not (Test-Path $parent)) { continue }
        Get-ChildItem $parent -Filter $filter -Recurse -File -Depth 5 -ErrorAction SilentlyContinue | ForEach-Object {
            $text = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($text -and (Test-NotionMention $text $notionPolicy.detect_patterns)) {
                $projKey = $rootName
                if ($_.FullName -notmatch [regex]::Escape((Join-Path $WorkspaceRoot $rootName))) {
                    $projKey = $rootName
                }
                if ($notionDependentProjects -notcontains $rootName) {
                    $notionDependentProjects += $rootName
                }
            }
        }
    }
}

if ($notionDependentProjects.Count -eq 0) {
    Add-Finding "pass" "notion" "Aucun projet scanne ne reference Notion MCP"
} else {
    Add-Finding "pass" "notion" "Projets dependants Notion: $($notionDependentProjects -join ', ')"
}

foreach ($projName in $notionDependentProjects) {
    $projPath = Join-Path $WorkspaceRoot $projName
    $slug = Get-CursorProjectSlug $projPath
    if (-not $slug) { continue }
    $mcpsRoot = Join-Path $userHome ".cursor\projects\$slug\mcps"
    $notionMcps = Join-Path $mcpsRoot $notionPolicy.cursor_snapshot_dir
    $toolsDir = Join-Path $notionMcps "tools"
    $toolCount = 0
    if (Test-Path $toolsDir) {
        $toolCount = @(Get-ChildItem $toolsDir -Filter "notion-*.json" -ErrorAction SilentlyContinue).Count
    }
    if ($toolCount -ge 1) {
        Add-Finding "pass" "notion" "$projName : mcps/$($notionPolicy.cursor_snapshot_dir) OK ($toolCount tools)"
    } else {
        Add-Finding "fail" "notion" "$projName : mcps/$($notionPolicy.cursor_snapshot_dir) absent ou vide (slug: $slug)"
        Add-Finding "warn" "notion" "$projName : reconnecter plugin Notion (Settings > Plugins > Enable, puis MCP > Connect OAuth, Reload Window)"
    }
}

# --- VS Code ---
Write-Host "`n--- VS Code ---" -ForegroundColor Yellow
$vscodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
Test-PathReport "VS Code user settings" $vscodeSettings | Out-Null
$vscodeMcp = Join-Path $userHome ".vscode\mcp.json"
Test-PathReport "VS Code MCP global" $vscodeMcp | Out-Null
$copilotInstr = @()
foreach ($dir in @("harness", "artmap", "Interface", "AI_agents")) {
    $base = Join-Path $WorkspaceRoot $dir
    if (Test-Path $base) {
        $copilotInstr += Get-ChildItem $base -Filter "copilot-instructions.md" -Recurse -File -Depth 4 -ErrorAction SilentlyContinue
    }
}
if ($copilotInstr) {
    Add-Finding "pass" "rules" "VS Code copilot-instructions: $($copilotInstr.Count) fichier(s)"
} else {
    Add-Finding "warn" "rules" "Aucun copilot-instructions.md - regles harness non propagees VS Code"
}

# --- Claude Code ---
Write-Host "`n--- Claude Code ---" -ForegroundColor Yellow
$claudeSettings = Join-Path $userHome ".claude\settings.json"
if (Test-Path $claudeSettings) {
    $cs = Get-Content $claudeSettings -Raw | ConvertFrom-Json
    Add-Finding "pass" "claude" "settings.json present (modele: $($cs.model))"
    foreach ($plug in $cs.enabledPlugins.PSObject.Properties) {
        if ($plug.Value -eq $true) {
            Add-Finding "pass" "plugins" "Plugin actif: $($plug.Name)"
            if ($plug.Name -match "superpowers") {
                Add-Finding "warn" "plugins" "superpowers actif - skills proactifs (using-superpowers, brainstorming)"
            }
        }
    }
} else {
    Add-Finding "warn" "claude" "settings.json absent"
}

$superRoot = Join-Path $userHome ".claude\plugins\cache\claude-plugins-official\superpowers"
$superCount = Count-Glob "SKILL.md" $superRoot 2

$eccRoot = Join-Path $userHome ".claude\plugins\cache\everything-claude-code"
$eccCount = Count-Glob "SKILL.md" $eccRoot 3
Add-Finding "pass" "skills" "Superpowers cache: $superCount SKILL.md (versions multiples possibles)"
Add-Finding "pass" "skills" "everything-claude-code cache: $eccCount SKILL.md"

$claudeMdRoot = Join-Path $WorkspaceRoot "CLAUDE.md"
if ((Test-Path $claudeMdRoot) -and ((Get-Item $claudeMdRoot).Length -lt 10)) {
    Add-Finding "warn" "rules" "CLAUDE.md racine Workspaces vide - pas de regles transverses Claude Code"
}

# --- Harness cross-cutting ---
Write-Host "`n--- Harness transverse ---" -ForegroundColor Yellow
Test-PathReport "RULES.md" (Join-Path $WorkspaceRoot "harness\RULES.md") | Out-Null
Test-PathReport "skills-curated.json" (Join-Path $WorkspaceRoot "harness\manifests\skills-curated.json") | Out-Null
$gitignore = Join-Path $WorkspaceRoot "harness\.gitignore"
if (Test-Path $gitignore) {
    $gi = Get-Content $gitignore -Raw
    if ($gi -match "mcp\.json") { Add-Finding "pass" "secrets" "harness/.gitignore exclut .cursor/mcp.json" }
    else { Add-Finding "fail" "secrets" "harness/.gitignore ne mentionne pas mcp.json" }
}

# --- Report ---
Write-Host "`n=== Findings ($($findings.Count)) ===" -ForegroundColor Cyan
$findings | Sort-Object Severity, Category | ForEach-Object {
    $color = switch ($_.Severity) { "pass" { "Green" } "warn" { "Yellow" } "fail" { "Red" } default { "White" } }
    Write-Host ("  [{0,4}] {1,-10} {2}" -f $_.Severity.ToUpper(), $_.Category, $_.Message) -ForegroundColor $color
}

Write-Host "`n=== Score ===" -ForegroundColor Cyan
Write-Host "  PASS: $($scores.pass)  WARN: $($scores.warn)  FAIL: $($scores.fail)"

$outFile = Join-Path $WorkspaceRoot "ops-tools\meta\rex\audit-editors-$(Get-Date -Format 'yyyy-MM-dd').md"
$md = @(
    "# Audit editeurs - $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
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
