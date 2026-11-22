#Requires -Version 5
param(
    [string]$Directory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\script-tests')
)

# Offline guard tests only. GhPath is replaced with a local command stub, so
# this script cannot create repositories, tags or releases on GitHub.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetFullPath($Directory)) ('publishing-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$mock = Join-Path $root 'mock-gh.ps1'
$publish = Join-Path $PSScriptRoot 'publish_windows_release.ps1'
$target = 'a' * 40
$previousStatePath = $env:NN4K_TEST_GH_STATE

$mockSource = @'
param()
$arguments = @($args)
$state = [IO.File]::ReadAllText($env:NN4K_TEST_GH_STATE) | ConvertFrom-Json
$state.calls = @($state.calls) + @([pscustomobject]@{ Arguments = $arguments })
$global:LASTEXITCODE = 0
function Save-State {
    [IO.File]::WriteAllText($env:NN4K_TEST_GH_STATE, ($state | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
}
function Argument-After([string]$Name) {
    $index = [Array]::IndexOf($arguments, $Name)
    if ($index -lt 0 -or $index + 1 -ge $arguments.Count) { throw 'Missing stub argument.' }
    return $arguments[$index + 1]
}
if ($arguments[0] -eq 'api') {
    if ($arguments[1] -eq 'repos/test-owner/nn4kvpn') {
        $state.repoCalls++
        $private = $state.scenario -ne 'public'
        $id = 99
        if ($state.scenario -eq 'privacyChanged' -and $state.repoCalls -gt 1) { $private = $false }
        if ($state.scenario -eq 'repositoryIdentityChanged' -and $state.repoCalls -gt 1) { $id = 100 }
        Save-State
        [pscustomobject]@{ id = $id; private = $private; full_name = 'test-owner/nn4kvpn' } | ConvertTo-Json -Compress
        return
    }
    if ($arguments[1] -eq 'repos/test-owner/nn4kvpn/releases/tags/v9.9.9') {
        $state.tagApiCalls++
        Save-State
        $global:LASTEXITCODE = 1
        Write-Error 'HTTP 404: an unpublished draft without a tag is unavailable through the tag endpoint'
        return
    }
    if ($arguments[1] -eq 'repos/test-owner/nn4kvpn/releases/123') {
        $state.releaseApiCalls++
        if ($state.scenario -eq 'publishedMidway' -and $state.releaseApiCalls -gt 1) { $state.release.draft = $false }
        if ($state.scenario -eq 'releaseIdentityChanged' -and $state.releaseApiCalls -gt 1) { $state.release.id = 124 }
        Save-State
        $state.release | ConvertTo-Json -Depth 12 -Compress
        return
    }
}
if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'view') {
    Save-State
    if ($state.scenario -eq 'authFailure') {
        $global:LASTEXITCODE = 1
        Write-Error 'HTTP 401: authentication failed'
        return
    }
    if ($null -eq $state.release) {
        $global:LASTEXITCODE = 1
        Write-Error 'release not found'
        return
    }
    $databaseId = $state.release.id
    if ($state.scenario -eq 'invalidDraftId') { $databaseId = 0 }
    [pscustomobject]@{
        databaseId = $databaseId; isDraft = $state.release.draft
        isPrerelease = $state.release.prerelease; tagName = $state.release.tag_name
        targetCommitish = $state.release.target_commitish
    } | ConvertTo-Json -Compress
    return
}
if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'create') {
    $state.creates++
    $state.release = [pscustomobject]@{
        id = 123; tag_name = 'v9.9.9'; target_commitish = (Argument-After '--target')
        draft = $true; prerelease = $false; assets = @()
    }
    Save-State
    return
}
if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'upload') {
    $file = $arguments[3]
    $state.uploads++
    $state.release.assets = @($state.release.assets) + @([pscustomobject]@{
        name = [IO.Path]::GetFileName($file); state = 'uploaded'
        size = (Get-Item -LiteralPath $file).Length
        digest = 'sha256:' + (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    })
    if ($state.scenario -eq 'localTampering' -and $state.uploads -eq 1) {
        [IO.File]::AppendAllText($file, 'tampered')
    }
    Save-State
    return
}
if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'edit') {
    if ($arguments -notcontains '--draft=false' -or $arguments -notcontains '--latest') { throw 'Unexpected publication flags.' }
    $state.edits++
    $state.release.draft = $false
    Save-State
    return
}
Save-State
throw 'Unexpected command sent to the offline GitHub stub.'
'@
[IO.File]::WriteAllText($mock, $mockSource, [Text.UTF8Encoding]::new($false))

