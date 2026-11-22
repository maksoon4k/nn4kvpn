# Qualified security review — NN4K 1.4.3+8

Review dates: **2026-11-22–23**. Scope: the supplied source tree, Windows-sensitive
application code, dependencies, packaging and the new GitHub updater.

## Conclusion and limits

The inspected first-party code did not reveal a clear deliberate backdoor or
an unexplained credential-upload endpoint. This is a **limited source review**,
not proof of absence of backdoors, a penetration test, an antivirus verdict or
a complete-security guarantee. Numerous security and reliability defects were
found and hardened; the important changes and residual risks are below.

Prebuilt Xray, sing-box, Flutter, native plugins, system DLLs and drivers were
not exhaustively audited or rebuilt from source. The locked dependency scan
does not cover every native/embedded component. Inherited non-Windows platform
code was not dynamically validated. Live Proxy/TUN tests were deliberately not
performed, as required by this project's `CLAUDE.md`.

## Validation evidence

| Check | Recorded result |
| --- | --- |
| Full Flutter unit/widget suite | **323 tests passed**, including deep-link, bounded download, IPC, system-tool path, proxy-lease, connection-lifecycle, updater, original first-run setup and seven bundled/offline typography regressions. |
| Dart analyzer | No errors or warnings; **15 informational lints** remain (UI deprecations/style and developer-tool imports). |
| Locked hosted Pub packages queried in OSV | **122 packages**, no known reported vulnerabilities returned after removing `google_fonts`; no other package version changed. |
| OSV scope | Pub hosted packages only; Flutter SDK, native cores, drivers and embedded/native dependencies excluded. |
| Windows tooling scripts | **9 scripts** passed syntax checks; **17 offline publishing-guard tests** passed, including identity/privacy changes, asset conflicts, tampering, safe retries and unpublished drafts without a tag. |
| Windows build and packaging | Release **1.4.3+8** compiled for `maksoon4k/nn4kvpn`; Inno Setup **7.1.1** produced the per-user x64 installer. The published files are the exact artifacts from the final successful hosted build. |
| Published bundle and portable ZIP | **315 files / 154694931 runtime bytes**; every ZIP file matched the verified CI bundle's size/SHA-256. No unexpected native binaries/scripts, reparse points, unsafe paths or duplicate entries found. Inter pins/license and the compiled update repository were verified. |
| Isolated `--safe-start` UI | Both main-screen and first-run modes passed on GitHub and locally using the exact CI portable: windows opened, normal exit **0**, two available zero-count TCP snapshots per mode, no observed core children, unchanged proxy/URI state. These are limited observations, not packet capture. |
| Private release publication | Stable **v1.4.3**, release ID **454794402**, published into the verified private repository **1468003190**. Tag/latest and all three asset IDs, sizes and GitHub SHA-256 digests were checked. |
| Independent release download | All three published assets were downloaded separately to D: and rehashed; the portable ZIP's **315 files** again matched the verified CI runtime. |
| Production updater replay | Actual published metadata and separately downloaded installer bytes accepted through the production updater with a mock client. Newer-only/no-downgrade, final verification, same-size tampering rejection and owned-copy cleanup passed. No application token, installer launch or Proxy/TUN used. |
| Source publication secret scan | **345 candidate files**, **297 text files** inspected with token/key/credential-URL/query/JWT heuristics; two findings were synthetic credential-URL test fixtures, not real credentials. Binary images/fonts were excluded. |
| Live network/privacy behavior | Not certified; no live Proxy/TUN tests performed. |
| End-to-end automatic upgrade | Not yet exercised with a later published release. |

The dependency-scan snapshot is [dependency-audit.json](dependency-audit.json).
It identifies the exact reviewed lockfile hash. A clean scan only means no
matching advisories were returned at that time; it is not a code review.

