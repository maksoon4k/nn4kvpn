#Requires -Version 5
param(
    [Parameter(Mandatory = $true)][string]$SdkRoot,
    [ValidatePattern('^10\.0\.[0-9]+\.0$')][string]$SdkVersion = '10.0.26100.0'
)

# Optional process-local discovery for an already verified SDK in a custom
# directory. Do not run the SDK installer or edit machine registry values here.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $SdkRoot -ErrorAction Stop).Path.TrimEnd('\')
$required = @(
    'SDKManifest.xml',
    "Include\$SdkVersion\um\Windows.h",
    "Include\$SdkVersion\shared\sdkddkver.h",
    "Include\$SdkVersion\winrt\wrl\client.h",
    "Include\$SdkVersion\ucrt\stdio.h",
    "Lib\$SdkVersion\um\x64\kernel32.lib",
    "Lib\$SdkVersion\um\x86\kernel32.lib",
    "Lib\$SdkVersion\ucrt\x64\ucrt.lib",
    "Lib\$SdkVersion\ucrt\x64\ucrtd.lib",
    "Lib\$SdkVersion\ucrt\x86\ucrt.lib",
    "Lib\$SdkVersion\ucrt\x86\ucrtd.lib",
    "bin\$SdkVersion\x64\rc.exe",
    "bin\$SdkVersion\x64\mt.exe",
    'DesignTime\CommonConfiguration\Neutral\ucrt.props',
    "DesignTime\CommonConfiguration\Neutral\UAP\$SdkVersion\UAP.props"
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Incomplete SDK: $relative"
    }
}

# ucrt.props has its own UCRTContentRoot lookup; supplying only WindowsSdkDir
# or UniversalCRTSdkDir does not override an orphaned KitsRoot10 registration.
$env:CMAKE_WINDOWS_KITS_10_DIR = $root
$env:WindowsSdkDir_10 = "$root\"
$env:WindowsSdkDir = "$root\"
$env:UniversalCRTSdkDir_10 = "$root\"
$env:UniversalCRTSdkDir = "$root\"
$env:UCRTContentRoot = "$root\"
$env:WindowsSDKVersion = "$SdkVersion\"
$env:WindowsSDKLibVersion = "$SdkVersion\"
$env:UCRTVersion = $SdkVersion
Write-Output "Using Windows SDK $SdkVersion from $root for this PowerShell process only."
