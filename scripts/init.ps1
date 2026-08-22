#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initializes this template into a concrete F# project.

.DESCRIPTION
    Replaces the placeholder tokens (__ProjectName__, __Author__, __AuthorEmail__,
    __GitHubOwner__, __Description__, __Year__) in file contents AND in file/folder names, then
    removes the template-only files (TEMPLATE.md, docs/AGENT-INIT-GUIDE.md, and,
    unless -KeepScript, both initializers — this script and init.sh).

    Run it once, right after creating a repository from the template:

        pwsh ./scripts/init.ps1 -ProjectName Acme.Widgets

    Omitted optional values fall back to sensible defaults so the result always
    builds; edit LICENSE / the .fsproj afterwards if you need to refine them.

.PARAMETER ProjectName
    Project / namespace / assembly / NuGet package id. Required.
    Letters, digits, underscores; dot-separated segments allowed (e.g. Acme.Widgets).
    The generated path names must also be portable across Windows and POSIX filesystems.

.PARAMETER Author
    Author for LICENSE and the .fsproj. Defaults to `git config user.name`, else "Your Name".

.PARAMETER AuthorEmail
    Author email for the release commit. Defaults to `git config user.email`, else "you@example.com".

.PARAMETER GitHubOwner
    GitHub owner/org used in repository URLs. Defaults to "your-org".

.PARAMETER Description
    Short package description. Defaults to "TODO: project description".

.PARAMETER Year
    Copyright year. Defaults to the current year.

.PARAMETER KeepScript
    Keep this script after running (TEMPLATE.md is removed either way).

.EXAMPLE
    pwsh ./scripts/init.ps1 -ProjectName Acme.Widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    [string]$Author,
    [string]$AuthorEmail,
    [string]$GitHubOwner,
    [string]$Description,
    [int]$Year = (Get-Date).Year,
    [switch]$KeepScript
)

$ErrorActionPreference = 'Stop'

if ($ProjectName -notmatch '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$') {
    throw "Invalid -ProjectName '$ProjectName'. Use letters, digits, underscores; dot-separated segments allowed (e.g. Acme.Widgets)."
}

$portablePathComponentLimit = 255
$windowsBaseName = $ProjectName.Split('.')[0]
if ($windowsBaseName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
    throw "Invalid -ProjectName '$ProjectName': Windows reserves the base name '$windowsBaseName' (case-insensitive), including when followed by an extension. No files were changed."
}

foreach ($suffix in @('', '.slnx', '.sln.DotSettings', '.Tests', '.Tests.fsproj')) {
    $generatedName = "$ProjectName$suffix"
    $nameLength = [System.Text.Encoding]::UTF8.GetByteCount($generatedName)
    if ($nameLength -gt $portablePathComponentLimit) {
        throw "Invalid -ProjectName '$ProjectName': generated path component '$generatedName' exceeds the portable path component limit of $portablePathComponentLimit bytes. No files were changed."
    }
}

$gitCommand = $null
if (-not $Author -or -not $AuthorEmail) {
    $gitCommand = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue
}
if (-not $Author) {
    if ($gitCommand) { $Author = (& $gitCommand.Source config user.name 2>$null) }
    if (-not $Author) { $Author = 'Your Name' }
}
if (-not $AuthorEmail) {
    if ($gitCommand) { $AuthorEmail = (& $gitCommand.Source config user.email 2>$null) }
    if (-not $AuthorEmail) { $AuthorEmail = 'you@example.com' }
}
if (-not $GitHubOwner) { $GitHubOwner = 'your-org' }
if (-not $Description) { $Description = 'TODO: project description' }

