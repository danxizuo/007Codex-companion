[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Domain,

  [string]$CloudflaredToken = $env:DESKRELAY_CLOUDFLARED_TOKEN,
  [string]$Version = $(if ($env:DESKRELAY_COMPANION_VERSION) { $env:DESKRELAY_COMPANION_VERSION } elseif ($env:ICODEX_COMPANION_VERSION) { $env:ICODEX_COMPANION_VERSION } else { "v0.1.0-beta.2" }),
  [string]$ReleaseRepo = $(if ($env:DESKRELAY_COMPANION_RELEASE_REPO) { $env:DESKRELAY_COMPANION_RELEASE_REPO } elseif ($env:ICODEX_COMPANION_RELEASE_REPO) { $env:ICODEX_COMPANION_RELEASE_REPO } else { "danxizuo/007Codex-companion" }),
  [string]$InstallHome = $(if ($env:DESKRELAY_COMPANION_HOME) { $env:DESKRELAY_COMPANION_HOME } elseif ($env:ICODEX_COMPANION_HOME) { $env:ICODEX_COMPANION_HOME } else { Join-Path $env:USERPROFILE ".deskrelay-companion" }),
  [string]$HostName = $(if ($env:DESKRELAY_COMPANION_HOST) { $env:DESKRELAY_COMPANION_HOST } elseif ($env:ICODEX_COMPANION_HOST) { $env:ICODEX_COMPANION_HOST } else { "0.0.0.0" }),
  [int]$Port = $(if ($env:DESKRELAY_COMPANION_PORT) { [int]$env:DESKRELAY_COMPANION_PORT } elseif ($env:ICODEX_COMPANION_PORT) { [int]$env:ICODEX_COMPANION_PORT } else { 3939 }),
  [string]$Name = $(if ($env:DESKRELAY_COMPANION_NAME) { $env:DESKRELAY_COMPANION_NAME } elseif ($env:ICODEX_COMPANION_NAME) { $env:ICODEX_COMPANION_NAME } else { "DeskRelay Windows Companion" }),
  [switch]$SkipCloudflared
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Add-CurrentPath {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = @($machinePath, $userPath, $env:Path) -join ";"
}

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

function Install-WingetPackage {
  param(
    [string]$PackageId,
    [string]$DisplayName
  )

  $winget = Get-CommandPath @("winget.exe", "winget")
  if (-not $winget) {
    throw "$DisplayName is not installed and winget is unavailable. Install $DisplayName first, then rerun this script."
  }

  Write-Step "Installing $DisplayName"
  & $winget install --id $PackageId --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install $DisplayName with winget."
  }
  Add-CurrentPath
}

function Ensure-Node {
  $node = Get-CommandPath @("node.exe", "node")
  if (-not $node) {
    Install-WingetPackage -PackageId "OpenJS.NodeJS.LTS" -DisplayName "Node.js LTS"
    $node = Get-CommandPath @("node.exe", "node")
  }
  if (-not $node) {
    throw "Node.js is still unavailable after installation."
  }
  return $node
}

function Ensure-Pnpm {
  $pnpm = Get-CommandPath @("pnpm.cmd", "pnpm.exe", "pnpm")
  if ($pnpm) {
    return $pnpm
  }

  $corepack = Get-CommandPath @("corepack.cmd", "corepack.exe", "corepack")
  if ($corepack) {
    Write-Step "Enabling pnpm with Corepack"
    & $corepack enable
    Add-CurrentPath
    $pnpm = Get-CommandPath @("pnpm.cmd", "pnpm.exe", "pnpm")
    if ($pnpm) {
      return $pnpm
    }
  }

  $npm = Get-CommandPath @("npm.cmd", "npm.exe", "npm")
  if (-not $npm) {
    throw "pnpm is not installed and npm is unavailable."
  }

  Write-Step "Installing pnpm"
  & $npm install --global pnpm
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install pnpm."
  }
  Add-CurrentPath

  $pnpm = Get-CommandPath @("pnpm.cmd", "pnpm.exe", "pnpm")
  if (-not $pnpm) {
    throw "pnpm is still unavailable after installation."
  }
  return $pnpm
}

