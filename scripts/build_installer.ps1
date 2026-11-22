#Requires -Version 5
param(
    [string]$UpdateRepository = $env:NN4K_UPDATE_REPOSITORY,
    [string]$FlutterPath,
    [string]$IsccPath,
    [switch]$SkipBuild
)
<#
Builds the Release exe and packages it into a single NN4KSetup-<version>.exe
installer with Inno Setup — replaces manually zipping up
build\windows\x64\runner\Release\ for distribution (see ROADMAP.md, трек 13).

Requires Inno Setup 7 (ISCC.exe). scripts/install_inno_setup.ps1 installs the
pinned, checksum-verified compiler for the current user. CI also uses this file.
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-BuildTool([string]$Executable, [string[]]$Arguments, [string]$FailureMessage) {
    # A native tool's informational stderr is not a failed process. Windows
    # PowerShell 5 wraps it in ErrorRecords even when the tool exits with zero.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw $FailureMessage }
}

$pubspec = Get-Content (Join-Path $repoRoot "pubspec.yaml") -Raw
if ($pubspec -notmatch "(?m)^version:\s*(\S+)") {
    throw "Could not find 'version:' in pubspec.yaml"
}
# pubspec version is "1.0.0+1" (semver+build number) — Inno Setup's
# AppVersion only wants the semver part.
$version = $Matches[1].Split('+')[0]

Write-Output "Building NN4K $version (Release)..."
if ($UpdateRepository -and $UpdateRepository -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}/[a-zA-Z0-9_.-]{1,100}$') {
    throw 'UpdateRepository must be owner/repository, never a token or URL'
}

Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        if (-not $FlutterPath) {
            $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
            if ($command) { $FlutterPath = $command.Source }
            else { $FlutterPath = Join-Path $repoRoot 'tool\flutter\bin\flutter.bat' }
        }
        if (-not (Test-Path -LiteralPath $FlutterPath)) { throw 'Flutter SDK was not found' }
        & (Join-Path $PSScriptRoot 'fetch_xray.ps1')
        & (Join-Path $PSScriptRoot 'fetch_sing_box.ps1')
        Invoke-BuildTool -Executable $FlutterPath -Arguments @('pub', 'get', '--enforce-lockfile') -FailureMessage 'Locked dependency resolution failed'
        $arguments = @('build', 'windows', '--release', '--no-pub')
        if ($UpdateRepository) { $arguments += "--dart-define=NN4K_UPDATE_REPOSITORY=$UpdateRepository" }
        Invoke-BuildTool -Executable $FlutterPath -Arguments $arguments -FailureMessage 'Flutter Windows build failed'
    }

    if (-not $IsccPath) {
        $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($command) { $IsccPath = $command.Source }
        else {
            $candidates = @(
                "${env:ProgramFiles}\Inno Setup 7\ISCC.exe",
                "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
            )
            $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        }
    }
    if (-not $IsccPath) { throw 'ISCC.exe not found; run scripts/install_inno_setup.ps1 or supply -IsccPath' }
    $release = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath (Join-Path $release 'nn4k.exe'))) { throw 'Release nn4k.exe not found' }
    foreach ($relative in @(
        'flutter_windows.dll', 'local_notifier_plugin.dll',
        'screen_retriever_windows_plugin.dll', 'tray_manager_plugin.dll',
        'video_player_win_plugin.dll', 'window_manager_plugin.dll', 'dartjni.dll',
        'data\icudtl.dat', 'data\app.so', 'data\flutter_assets\AssetManifest.bin',
        'assets\xray\xray.exe', 'assets\xray\wintun.dll',
        'assets\xray\LICENSE', 'assets\xray\LICENSE-Wintun',
        'assets\sing-box\sing-box.exe', 'assets\sing-box\LICENSE'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $relative) -PathType Leaf)) {
            throw "Incomplete runnable bundle: $relative. Rebuild before packaging; never distribute nn4k.exe alone."
        }
    }
    $allowedNative = @(
        'nn4k.exe', 'flutter_windows.dll', 'local_notifier_plugin.dll',
        'screen_retriever_windows_plugin.dll', 'tray_manager_plugin.dll',
        'video_player_win_plugin.dll', 'window_manager_plugin.dll', 'dartjni.dll',
        'data\app.so', 'assets\xray\xray.exe', 'assets\xray\wintun.dll',
        'assets\sing-box\sing-box.exe'
    )
    foreach ($entry in Get-ChildItem -LiteralPath $release -Recurse -Force) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The runtime bundle contains a reparse point; packaging stopped.' }
        if ($entry.PSIsContainer) { continue }
        $relative = $entry.FullName.Substring($release.Length + 1)
        if (($entry.Extension -match '(?i)^\.(?:exe|dll|so)$' -and $allowedNative -notcontains $relative) -or
            $entry.Extension -match '(?i)^\.(?:cmd|bat|ps1|vbs|js|jse|wsf|msi|scr|lnk)$') {
            throw "Unexpected executable or launcher in the runtime bundle: $relative"
        }
    }
    $output = Join-Path $repoRoot 'build\installer'
    New-Item -ItemType Directory -Path $output -Force | Out-Null

    Write-Output 'Packaging installer with Inno Setup...'
    Invoke-BuildTool -Executable $IsccPath -Arguments @("/DAppVersion=$version", (Join-Path $repoRoot 'windows\installer\flux.iss')) -FailureMessage 'ISCC failed'
    $portable = Join-Path $output "NN4K-$version-windows-portable.zip"
    Compress-Archive -Path (Join-Path $release '*') -DestinationPath $portable -Force
    $files = @(
        (Join-Path $output "NN4KSetup-$version.exe"),
        $portable
    )
    $checksums = foreach ($file in $files) {
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $([IO.Path]::GetFileName($file))"
    }
    [IO.File]::WriteAllLines((Join-Path $output 'checksums.txt'), [string[]]$checksums, [Text.UTF8Encoding]::new($false))
    Write-Output "Done: $output"
} finally {
    Pop-Location
}