$tokenPattern = '__ProjectName__|__Author__|__AuthorEmail__|__GitHubOwner__|__Description__|__Year__'
$metadata = [ordered]@{
    Author      = $Author
    AuthorEmail = $AuthorEmail
    GitHubOwner = $GitHubOwner
    Description = $Description
}
foreach ($entry in $metadata.GetEnumerator()) {
    if ($entry.Value -match '[\x00-\x1F\x7F\u2028\u2029]') {
        throw "Invalid -$($entry.Key): metadata values must not contain control characters or line separators."
    }
}
if ($GitHubOwner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$') {
    throw "Invalid -GitHubOwner '$GitHubOwner'. Use letters, digits, and internal hyphens only."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$selfPath = $PSCommandPath

$replacements = [ordered]@{
    '__ProjectName__' = $ProjectName
    '__Author__'      = $Author
    '__AuthorEmail__' = $AuthorEmail
    '__GitHubOwner__' = $GitHubOwner
    '__Description__' = $Description
    '__Year__'        = "$Year"
}

function ConvertTo-XmlContent([string]$value) {
    return $value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function ConvertTo-ShellDoubleQuoted([string]$value) {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $value.ToCharArray()) {
        if ([int]$character -in @(0x5C, 0x22, 0x24, 0x60)) {
            [void]$builder.Append('\')
        }
        [void]$builder.Append($character)
    }
    return $builder.ToString()
}

function ConvertTo-PythonDoubleQuoted([string]$value) {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $value.ToCharArray()) {
        if ([int]$character -in @(0x5C, 0x22)) {
            [void]$builder.Append('\')
        }
        [void]$builder.Append($character)
    }
    return $builder.ToString()
}

function ConvertTo-JsonStringContent([string]$value) {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $value.ToCharArray()) {
        $escaped = switch ([int]$character) {
            0x08 { '\b' }
            0x09 { '\t' }
            0x0A { '\n' }
            0x0C { '\f' }
            0x0D { '\r' }
            0x22 { '\"' }
            0x5C { '\\' }
            { $_ -lt 0x20 } { '\u{0:X4}' -f [int]$character; break }
            default { [string]$character }
        }
        [void]$builder.Append($escaped)
    }
    return $builder.ToString()
}

# Values written into XML files (e.g. the .fsproj <Authors>/<Description>) must be
# XML-escaped. The other maps protect string literals in generated JSON, shell, and
# Python/YAML workflow contexts; raw text is only used after control-character validation.
$xmlReplacements = [ordered]@{}
foreach ($key in $replacements.Keys) {
    $xmlReplacements[$key] = ConvertTo-XmlContent $replacements[$key]
}
$jsonReplacements = [ordered]@{}
$shellReplacements = [ordered]@{}
$pythonReplacements = [ordered]@{}
foreach ($key in $replacements.Keys) {
    $jsonReplacements[$key] = ConvertTo-JsonStringContent $replacements[$key]
    $shellReplacements[$key] = ConvertTo-ShellDoubleQuoted $replacements[$key]
    $pythonReplacements[$key] = ConvertTo-PythonDoubleQuoted $replacements[$key]
}
$workflowReplacements = [ordered]@{}
foreach ($key in $replacements.Keys) { $workflowReplacements[$key] = $replacements[$key] }
$workflowReplacements['__Author__'] = ConvertTo-ShellDoubleQuoted $Author
$workflowReplacements['__AuthorEmail__'] = ConvertTo-ShellDoubleQuoted $AuthorEmail
$workflowReplacements['__GitHubOwner__'] = ConvertTo-PythonDoubleQuoted $GitHubOwner
$xmlFileExtensions = @('.fsproj', '.props', '.targets', '.slnx', '.config')

$excludedDirs = @('.git', '.jj', 'bin', 'obj')

function Test-Excluded([string]$fullPath, [string]$traversalRoot) {
    $rel = $fullPath.Substring($traversalRoot.Length).TrimStart('\', '/')
    foreach ($seg in ($rel -split '[\\/]')) {
        if ($excludedDirs -contains $seg) { return $true }
    }
    return $false
}

function Assert-DirectoryWritable([string]$directory, [string]$operation) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Preflight cannot $operation directory '$directory': it is missing."
    }
    $item = Get-Item -LiteralPath $directory -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
        throw "Preflight cannot $operation directory '$directory': it is read-only."
    }
    $probe = Join-Path $directory ".init-preflight-$([guid]::NewGuid().ToString('N'))"
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($probe, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Dispose()
        $stream = $null
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    }
    catch {
        if ($stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
        throw "Preflight cannot $operation directory '$directory': $($_.Exception.Message)"
    }
}

function Assert-WritablePath([string]$path, [string]$operation) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            throw "Preflight cannot $operation '$path': it is read-only."
        }
    }
    Assert-DirectoryWritable (Split-Path -Path $path -Parent) $operation
    if (Test-Path -LiteralPath $path -PathType Container) { Assert-DirectoryWritable $path $operation }
}

function Test-PathEntry([string]$path) {
    if (Test-Path -LiteralPath $path) { return $true }
    $parent = Split-Path -Path $path -Parent
    $name = Split-Path -Path $path -Leaf
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { return $false }
    $entry = Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop |
        Where-Object { $_.Name -ceq $name } |
        Select-Object -First 1
    return $null -ne $entry
}

