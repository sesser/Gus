# RAF not rendering: implementation status

Issue: #161. Bug fix, branch `bug/raf-not-rendering`, cut from `develop` at `ef592d9`.

**Status: Done** (2026-11-13). A raw the system's RAW decoder gives no image
for is decoded by the vendored LibRaw and renders everywhere; it is adjusted
like any rendered image. The code review's findings C1 to C12 and the design
review's fixes F1 to F5 are answered below. Next: the designer and the
code-reviewer confirm their fixes; then qa-tester; then the owner's sign-off.

## Bug

**Steps to reproduce** (macOS 27.2.1). `swift run photocli render
/Volumes/photos/2019/2019-01/2019-01-12/DSCF5159.RAF --out o.png`, or open any
RAF of that folder (Fujifilm X-E3) in the loupe.

**Expected:** it renders. **Actual:** `undecodable`; a black loupe, grey film
strip tiles.

**Root cause.** Not the network volume or #160: all 16 X-E3 RAFs tried fail on
a local copy too. On this macOS `CIRAWFilter` is made for the file but has
`nativeSize` 0x0, decoder versions `["None"]` and no output image, and ImageIO
cannot decode it either, so `PreviewGenerator.decode` had nothing left and threw.
(A 2020 X-T3 RAF, `DSCF4583.RAF`, decodes with the system decoder.)

**The fix.** `PreviewGenerator.decode` falls back to LibRaw
(`Preview/LibRawDecoder.swift`) when, and only when, the system decoder gives
no image.

**The test that fails without the fix:**
`LibRawFallbackPipelineTests.rawWithoutSystemImageRenders` ("A raw the system
decoder gives no image for is decoded by LibRaw and renders",
`Tests/PhotoCoreTests/LibRawDecoderTests.swift`). It runs in every `swift test`
on a synthetic 256 x 192 DNG, for which the system decoder gives no image on
this Mac exactly as for the X-E3 file. Checked: with the fallback's line
switched off it fails with `undecodable` (and five more of the suite with it).
Where a macOS does read that DNG the test still passes, through the system
decoder, and prints that its premise does not hold there; `LibRawDecoderTests`
calls LibRaw directly and runs its code on every macOS. On a real file:
`RAF_SAMPLE=path/to/X-E3.RAF swift test --filter LibRawFallbackTests` (5 tests).

## Owner's rulings

