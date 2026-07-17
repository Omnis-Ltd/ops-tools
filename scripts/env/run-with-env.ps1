param(
  [Parameter(Mandatory=$true, Position=0)]
  [string]$Command,
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$EnvFile = $env:ENV_FILE
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
  $EnvFile = Join-Path $env:USERPROFILE ".config\env\notion.env"
}

if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) { return }
    $name = $parts[0].Trim()
    $value = $parts[1].Trim()
    # enlève éventuels guillemets simples/doubles
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
  }
}

& $Command @Args
exit $LASTEXITCODE

