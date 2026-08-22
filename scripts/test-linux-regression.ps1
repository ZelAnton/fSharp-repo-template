#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Assert-Contains {
    param(
        [object[]]$Items,
        [object]$Expected,
        [string]$Message
    )

    $contains = @($Items) -contains $Expected
    Assert-True ([bool]$contains) $Message
}

function Assert-DockerSafeVolumeName {
    param(
        [string]$Name
    )

    Assert-True ($Name -match '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') "'$Name' is not a Docker-safe named volume"
}

function Assert-CommonDockerArguments {
    param(
        [object]$Invocation,
        [string]$RepoRoot,
        [string]$ExpectedNugetVolume,
        [string]$ProjectName = '__ProjectName__'
    )

    $arguments = @($Invocation.Arguments)
    Assert-Contains $arguments 'run' 'the helper must invoke docker run'
    Assert-Contains $arguments '--rm' 'the helper must keep the disposable container option'
    Assert-Contains $arguments "${RepoRoot}:/src" 'the checkout bind mount must be preserved'
    $nugetMounts = @($arguments | Where-Object { $_ -match ':/root/\.nuget/packages$' })
    Assert-True ($nugetMounts.Count -eq 1) 'the helper must provide one NuGet cache volume'
    $nugetVolume = ($nugetMounts[0] -split ':', 2)[0]
    Assert-True ($nugetVolume -eq $ExpectedNugetVolume) "the NuGet cache volume must be '$ExpectedNugetVolume'"
    Assert-DockerSafeVolumeName $nugetVolume

    foreach ($path in @(
            "/src/src/$ProjectName/bin",
            "/src/src/$ProjectName/obj",
            "/src/tests/$ProjectName.Tests/bin",
            "/src/tests/$ProjectName.Tests/obj"
        )) {
        Assert-Contains $arguments $path "the anonymous volume for $path must be preserved"
    }

    Assert-Contains $arguments '-w' 'the container working-directory option must be preserved'
    Assert-Contains $arguments '/src' 'the container must keep /src as its working directory'
    Assert-Contains $arguments 'DOTNET_CLI_TELEMETRY_OPTOUT=1' 'the telemetry option must be preserved'
    Assert-Contains $arguments 'DOTNET_NOLOGO=1' 'the no-logo option must be preserved'
}

function Get-BashInvocation {
    param([object]$Invocation)

    $arguments = @($Invocation.Arguments)
    $bashIndex = [Array]::IndexOf([object[]]$arguments, [object]'bash')
    Assert-True ($bashIndex -ge 0) 'the helper must invoke bash'
    Assert-True (($bashIndex + 2) -lt $arguments.Count) 'bash must receive a script'

    [pscustomobject]@{
        Arguments = $arguments
        Script = [string]$arguments[$bashIndex + 2]
        BashIndex = $bashIndex
    }
}

function Invoke-Helper {
    param(
        [string]$HelperPath,
        [string]$CapturePath,
        [string[]]$HelperArguments
    )

    if (Test-Path -LiteralPath $CapturePath) {
        Remove-Item -LiteralPath $CapturePath -Force
    }

    $env:TEST_LINUX_DOCKER_CAPTURE = $CapturePath
    & pwsh -NoProfile -File $HelperPath @HelperArguments *> $null
    Assert-True ($LASTEXITCODE -eq 0) "the helper must succeed in the captured Docker run (exit code $LASTEXITCODE)"
    Assert-True (Test-Path -LiteralPath $CapturePath) 'the fake Docker CLI must capture the run invocation'

    Get-Content -LiteralPath $CapturePath -Raw | ConvertFrom-Json
}

$helperPath = Join-Path $PSScriptRoot 'test-linux.ps1'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path -replace '\\', '/'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "test-linux-regression-$([guid]::NewGuid())"
$fakeDockerPath = Join-Path $temporaryRoot 'docker.ps1'
$capturePath = Join-Path $temporaryRoot 'docker-run.json'
$leadingUnderscoreHelperPath = Join-Path $temporaryRoot 'scripts\test-linux-leading-underscore.ps1'
$originalPath = $env:Path
$originalCapture = $env:TEST_LINUX_DOCKER_CAPTURE

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $leadingUnderscoreHelperPath) | Out-Null

