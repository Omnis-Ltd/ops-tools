# migrate-da1.ps1
# DA-1 : Restructuration AI_agents multi-projet
# Usage : & ".\ops-tools\meta\migrate-da1.ps1" -WhatIf
#         & ".\ops-tools\meta\migrate-da1.ps1"

param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$ai = Join-Path $WorkspaceRoot "AI_agents"

function Move-IfExists([string]$src, [string]$dst) {
    if (-not (Test-Path $src)) {
        Write-Host "  SKIP  (absent) $src"
        return
    }
    if (Test-Path $dst) {
        Write-Warning "  EXISTS $dst - migration partielle ou deja faite"
        return
    }
    $parent = Split-Path $dst -Parent
    if (-not (Test-Path $parent)) {
        if ($WhatIf) { Write-Host "  MKDIR $parent" }
        else { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }
    if ($WhatIf) { Write-Host "  MOVE  $src -> $dst" }
    else { Move-Item -Path $src -Destination $dst; Write-Host "  OK    $dst" }
}

Write-Host "DA-1 migration - Workspace: $WorkspaceRoot"
if ($WhatIf) { Write-Host "(WhatIf - aucune modification)`n" }

$dirs = @("seomnix", "fluxguard\agents", "fluxguard\n8n-projects", "_shared")
foreach ($d in $dirs) {
    $p = Join-Path $ai $d
    if ($WhatIf) { Write-Host "  ENSURE $p" }
    elseif (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Move-IfExists (Join-Path $ai "ai-agents-core") (Join-Path $ai "seomnix\ai-agents-core")
Move-IfExists (Join-Path $ai "n8n-projects")   (Join-Path $ai "seomnix\n8n-projects")

$manifest = Join-Path $WorkspaceRoot "harness\manifests\seomnix.json"
$newPath = "AI_agents/seomnix/n8n-projects/workflows-b2c/workflows"
if (Test-Path $manifest) {
    if ($WhatIf) {
        Write-Host "  UPDATE $manifest n8n_output_dir = $newPath"
    } else {
        $json = Get-Content $manifest -Raw | ConvertFrom-Json
        $json.n8n_output_dir = $newPath
        $json | ConvertTo-Json -Depth 10 -Compress:$false | Out-File $manifest -Encoding utf8NoBOM
        Write-Host "  OK    manifest seomnix.json updated"
    }
}

$exportScript = Join-Path $WorkspaceRoot "ops-tools\n8n\export-workflows.ps1"
if (Test-Path $exportScript) {
    $newDefault = "AI_agents\seomnix\n8n-projects\workflows-b2c\workflows"
    if ($WhatIf) {
        Write-Host "  UPDATE export-workflows.ps1 OutputDir default"
    } else {
        $content = Get-Content $exportScript -Raw
        $content = $content -replace 'AI_agents\\n8n-projects\\workflows-b2c\\workflows', $newDefault
        Set-Content $exportScript $content -Encoding UTF8 -NoNewline
        Write-Host "  OK    export-workflows.ps1 updated"
    }
}

Write-Host "`nPost-migration: verifier CI paths, routines ops-tools, Docker compose"