function Copy-MutableTree([string]$sourceRoot, [string]$destinationRoot) {
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $sourceRoot -Force)) {
        if ($item.Name -eq '.git' -or (Test-Excluded $item.FullName $sourceRoot)) { continue }
        $destination = Join-Path $destinationRoot $item.Name
        if ($item.PSIsContainer) { Copy-MutableTree $item.FullName $destination }
        else { Copy-Item -LiteralPath $item.FullName -Destination $destination -Force }
    }
}

function Remove-MutableTree([string]$root) {
    foreach ($item in (Get-ChildItem -LiteralPath $root -Force | Sort-Object { $_.FullName.Length } -Descending)) {
        if ($item.Name -eq '.git' -or (Test-Excluded $item.FullName $root)) { continue }
        if ($item.PSIsContainer) {
            Remove-MutableTree $item.FullName
            if (-not (Get-ChildItem -LiteralPath $item.FullName -Force)) { Remove-Item -LiteralPath $item.FullName -Force }
        }
        else { Remove-Item -LiteralPath $item.FullName -Force }
    }
}

function Write-StagedFileAtomically([string]$source, [string]$destination, [string]$transactionId) {
    $temporary = Join-Path (Split-Path -Path $destination -Parent) ".init-$transactionId-$([System.IO.Path]::GetRandomFileName())"
    try {
        Copy-Item -LiteralPath $source -Destination $temporary -Force
        Move-Item -LiteralPath $temporary -Destination $destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction Stop }
    }
}

function Invoke-FailureInjection([string]$boundary) {
    if ($env:TEMPLATE_INIT_FAIL_AT -eq $boundary) { throw "Injected failure at '$boundary'." }
}

