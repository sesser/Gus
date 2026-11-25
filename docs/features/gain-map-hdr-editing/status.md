Issue: #282 · Complexity: Hard

# Edit and show gain-map photos in HDR: implementation status

Owner: swift-macos-engineer. Branch `feature/gain-map-hdr-editing`, from
`7bf972d` (develop merged in). Spec: the PRD (issue #282's body, revised
2026-11-25 for RI-6 and RI-7; read from the scratch copy the main session
gave, GitHub was refusing the body update) and `design.md`; evidence from
spike #285 (`docs/features/gain-map-hdr/spike.md`).

**State: In progress.** Stage 1 passed the owner's early check. Stage 2 (the
rest of the PRD) is being built; see "Stage 2" for what is done and left.

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

## Stage 1: what it is for

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

## What was built

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

## Findings

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

## Tests

`Tests/PhotoCoreTests/GainMapHDRTests.swift` (13 tests, synthetic files, always
run, plus the opt-in sample test):

| Test | Checks | PRD |
| --- | --- | --- |
| A gain-map HEIC or JPEG has a gain map… | load, headroom against the system's decode, ceiling; a plain JPEG, PQ HEICs with and without a gain map: none, no HDR version | R1 (detection), R16 |
| Unedited at the file's headroom… every orientation | HEIC and JPEG × orientations 1 to 8: 8 × 6 cell means within 0.05 stops of the system's `.expandToHDR` decode | AC5 (first half), AC17 (orientation) |
| For a smaller headroom… | at 1.5, 2 and above the file's headroom: each cell's brightening is log2(display)/log2(file) of the full one (ISO 21496-1), within 0.06 stops; values within the tag | AC5 (second half), R6 |
| An edit changes the HDR version by as many stops… | Exposure ±1, Contrast +50, Highlights −50: ratio drift under 0.05 stops RMS per pixel | AC6 (part: four controls) |
| A live HDR frame and the settled HDR render… | identity, Exposure −1, Contrast +20, crop + quarter turn + 3°, at headroom 2 and 100, orientation 6: same size, same tag, means within 0.005 stops | AC8 (rendered values), R9, AC17 (crop) |
| A map is never an HDR frame… | sharpening map SDR; a file without a gain map gives SDR frames | R8 (maps), R14 |
| A region frame at 100%… | region tile equals the matching quarter of the full-resolution HDR render within 0.005 stops, tagged | R9 at 100% |
| The service keeps one HDR version per photo… | memory lookup by tag, re-render for another headroom, nil for a plain JPEG | R6 |
| Headroom rules | weighting, tag, re-render threshold | R6 |
| Display headroom reading | ramp ignored, settle, follow both ways, keep across requests | R6 |
| Visit holds HDR | arrival one change, SDR refused after HDR, maps, refits | R8, AC7 (rule) |
| Temporary switch | test launches only | — |

"Fails without the fix" evidence for orientation: with the gain map left
unturned (a one-line change, run and reverted 2026-11-25), 14 of the 16
orientation cases failed (all but orientation 1, HEIC and JPEG).

Determinism: the tests compare renders of fixed synthetic files against
tolerances of 0.005 to 0.06 stops, 10 to 100 times above the half-float
rounding (2⁻¹¹ per step); `DisplayHeadroomReading` and `GainMapVisit` tests are
pure value types fed fixed times. No shared state, timing or pool order enters.

## Build and test results

- Baseline at `7bf972d` (2026-11-25): `swift build` clean; `swift test` 1533
  tests in 216 suites passed, 74.7 s.
- After stage 1 (2026-11-25): `swift build` clean, no new warnings (the two
  test warnings printed are older: `SmartAlbumTests`, `VirtualCopiesTests`).
  Full `swift test`: **1546 tests in 217 suites passed, 77.3 s**.
- CI toolchain: `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer
  swift build --build-tests --scratch-path .build-xcode26.3`: Build complete,
  no errors, no warnings in the changed files.
- `Scripts/build-app.sh`: bundle built and signed.

Debug script (bundle copy `me.sesser.gus.debugtest.gainmaphdr282`, a scratch
library in the session scratchpad with copies of two of the photos, launched
with `--gain-map-hdr on`; shell-started, so not frontmost):

- Built-in display, with two earlier builds of this branch (the screen changed
  to the Dell before the final one ran): open from the grid → `versions
  sdr,hdr changes 1`; the reading ramped 1.31 → 9.82 (a build tagging the
  display's potential, 16) and 1.22 → 1.85 → 2.62 (a build tagging the ceiling,
  2.62). Exposure scrubbed and released, Exposure −1, Contrast +20, back to 0:
  the live frame and the settled rendition stayed HDR, `changes 1` throughout.
  `hdr display 2`, `1.5`, `system`: the settled rendition was rendered again
  each time (`refits 1, 2, 3`), tags 2.00, 1.50, 2.62, still `changes 1`.
- Dell, final build: the reading settled at 1.29 (a frontmost run started with
  `open -n`) or 1.20 (shell-started, not frontmost), and the picture was
  rendered again for it (`refits 1`); the next photo opened directly at the
  known limit (`refits 0`). `--gain-map-hdr off`: SDR as before
  (`versions sdr`, no HDR frame).

## For the owner: the early check (design §13)

On the HDR display, with the app frontmost. The three photos are copies in
`/Users/randy/gus-qa/gain-map-hdr-editing/photos`; the library is a scratch
library made from them (`photobench import`); the app is a copy of the bundle
with its own identifier. Quit any copy started before.

Build the bundle and open it on that library:

```zsh
cd /Users/randy/Projects/Gus && git switch feature/gain-map-hdr-editing && Scripts/build-app.sh && Q=/Users/randy/gus-qa/gain-map-hdr-editing && rm -rf $Q/Gus-gainmap282.app && cp -R build/Gus.app $Q/Gus-gainmap282.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.gainmap282 $Q/Gus-gainmap282.app/Contents/Info.plist && codesign --force --deep --sign - $Q/Gus-gainmap282.app && open -n $Q/Gus-gainmap282.app --args --library-root $Q/library --gain-map-hdr on
```

Open it again later (only this way):

```zsh
open -n /Users/randy/gus-qa/gain-map-hdr-editing/Gus-gainmap282.app --args --library-root /Users/randy/gus-qa/gain-map-hdr-editing/library --gain-map-hdr on
```

The same photos as today (SDR), for comparing, after quitting the copy above:

```zsh
open -n /Users/randy/gus-qa/gain-map-hdr-editing/Gus-gainmap282.app --args --library-root /Users/randy/gus-qa/gain-map-hdr-editing/library --gain-map-hdr off
```

How to tell what is on screen: the loupe's caption shows **HDR** while the HDR
version is shown. Its tooltip says "Highlights up to N× SDR white": N is the
headroom the picture is shown at. The files go up to 2.6× (IMG_0546), 3.7×
(IMG_0542) and 4.6× (IMG_0561); an N below the file's means the picture is
fitted to the display. Grid, film strip and exports stay SDR, as designed.

1. **E1. A file brighter than the display.** Without the Pixel sample:
   - On the Dell, nothing to do: as it was set up during this session it gave
     only about 1.3× (see Findings), so every photo is fitted. Hover **HDR** to
     confirm N is about 1.3.
   - On the built-in display, turn the brightness up to the top (brightness
     keys or Control Center): that lowers what it can give. Open IMG_0561 (4.6×)
     and hover **HDR**; if N is still 4.6, IMG_0561 fits at that brightness and
     the built-in display can't show E1 with these files.
   Look at the fitted picture for a while. **Pass:** it looks like an
   acceptable HDR picture for that display (no flat, washed-out or crushed
   look you would not accept); compare with the `--gain-map-hdr off` launch if
   useful.
2. **E2. Drag sliders.** In the loupe, Adjust tab, on IMG_0561 and IMG_0546, at
   fit: drag Exposure slowly up and down and let go; drag Contrast both ways and
   let go; drag Sharpening's Amount to its maximum and let go. Then zoom to 100%
   (click the photo) and repeat Exposure and Sharpening. **Pass:** nothing away
   from what the slider does changes brightness while you drag or when you let
   go: no step on release, no pumping of the whole picture when highlights
   brighten, no drop to the SDR look at any point. The caption keeps **HDR**.
3. **E3. Change the screen's brightness with a photo open.** On the built-in
   display: brightness keys, slowly, a few steps down and up, then a quick run
   of steps. On the Dell, if macOS offers no brightness control for it, use the
   built-in display, or move the window from one screen to the other (the
   photo reloads on a move, which is expected). **Pass:** the picture follows
   within about a second and settles at a level that looks right; no flash of
   the SDR look, no jump to a wrong level that stays.
4. **E4. Open a photo from the grid.** Go back to the grid (Esc or
   double-click), then double-click a photo; do it for each of the three, and
   again after moving between photos with the arrow keys. **Pass:** at most one
   change, from the SDR look to HDR, shortly after it appears, and you find that
   change acceptable. Note: the first photo opened on a screen that gives less
   than the photo needs (the Dell) may change a second, smaller time about
   1.5 s later (DQ-1); later photos should not. Say whether that second change
   is acceptable.

Things this stage does not do, so not part of the check: the HDR check box,
menu item and badges of the design; the histogram (it shows the SDR version's
counts); the mask overlay, sharpening and fringe maps, and the crop session
(SDR, as today); side-by-side comparison (SDR); Distortion and spots with HDR
(the brightening does not follow them yet).

## Open questions

### Design questions (for apple-ui-designer)

**DQ-1. A second change on the first photo of a screen that gives less than
the photo needs.** What I hit: the display's headroom can only be read once the
layer asks for extended range, and the reading takes 1 to 2 s to settle
(Findings). Before it settles, the loupe renders for the potential headroom
capped at the photo's ceiling; when the display gives less (the Dell, 1.29), the
picture is rendered again about 1.5 s later. Options:
(a) accept it: it happens once per screen per launch (the limit is kept),
and Core Animation fits the picture in between, so the step is from the
system's fit to ours; cost none. (b) Keep the SDR preview up until the reading
settles on the first HDR photo of a screen: one change only, but HDR arrives
about 1.5 s later that once; cost small (a wait on the first visit). (c) Ask
for the ceiling with the SDR preview already in an extended layer, so the
reading settles before the HDR render lands; cost small, but untested: whether
an SDR image in a layer with `contentsHeadroom` set looks exactly like SDR, and
it spends the extended-range power on every gain-map photo before HDR shows.
Recommendation: (a) for now; decide after E4.

### Requirements issues (for the product manager)

None from this stage. For later, noted: design §5's reason 3 ("no HDR display",
potential headroom 1) does not cover a display that reports a potential above 1
and gives about 1.2 to 1.3 (the Dell here, or a background app under #287);
such a display shows HDR fitted to almost nothing. Whether that needs its own
reason is for after the early check.

## Next stage (after the owner's E1 to E4)

The rest of the PRD in the design's order, starting with the stored choice
(replacing the temporary switch), then badges and reasons, the HDR histogram,
overlays, maps and crop, comparison, the export notice, `photocli`, Distortion
and spots under the gain map (R19), AC6 for every adjustment and the Apple-only
gain map check, AC10's timings, and the user guide.

## README

Nothing for the README in this stage: no requirement, build command or layout
changed.

## User guide

Not updated: stage 1 changes nothing a person can reach without the
test-launch switch.