function Get-CodexExePath {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\codex.exe"),
    (Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe"),
    (Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-arm64\vendor\aarch64-pc-windows-msvc\codex\codex.exe")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }
  return $null
}

function Test-VersionAtLeast {
  param(
    [string]$VersionOutput,
    [int]$Major,
    [int]$Minor,
    [int]$Patch
  )

  if ($VersionOutput -notmatch "(\d+)\.(\d+)\.(\d+)") {
    return $false
  }

  $actualMajor = [int]$Matches[1]
  $actualMinor = [int]$Matches[2]
  $actualPatch = [int]$Matches[3]
  if ($actualMajor -ne $Major) {
    return $actualMajor -gt $Major
  }
  if ($actualMinor -ne $Minor) {
    return $actualMinor -gt $Minor
  }
  return $actualPatch -ge $Patch
}

function Add-UserPathPrefix {
  param([string]$Directory)
  $normalizedDirectory = $Directory.TrimEnd("\")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = $userPath -split ";" | Where-Object {
    $_ -and ($_.TrimEnd("\") -ne $normalizedDirectory)
  }
  [Environment]::SetEnvironmentVariable("Path", ($Directory + ";" + ($parts -join ";")), "User")
  $env:Path = @($Directory, $env:Path) -join ";"
}

function Ensure-CodexCli {
  $codexExe = Get-CodexExePath
  $shouldInstall = $true
  if ($codexExe) {
    try {
      $versionOutput = (& $codexExe --version 2>$null | Out-String).Trim()
      $shouldInstall = -not (Test-VersionAtLeast -VersionOutput $versionOutput -Major 0 -Minor 128 -Patch 0)
    } catch {
      $shouldInstall = $true
    }
  }

  if ($shouldInstall) {
    $npm = Get-CommandPath @("npm.cmd", "npm.exe", "npm")
    if (-not $npm) {
      throw "npm is unavailable. Install Node.js LTS first, then rerun this script."
    }

    Write-Step "Installing Codex app-server runtime"
    & $npm install -g "@openai/codex@0.128.0"
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to install @openai/codex."
    }
    Add-CurrentPath
    $codexExe = Get-CodexExePath
  }

  if (-not $codexExe) {
    throw "Codex app-server executable was not found after installation."
  }

  Add-UserPathPrefix -Directory (Split-Path $codexExe -Parent)
  return $codexExe
}

function Ensure-Cloudflared {
  $cloudflared = Get-CommandPath @("cloudflared.exe", "cloudflared")
  if (-not $cloudflared) {
    Install-WingetPackage -PackageId "Cloudflare.cloudflared" -DisplayName "cloudflared"
    $cloudflared = Get-CommandPath @("cloudflared.exe", "cloudflared")
  }
  if (-not $cloudflared) {
    throw "cloudflared is still unavailable after installation."
  }
  return $cloudflared
}

function Normalize-BaseUrl {
  param([string]$Value)
  $trimmed = $Value.Trim()
  if (-not $trimmed.Contains("://")) {
    $trimmed = "https://$trimmed"
  }
  $uri = [Uri]$trimmed
  if ($uri.Scheme -ne "https" -and $uri.Scheme -ne "http") {
    throw "Unsupported URL scheme: $($uri.Scheme)"
  }
  return $uri.GetLeftPart([UriPartial]::Authority).TrimEnd("/")
}

function Test-PortOpen {
  param([int]$CandidatePort)
  $client = [Net.Sockets.TcpClient]::new()
  try {
    $async = $client.BeginConnect("127.0.0.1", $CandidatePort, $null, $null)
    $connected = $async.AsyncWaitHandle.WaitOne(250)
    if ($connected) {
      $client.EndConnect($async)
      return $true
    }
    return $false
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Find-AvailablePort {
  param([int]$PreferredPort)
  $candidates = @($PreferredPort) + (3940..3999) + (4940..4999)
  foreach ($candidate in $candidates) {
    if (-not (Test-PortOpen -CandidatePort $candidate)) {
      return $candidate
    }
  }
  throw "No available Companion port was found."
}

function Stop-AndRemoveTask {
  param([string]$TaskName)
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }
}

function New-LongRunningTaskSettings {
  $command = Get-Command New-ScheduledTaskSettingsSet
  $supported = $command.Parameters
  $settingsArgs = @{}

  if ($supported.ContainsKey("AllowStartIfOnBatteries")) {
    $settingsArgs["AllowStartIfOnBatteries"] = $true
  }
  if ($supported.ContainsKey("DontStopIfGoingOnBatteries")) {
    $settingsArgs["DontStopIfGoingOnBatteries"] = $true
  }
  if ($supported.ContainsKey("ExecutionTimeLimit")) {
    $settingsArgs["ExecutionTimeLimit"] = [TimeSpan]::Zero
  }
  if ($supported.ContainsKey("RestartCount")) {
    $settingsArgs["RestartCount"] = 3
  }
  if ($supported.ContainsKey("RestartInterval")) {
    $settingsArgs["RestartInterval"] = New-TimeSpan -Minutes 1
  }

  return New-ScheduledTaskSettingsSet @settingsArgs
}

function Quote-TaskArgument {
  param([string]$Value)
  if ($Value.Contains(" ") -or $Value.Contains("`"")) {
    return '"' + $Value.Replace('"', '\"') + '"'
  }
  return $Value
}

function Read-TaskResultCode {
  param([string]$TaskName)
  try {
    return (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
  } catch {
    return $null
  }
}

function Wait-LocalStatus {
  param(
    [int]$StatusPort,
    [string]$AuthFile
  )

  $token = (Get-Content -Raw -Path $AuthFile).Trim()
  $headers = @{ Authorization = "Bearer $token" }
  for ($index = 0; $index -lt 30; $index++) {
    try {
      Invoke-RestMethod -Uri "http://127.0.0.1:$StatusPort/status" -Headers $headers -TimeoutSec 3 | Out-Null
      return
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  throw "Companion did not become healthy on 127.0.0.1:$StatusPort."
}

function Wait-PublicStatus {
  param(
    [string]$PublicBaseUrl,
    [string]$AuthFile
  )

  $token = (Get-Content -Raw -Path $AuthFile).Trim()
  $headers = @{ Authorization = "Bearer $token" }
  for ($index = 0; $index -lt 45; $index++) {
    try {
      Invoke-RestMethod -Uri "$PublicBaseUrl/status" -Headers $headers -TimeoutSec 5 | Out-Null
      return $true
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  return $false
}

function Get-LanBaseUrl {
  param([int]$StatusPort)

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
    return "http://$firstAddress`:$StatusPort"
  }
  return $null
}

function Start-CompanionTask {
  param(
    [string]$NodePath,
    [string]$CliPath,
    [string]$ConfigFile,
    [string]$AppDir
  )

  $taskName = "DeskRelayCompanion"
  Stop-AndRemoveTask -TaskName $taskName

  $arguments = @(
    (Quote-TaskArgument $CliPath),
    "start",
    "--config",
    (Quote-TaskArgument $ConfigFile)
  ) -join " "

  $action = New-ScheduledTaskAction -Execute $NodePath -Argument $arguments -WorkingDirectory $AppDir
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-LongRunningTaskSettings
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
}

function Start-CloudflaredTask {
  param(
    [string]$CloudflaredPath,
    [string]$PublicBaseUrl,
    [string]$CloudflaredToken,
    [int]$LocalPort,
    [string]$LogDir
  )

  $hostPrefix = ([Uri]$PublicBaseUrl).Host.Split(".")[0]
  $taskName = "DeskRelayTunnel-$hostPrefix"
  $logFile = Join-Path $LogDir "$taskName-cloudflared.log"
  Stop-AndRemoveTask -TaskName $taskName

  $arguments = @(
    "tunnel",
    "--no-autoupdate",
    "--logfile",
    (Quote-TaskArgument $logFile),
    "--loglevel",
    "info",
    "run",
    "--token",
    $CloudflaredToken,
    "--url",
    "http://127.0.0.1:$LocalPort"
  ) -join " "

  $action = New-ScheduledTaskAction -Execute $CloudflaredPath -Argument $arguments
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-LongRunningTaskSettings
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
  return $taskName
}

Add-CurrentPath

$publicBaseUrl = Normalize-BaseUrl -Value $Domain
$appDir = Join-Path $InstallHome "app"
$configFile = Join-Path $InstallHome "config.json"
$authFile = Join-Path $InstallHome "auth-token"
$logDir = Join-Path $InstallHome "logs"
$archiveName = "deskrelay-companion-$Version.tar.gz"
$archiveUrl = "https://github.com/$ReleaseRepo/releases/download/$Version/$archiveName"
$archivePath = Join-Path $env:TEMP $archiveName
$extractDir = Join-Path $env:TEMP "deskrelay-companion-$Version"

New-Item -ItemType Directory -Force -Path $InstallHome, $logDir | Out-Null

$node = Ensure-Node
$pnpm = Ensure-Pnpm
if (-not $SkipCloudflared -and $CloudflaredToken) {
  $cloudflared = Ensure-Cloudflared
}

Write-Step "Downloading DeskRelay Companion $Version"
Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath

Write-Step "Installing Companion files"
Stop-AndRemoveTask -TaskName "DeskRelayCompanion"
if (Test-Path $extractDir) {
  Remove-Item -Recurse -Force $extractDir
}
if (Test-Path $appDir) {
  Remove-Item -Recurse -Force $appDir
}
New-Item -ItemType Directory -Force -Path $appDir, $extractDir | Out-Null

$tar = Get-CommandPath @("tar.exe", "tar")
if (-not $tar) {
  throw "tar is unavailable. Install Windows tar support or extract $archiveName manually."
}
& $tar -xzf $archivePath -C $extractDir
if ($LASTEXITCODE -ne 0) {
  throw "Failed to extract $archiveName."
}
$innerDir = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
if (-not $innerDir) {
  throw "Release archive did not contain a Companion directory."
}
Copy-Item -Path (Join-Path $innerDir.FullName "*") -Destination $appDir -Recurse -Force

Write-Step "Installing Companion runtime dependencies"
& $pnpm -C $appDir install --prod --frozen-lockfile
if ($LASTEXITCODE -ne 0) {
  throw "Failed to install Companion runtime dependencies."
}
$codexExe = Ensure-CodexCli
Write-Host "Codex app-server runtime is available: $codexExe"

$selectedPort = Find-AvailablePort -PreferredPort $Port
$cliPath = Join-Path $appDir "packages\companion\dist\cli.js"
if (-not (Test-Path $cliPath)) {
  throw "Companion CLI was not found at $cliPath."
}

Write-Step "Writing Companion configuration"
& $node $cliPath configure `
  --config $configFile `
  --host $HostName `
  --port $selectedPort `
  --public-base-url $publicBaseUrl `
  --auth-token-file $authFile `
  --name $Name
if ($LASTEXITCODE -ne 0) {
  throw "Failed to configure Companion."
}

Write-Step "Starting Companion scheduled task"
Start-CompanionTask -NodePath $node -CliPath $cliPath -ConfigFile $configFile -AppDir $appDir
try {
  Wait-LocalStatus -StatusPort $selectedPort -AuthFile $authFile
} catch {
  $resultCode = Read-TaskResultCode -TaskName "DeskRelayCompanion"
  if ($null -ne $resultCode) {
    Write-Warning "DeskRelayCompanion LastTaskResult: $resultCode"
  }
  throw
}
Write-Host "Companion local service is healthy: http://127.0.0.1:$selectedPort"

if (-not $SkipCloudflared -and $CloudflaredToken) {
  Write-Step "Starting Cloudflare tunnel"
  $cloudflaredTask = Start-CloudflaredTask `
    -CloudflaredPath $cloudflared `
    -PublicBaseUrl $publicBaseUrl `
    -CloudflaredToken $CloudflaredToken `
    -LocalPort $selectedPort `
    -LogDir $logDir

  if (Wait-PublicStatus -PublicBaseUrl $publicBaseUrl -AuthFile $authFile) {
    Write-Host "Cloudflare public service is healthy: $publicBaseUrl"
  } else {
    Write-Warning "Cloudflare tunnel task $cloudflaredTask started, but $publicBaseUrl/status did not become healthy yet."
    Write-Warning "Check the log under $logDir and make sure the tunnel token belongs to this hostname."
  }
} elseif (-not $SkipCloudflared) {
  Write-Warning "No Cloudflare token was provided. Companion is usable on the local network only."
}

Write-Step "Pairing QR code"
$pairArgs = @($cliPath, "pair", "--config", $configFile)
if ($publicBaseUrl) {
  $pairArgs += @("--connection-url", $publicBaseUrl)
}
$lanBaseUrl = Get-LanBaseUrl -StatusPort $selectedPort
if ($lanBaseUrl) {
  $pairArgs += @("--connection-url", $lanBaseUrl)
}
& $node @pairArgs
if ($LASTEXITCODE -ne 0) {
  throw "Failed to print the pairing QR code."
}

Write-Host ""
Write-Host "DeskRelay Companion for Windows is installed and running."
Write-Host "Rerun this installer command any time you need to repair the Companion service or show the QR code again."