The [initial hosted Windows checks](https://github.com/maksoon4k/nn4kvpn/actions/runs/45076118325)
also passed **316 Flutter tests**, the then-current **14 publishing-guard tests**,
analysis and complete installer/portable compilation. A subsequent publishing
tool fix expands the guards to 17 and adds isolated startup checks to the hosted
build workflows. [That expanded run](https://github.com/maksoon4k/nn4kvpn/actions/runs/45078475411)
passed analysis, all 316 Flutter tests, 17 guards and packaging, but **failed the
startup gate** after observing six TCP entries. It was not treated as a passing
release validation. After bundling the original fonts and removing their runtime
loader, the [final Windows Checks run](https://github.com/maksoon4k/nn4kvpn/actions/runs/45081917123)
passed analysis, **323 Flutter tests**, **17 publishing guards**, packaging and
both strict startup modes. Its exact installer/portable bytes were published,
not a subsequent rebuild.

Sanitized durable evidence is retained in
[windows-release-validation.json](windows-release-validation.json), including
build/release identities, asset hashes, both hosted/local startup summaries,
native imports, the limited updater replay and the earlier failed observation.
CI artifact retention is seven days; the committed evidence does not depend on
those artifacts remaining available.

### Artifact identity

**Published release assets**, built from
`a6f1f80ac088d8d7250e98d8d67b2049553f90e6` and attached to
[v1.4.3](https://github.com/maksoon4k/nn4kvpn/releases/tag/v1.4.3).
The tag targets that exact tested source commit. These hashes were checked
before upload, against GitHub metadata and after a separate release download.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `NN4KSetup-1.4.3.exe` | 41665634 | `45df7bff26e653a2bb066188b12971679fc9bb287327114f49321bb90e7cb2fc` |
| `NN4K-1.4.3-windows-portable.zip` | 58570060 | `15b7057b2e3fbdd0eec16802383a7e827f905f45840d368d783c6c9efa97c8a3` |
| `checksums.txt` | 186 | `510a05f89020ccb348ffba82c0b72441a3180ae43629a1b51749d0969d9dbdb7` |

The runner SHA-256 is
`3d39b00b3a21e3816ff5b07a4f59ecc88449db20a78af23a8b29acac4d50450c`;
the compiled Dart AOT library is
`f4396446f1539f1f9534905b2b7de0f99af4834b1097da7520733d3eee92ce7f`.
The expected repository slug was found in the AOT library. Hashes identify
the inspected files, not their safety; the installer is **not Authenticode-signed**.

A separate local baseline had **316 files / 168034454 runtime bytes** and a
stale native CMake cache with empty Release C++ flags after earlier SDK failures.
It was preserved as an external baseline and **was not published**. Fresh hosted
artifacts were selected instead and also passed both local isolated startup
modes. Local and hosted builds are not claimed to be byte-reproducible.

### Startup-observation limitations

An initial check with the earlier observer reported **six TCP entries** owned
by the test process, but did not record states or endpoint classes, forced the
process to terminate, and did not retain a valid exit code. Later stricter
checks of the same build and extracted portable files, including a fresh
first-run profile, recorded **zero** owned TCP entries at their observation
points and normal exit code **0**. The expanded hosted run later observed six
entries: three unspecified `Bound` sockets and three non-loopback `Established`
connections to port 443. Publication remained blocked on this failure.

Source inspection found an overlooked runtime-network path: the UI used
`GoogleFonts.inter` with no bundled fonts, so an empty font cache caused three
Inter weights to be requested from `fonts.gstatic.com`. This is a concrete
unintentional startup dependency, consistent with the hosted socket pattern,
but the recorded snapshots do not prove the actual remote host or conclusively
attribute the earlier outlier. An isolated replay of the unchanged, uncached
8.2.0 library confirmed the three font HTTP requests using a mock client and
verified local font responses, without using a real profile or network.
The fix removes `google_fonts` and its cache/
HTTP loader, bundles the **same hash-verified Inter files** and SIL license, and
retains the UI style metrics. New regressions check font bytes, the local font
manifest, the license and absence of HTTP-client creation when building text.
The repeated strict hosted UI/network observation passed in both modes; its
TCP rejection and production onboarding/background defaults were not weakened.

These are process-table snapshots, not packet capture. They cannot exclude
short-lived TCP, UDP/DNS activity or all subprocess behavior. `--safe-start`
suppresses automatic startup actions but is not a sandbox. The main-screen
smoke test alone skips onboarding and hides the background in **disposable
settings only**; the production defaults, original setup steps and user
appearance settings remain intact.

Direct-import inspection of the **published CI runner and plugins** identified
unbundled `MSVCP140.dll`, `VCRUNTIME140.dll` and `VCRUNTIME140_1.dll`: a compatible
**Microsoft Visual C++ v14 x64 Redistributable** is required. The video plugin
also imports `MFPlat.dll`; Windows N/KN needs the appropriate **Media Feature Pack**.
The inherited JNI asset imports external `jvm.dll` and VC-runtime DLLs.
These components are not bundled, and the successful startup machines already
had the relevant Windows prerequisites. JNI/JVM functionality and a
clean-machine/Windows N compatibility test remain untested. See
[build notes](WINDOWS_BUILD.md).

## Remediations

### Executable updates and publishing

- Introduced an in-app Windows updater targeting the user's repository,
  not a hardcoded upstream publisher. Repository input is normalized and
  restricted to a valid GitHub owner/repository.
- Require stable, newer semantic versions, the exact Windows installer asset,
  uploaded state, bounded size and GitHub SHA-256 metadata.
- Use constructed GitHub API URLs, HTTPS-only allowlisted redirects, and
  permanent token stripping after an origin change. Private URLs, HTTP error
  bodies and tokens are not exposed in updater failures.
- Stream installer bytes to disk with awaited writes; enforce size/time bounds,
  validate SHA-256 and executable header, and verify the file again before
  execution. Reject tampering, replaced assets and stale repository results.
- Store a separate read-only token per repository in Windows Credential
  Manager; never serialize it into settings or compile it into the application.
- Default automatic executable installation to off. Defer it while VPN is
  active, invalidate consent on publisher changes, and recheck consent and
  cancellation after asynchronous validation and immediately before launch.
- Block update launch from elevated processes. Stop owned engines and restore
  owned proxy values before exit; the per-user installer waits for the caller.
- Draft-first release publishing verifies uploaded sizes/digests before exposing
  a release through `latest`; published versions must not be overwritten.
- Resolve and pin a positive numeric draft release ID before reading its assets.
  GitHub can return 404 from the tag endpoint for an unpublished draft; this
  real first-publication failure is now covered by the offline API stub.

### Native process and connection lifecycle

- Coordinate concurrent starts, server switches, disconnects and shutdown;
  prevent reconnect while preparing an update or exiting.
- Keep partially failed cleanup retryable; do not drop the only reference to
  an engine that still needs to be stopped.
- Place owned Windows core processes in kill-on-close Job Objects and handle
  unexpected core exits. Harden TUN bridge teardown and temporary-config cleanup.
- Resolve Windows system commands from the OS system directory rather than
  PATH/current-directory lookup, especially before elevating `schtasks.exe`.
  Bound draining of HTTP ping responses so a stalled body cannot hang a ping.
- Restore the original system proxy values and registry types through
  `SystemProxyLease`, rather than blindly disabling an existing proxy. Preserve
  PAC/bypass/unrelated values and avoid overwriting another application's proxy.

### Untrusted downloaded data and local IPC

- Bound streamed/decompressed subscription data to 8 MiB, fallback host lists
  to 64 KiB, routing presets to 2 MiB and geo assets to 64 MiB.
- Bound redirects and total deadlines, abort/cancel timed-out requests, and
  reject HTTPS-to-HTTP downgrade redirects. Plain HTTP remains an explicitly
  enabled compatibility option for non-executable data only.
- Limit fallback attempts to 16, validate fallback hosts, clamp subscription
  timeouts to 100–30000 ms and reject malformed payload/expiry values safely.
- Validate geo protobuf wire types, lengths, varints, required fields, CIDRs
  and record budgets; reject empty/malformed downloads before atomic replacement.
- Bound loopback IPC to 32 KiB, eight peers, a fixed two-second message deadline,
  one valid UTF-8 line, and eight messages per ten seconds. Accept only empty
  focus requests or `flux://` messages.
- Harden deep-link decoding, reject control characters/invalid escapes,
  unsupported actions and payload schemes, and allow only one deep-link dialog
  at a time. A link only pre-fills an import dialog; it does not authorize a
  network request, import, VPN connection or installer launch.

### Persistence and supply chain

- Write settings/profile JSON atomically and publish provider changes only
  after successful persistence.
- Restrict managed background-file cleanup to application-owned copies;
  never delete an arbitrary path read from settings.
- Pin Windows core versions/archive SHA-256 and CI action commits. Enforce
  the Pub lockfile and verify the pinned Inno Setup compiler.
- Whitelist packaged core runtime assets and license files, excluding upstream
  launcher scripts and arbitrary files left in core asset directories.
- Remove online font loading and external font-cache trust. Bundle the original
  Inter 400/500/600 files and their SIL license; both tests and packaging enforce
  their byte/hash pins, including when packaging an existing build.

## Remaining risks and trust boundaries

1. **Publisher compromise.** GitHub SHA-256 is integrity metadata supplied by
   the release service, not an independent signature. A compromised repository
   owner or publishing credential can publish malicious updates with valid
   hashes. No Authenticode signing is configured.
2. **Local user/admin compromise.** Credential Manager protects credentials at
   rest for the Windows user, not against malicious software running as that
   same user. Per-user executables, configurations and staged updates are
   writable by that user. Final rehashing narrows but does not eliminate the
   hash-to-execution race against a local attacker.
3. **Unauthenticated loopback IPC.** Limits reduce abuse, but a local process
   can still focus the window or pre-fill an import prompt. Port squatting may
   prevent normal single-instance startup or receive a forwarded deep link.
   The IPC must not be treated as authentication or an administrative API.
4. **Crash recovery and traffic leakage.** Proxy restoration covers normal
   cleanup and detected child exits, not abrupt application termination or
   power loss. A crash may leave a stale system proxy. No independently
   validated kill switch or DNS/traffic-leak guarantee is provided.
5. **Untrusted providers/data.** Subscription URLs and profiles can contain
   secrets and provider-controlled hosts/routing/TLS options. Fallback servers
   receive the subscription path/query. Plain HTTP data can be modified in
   transit; HTTPS/format validation does not make an untrusted provider safe.
   Geo/routing data authenticity is not independently signed.
6. **Native trust.** Official prebuilt core archives and signed SDK/compiler
   tools establish provenance relative to their publishers, not absence of
   vulnerabilities. Embedded Go libraries, media plugins and drivers require
   their own advisory/code review.
7. **Sensitive local data/logs.** Profiles and temporary core configs contain
   server credentials; logs may disclose hosts and traffic metadata. They use
   the current user's data directories, not an encrypted vault. Do not upload
   real profiles, logs or credential-bearing links to the repository.
8. **Upstream compatibility.** The fork retains `%AppData%\flux`, the URI
   scheme, IPC port and installer AppId for compatibility. Avoid running the
   original Flux and this fork concurrently against shared data/settings.
9. **Licensing unresolved.** The supplied tree has no top-level application
   license; GitHub's upstream metadata reported `license: null`. Clarify rights
   with the original author before distributing source/binaries. Core license
   files alone do not grant a license for the application.

## Remaining follow-up

- Keep the limits of the completed source/build/startup checks: zero TCP
  snapshots are not a packet trace or a live VPN/privacy certification. Do not
  use real profiles/connection controls on the user's machine for testing.
- Separately test upgrade to a genuinely newer release in a disposable user/VM;
  verify rollback/failure behavior, data preservation and restart without live
  Proxy/TUN testing on the user's machine.
- Test clean-machine Windows prerequisites and Windows N/KN separately; startup
  does not validate the inherited JNI/JVM asset.
- Revoke the PAT previously exposed in chat and create a separate expiring,
  repository-scoped **Contents: Read-only** updater token. Revocation of that
  exposed token has not been verified; do not reuse it.
- Resolve licensing; consider independent release signing and a durable,
  ownership-aware crash-recovery mechanism for proxy state.
