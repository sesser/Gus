Issue: #282 · Complexity: Hard

# Edit and show gain-map photos in HDR: implementation status

Owner: swift-macos-engineer. Branch `feature/gain-map-hdr-editing`, from
`7bf972d` (develop merged in). Spec: the PRD (issue #282's body, revised
2026-11-25 for RI-6 and RI-7; read from the scratch copy the main session
gave, GitHub was refusing the body update) and `design.md`; evidence from
spike #285 (`docs/features/gain-map-hdr/spike.md`).

**State: Done** (2026-11-25). Stage 1 passed the owner's early check; stage 2
built the rest of the PRD and design. Every acceptance criterion is built and
mapped to a test or a check below; nothing is blocked. What only a person can
check is listed under "For a person". Next: code review and the designer's
review, then QA.

States: Not started · In progress · Done · Blocked · Deferred.

## Early check (design §13): passed

The owner ran E1 to E4 on 2026-11-25 and reported, in full: "All four pass.
The built-in display showed 2.6x I think. It looks good and works as it
should". Q2 stands. The "2.6x" is from memory and not a measurement (design
§13.1).

DQ-1 (the second, smaller change on arrival on a screen that allows less
than the photo needs): the designer ruled option (a) (design §18.1) and the
owner accepted it on 2026-11-25: "Yes, Accept it. I did notice it in fact.
It's fine". Recorded in the PRD as RI-6 (R6, R8, AC7, AC18). Built as §18.1
says; the rule is `DisplayHeadroomReading.read` and `DisplayHeadroomMemory`
(PhotoCore), so changing it touches one type and its tests.

## Stage 2: where the choice is stored, and why

**Decision: an edit-stack operation, with a copy in the catalog.** The choice
is one operation in the version's edit stack (kind `hdr`, parameter `on`,
schema 1, left out when off: `Edits/HDRChoice.swift`), and migration v17 adds
`version.hdr`, a copy of it written with the stack.

- In the stack because R2 and the owner's Q3 ruling make it an edit like any
  other: one undo step, one History entry, a History revert restores the
  entry's value (entries older than the feature have no operation, so off),
  Reset All Adjustments removes it (`resettingAll`), a virtual copy starts
  with it, and each file of a pair has its own. All of that comes from the
  stack's existing paths with no new code. A `version` column alone would
  need its own undo step and would not be in History snapshots.
- Left out of `EditStack.renderHash` (and `isIdentity`) because it changes no
  SDR pixel (R12): toggling keeps every cached preview, and previews, exports
  and `photocli render` are byte for byte the same either way. No existing
  stack holds it, so no existing hash moved; no pipeline bump.
- Not a `Group`: presets, Copy Adjustments and paste never carry or change it
  (R3; `replacing` and `CopiedAdjustments.pasted` copy groups only).
- The `version.hdr` column exists because the loupe must know the choice
  before it reads the stack: to show an HDR rendition already in memory on
  arrival (design §6.1), to preload neighbors with the choice on, for the
  comparison panes and the export notice. It is written in the one place
  every stack write goes through (`Catalog.setEditStacks`), copied with a
  virtual copy and set again when Undo of Duplicate's removal puts a copy
  back (`storeHDRChoice`). `CatalogItem.hdr` carries it. It is deliberately
  not a property of `VersionRecord`: migration v2 reads and writes version
  records before v17 exists (the full suite caught this). An older build
  writing a stack does not update the column; the editor reconciles it from
  the stack whenever it opens the photo.

## Stage 2: progress

Built (commit "The stored HDR choice replaces the temporary switch"):
- The choice in the stack and catalog (above); `photocli develop --set
  hdr.on=true|false` and `--reset hdr` (R17, AC15): turning it on reads the
  original's header and refuses a file without a gain map (`invalidEdit`) or
  an original it can't read (`fileNotFound`); `photocli adjustments` lists
  the `hdr` module (no group); `query images` shows it in the stack.
