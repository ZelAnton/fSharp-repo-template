#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Set-Hidden([string]$path) {
    $item = Get-Item -LiteralPath $path -Force
    $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
}

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fsharp-template-init-hidden-' + [Guid]::NewGuid().ToString('N'))
$projectToken = '__' + 'ProjectName__'
$ownerToken = '__' + 'GitHubOwner__'

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    foreach ($entry in (Get-ChildItem -LiteralPath $sourceRoot -Force)) {
        if ($entry.Name -ne '.git') {
            Copy-Item -LiteralPath $entry.FullName -Destination (Join-Path $tempRoot $entry.Name) -Recurse -Force
        }
    }

    $hiddenGitHub = Join-Path $tempRoot '.github'
    Set-Hidden $hiddenGitHub

    $hiddenTokenDir = Join-Path $tempRoot ('.hidden-' + $projectToken + '-directory')
    New-Item -ItemType Directory -Path $hiddenTokenDir | Out-Null
    Set-Hidden $hiddenTokenDir

    $hiddenTokenFile = Join-Path $hiddenTokenDir ('file-' + $projectToken + '.txt')
    Set-Content -LiteralPath $hiddenTokenFile -Value ($projectToken + ' ' + $ownerToken) -NoNewline

    $initScript = Join-Path $tempRoot 'scripts/init.ps1'
    & $initScript -ProjectName 'Hidden.Test' -Author 'Test Author' -AuthorEmail 'test@example.com' -GitHubOwner 'test-owner' -Description 'hidden test' -Year 2026 -KeepScript

    $codeOwners = Get-Content -LiteralPath (Join-Path $tempRoot '.github/CODEOWNERS') -Raw
    Assert-True ($codeOwners -notmatch [regex]::Escape($ownerToken)) 'Hidden .github/CODEOWNERS still contains the owner token.'
    Assert-True ($codeOwners -match '@test-owner') 'Hidden .github/CODEOWNERS was not updated.'

    $releaseWorkflow = Get-Content -LiteralPath (Join-Path $tempRoot '.github/workflows/release.yml') -Raw
    Assert-True ($releaseWorkflow -notmatch [regex]::Escape($projectToken)) 'Hidden .github workflow still contains the project token.'

    $renamedDir = Join-Path $tempRoot '.hidden-Hidden.Test-directory'
    $renamedFile = Join-Path $renamedDir 'file-Hidden.Test.txt'
    Assert-True (Test-Path -LiteralPath $renamedDir) 'Hidden token-named directory was not renamed.'
    Assert-True (Test-Path -LiteralPath $renamedFile) 'Hidden token-named file was not renamed.'
    Assert-True ((Get-Content -LiteralPath $renamedFile -Raw) -eq 'Hidden.Test test-owner') 'Hidden token-named file content was not replaced.'

    $projectFile = Join-Path $tempRoot 'src/Hidden.Test/Hidden.Test.fsproj'
    Assert-True (Test-Path -LiteralPath $projectFile) 'Ordinary token-named project paths were not renamed.'

    Write-Host 'Hidden initializer regression passed.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
