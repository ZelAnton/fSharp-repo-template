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

if (-not $Author) {
    $Author = (& git config user.name 2>$null)
    if (-not $Author) { $Author = 'Your Name' }
}
if (-not $AuthorEmail) {
    $AuthorEmail = (& git config user.email 2>$null)
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
    if ($entry.Value -match $tokenPattern) {
        throw "Invalid -$($entry.Key): metadata values must not contain template tokens."
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
# Python/YAML workflow contexts; raw text is only used after control/token validation.
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

function Test-Excluded([string]$fullPath) {
    $rel = $fullPath.Substring($repoRoot.Length).TrimStart('\', '/')
    foreach ($seg in ($rel -split '[\\/]')) {
        if ($excludedDirs -contains $seg) { return $true }
    }
    return $false
}

$pathComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$renameTargets = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$renamePlan = [System.Collections.Generic.List[object]]::new()
$named = Get-ChildItem -Path $repoRoot -Recurse -Force | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.Name -like '*__ProjectName__*'
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

# 1) Replace tokens in file contents. Both initializers are skipped: they carry
#    the literal token strings as search keys, so substituting inside them would
#    corrupt the sibling script (which -KeepScript leaves on disk).
$siblingShPath = Join-Path $PSScriptRoot 'init.sh'
$files = Get-ChildItem -Path $repoRoot -File -Recurse -Force | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.FullName -ne $selfPath -and $_.FullName -ne $siblingShPath
}
# Binary extensions are skipped: they carry no tokens, and reading them as text
# (then rewriting) would corrupt them. The template ships none, but a downstream
# user may add e.g. a strong-name key or icon before running init.
$binaryExtensions = @('.snk', '.pfx', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip')
$contentChanged = 0
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
    if ($binaryExtensions -contains $file.Extension) { continue }
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $new = $text
    $map = Get-Replacements $file.FullName
    $new = [regex]::Replace($text, $tokenPattern, [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$match)
        [string]$map[$match.Value]
    })
    if ($new -ne $text) {
        [System.IO.File]::WriteAllText($file.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
        $contentChanged++
    }
}
Write-Host "    Updated contents in $contentChanged file(s)." -ForegroundColor DarkGray

# 2) Rename files and folders whose name contains the project-name token.
#    The complete plan was validated before content mutation; deepest paths
#    are processed first so child renames don't invalidate parent paths.
foreach ($rename in $renamePlan) {
    Rename-Item -LiteralPath $rename.Source -NewName $rename.NewName
    Write-Host "    Renamed $($rename.OldName) -> $($rename.NewName)" -ForegroundColor DarkGray
}

# 3) Activate the Claude Code shared settings. Shipped inert as a .template file
#    so the template repository itself does not auto-grant any permissions.
$claudeTemplate = Join-Path $repoRoot '.claude/settings.json.template'
if (Test-Path $claudeTemplate) {
    Move-Item -LiteralPath $claudeTemplate -Destination (Join-Path $repoRoot '.claude/settings.json') -Force
    Write-Host "    Activated .claude/settings.json" -ForegroundColor DarkGray
}

# 4) Remove template-only files.
foreach ($rel in @('TEMPLATE.md', 'docs/AGENT-INIT-GUIDE.md')) {
    $path = Join-Path $repoRoot $rel
    if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
}
# Drop docs/ if it's now empty (it may still hold linux-testing.md, in which
# case it is kept).
$docsDir = Join-Path $repoRoot 'docs'
if ((Test-Path $docsDir) -and -not (Get-ChildItem -LiteralPath $docsDir -Force)) {
    Remove-Item -LiteralPath $docsDir -Force
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. dotnet tool restore           # restores Fantomas (the F# formatter)"
Write-Host "  2. dotnet build $ProjectName.slnx"
Write-Host "  3. dotnet test  $ProjectName.slnx"
Write-Host "  4. Review LICENSE (author/year) and the .fsproj package metadata."
Write-Host "  5. NuGet publishing: add the NUGET_API_KEY repo secret, or delete"
Write-Host "     .github/workflows/release.yml and the packaging properties in the .fsproj."
Write-Host "  6. Commit the initialized project."

# Remove both initializers unless asked to keep them.
if (-not $KeepScript) {
    $siblingSh = Join-Path $PSScriptRoot 'init.sh'
    if (Test-Path $siblingSh) { Remove-Item -LiteralPath $siblingSh -Force }
    Remove-Item -LiteralPath $selfPath -Force
}
