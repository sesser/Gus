Issue: #277 · Complexity: Hard

# Some HEICs render brighter than Quick Look, and slider edits jump back: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/heic-exposure-bright`, from `develop` at `139b39e`.

**Status: Done.** Fixed as ruled (RI-1, option C: option A now, HDR editing
later as #282). RI-2 (HLG files jump the same way) was ruled 2026-11-24: its own
bug, #283; this fix doesn't change HLG behavior. First-pass review findings
(code review C1 to C3 and Q3, design review F1 and F2) fixed; see Review
findings. Next: code-reviewer's second pass (on opus, as the first) and the
designer's confirmation of F1 and F2, then qa-tester.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (scratch library only; the owner's `IMG_0546.HEIC`, an
iPhone HEIC, or any HEIC or JPEG whose gain map lifts the picture below SDR
white, such as `HDRTestImages.writeGainMap(…, gain: 2)`).
1. A display whose `maximumPotentialExtendedDynamicRangeColorComponentValue`
   is above 1 (here a DELL U2723QE in HDR mode: 4.18), View ▸ Show HDR
   Highlights on (the default).
2. Open the photo in the loupe, unedited. Compare with Quick Look of the file.
3. Drag Exposure (or Highlights to the left) and let go.

**Expected** (as ruled, RI-1). A photo whose HDR comes only from a gain map
shows in the loupe as its SDR rendition, the one live frames, previews,
exports and the system's own SDR decode give. A slider's edit stays on screen
after release, at the brightness the drag showed.

**Actual** (before the fix, measured on macOS 27.2.1, this Mac).
- The loupe showed the gain map's HDR rendition (`print hdr`: loupe headroom
  2.73). For the owner's file it is 0.86 stops brighter than the SDR rendition
  by mean luminance, and brighter at every level, not only above white: median
  0.258 → 0.426 (×1.65), 90th percentile 0.581 → 1.106 (+0.93 stops).
- While the slider moved, the loupe showed live frames, which are SDR (`print
  hdr`: headroom none). On release it swapped the HDR rendition back in, with
  the edit applied (Exposure −1: headroom 1.37), 0.86 stops brighter than the
  frames the drag showed: the edit was applied, but the picture jumped up by
  most of a stop, which reads as the edit snapping back.
- Any value `Adjustments.preservesExtendedRange` turns away (Contrast, Whites,
  Blacks, Highlights above 0, Tone Curve, Color Mixer, Color Grading, a look-up
  table, Dehaze, Grain) made the loupe settle on the SDR rendition instead:
  Contrast +20 dropped the photo 0.86 stops; resetting it jumped back.

**Root cause.** One cause gave both symptoms. On an EDR-capable display the
loupe replaces the SDR preview with `PreviewGenerator.hdrImage`, and
`decodeHDR` counted a gain map as HDR content, decoding the file with `CIImage`
`.expandToHDR`: the gain map's alternate (HDR) rendition at full headroom. The
design assumed that rendition is the SDR picture plus highlights above white
("Show HDR Highlights"). For an iPhone gain map it is not: the gain map lifts
mid-tones and shadows too (this file's ISO 21496-1 metadata: gain −0.15 to
+1.39 stops, alternate headroom 2.62×). Everything else (live frames,
previews, exports, stacks that turn HDR away) is the SDR rendition, so the
loupe moved between two renditions about a stop apart: at open, on every
slider release, and on every value that crosses `preservesExtendedRange`.

