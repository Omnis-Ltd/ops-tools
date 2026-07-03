# export-workflows.ps1
# Tire tous les workflows depuis n8n et les ecrit dans le repo local.
# Usage : & ".\ops-tools\n8n\export-workflows.ps1" -N8nUrl $env:N8N_URL -ApiKey $env:N8N_API_KEY
#
# Comportement :
#   - Workflows archives (isArchived=true) : ignores par defaut (--IncludeArchived pour les inclure)
#   - Workflows vides (0 noeuds)           : ignores
#   - Noms en doublon dans n8n             : le second recoit le suffixe -<id> pour eviter l'ecrasement
#   - Fichier existant dont le nom matche  : UPDATE (ecrase)
#   - Aucun fichier existant               : NEW

param(
    [string]$N8nUrl        = $env:N8N_URL,
    [string]$ApiKey        = $env:N8N_API_KEY,
    [string]$OutputDir     = "AI_agents\seomnix\n8n-projects\workflows-b2c\workflows",
    [switch]$IncludeArchived
)

if (-not $N8nUrl)  { Write-Error "N8N_URL manquant (param ou env var)"; exit 1 }
if (-not $ApiKey)  { Write-Error "N8N_API_KEY manquant (param ou env var)"; exit 1 }

$N8nUrl  = $N8nUrl.TrimEnd('/')
$headers = @{ "X-N8N-API-KEY" = $ApiKey }

Write-Host "Connexion a $N8nUrl ..."

# Recupere tous les workflows (pagination simple, 200 max)
$list      = Invoke-RestMethod -Uri "$N8nUrl/api/v1/workflows?limit=200" -Headers $headers -Method GET
$workflows = $list.data

Write-Host "$($workflows.Count) workflows trouves."

$exported  = 0
$skipped   = 0
# Table des noms de fichiers deja utilises dans cette session (detection doublons)
$usedNames = @{}

foreach ($wf in $workflows) {
    $id   = $wf.id
    $name = $wf.name

    # Ignorer les workflows archives sauf si --IncludeArchived
    if ($wf.isArchived -and -not $IncludeArchived) {
        Write-Host "  SKIP    [archived] $name"
        $skipped++
        continue
    }

    # Telecharge le workflow complet
    $full = Invoke-RestMethod -Uri "$N8nUrl/api/v1/workflows/$id" -Headers $headers -Method GET

    # Ignorer les workflows vides (0 noeuds) - residus d'import
    $nodeCount = if ($full.nodes) { $full.nodes.Count } else { 0 }
    if ($nodeCount -eq 0) {
        Write-Host "  SKIP    [empty, 0 nodes] $name"
        $skipped++
        continue
    }

    # Genere un nom de fichier safe depuis le nom du workflow
    $safeName = $name -replace '[^a-zA-Z0-9\-_ ]', '' -replace '\s+', '-' -replace '-+', '-'
    $safeName = $safeName.ToLower().Trim('-')

    # Detection doublon de nom dans cette session : ajouter l'ID court en suffixe
    if ($usedNames.ContainsKey($safeName)) {
        $shortId  = $id.Substring(0, 8)
        $safeName = "$safeName-$shortId"
        Write-Host "  WARN    Doublon de nom detecte, suffixe ID ajoute : $safeName"
    }
    $usedNames[$safeName] = $true

    # Cherche un fichier existant dont le nom correspond (matching souple)
    $existing = Get-ChildItem -Path $OutputDir -Filter "*.json" | Where-Object {
        $base  = $_.BaseName.ToLower()
        $safe  = $safeName.ToLower()
        $base -like "*$safe*" -or $safe -like "*$base*"
    } | Sort-Object { ($_.BaseName.Length - $safeName.Length) } | Select-Object -First 1

    if ($existing) {
        $targetPath = $existing.FullName
        Write-Host "  UPDATE  $($existing.Name)  <-- $name  [nodes=$nodeCount, active=$($full.active)]"
    } else {
        $targetPath = Join-Path $OutputDir "$safeName.json"
        Write-Host "  NEW     $safeName.json  <-- $name  [nodes=$nodeCount, active=$($full.active)]"
    }

    $full | ConvertTo-Json -Depth 30 | Out-File -FilePath $targetPath -Encoding utf8
    $exported++
}

Write-Host ""
Write-Host "Export termine : $exported ecrits, $skipped ignores (archives/vides)."
Write-Host "Verifier les diffs avec : git diff $OutputDir"
