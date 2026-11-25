# Some HEICs render brighter than Quick Look, and slider edits jump back: QA

Owner: qa-tester. Date: 2026-11-24. Step 4 of `docs/WORKFLOW.md`. Issue: #277.
Tested: `bug/heic-exposure-bright` at 8a76171, against `develop` at 139b39e,
on an Apple M4 Pro, macOS 27.2.1 (26B131), macOS 27.2 SDK, Swift 6.4.2.
Display: DELL U2723QE, potential EDR headroom 4.18.

## Verdict

**Passes. No findings.** Both symptoms reproduce on `develop` and are gone on
the branch: the owner's gain-map HEIC gets no HDR rendition anywhere in the
loupe, and the picture after a slider's release is pixel for pixel the one the
drag showed. PQ, HLG and floating-point DNG controls behave as on `develop`.
Open: five checks by eye (P1 to P5) and, from code review, Q1 (can CI's runners
encode HEIC), which only the pull request's CI run can settle.

## Acceptance criteria

B rows come from the **Bug** section of `status.md` (with ruling RI-1) and the
issue; D rows are the requirements in `review.md`. D1, D2 and D4 are covered by
B1, B2 and B4. D9 and D10 (user guide wording) were settled by the designer by
reading and need no run.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. An unedited gain-map photo shows its SDR rendition, as the system's SDR decode (D1) | Test | `GainMapRenditionTests` "A gain map alone gets no HDR rendition…" (HEIC and JPEG) and the opt-in "A real gain-map HEIC gets no HDR rendition" on a copy of the owner's file (−0.01 stops from ImageIO's SDR decode). Script S1: headroom none at open (2.73 on `develop`). `qlmanage -t` thumbnail and `photocli render` at 2560: mean luminance 0.2715 both | Pass |
| B2. A slider's edit stays on screen after release, at the drag's brightness (D2) | Script | S1: Exposure −1 and Highlights −100 are saved, and the photo's pixels after release equal the held drag's (0 pixels differ). Mean luminance, `develop` drag to release: 0.138 to 0.226, and 0.194 to 0.218; branch: 0.138 to 0.138, and 0.194 to 0.194. Supporting test: "A slider's release lands on the rendition its live frames showed" | Pass |
| B3. No stop-sized jump from values or views that had no HDR rendition: Contrast, Show Original, preset hover, arriving by arrow key, HDR setting | Script | S1 and S2, branch: headroom none at every step. Contrast +20 is 0.296 and back to 0 is 0.276 (`develop`: 0.296 and 0.315). Preset hover ends at 0.276, the photo's own value (`develop`: 0.312, against 0.137 while hovering Exposure −1). Arrival at 0.3 s and 6 s, and HDR off and on, give identical snapshots | Pass |
| B4. Floating-point DNGs and HLG or PQ images keep their HDR rendition (D4) | Test | "An HLG or PQ HEIC keeps its HDR rendition…" (four cases), `PreviewTests.hdrRenditionsKeepHighlightsAboveWhite`, `StalePreviewTests`. Script S2: PQ, HLG and DNG headrooms equal on `develop` and the branch at all 16 readings (PQ 4.11, HLG 4.09, DNG 2.96 at fit and 100%; HDR off none) | Pass |
| B5. Previews and exports render as before (no pipeline bump, no golden moved) | Script | S4: 30 `photocli render` cases (five files, three stacks, two sizes) on both builds; 29 identical bytes, one differed by at most 1 of 65535 and was run-to-run noise (see S4). The diff holds no golden and no `PreviewCacheKey` change | Pass |
| B6. The test named in the Bug section fails without the fix | Test | Branch tests in a scratch copy of `develop`: 10 issues in 12 tests (S5). Branch: full `swift test` 1533 tests in 216 suites pass; opt-in sample run passes | Pass |
| D3. No **HDR** badge on a gain-map photo | Script | S1 and S2: headroom none for the HEIC and a gain-map JPEG; snapshots show no badge. `develop` shows it | Pass |
| D5. Comparison panes follow the loupe, each side's badge its own | Script | S3: badges `[HDR]` on the merge, `[]` on the HEIC, with either side active; renditions `hdrPreview` and `preview`; both panes' snapshot luminance unchanged by switching (0.181 and 0.275). Look: P5 | Pass |
| D6. **View ▸ Show / Hide HDR Highlights** keeps its titles, enabled state and meaning | Person | P4. The setting behind it was scripted (S2: merge and PQ lose and regain HDR, HEIC unchanged); the menu item was not, because the app never became key (S3) | Open |
| D7. 100% shows the same rendition as fit | Script | S2: at 100% headroom none; drag 0.1586 and release 0.1586 (`develop`: 0.159 and 0.261). Look: P3 | Pass |
| D8. Grid, film strip, previews and loupe agree | Script | S2: over the whole photo, mean luminance is 0.276 for the grid thumbnail and 0.273 for the loupe at fit (under 0.02 stops). Look: P3 | Pass |
| The photo beside Quick Look on the display, with nothing brightening late | Person | P1 | Open |
| Real slider drags on the display: no visible flash or jump | Person | P2 | Open |
| 100%, thumbnails and fit look alike | Person | P3 | Open |
| HDR photos still glow above white, with badge and tooltip (D4's look) | Person | P4 | Open |
| Comparison on the extended-range display | Person | P5 | Open |

## Findings

None.

Notes, none of them a finding against this fix:

- **HLG still jumps (#283, out of scope).** The HLG control goes from HDR
  (4.09) to SDR while dragging and back to HDR (2.89) on release, the same on
  `develop` and the branch.
- **HDR photos leave HDR during a drag.** PQ and the DNG merge show no badge
  while a slider is held, on both builds, as the design review recorded.
- **First view against later frames.** On the branch the first view at open
  and the frame after an edit and reset differ slightly (mean 0.2756 against
  0.2763, about 0.004 stops; 0.7 % of the photo's pixels by more than 8 of
  255). `develop` with HDR highlights off gives the same snapshots pixel for
  pixel (open, drag, release, reset, Contrast), so it predates this branch.
- **Limits of the snapshots.** A snapshot draws an HDR layer into an SDR
  picture (highlights come out compressed), so `develop`'s HDR figures are not
  the display's brightness; its true gap was larger (`status.md`: +0.86 stops).
  The branch's gain-map figures are SDR pictures.
- **Code review Q1 stays open:** whether CI's virtual Macs can encode HEIC.

## Scripts

Bundles: `Scripts/build-app.sh` in the checkout, and in a `git archive develop`
tree outside it. Each was copied to a scratch folder, given the identifier
`me.sesser.gus.debugtest.qa277` (branch) or `…qa277dev` (`develop`) and signed
ad hoc. Every launch passed `--library-root`, on a fresh copy of a scratch
library.

The script library: a copy of the owner's HEIC; `control-gainmap.jpg`
(gain map only, twice the SDR light), `control-pq.heic` and `control-hlg.heic`
(a gray ramp with patches at 1, 2 and 4 times SDR white), written by a scratch
Swift script with Core Image (`jpegRepresentation` with `.hdrImage`,
`heif10Representation` in Display P3 PQ and HLG); and a synthetic bracket
merged to a floating-point DNG:

```
swift run -c release photobench generate --output GEN --jpeg 0 --dng 0 --heic 0 --pairs 0 --videos 0 --brackets 1
swift run -c release photobench import --library-root LIB --source PHOTOS
swift run photocli merge --version 2 --version 3 --version 4 --format dng --library-root LIB
```

(`PHOTOS` holds the three DNGs of `GEN/Brackets/Raw-0` beside the other files;
2 to 4 are their version ids from `photocli query images`.)

Run as `<copy>/Contents/MacOS/Gus --library-root LIB --debug-script "<script>"`,
the lines joined with spaces. `@SHOTS@` is a scratch folder. Luminance is the
mean of linear Display P3 luminance over the photo's rectangle in the
3600 x 2400 snapshot (x 1330, y 165, 1380 x 1845 at fit). Snapshots were
looked at before their checks were counted.

### S1: slider release, `develop` and branch

```
hdr on; windowsize 1800 1200; wait 2; focus IMG_0546; loupe; wait 6; print hdr; snapshot @SHOTS@/1-open.png;
adjust scrub exposure 0 -1 10 16 hold; wait 3; print hdr; snapshot @SHOTS@/2-exposure-drag.png;
adjust scrub exposure -1 -1 1; wait 6; print hdr; print adjustments; snapshot @SHOTS@/3-exposure-release.png;
adjust reset all; wait 5;
adjust scrub highlights 0 -100 10 16 hold; wait 3; print hdr; snapshot @SHOTS@/4-highlights-drag.png;
adjust scrub highlights -100 -100 1; wait 6; print hdr; print adjustments; snapshot @SHOTS@/5-highlights-release.png;
adjust reset all; wait 5; print hdr; snapshot @SHOTS@/6-reset.png;
adjust contrast 20; wait 6; print hdr; snapshot @SHOTS@/7-contrast20.png;
adjust contrast 0; wait 6; print hdr; print adjustments; snapshot @SHOTS@/8-contrast0.png;
quit
```

| Step | `develop` headroom, luminance | Branch headroom, luminance |
| --- | --- | --- |
| Open | 2.73, 0.315 | none, 0.276 |
| Exposure −1 held | none, 0.138 | none, 0.138 |
| Released | **1.37, 0.226** | none, 0.138 |
| Highlights −100 held | none, 0.194 | none, 0.194 |
| Released | **1.96, 0.218** | none, 0.194 |
| Reset | 2.73, 0.315 | none, 0.276 |
| Contrast +20 | **none, 0.296** | none, 0.296 |
| Contrast 0 | **2.73, 0.315** | none, 0.276 |

The saved stacks after release were `exposure.ev` −1 and `tone.highlights`
−100 on both. `develop`'s snapshots showed the brighter picture and the
**HDR** badge at open. The only pixels differing between a branch drag and its
release are the film strip's thumbnail taking the edit.

### S2: other loupe paths and HDR controls, `develop` and branch

```
hdr on; windowsize 1800 1200; wait 2; focus IMG_0546; loupe; wait 6; print hdr; snapshot @SHOTS@/fit.png;
key z; wait 20; print hdr; print loupe; snapshot @SHOTS@/zoom.png;
adjust scrub exposure 0 -1 10 16 hold; wait 3; print hdr; snapshot @SHOTS@/zoom-drag.png;
adjust scrub exposure -1 -1 1; wait 20; print hdr; snapshot @SHOTS@/zoom-release.png;
adjust reset all; wait 20; key z; wait 4; print hdr;
original on; wait 3; print hdr; snapshot @SHOTS@/original-on.png; original off; wait 4; print hdr; snapshot @SHOTS@/original-off.png;
adjust contrast 20; wait 2; preset save QAcontrast; wait 1; adjust exposure -1; adjust contrast 0; wait 2; preset save QAexposure; wait 1; adjust reset all; wait 5;
preset preview QAcontrast; wait 3; print hdr; snapshot @SHOTS@/preview-contrast.png; preset previewend; wait 4; print hdr; snapshot @SHOTS@/preview-contrast-end.png;
preset preview QAexposure; wait 3; print hdr; snapshot @SHOTS@/preview-exposure.png; preset previewend; wait 4; print hdr; snapshot @SHOTS@/preview-exposure-end.png;
key left; wait 5; print selection; key right; wait 0.3; print hdr; snapshot @SHOTS@/arrive-early.png; wait 6; print hdr; snapshot @SHOTS@/arrive-late.png;
grid; wait 5; snapshot @SHOTS@/grid.png;
focus control-gainmap; loupe; wait 6; print hdr; snapshot @SHOTS@/gainmap-jpeg.png; key z; wait 6; print hdr; key z; wait 2;
focus control-pq; wait 6; print hdr; snapshot @SHOTS@/pq.png; key z; wait 6; print hdr; key z; wait 3; hdr off; wait 4; print hdr; snapshot @SHOTS@/pq-hdroff.png; hdr on; wait 6; print hdr;
adjust scrub exposure 0 -0.5 5 16 hold; wait 3; print hdr; adjust scrub exposure -0.5 -0.5 1; wait 6; print hdr; adjust reset all; wait 5;
focus control-hlg; wait 6; print hdr; adjust scrub exposure 0 -0.5 5 16 hold; wait 3; print hdr; adjust scrub exposure -0.5 -0.5 1; wait 6; print hdr; adjust reset all; wait 5;
focus RAW_102_HDR; wait 8; print hdr; snapshot @SHOTS@/dng.png; key z; wait 10; print hdr; key z; wait 3; hdr off; wait 4; print hdr; snapshot @SHOTS@/dng-hdroff.png; hdr on; wait 8; print hdr;
adjust scrub exposure 0 -0.3 5 16 hold; wait 3; print hdr; adjust scrub exposure -0.3 -0.3 1; wait 8; print hdr; adjust reset all; wait 5; print hdr;
focus IMG_0546; wait 6; print hdr; hdr off; wait 4; print hdr; snapshot @SHOTS@/img-hdroff.png; hdr on; wait 6; print hdr; snapshot @SHOTS@/img-hdron.png;
quit
```

Loupe headroom in order (`none` means the SDR rendition):

| Readings | `develop` | Branch |
| --- | --- | --- |
| HEIC: fit, 100% | 2.73, 2.73 | none, none |
| HEIC: 100% held, released; fit | none, **1.36**; 2.73 | none, none; none |
| HEIC: Original on, off | none, 2.73 | none, none |
| HEIC: two preset hovers, each then ended | none, 2.73, none, 2.73 | none throughout |
| HEIC: arrival at 0.3 s, 6 s | 2.73, 2.73 | none, none |
| Gain-map JPEG: fit, 100% | 2.00, 2.00 | none, none |
| PQ: fit, 100%, off, on, held, released | 4.11, 4.11, none, 4.11, none, 2.91 | the same |
| HLG: fit, held, released | 4.09, none, 2.89 | the same |
| DNG: fit, 100%, off, on, held, released, reset | 2.96, 2.96, none, 2.96, none, 2.40, 2.96 | the same |
| HEIC again: on, off, on | 2.73, none, 2.73 | none, none, none |

The first `develop` run hit my script runner's time limit partway through the
DNG; it was rerun in full and the table is from the rerun.

### S3: comparison and menu, branch, activated

Launched with `open -W -n --stdout LOG <copy> --args --library-root LIB
--debug-script "…"` and brought forward once by process ID. macOS did not make
it key (`print responder` said `key nil`), on this and one earlier attempt, so
`menuitems HDR` printed `View/Hide HDR Highlights disabled` and the presses did
nothing. That says nothing about the app with a key window; it was not retried.
The comparison part ran:

```
hdr on; windowsize 1800 1200; wait 8; print responder; focus IMG_0546; loupe; wait 6; print hdr; menuitems HDR;
menupress Hide HDR Highlights; wait 5; menuitems HDR; print hdr;
menupress Show HDR Highlights; wait 5; menuitems HDR; print hdr;
focus RAW_102_HDR; wait 8; print hdr; menuitems HDR; snapshot @SHOTS@/dng-shown.png;
menupress Hide HDR Highlights; wait 5; menuitems HDR; print hdr; snapshot @SHOTS@/dng-hidden.png;
menupress Show HDR Highlights; wait 8; print hdr; menuitems HDR;
compare on; wait 4; compare active right; key right; wait 10; print compare; snapshot @SHOTS@/compare-right-active.png;
compare active switch; wait 6; print compare; snapshot @SHOTS@/compare-left-active.png;
compare active switch; wait 6; print compare;
menuitems HDR; menupress Hide HDR Highlights; wait 5; print compare; menupress Show HDR Highlights; wait 8; print compare;
compare off; wait 2; quit
```

It showed the merge on the left (`rendition hdrPreview`, `badges [HDR]`) and
the HEIC on the right (`rendition preview`, `badges []`), unchanged with either
side active.

### S4: previews and exports, both builds' `photocli`

For `IMG_0546.HEIC`, the gain-map JPEG, the PQ and HLG HEICs and the DNG merge,
with no edit, `--set exposure.ev=-1` and `--set tone.contrast=20`, at
`--long-edge 2560` and full size:

```
photocli render --input FILE --out OUT.png [--set …] [--long-edge 2560]
```

29 of 30 pairs were byte for byte equal. The PQ HEIC at −1 EV, 2560, differed
in 0.7 % of its values by 1 of 65535. Thirty more renders of that case per
build all gave one identical file (both builds), equal to the branch's first
one: the odd file was a single GPU rounding variation on the first `develop`
render, not a difference between the builds.

### S5: tests

Branch:

```
swift test
swift test --filter "GainMapRenditionTests|PreviewPipelineTests|StalePreviewTests"
HEIC_GAINMAP_SAMPLE=<copy of the owner's file> swift test --filter GainMapRenditionTests
```

Full suite: 1533 tests in 216 suites pass (75 s). The three suites: 15 tests
pass (the opt-in one skipped). The opt-in run: 4 tests pass (identity SDR mean
0.273, −0.01 stops; Exposure −1 0.137; Contrast +20 0.292).

Without the fix: a scratch copy of `develop` with the branch's
`GainMapRenditionTests.swift`, `PreviewTests.swift` and `HDRTestImages.swift`;
the one line calling `PreviewGenerator.hasHDREncoding` (new in the fix) was
removed from the test copy so it compiles, and no `develop` source changed.

```
HEIC_GAINMAP_SAMPLE=<copy> swift test --filter "GainMapRenditionTests|PreviewPipelineTests"
```

Failed with 10 issues: "A gain map alone…" 4 (HEIC and JPEG, fit and full),
"A slider's release…" 3 (Contrast has no HDR rendition either way), the real
sample 2 (identity and Exposure −1), and the gain-map line of
`hdrRenditionsKeepHighlightsAboveWhite` 1. The HLG and PQ cases pass on both.

### Safety

After the runs no instance was running; nothing under
`~/Library/Application Support/Gus` was newer than the start of the run, and
the app's own preferences file was last written before it. The owner's sample
in Downloads is unchanged (same SHA-256 and modification time). Scratch copies,
renders and snapshots of it were deleted, apart from the sign-off folder below.

## For a person

On the extended-range display, in HDR mode. M1 is done (2026-11-24); these
cover M2 to M7. No VoiceOver, macOS 15 or macOS 26 checks.

The scratch library is in `/Users/randy/gus-qa/heic-exposure-bright` (outside
the repository; delete the folder after the merge). It holds six photos: a copy
of `IMG_0546.HEIC`, `control-pq.heic` (an HDR file: gray ramp, three squares),
the synthetic frames `RAW_101` to `RAW_103`, and their DNG merge `RAW_102_HDR`.
It had no edits when handed over.

Build and start (quit any copy started earlier first):

```zsh
cd /Users/randy/Projects/Gus &&
git switch bug/heic-exposure-bright &&
Scripts/build-app.sh &&
Q=/Users/randy/gus-qa/heic-exposure-bright &&
rm -rf $Q/Gus-qa277.app &&
cp -R build/Gus.app $Q/Gus-qa277.app &&
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qa277 $Q/Gus-qa277.app/Contents/Info.plist &&
codesign --force --deep --sign - $Q/Gus-qa277.app &&
open -n $Q/Gus-qa277.app --args --library-root $Q/library
```

Start it again later (only this way):

```zsh
open -n /Users/randy/gus-qa/heic-exposure-bright/Gus-qa277.app --args --library-root /Users/randy/gus-qa/heic-exposure-bright/library
```

Show the same HEIC in Finder, for Quick Look (select it, press Space):

```zsh
open -R /Users/randy/gus-qa/heic-exposure-bright/photos/IMG_0546.HEIC
```

- **P1 (M2, M5). Open, against Quick Look.** Double-click `IMG_0546` and watch
  for a few seconds. Expect no brightening after it appears and no **HDR**
  badge at the bottom right. Put Quick Look beside it: same brightness. Press
  Left, then Right: no change after the photo arrives.
- **P2 (M2, M3). Sliders.** On the Adjust tab, drag Exposure to −1 and let go,
  then drag Highlights far left and let go: each time the picture stays where
  the drag left it. Set Contrast to +20, then Undo (⌘Z): only Contrast's own
  change, no big drop and return. Press `\` twice. Click **Save…** under
  Presets, then Reset All Adjustments (⋯ menu), hover the saved preset and move
  away: only the preset's own change.
- **P3 (M5). Fit, 100%, thumbnails.** Press Z for 100% and drag Exposure there
  too; release; Undo; press Z. The photo at 100%, at fit, in the film strip and
  in the grid has the same brightness.
- **P4 (M4, M6). HDR still works.** Open `RAW_102_HDR`: the window panes are
  brighter than the app's white text, with an **HDR** badge; resting the pointer
  on the badge shows "Highlights up to 3.0× SDR white…". Open `control-pq`:
  the middle and right squares glow brighter than the left one (which is SDR
  white), with the badge and a tooltip of about 4.1×. Choose **View ▸ Hide
  HDR Highlights**: the item is enabled and becomes **Show HDR Highlights**,
  both photos lose the glow and badge, and `IMG_0546` does not change (the item
  stays enabled on it). Choose **Show HDR Highlights**: glow and badge return.
- **P5 (M7). Comparison.** In the grid, ⌘-click so only `IMG_0546` and
  `RAW_102_HDR` are selected, press S. The badge is on the merge's side only.
  Press A twice: neither photo's brightness changes. Press S to leave.

## Follow-up

No reruns yet. Owner's sign-off (step 5): pending.
