#Requires -Version 5
param(
    [string]$Executable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\windows\x64\runner\Release\nn4k.exe'),
    [string]$Directory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\smoke'),
    [switch]$FirstRun
)

# UI startup only. Never import real profiles, click connection controls,
# install updates, change the system proxy, or stop unrelated processes.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'The built nn4k.exe was not found.' }
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$runRoot = Join-Path ([IO.Path]::GetFullPath($Directory)) ('safe-start-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$report = [ordered]@{
    StartedAt = [DateTime]::UtcNow.ToString('o')
    ExecutableSha256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant()
    RunDirectory = $runRoot
    ProfileMode = $(if ($FirstRun) { 'FirstRun' } else { 'IsolatedMainScreen' })
    Pid = $null
    WindowOpened = $false
    WindowTitle = $null
    CoreChildrenObserved = @()
    TcpConnectionInspectionAvailable = $false
    TcpConnectionsObserved = $null
    TcpSocketDetailsObserved = @()
    TcpSnapshotsObserved = @()
    ProxyUnchanged = $false
    UriHandlerUnchanged = $false
    ExitedGracefully = $false
    ForcedTermination = $false
    ExitCode = $null
    Passed = $false
    Error = $null
}

function Read-RegistrySnapshot([string]$Path, [string[]]$Names) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false)
    try {
        $values = [ordered]@{ KeyExists = $null -ne $key }
        foreach ($name in $Names) {
            if ($null -eq $key -or $key.GetValueNames() -notcontains $name) {
                $values[$name] = [ordered]@{ Exists = $false }
            } else {
                $values[$name] = [ordered]@{
                    Exists = $true
                    Kind = $key.GetValueKind($name).ToString()
                    Value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
            }
        }
        # Snapshot values stay in memory only; never put proxy URLs in reports.
        return ($values | ConvertTo-Json -Compress -Depth 8)
    } finally { if ($key) { $key.Dispose() } }
}

function Read-ProxySnapshot {
    return Read-RegistrySnapshot 'Software\Microsoft\Windows\CurrentVersion\Internet Settings' @('ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL')
}

function Read-UriSnapshot {
    return @(
        (Read-RegistrySnapshot 'Software\Classes\flux' @('', 'URL Protocol')),
        (Read-RegistrySnapshot 'Software\Classes\flux\shell\open\command' @(''))
    ) -join "`n"
}

$previousEnvironment = @{}
$process = $null
$beforeProxy = Read-ProxySnapshot
$beforeUri = Read-UriSnapshot

function Observe-OwnedTcp([string]$Phase) {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return }
    try {
        $connections = @(Get-NetTCPConnection -ErrorAction Stop | Where-Object OwningProcess -eq $process.Id)
    } catch {
        # A failed OS query is explicitly recorded, not evidence of no traffic.
        $report.TcpSnapshotsObserved += [PSCustomObject]@{ Phase = $Phase; Available = $false; Count = $null }
        return
    }
    $report.TcpConnectionInspectionAvailable = $true
    $report.TcpConnectionsObserved = [Math]::Max([int]$report.TcpConnectionsObserved, $connections.Count)
    $report.TcpSnapshotsObserved += [PSCustomObject]@{ Phase = $Phase; Available = $true; Count = $connections.Count }
    # Record socket state/endpoint classes and ports, never raw IP addresses.
    $report.TcpSocketDetailsObserved += @($connections | ForEach-Object {
        $local = [Net.IPAddress]::Parse($_.LocalAddress)
        $remote = [Net.IPAddress]::Parse($_.RemoteAddress)
        [PSCustomObject]@{
            Phase = $Phase
            State = $_.State.ToString()
            LocalLoopback = [Net.IPAddress]::IsLoopback($local)
            RemoteLoopback = [Net.IPAddress]::IsLoopback($remote)
            LocalUnspecified = $local.Equals([Net.IPAddress]::Any) -or $local.Equals([Net.IPAddress]::IPv6Any)
            RemoteUnspecified = $remote.Equals([Net.IPAddress]::Any) -or $remote.Equals([Net.IPAddress]::IPv6Any)
            LocalPort = $_.LocalPort
            RemotePort = $_.RemotePort
        }
    })
    if ($connections.Count) { throw "TCP activity was observed in the isolated safe-start process ($Phase)." }
}

