# NN4K 1.4.4 — Windows

- Public, token-free Windows updates. Removed “Configure GitHub”, repository/
  credential fields and update-source identity from the application interface.
  The executable publisher is pinned at build time; imported settings cannot
  redirect updates. Automatic installation remains opt-in and idle-VPN-only.
- Fixed physical hit-testing in the bottom-right tools menu and all six demos:
  flashlight toggle/color/scan/sliders, recorder cassette/time/rewind, DOOM shots/
  medkits/waves, calculator decimal arithmetic and Mbps-to-MB/s, a block world with
  materials/day/night, and a local video parody with pause/seek/likes/clip selection.
  Mouse, keyboard, dismissal and small-window scrolling are supported. No real
  microphone recording, online video or external game process is introduced.
- Added Diagnostics under Ping with confirmation, sequential checks of the exact
  seven DNS pairs, per-address results and automatic persistent primary/backup
  selection based on valid encrypted DoT answers. Cancellation or failure does
  not overwrite previous/newer DNS settings; appearance/onboarding is preserved.
- Propagated a validated same-provider encrypted backup into the Windows TUN
  mapper, with explicit TLS identities and bounded failover. ICMP/UDP success
  alone cannot choose a resolver for encrypted TUN DNS.
- Public release publication still uses exact successfully tested CI artifacts,
  draft-first identity/size/SHA-256 checks, pinned repository ID and no replacement
  of published versions. Original/component attribution and licenses are included
  in both Windows packages. The old v1.4.3 files are not changed.

Published exact CI packages and anonymous download/controller verification are
recorded in the [qualified 1.4.4 release record](../WINDOWS_RELEASE_1_4_4.md).
See [DNS behavior and limits](../DNS_DIAGNOSTICS.md),
[updates](../WINDOWS_UPDATES.md), and the [qualified review](../SECURITY_AUDIT.md).
The installer remains per-user and unsigned. Live Proxy/TUN behavior,
clean-machine/Windows N compatibility and end-to-end upgrading are not certified.
