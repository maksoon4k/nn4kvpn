# Windows build and validation

This fork builds **Windows x64 only**. Native Proxy/TUN operation must not be
tested automatically on the user's machine (`CLAUDE.md`). A passing unit suite
or successful compilation is not evidence that live VPN/privacy behavior is
correct.

## Toolchain

- Flutter **3.50.1** / Dart **3.14.0** (stable).
- Visual Studio Desktop development with C++ and MSVC x64 tools.
- Windows SDK headers, x64 libraries, Universal CRT, `rc.exe` and `mt.exe`.
- Inno Setup **7.1.1** for packaging. `scripts/install_inno_setup.ps1` downloads
  the checksum-pinned compiler; the local compiler signature was additionally
  verified during provisioning. Supply an explicit destination on a disk with space.
- Git/GitHub CLI for source and release publication, authenticated locally.

The local machine's Visual Studio Build Tools are on `E:\с++`. SDK provisioning
is separate from the repository and targets `D:\Windows Kits\10`; no SDK
installer or toolchain cache should be committed.

## Keep downloads, caches and build temporary files off C:

Before running development commands, set the following for the **current
PowerShell process**; do not change global user/system environment settings:

```powershell
$env:TEMP = 'D:\nn4kvpn-build-tmp'
$env:TMP = $env:TEMP
$env:PUB_CACHE = 'D:\nn4kvpn\.pub-cache'
$env:FLUTTER_ROOT = 'D:\nn4kvpn\tool\flutter'
$env:NUGET_PACKAGES = 'D:\nn4kvpn-tools\nuget-cache\packages'
$env:NUGET_HTTP_CACHE_PATH = 'D:\nn4kvpn-tools\nuget-cache\http'
$env:NUGET_PLUGINS_CACHE_PATH = 'D:\nn4kvpn-tools\nuget-cache\plugins'
$env:NUGET_SCRATCH = 'D:\nn4kvpn-tools\nuget-cache\scratch'
$env:DOTNET_CLI_HOME = 'D:\nn4kvpn-build-tmp\dotnet'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
```

Set these paths to your checkout/toolchain locations if they differ. The SDK,
Flutter downloads, package cache and application build output must all have
space on D:. These settings do **not** guarantee that a Windows SDK Burn/MSI
installer avoids system caches or restore points on C:. Do not repeatedly run
that installer on a full system drive assuming `/InstallPath` relocates them.

For a verified SDK in a nonstandard location, CMake supports the process-local
`CMAKE_WINDOWS_KITS_10_DIR` variable. MSBuild additionally needs the SDK and
Universal CRT roots, including `UCRTContentRoot`; use the optional helper:

```powershell
. ./scripts/use_windows_sdk.ps1 -SdkRoot 'D:\Windows Kits\10'
```

It checks required files and changes only the current process environment, not
the registry or system/user environment. SDK discovery must resolve the actual
headers/libraries; never mask a missing `kernel32.lib` with dummy files or
disable compiler checks. Correct system registrations only when they are
confirmed orphaned and preserve their prior values/types for rollback.

## Resolve, test and build

```powershell
./scripts/fetch_xray.ps1
./scripts/fetch_sing_box.ps1
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build windows --release --no-pub `
  --dart-define=NN4K_UPDATE_REPOSITORY=maksoon4k/nn4kvpn
