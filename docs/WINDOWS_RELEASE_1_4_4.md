# Public Windows release 1.4.4 — verified publication

Date: **2026-11-23**. [NN4K source](https://github.com/maksoon4k/nn4kvpn) is public
and [v1.4.4](https://github.com/maksoon4k/nn4kvpn/releases/tag/v1.4.4) is the stable
latest release. Repository ID: **1468003190**; release ID: **455099291**.

The tag and published packages identify the exact tested build source
`5251b25584ad1733bf4734d22aa040c576b7976a`, from
[Windows Checks 45127094577](https://github.com/maksoon4k/nn4kvpn/actions/runs/45127094577).
They were not replaced by a second build. Later documentation commits do not
change this tag or its installer/portable bytes.

## Using the release

- Download the Windows x64 installer or portable ZIP from the release above.
  The installer remains per-user and preserves existing `%AppData%\flux` data.
- In the application, open **Settings → About → Updates → Check for updates**
  (**Настройки → О программе → Обновления → Проверить обновления**).
  No account, GitHub setup or updater token is needed. The publisher is pinned
  in the executable; imported settings cannot redirect executable updates.
- Automatic installation remains **opt-in**, deferred while VPN is active,
  cancellation/consent-rechecked, and unavailable from an elevated application.
  An actual upgrade, installer launch and restart were not tested in this review.
- The bottom-right menu and all six tools have repaired clickable and keyboard
  controls, small-window scrolling and dismissal. The flashlight, cassette
  recorder, DOOM, calculator, block world and video tool remain local playful
  demos, not microphone recording, external games or online video playback.
- **Settings → Ping → Diagnostics** compares the exact seven
  [DNS pairs](DNS_DIAGNOSTICS.md), with consent and VPN stopped. It makes 126
  sequential example-domain measurements and saves a reliable primary/backup
  pair. Both addresses need at least 2/3 usable certificate-verified DoT answers;
  ICMP is informational. Cancellation, storage failure, manual DNS changes or VPN
  activation must not overwrite previous/newer DNS or unrelated settings.
  Live resolver reachability was not exercised during release validation.

Appearance preferences and the original first-run/onboarding flow are preserved.

## Exact validation

| Gate | Result |
| --- | --- |
| Hosted Flutter suite | **383 tests passed** with locked dependencies. |
| Analyzer | **0 errors, 0 warnings**, 11 informational lints. |
| Offline publication guards | **23 passed**; public numeric repository identity, draft-first verification and no overwrite. |
| Offline DNS schemas | **15 passed**: both orientations of all seven pairs plus the legacy default; only `sing-box check`, never `run`. |
| CI portable | **318 files / 154818746 bytes**, every ZIP entry size/SHA-256 matched; native allowlist, original font/core pins and notices checked. |
| Runtime containers | **11 AMD64 PE images** and the Dart **ELF64 little-endian AMD64 AOT snapshot**, read without executing the images. |
| Strict startup | Main-screen and first-run modes passed independently on hosted Windows and on the exact downloaded CI portable locally. |
| Anonymous release access | Exact public repository/tag/latest metadata and all three asset API downloads verified without Authorization, cookies or saved GitHub authentication. |
| Production-controller replay | Fresh Flutter compilation of the current controller/service accepted actual public metadata and independently downloaded installer bytes through an offline HTTP mock. |

All four isolated `--safe-start` runs opened their window and exited gracefully
with code **0**, with no forced termination or observed core children, unchanged
proxy/URI state, and two available zero-count OS TCP snapshots per mode. Retained
stdout/stderr contained only the usual native video-plugin shutdown and Impeller
renderer messages. No real application profile/settings, connection controls or
installer were used. These observations are **not** a packet capture, sandbox,
live VPN test or leak-safety certification.

The replay deliberately left the production publisher provider unmodified and
mocked network, settings storage, connection and installer dependencies. It
checked that imported legacy settings cannot redirect updates, automatic install
remains opt-in, unrelated appearance/onboarding survives, only a newer version is
offered, final size/hash checking succeeds, same-size tampering is rejected, and
only the owned staged copy is removed. The original installer and unrelated
fixture file were preserved. This is not an end-to-end installation/restart test.

## Published asset identities

| Asset | GitHub asset ID | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| `NN4KSetup-1.4.4.exe` | 781959024 | 41709284 | `62c2d266f0522642e0a4e7bc26768e7c24f8eeef4fbc88a8ba7ebbee91736430` |
| `NN4K-1.4.4-windows-portable.zip` | 781960391 | 58625484 | `b0919c085de4d9094a8f37b61f8c1a52fb111a9f7054bc991786f2fd4c39e48e` |
| `checksums.txt` | 781963188 | 186 | `eae6e61cac5c6a5f3f6ff4b0658ee7d0655d96baa4a335800d2cd4d1780ae9aa` |

All separately downloaded public bytes matched the exact successfully tested CI
assets and GitHub's uploaded size/digest metadata. An interrupted public full-file
transport was checked again using strictly sequential, certificate-verified 8 MiB
HTTPS byte ranges; full-file size/hash matching remained mandatory. This
verification-only method did not change the application's download behavior.
Both packages contain original application/globe attribution, pinned core source
notices, complete GPL terms,
original MPL/Wintun notices, Inter's SIL license and Flutter dependency notices.
See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

The existing **v1.4.3** release ID **454794402**, its original tag and all three
asset identities/sizes/digests remain unchanged. Its
[historical validation JSON](windows-release-validation.json) is preserved,
not relabeled as 1.4.4 evidence. The separate current record is
[windows-release-validation-1.4.4.json](windows-release-validation-1.4.4.json).

## Publication review and corrections

- Immediately before public visibility, the finalized candidate scan covered
  **362 files: 314 text / 48 binary**. The exact committed history contained
  **6 commits / 558 reachable objects**. All **21 findings** were the same
  individually reviewed synthetic/parser examples and locations documented in
  [PUBLICATION_REVIEW.md](PUBLICATION_REVIEW.md); no new high-risk findings were
  reported. Five retained completed Actions runs and public-facing repository
  materials were also inspected. Heuristic scans cannot rule out arbitrary,
  encoded or unknown secrets.
- The first 1.4.4 CI run,
  [45125691400](https://github.com/maksoon4k/nn4kvpn/actions/runs/45125691400),
  failed because Windows test teardown raced asynchronous cancellation cleanup.
  The follow-up changed **tests only** to observe/await those exact futures and
  assert discarded files are removed. No sleeps, skipped assertions, retries or
  production behavior changes were used to pass the test. Packaging/publication
  did not run on the failed source; the later successful exact run supplied all
  published bytes. An interrupted CI artifact download was resumed from that same
  completed run without rerunning tests or rebuilding packages.
- An initial Windows PowerShell 5 release-text encoding problem was corrected
  from the pinned UTF-8 Git source template. Inspected Windows prerequisites and
  exact CI identity were appended. **Only v1.4.4's description was edited**;
  binaries, asset identities, tag/latest and v1.4.3 were not changed.
- The maintainer confirmed the original author's permission for public modified
  source/Windows distribution. This is not a blanket upstream application license;
  required attribution/component licenses remain included.

## Prerequisites and limits

The installer is **unsigned** and Windows may show an unknown-publisher or
SmartScreen warning. Hashes establish matching bytes, not publisher trust,
antivirus safety or absence of backdoors.

The CI runner/plugins require an unbundled compatible **Microsoft Visual C++ v14
x64 Redistributable**, at least as recent as the build toolset; use
[Microsoft's official guidance](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist),
not DLL-download sites. Windows **N/KN** editions need the appropriate **Media
Feature Pack**. Installing system prerequisites may need admin rights even though
NN4K's own installer remains per-user. The inherited JNI asset imports external
`jvm.dll`; the reviewed Windows connection path does not use JNI.

Static direct/delay native import sets match the previously inspected runtime.
Dynamic imports, clean-machine/Windows N compatibility, JNI/JVM functionality,
actual installer execution/upgrading and live Proxy/TUN/privacy behavior remain
untested. Native/embedded components were not exhaustively audited or rebuilt.
Inherited Android/macOS paths are outside this Windows release.

The previously exposed GitHub PAT must be revoked; revocation remains
**unconfirmed**. It is not embedded in the application or used for public updater
requests. See [security qualifications](SECURITY_AUDIT.md) and
[update behavior](WINDOWS_UPDATES.md).
