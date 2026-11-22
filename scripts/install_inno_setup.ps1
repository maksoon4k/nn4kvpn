#Requires -Version 5
param(
    [string]$Directory = (Join-Path ([IO.Path]::GetTempPath()) 'NN4K-InnoSetup-7.1.1')
)

$ErrorActionPreference = 'Stop'
$version = '7.1.1'
$expected = '8a5a6711c3766a6e5fb74f280ba0e3551e719ce94538d901fdbd1f8f9920b3f0'
$uri = "https://github.com/jrsoftware/issrc/releases/download/is-7_1_1/innosetup-$version-x64.exe"
$staging = Join-Path ([IO.Path]::GetTempPath()) ('nn4k-inno-download-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
$setup = Join-Path $staging 'InnoSetup.exe'
try {
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $setup
    if ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash -ne $expected) {
        throw 'Inno Setup SHA-256 mismatch; installer was not run'
    }
    # Install this build tool for the current user, not as administrator.
    # /CURRENTUSER is supported by the official Inno Setup installer.
    $process = Start-Process -FilePath $setup -ArgumentList @(
        '/CURRENTUSER', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
        '/NOICONS', ('/DIR="' + [IO.Path]::GetFullPath($Directory) + '"')
    ) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Inno Setup tool installation failed: $($process.ExitCode)" }
    $compiler = Join-Path $Directory 'ISCC.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { throw 'ISCC.exe not found after tool installation' }
    Write-Output $compiler
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
