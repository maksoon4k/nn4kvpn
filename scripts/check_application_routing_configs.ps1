#Requires -Version 5
param(
    [string]$DartPath,
    [string]$SingBoxPath,
    [string]$Directory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\application-schema-checks')
)

# Offline generation and native schema CHECK only. Never start Proxy/TUN,
# inspect live processes, change routes/DNS, contact a server or read profiles.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $DartPath) { $DartPath = Join-Path $repoRoot 'tool\flutter\bin\dart.bat' }
if (-not $SingBoxPath) { $SingBoxPath = Join-Path $repoRoot 'assets\sing-box\sing-box.exe' }
if (-not (Test-Path -LiteralPath $DartPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $SingBoxPath -PathType Leaf)) {
    throw 'The initialized Dart SDK and checksum-verified sing-box binary are required'
}
$root = Join-Path ([IO.Path]::GetFullPath($Directory)) ('schemas-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

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
$hash = (Get-FileHash -LiteralPath $SingBoxPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -cne $versions.SING_BOX_WINDOWS_EXE_SHA256) { throw 'The schema checker does not have the pinned extracted sing-box checksum' }
$version = Invoke-OfflineTool -Executable $SingBoxPath -Arguments @('version') -Name 'version'
if ($version.ExitCode -ne 0 -or ($version.Output -join "`n") -notmatch
    ("(?m)^sing-box version " + [regex]::Escape($expectedVersion) + '\s*$')) {
    throw 'The schema checker is not the pinned sing-box version'
}

$fixtures = @('disabled', 'whitelist', 'blacklist', 'empty-whitelist',
    'empty-blacklist', 'inactive-rules', 'escaped-identities', 'max-rules')
$cases = @()
foreach ($fixture in $fixtures) {
    $cases += [pscustomobject]@{ Policy = $fixture; PairIndex = -1; Reverse = $false }
}
foreach ($fixture in @('whitelist', 'blacklist')) {
    foreach ($index in 0..6) {
        foreach ($reverse in @($false, $true)) {
            $cases += [pscustomobject]@{ Policy = $fixture; PairIndex = $index; Reverse = $reverse }
        }
    }
}
$results = @()
Push-Location $repoRoot
try {
    foreach ($case in $cases) {
        $name = $case.Policy
        $arguments = @('run', 'tool/dump_singbox_config.dart', '--application-policy', $case.Policy)
        if ($case.PairIndex -ge 0) {
            $arguments += @('--dns-pair', [string]$case.PairIndex)
            $name += "-pair-$($case.PairIndex)"
            if ($case.Reverse) { $arguments += '--reverse-dns-pair'; $name += '-reverse' }
        }
        $generated = Invoke-OfflineTool -Executable $DartPath -Arguments $arguments -Name "$name-generate"
        if ($generated.ExitCode -ne 0) { throw "Offline fixture generation failed: $name" }
        $text = ($generated.Output -join "`n") + "`n"
        $config = $text | ConvertFrom-Json
        $rules = @($config.route.rules)
        $applications = @($rules | Where-Object { $_.PSObject.Properties.Name -contains 'process_path_regex' })
        $expectedRules = switch ($case.Policy) {
            'disabled' { 0 }
            'empty-whitelist' { 0 }
            'empty-blacklist' { 0 }
            'inactive-rules' { 0 }
            'max-rules' { 512 }
            default { 4 }
        }
        if ($applications.Count -ne $expectedRules) { throw "Unexpected application rule count: $name" }
        if ($rules[0].action -ne 'sniff' -or $rules[1].action -ne 'reject' -or
            $rules[2].action -ne 'reject' -or $rules[2].port -ne 443 -or
            $rules[3].action -ne 'hijack-dns' -or $rules[3].port -ne 53 -or
            $rules[4].outbound -ne 'direct') {
            throw "VPN infrastructure protection/order changed: $name"
        }
        if (($config.inbounds[0].route_exclude_address -join ',') -ne '203.0.113.7/32,2001:db8::1/128') {
            throw "VPN server route exclusions changed: $name"
        }
        if ($case.Policy -eq 'disabled') {
            if ($config.route.final -ne 'block' -or $rules.Count -ne 7) { throw "Legacy domain/IP routing changed: $name" }
        } else {
            $expectedFinal = if ($case.Policy -in @('blacklist', 'empty-blacklist')) { 'xray-socks-out' } else { 'direct' }
            if ($config.route.final -ne $expectedFinal -or $rules.Count -ne 5 + $expectedRules -or
                $config.route.PSObject.Properties.Name -contains 'rule_set') {
                throw "Application fallback/domain-preset replacement changed: $name"
            }
        }
        if (($expectedRules -gt 0) -ne ($config.route.find_process -eq $true)) { throw "Unexpected process discovery setting: $name" }
        if ($config.dns.strategy -ne 'ipv4_only' -or $config.route.default_domain_resolver -ne 'bootstrap' -or
            $config.dns.servers[0].detour -ne 'xray-socks-out' -or $config.dns.servers[0].type -ne 'tls' -or
            $config.dns.servers[0].tls.enabled -ne $true) {
            throw "Protected encrypted DNS changed: $name"
        }
        if ($case.PairIndex -ge 0 -and (@($config.dns.servers).Count -ne 4 -or @($config.dns.rules).Count -ne 8 -or
            $config.dns.servers[1].detour -ne 'xray-socks-out' -or $config.dns.servers[1].type -ne 'tls')) {
            throw "Encrypted paired DNS failover changed: $name"
        }
        $file = Join-Path $root "$name.json"
        [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($false))
        $checked = Invoke-OfflineTool -Executable $SingBoxPath -Arguments @('check', '-c', $file) -Name "$name-check"
        [IO.File]::WriteAllText((Join-Path $root "$name-check.log"), ($checked.Output -join "`n"), [Text.UTF8Encoding]::new($false))
        $results += [pscustomobject]@{ Name = $name; Passed = $checked.ExitCode -eq 0; ApplicationRules = $expectedRules }
    }
} finally {
    Pop-Location
    [IO.File]::WriteAllText((Join-Path $root 'report.json'),
        ([pscustomobject]@{ SingBoxVersion = $expectedVersion; SingBoxSha256 = $hash;
            SchemaChecks = $results; EngineStarted = $false; LiveProcessSnapshot = $false } | ConvertTo-Json -Depth 6),
        [Text.UTF8Encoding]::new($false))
}
if ($results.Count -ne 36 -or @($results | Where-Object { -not $_.Passed }).Count) {
    throw "Offline application-routing schema checks failed; evidence: $root"
}
Write-Output "36 offline application-routing schema checks passed. Evidence: $root"