$cases = @(
    @{ Name = 'newDraft'; Fails = $false; Uploads = 3; Edits = 1 },
    @{ Name = 'newDraftWithoutTag'; Fails = $false; Uploads = 3; Edits = 1 },
    @{ Name = 'published'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'public'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'badChecksums'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'authFailure'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'identicalRetry'; Fails = $false; Uploads = 0; Edits = 1 },
    @{ Name = 'conflictingAsset'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'differentTarget'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'invalidDraftId'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'draftPrerelease'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'publishedMidway'; Fails = $true; Uploads = 1; Edits = 0 },
    @{ Name = 'releaseIdentityChanged'; Fails = $true; Uploads = 1; Edits = 0 },
    @{ Name = 'localTampering'; Fails = $true; Uploads = 3; Edits = 0 },
    @{ Name = 'extraAsset'; Fails = $true; Uploads = 0; Edits = 0 },
    @{ Name = 'privacyChanged'; Fails = $true; Uploads = 3; Edits = 0 },
    @{ Name = 'repositoryIdentityChanged'; Fails = $true; Uploads = 3; Edits = 0 }
)
$results = @()
try {
    foreach ($case in $cases) {
        $directory = Join-Path $root $case.Name
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        $installer = Join-Path $directory 'NN4KSetup-9.9.9.exe'
        $portable = Join-Path $directory 'NN4K-9.9.9-windows-portable.zip'
        [IO.File]::WriteAllText($installer, 'MZ offline test fixture')
        [IO.File]::WriteAllText($portable, 'offline archive fixture')
        $checksumsPath = Join-Path $directory 'checksums.txt'
        $checksums = @($installer, $portable) | ForEach-Object {
            '{0}  {1}' -f (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant(), [IO.Path]::GetFileName($_)
        }
        [IO.File]::WriteAllLines($checksumsPath, [string[]]$checksums, [Text.UTF8Encoding]::new($false))
        if ($case.Name -eq 'badChecksums') { [IO.File]::WriteAllText($checksumsPath, 'invalid') }
        $release = $null
        if ($case.Name -in @('published', 'identicalRetry', 'conflictingAsset', 'differentTarget', 'extraAsset', 'invalidDraftId', 'draftPrerelease')) {
            $assets = @($installer, $portable, $checksumsPath) | ForEach-Object {
                [pscustomobject]@{
                    name = [IO.Path]::GetFileName($_); state = 'uploaded'; size = (Get-Item -LiteralPath $_).Length
                    digest = 'sha256:' + (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
            if ($case.Name -eq 'conflictingAsset') { $assets[0].digest = 'sha256:' + ('0' * 64) }
            if ($case.Name -eq 'extraAsset') { $assets = @($assets) + @([pscustomobject]@{name = 'unexpected.exe'; state = 'uploaded'; size = 1; digest = 'sha256:' + ('0' * 64)}) }
            $release = [pscustomobject]@{
                id = 123; tag_name = 'v9.9.9'; target_commitish = $target
                draft = $case.Name -ne 'published'; prerelease = $false; assets = @($assets)
            }
            if ($case.Name -eq 'differentTarget') { $release.target_commitish = 'b' * 40 }
            if ($case.Name -eq 'draftPrerelease') { $release.prerelease = $true }
        }
        $statePath = Join-Path $directory 'state.json'
        $state = [pscustomobject]@{
            scenario = $case.Name; repoCalls = 0; releaseApiCalls = 0; tagApiCalls = 0; calls = @()
            creates = 0; uploads = 0; edits = 0; release = $release
        }
        [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        $env:NN4K_TEST_GH_STATE = $statePath
        $failed = $false
        $errorMessage = $null
        try {
            & $publish -Repository 'test-owner/nn4kvpn' -Version '9.9.9' -ArtifactDirectory $directory -TargetCommit $target -GhPath $mock | Out-Null
        } catch {
            $failed = $true
            $errorMessage = $_.Exception.Message
        }
        $after = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        $usedClobber = @($after.calls | Where-Object { $_.Arguments -contains '--clobber' }).Count -ne 0
        $passed = $failed -eq $case.Fails -and $after.uploads -eq $case.Uploads -and $after.edits -eq $case.Edits -and $after.tagApiCalls -eq 0 -and -not $usedClobber
        $results += [pscustomobject]@{ Case = $case.Name; Passed = $passed; FailedSafely = $failed; Uploads = $after.uploads; Publications = $after.edits; TagEndpointLookups = $after.tagApiCalls; Error = $errorMessage }
    }
} finally {
    $env:NN4K_TEST_GH_STATE = $previousStatePath
    [IO.File]::WriteAllText((Join-Path $root 'report.json'), ($results | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}
$failures = @($results | Where-Object { -not $_.Passed })
if ($failures.Count -or $results.Count -ne $cases.Count) {
    $failures | ConvertTo-Json -Depth 5
    throw "Offline release guard tests failed; evidence: $root"
}
Write-Output "$($results.Count) offline release guard tests passed. Evidence: $root"