2026-11-13, before the review: no embedded preview in place of a render (a
grid placeholder is its own feature, #168). LibRaw, vendored, only where the
system decoder gives no image, so nothing gets slower.

2026-11-13, on the code review's questions:

- **Q1, license.** LibRaw is taken under the LGPL 2.1, not the CDDL.
- **Q2, `CLAUDE.md`.** The Dependencies edit stands, with LGPL 2.1 in place of
  CDDL; the other "GRDB only" statements follow. See **Not done** below: the
  wording is proposed there, not applied by the engineer.
- **Q3, adjusting.** A photo LibRaw decoded must still be adjustable. Controls
  are not hidden unless an adjustment is impossible; what is impossible is
  reported as a Design question.
- **Q4, the cache.** LibRaw previews stay on disk under the same keys as any
  preview; two looks after a macOS change are accepted. No cache change was
  made.
- **Q5, the frame.** Stays LibRaw's first inset crop. Listed under **Open**.

## What a LibRaw photo is

One test, `SystemRAWDecoder.reads(url)` (`Preview/SystemRAWDecoder.swift`):
the system decoder gives an image of the file with its default settings. It is
the test `PreviewGenerator.decode` makes of a decode, and what `RawDefaults`,
Auto White Balance, the live session, the 100% renderer, the sharpening map,
the fringe picker, Color Alignment's measurement and the editor ask instead of
the file's extension. A raw that fails it is a rendered image everywhere, as a
JPEG is (`RenderContext.isRaw` false):

| | Raw the system decodes (X-T3) | Raw LibRaw decodes (X-E3) |
|---|---|---|
| White Balance modes | As Shot, Auto, Daylight … Flash, Custom | As Shot, Auto, Custom |
| Temperature, Tint | Kelvin and tint, in the decoder | relative (−100 … 100), in the renderer |
| Auto White Balance | Kelvin (5886 K, tint 7) | relative (16, −22) |
| Tone, Presence, Tone Curve, Color Mixer, Color Grading, masks, Lens, Effects, Sharpening, crop | renderer | renderer, the same |
| Highlights or Exposure below 0 | decoder keeps values above white | what the decode holds (as a JPEG) |
| Luminance noise reduction | decoder | renderer's denoiser |
| Color noise reduction | decoder | not offered |
| Profile, Decoder | offered | a note in the group's place |
| Use machine learning | offered | dimmed: "Not available for this camera." (on every macOS, F3) |
| Mode shown after a paste of Daylight or a Kelvin Custom | the pasted mode | As Shot: what renders (F2) |

`photocli render --long-edge 600` with one `--set` at a time, SHA-256 of the
PNG against the unedited render (debug build):

| Setting | X-E3 (LibRaw) | X-T3 (system) |
|---|---|---|
| `whiteBalance.relativeTemperature=60`, `relativeTint=30` | changes | same (a raw's is Kelvin) |
| `whiteBalance.temperature=2500`, `tint=60` | same | changes |
| `whiteBalance.preset=daylight` (5500 K) | same | changes |
| `exposure.ev=1`, `exposure.ev=-1` | changes | changes |
| `tone.highlights=-80`, `tone.shadows=60`, `tone.contrast=50` | changes | changes |
| `noiseReduction.luminance=80` | changes | changes |
| `noiseReduction.color=90` | same | changes |
| `rawDecode.look=flat` | same | changes |
| `sharpen.amount=120` | changes | same (under a fifth of full size: no sharpening shows) |
| `presence.saturation=40` | changes | changes |

So the two kinds of raw mirror each other in white balance: Kelvin values do
nothing to a LibRaw photo, relative values do nothing to a system raw. That is
how a JPEG has always behaved, and the Adjust tab offers each photo only the
kind that works. Kelvin values reach a LibRaw photo only by paste, a preset or
`photocli`, and then change nothing; they stay in the stack, and the Mode
pop-up shows the mode that renders (design review D2, F2).

## Code review findings

| # | Outcome |
|---|---|
| C1 | Fixed in `7957ed1` (no `LIBRAW_NOTHREADS`). Now tested: `concurrentDecodesMatchSoloDecodes` (12 decodes of 6 files at once, four rounds, against each alone) and `buildIsThreadSafe` (the define is not in `Package.swift`). With the define put back, the first fails here (8 of 48 decodes differed) and so do the orientation and inset crop tests running beside it. |
| C2 | Fixed: the one test above. The editor's `isRaw` is "the system decoder reads this file"; the Adjust tab, Auto White Balance and the renderer agree. `photocli` table above. |
| C3 | Fixed. Decode settings reach only a raw the system decodes (`SystemRAWDecoder.Memo`, told by the editor from `RawDefaults`, else read from the file once), so they no longer key a LibRaw decode in `LiveRenderSession`, `LiveRegionRenderer`, `SharpeningMapRefiner`, the fringe picker or Color Alignment. `LiveRenderSession` also keeps LibRaw's decodes by what they differ by, half the frame or all of it, so a draft request, a final one and a small crop share one. On the X-E3 file: one decode through an interactive frame, a final frame, Kelvin and noise reduction changes and a 0.9 crop; a second, full one for a 0.3 crop. Test: `decodeSettingsDoNotDecodeAgain`. |
| C4 | Fixed. `LibRawDecoder.frameSize` reads the frame from the header (`libraw_open_file` only, about 1 ms) and `PreviewGenerator.nativeSize` answers with it. The reviewer's command now gives 1799x1199 for the X-E3 (was 900x600; X-T3 1872x1248). Tests: `cropDecodesLargeEnough`, and `aCropDecodesLargeEnough` on a real file. |
| C5 | Ruled (Q4): no change. |
| C6 | Fixed. `LibRawDecoderTests` (8 tests) and `LibRawFallbackPipelineTests` (8) run by default on synthetic DNGs: linear and neutral levels derived from the mosaic's values, orientations 3, 6 and 8 pixel for pixel, the half-size rule, the frame math and a real inset crop (`SyntheticDNG` can write a default crop), failing files, concurrent decodes, the fallback, the shared test, crop size, decode keys, the machine learning reason, Auto White Balance. The Bug section names the failing test. |
| C7 | Fixed: the reason is the availability's (`cameraNotSupported` on macOS 27, `notOnThisMac` before), not `failed`. Such a preview is still kept for the session only, as every not-applied render is. |
| C8 | Fixed: LibRaw's reason is logged (category `decode`) when it cannot decode a file the system decoder gave no image for. |
| C9 | Fixed: `src/Makefile` excluded (the build has no warning now), zlib no longer linked. |
| C10 | Fixed in `THIRD_PARTY_NOTICES.md`, `LibRawDecoder`'s comments, this file and the user guide. `README.md`, `CLAUDE.md` and `.claude/agents/code-reviewer.md`: see **Not done**. |
| C11 | Fixed: the real-file test compares long edges. |
| C12 | Fixed: `rawcompare` prints the first run and the best of N, is in the usage text and in `docs/PROFILING.md`, which says what the figures do not show. |

## Design review (`review.md`, 2026-11-13)

Rulings on the engineer's Design questions: **D1** keep the note under the
Profile heading, no dimmed pop-ups. **D2** no Kelvin scale and no Daylight to
Flash for these photos. **D3** their machine learning caption, check box help
and badge tooltip name Luminance only. **D4** no decoder badge in the grid or
the loupe.

| # | Outcome |
|---|---|
| F1 | Fixed. For a photo the system decoder doesn't read (`AdjustmentEditor.usesFallbackDecoder`), the caption and check box help are "Not applied: this camera isn't supported. Luminance applies instead." and the badge tooltip ends "It's shown with Luminance instead." (`MachineLearningText.caption`, `checkBoxHelp` and `badgeHelp` take `fallbackDecoder`; no new `Reason`, so export rows keep one reason per camera). Both keys are in the catalog with the review's comments. `print ml` prints them. |
| F2 | Fixed. `WhiteBalance.relativeDisplayPreset` (PhotoCore): Auto when the mode is Auto, else As Shot when both relative values are 0, else Custom. The Mode pop-up of every file that is not decoded as a raw (JPEGs too) selects it; the stack is not rewritten. Test: `LibRawFallbackPipelineTests.relativeModeShown`. Scripted: Daylight and machine learning copied from the X-T3 and pasted onto the X-E3 show `wb mode 'As Shot'` with `"preset":"daylight","temperature":5500` kept in the stack; after Temperature +25, `'Custom'`. `print ml` prints the pop-up's selected mode. |
| F3 | Fixed. The reason for these photos is the camera on every macOS: `MachineLearningNoiseReduction.reasonWithoutSystemDecoder` (`cameraNotSupported`) is what a decode reports (so the badge, `photocli` and the export's Activity row), and the editor gives the check box and caption `cameraNotSupported` without asking the macOS version. Test: `machineLearningReasonIsTheCamera`. Not run before macOS 27: no such Mac here; the code no longer has a branch on the version for these photos. |
| F4 | Fixed: the note reads "macOS can't decode this raw file, so it's shown without a profile. Temperature and Tint are relative to the camera's white balance, and Color noise reduction isn't available." (catalog key and value; place, style and the combined accessibility element kept). |
| F5 | Fixed in `docs/USER_GUIDE.md`: "not the macOS decoder's profile and contrast"; the groups by their names (Tone, Presence, Tone Curve, Color Mixer, Color Grading, …); Use machine learning "dimmed unless a paste or preset turned it on; it then says it isn't applied, and Luminance applies instead". |

The review's improvement (the tab laying out as for a JPEG while a photo
loads): the Adjust tab shows its spinner while the editor is loading
(`loupeAdjustState` `.loading`) and lays the controls out only once the file's
kind is known, so no layout of the wrong kind is drawn. M5 stays a manual check.

## Build and tests

- Baseline before this pass (`7957ed1`): `swift build` complete with one
  warning (C9); `swift test` 859 tests in 129 suites passed, 1 known issue.
- Now: `swift build` complete, no warning. `swift test`: 879 tests in 131
  suites passed, the same 1 known issue (`LiveSessionTests`, values above
  white in the cached stages). `RAF_SAMPLE=… swift test --filter
  LibRawFallbackTests`: 5 tests passed. `Scripts/build-app.sh all`: both
  bundles built (SDK 27.2, minimum 15.0).
- Two existing tests changed, neither loosened: `RAWDecodeGraphTests`' tripwire
  lists `SystemRAWDecoder.swift` as a place a RAW filter is made and never
  rendered; `LiveRegionRendererTests.decodeWhileMoving` uses a file that does
  not exist and now tells the renderer the system decodes it, as the editor does.
- No golden moved, no pipeline bump, no migration. Renders of files the system
  decoder reads are unchanged; the live session's decode size for a crop keeps
  its old arithmetic for them.

## Debug-script check

A copy of the release bundle with its own bundle identifier, a new library
root in a scratch folder, the X-E3 and X-T3 files added with `addfolder`.
`print ml` now starts with the decoder and what the Adjust tab offers.

- X-E3: `decoder fallback wb modes [As Shot, Auto, Custom] temperature enabled
  true value 0`; `ml checkbox off enabled false tip 'Not available for this
  camera.'`; Color and Decoder not shown. `adjust warmth 60`, `adjust auto wb`
  (relative 16, −22), exposure, highlights and `luminance-nr` each saved a
  stack and an undo step, and the loupe's picture changed (snapshots).
- X-T3: `decoder system wb modes [As Shot, Auto, Daylight, Cloudy, Shade,
  Tungsten, Fluorescent, Flash, Custom] temperature enabled true value 6,246 K`,
  the check box enabled, Color and Decoder shown; Auto gave 5886 K, tint 7.
- Not checked by script: the note's look (the snapshot leaves the inspector
  blank in this design, and SwiftUI text is not found through AppKit).

- After the design review's fixes, a paste from the X-T3 (Daylight, Use
  machine learning on) onto the X-E3: `wb mode 'As Shot'`; `ml caption 'Not
  applied: this camera isn't supported. Luminance applies instead.' triangle
  true`, the check box on and enabled with the same tip; the badge's help ends
  "It's shown with Luminance instead."; turning it off gives the dimmed "Not
  available for this camera." again.

