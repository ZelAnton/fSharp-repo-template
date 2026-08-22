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

function Copy-Template([string]$destination) {
    New-Item -ItemType Directory -Path $destination | Out-Null
    foreach ($entry in (Get-ChildItem -LiteralPath $sourceRoot -Force)) {
        if ($entry.Name -ne '.git') {
            Copy-Item -LiteralPath $entry.FullName -Destination (Join-Path $destination $entry.Name) -Recurse -Force
        }
    }
}

function Get-Snapshot([string]$root) {
    Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length).TrimStart('\', '/')
            "$relative|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        } |
        Sort-Object
}

function Assert-PsFailure([string]$name, [string]$expected, [string[]]$arguments) {
    $caseRoot = Join-Path $tempRoot "failure-$name"
    Copy-Template $caseRoot
    $before = Get-Snapshot $caseRoot
    $output = & pwsh -NoProfile -File (Join-Path $caseRoot 'scripts/init.ps1') @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        throw "expected initializer failure for $name"
    }
    Assert-True (($output -replace '\s+', ' ') -match [regex]::Escape($expected)) "missing diagnostic for ${name}: $output"
    Assert-True (($before -join "`n") -eq ((Get-Snapshot $caseRoot) -join "`n")) "initializer mutated checkout for $name"
}

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fsharp-template-init-hidden-' + [Guid]::NewGuid().ToString('N'))
$projectToken = '__' + 'ProjectName__'
$ownerToken = '__' + 'GitHubOwner__'

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    $controlAuthors = [ordered]@{
        newline = "bad`nname"
        tab = "bad`tname"
        carriageReturn = "bad`rname"
    }
    foreach ($entry in $controlAuthors.GetEnumerator()) {
        Assert-PsFailure ("control-author-" + $entry.Key) 'Invalid -Author' @(
            '-ProjectName', 'Acme.Widgets', '-Author', $entry.Value)
    }
    Assert-PsFailure 'token-description' 'Invalid -Description' @(
        '-ProjectName', 'Acme.Widgets', '-Description', 'prefix__Author__suffix')
    Assert-PsFailure 'unsafe-owner' 'Invalid -GitHubOwner' @(
        '-ProjectName', 'Acme.Widgets', '-GitHubOwner', 'acme;touch-pwned')

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

    $contextRoot = Join-Path $tempRoot 'encoded-context'
    Copy-Template $contextRoot
    $author = 'O"Reilly \Program Files\Acme\"quoted"\bin & Sons; $HOME `id`'
    Set-Content -LiteralPath (Join-Path $contextRoot 'metadata.json') -Value '{"author":"__Author__"}' -NoNewline
    Set-Content -LiteralPath (Join-Path $contextRoot 'metadata.yaml') -Value 'value: "__Author__"' -NoNewline
    Set-Content -LiteralPath (Join-Path $contextRoot 'metadata.py') -Value 'value = "__Author__"' -NoNewline
    Set-Content -LiteralPath (Join-Path $contextRoot 'metadata.sh') -Value 'printf "%s\n" "__Author__"' -NoNewline
    & (Join-Path $contextRoot 'scripts/init.ps1') -ProjectName 'Acme.Widgets' -Author $author -AuthorEmail 'dev+tag@example.com' -GitHubOwner 'acme-tools' -Description 'Widget toolkit' -Year 2026 -KeepScript | Out-Null
    $expectedJson = '"O\"Reilly \\Program Files\\Acme\\\"quoted\"\\bin & Sons; $HOME `id`"'
    Assert-True ((Get-Content -LiteralPath (Join-Path $contextRoot 'metadata.json') -Raw) -eq ('{"author":' + $expectedJson + '}')) 'JSON metadata was not encoded.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $contextRoot 'metadata.yaml') -Raw) -eq ('value: ' + $expectedJson)) 'YAML metadata was not encoded.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $contextRoot 'metadata.py') -Raw) -eq ('value = ' + $expectedJson)) 'Python metadata was not encoded.'
    $pythonValue = & python3 -c "import runpy, sys; print(runpy.run_path(sys.argv[1])['value'])" (Join-Path $contextRoot 'metadata.py')
    Assert-True ($pythonValue -eq $author) 'Python metadata did not round-trip.'
    $shellMetadata = Get-Content -LiteralPath (Join-Path $contextRoot 'metadata.sh') -Raw
    $expectedShellMetadata = 'printf "%s\n" "O\"Reilly \\Program Files\\Acme\\\"quoted\"\\bin & Sons; \$HOME \`id\`"'
    Assert-True ($shellMetadata -eq $expectedShellMetadata) 'Shell metadata was not escaped.'
    $xml = [xml](Get-Content -LiteralPath (Join-Path $contextRoot 'src/Acme.Widgets/Acme.Widgets.fsproj') -Raw)
    Assert-True ($xml.Project.PropertyGroup.Authors -eq $author) 'XML metadata did not round-trip.'

    Write-Host 'Hidden initializer regression passed.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
