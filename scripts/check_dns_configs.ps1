#Requires -Version 5
param(
    [string]$DartPath,
    [string]$SingBoxPath,
    [string]$Directory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\dns-schema-checks')
)

# Offline schema validation only. Never run a generated engine configuration,
# connect a VPN, change system DNS/routes or read a real user profile.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $DartPath) {
    $command = Get-Command dart.bat -ErrorAction SilentlyContinue
    $DartPath = if ($command) { $command.Source } else { Join-Path $repoRoot 'tool\flutter\bin\dart.bat' }
}
if (-not $SingBoxPath) { $SingBoxPath = Join-Path $repoRoot 'assets\sing-box\sing-box.exe' }
if (-not (Test-Path -LiteralPath $DartPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $SingBoxPath -PathType Leaf)) {
    throw 'The initialized Dart SDK and checksum-verified sing-box binary are required'
}
$root = Join-Path ([IO.Path]::GetFullPath($Directory)) ('schemas-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null

function Invoke-OfflineTool([string]$Executable, [string[]]$Arguments, [string]$Name) {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Executable @Arguments 2> (Join-Path $root "$Name-error.log")
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ Output = $output; ExitCode = $code }
}

$versions = ConvertFrom-StringData ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'core_versions.env')))
$expectedVersion = $versions.SING_BOX_VERSION.TrimStart('v')
$version = Invoke-OfflineTool -Executable $SingBoxPath -Arguments @('version') -Name 'version'
if ($version.ExitCode -ne 0 -or ($version.Output -join "`n") -notmatch
    ("(?m)^sing-box version " + [regex]::Escape($expectedVersion) + '\s*$')) {
    throw 'The schema checker is not the pinned sing-box version'
}

$results = @()
Push-Location $repoRoot
try {
    foreach ($index in -1..6) {
        foreach ($reverse in @($false, $true)) {
            if ($index -eq -1 -and $reverse) { continue }
            $arguments = @('run', 'tool/dump_singbox_config.dart')
            $name = 'default'
            if ($index -ge 0) {
                $arguments += @('--dns-pair', [string]$index)
                $name = "pair-$index"
                if ($reverse) { $arguments += '--reverse-dns-pair'; $name += '-reverse' }
            }
            $generated = Invoke-OfflineTool -Executable $DartPath -Arguments $arguments -Name "$name-generate"
            if ($generated.ExitCode -ne 0) { throw "Offline fixture generation failed: $name" }
            $text = ($generated.Output -join "`n") + "`n"
            $null = $text | ConvertFrom-Json
            $config = Join-Path $root "$name.json"
            [IO.File]::WriteAllText($config, $text, [Text.UTF8Encoding]::new($false))
            $checked = Invoke-OfflineTool -Executable $SingBoxPath -Arguments @('check', '-c', $config) -Name "$name-check"
            [IO.File]::WriteAllText((Join-Path $root "$name-check.log"), ($checked.Output -join "`n"), [Text.UTF8Encoding]::new($false))
            $results += [pscustomobject]@{ Name = $name; Passed = $checked.ExitCode -eq 0 }
        }
    }
} finally {
    Pop-Location
    [IO.File]::WriteAllText((Join-Path $root 'report.json'),
        ([pscustomobject]@{ SingBoxVersion = $expectedVersion; SchemaChecks = $results; EngineStarted = $false } | ConvertTo-Json -Depth 6),
        [Text.UTF8Encoding]::new($false))
}
if ($results.Count -ne 15 -or @($results | Where-Object { -not $_.Passed }).Count) {
    throw "Offline DNS schema checks failed; evidence: $root"
}
Write-Output "15 offline DNS schema checks passed. Evidence: $root"
