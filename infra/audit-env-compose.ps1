# audit-env-compose.ps1
# Detecte les variables presentes dans le .env VPS mais absentes de la section
# environment: du service cible dans le docker-compose — evite la regression
# "variable disponible sur le VPS mais invisible au container".
#
# Usage :
#   .\ops-tools\infra\audit-env-compose.ps1
#   .\ops-tools\infra\audit-env-compose.ps1 -Service n8n
#   .\ops-tools\infra\audit-env-compose.ps1 -EnvFile Infra\infra-prod\.env.example

param(
    [string]$ComposeFile = "Infra\infra-prod\docker-compose.yml",
    [string]$Service     = "",          # vide = tous les services
    [string]$VpsHost     = "seo-prod",
    [string]$VpsEnvPath  = "/opt/seo-empire/.env",
    [switch]$Remote                     # lit le .env depuis le VPS via SSH
)

# =============================================================================
# Etape 1 — Recuperer les noms de variables du .env
# =============================================================================
Write-Host ""
Write-Host "=== Audit .env vs docker-compose ===" -ForegroundColor Cyan

$envVars = @()

if ($Remote) {
    Write-Host "Lecture .env depuis $VpsHost..." -ForegroundColor Gray
    $raw = ssh $VpsHost "cat $VpsEnvPath 2>/dev/null" 2>&1
} else {
    # Cherche un .env local de reference (example ou vrai)
    $candidates = @(
        "Infra\infra-prod\.env.example",
        "Infra\infra-prod\.env"
    )
    $raw = $null
    foreach ($c in $candidates) {
        if (Test-Path $c) { $raw = Get-Content $c -Raw; Write-Host "Lecture locale : $c" -ForegroundColor Gray; break }
    }
    if (-not $raw) {
        Write-Host "Aucun .env local trouve. Utilise -Remote pour lire depuis le VPS." -ForegroundColor Yellow
        Write-Host "Ou cree Infra\infra-prod\.env.example avec les noms de variables (valeurs vides)." -ForegroundColor Yellow
        exit 0
    }
}

# Parse : garde uniquement les lignes VAR=... (ignore commentaires et vides)
$envVars = $raw -split "`n" |
    Where-Object { $_ -match "^[A-Z_][A-Z0-9_]*=" } |
    ForEach-Object { ($_ -split "=", 2)[0].Trim() } |
    Sort-Object

Write-Host "$($envVars.Count) variables trouvees dans .env" -ForegroundColor Gray

# =============================================================================
# Etape 2 — Parser le docker-compose pour chaque service
# =============================================================================
$composePath = Join-Path (Get-Location) $ComposeFile
if (-not (Test-Path $composePath)) {
    Write-Error "Compose file introuvable : $composePath"
    exit 1
}

$composeContent = Get-Content $composePath -Raw

# Extrait toutes les references ${VAR_NAME} du compose (toutes sections confondues)
# On va faire la distinction par service manuellement
$allServiceRefs = [regex]::Matches($composeContent, '\$\{([A-Z_][A-Z0-9_]*)[^}]*\}') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

# Detect services dans le compose (parsing YAML simplifie par regex)
$serviceBlocks = @{}
$lines = Get-Content $composePath
$currentService = $null
$inServices = $false
$indent = 0

foreach ($line in $lines) {
    if ($line -match "^services:") { $inServices = $true; continue }
    if (-not $inServices) { continue }
    # Detecte un service (2 espaces + nom + colon)
    if ($line -match "^  ([a-z][a-zA-Z0-9_-]+):") {
        $currentService = $Matches[1]
        $serviceBlocks[$currentService] = @()
    }
    if ($currentService -and $line -match '\$\{([A-Z_][A-Z0-9_]*)[^}]*\}') {
        $serviceBlocks[$currentService] += $Matches[1]
    }
}

# =============================================================================
# Etape 3 — Rapport
# =============================================================================
$services = if ($Service) { @($Service) } else { $serviceBlocks.Keys | Sort-Object }

$totalMissing = 0

foreach ($svc in $services) {
    if (-not $serviceBlocks.ContainsKey($svc)) {
        Write-Host "  Service '$svc' non trouve dans le compose." -ForegroundColor Red
        continue
    }

    $svcRefs   = $serviceBlocks[$svc] | Sort-Object -Unique
    $missing   = $envVars | Where-Object { $_ -notin $svcRefs }
    $undefined = $svcRefs  | Where-Object { $_ -notin $envVars }

    Write-Host ""
    Write-Host "--- Service : $svc ---" -ForegroundColor White
    Write-Host "  Vars referees dans environment : $($svcRefs.Count)"

    if ($undefined.Count -gt 0) {
        Write-Host "  [ERR] Vars referees ABSENTES du .env ($($undefined.Count)) :" -ForegroundColor Red
        $undefined | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
    }

    if ($missing.Count -gt 0) {
        Write-Host "  [WARN] Vars du .env NON passees a ce service ($($missing.Count)) :" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        $totalMissing += $missing.Count
    } else {
        Write-Host "  [OK] Toutes les vars .env sont passees au service" -ForegroundColor Green
    }
}

Write-Host ""
if ($totalMissing -gt 0) {
    Write-Host "Total vars potentiellement manquantes : $totalMissing" -ForegroundColor Yellow
    Write-Host "Note : une var 'manquante' n'est pas forcement necessaire au service." -ForegroundColor Gray
    Write-Host "       Verifier si le service en a besoin avant d'ajouter." -ForegroundColor Gray
} else {
    Write-Host "Aucun ecart detecte." -ForegroundColor Green
}
Write-Host ""