```

For a different fork, use its actual repository slug. Omitting the define leaves
repository configuration to the in-app update settings; it must not fall back
to the upstream repository. Do not put any token into a build command.

The Windows core archive pins/hashes live in `scripts/core_versions.env`:
Xray **v26.11.9** and sing-box **v1.14.4**. Downloads are verified before
extraction; native source and embedded dependencies need separate review.

The application bundle is `build\windows\x64\runner\Release\nn4k.exe` plus
its DLLs, data and whitelisted core assets. Do not distribute the EXE alone.
Inter fonts are included locally with the original byte/hash pins and SIL
license (`assets/fonts/SOURCE.md`). The UI no longer has a runtime Google Fonts
download/cache path; text-style metrics and the original setup flow are retained.
The CMake `INSTALL` target is staging, not system installation: its prefix is
forced to the executable's build directory on every configuration. This avoids
a stale failed-configuration cache copying runtime files into `C:\Program Files`.

The media plugin pins NuGet **5.10.0** by SHA-256 and WIL
**1.0.220914.1** by version. Its "Nuget is not installed" stderr notice is a
handled download path, not itself a build failure. The packaging helper checks
native exit codes explicitly; the local NuGet binary's pinned hash and Microsoft
Authenticode signature were also verified. This is not a full WIL/plugin audit.

If the bundled Flutter `.bat` launcher cannot initialize in this local
environment, the already provisioned tool snapshot can be invoked directly:

```powershell
& "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe" `
  "--packages=$env:FLUTTER_ROOT\packages\flutter_tools\.dart_tool\package_config.json" `
  "$env:FLUTTER_ROOT\bin\cache\flutter_tools.snapshot" `
  --no-version-check --suppress-analytics test --no-pub
```

Replace `test --no-pub` with the corresponding analyze/build arguments. This
is a workaround for the local initialized SDK, not a replacement for installing
or updating Flutter correctly.

## Package and inspect

```powershell
./scripts/build_installer.ps1 -SkipBuild -IsccPath 'D:\tools\inno\ISCC.exe'
```

Alternatively omit `-SkipBuild` and supply `-UpdateRepository maksoon4k/nn4kvpn`
to let the script fetch verified cores and build before packaging. `-SkipBuild`
does not inject repository configuration into an already compiled application.

Expected outputs in `build\installer`:

```text
NN4KSetup-1.4.3.exe
NN4K-1.4.3-windows-portable.zip
checksums.txt
```

Check the final bundle/ZIP for unexpected executables or launcher scripts.
The packaging helper rejects unlisted native binaries, launcher scripts and
reparse points, and rejects an incomplete runtime bundle before invoking Inno.
It also requires the local font manifest/license and validates all three Inter
font hashes, so a stale pre-font-fix bundle cannot be packaged with `-SkipBuild`.
The installer is per-user, defaults to `%LocalAppData%\NN4K`, retains its fixed
AppId and preserves `%AppData%\flux`. No Authenticode signing is configured.
It accepts only an x64 Windows OS (`ArchitecturesAllowed=x64os`), because the
packaged Wintun driver cannot run through ARM64 x64-application emulation.

The native import inspection found that the media plugin imports Windows Media
Foundation (`MFPlat.dll`). Windows N/KN editions need the appropriate Media
Feature Pack; it is not bundled. The JNI native asset `dartjni.dll` imports
`jvm.dll` and `VCRUNTIME140.dll`, which are not bundled either. JNI belongs to
the inherited Android engine and is not used by the reviewed Windows connection
path; the successful Windows startup is not a test of JNI/JVM functionality.
Other inspected Windows startup binaries import system DLLs and bundled plugins,
not a separate dynamic MSVC runtime. A clean-machine/Windows N test remains pending.

## Isolated smoke check

Launch only `nn4k.exe --safe-start` with fresh `APPDATA`, `LOCALAPPDATA`, `TEMP`
and `TMP` directories on D:. Do not reuse the real user's profile or click any
Proxy/TUN control. This flag suppresses startup connection, subscriptions,
pings, geo downloads, updates, URI registration, single-instance IPC and tray
initialization. It is **not a sandbox** and does not disable deliberate manual
UI actions.

Verify the application opens, inspect process output, close only that test
process, and compare the system proxy registry before/after without modifying
it. Keep smoke evidence separate from private application data. Successful
smoke startup does not validate actual VPN connectivity or updater installation.

