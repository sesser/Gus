# Edit and show gain-map photos in HDR: QA

Owner: qa-tester. Date: 2026-11-25. Step 4 of `docs/WORKFLOW.md`. Issue #282.
Tested: `feature/gain-map-hdr-editing` at `60b95bd` (clean tree), on a Mac16,8
(M4 Pro), macOS 27.2.1 (26B131), macOS SDK 27.2, Swift 6.4.2. The
only screen the scripted app used reported potential headroom 4.18 (the external
display). Nothing here was looked at on a screen: no visual HDR result is
claimed. `snapshot` was used only for the SDR caption row and the Export sheet.

## Verdict

**Does not pass.** A photo that carries only Apple's kind of gain map is offered
HDR and labeled **HDR**, but shows its SDR brightness (Q1; AC5 and AC6 fail).
AC4 also fails in two places (Q2, Q3). The other criteria pass or wait for eyes.
The findings go to the engineer before the sign-off.

Full `swift test` at `60b95bd`: **1574 tests in 221 suites passed** (85.2 s),
goldens included. The HDR suites with #277's
(`GainMapHDRTests`, `GainMapAdjustmentTests`, `HDRChoiceTests`,
`HDRChoiceOutputTests`, `GainMapRenditionTests`; opt-in tests skipped there):
45 tests in 6 suites passed. `Scripts/build-app.sh` built the bundle (SDK
27.2). The CI toolchain build was not rerun (`status.md` records it).

After the runs: no instance of the app was running, and
`~/Library/Application Support/Gus/Library` had no file newer than the start of
QA.

## Acceptance criteria

