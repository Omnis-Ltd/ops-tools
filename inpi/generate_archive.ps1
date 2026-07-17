param(
    [Parameter(Mandatory)] [string]   $ProjectName,
    [Parameter(Mandatory)] [string]   $Owner,
    [Parameter(Mandatory)] [string]   $Email,
    [string]   $GitRepo       = "",
    [string[]] $ExtraFolders  = @(),
    [string]   $OutputDir     = "",
    [string]   $WorkspaceRoot = (Get-Location).Path,
    [string[]] $ExcludeDirs   = @(),
    [string[]] $ExcludeGlobs  = @(),
    [switch]   $SkipLicense
)

$ErrorActionPreference = "Stop"

$BaseDirs  = @("__pycache__", ".git", "dist", "node_modules", ".venv", ".astro", "graphify-out", ".claude")
$BaseGlobs = @("*.pyc", "*.log", ".env", "*.env", "pnpm-lock.yaml", "package-lock.json")
$AllDirs   = $BaseDirs  + $ExcludeDirs
$AllGlobs  = $BaseGlobs + $ExcludeGlobs

$Date = Get-Date -Format "yyyy-MM-dd"
if (-not $OutputDir) { $OutputDir = "INPI\" + $ProjectName }
$OutFull  = Join-Path $WorkspaceRoot $OutputDir
$ZipName  = ($ProjectName.ToLower() -replace " ", "-") + "-inpi-soleau-$Date.zip"
$TmpDir   = "$OutFull\tmp_$Date"

Write-Host "=== INPI e-Soleau - $ProjectName ===" -ForegroundColor Cyan
Write-Host "Owner : $Owner ($Email)"
Write-Host "Out   : $OutFull\$ZipName"
Write-Host ""

New-Item -ItemType Directory -Force -Path $OutFull | Out-Null
if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

$Commit = "(no git)"

# 1 - git archive
if ($GitRepo) {
    $Full = Join-Path $WorkspaceRoot $GitRepo
    Write-Host "[1] git archive: $GitRepo" -ForegroundColor Yellow
    Push-Location $Full
    $Commit = git rev-parse HEAD
    $Leaf = Split-Path $GitRepo -Leaf
    New-Item -ItemType Directory -Force -Path "$TmpDir\$Leaf" | Out-Null
    git archive --format=zip --output="$TmpDir\g.zip" HEAD
    Expand-Archive -Path "$TmpDir\g.zip" -DestinationPath "$TmpDir\$Leaf" -Force
    Remove-Item "$TmpDir\g.zip"
    Pop-Location
    Write-Host "    commit: $Commit" -ForegroundColor Gray
    Write-Host "    OK" -ForegroundColor Green
}

# 2 - extra folders
foreach ($folder in $ExtraFolders) {
    $src = Join-Path $WorkspaceRoot $folder
    $dst = Join-Path $TmpDir (Split-Path $folder -Leaf)
    Write-Host "[2] copy: $folder" -ForegroundColor Yellow
    Get-ChildItem -Path $src -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $item = $_
        $rel  = $item.FullName.Substring($src.Length + 1)
        $segs = $rel -split "\\"
        $skip = $false
        foreach ($s in $segs) { if ($AllDirs -contains $s) { $skip = $true; break } }
        if (-not $skip -and -not $item.PSIsContainer) {
            foreach ($g in $AllGlobs) { if ($item.Name -like $g) { $skip = $true; break } }
        }
        if (-not $skip) {
            $dest = Join-Path $dst $rel
            if ($item.PSIsContainer) {
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
            } else {
                $p = Split-Path $dest -Parent
                if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
                Copy-Item -Path $item.FullName -Destination $dest -Force
            }
        }
    }
    Write-Host "    OK" -ForegroundColor Green
}

# 3 - manifeste
Write-Host "[3] manifeste..." -ForegroundColor Yellow
$m = Get-ChildItem -Path $OutFull -Filter "*Manifeste*.txt" -ErrorAction SilentlyContinue |
     Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($m) {
    Copy-Item -Path $m.FullName -Destination "$TmpDir\MANIFESTE.txt" -Force
    Write-Host "    $($m.Name)" -ForegroundColor Gray
} else {
    $tpl = Join-Path $PSScriptRoot "template_manifeste.txt"
    if (Test-Path $tpl) {
        $txt = (Get-Content $tpl -Raw -Encoding UTF8) `
            -replace "{{PROJECT_NAME}}", $ProjectName `
            -replace "{{OWNER}}",        $Owner `
            -replace "{{EMAIL}}",        $Email `
            -replace "{{DATE}}",         $Date `
            -replace "{{COMMIT}}",       $Commit `
            -replace "{{ARCHIVE_NAME}}", $ZipName
        Set-Content "$TmpDir\MANIFESTE.txt" $txt -Encoding UTF8
        Write-Host "    generated from template" -ForegroundColor Gray
    }
}

# 4 - license
if (-not $SkipLicense) {
    $tpl = Join-Path $PSScriptRoot "template_license.md"
    if (Test-Path $tpl) {
        $txt = (Get-Content $tpl -Raw -Encoding UTF8) `
            -replace "{{PROJECT_NAME}}", $ProjectName `
            -replace "{{OWNER}}",        $Owner `
            -replace "{{EMAIL}}",        $Email `
            -replace "{{YEAR}}",         (Get-Date -Format "yyyy")
        Set-Content "$TmpDir\LICENSE.md" $txt -Encoding UTF8
        Write-Host "[4] LICENSE.md added" -ForegroundColor Green
    }
}

# 5 - compress
Write-Host "[5] compressing..." -ForegroundColor Yellow
$Out = Join-Path $OutFull $ZipName
if (Test-Path $Out) { Remove-Item $Out -Force }
Compress-Archive -Path "$TmpDir\*" -DestinationPath $Out -CompressionLevel Optimal
Remove-Item -Recurse -Force $TmpDir

$Hash = (Get-FileHash -Path $Out -Algorithm SHA256).Hash
$KB   = [math]::Round((Get-Item $Out).Length / 1KB, 1)

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "File   : $Out"
Write-Host "Size   : $KB KB"
Write-Host "SHA256 : $Hash"
Write-Host "Commit : $Commit"
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Preview : Expand-Archive '$Out' -DestinationPath '$OutFull\preview'"
Write-Host "  2. Deposit : https://www.inpi.fr -> e-Soleau numerique"
Write-Host "  3. Add DSO number to MANIFESTE.txt + /mentions-legales"
Write-Host ""
Write-Host "RESULT_JSON: archive=$Out|sha256=$Hash|size_kb=$KB|commit=$Commit"
