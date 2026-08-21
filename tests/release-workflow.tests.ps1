$ErrorActionPreference = 'Stop'

$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python -ErrorAction Stop
}

& $python.Source (Join-Path $PSScriptRoot 'release-workflow.scenarios.py')
if ($LASTEXITCODE -ne 0) {
    throw "Release workflow executable scenarios failed with exit code $LASTEXITCODE."
}
