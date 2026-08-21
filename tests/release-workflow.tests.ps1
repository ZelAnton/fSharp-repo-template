$ErrorActionPreference = 'Stop'

$workflowPath = Join-Path $PSScriptRoot '..\.github\workflows\release.yml'
$verifierPath = Join-Path $PSScriptRoot '..\scripts\verify-nuget-package.py'
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$verifier = Get-Content -Raw -Encoding UTF8 $verifierPath

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw "Release workflow invariant failed: $Message"
    }
}

function Index-Of([string] $Text, [string] $Needle) {
    $index = $Text.IndexOf($Needle, [System.StringComparison]::Ordinal)
    Assert-True ($index -ge 0) "missing '$Needle'"
    return $index
}

$commitStep = Index-Of $workflow 'id: release-identity'
$sourceIdentity = Index-Of $workflow 'id: release-source'
$bundleStep = Index-Of $workflow 'name: Create local release recovery bundle'
$packStep = Index-Of $workflow 'name: Pack'
$prePublishCheck = Index-Of $workflow 'name: Verify existing NuGet package identity'
$nugetPush = Index-Of $workflow 'name: Push to NuGet.org (irreversible pivot)'
$postPublishCheck = Index-Of $workflow 'name: Verify published NuGet package identity'
$vcsPush = Index-Of $workflow 'name: Push the release commit + tag (atomic)'
$githubRelease = Index-Of $workflow 'name: Create or update the GitHub Release (idempotent)'
$recoveryUpload = Index-Of $workflow 'name: Preserve exact post-pivot recovery state'

Assert-True ($commitStep -lt $packStep) 'the package must be built from the committed release identity'
Assert-True ($sourceIdentity -lt $commitStep) 'the release commit must use the captured source identity'
Assert-True ($commitStep -lt $bundleStep -and $bundleStep -lt $packStep) 'the exact release bundle must be created before packaging'
Assert-True ($workflow.Contains('GIT_AUTHOR_DATE=')) 'release commit author date is not deterministic'
Assert-True ($workflow.Contains('GIT_COMMITTER_DATE=')) 'release commit committer date is not deterministic'
Assert-True ($workflow.Contains('RELEASE_DATE: ${{ steps.release-source.outputs.date }}')) 'changelog release date is not deterministic'
Assert-True ($prePublishCheck -lt $nugetPush) 'existing versions must be checked before publish'
Assert-True ($postPublishCheck -gt $nugetPush -and $postPublishCheck -lt $vcsPush) 'publish success must be verified before VCS writes'
Assert-True ($vcsPush -lt $githubRelease) 'GitHub Release must remain after the atomic VCS push'
Assert-True ($bundleStep -lt $packStep) 'the immutable recovery bundle must capture the release commit before packaging'
Assert-True ($recoveryUpload -gt $githubRelease) 'recovery state must be preserved after partial VCS/GitHub completion'
Assert-True ($workflow.Contains('release-recovery-${{ steps.version.outputs.tag }}')) 'recovery artifacts are not versioned by the release tag'
Assert-True ($githubRelease -lt $recoveryUpload) 'post-pivot recovery must run after the GitHub Release step'
Assert-True ($workflow.Contains('scripts/verify-nuget-package.py')) 'the package identity verifier is not used'
Assert-True ($workflow.Contains('--allow-missing')) 'a missing version must be distinguishable from a lookup failure'
Assert-True ($workflow.Contains('if: ${{ steps.package-identity.outputs.existing != ''true'' }}')) 'NuGet publish must be skipped only after a matching existing package is verified'
Assert-True ($workflow.Contains('--skip-duplicate')) 'the transient publish retry guard was removed'
Assert-True ($workflow.Contains('git bundle create ./artifacts/release-recovery.bundle HEAD "$TAG"')) 'the recovery bundle no longer captures the exact commit and tag'
Assert-True ($workflow.Contains('artifacts/release-recovery.bundle')) 'post-pivot recovery no longer uploads the exact VCS state'
Assert-True ($workflow.Contains('Do NOT re-run this workflow')) 'partial post-publish failures must prohibit rebuilding from a moved main'
Assert-True ($workflow.Contains('SHA-256') -or $workflow.Contains('SHA256')) 'package content identity is no longer checked'
Assert-True ($workflow.Contains('HEAD:refs/heads/main')) 'the release commit is not pushed to main'
Assert-True ($workflow.Contains('${{ steps.version.outputs.tag }}')) 'the same computed tag is not threaded through VCS and GitHub phases'
Assert-True ($verifier.Contains('actual_sha != expected_sha')) 'an occupied version is not checked against canonical package contents'
Assert-True ($verifier.Contains('remote_commit.lower() != args.expected_commit.lower()')) 'an occupied version is not checked against the release commit'
Assert-True ($verifier.Contains('error.code == 404 and args.allow_missing')) 'missing and occupied versions are not distinguished'
Assert-True ($verifier.Contains('refusing to continue')) 'NuGet lookup failures do not fail closed'

Write-Output 'Release workflow static invariants passed.'
