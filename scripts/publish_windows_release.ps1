#Requires -Version 5
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+$')][string]$Repository,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version,
    [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$TargetCommit,
    [string]$GhPath = 'gh'
)

$ErrorActionPreference = 'Stop'
$TargetCommit = $TargetCommit.ToLowerInvariant()
$ArtifactDirectory = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$errorFile = Join-Path $ArtifactDirectory 'github-publish-error.log'

function Invoke-GitHub([string[]]$Arguments) {
    # Windows PowerShell 5 turns native stderr into ErrorRecords. Check the
    # process exit code explicitly instead of aborting on a harmless notice.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $GhPath @Arguments 2>$errorFile
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    return [PSCustomObject]@{ Output = $output; ExitCode = $exitCode }
}

function Invoke-GitHubJson([string[]]$Arguments) {
    $result = Invoke-GitHub -Arguments $Arguments
    if ($result.ExitCode -ne 0) { throw 'GitHub API request failed; no response body or credentials were printed.' }
    return ($result.Output | ConvertFrom-Json)
}

function Get-DraftReleaseId($Draft) {
    if ($Draft.isDraft -ne $true) {
        throw 'A published version already exists. Bump pubspec.yaml; never replace published update binaries.'
    }
    if ($Draft.isPrerelease -or $Draft.tagName -cne "v$Version" -or $Draft.targetCommitish -cne $TargetCommit) {
        throw 'The existing release is not the expected stable draft/target; nothing will be overwritten.'
    }
    $id = 0L
    if (-not [long]::TryParse([string]$Draft.databaseId, [ref]$id) -or $id -le 0) {
        throw 'GitHub did not return a valid draft release identity.'
    }
    return $id
}

