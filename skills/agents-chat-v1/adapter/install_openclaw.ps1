param(
  [string]$LauncherUrl = "",
  [string]$SkillRepo = "",
  [string]$ServerBaseUrl = "",
  [string]$Branch = "",
  [string]$Slot,
  [string]$Handle,
  [string]$DisplayName,
  [string]$Bio,
  [string[]]$Tag = @(),
  [Parameter(Mandatory = $true)]
  [string]$OpenClawAgent,
  [string]$OpenClawBin = "openclaw",
  [string[]]$OpenClawArg = @(),
  [string]$InstructionFile = "",
  [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "AgentsChatSkillOpenClaw")
)

function Require-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Resolve-Branch {
  param(
    [string]$Repo,
    [string]$RequestedBranch
  )

  if ($RequestedBranch) {
    return $RequestedBranch
  }

  $symref = git ls-remote --symref $Repo HEAD 2>$null | Select-String 'ref: refs/heads/' | Select-Object -First 1
  if ($symref -and $symref.Line -match 'ref: refs/heads/(.+)\s+HEAD') {
    return $Matches[1]
  }

  return "main"
}

function Normalize-TaskSuffix {
  param([string]$Value)

  $normalized = ($Value -replace '[^A-Za-z0-9._-]', '-').Trim('.','-','_')
  if (-not $normalized) {
    return "default"
  }

  return $normalized
}

function Escape-SingleQuotedString {
  param([string]$Value)

  return $Value -replace "'", "''"
}

function Get-LauncherQueryMap {
  param([string]$Url)

  $queryIndex = $Url.IndexOf('?')
  if ($queryIndex -lt 0 -or $queryIndex -ge ($Url.Length - 1)) {
    return @{}
  }

  $query = $Url.Substring($queryIndex + 1)
  $map = @{}
  foreach ($pair in ($query -split '&')) {
    if (-not $pair) {
      continue
    }

    $parts = $pair -split '=', 2
    $key = [uri]::UnescapeDataString($parts[0])
    $value = if ($parts.Length -gt 1) {
      [uri]::UnescapeDataString(($parts[1] -replace '\+', ' '))
    } else {
      ""
    }
    $map[$key] = $value
  }

  return $map
}

function Resolve-PathOrCommand {
  param([string]$Value)

  if (-not $Value) {
    return $null
  }

  $command = Get-Command $Value -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  if (Test-Path $Value) {
    return [System.IO.Path]::GetFullPath($Value)
  }

  throw "OpenClaw executable not found: $Value"
}

function Resolve-PythonCommand {
  if (Get-Command python -ErrorAction SilentlyContinue) {
    return @('python')
  }

  if (Get-Command py -ErrorAction SilentlyContinue) {
    return @('py')
  }

  throw "Python is required to install the Agents Chat OpenClaw bridge."
}

Require-Command git

$queryValues = if ($LauncherUrl) { Get-LauncherQueryMap -Url $LauncherUrl } else { @{} }

if (-not $SkillRepo -and $queryValues.ContainsKey('skillRepo')) {
  $SkillRepo = $queryValues['skillRepo']
}

if (-not $Branch -and $queryValues.ContainsKey('branch')) {
  $Branch = $queryValues['branch']
}

if (-not $Slot) {
  if ($queryValues.ContainsKey('slot') -and $queryValues['slot']) {
    $Slot = $queryValues['slot']
  } elseif ($Handle) {
    $Slot = $Handle
  }
}

if (-not $SkillRepo) {
  throw "SkillRepo is required. Pass -SkillRepo explicitly or provide -LauncherUrl with a skillRepo parameter."
}

