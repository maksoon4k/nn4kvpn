# Windows updates

## Configure a private repository

1. Open **Settings → About → Updates** (Russian: **Настройки → О программе →
   Обновления**).
2. The distributed build is configured for `maksoon4k/nn4kvpn`. If necessary,
   set that slug or `https://github.com/maksoon4k/nn4kvpn` in the repository
   field. For your own different fork, use its exact private repository instead.
   Do not use the upstream Flux repository.
3. For private releases, create a **fine-grained personal access token** in
   your own GitHub account. Restrict it to this one repository and
   **Contents: Read-only**; grant no write or administration permissions.
   Use an expiry and revoke/replace it if it is exposed. The account must
   already have access to the private repository.
4. Enter the token in the application's masked field and save. Never send a
   token in chat, put it in source, a build argument, `.env`, or release notes.
5. Click **Check**, then **Download / Install**. The app performs these actions
   itself; a browser is not used to download the installer.

GitHub CLI login is for the maintainer's repository/release publishing. It is
separate from the read-only credential used by the application. CI uses its
short-lived `github.token`; neither publishing credentials nor read tokens are
embedded in release binaries.

Tokens are stored per normalized repository in the current user's **Windows
Credential Manager**, under `NN4K/GitHubUpdates/owner/repository`. Only the
repository and preferences are written to `settings.json`. A blank token field
preserves the stored token; the explicit remove action deletes the credential
for the selected repository. Changing repository does not silently copy its
credential to another publisher.

## Automatic behavior and installation

- Background checks start approximately 10 seconds after launch and repeat
  every six hours when update checking or automatic installation is enabled.
- Automatic download and installation are **off by default**. The startup
  checking option alone never authorizes executable downloads/installation.
- With automatic installation enabled, downloads can occur while connected,
  but installation waits for an idle VPN. It will not disconnect an active
  VPN automatically. Changing repository requires fresh auto-install consent.
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
redirects, and an exact allowlist of GitHub/CDN hosts. The read token is sent
only to `api.github.com` and is permanently removed when redirecting to a
different origin. Errors never display private HTTP bodies or signed URLs.
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

1. Resolve upstream/application licensing before distribution. Review changes,
   inspect the source for secrets and keep the repository **private**.
2. Bump `pubspec.yaml` to a new stable three-part version and build number.
   Keep `pubspec.lock` checked in; use `flutter pub get --enforce-lockfile`.
3. Run the Windows checks and build with
   `--dart-define=NN4K_UPDATE_REPOSITORY=maksoon4k/nn4kvpn`. For a different
   fork, substitute its exact repository. Do not pass tokens.
4. Package the installer and portable ZIP; retain `checksums.txt`. Do an
   isolated `--safe-start` smoke check without live Proxy/TUN testing.
5. Use the Windows Release workflow, or the publishing script:

   ```powershell
   ./scripts/publish_windows_release.ps1 `
      -Repository maksoon4k/nn4kvpn -Version 1.4.3 `
     -ArtifactDirectory ./build/installer -TargetCommit <commit-sha>
   ```

The script uploads into a **draft**, verifies the size and GitHub SHA-256 for
all three assets, then publishes it as latest. Failed verification leaves the
draft unpublished. It refuses to overwrite an already published version;
retries skip identical draft assets and reject conflicting assets without
replacing them. The script also checks the target repository is private,
checks local checksum records and requires the exact target commit SHA.
It resolves the draft's numeric release ID and reads assets by that pinned ID;
an unpublished draft need not be accessible through GitHub's tag endpoint.

Do not race manual publication against the automatic Windows Release workflow.
For the initial locally verified upload, the bootstrap commit uses `[skip ci]`
to avoid a simultaneous version-push release. The manual **Windows Checks**
workflow can still be dispatched with `build_windows=true` to analyze, test and
build the exact commit without publishing. Subsequent normal version commits
use the automatic release workflow; never use `--clobber` to resolve a conflict.

Only the publishing CI job has `contents: write`. Workflow actions are pinned
to commit SHAs. No Android/macOS release jobs run in this fork.

## Troubleshooting

| Message/symptom | Check |
| --- | --- |
| Repository not configured | Set the exact repository in the application or use the build-time define. |
| No release / HTTP 404 | GitHub also conceals inaccessible private repositories as 404. Check account access, token repository selection, expiry and whether a stable release was published. |
| Access denied | Renew/restrict the token; check any required organization approval. |
| Missing installer/checksum | Verify the exact asset name, uploaded state and GitHub `digest` metadata. |
| Hash/size mismatch | Do not run the file manually. Re-download only after investigating the release; never bypass validation. |
| Elevated application | Stop the app and restart without administrator privileges. |
| Automatic update remains ready | Disconnect manually, or leave it pending until VPN is idle. |
| Same version not offered | Bump the semantic version; changing only `+buildNumber` is insufficient. |

The initial version cannot prove end-to-end automatic upgrading from itself to
itself: that requires a later, genuinely newer release and a separate isolated
installation test. Unit/widget tests use mocked installers and do not replace
a live application installation.
