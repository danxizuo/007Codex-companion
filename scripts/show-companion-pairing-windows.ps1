[CmdletBinding()]
param(
  [string]$InstallHome = $(if ($env:DESKRELAY_COMPANION_HOME) { $env:DESKRELAY_COMPANION_HOME } elseif ($env:ICODEX_COMPANION_HOME) { $env:ICODEX_COMPANION_HOME } else { Join-Path $env:USERPROFILE ".deskrelay-companion" })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CommandPath {
  param([string[]]$Names)
  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
      return $command.Source
    }
  }
  return $null
}

function Read-ConfigValue {
  param(
    [string]$ConfigFile,
    [string]$Key
  )
  if (-not (Test-Path $ConfigFile)) {
    return $null
  }
  $config = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json
  if ($config.PSObject.Properties.Name -contains $Key) {
    return $config.$Key
  }
  return $null
}

function Get-LanBaseUrl {
  param([int]$Port)
  $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -and
      $_.IPAddress -notlike "127.*" -and
      $_.IPAddress -notlike "169.254.*" -and
      $_.PrefixOrigin -ne "WellKnown"
    } |
    Select-Object -ExpandProperty IPAddress

  $firstAddress = $addresses | Select-Object -First 1
  if ($firstAddress) {
    return "http://$firstAddress`:$Port"
  }
  return $null
}

$node = Get-CommandPath @("node.exe", "node")
if (-not $node) {
  throw "Node.js is unavailable. Rerun the Windows Companion installer."
}

$configFile = Join-Path $InstallHome "config.json"
$cliPath = Join-Path $InstallHome "app\packages\companion\dist\cli.js"
if (-not (Test-Path $configFile)) {
  throw "Companion config was not found at $configFile."
}
if (-not (Test-Path $cliPath)) {
  throw "Companion CLI was not found at $cliPath."
}

$publicBaseUrl = Read-ConfigValue -ConfigFile $configFile -Key "publicBaseURL"
$portValue = Read-ConfigValue -ConfigFile $configFile -Key "port"
$port = if ($portValue) { [int]$portValue } else { 3939 }

$pairArgs = @($cliPath, "pair", "--config", $configFile)
if ($publicBaseUrl) {
  $pairArgs += @("--connection-url", [string]$publicBaseUrl)
}
$lanBaseUrl = Get-LanBaseUrl -Port $port
if ($lanBaseUrl) {
  $pairArgs += @("--connection-url", $lanBaseUrl)
}

& $node @pairArgs
