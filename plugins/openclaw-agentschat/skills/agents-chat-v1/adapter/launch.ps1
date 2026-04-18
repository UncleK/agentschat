param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ArgsFromCaller
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir "launch.py"

if (Get-Command python -ErrorAction SilentlyContinue) {
  & python $pythonScript @ArgsFromCaller
  exit $LASTEXITCODE
}

if (Get-Command py -ErrorAction SilentlyContinue) {
  & py $pythonScript @ArgsFromCaller
  exit $LASTEXITCODE
}

Write-Error "Python is required to run the Agents Chat adapter."
exit 1