- Editor: `hasGainMap` (header read with the other per-file facts, before the
  tab lays out), `setHDR` (**Turn On HDR** / **Turn Off HDR**, one undo step
  and History entry), live frames HDR exactly when the values rendered have
  the choice on, Show Original keeps the choice (unedited HDR, R8).
- Adjust tab header: the **HDR** check box after Original (design §2.1);
  Adjust ▸ Turn On / Off HDR above Auto Exposure (§2.2); View ▸ Show / Hide
  HDR (§3).
- Loupe: the visit follows the shown photo's choice (the editor's values once
  ready, else `CatalogItem.hdr`); changing it starts a new visit with the old
  picture kept until the new one; neighbors with the choice on are preloaded
  in HDR; a failed HDR version keeps the visit SDR (design §5, reason 4).
- Version badge and reasons (§4, §5, §12): `HDRVersionBadge` (PhotoCore, the
  rule) and `HDRText` (words); the caption shows one badge, a warning triangle
  for a reason, a short form when the row is too narrow (`ViewThatFits`
  bounded by the centered culling marks), the spinner after 0.5 s.
- What a screen allows (§18.1, §18.2): `DisplayHeadroomMemory` per screen in
  `LibraryModel`, outliving the loupe; a reading at a lower request keeps the
  remembered value; one showing more replaces it; readings while the app is
  not active are followed, not kept, and dropped on activation.
- HDR histogram (§7): `HDRHistogram` (153 SDR + 102 HDR bins, fixed +3 stop
  axis, share above white) from the whole HDR version at the file's full
  brightening, computed with each HDR live frame; `HDRHistogramView`; the
  Tone Curve keeps the SDR histogram (§7.3).

Built (commit "The gain map follows Distortion and spots; every adjustment tested in HDR"):
- R19: the gain map goes through Distortion's warp, then the spots (heal and
  clone, the spot's own mode), then turns, straightening and crop
  (`AdjustmentRenderer.gainMapGeometry`, used by `GainMap.placed(over:values:context:)`
  in the settled render, live frames and region frames). Lens Vignetting,
  Color Alignment and Color Fringes move nothing a one-channel gain map holds.