**Quick Look.** Observed by the owner (M1, 2026-11-24): Quick Look shows the
file darker than Gus did, also when its window is focused; it does not
brighten. Why Quick Look shows it that way was not established. An earlier
version of this file suggested Quick Look follows macOS 26's HDR suppression
for background apps; M1 does not support that, and it is withdrawn. (HDR
suppression stays an unverified item in #282.)

**Fix.** `decodeHDR` no longer counts a gain map as HDR content
(`PreviewGenerator.hasHDREncoding`). What each kind of file does now:

| File | Before | Now |
| --- | --- | --- |
| HEIC, JPEG (or other non-raw) with a gain map only | HDR rendition (gain map applied) | SDR, as previews and exports |
| HLG or PQ HEIC, no gain map | HDR | HDR, unchanged (same decode, `.expandToHDR`) |
| HLG or PQ HEIC with a gain map | HDR | HDR, unchanged: the encoding decides, not the gain map |
| Floating-point DNG (HDR merges), with or without a gain map | HDR | HDR, unchanged: raws were never asked about gain maps |
| Integer DNG (ProRAW, camera DNGs) or camera raw, with or without a gain map | SDR | SDR, unchanged |

The comparison view's panes use the same `hdrImage` and follow. No stored
stack renders differently anywhere it is stored or exported (previews and
exports were always SDR), so no `PreviewCacheKey.currentPipelineVersion` bump
and no golden moved. HDR renditions live in memory only, so no cache to clear.

**Test that fails without the fix.** `GainMapRenditionTests`:
"A gain map alone gets no HDR rendition" (HEIC and JPEG; `hdrImage` at fit and
full size is nil, and Gus's SDR render equals ImageIO's SDR decode within 0.05
stops) and "A slider's release lands on the rendition its live frames showed"
(Identity, Exposure −0.5, Exposure +1 and Contrast +20 all give no HDR
rendition). Run against the unfixed `decodeHDR` (2026-11-24): both fail, 7
issues, at every case but Contrast (which had no HDR rendition before either);
`PreviewTests.hdrRenditionsKeepHighlightsAboveWhite`'s gain-map line fails too.
With the fix, all pass.

## Evidence

The owner's file (never committed; personal metadata not recorded here): an
iPhone HEIC, 4032 × 3024, 8-bit Display P3, orientation 6, with an ISO 21496-1
gain map (2016 × 1512, base headroom 0, alternate headroom log2 1.389 = 2.62×,
gain −0.151 to +1.389 stops, gamma 0.73), Apple's HDR gain map (headroom
2.62) and a sky matte.

Mean, median and 90th-percentile luminance, linear Display P3, relative to SDR
white (800-pixel reductions), before the fix:

| Rendition | Mean | Median | p90 | vs SDR |
| --- | --- | --- | --- | --- |
| ImageIO SDR decode (`CIImage` default; also its 2560 thumbnail) | 0.274 | 0.265 | 0.573 | |
| Gus SDR, unedited (`cgImage`, `photocli render`) | 0.273 | 0.258 | 0.581 | −0.01 stops |
| Gus HDR, unedited (`hdrImage`, the loupe on EDR) | 0.494 | 0.426 | 1.106 | +0.86 stops |
| ImageIO `kCGImageSourceDecodeToHDR` | 0.490 | 0.427 | 1.085 | +0.85 stops |
| Gus SDR, Exposure −1 (the live frames) | 0.137 | 0.129 | 0.291 | |
| Gus HDR, Exposure −1 (the loupe after release) | 0.247 | 0.213 | 0.553 | +0.86 stops |
| Gus SDR, Highlights −100 | 0.191 | 0.200 | 0.375 | |
| Gus HDR, Highlights −100 | 0.269 | 0.276 | 0.532 | +0.49 stops |
| Gus SDR, Contrast +20 (no HDR rendition offered) | 0.292 | 0.273 | 0.634 | |

Gus's HDR rendition equalled ImageIO's own HDR decode: the gain map was
applied as the system applies it; the difference was which rendition is shown.

Debug script, before the fix (bundle copy `me.sesser.gus.debugtest.heicbright`,
scratch library from `photobench import` of a copy of the file):
`hdr on; windowsize 1800 1200; wait 2; focus 0; loupe; wait 4; print hdr;
adjust scrub exposure 0 -1 10 16 hold; print hdr; adjust scrub exposure -1 -1
1; wait 4; print hdr; adjust contrast 20; wait 4; print hdr; …` printed loupe
headroom 2.73 (opened), none (dragging), 1.37 (released), none (Contrast).

