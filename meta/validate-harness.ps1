# validate-harness.ps1
# Validation harness MCP — modules + build + paths + n8n creds
# Usage : & ".\ops-tools\meta\validate-harness.ps1"
# Charge automatiquement ops-tools/.env (surcharge possible via -EnvFile)

param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Continue"
$ok = $true
$envLoaded = $false

function Import-DotEnvFile([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $parts = $line.Split("=", 2)
        if ($parts.Count -ne 2) { return }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, "Process"))) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
    return $true
}

if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $EnvFile = Join-Path $WorkspaceRoot "ops-tools\.env"
}
$envLoaded = Import-DotEnvFile $EnvFile

function Check($label, [scriptblock]$test) {
    try {
        if (& $test) { Write-Host "  OK   $label" -ForegroundColor Green }
        else { Write-Host "  FAIL $label" -ForegroundColor Red; $script:ok = $false }
    } catch {
        Write-Host "  FAIL $label - $_" -ForegroundColor Red
        $script:ok = $false
    }
}

Write-Host "`n=== Harness validation ===`n"
if ($envLoaded) {
    Write-Host "  INFO .env charge : $EnvFile" -ForegroundColor Cyan
} else {
    Write-Host "  WARN .env absent : $EnvFile" -ForegroundColor Yellow
}
Write-Host ""

Check "mcp-server built" {
    Test-Path (Join-Path $WorkspaceRoot "harness\mcp-server\dist\index.js")
}

Check "seomnix manifest" {
    Test-Path (Join-Path $WorkspaceRoot "harness\manifests\seomnix.json")
}

Check "n8n workflows dir exists" {
    $m = Get-Content (Join-Path $WorkspaceRoot "harness\manifests\seomnix.json") -Raw | ConvertFrom-Json
    Test-Path (Join-Path $WorkspaceRoot ($m.n8n_output_dir -replace "/", "\"))
}

Check "N8N_URL set" { [bool]$env:N8N_URL }

Check "N8N_API_KEY set" { [bool]$env:N8N_API_KEY }

Check "n8n API reachable (list_workflows)" {
    if (-not $env:N8N_URL -or -not $env:N8N_API_KEY) { return $false }
    $url = $env:N8N_URL.TrimEnd('/')
    $headers = @{ "X-N8N-API-KEY" = $env:N8N_API_KEY }
    $list = Invoke-RestMethod -Uri "$url/api/v1/workflows?limit=5" -Headers $headers -Method GET
    $null -ne $list.data
}

Check "llm-router smoke" {
    Push-Location (Join-Path $WorkspaceRoot "harness\mcp-server")
    $out = node smoke-router.mjs 2>&1
    Pop-Location
    ($out -join "") -match "qwen"
}

Check "benchmark-models.py syntax" {
    python -m py_compile (Join-Path $WorkspaceRoot "ops-tools\meta\benchmark-models.py") 2>$null
    $LASTEXITCODE -eq 0
}

Write-Host ""
if (-not $env:N8N_URL -or -not $env:N8N_API_KEY) {
    Write-Host "  INFO N8N_* manquant : verifier $EnvFile" -ForegroundColor Yellow
}

if ($ok) {
    Write-Host "=== All checks passed ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== Some checks failed - see harness/mcp-config/SETUP.md ===" -ForegroundColor Red
    exit 1
}