- AC6 and AC17 tests (`GainMapAdjustmentTests`), below under Tests.
- A test-harness fix: `GainMapHDRTests.Pixels` rendered CIImages in a default
  context (linear sRGB working space), so a recipe built for the app's
  working space (Black & White's matrix, Saturation, Vibrance) was measured
  differently on its SDR side than the engine rendered the HDR side. Black &
  White read as 0.40 stops RMS of drift; with the app's working space it reads
  as the others. Found by probing: Core Image's `applyingGainMap` scales each
  pixel by one factor (flat colors, ISO maps: exact; IMG_0561's map: within
  3%), so a gray picture stays gray in HDR.

Built (commit "Crop, comparison and the export notice in HDR"):
- Crop session (§8): the image under the frame is the HDR version (the live
  session renders it with the choice's headroom), in an extended-range layer
  of its own, rendered again when the headroom moves; the shade, frame,
  handles and grid are drawn as before.
- Maps (§8, RI-4): no version badge while a map shows; the HDR histogram's
  last counts stay (`LibraryModel.loupeHistogramIsHDR`, set by the visit, not
  by the badge).
- Comparison and review (§9): each pane shows its photo's choice (gain-map
  HDR rendition at fit and 100%, never replaced by SDR in that showing, a
  failure keeping it SDR), its own version badge (`comparisonHDRStatus`),
  which never drops from a narrow caption and takes its short form last; a
  choice-off photo's header is read once so its pane can say SDR. Panes read
  the screen into the same per-screen memory as the loupe (§18.1) and
  re-render when it moves. The inspector's HDR histogram follows the active
  pane (`PreviewService.gainMapHDRHistogram`, a 512 px render of the whole HDR
  version). Review is the loupe.
- Export notice (§10): "1 photo has HDR on. Exports are SDR." / "%lld photos
  have HDR on. …" (plural variations) under the subtitle, `info.circle`,
  counted over the sheet's photos when it opens (`ExportTargets.hdrCount`: a
  pair that exports its raw doesn't count; videos never).
- VoiceOver (§12): the loupe canvas's value includes the badge's phrase,
  without announcing a change of it alone.

Built (commit "HDR frames render the graph once; tests for SDR output, measurements, histogram, timing"):
- R11: an HDR live frame first rendered the whole adjustment graph three
  times (the frame, the SDR histogram's reduction, the HDR histogram's), 2.5
  to 3.2 times an SDR frame. Now the edited SDR frame is rendered once into a
  half-float IOSurface (`RenderEngine.materialized`) and the HDR frame and
  both histograms read it; the gain map is scaled to the frame as the decode
  is. Live and settled frames still agree (AC8 test unchanged and passing).
- Tests for AC9, AC11, AC12, AC13 and the timing run (AC10), below.

## Stage 1 (history): what it was for

Only what E1 to E4 need: one gain-map file shown and edited in HDR in the
loupe, with the gain map loaded, turned by the file's orientation and applied
last; fitted to what the display can give now and following it; live frames
and the settled render agreeing; at most one SDR-to-HDR change on opening from
the grid. Written as the foundation the rest builds on (PhotoCore pieces with
tests, in the spike's order). Not built: the stored per-photo choice and its
UI, version badges and reasons, the HDR histogram, overlays and maps in HDR,
the crop session in HDR, comparison panes, the export notice, `photocli`, the
user guide.

## The temporary switch: removed

Stage 1's `--gain-map-hdr on` is gone: `LaunchOptions.gainMapHDR`,
`TemporaryGainMapHDR` and its test, `LibraryModel.showsGainMapsInHDR`,
`LoupeController.gainMapSetting` and the debug script's `gainmaphdr`. The
stored choice replaces it. `LaunchOptions.swift` is back to `develop`'s text.

## Stage 1 (history): what was built

PhotoCore:
- `Preview/GainMap.swift`:
  - `GainMap`: loads a non-raw, non-video, not HLG/PQ file's gain map (ISO
    21496-1 or Apple's), turns it by the file's EXIF orientation (spike trap
    1), knows the file's headroom (the HDR decode's `contentHeadroom`) and the
    photo's *ceiling* (SDR white through the whole gain map at full weight: the
    brightest any HDR version of the photo can be; 2.62, 3.74 and 4.57 on the
    owner's three files, equal to their headroom within 0.5%). `placed(over:crop:)`
    stretches it over a decode of any size and takes it through the stack's
    turns, straightening and crop. `hdr(_:placed:displayHeadroom:)` clips the
    edited SDR render to SDR white in Display P3 (the SDR picture as shown),
    applies the gain map weighted for the display (`applyingGainMap(_:headroom:)`,
    the gain map's own rule) and limits the result to the tag.
  - `GainMapHeadroom`: weighting = min(file, display); tag = min(display,
    ceiling), so every frame of a visit has the same tag whatever an edit does
    to its brightest pixel, and no value is above what the display can show;
    when to render again (0.02 stops).
  - `GainMapVisit`: the loupe's R8 rule. Arrival may show SDR then HDR (one
    change); once HDR is on screen no SDR picture replaces it; maps are neither
    version; following the headroom is not a change.
  - `DisplayHeadroomReading`: what the display can give now, learned from
    settled screen readings (see Findings).
  - `TemporaryGainMapHDR` (see above).
- `RenderEngine.makeHDRCGImage(_:contentHeadroom:)`: half float, a given tag,
  no pixel scan. The existing `makeHDRCGImage(_:)` is unchanged in behavior
  (refactored to share the render).
- `PreviewGenerator.gainMapHDRImage(source:stack:longEdge:displayHeadroom:)`:
  the same decode as the SDR renditions, the stack, the gain map last.
- `PreviewService.gainMapHDRImage(for:displayHeadroom:fullResolution:)`, its
  memory lookup (by the tag the display wants), `insertGainMapHDRIntoMemory`
  and `gainMapHeadroom(for:)`; its own lane beside the HDR lane.
- `LiveRenderSession.render(…, hdrHeadroom:)` and
  `LiveRegionRenderer.render(…, hdrHeadroom:)`: with a headroom, a gain-map
  photo's frame is its HDR version (`Frame.headroom`); maps and other files
  are unchanged. An HDR frame's histogram is, for now, the SDR frame's
  (counted from a 256-pixel SDR reduction), until the HDR histogram (design §7)
  is built.
- `HDRTestImages.writePatternedGainMap` (PhotoFixtures): a gain map that
  brightens one part of the picture more, with any EXIF orientation.

PhotoApp:
- `LoupeController`: for a gain-map photo, the settled rendition at fit and at
  100% is `gainMapHDRImage` (neighbors preloaded too); live frames and region
  tiles are HDR (`AdjustmentEditor.hdrDisplayHeadroom`); `display` and
  `showLiveFrame` go through `GainMapVisit`, so the cached SDR preview, the SDR
  full rendition and SDR tiles never replace HDR once it is on screen; the
  layer asks for the photo's ceiling (`CALayer.contentsHeadroom`) while it
  shows a gain-map photo's HDR version; a 0.25 s poll and
  `NSApplication.didChangeScreenParametersNotification` follow the display's
  headroom and render the settled rendition again when it moves (one render at
  a time, latest wins). The caption's existing HDR badge shows, with the
  headroom the picture is shown at (min of the fitted tag and the file's) in its
  tooltip; the designed badges are later work.
- `AdjustmentEditor`: passes the headroom to both renderers; an HDR frame of
  the saved values goes into memory as the new edit's HDR version, never as its
  SDR preview.
- Debug script: `hdr display <h>|system` (override the display headroom),
  `gainmaphdr on|off` (temporary), and `print hdr` now also prints the screen's
  current reading and the visit (`LoupeGainMapReport`: version changes and their
  order, rendered tag, fitted display headroom, known limit, request, file
  headroom, refits, the live frame's kind).

SDR output: no SDR code path changed except `LiveRenderSession`'s final
lines, rewritten to the same calls in the same order (`scaledToFit`, then
`makeCGImage`, then `Histogram`). No golden moved; no
`PreviewCacheKey.currentPipelineVersion` bump; no migration; no package.

## Stage 1 (history): findings

### The display's headroom (design §13's note, verified)

Measured on macOS 27.2.1, M4 Pro, with a probe app in the scratchpad and the
app's debug script (`print hdr`). Two screens were seen, as the owner's setup
changed during the session: the built-in Retina display (potential 16.0) and
the DELL U2723QE (potential 4.18).

- With nothing asking for extended range, the current reading
  (`maximumExtendedDynamicRangeColorComponentValue`) was **1.20, not 1.0**,
  on both screens. The note's direction holds: it does not show what the
  display can give until a layer asks.
- A layer with `preferredDynamicRange = .high` showing an untagged image, or
  one tagged 1.0, did **not** raise it. An image tagged above 1 did: the
  reading ramped (about 1 to 2 s, `didChangeScreenParameters` posted about
  120 times a second meanwhile) to exactly the tag (2.0, then 6.0) when that was below what the
  display could give. Tagged 16 on the built-in display, it stopped at 9.82.
- The potential reading stayed at 16.0 (4.18 on the Dell) throughout. So the
  potential is **not** what the display can show now; a settled current
  reading below the request is. On the built-in display at the brightness of
  the moment that was 9.82; on the Dell it was 1.29 (a probe asking for 16 got
  1.29 too), so on the Dell as set up then every one of the three photos is
  brighter than the display.
- `CALayer.contentsHeadroom` (macOS 26) above the image's tag raises the
  request: an image tagged 1.5 with `contentsHeadroom` 16 took the reading to
  9.82. The loupe uses that: it asks for the photo's ceiling and tags the
  picture with the fitted headroom, so the reading settles at what the display
  can give up to the ceiling and can follow a brightness change both ways.
  (The deprecated `wantsExtendedDynamicRangeContent` also raises it to 9.82
  with `.standard`; not used.)
- In an app that is not frontmost the request was not always granted: a probe
  that lost activation got no ramp for a 6.0 tag until it was active again, and
  a shell-started (inactive) run on the Dell stayed at 1.20 and fitted to it.
  This is macOS 26's background HDR suppression (#287), not handled here.

What this means for E4: the first gain-map photo shown on a screen is rendered
for the potential headroom capped at the photo's ceiling, because nothing
better is known yet. Where the display gives at least the ceiling (the built-in
display at that brightness), nothing more happens. Where it gives less (the
Dell at 1.29), the reading settles about 1.5 s later and the picture is
rendered again for it: a second, smaller change, and between the two Core
Animation fits the picture to the display itself. The known limit is kept for
later photos on the same screen, which open directly at it. See DQ-1.

Not observed (no way to here): a real brightness change, so whether the
reading follows the brightness keys is unverified (E3 is that check); how any
of it looks.

### Rendering (from tests; no screen involved)

Owner's files, opt-in test (`HEIC_GAINMAP_SAMPLE=… swift test --filter
"GainMapHDRTests/sample"`), means of linear Display P3 luminance at a quarter of
2560 px; no personal metadata recorded:

| File | File headroom | Ceiling | Ours vs system HDR decode, unedited | Live vs settled at headroom 3 (identity, Exposure −1, Contrast +20) | Warm HDR frame, 2560 px |
| --- | --- | --- | --- | --- | --- |
| IMG_0546 | 2.62 | 2.62 | +0.006 stops | −0.0005, −0.0005, −0.0005 | 16 to 17 ms |
| IMG_0542 | 3.74 | 3.74 | +0.001 | −0.0005 each | 12.5 to 13 ms |
| IMG_0561 | 4.55 | 4.57 | +0.000 | −0.0005, −0.0005, −0.0004 | 9.6 to 17 ms |

The first frame of a session took 77 to 128 ms (gain map load, decode). SDR
frame times for the same stacks were not measured in this stage (AC10 is
later work).

## Acceptance criteria

PRD as revised 2026-11-25 (RI-6, RI-7, AC18). Tests are Swift Testing suites
in `Tests/PhotoCoreTests`; "script" is a debug-script run on a copy of the
bundle (identifier `me.sesser.gus.debugtest.hdrchoice282`, a scratch library
of copies of the owner's three photos in the session scratchpad,
shell-started unless said).

| AC | How it is checked | Result |
| --- | --- | --- |
| AC1 (R1) | `GainMapHDRTests` "A gain-map HEIC or JPEG has a gain map…" (HEIC, JPEG: yes; plain JPEG, PQ with and without a gain map: no); `GainMap.exists` refuses raws and videos by extension; `HDRChoiceTests` "Off is the default…"; script: a newly imported HEIC shows **SDR**, choice off, check box shown (`has choice true`) | Pass |
| AC2 (R2) | `HDRChoiceTests`: stack round trip, catalog column and History snapshot revert, virtual copy independence and Undo of Duplicate's removal, Reset All; script: on, relaunch still on, undo off, redo on, History lists **Turn On HDR**, revert to an entry with it off shows SDR, Reset All (menu, activated run) off, its undo on | Pass |
| AC3 (R3) | `HDRChoiceTests` "presets and Paste Adjustments neither carry nor change the choice" (both directions, all items and one group) | Pass |
| AC4 (R4, R5) | `HDRChoiceTests` badge reasons and order, offline with choice off (RI-3), fitted at 1.29 and 1.0 is **HDR** (RI-7); script: **SDR: HDR Hidden**, **SDR: No HDR Display** (`hdr display sdr`), **SDR: HDR Failed** (`hdr fail on`), allowance 1.29 and 1.0 read **HDR** with the fitted help tag; comparison panes each state their version; the stored choice unchanged under every reason | Pass (offline by the rule's test only; narrow-caption short form by eye) |
| AC5 (R6) | `GainMapHDRTests` system decode in every orientation, smaller headroom by the gain map's rule; script: `hdr display 2`, `1.5`, `system` refit without reopening, version unchanged | Pass |
| AC6 (R7) | `GainMapAdjustmentTests` "every adjustment…" (24 cases: every group and control, look-up table, masks; Black & White as a switch); opt-in `GAINMAP_SAMPLES` on the owner's three files (one with only Apple's kind of gain map), table below | Pass |
| AC7 (R8) | `GainMapHDRTests` "Once HDR is on screen…" (the visit rule); script: arrival `versions sdr,hdr changes 1`, then an Exposure change, Exposure −3 (nothing above white), crop begin and done, sharpening map on and off (no badge, HDR back), comparison and back, grid and back: still HDR, no further change; Undo of Turn On HDR, Reset All and a revert to an entry with it off show SDR | Pass (drags, zoom and hover by stage 1's scripted runs and the code path) |
| AC8 (R9) | `GainMapHDRTests` "A live HDR frame and the settled HDR render… agree" and "A region frame at 100%…" (within 0.005 stops), still passing after the single-render change | Pass in values; by eye with the owner |
| AC9 (R10) | `HDRChoiceOutputTests` "the HDR histogram counts values above white…" (same at headroom 1.3 and 16, draft and settled share within 0.05, dark edit keeps the axis) and its bins test; script: histogram kind and share in `print hdr` and `print compare` | Pass |
| AC10 (R11) | `GainMapTimingTests` (`GAINMAP_TIMING`), table below | Measured: within 1.5× |
| AC11 (R12, R14) | `HDRChoiceOutputTests` "previews and photocli render are the same bytes with the choice on and off"; `HDRChoiceTests` render hash; every golden passes unchanged | Pass |
| AC12 (R13) | `HDRChoiceTests` "the export notice counts…"; script: `export` prints "1 photo has HDR on. Exports are SDR." | Pass |
| AC13 (R15) | `HDRChoiceOutputTests` Auto Exposure, Auto White Balance and Color Alignment measure the same | Pass |
| AC14 (R16) | the existing HLG, PQ and floating-point DNG tests (`GainMapRenditionTests` for HLG and PQ, with and without a gain map; `PreviewTests` and the DNG merge suites `HDRMergerTests` and `HDRMergeJobTests`) pass unchanged; user guide states the limit | Pass |
| AC15 (R17) | `HDRChoiceTests` "develop sets and resets the choice…" (sets, reads back through `query images`, refuses a plain JPEG with `invalidEdit` and an unreadable original with `fileNotFound`) | Pass |
| AC16 (R18) | Every check above ran on macOS 27.2.1; nothing checks macOS 15 | n/a |
| AC17 (R19) | `GainMapHDRTests` every orientation, crop with turn and Straighten; `GainMapAdjustmentTests` Distortion with a crop and a turn (and a check that an unwarped gain map would be caught), heal and clone over a small bright object | Pass |
| AC18 (R6) | `GainMapHDRTests` "Design §18.1…" and "AC18: each screen's allowance…" (lower request keeps, more replaces, inactive not kept, per screen, survives requests stopping); structural: the memory lives in `LibraryModel`, outside the loupe; script: grid and comparison and back open with `refits 0` | Pass; by hand on a low-allowance screen, below |

"Fails without the fix": with the spot step left out of the gain map's
geometry (run and reverted 2026-11-25), both spot cases failed (2.0 stops at
the spot against 0.59 at its source). The Distortion test checks within itself
that an unwarped gain map is caught (more than 0.2 stops and four times the
warped error).

### AC6 on the owner's files (opt-in, 1024 px, stops RMS of ratio drift)

`GAINMAP_SAMPLES=…IMG_0546.HEIC:…IMG_0542.HEIC:…IMG_0561.HEIC swift test --filter "GainMapAdjustmentTests/everyAdjustmentOnRealFiles"`.
All below 0.05. Largest: IMG_0561 (only Apple's kind of gain map; Core Image
applies it with a small dependence on the base's level, spike trap 5)
Contrast 0.046, Tone Curve 0.040, Exposure 0.026, Clarity 0.025. IMG_0546 and
IMG_0542 (ISO gain maps): every adjustment 0.004 or less. Every value on
IMG_0561: white balance 0.0007, exposure 0.0258, contrast 0.0458, highlights
−80 0.0058, highlights +80 0.0008, shadows 0.0206, whites 0.0007, blacks
0.0218, clarity 0.0253, dehaze 0.0201, vibrance 0.0050, saturation 0.0034,
tone curve 0.0403, color mixer 0.0049, black and white 0.0106, color grading
0.0005, look-up table 0.0052, vignette 0.0208, grain 0.0048, sharpening 0.0000,
noise reduction 0.0171, lens vignetting 0.0131, color alignment 0.0080, mask
0.0083.

### AC10: frame times (opt-in, medians of 15 interactive frames, M4 Pro, macOS 27.2.1)

`GAINMAP_TIMING=…IMG_0546.HEIC:…IMG_0542.HEIC:…IMG_0561.HEIC swift test --filter GainMapTimingTests`.
Stack: Exposure (moving), Contrast +20, Highlights −30, Vibrance +15, an S
curve, Sharpening 40. Fit: 2560 px frames with both histograms; 100%: a
2560 × 1440 region of the full-resolution decode.

| File | Fit SDR | Fit HDR | Ratio | 100% SDR | 100% HDR | Ratio |
| --- | --- | --- | --- | --- | --- | --- |
| IMG_0546 | 22.1 ms | 24.7 ms | 1.12 | 12.6 ms | 10.9 ms | 0.87 |
| IMG_0542 | 21.0 ms | 24.3 ms | 1.16 | 11.7 ms | 10.7 ms | 0.91 |
| IMG_0561 | 16.6 ms | 23.8 ms | 1.44 | 18.7 ms | 18.5 ms | 0.99 |

Before the single-render change, fit HDR was 2.48 to 3.17 times SDR.

## Tests

New or changed suites: `HDRChoiceTests` (11 tests), `HDRChoiceOutputTests` (4),
`GainMapAdjustmentTests` (24 adjustment cases, Distortion, two spot modes,
the opt-in real-file run), `GainMapTimingTests` (opt-in), `GainMapHDRTests`
(stage 1's, plus the §18.1 and AC18 tests; the temporary switch's test
removed; its pixel reader now renders in the app's working space),
`CatalogTests` (v17 listed), `CommandTests` (`adjustments` lists `hdr`).

Determinism: the new tests compare renders of fixed synthetic files against
tolerances 10 to 100 times above half-float rounding, or compare pure values
(`HDRVersionBadge`, `DisplayHeadroomReading`, `DisplayHeadroomMemory`,
`HDRHistogram.bin`, `ExportTargets.hdrCount`) fed fixed inputs and times.
The byte-equality test renders the same stack twice through one generator and
compares whole files; renders with identical graphs and inputs are identical
here (as the existing "Rendering the same file with the same edits gives the
same bytes" test relies on). No shared state, timing or pool order enters.
The timing test asserts nothing about time.

## Build and test results

- Baseline at `2903ea7` (2026-11-25): `swift build` clean; `swift test`
  1546 tests in 217 suites passed, 83.4 s.
- At the end of stage 2 (2026-11-25): `swift build` clean, no warnings;
  full `swift test`: **1568 tests in 221 suites passed**, 86 s. Goldens
  unchanged; no `PreviewCacheKey.currentPipelineVersion` bump.
- CI toolchain: `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3`:
  **Build complete**, no errors, no warnings.
- `Scripts/build-app.sh`: bundle built and signed.

Debug-script results (2026-11-25) are in the AC table. Screens seen: the
DELL U2723QE (potential 4.18; the shell-started app read 1.0 to 1.2, an
activated one 1.29) and earlier the built-in display.

## For a person

On an HDR display, with a copy of the bundle on a scratch library (the
owner's three photos are copied in `/Users/randy/gus-qa/gain-map-hdr-editing/photos`
from the early check):

```zsh
cd /Users/randy/Projects/Gus && Scripts/build-app.sh && Q=/Users/randy/gus-qa/gain-map-hdr-editing && rm -rf $Q/Gus-gainmap282.app && cp -R build/Gus.app $Q/Gus-gainmap282.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.gainmap282 $Q/Gus-gainmap282.app/Contents/Info.plist && codesign --force --deep --sign - $Q/Gus-gainmap282.app && open -n $Q/Gus-gainmap282.app --args --library-root $Q/library
```

The early check's `--gain-map-hdr on` is gone: turn HDR on per photo with the
Adjust tab's **HDR** check box.

1. The **HDR** check box after **Original** and **Adjust ▸ Turn On / Off HDR**:
   look, spacing, that the box doesn't appear for a raw or a plain JPEG.
2. Turning it on: the badge and check mark respond at once, the picture
   changes once to HDR; turning it off returns to SDR at once.
3. Brightness while dragging and on release, at fit and 100% (AC8 by eye),
   including Exposure, Contrast, a curve, a mask, and Show Original.
4. Handles (crop, mask, spot) over bright highlights stay findable; the mask
   overlay's red reads clearly over highlights; the crop session's picture is
   HDR and Done and Esc go straight back to HDR.
5. Sharpening and fringe maps: no flash of SDR around them; HDR returns.
6. The HDR histogram's look in Light and Dark appearance and with Increase
   Contrast: the line, fill, dashed lines and the **HDR** mark; the Tone
   Curve's backdrop staying SDR.
7. Narrow captions: shrink the window until a reason badge
   (**SDR: HDR Hidden**, via View ▸ Hide HDR) takes its short form, triangle
   and **SDR**; in comparison, that the version badge never drops.
8. On a screen that allows less than the photo needs (the Dell): the first
   photo changes at most once more about 1.5 s after HDR appears; later
   photos, also after the grid, a video, comparison and moving the window
   away and back, do not (AC18 by hand). The badge's help tag names the
   file's number and the display's.
9. The Export sheet's notice line under the subtitle.
10. Comparison with an HDR photo beside an SDR one: each pane's badge, the
    histogram following the active side.

Covered by CI only, per the owner's standing ruling: VoiceOver, macOS 15 and
macOS 26.

## Open questions

### Design questions (for apple-ui-designer)

None open. DQ-1 is ruled (design §18.1) and accepted by the owner.

Noted, not a question: the comparison panes follow the screen's headroom with
a 0.25 s poll like the loupe's; while comparing, the panes' layers make the
request the screen's reading answers (the largest ceiling of the two photos).

### Requirements issues (for the product manager)

None open. RI-6 and RI-7 are in the revised PRD.

## README

- Catalog: migration v17 adds the column `version.hdr` (the HDR choice's copy
  of the stack's value). CLAUDE.md's Catalog rule lists tables only; the edit
  stack rule may want "the `hdr` operation is left out of the render hash".
- New opt-in test variables: `GAINMAP_SAMPLES=a.HEIC:b.HEIC swift test --filter "GainMapAdjustmentTests/everyAdjustmentOnRealFiles"`
  and `GAINMAP_TIMING=a.HEIC swift test --filter GainMapTimingTests` (the
  owner's files, never committed), for CLAUDE.md's command list.
- The View menu item is now **Show / Hide HDR** (CLAUDE.md's Scope still says
  "Show / Hide HDR Highlights" in the #277 entry).
- `photocli develop --set hdr.on=true|false`.

## User guide

Updated in its own commit: the HDR passage (gain-map photos, the choice, the
badges and reasons, fitting, the first photo's second adjustment, what stays
SDR, the HLG/PQ/DNG limit naming the adjustments), the histogram passage, the
Export passage, the Adjust tab header, and `photocli develop`.
