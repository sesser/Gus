# Third-party notices

## LightCraft

Some mask math follows LightCraft (https://github.com/storytold/lightcraft,
commit `07301cb`), licensed under the MIT License or the Apache License,
Version 2.0, at the user's option; it is used here under the MIT License.
Nothing was copied verbatim: the formulas were reimplemented in Swift. Each
place says so in a comment.

- The brush dab profile (1 inside the hard core, 1 − smoothstep beyond it)
  and dabs spaced a quarter of the radius apart:
  `Sources/PhotoCore/Edits/Masks/BrushRasterizer.swift`, from
  `crates/pipeline/src/masks.rs` (`dab_alpha`, `dab_spacing`).
- The color range's weighted OkLab distance √(Δa² + Δb² + ¼ΔL²) and the
  range of its tolerance (0.015 + 0.06 × tolerance / 100):
  `Sources/PhotoCore/Edits/Masks/MaskRenderer.swift`, from
  `crates/pipeline/src/masks.rs` (`shape_alpha`, `color_range_tolerance`).

```
MIT License

Copyright (c) 2026 ArtCraft Team and the LightCraft contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## darktable

The lens corrections a Fujifilm camera stores in its raw files (geometric
distortion, lateral chromatic aberration and vignetting tables) are read and
applied after darktable (https://github.com/darktable-org/darktable, `master`
as of 2026-11-13), which is free software under the GNU General Public
License, version 3 or (at your option) any later version; this project is
under the same license. Nothing was copied verbatim: the layout and the
formulas were written again in Swift and Metal. Each place says so in a
comment.

- Which values of the three tags are knots and which are values, in the two
  layouts cameras write (23, 31 and 23 values; 19, 29 and 19):
  `Sources/PhotoCore/Preview/FujifilmRAF.swift` (`LensTables`), from
  `src/common/exif.cc` ("Fuji lens correction data"). Where the tags are in a
  RAF file follows ExifTool's tag documentation (FujiFilm RAF and FujiIFD
  tags) and the file itself; no ExifTool code is used.
- The correction: tables linear between knots that are radii of the recorded
  image, the corrected radius as the recorded one over (1 + distortion / 100),
  red and blue taken from their own radii, each sample divided by
  vignetting / 100, and the picture scaled by the largest multiplier between
  the frame's short side and its corner:
  `Sources/PhotoCore/Preview/EmbeddedLensCorrection.swift` and the
  `embeddedLens` kernel in `Sources/PhotoCore/Edits/Kernels/LensKernels.swift`,
  from `src/iop/lens.cc` (`_init_coeffs_md_v2` and `_process_md`, the
  embedded-metadata correction "based on the algorithm developed by Freddie
  Witherden" in darktable pull request 7092). darktable resamples its spline
  at fixed knots; here the recorded radius is solved for exactly and kept in
  a lookup table.

Copyright (C) 2019-2026 darktable developers. The license's text is this
project's own `LICENSE`.

## LibRaw 0.22.3

Vendored in `Sources/CLibRaw` (the `src`, `internal` and `libraw` folders of the
release, from https://github.com/LibRaw/LibRaw, tag `0.22.3`). LibRaw is offered
under the GNU Lesser General Public License, version 2.1, or the Common
Development and Distribution License 1.0, at the user's option. It is used here
under the **LGPL 2.1** (`Sources/CLibRaw/LICENSE.LGPL`, upstream's file): this
project is under the GPL, version 3 or later, with which the Free Software
Foundation lists the LGPL 2.1 as compatible and the CDDL as not. Upstream's
`LICENSE.CDDL` stays beside it only because the release ships both; that
license is not the one taken. Copyright 2008-2025 LibRaw LLC, with portions by
Dave Coffin (dcraw) and others: see `Sources/CLibRaw/COPYRIGHT`.

- **Used for** raws the system's RAW decoder gives no image for (Fujifilm X-E3
  on macOS 27.2.1), and by `photobench rawcompare`:
  `Sources/PhotoCore/Preview/LibRawDecoder.swift` calls its C API,
  `PreviewGenerator.decode` falls back to it. The apps and `photocli` link it
  statically.
- **Modified files** (changed 2026-11-13): `internal/x3f_tools.h` and
  `internal/libraw_checked_buffer.h`, one `#include "../libraw/…"` line each,
  changed to `#include "libraw/…"` for SwiftPM's layout. Nothing else in the
  vendored tree is changed.
- **Changing LibRaw and building again.** LibRaw's complete source, as used, is
  in this repository and is compiled from it by `Package.swift` (the `CLibRaw`
  target); nothing is linked from a binary. To use a modified LibRaw, change
  the files under `Sources/CLibRaw` (or replace `src`, `internal` and
  `include/libraw` with those of another LibRaw release that has the same C
  API, and make the two `#include` changes above) and run `swift build` or
  `Scripts/build-app.sh`. The rest of
  the source is in the same repository under the GPL, so the whole program can
  be rebuilt with it.
- **Not built**: zlib, libjpeg, lcms, RawSpeed and the Adobe DNG SDK (so
  deflate-compressed and lossy DNGs are not decoded by it), and the GPL
  demosaic packs, which were never vendored. `src/*/…_ph.cpp` are upstream's
  placeholder stubs for builds without the real sources beside them, and
  `src/Makefile` is upstream's own build; both are excluded from the target
  (`Package.swift`). LibRaw is built thread-safe: `LIBRAW_NOTHREADS` is not
  defined.

https://www.libraw.org

## GRDB

GRDB.swift (https://github.com/groue/GRDB.swift) is this project's one package
dependency, declared in `Package.swift` and pinned by `Package.resolved`
(7.11.1 when this was written). It is the SQLite toolkit under the catalog
(`Sources/PhotoCore/Catalog`). SwiftPM compiles it from its source, unmodified,
and it is linked into the apps, `photocli` and `photobench`. It is used under
the MIT License; the text below is upstream's `LICENSE` file as it is.

```
Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

One file compiled into GRDB, `GRDB/Utils/Inflections+English.swift`, carries a
second MIT notice beside GRDB's own. It is reproduced here from that file's
header:

```
Copyright (c) 2005-2019 David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

Three of GRDB's files say that parts of them come from the Swift.org open
source project (copyright Apple Inc. and the Swift project authors), licensed
under the Apache License v2.0 with Runtime Library Exception
(https://swift.org/LICENSE.txt): `GRDB/Core/Cursor.swift` (2014 - 2018), and
the functions `_convertToSnakeCase` in `GRDB/Record/EncodableRecord.swift` and
`_convertFromSnakeCase` in `GRDB/Record/FetchableRecord.swift` (2014 - 2020).
That license's text is not reproduced in this file.

## ExifTool

ExifTool (https://exiftool.org, by Phil Harvey) is not part of the apps and is
not distributed with them; none of its code is in this repository. When it is
installed on the Mac it is run as a separate program to read metadata
(`Sources/PhotoCore/Metadata/ExifToolMetadataReader.swift`); without it,
metadata is read with ImageIO. ExifTool is free software under the same terms
as Perl itself (the Artistic License or the GNU General Public License), as
its page states. Its tag documentation was also read to find where a Fujifilm
raw keeps its lens tags (see darktable above).
