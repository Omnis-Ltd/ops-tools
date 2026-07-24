# doctor.ps1
# Preflight check unique pour l'ecosysteme Fadel OS : infra, MCP, completude .env, avancement backlogs.
# Usage: & ".\scripts\ops\doctor.ps1"  (depuis ops-tools/)
#    ou: make doctor

param(
    [string]$WorkspacesRoot = $(if ($env:WORKSPACES_ROOT) { $env:WORKSPACES_ROOT } else { Join-Path $env:USERPROFILE "git\Workspaces" })
)

$ErrorActionPreference = "Stop"
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