The following script performs that limited check and retains its JSON report
and process output in a uniquely named directory:

```powershell
./scripts/smoke_windows.ps1 -Directory 'D:\nn4kvpn-build-tmp\smoke'
./scripts/smoke_windows.ps1 -FirstRun -Directory 'D:\nn4kvpn-build-tmp\smoke'
```

It reads proxy/URI registry snapshots without changing them, never copies a
real profile, and closes only the test process it started. OS TCP inspection,
if available, is an observation at check time, not a full packet capture.
The default test seeds **only disposable settings** with onboarding completed
and background `none` to inspect the main screen. `-FirstRun` creates no settings
file and keeps the original welcome/setup flow and production defaults intact.
Neither mode changes the user's real profile, chosen theme or background.

Publishing safeguards can be exercised without any network calls:

```powershell
./scripts/test_publish_windows_release.ps1
```

It substitutes a local GitHub command stub, checks successful draft publication
and fail-closed retry/tampering/privacy scenarios, and cannot publish to GitHub.

The **Windows Checks** workflow also has a manual `build_windows` option. It
performs analysis, tests and a complete Windows installer/ZIP build with read-only
repository permissions, then stores CI artifacts; it never publishes a release.
The expanded workflow also runs both isolated `--safe-start` UI modes and retains
their JSON/process-output evidence. No real profile or Proxy/TUN connection is used.

## Recorded status — 2026-11-23

- Full suite after the local-font fix: **323 tests passed**, including the original
  first-run setup, completion/skip/replay, background-default and seven
  bundled/offline typography regressions.
- Analyzer: **no errors/warnings**, 15 informational lints.
- Refreshed OSV query: **122 locked hosted Pub packages**, no returned advisories;
  the only lockfile change is removal of `google_fonts` 8.2.0. Native/embedded
  components and the Flutter SDK are outside this query's scope.
- SDK **10.0.26100.0** was provisioned on D: from verified Microsoft packages
  without running Burn/MSI installation again. The x64/x86 C++/resource probes
  compiled, linked against UM/Universal CRT libraries and executed successfully
  using process-local SDK settings; no system SDK registration changes needed.
- The earlier Windows Release compilation and Inno Setup **7.1.1** packaging succeeded.
  Runtime bundle: **310 files / 167084737 bytes**. Every portable ZIP file was
  size/SHA-256 verified against the bundle; no unexpected native binaries,
  launcher scripts, reparse points, duplicate entries or unsafe ZIP paths found.
- Main-screen, extracted-portable and first-run `--safe-start` checks opened the
  NN4K window and closed normally with exit code **0**, without observed core
  children or proxy/URI registry changes. Later TCP snapshots were zero;
  the first six-entry observation is retained in the security review. The later
  expanded hosted check reproduced startup TCP activity; this was a release blocker.
- All **9 Windows tooling scripts** passed syntax validation, and **17 offline
  publication-guard scenarios** passed. Inherited Android tooling is outside this
  validation; its existing syntax problems were not treated as Windows failures.
- [Initial hosted Windows checks](https://github.com/maksoon4k/nn4kvpn/actions/runs/45076118325)
  passed analysis, **316 Flutter tests**, the then-current **14 publishing guards**
  and a full installer/portable build. [Expanded checks](https://github.com/maksoon4k/nn4kvpn/actions/runs/45078475411)
  passed analysis, 316 tests, 17 guards and packaging, but failed startup TCP
  observation. The UI's overlooked online font loader was removed and the same
  fonts bundled; a fresh complete validation is required before publishing.
- Local GitHub authentication and private repository **maksoon4k/nn4kvpn**
  (repository ID **1468003190**) were verified. Source/release publication and
  hosted CI results are recorded only after the remote operations finish.
- End-to-end upgrade and upstream/application licensing: unresolved; see
  [security review](SECURITY_AUDIT.md) and [updates](WINDOWS_UPDATES.md).