## Requirements issues (for the product manager / owner)

**RI-1. Ruled 2026-11-24 (owner): option C.** Gain-map photos show as SDR in
the loupe now (option A, this fix); HDR editing of gain-map photos is the
follow-up, #282.

**RI-2. HLG files jump the same way, by more (part b, measured; behavior not
changed). Ruled 2026-11-24 (owner): a bug of its own, filed as #283 (option
(a) below).** This fix doesn't change HLG behavior: HLG and PQ files keep the
same decode as before. Synthetic files from `HDRTestImages` (1600 × 1200, the HDR picture
twice the SDR one's light), measured with `GainMapRenditionTests.Light`
(scratch probe, not committed: `cgImage` at long edge 2560 against `hdrImage`
at long edge 2560, unedited and at Exposure −0.5):

| File | SDR mean (loupe at fit, live frames) | SDR mean at full size (100%) | HDR mean | HDR over SDR |
| --- | --- | --- | --- | --- |
| PQ HEIC | 0.439 | 0.459 | 0.466 | +0.09 stops (−0.5 EV: +0.02) |
| PQ HEIC with a gain map (SDR base) | 0.233 | 0.233 | 0.467 | +1.00 stops (−0.5 EV: +1.00) |
| HLG HEIC | 0.149 | 0.459 | 0.466 | +1.64 stops (−0.5 EV: +1.53) |
| HLG HEIC with a gain map (SDR base) | 0.087 | 0.233 | 0.466 | +2.43 stops (−0.5 EV: +2.32) |
| Floating-point DNG (as the merge writes) | 0.664 | 0.664 | 0.707 | +0.09 stops; at −0.5 EV no HDR rendition |

- **HLG HEICs** (some cameras' HDR HEIF modes): the SDR rendition the loupe
  shows at fit, in live frames and in previews (ImageIO's thumbnail decode,
  `decodeWithImageIO` with a size) is 1.6 stops darker than the HDR rendition,
  and also 1.6 stops darker than the full-size SDR decode used at 100%. So an
  HLG photo jumps about 1.5 stops on every slider release, as gain-map photos
  did, and its preview disagrees with its own 100% view. Not changed here.
- **PQ HEICs and floating-point DNGs**: within 0.1 stops; no visible jump.
  A DNG merge at −0.5 EV falls below `minimumHDRHeadroom` and settles on SDR,
  0.1 stops off: negligible.
- **HLG or PQ with a gain map**: synthetic only (Core Image wrote an SDR base
  in an HDR encoding with a gain map up to the HDR picture); its SDR rendition
  is the base, its HDR rendition the gain map's, a stop or more apart. No real
  file of this kind was available; whether cameras write such files is unknown.
- Options for the product manager: (a) leave HLG/PQ as they are and file the
  HLG jump and the thumbnail-versus-full-size mismatch as a bug; (b) treat HLG
  like gain maps now (SDR in the loupe), which loses HLG's HDR view; (c) fold
  it into #282. Recommendation: (a), a bug of its own: the HLG thumbnail
  decode disagreeing with the full-size decode by 1.6 stops is wrong whatever
  the HDR ruling, and it would need a real HLG HEIF to confirm first.

## Proposed wording for CLAUDE.md's Rendering rule (owner's text)

Replace "HDR content only: floating-point DNGs, gain maps, HLG/PQ." with:
"HDR content only: floating-point DNGs and HLG/PQ-encoded images. A gain map
alone is not HDR content (issue #277): its HDR rendition is a different,
often brighter picture, and live frames, previews and exports are its SDR
rendition, so gain-map photos show their SDR rendition (HDR editing of them is
#282)."

(Corrected after code review Q3: the first proposal said "everything that edits
or exports is SDR", which is wrong. The HDR rendition applies the edit stack:
an HLG, PQ or floating-point DNG photo shows its edits in HDR in the loupe once
a slider is let go. What is SDR is the live frames, the cached previews and
exports.)

## For the owner, by eye (on the Dell, which has extended range)

- **M1** (done 2026-11-24): Quick Look stays darker than Gus showed, focused or
  not.
- **M2.** Open `IMG_0546.HEIC` in the loupe: does it look like Quick Look now,
  with no HDR badge in the caption? Drag Exposure to −1 and let go: does the
  picture stay at the brightness the drag showed?
- **M3.** Set Contrast to +20, then back to 0: the photo's brightness changes
  only by what Contrast does, no stop-sized drop and return.
- **M4.** A floating-point DNG merge (File ▸ Merge to HDR…, DNG) still shows
  its HDR badge and bright highlights.

M2 and M3 (before the fix) were not reported.

## Tests

- `GainMapRenditionTests` (new, synthetic, always run):
  - "A gain map alone gets no HDR rendition" (HEIC and JPEG): the files have a
    gain map; no HDR rendition at fit or full size; SDR equals ImageIO's SDR
    decode within 0.05 stops. Fails without the fix.
  - "A slider's release lands on the rendition its live frames showed":
    Identity, Exposure −0.5 and +1, Contrast +20 give no HDR rendition. Fails
    without the fix.
  - "An HLG or PQ HEIC keeps its HDR rendition, with or without a gain map"
    (four cases): the file has a gain map exactly when the case says so (C1),
    `hasHDREncoding` is true and an HDR rendition with headroom of at least
    `minimumHDRHeadroom` is made.
  - "A real gain-map HEIC gets no HDR rendition", opt-in:
    `HEIC_GAINMAP_SAMPLE=path/to/IMG.HEIC swift test --filter GainMapRenditionTests`.
    Asserts no HDR rendition for every stack and, unedited, Gus's SDR render
    within 0.05 stops of the system's SDR decode (C2). On the owner's file:
    passes, SDR mean 0.273 (−0.01 stops), at Exposure −1 0.137, Contrast +20
    0.292.
- `PreviewTests.hdrRenditionsKeepHighlightsAboveWhite`: its gain-map JPEG now
  expects no HDR rendition; the HDR case is a PQ HEIC (headroom above 2).
- `StalePreviewTests` ("The HDR rendition is not kept under a hash the loaded
  stack does not have"): its source is now a PQ HEIC with the same patch at 4×
  SDR white, since a gain-map JPEG has no HDR rendition any more. The edit is
  −1 EV (C3; it was −2 EV, whose rendition's headroom, 1.064 to 1.082, sat 1.4
  to 3 % over `minimumHDRHeadroom`): headroom now 2.16. The check that the
  rendition is the edit's is "8-bit mean level at least 5 below the unedited
  rendition's", measured here: unedited renditions at 512 px, 800 px and full
  size agree within 0.03 levels (95.62 to 95.65), the −1 EV ones are 13.5 lower
  (82.07). The old margin of 20 fit −2 EV only; drawn into 8-bit sRGB the 2×
  patch still clips, so −1 EV moves the mean less than a full stop would.
- Determinism: the assertions compare a nil against a rendition, or levels a
  stop apart against 0.05-stop margins; GPU rounding is 2⁻¹¹ per half-float
  step. No shared state, timing or pool order enters.

## Build and test results

- Baseline at `139b39e`: `swift build` clean.
- Full `swift test` (2026-11-24, with the fix): 1533 tests in 216 suites pass,
  78 s.
- `Scripts/build-app.sh all`: both bundles built and signed.
- CI toolchain, `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer
  swift build --build-tests --scratch-path .build-xcode26.3`: exit 0, no
  warnings in the changed files. (A first run failed: Xcode 26.3's type checker
  gave up on the luminance expression in `GainMapRenditionTests.Light`; split
  into three terms.)
- Debug script with the fix (bundle copy `me.sesser.gus.debugtest.heicbright`,
  scratch library with a copy of the owner's file; same script as above, `hdr
  on` first): loupe headroom none when opened, while dragging, after release at
  −1 EV (stack saved, ev −1), at Contrast +20 and back at 0. Positive control: a
  PQ HEIC (gray with a 4× patch, made in the scratchpad) in its own scratch
  library: loupe headroom 4.11.
- After the first-pass fixes (2026-11-24): `swift build --build-tests` clean,
  no warnings. Full `swift test`: 1533 tests in 216 suites pass, 75 s.
  `HEIC_GAINMAP_SAMPLE=…/IMG_0546.HEIC swift test --filter
  GainMapRenditionTests`: 4 tests pass, the figures above. CI toolchain,
  `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build
  --build-tests --scratch-path .build-xcode26.3`: exit 0, the two changed test
  files compiled, no errors or warnings. The changes are tests and docs only, so
  the bundle and debug-script results above stand.

## Review findings

First pass, code review (`code-review.md`) and design review (`review.md`),
2026-11-24. All fixed in one commit after `06188c2`.

| # | From | Finding | Resolution |
| --- | --- | --- | --- |
| C1 | code review | The HLG/PQ test never checked that its `gainMap: true` files have a gain map | Fixed: `#expect(Self.hasGainMap(url) == gainMap)` in "An HLG or PQ HEIC keeps its HDR rendition…". Passes here for all four cases |
| C2 | code review | The opt-in real-file test printed, not asserted, SDR against the system's decode | Fixed: unedited, `abs(sdr.stops(over: system)) < 0.05` is asserted (the owner's file: −0.01) |
| C3 | code review | The stale-hash test's −2 EV rendition sat 1.4 to 3 % over `minimumHDRHeadroom` | Fixed: −1 EV (headroom 2.16), level margin 5 from measurement (see Tests) |
| Q1 | code review | Can CI's virtual Macs encode HEIC? | Open, not checkable here (see Open questions); nothing changed |
| Q2 | code review | RI-2 needs its own issue before `Closes #277` | Done by the owner: #283 |
| Q3 | code review | The proposed `CLAUDE.md` wording said "everything that edits or exports is SDR" | Fixed in the proposal above; `CLAUDE.md` not edited (the owner's) |
| F1 | design review | User guide HDR paragraph: the SDR sentences split the HDR ones, "it" lost its referent | Fixed: the designer's suggested text, HDR photos in one paragraph, then the SDR ones |
| F2 | design review | README section said "No change", but the README lists gain-map files as HDR sources | Fixed: recorded under README for Ship |

## README

For Ship (the product manager's; `README.md` not edited here): the Features
list (`README.md` around lines 144-145) says "HDR display of HDR sources
(floating-point DNG, gain-map HEIC and JPEG, HLG and PQ) on EDR screens". After
this fix gain-map HEIC and JPEG photos are shown SDR, so it should read
floating-point DNG and HLG or PQ only. The same claim is in
`docs/features/_inventory.md` (the "HDR display" row) and in `CLAUDE.md`'s
Rendering rule (proposed wording above). Since README and `CLAUDE.md` change,
Ship (step 6) applies to this fix. No requirements, build commands or layout
changed. The user guide's HDR paragraph is updated in this change.

## Open questions

- **Q1 (code review): can CI's runners encode HEIC?** This branch is the first
  time the suite writes HEIC files (`HDRTestImages`, `PreviewTests`,
  `StalePreviewTests`). It can't be checked on this Mac, and there is no
  evidence either way, so nothing was changed. If the pull request's CI run
  shows `heifRepresentation` or `heif10Representation` failing, the fix is a
  skip with the reason when the encoder is missing (checked with
  `CGImageDestinationCopyTypeIdentifiers()`), never a weaker assertion.

## Follow-ups

- #282: HDR editing of gain-map photos (filed by the main session).
- #283: HLG files jump on slider release and their fitted render disagrees with
  their 100% render (RI-2, filed by the owner 2026-11-24).
