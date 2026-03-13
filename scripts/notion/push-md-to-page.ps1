param(
  [Parameter(Mandatory = $true)]
  [string]$MetaPath,

  [ValidateSet("replace", "append")]
  [string]$Mode = "replace",

  [switch]$DryRun
)

function Fail($msg) { Write-Error $msg; exit 1 }

# --- Preconditions ---
if (-not $env:NOTION_API_KEY) { Fail "Missing NOTION_API_KEY" }

$metaFull = Resolve-Path $MetaPath -ErrorAction Stop
$meta = Get-Content $metaFull -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $meta.files_written) { Fail "Invalid meta: files_written missing" }

$mdPath = $meta.files_written | Where-Object { $_ -like "*.md" } | Select-Object -First 1
if (-not $mdPath) { Fail "Invalid meta: markdown export not found in files_written" }

$mdFull = Resolve-Path $mdPath -ErrorAction Stop
$md = Get-Content $mdFull -Raw -Encoding UTF8

# Resolve target page id
$pageId = $null
if ($meta.notion_target_page_id) { $pageId = $meta.notion_target_page_id }
elseif ($env:NOTION_TARGET_PAGE_ID) { $pageId = $env:NOTION_TARGET_PAGE_ID }
if (-not $pageId) { Fail "No target page id found (meta.notion_target_page_id or NOTION_TARGET_PAGE_ID)" }

# --- TLS 1.2 (required for Notion API on PS 5.1) ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Notion headers ---
$headers = @{
  "Authorization" = "Bearer $($env:NOTION_API_KEY)"
  "Notion-Version" = "2022-06-28"
  "Content-Type" = "application/json; charset=utf-8"
}

