# audit-images.ps1
# Scanne tous les docker-compose du workspace, extrait les images epinglees,
# interroge Docker Hub pour detecter les versions plus recentes disponibles.
#
# Usage : .\ops-tools\infra\audit-images.ps1
# Usage (pull auto) : .\ops-tools\infra\audit-images.ps1 -Pull

param([switch]$Pull)

$ComposeFiles = @(
    "AI_agents\seomnix\n8n-projects\n8n-core\docker-compose.yml",
    "Infra\infra-local\docker-compose.yml",
    "Infra\infra-local\docker-compose.seo.yml",
    "Infra\infra-prod\docker-compose.yml"
)

# Images a surveiller — [image, tag-prefix pour filtrer les releases stables]
$WatchList = @(
    @{ Image = "n8nio/n8n";           Prefix = ""; Pattern = "^\d+\.\d+\.\d+$" },
    @{ Image = "directus/directus";   Prefix = ""; Pattern = "^11\.\d+\.\d+$"  },
    @{ Image = "qdrant/qdrant";       Prefix = "v"; Pattern = "^v\d+\.\d+\.\d+$" },
    @{ Image = "traefik";             Prefix = "v"; Pattern = "^v\d+\.\d+\.\d+$" },
    @{ Image = "postgres";            Prefix = ""; Pattern = "^16-alpine$"      },
    @{ Image = "redis";               Prefix = ""; Pattern = "^7-alpine$"       }
)

function Get-LatestTag($image, $pattern) {
    $ns, $repo = if ($image -match "/") { $image -split "/", 2 } else { "library", $image }
    $url = "https://hub.docker.com/v2/repositories/$ns/$repo/tags?page_size=100&ordering=-last_updated"
    try {
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 10
        $tags = $resp.results | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        return $tags.name
    } catch { return "?" }
}

function Extract-PinnedVersions($file) {
    $content = Get-Content $file -Raw
    $versions = @{}
    foreach ($entry in $WatchList) {
        $img = $entry.Image
        if ($content -match "image:\s*$([regex]::Escape($img)):([^\s""']+)") {
            $versions[$img] = $Matches[1]
        }
    }
    return $versions
}

# --- Collecte toutes les versions epinglees ---
$pinned = @{}
foreach ($f in $ComposeFiles) {
    $path = Join-Path (Get-Location) $f
    if (-not (Test-Path $path)) { continue }
    $found = Extract-PinnedVersions $path
    foreach ($k in $found.Keys) {
        if (-not $pinned.ContainsKey($k)) { $pinned[$k] = $found[$k] }
    }
}

# --- Interroge Docker Hub ---
Write-Host ""
Write-Host "=== Audit images Docker — $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan
Write-Host ""
Write-Host ("{0,-30} {1,-15} {2,-15} {3}" -f "Image", "Epingle", "Disponible", "Statut")
Write-Host ("-" * 75)

$updates = @()
foreach ($entry in $WatchList) {
    $img     = $entry.Image
    $current = $pinned[$img] ?? "(non trouve)"
    $latest  = Get-LatestTag $img $entry.Pattern

    $status = if ($current -eq $latest) { "✅ a jour" }
              elseif ($current -eq "(non trouve)") { "⚠️  non epingle" }
              elseif ($latest -eq "?")  { "❓ inconnu" }
              else                      { "🔄 MaJ dispo" }

    $color = if ($status -like "*MaJ*") { "Yellow" } elseif ($status -like "*✅*") { "Green" } else { "Gray" }
    Write-Host ("{0,-30} {1,-15} {2,-15} {3}" -f $img, $current, $latest, $status) -ForegroundColor $color

    if ($status -like "*MaJ*") { $updates += @{ Image = $img; Current = $current; Latest = $latest } }
}

Write-Host ""
if ($updates.Count -eq 0) {
    Write-Host "Tout est a jour." -ForegroundColor Green
} else {
    Write-Host "$($updates.Count) mise(s) a jour disponible(s)." -ForegroundColor Yellow
    if ($Pull) {
        Write-Host ""
        Write-Host "Pull des nouvelles images..." -ForegroundColor Cyan
        foreach ($u in $updates) {
            Write-Host "  docker pull $($u.Image):$($u.Latest)"
            docker pull "$($u.Image):$($u.Latest)" 2>&1 | Select-Object -Last 2
        }
        Write-Host ""
        Write-Host "Mettez a jour les compose files puis lancez le script de mise a jour prod."
    } else {
        Write-Host "Relancez avec -Pull pour tirer les nouvelles images localement."
    }
}
Write-Host ""
