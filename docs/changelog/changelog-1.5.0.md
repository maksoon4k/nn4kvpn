# NN4K 1.5.0 — Windows

- YouTube now opens the real site in the system browser instead of the offline
  parody. Home, search queries, `youtube.com`, `youtu.be` and `music.youtube.com`
  links are validated and opened over HTTPS; no embedded webview, token or
  downloaded player is introduced.
- Fixed the recorder playing no sound at all. The cassette now renders its own
  deterministic PCM loops (or plays a user-picked local audio file), with
  play/pause, rewind and volume. Microphone recording is still not implemented.
- Added a bounded first-person 3D voxel sandbox: procedural terrain, exposed-face
  meshing, collision, block placing/breaking, materials and day/night lighting.
  It is an original Flutter renderer — no bundled engine, download or external
  game process.
- Added Minesweeper with mouse and keyboard input. Losing safely reveals the
  board and offers to close NN4K through the normal shutdown path; it never
  crashes the application or changes the VPN connection on its own.
- Added targeted pings: right-click a server for “Ping” and use the button beside
  a folder name to ping that group. Each request is scoped to its server or
  folder, later requests invalidate stale replies, and results/errors are shown
  in place without touching other rows.
- Fixed newly imported backgrounds sometimes never replacing the previous one.
  Every import now uses an immutable UUID file name, the settings save switches
  atomically, and the retired copy is deleted only after the new selection is
  persisted.
- Added persistent per-application TUN routing. Rules can be `direct`, `proxy`
  or `block`, with whitelist/blacklist defaults, a running-process picker,
  manual executable entries and a JSON editor. Exact paths take precedence over
  file names; generated sing-box rules are anchored, escaped, case-insensitive
  `process_path_regex` values. Invalid rules are rejected before saving.
- Release validation now includes offline application-routing schema checks
  against pinned sing-box, alongside the existing DNS schema and publishing
  guard tests. Core downloads remain checksum-pinned.
