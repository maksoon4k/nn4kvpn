# Public source and publication review

Review date: **2026-11-23**. Intended repository: **maksoon4k/nn4kvpn**, numeric
GitHub repository identity **1468003190**. The maintainer requested public source
and token-free Windows downloads and confirmed the original author's permission.
See [attribution and license scope](../THIRD_PARTY_NOTICES.md).

## Reachable history

The pre-change history snapshot at
`aae390adad2a9268632231145a5a3f4c85d34837` contains **4 commits / 478 reachable
objects**: 361 blobs, 4 commit objects and 113 trees. All non-tree object bodies
were inspected with common token/private-key, cloud credential, credential-URL/
query/literal, JWT and proxy-URI heuristics. Binary objects received the high-risk
ASCII token/key checks. Trees were enumerated but not scanned as text. No history
was rewritten and the published `v1.4.3` tag/assets were not replaced.

The current 1.4.4 candidate scan including the full GPL text covered **362 files**: **314 text files** and
**48 binary files** checked with the high-risk heuristics. Its **21 findings**
are the same unchanged, individually reviewed locations below; no new high-risk
token/key findings were reported. External reports record file hashes without
secret-shaped match values; final committed-history verification remains a gate.

There were **21 findings**. Every finding was reviewed against its source object;
the table records locations/dispositions without repeating credential-shaped
values. All remaining matches are syntax examples or synthetic tests, not real
profiles, subscription credentials or tokens.

| Git blob | Path and line(s) | Findings | Reviewed disposition |
| --- | --- | ---: | --- |
| `7d0a8648a8e05e85ee2cd06e265b7b2bdec2acf7` | `ROADMAP.md:129` | 1 | Protocol/import syntax in development notes; placeholder grammar, not a live link. |
| `34b7b4427b9c24d0c4b18e4480621a36a24d5a30` | `docs/magic-json/magic_json.md:198` | 1 | Supported-protocol syntax, with placeholder parameters. |
| `778c46b1b195d0ca808e830e4bdb608a2597a413` | `lib/features/servers/hysteria2_link_parser.dart:19` | 1 | Parser documentation: password/host grammar, not credentials. |
| `9361c923bf91ee824572c69c0215d321a40403d3` | `lib/features/servers/vless_link_parser.dart:21` | 1 | Parser documentation: UUID/host grammar, not a profile. |
| `cc83fa6f0e58bcd1d45e93a3e42a5d35d86ee5b8` | `test/app/bounded_http_test.dart:229` | 1 | Deliberately rejected user-info URL with short placeholders and reserved `.test` host. |
| `e5ff59d961470473852ab387fed936edc3d7e400` | `test/app/deep_link_test.dart:7,8,9` | 3 | Synthetic deep-link payloads at reserved `.test` endpoints; no import/network authorization. |
| `3d96809998fbb2a5985d0ab326f89b97afb80c66` | `test/features/servers/base64_subscription_parser_test.dart:13,16,17,42,60,103,104` | 7 | Placeholder IDs and unsupported-link fixtures at example domains or RFC 5737 documentation IPs; certificate pin generated from repeated test characters. |
| `c64e79a3bc23ab4e5531438bb2c87d199f86a4e7` | `test/features/servers/hysteria2_link_parser_test.dart:7,23,33,40` | 4 | Fixed placeholder passwords, missing-password and wrong-scheme parser tests at example domains. |
| `ced4839f9ac9b02e52df5f682c9d2254c2afed88` | `test/features/servers/subscription_import_test.dart:92` | 1 | Synthetic example-domain profile in an HTTP mock for expiry-header overflow. |
| `e7e4f6e6302caa9baa9cdaa896c104585520bd62` | `test/features/updates/github_update_service_test.dart:119` | 1 | Deliberately unsafe redirect with short user/password placeholders; mocked response, never a real account. |

This heuristic review cannot prove the absence of arbitrary, encoded or unknown
secrets. It covers this repository's locally reachable history, not upstream
history that was never imported. The current candidate and final committed
history must be scanned again before publication; new findings require review.

## Public-facing materials

The authenticated **read-only** pre-visibility audit verified the repository's
identity, admin permission, one `main` branch and one `v1.4.3` tag at
`a6f1f80ac088d8d7250e98d8d67b2049553f90e6`. At that snapshot the only release was
stable `v1.4.3`, release ID **454794402**; its three asset sizes/digests matched
the historical exact CI verification. There were no issues or pull requests,
the wiki was disabled, and the repository description and release text had no
reported high-risk secret-heuristic matches.

The inherited desktop/mobile screenshots were visually reviewed: they contain
generic server labels and the public upstream subscription-site label, not
credential-bearing URLs, QR codes, account identifiers or server/profile secrets.
They are retained as historical upstream appearance examples, not current
Windows release test evidence. Source fonts/images and original notices remain
included; no generated user profile, SDK/tool cache or local build log is published.

## Release gate

- Review and commit only source/public documentation; preserve historical evidence.
- Build/test the exact commit on hosted Windows, including all Flutter tests,
  publishing guards, 15 offline DNS schemas and both isolated safe-start modes.
- Independently download and verify that CI run's packages, portable contents,
  native-file allowlist, version/publisher, original fonts and component notices.
- Only then change this exact repository to public, recheck name/ID/visibility,
  and use draft-first publication of those exact verified bytes. Never overwrite
  `v1.4.3` or resolve a conflict with `--clobber`.
- Verify metadata and downloads anonymously after publication. Application
  updates must not require a repository field, credential store or Authorization
  header. Installer execution and live Proxy/TUN tests are excluded from this gate.

The previously exposed PAT must be revoked at GitHub; revocation remains
unconfirmed. It is not embedded or reused for application updates. A passing
source/build/startup check is not an antivirus, backdoor-free or traffic-leak
certification; see the [qualified review](SECURITY_AUDIT.md).