**For a person:** the design review's manual checks M1 to M5 (`review.md`):
the note's look, White Balance, the dimmed check box, a paste from a raw macOS
decodes, and switching between the two photos.

## Timings

Release build, local copies, `photobench rawcompare --runs 3` (first run /
best of three; `docs/PROFILING.md` says how to read the system's column):

| File | System | LibRaw full | LibRaw half |
| --- | --- | --- | --- |
| Sony ARW 24 MP | 0.19 / 0.06 s | 1.18 / 1.15 s | 0.13 / 0.12 s |
| Fujifilm X-T3 RAF (26 MP, compressed) | 0.05 / 0.05 s | 9.62 / 9.55 s | 0.64 / 0.62 s |
| Fujifilm X-E3 RAF (24 MP) | no image | 8.79 / 8.71 s | 0.60 / 0.59 s |
| Canon CR2 | 0.05 / 0.05 s | 1.29 / 1.26 s | 0.30 / 0.30 s |
| Olympus ORF | 0.09 / 0.08 s | 1.32 / 1.30 s | 0.42 / 0.41 s |
| Panasonic RW2 | 0.05 / 0.02 s | 1.09 / 1.09 s | 0.16 / 0.16 s |
| Panasonic HDR DNG | 0.04 / 0.03 s | unsupported | n/a |

The half-size decode serves thumbnails and fitted previews (a 2560 pixel
preview of the X-E3 takes about 0.6 s to decode). The full decode, about 9 s
for an X-E3 file, is needed at 100%, for an export over half the frame's size,
and for a crop that keeps less than 85% of the frame's long edge at preview
size. LibRaw is single-threaded here.

## Open (the owner's call)

- **Q5, the frame.** LibRaw's first inset crop: 5998x3997 for the X-E3 (its
  JPEG is 6000x4000; LibRaw moves the crop onto the X-Trans pattern), and the
  visible area where a file has none. The second inset crop (a 16:9 or 1:1
  picture) is not read; no sample here.