try {
    @'
if ($args.Count -gt 0 -and $args[0] -eq 'run') {
    [ordered]@{ Arguments = @($args) } |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $env:TEST_LINUX_DOCKER_CAPTURE -Encoding utf8
}
exit 0
'@ | Set-Content -LiteralPath $fakeDockerPath -Encoding utf8

    $env:Path = "$temporaryRoot$([System.IO.Path]::PathSeparator)$originalPath"

    $withoutFilter = Invoke-Helper $helperPath $capturePath @()
    Assert-CommonDockerArguments $withoutFilter $repoRoot 'nuget-__ProjectName__'
    $withoutFilterBash = Get-BashInvocation $withoutFilter
    $expectedWithoutFilterScript = @(
        'set -e',
        'dotnet build -c Release',
        'dotnet test --no-build -c Release tests/__ProjectName__.Tests/__ProjectName__.Tests.fsproj'
    ) -join "`n"
    Assert-True ($withoutFilterBash.Script -ceq $expectedWithoutFilterScript) 'the no-filter command set must remain unchanged'
    Assert-True (-not $withoutFilterBash.Script.Contains('--filter')) 'the no-filter invocation must not add a filter'
    Assert-True ($withoutFilterBash.Arguments.Count -eq ($withoutFilterBash.BashIndex + 3)) 'the no-filter invocation must not add positional filter data'

    (Get-Content -LiteralPath $helperPath -Raw).Replace('__ProjectName__', '_Library') |
        Set-Content -LiteralPath $leadingUnderscoreHelperPath -Encoding utf8
    $leadingUnderscoreRepoRoot = $temporaryRoot -replace '\\', '/'
    $leadingUnderscore = Invoke-Helper $leadingUnderscoreHelperPath $capturePath @()
    Assert-CommonDockerArguments $leadingUnderscore $leadingUnderscoreRepoRoot 'nuget-_Library' '_Library'

    $adversarialFilter = 'FullyQualifiedName~Tests."Quoted"; printf INJECTION >&2; #'
    $withFilter = Invoke-Helper $helperPath $capturePath @(
        '-Filter', $adversarialFilter,
        '-Configuration', 'Debug',
        '-Rebuild'
    )
    Assert-CommonDockerArguments $withFilter $repoRoot 'nuget-__ProjectName__'
    $withFilterBash = Get-BashInvocation $withFilter
    $expectedWithFilterScript = @(
        'set -e',
        'dotnet clean -c Debug',
        'dotnet build -c Debug',
        'dotnet test --no-build -c Debug tests/__ProjectName__.Tests/__ProjectName__.Tests.fsproj --filter "$1"'
    ) -join "`n"
    Assert-True ($withFilterBash.Script -ceq $expectedWithFilterScript) 'rebuild and configuration options must remain unchanged'
    Assert-True (-not $withFilterBash.Script.Contains($adversarialFilter)) 'the filter must not be interpolated into the Bash program'
    Assert-True ($withFilterBash.Arguments[$withFilterBash.BashIndex + 3] -eq '--') 'the filter must use a positional Bash argument'
    Assert-True ($withFilterBash.Arguments[$withFilterBash.BashIndex + 4] -ceq $adversarialFilter) 'shell metacharacters must remain data'
    Assert-True ($withFilterBash.Arguments.Count -eq ($withFilterBash.BashIndex + 5)) 'the adversarial filter must not add extra Docker command arguments'

    Write-Host 'Linux test helper regression checks passed.'
}
finally {
    $env:Path = $originalPath

    if ($null -eq $originalCapture) {
        Remove-Item Env:TEST_LINUX_DOCKER_CAPTURE -ErrorAction SilentlyContinue
    }
    else {
        $env:TEST_LINUX_DOCKER_CAPTURE = $originalCapture
    }

    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