# --- Hash (idempotence) ---
function Get-Sha256Hex([string]$text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

$newHash = Get-Sha256Hex $md
$hashMarker = "omnis-doc-hash: $newHash"

# Read existing marker hash (if any)
function Get-ExistingHashFromPage([string]$pageId) {
  $url = "https://api.notion.com/v1/blocks/$pageId/children?page_size=100"
  try {
    $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
  } catch {
    return $null
  }

  foreach ($b in $resp.results) {
    if ($b.type -eq "paragraph" -and $b.paragraph -and $b.paragraph.rich_text) {
      $txt = ($b.paragraph.rich_text | ForEach-Object { $_.plain_text }) -join ""
      if ($txt -match '^omnis-doc-hash:\s*([a-f0-9]{64})\s*$') {
        return $Matches[1]
      }
    }
  }
  return $null
}

$existingHash = Get-ExistingHashFromPage $pageId

Write-Host "Target page: $pageId"
Write-Host "Mode: $Mode"
Write-Host "Markdown file: $mdFull"
Write-Host "New hash: $newHash"
if ($existingHash) { Write-Host "Existing hash: $existingHash" }

if ($Mode -eq "replace" -and $existingHash -eq $newHash) {
  Write-Host "✅ No change detected (hash match). Skipping replace."
  exit 0
}

if ($DryRun) {
  Write-Host "DryRun enabled: no changes will be sent to Notion."
  exit 0
}

# --- Rich text helpers (light inline parsing) ---
function New-TextNode([string]$content, [bool]$bold=$false, [bool]$code=$false) {
  $node = @{
    type = "text"
    text = @{ content = $content }
    annotations = @{
      bold = $bold
      italic = $false
      strikethrough = $false
      underline = $false
      code = $code
      color = "default"
    }
  }
  return $node
}

function Parse_Inline([string]$line) {
  # Light parsing: **bold** and `code` (non-nested, left-to-right)
  $out = New-Object System.Collections.Generic.List[object]
  $i = 0
  while ($i -lt $line.Length) {
    # inline code
    if ($i -le $line.Length-1 -and $line[$i] -eq '`') {
      $j = $line.IndexOf('`', $i+1)
      if ($j -gt $i) {
        $codeText = $line.Substring($i+1, $j-$i-1)
        if ($codeText.Length -gt 0) { $out.Add((New-TextNode $codeText $false $true)) }
        $i = $j + 1
        continue
      }
    }
    # bold
    if ($i -le $line.Length-2 -and $line.Substring($i,2) -eq "**") {
      $j = $line.IndexOf("**", $i+2)
      if ($j -gt $i) {
        $boldText = $line.Substring($i+2, $j-($i+2))
        if ($boldText.Length -gt 0) { $out.Add((New-TextNode $boldText $true $false)) }
        $i = $j + 2
        continue
      }
    }
    # normal chunk until next marker
    $next = $line.Length
    $idxCode = $line.IndexOf('`', $i)
    if ($idxCode -ge 0 -and $idxCode -lt $next) { $next = $idxCode }
    $idxBold = $line.IndexOf("**", $i)
    if ($idxBold -ge 0 -and $idxBold -lt $next) { $next = $idxBold }
    $chunk = $line.Substring($i, $next-$i)
    if ($chunk.Length -gt 0) { $out.Add((New-TextNode $chunk $false $false)) }
    $i = $next
  }

  if ($out.Count -eq 0) {
    $out.Add((New-TextNode "" $false $false))
  }
  return ,$out
}

# --- Markdown -> Blocks (improved) ---
$lines = $md -split "`r`n|`n|`r"
$blocks = New-Object System.Collections.Generic.List[object]

# Put hash marker first (so we can detect idempotence next time)
$blocks.Add(@{
  object="block"
  type="paragraph"
  paragraph=@{ rich_text = (Parse_Inline $hashMarker) }
})

$inCode = $false
$codeLang = ""
$codeBuf = New-Object System.Collections.Generic.List[string]
$inTable   = $false
$tableRows = New-Object System.Collections.Generic.List[object]
$tableWidth = 0

function Flush-Table {
  if ($script:tableRows.Count -gt 0) {
    $tw = if ($script:tableWidth -gt 0) { $script:tableWidth } else { 1 }
    $rowsSnap = $script:tableRows.ToArray()
    $tblBlock = @{
      object = "block"
      type   = "table"
      table  = @{
        table_width       = $tw
        has_column_header = $true
        has_row_header    = $false
        children          = $rowsSnap
      }
    }
    $script:blocks.Add($tblBlock) | Out-Null
    $script:tableRows.Clear()
    $script:tableWidth = 0
  }
  $script:inTable = $false
}


foreach ($raw in $lines) {
  $line = $raw.TrimEnd()

  # fence code
  if ($line -match '^\s*```') {
    if (-not $inCode) {
      $inCode = $true
      $codeLang = ($line -replace '^\s*```', '').Trim()
      $codeBuf.Clear()
    } else {
      $inCode = $false
      $codeText = ($codeBuf -join "`n")
      $blocks.Add(@{
        object="block"
        type="code"
        code=@{
          rich_text = @(@{ type="text"; text=@{ content=$codeText } })
          language = ($(if ($codeLang) { $codeLang } else { "plain text" }))
        }
      })
      $codeLang = ""
      $codeBuf.Clear()
    }
    continue
  }

  if ($inCode) {
    $codeBuf.Add($line) | Out-Null
    continue
  }

  # flush table when leaving table context (non-table line or blank)
  if ($inTable -and $line -notmatch '^\s*\|') { Flush-Table }

  if ($line.Trim() -eq "") { continue }

  # --- table row ---
  if ($line -match '^\s*\|') {
    # separator row (|---|---) → skip, end of header
    if ($line -match '^\s*\|[\s\-\|:]+\|?\s*$') {
      $inTable = $true
      continue
    }
    $rawCells = ($line.Trim() -replace '^\|','' -replace '\|$','') -split '\|' | ForEach-Object { $_.Trim() }
    if ($rawCells.Count -gt $tableWidth) { $tableWidth = $rawCells.Count }
    # Build cell arrays without PS flattening: each cell = [object[]] array of rich-text nodes
    $cellList = New-Object 'System.Collections.Generic.List[System.Object]'
    foreach ($ct in $rawCells) {
      $cellList.Add([System.Object[]]@(@{ type="text"; text=@{ content=$ct } })) | Out-Null
    }
    $tableRows.Add(@{
      type      = "table_row"
      table_row = @{ cells = $cellList.ToArray() }
    }) | Out-Null
    $inTable = $true
    continue
  }

  # horizontal rule
  if ($line -match '^\s*(---|\*\*\*|___)\s*$') {
    $blocks.Add(@{ object="block"; type="divider"; divider=@{} })
    continue
  }

  # blockquote
  if ($line -match '^\s*>\s+(.*)$') {
    $t = $Matches[1]
    $blocks.Add(@{
      object="block"
      type="quote"
      quote=@{ rich_text = (Parse_Inline $t) }
    })
    continue
  }

  # headings
  if ($line -match '^\s*###\s+(.*)$') {
    $t = $Matches[1]
    $blocks.Add(@{ object="block"; type="heading_3"; heading_3=@{ rich_text=(Parse_Inline $t) } })
    continue
  }
  if ($line -match '^\s*##\s+(.*)$') {
    $t = $Matches[1]
    $blocks.Add(@{ object="block"; type="heading_2"; heading_2=@{ rich_text=(Parse_Inline $t) } })
    continue
  }
  if ($line -match '^\s*#\s+(.*)$') {
    $t = $Matches[1]
    $blocks.Add(@{ object="block"; type="heading_1"; heading_1=@{ rich_text=(Parse_Inline $t) } })
    continue
  }

  # numbered list: "1. item"
  if ($line -match '^\s*\d+\.\s+(.*)$') {
    $t = $Matches[1]
    $blocks.Add(@{
      object="block"
      type="numbered_list_item"
      numbered_list_item=@{ rich_text=(Parse_Inline $t) }
    })
    continue
  }

  # bulleted list
  if ($line -match '^\s*[-\*]\s+(.*)$') {
    $t = $Matches[1]
    $blocks.Add(@{
      object="block"
      type="bulleted_list_item"
      bulleted_list_item=@{ rich_text=(Parse_Inline $t) }
    })
    continue
  }

  # paragraph
  $blocks.Add(@{
    object="block"
    type="paragraph"
    paragraph=@{ rich_text=(Parse_Inline $line) }
  })
}

# flush table at end of file (if markdown ends with a table)
if ($inTable) { Flush-Table }

# --- Chunking (100 max) ---
$chunkSize = 100
$chunks = @()
for ($i=0; $i -lt $blocks.Count; $i += $chunkSize) {
  $end = [Math]::Min($i + $chunkSize - 1, $blocks.Count - 1)
  $chunks += ,($blocks.GetRange($i, $end - $i + 1))
}

Write-Host "Blocks to push: $($blocks.Count) in $($chunks.Count) request(s)"

# --- Replace: erase existing content ---
if ($Mode -eq "replace") {
  $eraseUrl = "https://api.notion.com/v1/pages/$pageId"
  $eraseBody = @{ erase_content = $true } | ConvertTo-Json -Depth 5
  try {
    Invoke-RestMethod -Method Patch -Uri $eraseUrl -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($eraseBody)) | Out-Null
    Write-Host "✅ Existing page content erased."
  } catch {
    Fail "Erase content failed: $($_.Exception.Message)"
  }
}

# --- Append blocks ---
foreach ($c in $chunks) {
  $appendUrl = "https://api.notion.com/v1/blocks/$pageId/children"
  $appendBody = @{ children = $c } | ConvertTo-Json -Depth 12 -Compress
  if ($chunks.IndexOf($c) -eq 0) {   [System.IO.File]::WriteAllText("C:\Users\delfa\debug-chunk0.json", $appendBody, [System.Text.Encoding]::UTF8) }
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($appendBody)
  try {
    Invoke-RestMethod -Method Patch -Uri $appendUrl -Headers $headers -Body $bodyBytes | Out-Null
  } catch {
    Fail "Append blocks failed: $($_.Exception.Message)"
  }
}

Write-Host "✅ Notion push completed ($Mode)."
exit 0