try {
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        $isolated = Join-Path $runRoot $name
        [IO.Directory]::CreateDirectory($isolated) | Out-Null
        [Environment]::SetEnvironmentVariable($name, $isolated, 'Process')
    }
    if (-not $FirstRun) {
        # Only this disposable main-screen test skips onboarding and hides the
        # animated background. Never change the real user's settings or defaults.
        $profileDirectory = Join-Path $env:APPDATA 'flux'
        [IO.Directory]::CreateDirectory($profileDirectory) | Out-Null
        $settings = @{ onboardingCompleted = $true; homeBackground = 'none'; autoConnectOnStartup = $false; pingAllOnStartup = $false; autoInstallUpdates = $false }
        [IO.File]::WriteAllText((Join-Path $profileDirectory 'settings.json'), ($settings | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }

    $process = Start-Process -FilePath $Executable -ArgumentList '--safe-start' `
        -WorkingDirectory (Split-Path -Parent $Executable) -PassThru `
        -RedirectStandardOutput (Join-Path $runRoot 'stdout.log') `
        -RedirectStandardError (Join-Path $runRoot 'stderr.log')
    $report.Pid = $process.Id
    # Retain the native process handle before it exits. Windows PowerShell's
    # Start-Process object may otherwise lose access to its final exit code.
    [void]$process.Handle
    if (-not $process.WaitForInputIdle(60000)) { throw 'UI startup exceeded the input-idle deadline.' }
    Observe-OwnedTcp 'InputIdle'
    # Observe this process for ten seconds, waiting on its exit event (no file
    # polling), so early Flutter/native initialization failures are detected.
    if ($process.WaitForExit(10000)) { throw 'The isolated application exited before the UI check.' }
    $process.Refresh()
    $report.WindowOpened = $process.MainWindowHandle -ne [IntPtr]::Zero
    $report.WindowTitle = $process.MainWindowTitle
    if (-not $report.WindowOpened) { throw 'The isolated application did not expose a main window.' }

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($process.Id)")
    $report.CoreChildrenObserved = @($children | Where-Object { $_.Name -in @('xray.exe', 'sing-box.exe') } | ForEach-Object Name)
    if ($report.CoreChildrenObserved.Count) { throw 'A VPN core was observed during safe-start.' }
    Observe-OwnedTcp 'AfterObservationWindow'

    if (-not $process.CloseMainWindow()) { throw 'Could not request closing the isolated window.' }
    if (-not $process.WaitForExit(15000)) { throw 'The isolated application did not exit after closing its window.' }
    $report.ExitedGracefully = $true
    $report.ExitCode = $process.ExitCode
    if ($process.ExitCode -ne 0) { throw 'The isolated application returned a nonzero exit code.' }
} catch {
    $report.Error = $_.Exception.Message
} finally {
    if ($process -and -not $process.HasExited) {
        # Request a normal close even when an observation failed. Do not use
        # forced termination until the owned process ignores that request.
        [void]$process.CloseMainWindow()
        [void]$process.WaitForExit(5000)
    }
    if ($process -and -not $process.HasExited) {
        # This handle/PID belongs only to the instance this script started.
        $report.ForcedTermination = $true
        Stop-Process -InputObject $process -Force -ErrorAction SilentlyContinue
        [void]$process.WaitForExit(5000)
    }
    if ($process -and $process.HasExited) {
        $report.ExitCode = $process.ExitCode
    }
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
    $report.ProxyUnchanged = (Read-ProxySnapshot) -eq $beforeProxy
    $report.UriHandlerUnchanged = (Read-UriSnapshot) -eq $beforeUri
    if (-not $report.ProxyUnchanged -or -not $report.UriHandlerUnchanged) {
        $report.Error = 'Observed proxy/URI registration changed during the check; no automatic restoration was attempted.'
    }
    $report.Passed = -not $report.Error -and $report.WindowOpened -and $report.ExitedGracefully -and -not $report.ForcedTermination
    if ($process) { $process.Dispose() }
    $json = $report | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $runRoot 'report.json'), $json, [Text.UTF8Encoding]::new($false))
    Write-Output $json
}
if (-not $report.Passed) { throw "Isolated safe-start smoke check failed; evidence: $runRoot" }
