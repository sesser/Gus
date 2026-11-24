Issue: #277 · Complexity: Hard

# Some HEICs render brighter than Quick Look, and slider edits jump back: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/heic-exposure-bright`, from `develop` at `139b39e`.

**Status: Blocked** on RI-1 (what a gain-map photo should look like in the
loupe on a display with extended dynamic range). The cause is established
(below); no code that changes behavior is written. What is committed: this
file, a synthetic gain-map fixture (`Sources/PhotoFixtures/GainMapImages.swift`)
and tests that record the cause (`Tests/PhotoCoreTests/GainMapRenditionTests.swift`),
with an opt-in suite for the owner's file.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (scratch library only; the owner's `IMG_0546.HEIC`, an
iPhone HEIC, or any HEIC or JPEG whose gain map lifts the picture below SDR
white, such as `GainMapImages.write(…, gain: 2)`).
1. A display whose `maximumPotentialExtendedDynamicRangeColorComponentValue`
   is above 1 (here a DELL U2723QE in HDR mode: 4.18), View ▸ Show HDR
   Highlights on (the default).
2. Open the photo in the loupe, unedited. Compare with Quick Look of the file
   while Gus is the active app.
3. Drag Exposure (or Highlights to the left) and let go.

**Expected** (as filed). The unedited photo looks like the system's own
rendering of it; a slider's edit stays applied after release. Which system
rendering is meant is open: see RI-1.

**Actual** (measured, macOS 27.2.1, this Mac).
- The loupe shows the gain map's HDR rendition (`print hdr`: loupe headroom
  2.73). For the owner's file it is 0.86 stops brighter than the SDR rendition
  by mean luminance, and brighter at every level, not only above white: median
  0.258 → 0.426 (×1.65), 90th percentile 0.581 → 1.106 (+0.93 stops). The SDR
  rendition is what Gus's previews, thumbnails, exports, `photocli render` and
  live frames show, and it equals ImageIO's own SDR decode (−0.01 stops).
- While the slider moves, the loupe shows live frames, which are SDR (`print
  hdr`: headroom none). On release it swaps the HDR rendition back in, with the
  edit applied (Exposure −1: headroom 1.37): 0.86 stops brighter than the frames
  the drag showed. So the edit is applied, but the picture jumps up by most of
  a stop, which reads as the edit snapping back.
- Any value `Adjustments.preservesExtendedRange` turns away (Contrast, Whites,
  Blacks, Highlights above 0, Tone Curve, Color Mixer, Color Grading, a look-up
  table, Dehaze, Grain) makes the loupe settle on the SDR rendition instead:
  Contrast +20 drops the photo 0.86 stops darker than before the change; reset
  it and it jumps bright again. Exposure low enough that nothing stays above
  1.05 does the same (`RenderEngine.minimumHDRHeadroom`).

