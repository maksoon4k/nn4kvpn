# Windows updates

## Public updates — no setup or token

1. Open **Settings → About → Updates** (Russian: **Настройки → О программе →
   Обновления**).
2. Click **Check**, then **Download / Install**. The app performs these actions
   itself; a browser is not used to download the installer.
3. Optionally enable automatic installation. It is off by default and waits
   until VPN is idle; checking for updates alone is not installation consent.

GitHub CLI login is for the maintainer's repository/release publishing. It is
not required by the application. CI uses its short-lived `github.token` for
publication; no publishing credential is embedded in the executable.

The publisher is compiled into the executable: this distribution uses
`maksoon4k/nn4kvpn`, never the upstream application repository. There is no
repository/token configuration UI, and the source identity and technical release
body are not shown in the application. Imported/legacy repository and token
fields cannot redirect executable downloads. All production-controller metadata
and installer requests are **anonymous**, including redirects.

Earlier versions could save a token in Windows Credential Manager under
`NN4K/GitHubUpdates/owner/repository`. Version 1.4.4 does not read, copy or use
that credential; it also does not delete an existing credential without a user
request. Remove obsolete entries through Windows Credential Manager if desired,
and revoke any exposed token at GitHub. Do not send tokens in chat or commit them.

## Automatic behavior and installation

- Background checks start approximately 10 seconds after launch and repeat
  every six hours when update checking or automatic installation is enabled.
- Automatic download and installation are **off by default**. The startup
  checking option alone never authorizes executable downloads/installation.
- With automatic installation enabled, downloads can occur while connected,
  but installation waits for an idle VPN. It will not disconnect an active
  VPN automatically. Consent is bound to the build's pinned publisher through
  `autoInstallUpdateOrigin`. Legacy consent is preserved only if its previous
  publisher matches; otherwise automatic installation is disabled until re-enabled.
- A manual installation first validates the installer, then stops the app's
  engines and restores the proxy values owned by the current connection.
- The installer waits up to two minutes for the calling PID to exit, updates
  the current executable directory, and restarts the application.
- Settings, subscriptions, servers and other data in `%AppData%\flux` are
  preserved. The default new installation directory is `%LocalAppData%\NN4K`.
  Portable users are updated in their current directory, not moved elsewhere.
- An app running with administrator/TUN privileges **cannot launch updates**.
  Stop it and restart normally before installing. The per-user installer must
  not inherit elevated privileges.
- `--safe-start` disables the startup scheduler. It is for an isolated UI smoke
  check, not a sandbox: manual UI actions remain available.

Completed downloads are staged in uniquely named subdirectories below
`%LocalAppData%\NN4K\updates`. A canceled or invalid download is never launched;
cleanup failure can leave an inert file on disk. Normal application data and
downloads use the current user's Windows directories, so ensure adequate
space there. The development build instructions redirect temporary files and
caches to D: separately.

## Accepted release format

The updater calls GitHub's `/repos/OWNER/REPOSITORY/releases/latest` API and
accepts only a published, non-prerelease stable semantic version newer than
the running version. A tag must be `v<major>.<minor>.<patch>` or the equivalent
without `v`. The `+buildNumber` in `pubspec.yaml` is not a new updater version:
bump the three-part version when releasing changed binaries.

The release must contain exactly one asset named:

```text
NN4KSetup-<major>.<minor>.<patch>.exe
```

The asset must be fully uploaded, have a positive ID, a size no larger than
512 MiB, and GitHub metadata containing `digest: sha256:<64 hex characters>`.
The updater does not execute the portable ZIP or download from arbitrary
`browser_download_url` values, release-note links or `checksums.txt` URLs.

Downloads use the constructed GitHub asset API URL, HTTPS only, at most five
redirects, and an exact allowlist of GitHub/CDN hosts. The production controller
does not send an Authorization header or read a credential store. Errors never
display HTTP response bodies or signed URLs.
The file must match the release size and SHA-256 and begin with an executable
`MZ` header. Size/digest are checked again immediately before launch; cached
files are invalidated if their repository or asset identity/metadata changes.
Cancellation, current repository and automatic-install consent are rechecked
at the final launch boundary.

This establishes integrity relative to GitHub's metadata, **not independent
publisher authenticity**. The repository owner and GitHub account are trusted
executable publishers. A compromised publisher can distribute a malicious
file with a matching hash. Authenticode signing is not currently configured,
and same-user malware is outside the local-file trust boundary.

## Publish the next Windows release

1. Confirm redistribution rights and retain required third-party attribution.
   For this distribution the maintainer confirmed the original author's
   permission. Review the full reachable Git history, current source and public
   publication materials for secrets before changing visibility.
2. Bump `pubspec.yaml` to a new stable three-part version and build number.
   Keep `pubspec.lock` checked in; use `flutter pub get --enforce-lockfile`.
3. Run the Windows checks and build with
   `--dart-define=NN4K_UPDATE_REPOSITORY=maksoon4k/nn4kvpn`. For a different
   fork, substitute its exact repository. Do not pass tokens.
4. Package the installer and portable ZIP; retain `checksums.txt`. Run both
   strict isolated `--safe-start` modes without live Proxy/TUN testing. Publish
   the exact tested bytes, not an unchecked rebuild of the same commit.