Suites are in `Tests/PhotoCoreTests`. "S1" and so on are under Scripts. All
script and real-file results are for the owner's three HEICs (copies), which
carry **both** Apple's and the ISO 21496-1 gain map, unless a row says
otherwise.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| AC1 | Test, Script | `GainMapHDRTests` "A gain-map HEIC or JPEG has a gain map…", "AC1: only a HEIC or JPEG, by name and content…"; `HDRChoiceTests` "Off is the default…". S1: gain-map HEIC shows **SDR**, off, **HDR** box present; plain JPEG, raw (DNG), TIFF, video: no choice, no box; PQ HEIC: no choice, its own HDR rendition. S2: a library cataloged by a pre-v17 build (a copy of the early check's, schema v16) migrates to v17 with every photo off and **SDR** | Pass |
| AC2 | Test, Script | `HDRChoiceTests` "R2: the catalog keeps the choice…", "R2: a virtual copy…", "R2: Reset All…", "A batch change…". S3: kept across relaunch, undo and redo, History lists it, revert to an entry with it off shows SDR and Undo brings HDR back, Reset All off and undone. S4: pair file and copy independent | Pass |
| AC3 | Test, Script | `HDRChoiceTests` "AC3: presets and Paste Adjustments neither carry nor change the choice". S5: paste and preset in both directions | Pass |
| AC4 | Test, Script | `HDRChoiceTests` badge tests; `GainMapHDRTests` "Code review C1, C3…". S6, S7: every reason, 1.29 and 1.0 read **HDR** fitted, comparison panes, choice unchanged. S9: offline badges and help texts; a photo opened while offline has no check box. S10: short form seen in a narrow caption. **Fails**: a photo whose original goes away while open keeps a working **HDR** box (Q2); at the minimum window width the culling stars cover the warning mark (Q3). With Q1 the **HDR** label is shown over SDR brightness | **Fail** (Q2, Q3) |
| AC5 | Test, Script | `GainMapHDRTests` "…the system's HDR decode, in every orientation", "For a smaller headroom…" (ISO maps only). Opt-in sample test: +0.006, +0.001, +0.000 stops on the three files. S6: 2, 1.5, 1.29, 1.0 refit without reopening, still HDR. **Fails for Apple-only gain maps**: 0.84 to 0.94 stops under the system's HDR decode, no brightening at all (Q1) | **Fail** (Q1) |
| AC6 | Test | `GainMapAdjustmentTests` "AC6: every adjustment…" (24 cases pass). Opt-in on the three files: largest 0.046 stops RMS (contrast, IMG_0561), all under 0.05. **The Apple-only clause is not met**: none of the three files is Apple-only, and on Apple-only copies the test passes without any gain being applied (largest 0.0038 stops) (Q1, Q4). No Color Fringes case (Q4) | **Fail** (Q1, Q4) |
| AC7 | Test, Script | `GainMapHDRTests` "Once HDR is on screen…". S8: about 80 steps (every adjustment, Exposure −3, drags, 100%, Show Original, masks and overlay, spot, crop, turn, maps, preset preview, History revert, tabs, review, grid and back): stays HDR, `versions` never returns to SDR, no badge during a map. S11: undo and redo, at fit and 100%. S3: Undo of Turn On HDR, Reset All and a revert to an off entry show SDR. The preset preview was driven by `preset preview`, not a pointer. Not run on an Apple-only file | Pass |
| AC8 | Test, Person | `GainMapHDRTests` "A live HDR frame and the settled HDR render…" (identity, Exposure −1, Contrast +20, crop with turn and Straighten, within 0.005 stops), "A region frame at 100%…" (Exposure −0.5), "Review F5…". Opt-in sample: −0.0005 to −0.0010 stops. Not "for each adjustment" (Q5). By eye: P1 | Open |
| AC9 | Test, Script | `HDRChoiceOutputTests` "AC9: the HDR histogram counts values above white…", "The HDR histogram's bins…". S6: share above white 0.381 at 16, 2, 1.5, 1.29 and 1.0. S8: HDR counts through drags and releases | Pass |
| AC10 | Test | `GainMapTimingTests` rerun: HDR/SDR at fit 1.29, 1.23, 1.26; at 100% 1.02, 0.94, 0.95 (IMG_0546, 0542, 0561). Recorded in `status.md`, whose figures (up to 1.44) are also under 1.5 | Pass |
| AC11 | Test, Script | `HDRChoiceOutputTests` "AC11: previews and photocli render are the same bytes…"; every golden passes. S12: `photocli render --version` on a real file gives identical TIFF bytes with the choice on and off | Pass |
| AC12 | Test, Script | `HDRChoiceTests` "AC12: the export notice counts…". S13: "1 photo has HDR on. Exports are SDR.", "2 photos have HDR on. …", none for a plain JPEG; sheet snapshots show the line under the subtitle | Pass |
| AC13 | Test | `HDRChoiceOutputTests` "AC13: Auto Exposure, Auto White Balance and Color Alignment measure the same…" | Pass |
| AC14 | Test | `GainMapRenditionTests` (HLG and PQ), `PreviewTests` and the merge suites pass in the full run; none of those files changed on this branch. The user guide's HDR passage names the adjustments and says it does not happen to gain-map photos | Pass |
| AC15 | Test, Script | `HDRChoiceTests` "AC15: develop sets and resets…", "R17…". S12: set, read back, plain JPEG `invalidEdit`, moved original `fileNotFound`, reset | Pass |
| AC16 | n/a | Every check ran on macOS 27.2.1; nothing checks macOS 15 | Pass |
| AC17 | Test | `GainMapHDRTests` every orientation, "A region frame at 100%…"; `GainMapAdjustmentTests` "AC17: under Distortion…", "AC17: a healed or cloned spot…"; live and settled with crop, turn and Straighten | Pass |
| AC18 | Test, Person | `GainMapHDRTests` "Design §18.1…", "AC18: each screen's allowance…", "The display's headroom is a current reading…". S14: grid and comparison and back, `refits 0` (with an overridden reading, so it shows no second fit, not what a screen reports). By hand: P3 | Open |

Counts: 13 pass (4 by test alone: AC10, AC13, AC14, AC17; 8 by test and
script: AC1, AC2, AC3, AC7, AC9, AC11, AC12, AC15; AC16 n/a), 2 open for a
person (AC8, AC18), 3 fail (AC4, AC5, AC6).

### Designer's checks answered by script

- **M8** (narrow captions): run by snapshot. Short form and comparison pass;
  the minimum width fails (Q3). Not repeated for a person until Q3 is fixed.
- **M14** (export notice): S13. Its order above an issue line was not provoked
  (design review passed it by reading).
- **M15** (offline): S9, apart from Q2. The empty histogram of a photo first
  opened offline was seen (`hdr empty`), as design §19.4 accepts.
- **M17**, offline half: at 200% the magnification and visible rect were the
  same offline and after reconnecting (S9). The System Settings half is P5.
- **M16**, histogram half: at 100%, Show HDR filled the HDR histogram, and with
  Show Original and the mask overlay the tile followed 3 and 2 (S14). The look
  while following a real screen is P4.
- **M1**, in part: box only on gain-map photos (S1); menu title follows the
  choice, dimmed on a plain JPEG and in the grid (S15). Dimmed while comparing
  and cropping was not verified: macOS would not activate the app for the later
  runs (`key nil`). In P10.

## Findings

### Q1. A photo with only Apple's gain map is labeled HDR and shows SDR brightness (high)

R6, R4, AC5, AC6; PRD Terms ("a gain map macOS reads").

Which files: HEIC or JPEG carrying Apple's gain map and no ISO 21496-1 one. I
believe iPhone photos taken before iOS 18 are such files; that was not verified.
The owner's three files carry both, so neither the early check nor any run so
far could show this.

Steps (zsh, with absolute paths; the copy renames the `tmap` code, which hides
the ISO map and leaves every other byte):

`hide_tmap.py`:

```python
import sys
data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(data.replace(b"tmap", b"xxxx"))
```

```zsh
python3 -I hide_tmap.py IMG_0546.HEIC APPLE_0546.HEIC
```

```zsh
HEIC_GAINMAP_SAMPLE=APPLE_0546.HEIC swift test --filter "GainMapHDRTests/sample"
```

Then catalog the copy in a scratch library, open it in the loupe and turn HDR on
(S1b).

Expected: the unedited HDR version matches the system's HDR decode within 0.05
stops.

Actual:

| File (Apple-only) | Ours, mean | System HDR decode | Difference |
| --- | --- | --- | --- |
| from IMG_0546 | 0.276 | 0.495 | −0.844 stops |
| from IMG_0542 | 0.051 | 0.097 | −0.940 |
| from IMG_0561 | 0.356 | 0.647 | −0.860 |
| JPEG written by ImageIO from the first, Apple map and maker data only | 0.275 | 0.495 | −0.845 |

In the app (HEIC and JPEG copies): badge `hdr`, `rendered 2.62`, help "…brightens
up to 2.6× SDR white", `histogram hdr above white 0.000`. The same photo with
both maps: `0.128`. Our means equal the SDR render's (0.273 for IMG_0546).

Likely cause (from a probe, not a change to the code): Core Image's
`applyingGainMap` needs the receiving image's own properties (the Apple maker
dictionary) for an Apple map. On the file's `CIImage` as loaded it gives the
system's mean (0.6474 against 0.6474); on the same image after
`settingProperties([:])` it gives SDR (0.3567). `GainMap.hdr` applies the map to
the rendered, clamped picture, and `GainMap.ceiling` to a plain white image;
neither carries those properties (`Preview/GainMap.swift`). An ISO map keeps its
metadata on the map, so it works.

