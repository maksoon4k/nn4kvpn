# Attribution and third-party notices

## Original application

NN4K is derived from **Flux** by [fllcker](https://github.com/fllcker),
original project: <https://github.com/fllcker/flux-vpn-client>.
The supplied upstream application has no top-level license and GitHub reports
no recognized license. The NN4K maintainer confirmed the original author's
permission to publish the modified source and Windows packages on 2026-11-23.
This notice does not invent an MIT/GPL license for the application or grant
additional rights to upstream code; third-party components retain their own terms.

## Bundled native cores

These are unmodified upstream binaries fetched from checksum-pinned archives.
NN4K communicates with them as separate child processes.

| Component | Version | License / full text in the Windows package | Corresponding source |
| --- | --- | --- | --- |
| Xray-core | v26.11.9 | MPL 2.0, `assets/xray/LICENSE` | [Tagged source](https://github.com/XTLS/Xray-core/tree/v26.11.9), [source archive](https://github.com/XTLS/Xray-core/archive/refs/tags/v26.11.9.tar.gz) |
| sing-box | v1.14.4 | GPL v3 or later: original `assets/sing-box/LICENSE`, full terms `licenses/GPL-3.0.txt` | [Tagged source](https://github.com/SagerNet/sing-box/tree/v1.14.4), [source archive](https://github.com/SagerNet/sing-box/archive/refs/tags/v1.14.4.tar.gz) |
| Wintun prebuilt DLL bundled with Xray | Upstream Xray archive pin | Wintun Prebuilt Binaries License, `assets/xray/LICENSE-Wintun` | <https://www.wintun.net/> |

Each core's `SOURCE.md` identifies its download instructions and source repository;
build recipes are in the corresponding tagged upstream source.
Archive hashes and versions are in `scripts/core_versions.env` in the published
source. When changing a core version, update this notice and its source links.
Do not distribute the Wintun DLL separately from the application that uses its API,
remove proprietary notices or imply endorsement by its authors.

The complete GPL v3 text was copied from the
[SPDX license-list data](https://github.com/spdx/license-list-data/blob/main/text/GPL-3.0-or-later.txt)
on 2026-11-23. It accompanies the sing-box component and does not assign a
GPL license to unrelated NN4K application code. The original sing-box copyright,
warranty and no-implied-association notice is retained unchanged.
The copied full text was checked against the SPDX response (UTF-8 SHA-256
`fb981668c18a279e285fc4d83fba1e836cc84dd4daa73c9697d3cfd2d8aca6e0`;
line endings may be normalized by Git checkout).

## Flutter and Dart packages

The Windows package includes Flutter's generated dependency notices in
`data/flutter_assets/NOTICES.Z` (zlib-compressed text). These contain copyright
and license texts collected from the Flutter SDK and resolved Pub packages.
The exact package versions are recorded in `pubspec.lock` in the source tree.
No dependency notice is replaced by this summary.

## Inter fonts

Original Inter Regular, Medium and SemiBold files are distributed under
the **SIL Open Font License 1.1**. Full copyright/license text and provenance:
`data/flutter_assets/assets/fonts/OFL.txt` and `SOURCE.md` in Windows packages,
or `assets/fonts/` in the source. The original byte/hash pins are retained.

## Globe texture

The land/ocean mask comes from [cobe](https://github.com/shuding/cobe) by Shu Ding.
Its original notice is included in `assets/globe/NOTICE.md` in Windows packages
and in the source tree:

> MIT License
>
> Copyright (c) 2022 Shu Ding
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.

## Playful tools

The six tools are local NN4K UI demos. The DOOM, Minecraft and video-service
parodies do not bundle those products' game code, media or assets and do not
imply affiliation or endorsement by their owners.