**Root cause.** One cause gives both symptoms. On an EDR-capable display the
loupe replaces the SDR preview with `PreviewGenerator.hdrImage`, which decodes
gain-map files with `CIImage` `.expandToHDR` (`decodeHDR`) and so shows the
gain map's alternate (HDR) rendition at its full headroom. The design assumed
that rendition is the SDR picture plus highlights above white ("Show HDR
Highlights", the user guide's "highlights above white"). For an iPhone gain map
it is not: the gain map lifts the mid-tones and shadows too (here its ISO
21496-1 metadata: gain from −0.15 to +1.39 stops, alternate headroom 2.62×).
Everything else (live frames, previews, exports, stacks that turn HDR away)
is the SDR rendition, so the loupe moves between two renditions about a stop
apart: at open (against an SDR reference), on every slider release, and on
every value that crosses `preservesExtendedRange`.

Why Quick Look looked darker: Quick Look's image view is HDR-aware and follows
the system's HDR suppression policy (its `Image.qldisplay` has
`hostAppIsHDRSuppressed`, `isAppHDRSuppressed`, `hdrFocusMode`,
`reloadWithHDR:`; AppKit's `NSApplication.applicationShouldSuppressHighDynamicRangeContent`,
macOS 26, and WebKit's handling of backgrounded apps describe the policy).
With Gus active, Quick Look is in the background and likely shows the SDR
rendition; focused, it likely shows the same HDR rendition Gus does. Gus does
not follow that policy (nothing reads `applicationShouldSuppressHighDynamicRangeContent`).
This last part cannot be measured from a shell (screen capture of EDR content
needs permission and clips); it is check M1 below.

**Which files.** Non-raw files with a gain map, Apple's (`HDRGainMap`) or ISO
21496-1 (`ISOGainMap`): iPhone HEICs and JPEGs from recent iPhones, Android
Ultra HDR JPEGs, Core Image-written gain maps. How far the picture jumps is
how much the gain map lifts below white, which varies by photo (a gain map
that only lifts highlights barely shows it). Plain HEICs and JPEGs and every
camera raw are unaffected (no HDR rendition). Only with View ▸ Show HDR
Highlights on and a display with potential extended range above 1; elsewhere
the loupe is SDR throughout and matches the system. Not measured: HLG/PQ files
and floating-point DNGs (HDR merges), the other HDR content; whether their HDR
rendition agrees with their SDR one below white is open (RI-1, part b).

**Test that fails without the fix.** Not yet written: what it asserts depends
on RI-1. Under option A it is "`hdrImage` returns nil for a gain-map HEIC and
JPEG" (fails today: `GainMapRenditionTests.hdrRenditionIsBrighterBelowWhite`
shows it returns a rendition a stop brighter); under option B it is a live
frame and the settled rendition agreeing for the same values. The committed
tests record the cause as the code behaves today and will be turned around by
the fix.

## Evidence

The owner's file (never committed; personal metadata not recorded here): an
iPhone HEIC, 4032 × 3024, 8-bit Display P3, orientation 6, with an ISO 21496-1
gain map (2016 × 1512, base headroom 0, alternate headroom log2 1.389 = 2.62×,
gain −0.151 to +1.389 stops, gamma 0.73), Apple's HDR gain map (headroom
2.62) and a sky matte.

Mean, median and 90th-percentile luminance, linear Display P3, relative to SDR
white (800-pixel reductions; `HEIC_GAINMAP_SAMPLE`, and the scratch tools):

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

Gus's HDR rendition equals ImageIO's own HDR decode, so the gain map is
applied as the system applies it; the difference is which rendition is shown.

In the app (bundle copy `me.sesser.gus.debugtest.heicbright`, scratch library
from `photobench import` of a copy of the file, `--debug-script "windowsize
1800 1200; wait 2; focus 0; loupe; wait 4; print hdr; adjust scrub exposure 0
-1 10 16 hold; print hdr; adjust scrub exposure -1 -1 1; wait 4; print hdr;
adjust contrast 20; wait 4; print hdr; hdr off; wait 3; print hdr; quit"`):

```
hdr setting true screen potential 4.18 loupe headroom 2.73   (opened: HDR rendition)
hdr setting true screen potential 4.18 loupe headroom none   (dragging: SDR live frames)
hdr setting true screen potential 4.18 loupe headroom 1.37   (released at −1 EV: HDR again, edit applied)
hdr setting true screen potential 4.18 loupe headroom none   (Contrast +20: SDR)
hdr setting false screen potential 4.18 loupe headroom none  (Hide HDR Highlights: SDR)
```

## Requirements issue (for the product manager / owner)

**RI-1. What should a gain-map photo look like in the loupe on an EDR display,
and while it is edited?** `CLAUDE.md`'s Rendering rule and the user guide say
the loupe swaps in an HDR render for gain-map content on EDR displays, as
"highlights above white". For iPhone gain maps that render is a different,
brighter picture, and every edit path is SDR. Fixing the symptoms means
changing that rule one way or the other, so it is not mine to decide.

- **A. Gain-map files stay SDR in the loupe** (`decodeHDR` no longer counts a
  gain map as HDR content). The loupe then shows what live frames, previews,
  exports and Quick Look in the background show; edits never jump. Loses the
  brighter HDR view of iPhone photos (the HDR badge and Show HDR Highlights
  then apply to HLG/PQ files and HDR merges only). Cost: small; no stack renders
  differently anywhere it is stored or exported, so no
  `PreviewCacheKey.currentPipelineVersion` bump and no golden moves; the user
  guide's HDR paragraph and the Rendering rule's list change.