The spike's level dependence for an Apple-only map (up to 0.04 stops RMS) was
measured on a file that carries both, so AC6's drift for a truly Apple-only file
is unmeasured and needs a run after the fix.

### Q2. A photo that goes offline while open can still have its HDR choice changed (medium)

AC4 ("With the original offline, the loupe offers no way to change the choice"),
design §2.1, user guide.

Steps: S9b. Library on a disk image; open a photo, turn HDR on, eject the image
with the photo open, click the **HDR** box.

Expected: no box (or a disabled one), and the menu item dimmed.

Actual: badge **SDR** (`sdr offline`), the box still shown, enabled and checked.
A click turned HDR off: History gained **Turn Off HDR** and the catalog stack
lost the `hdr` operation. The badge then reads `sdr cached`, whose help says the
HDR version needs the original, with the box still enabled. A photo **opened**
while offline is right (no Adjust header). The menu item was not verified (app
not key); by reading, `canSetHDR` (`LibraryMenuContext.swift`) has no offline
condition. The rest of the Adjust tab also stays enabled after the volume goes,
which is older than this branch.

### Q3. At the minimum window width the culling marks cover the version badge (low)

R4, AC4's last clause, design §5 ("the badges never run into the culling marks"),
M8.

Steps: S10. Window 760 pt wide (the minimum), sidebar and inspector shown, a
gain-map photo rated 5 stars.

Actual:
- HDR on with **View ▸ Hide HDR**: the fifth star is drawn over the warning
  mark.
- The same as a virtual copy, in HDR or hidden: the stars cover the version
  badge (the warning mark is unreadable) and **Copy** collapses to an empty box.
- Choice off with **SDR**, and **HDR**, on a photo with no second badge: fit.
- 900 pt and 1000 pt: fit. Comparison at 760 pt: the version badge is whole.
- A plain JPEG copy at 760 pt truncates **Copy** to "…" without overlapping, so
  the overlap comes with the version badge.

### Q4. AC6's tests miss a case and cannot fail for an unapplied gain map (medium; missing tests)

- No test file is Apple-only: `HDRTestImages` writes ISO maps. Q1 passes the
  whole suite.
- "AC6 on real files…" checks only ratio drift. With no gain applied, HDR equals
  SDR and every drift is near zero: it passed 72 of 72 cases on Apple-only
  copies. It should also require the unedited HDR version to match the system's
  decode, or to exceed white.
- `status.md` (and the spike) call IMG_0561 Apple-only. Its container has a
  `tmap` item, ImageIO on this Mac reports an ISO gain map for it, and the test
  itself prints `ISO`. The AC6 and AC10 notes should say so.
- No **Color Fringes** case in "AC6: every adjustment…" (S8 only shows that
  filling a slot leaves the picture HDR with values above white).
- AC6 names an identity look-up table; the case uses a built-in table at 1%.

### Q5. AC8 is automated for a few stacks only (low; missing test)

AC8 says "for each adjustment" at fit and at 100%. The tests compare four stacks
at fit (identity, Exposure, Contrast, crop) and one at 100% (Exposure). No test
compares a live and a settled HDR frame for sharpening, noise reduction, grain,
clarity, masks, spots, lens corrections or the rest.

### For the product manager (no ruling needed to fix the above)

The PRD's Dependencies give 0.04 stops for "a file with only Apple's" kind of
gain map. The file measured carries both (Q4).

## Scripts

All runs used a copy of `build/Gus.app` with the identifier
`me.sesser.gus.debugtest.qa282`, scratch libraries, and copies of the owner's
photos (deleted after QA). `$R` is a scratch folder; every launch was

```zsh
$R/Gus-qa282.app/Contents/MacOS/Gus --library-root $R/<library> --debug-script "<script>"
```

except S15 (`open -W -n --stdout <log> $R/Gus-qa282.app --args --library-root …`).
**View ▸ Hide HDR** is a preference and survives between runs of one bundle:
`hdr off` in one script hides HDR in the next until `hdr on`.

Libraries (each `swift run -c release photobench import --library-root $R/<library> --source $R/<folder>`):

