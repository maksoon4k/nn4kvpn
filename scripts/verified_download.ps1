#Requires -Version 5

# Download only pinned HTTPS release assets and verify BEFORE extracting/running.
# The caller owns and must remove the returned, uniquely named staging directory.
function Get-VerifiedReleaseArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$Sha256
    )

    $parsed = [Uri]$Uri
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'github.com' -or
        $parsed.Port -ne 443 -or $parsed.UserInfo) {
        throw 'Only official HTTPS GitHub release downloads are accepted'
    }

    $staging = Join-Path ([IO.Path]::GetTempPath()) ('nn4k-core-' + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
    $archive = Join-Path $staging 'release.zip'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $archive -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actual -ne $Sha256) {
            throw 'Core archive SHA-256 mismatch; nothing was extracted'
        }
        return [PSCustomObject]@{ Archive = $archive; Directory = $staging }
    } catch {
        Remove-Item -LiteralPath $staging -Recurse -Force
        throw
    }
}
