$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')

Push-Location $repoRoot
try {
  python .\tool\readme_i18n\render.py @args
} finally {
  Pop-Location
}