5. Use the Windows Release workflow, or the publishing script:

   ```powershell
   ./scripts/publish_windows_release.ps1 `
     -Repository maksoon4k/nn4kvpn -ExpectedRepositoryId 1468003190 `
     -Version <new-three-part-version> `
     -ArtifactDirectory <exact-tested-CI-artifact-directory> `
     -TargetCommit <exact-tested-commit-sha>
   ```

The script uploads into a **draft**, verifies the size and GitHub SHA-256 for
all three assets, then publishes it as latest. Failed verification leaves the
draft unpublished. It refuses to overwrite an already published version;
retries skip identical draft assets and reject conflicting assets without
replacing them. The script requires the target repository to be **public**,
pins its expected numeric identity, checks local checksum records and requires
the exact target commit SHA. It rechecks visibility/name/identity before publication.
It resolves the draft's numeric release ID and reads assets by that pinned ID;
an unpublished draft need not be accessible through GitHub's tag endpoint.

Do not race manual publication against the automatic Windows Release workflow.
For preparation while the repository is private, the release workflow builds
and tests but skips its publishing job; the publishing script independently
rejects private visibility. The manual **Windows Checks**
workflow can still be dispatched with `build_windows=true` to analyze, test and
build the exact commit without publishing. After reviewing those exact artifacts,
make the intended repository public and publish only those bytes. Subsequent
normal version commits in the public repository use the automatic release
workflow; never use `--clobber` to resolve a conflict.

Only the publishing CI job has `contents: write`. Workflow actions are pinned
to commit SHAs. No Android/macOS release jobs run in this fork.

## Initial release validation — 2026-11-23

[v1.4.3](https://github.com/maksoon4k/nn4kvpn/releases/tag/v1.4.3) is a published
stable release in the repository that was private at the time of initial
publication, release ID **454794402**. This historical release is not replaced.
Its tag targets the exact tested build source
`a6f1f80ac088d8d7250e98d8d67b2049553f90e6`.
[Windows Checks](https://github.com/maksoon4k/nn4kvpn/actions/runs/45081917123)
passed analysis, **323 Flutter tests**, **17 publishing guards**, packaging and
both strict startup modes. The exact CI installer/portable bytes were published;
the same extracted portable also passed both isolated modes locally.

All three published assets were separately downloaded to D: and rehashed
against both the original CI files and GitHub metadata. Every one of the
portable archive's **315 files** matched the verified CI runtime. The installer
asset ID is **780857529**, size **41665634 bytes**; complete hashes and identities
are retained in [windows-release-validation.json](windows-release-validation.json)
and the [security review](SECURITY_AUDIT.md).

A limited replay used the actual published metadata and separately downloaded
installer through the **production updater code with a mock HTTP client**:

- Current `1.4.2` was offered `1.4.3`; `1.4.3+8` and `1.4.4` were not offered
  that release, preserving newer-only/no-downgrade behavior.
- Streaming and final size/SHA-256 validation passed. A changed middle byte in
  an owned staged copy, with the original size/header retained, was rejected.
- The staged test copy was removed and the original downloaded installer
  remained unchanged.

This did **not** use an application token, contact the network through the
updater, launch the installer or exercise Proxy/TUN. It is not a live private
credential/redirect test or an end-to-end upgrade/restart test. Installing this
same version cannot prove upgrading to a genuinely newer release.

Initial publication also recovered only the maintainer's pinned, still-empty
unpublished draft after a target-only REST PATCH caused GitHub to substitute an
`untagged-…` name. Recovery explicitly sent both `tag_name=v1.4.3` and the tested
`target_commitish`, after rechecking author/repository identity and absence of
assets/tags. No Git tag was deleted/replaced and no published binary was changed;
this is not an exception to the publisher's version/target safeguards.

The installer is unsigned. The CI runtime requires an unbundled compatible
Visual C++ v14 x64 Redistributable; Windows N/KN also needs Media Feature Pack.
See [Windows prerequisites](WINDOWS_BUILD.md#package-and-inspect). The initial
licensing question was subsequently answered by the maintainer's permission
confirmation; see [attribution](../THIRD_PARTY_NOTICES.md). Clean-machine
compatibility and live VPN/privacy behavior remain qualified.

## Troubleshooting

| Message/symptom | Check |
| --- | --- |
| No release / HTTP 404 | Check network access and that a stable release exists in the build's public publisher. An old custom-fork build may need replacement by the intended Windows installer. |
| Access denied / rate limit | Anonymous GitHub requests can be rate-limited. Wait and retry; do not enter a token or disable verification. |
| Missing installer/checksum | Verify the exact asset name, uploaded state and GitHub `digest` metadata. |
| Hash/size mismatch | Do not run the file manually. Re-download only after investigating the release; never bypass validation. |
| Elevated application | Stop the app and restart without administrator privileges. |
| Missing MSVCP140/VCRUNTIME140 DLL | Install a compatible Microsoft Visual C++ v14 x64 Redistributable from Microsoft's official guidance; never fetch individual DLLs from third-party sites. |
| Missing MFPlat.dll on Windows N/KN | Install the appropriate Media Feature Pack; clean-machine compatibility has not been validated. |
| Automatic update remains ready | Disconnect manually, or leave it pending until VPN is idle. |
| Same version not offered | Bump the semantic version; changing only `+buildNumber` is insufficient. |

The initial version cannot prove end-to-end automatic upgrading from itself to
itself: that requires a later, genuinely newer release and a separate isolated
installation test. Unit/widget tests use mocked installers and do not replace
a live application installation.