$repositoryInfo = Invoke-GitHubJson -Arguments @('api', "repos/$Repository", '--jq', '{id: .id, private: .private, full_name: .full_name}')
if (-not $repositoryInfo.private -or $repositoryInfo.full_name.ToLowerInvariant() -ne $Repository.ToLowerInvariant()) {
    throw 'Publication is restricted to the exact requested private repository.'
}
$repositoryId = $repositoryInfo.id
$files = @(
    (Join-Path $ArtifactDirectory "NN4KSetup-$Version.exe"),
    (Join-Path $ArtifactDirectory "NN4K-$Version-windows-portable.zip"),
    (Join-Path $ArtifactDirectory 'checksums.txt')
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing release artifact: $([IO.Path]::GetFileName($file))" }
}
$artifactInfo = @{}
foreach ($file in $files) {
    $artifactInfo[[IO.Path]::GetFileName($file)] = [PSCustomObject]@{
        Size = (Get-Item -LiteralPath $file).Length
        Hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$installerBytes = (Get-Item -LiteralPath $files[0]).Length
if ($installerBytes -le 0 -or $installerBytes -gt 512MB) { throw 'The installer exceeds the updater size limit.' }
$checksums = [IO.File]::ReadAllLines($files[2])
if ($checksums.Count -ne 2) { throw 'checksums.txt must contain exactly the installer and portable ZIP hashes.' }
foreach ($file in $files[0..1]) {
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedLine = "$hash  $([IO.Path]::GetFileName($file))"
    if (@($checksums | Where-Object { $_ -ceq $expectedLine }).Count -ne 1) { throw 'checksums.txt does not match the local release artifacts.' }
}

$releaseId = $null
$lookupFields = 'databaseId,isDraft,isPrerelease,tagName,targetCommitish'
$lookup = Invoke-GitHub -Arguments @('release', 'view', "v$Version", '--repo', $Repository, '--json', $lookupFields)
if ($lookup.ExitCode -eq 0) {
    $releaseId = Get-DraftReleaseId -Draft ($lookup.Output | ConvertFrom-Json)
} elseif ((Get-Content -LiteralPath $errorFile -Raw) -notmatch 'release not found|HTTP 404|Not Found') {
    throw 'Release lookup failed; an access/network error is not a missing release.'
}

$notesTemplate = @'
## NN4K __VERSION__ — Windows

- `NN4KSetup-__VERSION__.exe`: per-user installer, no administrator privileges required.
- `NN4K-__VERSION__-windows-portable.zip`: extract and run `nn4k.exe`.
- `checksums.txt`: SHA-256 checksums of both downloads.

This package targets an **x64 Windows OS**, not 32-bit Windows or ARM64 emulation.
The original first-run setup and appearance preferences are preserved.

### In-app updates
Open Settings → About → Updates. Private repositories require your own fine-grained
GitHub token with access to this repository and **Contents: Read-only**. The token
is stored in Windows Credential Manager, not in the executable or settings JSON.
Automatic download/installation is opt-in and is deferred while VPN is active.
The update path is designed to preserve existing servers/settings, verify the
installer SHA-256, stop owned engines, install in place and restart. End-to-end
upgrading to a genuinely newer release still requires a separate installation test.

Builds are not Authenticode-signed unless the owner adds signing separately.
A checksum confirms integrity; it is not an antivirus or publisher-trust guarantee.
Live Proxy/TUN and end-to-end upgrading are not certified by this release.
The upstream application's licensing remains unresolved; keep this repository
private and clarify redistribution rights with the original author.
'@
$notesFile = Join-Path $ArtifactDirectory 'release-notes.md'
[IO.File]::WriteAllText($notesFile, $notesTemplate.Replace('__VERSION__', $Version), [Text.UTF8Encoding]::new($false))
if ($null -eq $releaseId) {
    $arguments = @('release', 'create', "v$Version", '--repo', $Repository,
        '--draft', '--title', "NN4K $Version", '--notes-file', $notesFile)
    $arguments += @('--target', $TargetCommit)
    $created = Invoke-GitHub -Arguments $arguments
    if ($created.ExitCode -ne 0) { throw 'Could not create draft release' }
    $draft = Invoke-GitHubJson -Arguments @('release', 'view', "v$Version", '--repo', $Repository, '--json', $lookupFields)
    $releaseId = Get-DraftReleaseId -Draft $draft
}

# No --clobber: a concurrent publication must never permit replacing an already
# uploaded binary. A retry skips identical draft assets and rejects conflicts.
# GitHub's /releases/tags endpoint can return 404 for a new unpublished draft.
# Resolve its numeric identity through gh, then pin every API read to that ID.
foreach ($file in $files) {
    $release = Invoke-GitHubJson -Arguments @('api', "repos/$Repository/releases/$releaseId")
    if (-not $release.draft -or $release.prerelease -or $release.tag_name -cne "v$Version" -or $release.target_commitish -cne $TargetCommit) { throw 'The release is no longer the expected stable draft/target; nothing will be overwritten.' }
    if ($release.id -ne $releaseId) { throw 'The draft identity changed during publication.' }
    $name = [IO.Path]::GetFileName($file)
    $expected = $artifactInfo[$name]
    $matching = @($release.assets | Where-Object { $_.name -ceq $name })
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne $expected.Hash -or (Get-Item -LiteralPath $file).Length -ne $expected.Size) { throw 'A local artifact changed during publication; the draft was not published.' }
    if ($matching.Count) {
        if ($matching.Count -ne 1 -or $matching[0].state -ne 'uploaded' -or
            $matching[0].digest -cne "sha256:$hash" -or $matching[0].size -ne (Get-Item -LiteralPath $file).Length) {
            throw "Conflicting draft asset: $name. No asset was replaced; investigate or use a new version."
        }
        continue
    }
    $uploaded = Invoke-GitHub -Arguments @('release', 'upload', "v$Version", $file, '--repo', $Repository)
    if ($uploaded.ExitCode -ne 0) { throw 'Release upload failed; no asset was replaced and the script did not publish the draft.' }
}

# The release remains a DRAFT until GitHub confirms every uploaded size/digest.
# Recheck identity and draft state immediately before exposing it through latest.
$release = Invoke-GitHubJson -Arguments @('api', "repos/$Repository/releases/$releaseId")
if (-not $release.draft -or $release.prerelease -or $release.id -ne $releaseId -or $release.tag_name -cne "v$Version" -or $release.target_commitish -cne $TargetCommit) { throw 'The release changed before final verification; publication was stopped.' }
if (@($release.assets).Count -ne $files.Count) { throw 'Unexpected assets in the draft; publication was stopped.' }
foreach ($file in $files) {
    $name = [IO.Path]::GetFileName($file)
    $expected = $artifactInfo[$name]
    $matching = @($release.assets | Where-Object { $_.name -ceq $name })
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne $expected.Hash -or (Get-Item -LiteralPath $file).Length -ne $expected.Size) { throw 'A local artifact changed before final verification; publication was stopped.' }
    if ($matching.Count -ne 1 -or $matching[0].digest -ne "sha256:$hash" -or
        $matching[0].state -ne 'uploaded' -or $matching[0].size -ne (Get-Item -LiteralPath $file).Length) {
        throw "GitHub integrity verification failed for $name; the release remains a draft"
    }
}
$repositoryInfo = Invoke-GitHubJson -Arguments @('api', "repos/$Repository", '--jq', '{id: .id, private: .private, full_name: .full_name}')
if (-not $repositoryInfo.private -or $repositoryInfo.id -ne $repositoryId -or $repositoryInfo.full_name.ToLowerInvariant() -ne $Repository.ToLowerInvariant()) { throw 'Repository privacy/identity changed; publication was stopped.' }
$published = Invoke-GitHub -Arguments @('release', 'edit', "v$Version", '--repo', $Repository, '--draft=false', '--latest', '--title', "NN4K $Version", '--notes-file', $notesFile)
if ($published.ExitCode -ne 0) { throw 'Could not publish verified draft release' }
Write-Output "Published: https://github.com/$Repository/releases/tag/v$Version"
