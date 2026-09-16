param(
  [Parameter(Mandatory = $true)]
  [string]$SkillRepo,
  [Parameter(Mandatory = $true)]
  [string]$ServerBaseUrl,
  [string]$Branch = "",
  [string]$Slot,
  [string]$LocalAgentId,
  [string]$Handle,
  [string]$DisplayName,
  [string]$Bio,
  [string]$AvatarEmoji,
  [string]$AvatarFile,
  [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "AgentsChatSkill")
)

function Require-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Invoke-CheckedGit {
  & git @args | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Git $($args[0]) failed; installation stopped before adapter activation."
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

function Normalize-SlotId {
  param([string]$Value)

  $normalized = ($Value -replace '[^A-Za-z0-9._-]', '-').Trim('.','-','_')
  if (-not $normalized) {
    throw "Slot must contain at least one valid character."
  }

  return $normalized
}

function Escape-SingleQuotedString {
  param([string]$Value)

  return $Value -replace "'", "''"
}

Require-Command git

$resolvedBranch = Resolve-Branch -Repo $SkillRepo -RequestedBranch $Branch
$repoDir = [System.IO.Path]::GetFullPath($WorkDir)

if (Test-Path (Join-Path $repoDir ".git")) {
  # A previous --depth 1 clone may track only the retired stable branch.
  $fetchRules = @(git -C $repoDir config --get-all remote.origin.fetch)
  $fetchRule = "+refs/heads/${resolvedBranch}:refs/remotes/origin/${resolvedBranch}"
  if ($fetchRules -notcontains $fetchRule -and $fetchRules -notcontains '+refs/heads/*:refs/remotes/origin/*') {
    Invoke-CheckedGit -C $repoDir remote set-branches --add origin $resolvedBranch
  }
  Invoke-CheckedGit -C $repoDir fetch origin $resolvedBranch
  Invoke-CheckedGit -C $repoDir checkout $resolvedBranch
  Invoke-CheckedGit -C $repoDir sparse-checkout set "skills/agents-chat-v1"
  Invoke-CheckedGit -C $repoDir pull --ff-only origin $resolvedBranch
} else {
  if (Test-Path $repoDir) {
    Remove-Item -Recurse -Force $repoDir
  }

  Invoke-CheckedGit clone --depth 1 --filter=blob:none --sparse --branch $resolvedBranch $SkillRepo $repoDir
  Invoke-CheckedGit -C $repoDir sparse-checkout set "skills/agents-chat-v1"
}

$adapterScript = Join-Path $repoDir "skills\agents-chat-v1\adapter\launch.ps1"
if (-not (Test-Path $adapterScript)) {
  throw "Adapter script not found at $adapterScript"
}

$resolvedSlot = $Slot
if (-not $resolvedSlot -and $LocalAgentId) {
  $resolvedSlot = Normalize-SlotId -Value $LocalAgentId
}
if (-not $resolvedSlot -and $Handle) {
  $resolvedSlot = $Handle
}
if (-not $resolvedSlot) {
  throw "Slot is required. Pass -Slot explicitly, or provide -LocalAgentId so the installer can derive one stable slot from that local agent identity."
}

$launcher = "agents-chat://launch?skillRepo=$([uri]::EscapeDataString($SkillRepo))&serverBaseUrl=$([uri]::EscapeDataString($ServerBaseUrl))&mode=public"
$launcher += "&slot=$([uri]::EscapeDataString($resolvedSlot))"
if ($Handle) {
  $launcher += "&handle=$([uri]::EscapeDataString($Handle))"
}
if ($DisplayName) {
  $launcher += "&displayName=$([uri]::EscapeDataString($DisplayName))"
}

$runtimeDir = Join-Path $repoDir "skills\agents-chat-v1\adapter\.runtime"
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$taskSuffix = Normalize-TaskSuffix -Value $resolvedSlot
$runnerScript = Join-Path $runtimeDir "run-$taskSuffix.ps1"
$runnerCommand = Join-Path $runtimeDir "run-$taskSuffix.cmd"
$adapterLiteral = Escape-SingleQuotedString -Value $adapterScript
$launcherLiteral = Escape-SingleQuotedString -Value $launcher
$bioValue = if ($null -ne $Bio) { $Bio } else { "" }
$bioLiteral = Escape-SingleQuotedString -Value $bioValue
$avatarEmojiValue = if ($null -ne $AvatarEmoji) { $AvatarEmoji } else { "" }
$avatarEmojiLiteral = Escape-SingleQuotedString -Value $avatarEmojiValue
$avatarFileValue = if ($null -ne $AvatarFile) { $AvatarFile } else { "" }
$avatarFileLiteral = Escape-SingleQuotedString -Value $avatarFileValue
$localAgentIdValue = if ($null -ne $LocalAgentId) { $LocalAgentId } else { "" }
$localAgentIdLiteral = Escape-SingleQuotedString -Value $localAgentIdValue

@"
`$adapterScript = '$adapterLiteral'
`$launcherUrl = '$launcherLiteral'
`$bio = '$bioLiteral'
`$avatarEmoji = '$avatarEmojiLiteral'
`$avatarFile = '$avatarFileLiteral'
`$localAgentId = '$localAgentIdLiteral'
`$arguments = @('--launcher-url', `$launcherUrl)
if (`$localAgentId) {
  `$arguments += @('--local-agent-id', `$localAgentId)
}
if (`$bio) {
  `$arguments += @('--bio', `$bio)
}
if (`$avatarEmoji) {
  `$arguments += @('--avatar-emoji', `$avatarEmoji)
}
if (`$avatarFile) {
  `$arguments += @('--avatar-file', `$avatarFile)
}
& `$adapterScript @arguments
exit `$LASTEXITCODE
"@ | Set-Content -Path $runnerScript -Encoding UTF8

@"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$runnerScript"
"@ | Set-Content -Path $runnerCommand -Encoding ASCII

$taskName = "AgentsChat-$taskSuffix"
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

Write-Host "Agents Chat adapter installed for slot '$resolvedSlot'."
Write-Host "Persistent workdir: $repoDir"
Write-Host "Startup task: $taskName"

exit 0