- `photos2`: IMG_0546, IMG_0542, IMG_0561 (`.HEIC`); `PAIR.HEIC` (IMG_0561 with
  an empty `free` box appended, so it isn't a duplicate) beside `PAIR.dng`, and
  `PLAIN.jpg` (`photobench scenes` dusty sky). Each script from S3 on used a
  fresh import unless it says it follows another.
- `photos`: the three HEICs, `APPLE_0546.HEIC`, `APPLEJ_0546.jpg` (Q1),
  `PLAIN.jpg`, `RAWFILE.dng`, `SCENE.tif`, `PQFILE.heic` (`control-pq.heic`), a
  `photobench` video.

### S1: which files have the choice (`photos`)

```
wait 2; focus IMG_0546; loupe; wait 4; tab adjust; wait 1; print hdr; buttons; menuitems HDR; focus PLAIN; wait 3; print hdr; buttons; menuitems HDR; focus RAWFILE; wait 4; print hdr; buttons; focus SCENE; wait 3; print hdr; buttons; focus PQFILE; wait 3; print hdr; buttons; focus VIDEO; wait 3; print hdr; buttons; menuitems HDR; quit
```

```
wait 2; focus IMG_0546; loupe; wait 2; inspector on; tab adjust; wait 4; print inspector; buttons; snapshot $R/a-adjust.png; focus PLAIN; wait 4; print inspector; buttons; focus RAWFILE; wait 5; buttons; quit
```

`has choice true`, off, badge `sdr` for the HEIC; `has choice false` for the
others (PQ shows `shown hdr` with badge `none`: its own rendition). Button `HDR`
(state off, with the design's help tag) after `Original` only on the HEIC.

### S1b: HDR on, both maps against Apple-only (`photos`)

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 6; print hdr; focus APPLE_0546; wait 4; print hdr; adjust hdr on; wait 6; print hdr; focus APPLEJ_0546; wait 3; adjust hdr on; wait 6; print hdr; focus IMG_0561; wait 3; adjust hdr on; wait 6; print hdr; focus IMG_0542; wait 3; adjust hdr on; wait 6; print hdr; quit
```

Share above white: IMG_0546 0.128, APPLE_0546 0.000, APPLEJ_0546 0.000,
IMG_0561 0.381, IMG_0542 0.021. All badge `hdr`, `versions sdr,hdr`.

### S2: an already cataloged library (copy of the early check's, schema v16)

```
wait 2; hdr on; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 4; print hdr; focus IMG_0561; wait 4; print hdr; focus IMG_0542; wait 4; print hdr; quit
```

Choice off, badge `sdr` on all three; afterwards the catalog is at v17 with
`version.hdr` 0.

### S3: persistence, undo, History, Reset All (two runs, one library)

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust exposure 0.2; wait 1; adjust hdr on; wait 5; print hdr; print undo; history open; history wait; history; quit
```

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 6; print hdr; adjust hdr off; wait 3; print undo; print hdr; undo; wait 5; print hdr; print undo; redo; wait 3; print hdr; undo; wait 5; print hdr; history open; history wait; history; history revert 3; wait 4; history wait; history; print hdr; undo; wait 5; print hdr; adjust reset all; wait 3; print hdr; history wait; history; undo; wait 5; print hdr; quit
```

Run 2 opens with the choice on. States in order: on, off, on, off, on; revert to
**Turn Off HDR** off; undo on; **Reset Adjustments** off; undo on. History lists
each, with **Turn On HDR** and **Turn Off HDR**.

### S4: pair file and virtual copy

```
wait 2; hdr display 16; pairs grouped; print items; focus PAIR; loupe; inspector on; tab adjust; wait 4; print hdr; pairfile jpeg; wait 4; adjust hdr on; wait 5; print hdr; pairfile raw; wait 5; print hdr; pairfile jpeg; wait 5; print hdr; focus IMG_0546; wait 3; adjust hdr on; wait 4; duplicate; wait 2; print copies; adjust hdr off; wait 3; print hdr; print copies; quit
```

Same library, then:

```
wait 2; hdr display 16; focus 1; loupe; inspector on; tab adjust; wait 5; print hdr; focus 2; wait 5; print hdr; focus 1; wait 3; duplicate; wait 4; print hdr; print copies; quit
```

Raw file: no choice, before and after the HEIC file was turned on; the HEIC kept
it. Turning the copy off left the original on.

### S5: paste and presets

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust exposure 0.5; adjust hdr on; wait 4; copyadjust all; preset save HDRsource; focus IMG_0542; wait 4; pasteadjust; wait 4; print hdr; print stacks; preset apply HDRsource; wait 3; print hdr; adjust exposure -0.5; wait 1; copyadjust all; preset save SDRsource; focus IMG_0546; wait 5; pasteadjust; wait 4; print hdr; print stacks; preset apply SDRsource; wait 4; print hdr; adjust reset all; wait 2; adjust hdr on; wait 4; preset apply HDRsource; wait 4; print hdr; quit
```

The SDR target stayed off after paste and preset (stack `[exposure]`); the HDR
target stayed on.

### S6: headroom, reasons, histogram

```
wait 2; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 5; print hdr; hdr display 2; wait 3; print hdr; hdr display 1.5; wait 3; print hdr; hdr display 1.29; wait 3; print hdr; hdr display 1.0; wait 3; print hdr; hdr display system; wait 3; print hdr; hdr display 16; wait 3; hdr off; wait 3; print hdr; buttons; hdr on; wait 4; print hdr; hdr display sdr; wait 3; print hdr; hdr display flat; wait 3; print hdr; hdr display 16; wait 4; print hdr; hdr fail on; focus PLAIN; wait 3; focus IMG_0561; wait 5; print hdr; hdr fail off; wait 3; print hdr; focus PLAIN; wait 3; focus IMG_0561; wait 5; print hdr; quit
```

`rendered` 4.57, 2.00, 1.50, 1.29, 1.00 with badge `hdr fitted` and both numbers
in the help; `changes 1` throughout. `sdr hidden`, `sdr noHDRDisplay` (`sdr` and
`flat`), `sdr failed` (stays until reopened); box still checked; HDR returns.

### S7: comparison

```
wait 2; compare animate off; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 4; compare on; wait 3; print compare; compare active right; wait 2; print compare; compare active left; wait 2; print compare; hdr display 1.29; wait 3; print compare; hdr display 1.0; wait 3; print compare; hdr display 16; hdr off; wait 3; print compare; hdr on; wait 4; print compare; hdr display sdr; wait 3; print compare; hdr display flat; wait 3; print compare; hdr display 16; wait 4; print compare; hdr fail on; compare off; focus PLAIN; wait 2; focus IMG_0546; wait 2; compare on; wait 4; print compare; hdr fail off; compare off; focus PLAIN; wait 2; focus IMG_0546; wait 4; print hdr; compare on; wait 4; print compare; menuitems HDR; compare off; wait 3; print hdr; grid; wait 1; loupe; wait 3; print hdr; quit
```

Each pane states its own version and reason, in its badge and VoiceOver value;
the inspector histogram is HDR only with the HDR pane active and HDR shown.

### S8: AC7, every adjustment (follows S6's library, IMG_0561 on)

```
wait 2; hdr display 2; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; print STEP-arrival; print hdr; adjust temperature 4000; wait 1.2; print STEP-adjust_temperature_4000; print hdr; adjust tint 20; wait 1.2; print STEP-adjust_tint_20; print hdr; adjust exposure 1.0; wait 1.2; print STEP-adjust_exposure_1.0; print hdr; adjust contrast 60; wait 1.2; print STEP-adjust_contrast_60; print hdr; adjust highlights -60; wait 1.2; print STEP-adjust_highlights_-60; print hdr; adjust shadows 40; wait 1.2; print STEP-adjust_shadows_40; print hdr; adjust whites 30; wait 1.2; print STEP-adjust_whites_30; print hdr; adjust blacks -30; wait 1.2; print STEP-adjust_blacks_-30; print hdr; adjust clarity 50; wait 1.2; print STEP-adjust_clarity_50; print hdr; adjust dehaze 40; wait 1.2; print STEP-adjust_dehaze_40; print hdr; adjust vibrance 40; wait 1.2; print STEP-adjust_vibrance_40; print hdr; adjust saturation 30; wait 1.2; print STEP-adjust_saturation_30; print hdr; adjust curve rgb 0,0 0.25,0.15 0.75,0.85 1,1; wait 1.2; print STEP-adjust_curve_rgb_0,0_0.25,0.15_0.75,0.85_1,1; print hdr; adjust mix orange 0 60 0; wait 1.2; print STEP-adjust_mix_orange_0_60_0; print hdr; adjust bw on; wait 1.2; print STEP-adjust_bw_on; print hdr; adjust bw filter red; wait 1.2; print STEP-adjust_bw_filter_red; print hdr; adjust bw off; wait 1.2; print STEP-adjust_bw_off; print hdr; adjust grade highlights 40 60; wait 1.2; print STEP-adjust_grade_highlights_40_60; print hdr; lut Warm; wait 1.2; print STEP-lut_Warm; print hdr; adjust intensity 80; wait 1.2; print STEP-adjust_intensity_80; print hdr; adjust vignette -60; wait 1.2; print STEP-adjust_vignette_-60; print hdr; adjust grain 50; wait 1.2; print STEP-adjust_grain_50; print hdr; adjust amount 100; wait 1.2; print STEP-adjust_amount_100; print hdr; adjust masking 50; wait 1.2; print STEP-adjust_masking_50; print hdr; adjust luminance-nr 50; wait 1.2; print STEP-adjust_luminance-nr_50; print hdr; adjust color-nr 40; wait 1.2; print STEP-adjust_color-nr_40; print hdr; lens vignetting manual; wait 1.2; print STEP-lens_vignetting_manual; print hdr; lens vignetting amount 50; wait 1.2; print STEP-lens_vignetting_amount_50; print hdr; lens distortion manual; wait 1.2; print STEP-lens_distortion_manual; print hdr; lens distortion amount 40; wait 1.2; print STEP-lens_distortion_amount_40; print hdr; adjust fringe fill 1 purple; wait 1.2; print STEP-adjust_fringe_fill_1_purple; print hdr; adjust fringe tolerance 1 50; wait 1.2; print STEP-adjust_fringe_tolerance_1_50; print hdr; adjust align redcyan 10; wait 1.2; print STEP-adjust_align_redcyan_10; print hdr; adjust off light; wait 1.2; print STEP-adjust_off_light; print hdr; adjust on light; wait 1.2; print STEP-adjust_on_light; print hdr; adjust exposure -3; wait 1.2; print STEP-adjust_exposure_-3; print hdr; adjust exposure 0; wait 1.2; print STEP-adjust_exposure_0; print hdr; adjust scrub exposure -1 1 20 30 hold; wait 1.2; print STEP-adjust_scrub_exposure_-1_1_20_30_hold; print hdr; adjust scrub exposure 1 0.2 10 30; wait 1.2; print STEP-adjust_scrub_exposure_1_0.2_10_30; print hdr; zoom; wait 2.5; print STEP-zoom; print hdr; adjust scrub exposure 0.2 -0.5 10 30; wait 1.2; print STEP-adjust_scrub_exposure_0.2_-0.5_10_30; print hdr; original on; wait 1.2; print STEP-original_on; print hdr; original off; wait 1.2; print STEP-original_off; print hdr; adjust scrub contrast 60 20 10 30; wait 1.2; print STEP-adjust_scrub_contrast_60_20_10_30; print hdr; zoom; wait 2.5; print STEP-zoom; print hdr; adjust mask add radial; wait 1.2; print STEP-adjust_mask_add_radial; print hdr; adjust mask set exposure 1; wait 1.2; print STEP-adjust_mask_set_exposure_1; print hdr; adjust mask overlay on; wait 1.2; print STEP-adjust_mask_overlay_on; print hdr; adjust mask overlay off; wait 1.2; print STEP-adjust_mask_overlay_off; print hdr; adjust mask add brush; wait 1.2; print STEP-adjust_mask_add_brush; print hdr; adjust mask brush 0.2 0.2 0.4 0.4 0.6 0.5; wait 1.2; print STEP-adjust_mask_brush_0.2_0.2_0.4_0.4_0.6_0.5; print hdr; adjust mask overlay off; wait 1.2; print STEP-adjust_mask_overlay_off; print hdr; adjust mask select none; wait 1.2; print STEP-adjust_mask_select_none; print hdr; spots on; wait 1.2; print STEP-spots_on; print hdr; spot add 0.5 0.5; wait 2.5; print STEP-spot_add_0.5_0.5; print hdr; spots off; wait 1.2; print STEP-spots_off; print hdr; adjust crop begin; wait 2.5; print STEP-adjust_crop_begin; print hdr; adjust crop rect 0.1 0.1 0.8 0.8; wait 1.2; print STEP-adjust_crop_rect_0.1_0.1_0.8_0.8; print hdr; adjust crop angle 3; wait 1.2; print STEP-adjust_crop_angle_3; print hdr; adjust crop done; wait 2.5; print STEP-adjust_crop_done; print hdr; adjust crop begin; wait 2.5; print STEP-adjust_crop_begin; print hdr; adjust crop cancel; wait 1.2; print STEP-adjust_crop_cancel; print hdr; adjust crop turn right; wait 1.2; print STEP-adjust_crop_turn_right; print hdr; sharpenmap on; wait 1.2; print STEP-sharpenmap_on; print hdr; sharpenmap off; wait 1.2; print STEP-sharpenmap_off; print hdr; fringemap on; wait 1.2; print STEP-fringemap_on; print hdr; fringemap off; wait 1.2; print STEP-fringemap_off; print hdr; preset save QA; wait 1.2; print STEP-preset_save_QA; print hdr; adjust exposure 0.7; wait 1.2; print STEP-adjust_exposure_0.7; print hdr; preset preview QA; wait 1.2; print STEP-preset_preview_QA; print hdr; preset previewend; wait 1.2; print STEP-preset_previewend; print hdr; undo; wait 1.2; print STEP-undo; print hdr; undo; wait 1.2; print STEP-undo; print hdr; redo; wait 1.2; print STEP-redo; print hdr; history open; wait 1.2; print STEP-history_open; print hdr; history revert 3; wait 1.2; print STEP-history_revert_3; print hdr; tab info; wait 1.2; print STEP-tab_info; print hdr; tab adjust; wait 1.2; print STEP-tab_adjust; print hdr; review on; wait 1.2; print STEP-review_on; print hdr; review off; wait 1.2; print STEP-review_off; print hdr; print adjustments; grid; wait 1; loupe; wait 3; print STEP-grid-and-back; print hdr; quit
```

Every step: choice on, `shown hdr`, `hdr fitted` (maps: badge `none`, SDR map
frame, then `hdr fitted` again), inspector histogram `hdr`; at Exposure −3 the
share above white is 0.000 and the version stays HDR. The two `undo` and one
`redo` after the preset preview changed nothing (the script's preview commands
leave empty undo steps), so undo is shown by S11.

### S9: offline (`$R/qa282.dmg`, FAT32, library of the three HEICs and PLAIN.jpg on it)

A helper started the app and ran `hdiutil detach /Volumes/QA282 -force` when the
output reached `print DETACH`, and `hdiutil attach $R/qa282.dmg -nobrowse` at
`print ATTACH`.

```
wait 2; hdr on; hdr display 16; focus IMG_0542; loupe; inspector on; tab adjust; wait 4; focus IMG_0546; wait 4; adjust hdr on; wait 5; zoomstep; zoomstep; zoomstep; zoomstep; wait 3; pan 400 300; wait 2; print STEP-online; print hdr; print loupe; print DETACH; wait 8; print STEP-offline; print hdr; print loupe; menuitems HDR; buttons; focus PLAIN; wait 3; focus IMG_0546; wait 4; print STEP-offline-return; print hdr; focus IMG_0542; wait 3; print STEP-offline-off-known; print hdr; focus IMG_0561; wait 3; print STEP-offline-off-unknown; print hdr; focus IMG_0546; wait 3; zoomstep; zoomstep; zoomstep; zoomstep; wait 2; pan 400 300; wait 2; print STEP-offline-before-attach; print hdr; print loupe; print ATTACH; wait 10; print STEP-reattached; print hdr; print loupe; quit
```

`sdr offline` (HDR in memory not shown); off and known: `sdr cached`; off and
never read: no badge; reattached with the photo open (reopened while offline):
`shown hdr`, badge `hdr`, histogram `hdr empty`; 200% and the visible rect
unchanged.

S9b (Q2), same library, attached again:

```
wait 2; hdr on; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; adjust hdr on; wait 5; print STEP-online; print hdr; print DETACH; wait 8; print STEP-offline; print hdr; buttons; click 580 202; wait 4; print STEP-after-click; print hdr; print undo; buttons; history open; wait 2; history; print STEP-end; print hdr; quit
```

(`580 202` is the box in that window; take it from `buttons`.) Then, still
detached:

```
wait 2; hdr on; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 4; print STEP-opened-offline-on; print hdr; buttons; focus IMG_0561; wait 3; print STEP-opened-offline-off; print hdr; buttons; quit
```

No **Original** or **HDR** button; `sdr offline`.

### S10: narrow captions (Q3)

```
wait 2; hdr display 16; focus IMG_0561; loupe; inspector on; wait 3; windowsize 760 560; wait 2; key 5; wait 2; tab adjust; adjust hdr on; wait 5; print hdr; snapshot $R/b-min-hdr-5.png; duplicate; wait 5; print hdr; snapshot $R/b-min-hdr-copy.png; hdr off; wait 2; print hdr; snapshot $R/b-min-hidden-copy.png; quit
```

Run after a script that had left HDR hidden (the fifth star over the warning
mark, no copy):

```
wait 2; hdr display 16; focus IMG_0561; loupe; inspector on; wait 3; windowsize 760 560; wait 2; key 5; wait 2; snapshot $R/min-sdr-5.png; tab adjust; adjust hdr on; wait 5; snapshot $R/min-hdr-5.png; duplicate; wait 4; snapshot $R/min-hdr-copy.png; hdr off; wait 2; snapshot $R/min-hidden-copy.png; windowsize 900 600; wait 2; snapshot $R/w900-hidden-copy.png; windowsize 1000 640; wait 2; snapshot $R/w1000-hidden-copy.png; windowsize 760 560; wait 1; hdr on; focus PLAIN; wait 3; key 5; wait 1; duplicate; wait 4; snapshot $R/min-plain-copy.png; quit
```

Comparison caption (in S13's second script).

### S11: undo and redo (follows S8's library)

```
wait 2; hdr display 2; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; adjust exposure -1; wait 2; print STEP-ev-1; print hdr; adjust exposure 1; wait 2; print STEP-ev1; print hdr; print undo; undo; wait 3; print STEP-undo; print hdr; redo; wait 3; print STEP-redo; print hdr; zoom; wait 3; undo; wait 3; print STEP-undo-at-100; print hdr; redo; wait 3; print STEP-redo-at-100; print hdr; quit
```

HDR throughout; share above white 0.082, 0.470, 0.082, 0.470, and the same at
100%.

### S12: `photocli` (library of IMG_0542, IMG_0546, PLAIN.jpg; app closed)

Each with `--library-root $R/lib7`:

```zsh
swift run photocli develop --version 2 --set hdr.on=true --library-root $R/lib7
swift run photocli query images --library-root $R/lib7
swift run photocli develop --version 3 --set hdr.on=true --library-root $R/lib7
swift run photocli render --version 2 --library-root $R/lib7 --out $R/on.tiff --long-edge 1024
swift run photocli develop --version 2 --set hdr.on=false --library-root $R/lib7
swift run photocli render --version 2 --library-root $R/lib7 --out $R/off.tiff --long-edge 1024
cmp $R/on.tiff $R/off.tiff
swift run photocli develop --version 2 --set hdr.on=true --library-root $R/lib7
swift run photocli develop --version 2 --reset hdr --library-root $R/lib7
mv $R/photos7/IMG_0542.HEIC $R/IMG_0542.away
swift run photocli develop --version 1 --set hdr.on=true --library-root $R/lib7
```

### S13: export notice

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 4; export window; export print; export windowshot $R/export1.png; export close; focus IMG_0561; wait 3; adjust hdr on; wait 4; grid; wait 1; selectall; wait 1; export window; export print; export windowshot $R/export2.png; export close; focus PLAIN; wait 1; export window; export print; export windowshot $R/export0.png; export close; focus IMG_0561; loupe; wait 4; hdr off; wait 2; snapshot $R/caption-wide.png; windowsize 900 600; wait 2; snapshot $R/caption-narrow.png; windowsize 760 520; wait 2; print hdr; snapshot $R/caption-narrower.png; duplicate; wait 3; rating any; key 5; wait 1; flag any; wait 1; snapshot $R/caption-copy.png; compare on; wait 3; snapshot $R/caption-compare.png; print compare; quit
```

Nothing was exported (`export run` was not used).

### S14: 100% and returning to the loupe

```
wait 2; compare animate off; hdr on; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 5; grid; wait 1; hdr off; loupe; wait 4; zoom; wait 4; print STEP-100-hidden; print hdr; hdr on; wait 6; print STEP-100-shown; print hdr; original on; wait 3; hdr display 3; wait 3; print STEP-original-3; print hdr; hdr display 2; wait 3; print STEP-original-2; print hdr; original off; adjust mask add radial; adjust mask overlay on; wait 3; print STEP-overlay-2; print hdr; hdr display 3; wait 3; print STEP-overlay-3; print hdr; adjust mask overlay off; zoom; wait 3; grid; wait 1; loupe; wait 4; print STEP-grid-back; print hdr; compare on; wait 3; compare off; wait 3; print STEP-compare-back; print hdr; quit
```

After Show HDR at 100%: histogram `hdr above white 0.381`. Tile 3.00, 2.00, then
2.00, 3.00. `refits 0` throughout. (Comparison ends on the other pane's photo, a
plain JPEG, hence its last SDR line.)

### S15: menu state (activated)

```
wait 2; compare animate off; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 5; print responder; menuitems HDR; focus PLAIN; wait 2; menuitems HDR; focus IMG_0561; wait 3; menuitems HDR; menupress Turn On HDR; wait 4; print STEP-menu-on; print hdr; print undo; menuitems HDR; menupress Turn Off HDR; wait 3; print STEP-menu-off; print hdr; print undo; grid; wait 2; menuitems HDR; quit
```

(These are the head of a longer script, cut after the last command that ran with
a key window.) Key window: **Turn Off HDR** enabled on the photo with HDR on;
**Turn On HDR** disabled on the plain JPEG, enabled on a gain-map photo with it
off; the menu item turns it on and off with undo names **Turn On HDR** and
**Turn Off HDR**; disabled in the grid. Two further activated runs for the
comparing, cropping and Reset All menu states stayed `key nil` and were not
retried.

## For a person

On the final build, after the findings are fixed. Most important first. The early
check of 2026-11-25 (design §13.1) is recorded as passed, with the second change
on arrival accepted; it used a first-stage build, and its record does not say
which display or photo each check used. VoiceOver, macOS 15 and macOS 26 are
left to CI.

### Setup

A fresh library is ready at
`/Users/randy/gus-qa/gain-map-hdr-editing/signoff/library` (copies of the three
photos in `signoff/photos`, every HDR choice off). The early check's app copy,
library and photos beside it are untouched. Quit any running copy of the app,
then run in order:

```zsh
cd /Users/randy/Projects/Gus
```

```zsh
Scripts/build-app.sh
```

```zsh
rm -rf /Users/randy/gus-qa/gain-map-hdr-editing/signoff/Gus-signoff.app
```

```zsh
cp -R /Users/randy/Projects/Gus/build/Gus.app /Users/randy/gus-qa/gain-map-hdr-editing/signoff/Gus-signoff.app
```

```zsh
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.gainmap282signoff /Users/randy/gus-qa/gain-map-hdr-editing/signoff/Gus-signoff.app/Contents/Info.plist
```

```zsh
codesign --force --deep --sign - /Users/randy/gus-qa/gain-map-hdr-editing/signoff/Gus-signoff.app
```

```zsh
open -n /Users/randy/gus-qa/gain-map-hdr-editing/signoff/Gus-signoff.app --args --library-root /Users/randy/gus-qa/gain-map-hdr-editing/signoff/library
```

To start it again, use only that last command. Never open the copy by
double-click: it would open the real library.

The files go up to 2.6× (IMG_0546), 3.7× (IMG_0542) and 4.6× (IMG_0561) SDR
white. The **HDR** badge's help tag says what the display allows now when that is
less than the file. The external display allowed about 1.3× during the build, so
HDR looking close to SDR there is expected.

| P | Do | Pass looks like | Covers |
| --- | --- | --- | --- |
| P1 | Turn HDR on for IMG_0561 and IMG_0546. Once with the badge's help tag showing no display limit (built-in display), once on a display that allows less than the file. At fit, then at 100% (`Z`): drag and release Exposure, Contrast, a Tone Curve point, Sharpening to its maximum, and a radial mask's Exposure. Press **Original** | Brightness and color do not shift while dragging or on release, away from the edit too. A frame may be soft while moving. **Original** is the unedited photo, still HDR | AC8; `status.md` item 3; E2 repeated |
| P2 | With all three on: turn one off and on, by the box and by `⌘Z`, at fit and at 100%. Arrow through the three and back several times; go to the grid and back | At most one change, SDR then HDR, on arrival. Off is SDR at once with no flash of HDR. Under an HDR picture the histogram is the HDR one, or briefly its empty frame, never an SDR curve or the previous photo's. No soft or blurry moment worth reporting at 100% | M2, M3 |
| P3 | Quit and relaunch with the window on the display that allows less than the photo needs, the app in front. Open a first HDR photo and wait 3 s. Then other photos, the grid, comparison (`S`), review (`F`), the window to the other display and back | At most one further change, about 1.5 s after HDR appears, on the first photo only; none later. Badge stays **HDR**; its help tag gives the file's number and the display's | AC18; M9 |
| P4 | With an HDR photo open, change screen brightness: at rest; during a slider drag; at 100% with the mask overlay, then with **Original**; during Crop. Switch to another app and back. Move the window between displays (and to an SDR display if there is one). At 100% choose **View ▸ Hide HDR**, wait, **Show HDR** | The picture follows without a flash, spinner, lasting wrong level or repeated jumps; the histogram does not change with brightness. An SDR display reads **SDR: No HDR Display** and HDR returns afterwards. The HDR histogram fills within a moment of **Show HDR** | AC5; M10, M11, M16 |
| P5 | On the external display, photo at 200% (`⌘=`) panned to a corner: turn its HDR off and on in System Settings. Repeat in comparison | Picture and badge agree both ways, never "loading" for good; zoom and place stay. If only this returns to 100%, note it for the proposed follow-up bug | M12, M17 |
| P6 | Over an HDR photo: Crop, straighten, Done; Crop, Esc; Edit Spots (`H`), add a spot; save a preset and hover it; sharpening map on and off; fill a fringe color, Fringe Map on and off; at 100% pick the filled slot again | No flash of SDR anywhere. A map shows no version badge and no brightness ramp around it, and HDR returns straight away. While picking at 100% the picture turns sharp and stays HDR | AC7 by eye; M5, M6 |
| P7 | Put crop, mask and spot handles over the brightest areas; paint a brush mask there with the overlay on | Handles easy to find; the red reads about as clearly as in SDR | M4 |
| P8 | Compare an HDR photo with an SDR one, `A` to switch; then two HDR photos, the first time each is shown after a relaunch; review mode | Each pane has its own badge, with a small spinner if HDR takes over half a second; the histogram follows the active side without showing the other's curve | M13 |
| P9 | Look at the HDR histogram with Increase Contrast off and on, in a Light and a Dark system appearance; watch the Tone Curve | Line, fill, dashed lines and **HDR** mark readable; the curve's backdrop does not change its axis | M7 |
| P10 | Look at the Adjust header, and Tab through it with Keyboard Navigation on. Open the **Adjust** and **View** menus on the photo, while comparing, while cropping and after Hide HDR. Choose **Adjust ▸ Reset All Adjustments**, then Undo | **HDR** box after **Original**, evenly spaced, reachable by Tab. **Turn On / Off HDR** follows the choice and is dimmed while comparing and cropping; View reads **Hide HDR** or **Show HDR**. Reset turns HDR off, Undo restores it | M1 |

## Follow-up

No reruns yet.
