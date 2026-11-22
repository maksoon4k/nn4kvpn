# Bundled Inter fonts

These unmodified TrueType files are the **same bytes** previously requested by
the UI through `google_fonts` **8.2.0**. Their size/SHA-256 pins were taken from
that locked package's `lib/src/google_fonts_parts/part_i.dart` Inter descriptors
and verified before including the files. They are now loaded by Flutter's local
font manifest; no Google Fonts client, runtime download or external font cache
is needed. The original 400/500/600 weights and text-style metrics are retained.

Source URL for each file is `https://fonts.gstatic.com/s/a/<sha256>.ttf`:

| File | Weight | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| `Inter-Regular.ttf` | 400 | 324796 | `15b294b67f2f8bbc04d990023ef4aec66502b87dc9040d84abe5f896ccb693de` |
| `Inter-Medium.ttf` | 500 | 325280 | `36a36ff7ac46dc2aeceac3a80a87a67e7b844b8fc936699259aac8fba9bcf734` |
| `Inter-SemiBold.ttf` | 600 | 326024 | `334bb2c51aeba5f566abac8d03a7e75ab3234d6926b52e92a85dc704129258b5` |

Copyright 2020 The Inter Project Authors (https://github.com/rsms/inter).
License: **SIL Open Font License 1.1**, included in [OFL.txt](OFL.txt).
The license was obtained from `google/fonts`, `ofl/inter/OFL.txt`, on 2026-11-23.
The font license does not resolve the application's separate licensing question.

The Flutter tests and Windows packaging checks verify the bundled font hashes.
Matching hashes establish file identity, not an exhaustive font/parser audit.