- **B. Keep the HDR rendition and make editing match it.** Live frames (the
  whole frame and the 100% region) rendered as half-float HDR whenever the
  loupe would settle on HDR, the histogram over the same, and every module
  `preservesExtendedRange` turns away made to work above white (or the
  remaining jumps accepted); plus following macOS 26's HDR suppression policy
  so Gus in the background shows SDR as Quick Look does. Matches Quick Look and
  Preview when focused. Cost: large (`LiveRenderSession`, `LiveRegionRenderer`,
  frame formats at twice the memory, ten modules), and previews and exports
  would still be SDR, so what is edited is not what is exported: this is an
  HDR editing feature and needs its own PRD and design.
- **C. A, now, and B later** as an enhancement (HDR editing and HDR export of
  gain-map photos), filed as an issue.
- **D. Show HDR only above white** (the SDR rendition below white, the gain map
  only for highlights). Not recommended: a rendering no other app shows, and
  its look would be invented here.

Part b, under A: should HLG/PQ files and HDR merges keep their HDR rendition?
Their HDR and SDR renditions were not compared below white; if they differ the
same jumps apply. I would measure them as part of the fix.

**Recommendation: C.** The loupe should show the picture being edited and
exported; A does that with a small change and no rendering change, and B is
real feature work. Before ruling, check M1: it says whether "expected" is
Quick Look in the background (A's look) or focused (today's look).

## For the owner, by eye (on the Dell, which has extended range)

- **M1.** Open `IMG_0546.HEIC` in Quick Look beside Gus's loupe, then click into
  the Quick Look window so it is the active app. Does Quick Look brighten to
  look like Gus (its HDR rendition), and darken again when Gus is clicked?
- **M2.** In Gus, View ▸ Hide HDR Highlights: does the loupe now match Quick
  Look as it looked in the issue's screenshot? Show HDR Highlights again, drag
  Exposure to −1 and let go: the jump on release is the swap described above.
- **M3.** With HDR highlights shown, set Contrast to +20, then back to 0: the
  photo drops about a stop and comes back (the `preservesExtendedRange` switch).

## Tests

- `GainMapRenditionTests` (new, synthetic, always run): a HEIC and a JPEG
  written by `GainMapImages` with a one-stop gain everywhere have a gain map;
  Gus's SDR render equals ImageIO's SDR decode within 0.05 stops; the HDR
  rendition is more than 0.8 stops brighter by mean and its median above 1.7×
  the SDR median; at Exposure −0.5 the settled HDR rendition is more than 0.8
  stops brighter than the SDR live frame of the same value; Contrast +20 gets
  no HDR rendition. These record today's behavior and change with the fix.
  Determinism: the assertions compare renditions a stop apart against 0.8-stop
  and 0.05-stop margins; GPU rounding is 2⁻¹¹ per half-float step, so no run
  order or timing enters (no shared state, no timing, no pool order).
- `GainMapRenditionTests.sampleRenditions`, opt-in:
  `HEIC_GAINMAP_SAMPLE=path/to/IMG.HEIC swift test --filter GainMapRenditionTests`.
  Prints the table's Gus rows; asserts only that the file has a gain map.

## Build and test results

- Baseline at `139b39e`: `swift build` clean.
- `swift test --filter GainMapRenditionTests`: 3 tests (4 cases) pass, the
  sample suite skipped; with `HEIC_GAINMAP_SAMPLE` set, all pass and print the
  measurements above.
- Full `swift test` (2026-11-24, with the new tests): 1532 tests in 216
  suites pass, 77 s.
- CI toolchain (`DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer
  swift build --build-tests --scratch-path .build-xcode26.3`, Xcode 26.3 at
  `/Applications/Xcode_26.3.app`): exit 0, no warnings in the new files. Not
  yet the Done check: nothing that fixes the bug is built.

## Open questions

- RI-1 (above).

## Follow-ups (proposed issues)

- Gus does not follow macOS 26's HDR suppression policy
  (`applicationShouldSuppressHighDynamicRangeContent` and its notifications):
  in the background it keeps showing HDR. Part of B; on its own it would only
  make Gus darker when another app is active.