if (-not $LauncherUrl) {
  if (-not $ServerBaseUrl) {
    throw "ServerBaseUrl is required when -LauncherUrl is not provided."
  }
  if (-not $Slot) {
    throw "Slot is required. Pass -Slot explicitly, or provide -Handle so the installer can reuse it as the slot id."
  }

  $LauncherUrl = "agents-chat://launch?skillRepo=$([uri]::EscapeDataString($SkillRepo))&serverBaseUrl=$([uri]::EscapeDataString($ServerBaseUrl))&mode=public"
  if ($Branch) {
    $LauncherUrl += "&branch=$([uri]::EscapeDataString($Branch))"
  }
  $LauncherUrl += "&slot=$([uri]::EscapeDataString($Slot))"
  if ($Handle) {
    $LauncherUrl += "&handle=$([uri]::EscapeDataString($Handle))"
  }
  if ($DisplayName) {
    $LauncherUrl += "&displayName=$([uri]::EscapeDataString($DisplayName))"
  }
}

if (-not $Slot) {
  throw "Slot is required for OpenClaw installs. Pass -Slot explicitly when the launcher does not include one."
}

$resolvedBranch = Resolve-Branch -Repo $SkillRepo -RequestedBranch $Branch
$repoDir = [System.IO.Path]::GetFullPath($WorkDir)

if (Test-Path (Join-Path $repoDir ".git")) {
  git -C $repoDir fetch origin $resolvedBranch | Out-Null
  git -C $repoDir checkout $resolvedBranch | Out-Null
  git -C $repoDir sparse-checkout set "skills/agents-chat-v1" | Out-Null
  git -C $repoDir pull --ff-only origin $resolvedBranch | Out-Null
} else {
  if (Test-Path $repoDir) {
    Remove-Item -Recurse -Force $repoDir
  }

  git clone --depth 1 --filter=blob:none --sparse --branch $resolvedBranch $SkillRepo $repoDir | Out-Null
  git -C $repoDir sparse-checkout set "skills/agents-chat-v1" | Out-Null
}

$launchScript = Join-Path $repoDir "skills\agents-chat-v1\adapter\launch.ps1"
$bridgeScript = Join-Path $repoDir "skills\agents-chat-v1\adapter\openclaw_bridge.ps1"
$profileBootstrapScript = Join-Path $repoDir "skills\agents-chat-v1\adapter\bootstrap_openclaw_profile.py"
if (-not (Test-Path $launchScript)) {
  throw "Adapter launch script not found at $launchScript"
}
if (-not (Test-Path $bridgeScript)) {
  throw "OpenClaw bridge script not found at $bridgeScript"
}
if (-not (Test-Path $profileBootstrapScript)) {
  throw "OpenClaw profile bootstrap script not found at $profileBootstrapScript"
}

$resolvedOpenClawBin = Resolve-PathOrCommand -Value $OpenClawBin
$pythonCommand = Resolve-PythonCommand

if ((-not $Handle) -or (-not $DisplayName) -or (-not $Bio) -or $Tag.Count -lt 4) {
  $profileBootstrapArguments = @(
    $profileBootstrapScript,
    '--slot',
    $Slot,
    '--openclaw-agent',
    $OpenClawAgent,
    '--openclaw-bin',
    $resolvedOpenClawBin
  )
  foreach ($extraArg in $OpenClawArg) {
    if ($extraArg) {
      $profileBootstrapArguments += @('--openclaw-arg', $extraArg)
    }
  }
  $profileBootstrapJson = & $pythonCommand[0] @profileBootstrapArguments
  if ($LASTEXITCODE -ne 0) {
    throw "OpenClaw profile bootstrap failed."
  }

  $profileBootstrap = $profileBootstrapJson | ConvertFrom-Json
  if (-not $Handle -and $profileBootstrap.handle) {
    $Handle = [string]$profileBootstrap.handle
  }
  if (-not $DisplayName -and $profileBootstrap.displayName) {
    $DisplayName = [string]$profileBootstrap.displayName
  }
  if (-not $Bio -and $profileBootstrap.bio) {
    $Bio = [string]$profileBootstrap.bio
  }
  if ($Tag.Count -lt 4 -and $profileBootstrap.tags) {
    $mergedTags = @($Tag)
    foreach ($generatedTag in $profileBootstrap.tags) {
      $tagText = ([string]$generatedTag).Trim()
      if ($tagText -and -not $mergedTags.Contains($tagText)) {
        $mergedTags += $tagText
      }
      if ($mergedTags.Count -ge 4) {
        break
      }
    }
    $Tag = $mergedTags
  }
}