function Remove-TransactionRoot([string]$path) {
    if ($env:TEMPLATE_INIT_FAIL_AT -eq 'cleanup' -and -not $script:cleanupFailureInjected) {
        $script:cleanupFailureInjected = $true
        throw "Injected failure at 'cleanup'."
    }
    if ($path -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
    if ($path -and (Test-Path -LiteralPath $path)) { throw "Transaction cleanup did not remove staging directory '$path'." }
}

$pathComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$renameTargets = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$renamePlan = [System.Collections.Generic.List[object]]::new()
$named = Get-ChildItem -Path $repoRoot -Recurse -Force | Where-Object {
    -not (Test-Excluded $_.FullName $repoRoot) -and $_.Name -like '*__ProjectName__*'
} | Sort-Object { $_.FullName.Length } -Descending
foreach ($item in $named) {
    $newName = $item.Name.Replace('__ProjectName__', $ProjectName)
    if ($newName -eq $item.Name) { continue }

    $parentPath = [System.IO.Path]::GetDirectoryName($item.FullName)
    $targetPath = Join-Path $parentPath $newName
    if (Test-Path -LiteralPath $targetPath) {
        throw "Cannot initialize: generated path collision for '$targetPath' (from '$($item.FullName)')."
    }
    if (-not $renameTargets.Add($targetPath)) {
        throw "Cannot initialize: generated path collision because multiple paths target '$targetPath'."
    }
    $renamePlan.Add([pscustomobject]@{
        Source  = $item.FullName
        Target  = $targetPath
        OldName = $item.Name
        NewName = $newName
    })
}

Write-Host "==> Initializing template as '$ProjectName'" -ForegroundColor Cyan

# 1) Replace tokens only in the template-owned text surface. User files are
#    deliberately absent from this list, even when they use a familiar text
#    extension or contain a placeholder-looking string.
$knownTextPaths = @(
    '.claude/settings.json.template', '.config/dotnet-tools.json', '.editorconfig', '.gitattributes',
    '.github/CODEOWNERS', '.github/dependabot.yml', '.github/PULL_REQUEST_TEMPLATE.md',
    '.github/workflows/ci.yml', '.github/workflows/release.yml', '.gitignore', '.yamllint.yml',
    'AGENTS.md', 'CHANGELOG.md', 'CLAUDE.md', 'CONTRIBUTING.md', 'Directory.Build.props',
    'Directory.Packages.props', 'docs/AGENT-INIT-GUIDE.md', 'docs/linux-testing.md', 'global.json',
    'LICENSE', 'README.md', 'SECURITY.md', 'TEMPLATE.md', '__ProjectName__.sln.DotSettings',
    '__ProjectName__.slnx', 'cliff.toml', 'nuget.config', 'release-token-bypass.md',
    'scripts/check-env.ps1', 'scripts/check-env.sh', 'scripts/test-linux-regression.ps1',
    'scripts/test-linux.ps1', 'scripts/verify-nuget-package.py', 'scripts/verify-test-results.py',
    'src/__ProjectName__/Greeter.fs', 'src/__ProjectName__/__ProjectName__.fsproj',
    'tests/__ProjectName__.Tests/GreeterTests.fs',
    'tests/__ProjectName__.Tests/__ProjectName__.Tests.fsproj',
    'tests/ci-tooling/constraints.txt', 'tests/ci-tooling/requirements.in',
    'tests/ci-tooling/test_sdk_alignment.py', 'tests/ci-tooling/test_yamllint_contract.py',
    'tests/release-workflow.scenarios.py'
)
$files = foreach ($relativePath in $knownTextPaths) {
    $path = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path -Force }
}
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$contentPlans = [System.Collections.Generic.List[object]]::new()
function Get-Replacements([string]$fullPath) {
    $relativePath = $fullPath.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($xmlFileExtensions -contains $extension) { return $xmlReplacements }
    if ($extension -eq '.json') { return $jsonReplacements }
    if ($extension -in @('.py')) { return $pythonReplacements }
    if ($extension -in @('.sh', '.bash')) { return $shellReplacements }
    if ($relativePath -eq '.github/workflows/release.yml') { return $workflowReplacements }
    if ($extension -in @('.yml', '.yaml')) { return $jsonReplacements }
    return $replacements
}
foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ([Array]::IndexOf[byte]($bytes, [byte]0) -ge 0) { continue }
    try {
        $text = $strictUtf8.GetString($bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        continue
    }
    $new = $text
    $map = Get-Replacements $file.FullName
    $new = [regex]::Replace($text, $tokenPattern, [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$match)
        [string]$map[$match.Value]
    })
    if ($new -ne $text) {
        Assert-WritablePath $file.FullName 'write'
        $contentPlans.Add([pscustomobject]@{
            RelativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
            Content      = $new
        })
    }
}
$claudeTemplate = Join-Path $repoRoot '.claude/settings.json.template'
$claudeSettings = Join-Path $repoRoot '.claude/settings.json'
$templateOnly = @('TEMPLATE.md', 'docs/AGENT-INIT-GUIDE.md')
$docsDir = Join-Path $repoRoot 'docs'
if (Test-Path -LiteralPath $claudeTemplate) {
    if (Test-PathEntry $claudeSettings) {
        throw "Cannot initialize: refusing to overwrite existing local '.claude/settings.json'; remove it or the template before retrying."
    }
    Assert-WritablePath $claudeTemplate 'activate settings'
    Assert-WritablePath $claudeSettings 'activate settings'
}
foreach ($relativePath in $templateOnly) {
    $path = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $path) { Assert-WritablePath $path 'remove' }
}
if (Test-Path -LiteralPath $docsDir) { Assert-WritablePath $docsDir 'remove' }
$siblingSh = Join-Path $PSScriptRoot 'init.sh'
if (-not $KeepScript) {
    if (Test-Path -LiteralPath $siblingSh) { Assert-WritablePath $siblingSh 'remove' }
    Assert-WritablePath $selfPath 'remove'
}

$transactionId = [guid]::NewGuid().ToString('N')
$transactionRoot = Join-Path ([System.IO.Path]::GetTempPath()) "fsharp-template-init-$transactionId"
$candidateRoot = Join-Path $transactionRoot 'candidate'
$contentRoot = Join-Path $transactionRoot 'content'
$rollbackRoot = Join-Path $transactionRoot 'rollback'
$transactionStarted = $false
$cleanupFailureInjected = $false

