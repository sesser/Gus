# RAF not rendering: implementation status

Issue: #161. Bug fix, branch `bug/raf-not-rendering`, cut from `develop` at `ef592d9`.

**Status: In progress.** Owner's ruling (2026-11-13): LibRaw only where the
system decoder gives no image, so nothing gets slower. `PreviewGenerator.decode`
now falls back to it (`decodeWithLibRaw`): half-size decode when the target is at
most half the frame, scale from the frame's size, `isRaw` false (the stack's
RAW decode settings do not apply to it; the look is flat and darker than the
system's, no baseline exposure or tone). The camera's inset crop is applied
(5998x3997 on the X-E3). Test: `LibRawFallbackTests` (needs `RAF_SAMPLE`, fails
without the fallback). Not done: the look, decode settings, the HDR DNG, other
cameras (the owner's X-T3 files open with the system decoder; an X100S/T
untested), code review, QA, sign-off.

## Bug

**Steps to reproduce** (macOS 27.2.1). `swift run photocli render
/Volumes/photos/2019/2019-01/2019-01-12/DSCF5159.RAF --out o.png`, or open any
RAF of that folder in the loupe. **Expected:** it renders. **Actual:**
`undecodable`; black loupe, grey film strip tiles.

**Root cause.** Not the network volume or #160: all 16 X-E3 RAFs tried fail on a
local copy too. On this macOS `CIRAWFilter` has `nativeSize` 0x0 and no output,
and ImageIO cannot decode them. (A 2020 RAF, `DSCF4583.RAF`, decodes with the
system decoder.)

**Owner's rulings (2026-11-13).** No embedded preview in place of a render; a
preview placeholder in the grid is its own feature (#168, Later). Explore a
third-party decoder: LibRaw, vendored, under CDDL; possibly for all raws if
performance is close; compare its output with the system decoder's.

## Spike

`Sources/CLibRaw` (LibRaw 0.22.3, vendored; `THIRD_PARTY_NOTICES.md`),
`PhotoCore/Preview/LibRawDecoder.swift` (linear Rec. 2020, camera white balance,
no auto brightness, no tone curve, 16 bit; no stack decode settings) and
`photobench rawcompare --files a.RAF:b.RW2 [--output DIR] [--runs N]`.

Decode plus render to 8-bit sRGB, best of 2, local copies. The system numbers
look too fast for 20+ MP and need a second measure before they decide anything.

| File | System | LibRaw full | LibRaw half |
| --- | --- | --- | --- |
| Sony ARW 24 MP | 0.05 s | 1.13 s | 0.13 s |
| Fujifilm RAF 2020 (26 MP, compressed) | 0.04 s | 9.16 s | 0.61 s |
| Fujifilm RAF X-E3 (24 MP) | no image | 8.60 s | 0.58 s |
| Canon CR2 | 0.05 s | 1.23 s | 0.26 s |
| Olympus ORF | 0.08 s | 1.28 s | 0.41 s |
| Panasonic RW2 | 0.02 s | 1.08 s | 0.16 s |
| Panasonic HDR DNG | 0.03 s | unsupported | n/a |

- The X-E3 RAF decodes correctly (checked by eye).
- Look: LibRaw is flat, 18 to 40 mean-luma levels darker and less saturated
  (Apple adds baseline exposure and a tone curve). Mean absolute difference 22 to
  39 of 255, tone not matched.
- LibRaw's frame is a little larger than the system's (6032x4028 against
  6000x4000 on the X-E3): it keeps masked border pixels. Its crop needs setting.
- The HDR DNG failed ("Unsupported file format"): probably needs zlib or JPEG
  support, which this build leaves off.
- Single-threaded CPU against the system's GPU path; Fuji compressed full
  decodes take about 9 s.

## Open (the owner's call)

LibRaw only for files the system rejects, or for all raws; matching the system's
look (baseline exposure, tone) if all; decode settings (exposure, white balance,
highlights, noise reduction) on the LibRaw path; the crop; speed (half size for
small targets, threads).