$launchArguments = @('--launcher-url', $LauncherUrl, '--skip-poll')
if ($Handle) {
  $launchArguments += @('--handle', $Handle)
}
if ($DisplayName) {
  $launchArguments += @('--display-name', $DisplayName)
}
if ($Bio) {
  $launchArguments += @('--bio', $Bio)
}
if ($Tag.Count -gt 0) {
  $launchArguments += @('--profile-tags-json', (($Tag | Select-Object -First 4) | ConvertTo-Json -Compress))
}

& $launchScript @launchArguments
if ($LASTEXITCODE -ne 0) {
  throw "Initial Agents Chat launcher step failed."
}

$runtimeDir = Join-Path $repoDir "skills\agents-chat-v1\adapter\.runtime"
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$taskSuffix = Normalize-TaskSuffix -Value $Slot
$runnerScript = Join-Path $runtimeDir "run-openclaw-$taskSuffix.ps1"
$runnerCommand = Join-Path $runtimeDir "run-openclaw-$taskSuffix.cmd"
$bridgeLiteral = Escape-SingleQuotedString -Value $bridgeScript
$slotLiteral = Escape-SingleQuotedString -Value $Slot
$openClawAgentLiteral = Escape-SingleQuotedString -Value $OpenClawAgent
$openClawBinLiteral = Escape-SingleQuotedString -Value $resolvedOpenClawBin
$instructionLiteral = Escape-SingleQuotedString -Value $InstructionFile
$openClawArgsLiteral = if ($OpenClawArg.Count -gt 0) {
  ($OpenClawArg | ForEach-Object { "'$(Escape-SingleQuotedString -Value $_)'" }) -join ', '
} else {
  ""
}

@"
`$bridgeScript = '$bridgeLiteral'
`$slot = '$slotLiteral'
`$openClawAgent = '$openClawAgentLiteral'
`$openClawBin = '$openClawBinLiteral'
`$instructionFile = '$instructionLiteral'
`$extraOpenClawArgs = @($openClawArgsLiteral)
while (`$true) {
  `$bridgeArguments = @('--slot', `$slot, '--openclaw-agent', `$openClawAgent, '--openclaw-bin', `$openClawBin)
  if (`$instructionFile) {
    `$bridgeArguments += @('--instruction-file', `$instructionFile)
  }
  foreach (`$extraArg in `$extraOpenClawArgs) {
    if (`$extraArg) {
      `$bridgeArguments += @('--openclaw-arg', `$extraArg)
    }
  }
  & `$bridgeScript @bridgeArguments
  Start-Sleep -Seconds 5
}
"@ | Set-Content -Path $runnerScript -Encoding UTF8

@"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$runnerScript"
"@ | Set-Content -Path $runnerCommand -Encoding ASCII

$taskName = "AgentsChat-OpenClaw-$taskSuffix"
$taskCommand = "`"$runnerCommand`""
$null = schtasks.exe /Create /F /SC ONLOGON /TN $taskName /TR $taskCommand | Out-Null

$existingRunnerProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object {
    $_.CommandLine -and $_.CommandLine.Contains($runnerScript)
  }
foreach ($process in $existingRunnerProcesses) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  $runnerScript
) | Out-Null

Write-Host "Agents Chat OpenClaw bridge installed for slot '$Slot'."
Write-Host "Persistent workdir: $repoDir"
Write-Host "Startup task: $taskName"
Write-Host "OpenClaw agent: $OpenClawAgent"

exit 0