try {
    New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
    Copy-MutableTree $repoRoot $candidateRoot
    foreach ($plan in $contentPlans) {
        $candidatePath = Join-Path $candidateRoot $plan.RelativePath
        [System.IO.File]::WriteAllText($candidatePath, $plan.Content, (New-Object System.Text.UTF8Encoding($false)))
        $stagedPath = Join-Path $contentRoot $plan.RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Path $stagedPath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $candidatePath -Destination $stagedPath -Force
    }
    Invoke-FailureInjection 'content-write'

    foreach ($rename in $renamePlan) {
        $candidateSource = Join-Path $candidateRoot $rename.Source.Substring($repoRoot.Length).TrimStart('\', '/')
        Rename-Item -LiteralPath $candidateSource -NewName $rename.NewName
    }
    Invoke-FailureInjection 'path-rename'
    $candidateTemplate = Join-Path $candidateRoot '.claude/settings.json.template'
    if (Test-Path -LiteralPath $candidateTemplate) { Move-Item -LiteralPath $candidateTemplate -Destination (Join-Path $candidateRoot '.claude/settings.json') }
    Invoke-FailureInjection 'settings-activation'
    foreach ($relativePath in $templateOnly) {
        $candidatePath = Join-Path $candidateRoot $relativePath
        if (Test-Path -LiteralPath $candidatePath) { Remove-Item -LiteralPath $candidatePath -Force }
    }
    $candidateDocs = Join-Path $candidateRoot 'docs'
    if ((Test-Path -LiteralPath $candidateDocs) -and -not (Get-ChildItem -LiteralPath $candidateDocs -Force)) { Remove-Item -LiteralPath $candidateDocs -Force }
    if (-not $KeepScript) {
        Remove-Item -LiteralPath (Join-Path $candidateRoot 'scripts/init.ps1') -Force
        Remove-Item -LiteralPath (Join-Path $candidateRoot 'scripts/init.sh') -Force
    }
    Invoke-FailureInjection 'template-removal'

    Copy-MutableTree $repoRoot $rollbackRoot
    $transactionStarted = $true
    Invoke-FailureInjection 'apply-content-write'
    foreach ($plan in $contentPlans) {
        Write-StagedFileAtomically (Join-Path $contentRoot $plan.RelativePath) (Join-Path $repoRoot $plan.RelativePath) $transactionId
    }
    Invoke-FailureInjection 'apply-path-rename'
    foreach ($rename in $renamePlan) {
        Rename-Item -LiteralPath $rename.Source -NewName $rename.NewName
        Write-Host "    Renamed $($rename.OldName) -> $($rename.NewName)" -ForegroundColor DarkGray
    }
    Invoke-FailureInjection 'apply-settings-activation'
    if (Test-Path -LiteralPath $claudeTemplate) {
        Move-Item -LiteralPath $claudeTemplate -Destination $claudeSettings -Force
        Write-Host '    Activated .claude/settings.json' -ForegroundColor DarkGray
    }
    Invoke-FailureInjection 'apply-template-removal'
    foreach ($relativePath in $templateOnly) {
        $path = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $docsDir) -and -not (Get-ChildItem -LiteralPath $docsDir -Force)) { Remove-Item -LiteralPath $docsDir -Force }
    if (-not $KeepScript) {
        if (Test-Path -LiteralPath $siblingSh) { Remove-Item -LiteralPath $siblingSh -Force }
        Remove-Item -LiteralPath $selfPath -Force
    }
    Remove-TransactionRoot $transactionRoot
    $transactionStarted = $false
}
catch {
    $message = $_.Exception.Message
    $rollbackMessage = $null
    $cleanupMessage = $null
    if ($transactionStarted) {
        try {
            Remove-MutableTree $repoRoot
            Copy-MutableTree $rollbackRoot $repoRoot
        }
        catch { $rollbackMessage = $_.Exception.Message }
    }
    if ($transactionRoot -and (Test-Path -LiteralPath $transactionRoot)) {
        try { Remove-TransactionRoot $transactionRoot } catch { $cleanupMessage = $_.Exception.Message }
    }
    if ($rollbackMessage) { throw "Initialization failed: $message Rollback failed: $rollbackMessage" }
    if ($cleanupMessage) { throw "Initialization failed: $message Cleanup failed: $cleanupMessage Staging artifact: $transactionRoot" }
    throw "Initialization failed: $message"
}

Write-Host "    Updated contents in $($contentPlans.Count) file(s)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. dotnet tool restore           # restores Fantomas (the F# formatter)"
Write-Host "  2. dotnet build $ProjectName.slnx"
Write-Host "  3. dotnet test  $ProjectName.slnx"
Write-Host "  4. Review LICENSE (author/year) and the .fsproj package metadata."
Write-Host "  5. NuGet publishing: add the NUGET_API_KEY repo secret, or delete"
Write-Host "     .github/workflows/release.yml and the packaging properties in the .fsproj."
Write-Host "  6. Commit the initialized project."
