#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Checks this machine can build and test an F# (.NET) project before you
    initialize the template.

.DESCRIPTION
    Asks the .NET host to resolve the SDK configuration pinned in global.json.
    Prints "Environment ready" and exits 0 on success; if a required tool is
    missing or the SDK configuration cannot be resolved, it prints per-OS install
    commands and exits 1 — install what it names, then re-run. (Fantomas is a
    local tool restored by `dotnet tool restore`,
    not a separate environment prerequisite, so it is not checked here.)

    Run it first, before scripts/init.ps1:

        pwsh ./scripts/check-env.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$problems = @()

Write-Host "==> Checking environment for F# (.NET) development" -ForegroundColor Cyan

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$globalJson = Join-Path $repoRoot 'global.json'
$globalJsonMissing = -not (Test-Path -LiteralPath $globalJson -PathType Leaf)
$configuredSdkVersion = $null
$configuredSdkMajor = $null
$configurationError = $null

# Required: the .NET SDK (it bundles the F# compiler and `dotnet test`).
if ($globalJsonMissing) {
    $problems += "the SDK configuration file '$globalJson' is missing"
} else {
    try {
        $config = Get-Content -LiteralPath $globalJson -Raw | ConvertFrom-Json
        if ($null -eq $config.sdk -or $null -eq $config.sdk.version) {
            throw 'global.json must define sdk.version'
        }

        $configuredSdkVersion = [string]$config.sdk.version
        if ([string]::IsNullOrWhiteSpace($configuredSdkVersion) -or
            $configuredSdkVersion -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
            throw "sdk.version '$configuredSdkVersion' is not a valid SDK version"
        }

        $configuredSdkMajor = ($configuredSdkVersion -split '\.')[0]
    }
    catch {
        $configurationError = $_.Exception.Message
    }
}

if ($null -ne $configurationError) {
    $problems += "invalid SDK configuration in '$globalJson': $configurationError"
} elseif (-not $globalJsonMissing) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $problems += "the .NET SDK ('dotnet' is not on PATH)"
    } else {
        Push-Location $repoRoot
        $nativeErrorPreference = $PSNativeCommandUseErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $sdkOutput = @(& dotnet --version 2>&1)
            $sdkExitCode = $LASTEXITCODE
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $nativeErrorPreference
            Pop-Location
        }

        if ($sdkExitCode -eq 0 -and $sdkOutput.Count -gt 0) {
            $resolvedSdk = [string]$sdkOutput[-1]
            Write-Host "    .NET SDK $resolvedSdk resolved from global.json" -ForegroundColor DarkGray
        } else {
            $problems += "the SDK configuration in '$globalJson' could not be resolved by dotnet"
            foreach ($line in $sdkOutput) {
                Write-Host "    $line" -ForegroundColor DarkGray
            }
        }
    }
}

# Soft: git drives the init defaults (author/email) and the VCS workflow.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "    note: git is not on PATH — init falls back to placeholder author/email." -ForegroundColor Yellow
}

if ($problems.Count -eq 0) {
    Write-Host ""
    Write-Host "Environment ready. Next: pwsh ./scripts/init.ps1 -ProjectName ..." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Environment NOT ready. Missing:" -ForegroundColor Red
foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Red }
Write-Host ""
if ($null -ne $configuredSdkVersion) {
    Write-Host "Install the .NET SDK $configuredSdkVersion, then re-run this check:" -ForegroundColor Yellow
    Write-Host "  Windows : winget install Microsoft.DotNet.SDK.$configuredSdkMajor"
    Write-Host "  macOS   : brew install --cask dotnet-sdk"
    Write-Host "  Linux   : see https://learn.microsoft.com/dotnet/core/install/linux"
} else {
    Write-Host "Fix the SDK configuration in '$globalJson', then re-run this check." -ForegroundColor Yellow
}
exit 1