- **Edits when a later macOS decodes the camera.** The photo then goes to the
  system decoder: its look changes (Q4 accepted that for the cache), and a
  relative Temperature or Tint set meanwhile stops applying, because a system
  raw takes Kelvin values only. The stack keeps the values. Requirements issue R1.
- **The level of a LibRaw decode depends on its content.** LibRaw's default
  takes the brightest value in the frame as white when it is over 75% of the
  file's white level (`adjust_maximum_thr`, against color casts in clipped
  highlights). Two frames of one scene can differ by up to 0.4 EV. Kept as
  LibRaw's default; found by the inset crop test. Requirements issue R2.
- **LGPL in a distributed binary.** The bundles carry no notices; the LGPL asks
  for a notice and a copy of the license with a binary, and for a note of the
  change and its date in each modified file (the two headers carry none: the
  vendored tree was not to be touched; the notices file has it). Not legal
  advice. Requirements issue R3.
- **White balance across decoders.** Ruled for this fix (D2: not offered). A
  Kelvin white balance pasted onto a LibRaw photo, or a relative one onto a
  raw macOS decodes, is kept and does nothing; the designer proposes an
  enhancement for the product manager (slug `white-balance-across-decoders`),
  which also covers R1.

## Not done, and why

- **`CLAUDE.md`** (Dependencies, about line 364, still says CDDL; line 158
  still says GRDB is the only dependency) and
  **`.claude/agents/code-reviewer.md:37`**: not edited. The engineer's rules do
  not let another agent's message authorize a change to `CLAUDE.md` or to
  `.claude/`; the wording is in the report for the owner or the main session.
- **`README.md`**: the product manager's (`docs/WORKFLOW.md`); see **README**.
- **`Sources/CLibRaw`**: untouched except for `LICENSE.LGPL`.
- No decoder badge in the grid or loupe, no `decoder` field in `photocli`'s
  JSON, no multithreaded LibRaw, no zlib or JPEG support in it: proposed as
  follow-ups in the report.

## README

For the product manager at Ship:

- Line 161: GRDB is no longer the only third-party code. Proposed: "GRDB is
  the only package dependency. LibRaw 0.22.3 is vendored in `Sources/CLibRaw`
  under the LGPL 2.1 (see `THIRD_PARTY_NOTICES.md`) and decodes raw files the
  macOS raw decoder cannot."
- The layout table has no row for `Sources/CLibRaw` (LibRaw's source, built by
  `Package.swift`; never edited).
- Requirements: raws macOS does not decode (the Fujifilm X-E3 on macOS 27.2)
  now render, flatter, with the differences the user guide lists.
- The License section may want a line that LibRaw is included under the LGPL 2.1.
- `CLAUDE.md`'s "Scope so far" needs an entry for this fix; its Commands could
  list `RAF_SAMPLE=path/to/file.RAF swift test --filter LibRawFallbackTests`.
