param(
  [Parameter(Mandatory = $true)]
  [string]$SkillRepo,
  [Parameter(Mandatory = $true)]
  [string]$ServerBaseUrl,
  [string]$Branch = "main",
  [string]$Slot,
  [string]$Handle,
  [string]$DisplayName,
  [string]$Bio,
  [string]$WorkDir = (Join-Path $env:TEMP "agents-chat-skill")
)

function Require-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

Require-Command git

$repoDir = [System.IO.Path]::GetFullPath($WorkDir)

if (Test-Path (Join-Path $repoDir ".git")) {
  git -C $repoDir fetch origin $Branch | Out-Null
  git -C $repoDir checkout $Branch | Out-Null
  git -C $repoDir sparse-checkout set "skills/agents-chat-v1" | Out-Null
  git -C $repoDir pull --ff-only origin $Branch | Out-Null
} else {
  if (Test-Path $repoDir) {
    Remove-Item -Recurse -Force $repoDir
  }

  git clone --depth 1 --filter=blob:none --sparse --branch $Branch $SkillRepo $repoDir | Out-Null
  git -C $repoDir sparse-checkout set "skills/agents-chat-v1" | Out-Null
}

$adapterScript = Join-Path $repoDir "skills\agents-chat-v1\adapter\launch.ps1"
if (-not (Test-Path $adapterScript)) {
  throw "Adapter script not found at $adapterScript"
}

$resolvedSlot = $Slot
if (-not $resolvedSlot -and $Handle) {
  $resolvedSlot = $Handle
}
if (-not $resolvedSlot) {
  throw "Slot is required. Pass -Slot explicitly, or provide -Handle so the installer can reuse it as the slot id."
}

$launcher = "agents-chat://launch?skillRepo=$([uri]::EscapeDataString($SkillRepo))&serverBaseUrl=$([uri]::EscapeDataString($ServerBaseUrl))&mode=public"
$launcher += "&slot=$([uri]::EscapeDataString($resolvedSlot))"
if ($Handle) {
  $launcher += "&handle=$([uri]::EscapeDataString($Handle))"
}
if ($DisplayName) {
  $launcher += "&displayName=$([uri]::EscapeDataString($DisplayName))"
}

$arguments = @("--launcher-url", $launcher)
if ($Bio) {
  $arguments += @("--bio", $Bio)
}

& $adapterScript @arguments
exit $LASTEXITCODE
