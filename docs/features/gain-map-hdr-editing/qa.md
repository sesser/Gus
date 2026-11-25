# Edit and show gain-map photos in HDR: QA

Owner: qa-tester. Date: 2026-11-25. Step 4 of `docs/WORKFLOW.md`. Issue #282.
Tested (second pass): `feature/gain-map-hdr-editing` at `e4c14b2` (clean tree),
on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), macOS SDK 27.2, Swift 6.4.2. The
screen the scripted app used reported potential headroom 4.18 (the external
display); script results at other headrooms use the debug script's override.
Nothing here was looked at on an HDR display: no visual HDR result is claimed.
Snapshots were used only for caption and pane layout. The first pass was at
`60b95bd` (committed as `ac6f297`).

## Verdict

**Does not pass.** Q1 to Q5 are fixed and no acceptance criterion fails: 15
pass, 2 wait for eyes (AC8, AC18), 1 does not apply (AC16). But the Q3 fix
brought a new fault (Q6): in the narrowest windows an ordinary caption now makes
the loupe wider than its space and pushes the sidebar and inspector partly off
the window. `develop` does not do this. The designer's check M18 therefore
**fails**, so by `review.md` F12 is to be fixed on this branch.

Full `swift test` at `e4c14b2`: **1575 tests in 221 suites passed** (101.3 s),
goldens included, no warnings. The HDR suites with #277's (`GainMapHDRTests`,
`GainMapAdjustmentTests`, `HDRChoiceTests`, `HDRChoiceOutputTests`,
`GainMapRenditionTests`, `GainMapTimingTests`): 46 tests in 6 suites passed,
opt-in tests skipped there and run separately (T0). `Scripts/build-app.sh` built
the bundle. The CI toolchain build was not rerun (`status.md` records it).

After the runs: no instance of the app was running,
`~/Library/Application Support/Gus/Library` had no file newer than the start of
this pass (12:03), the owner's three originals have the same SHA-256 as before,
and the scratch copies of them were deleted. The early check's files were not
touched.

## Acceptance criteria

PRD as revised after the first pass (RI-8: AC4, AC6). The owner accepted the new
AC6 wording on 2026-11-25, as relayed by the main session: asked "Is testing
Apple-only support on altered copies of your photos good enough?", they answered
"Yes, accept it". (The issue body still lists it under RI-8 as not an owner
ruling.)

Suites are in `Tests/PhotoCoreTests`. "T" scripts are this pass's, "S" scripts
the first pass's (both under Scripts). "Both kinds" means ISO 21496-1 and
Apple-only gain maps. The owner's three HEICs carry both; "Apple-only copies"
are copies with the ISO map hidden.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| AC1 | Test, Script | `GainMapHDRTests` "A gain-map HEIC or JPEG has a gain map…" (both kinds), "AC1: only a HEIC or JPEG, by name and content…"; `HDRChoiceTests` "Off is the default…". T1: gain-map HEIC and Apple-only JPEG start **SDR**, off; plain JPEG has no choice. Other file types: S1 (not rerun) | Pass |
| AC2 | Test, Script | `HDRChoiceTests` "R2: the catalog keeps…", "R2: a virtual copy…", "R2: Reset All…". T5, with the original gone: Undo of **Turn On HDR** turns the choice off and Redo on, History lists both, a revert to a **Turn Off HDR** entry restores off, Reset All turns it off, each undone. Relaunch, pair and copy: S3, S4 (not rerun) | Pass |
| AC3 | Test | `HDRChoiceTests` "AC3: presets and Paste Adjustments neither carry nor change the choice" (script: S5, not rerun) | Pass |
| AC4 | Test, Script | `HDRChoiceTests` badge tests. T6, T7: every reason, 1.29 and 1.0 read **HDR**, comparison panes. T5: original gone while open: box dimmed, click and command refused, SDR throughout Undo, Redo, History revert and Reset All, label follows R4, HDR and the box return with the volume. T8: the menu item is dimmed offline (activated run). T9: opened while offline: no check box; never-seen photo shows **Offline** alone. T10, T11: at 760 pt the warning mark and **SDR** are whole in every state. The crowded states break the layout around the caption (Q6); no clause of AC4 failed | Pass |
| AC5 | Test, Script | `GainMapHDRTests` "…the system's HDR decode, in every orientation" and "For a smaller headroom…" (both kinds, the latter against Core Image's own rule). T0: +0.006, +0.001, +0.000 stops on the three files, +0.006, +0.001, −0.000 on the Apple-only copies, +0.005 on an Apple-only JPEG. T1: Apple-only photos show values above white and refit at 2 and 1.29 without reopening | Pass |
| AC6 | Test | `GainMapAdjustmentTests` "AC6: every adjustment…" (50 cases: 25 × both kinds; unedited against the system's decode, Color Fringes, identity table). T0, opt-in on the **Apple-only copies**: unedited −0.015 to −0.032 stops off the system's decode; smallest values at most 0.011 stops; strong values at most 0.0038 stops RMS (Shadows). On copies with both maps: at most 0.046 (Contrast). Color Fringes at its strong value does change pixels on real files (T0) | Pass |
| AC7 | Test, Script | `GainMapHDRTests` "Once HDR is on screen…". T3: 82 steps on an Apple-only copy and on its original: all HDR, no version badge only during the two maps. T4 (undo, redo at fit and 100%). Turning it off shows SDR (T5, after reattaching). Undo of **Turn On HDR**, Reset All and a revert to an off entry showing SDR: S3, not rerun | Pass |
| AC8 | Test, Person | `GainMapAdjustmentTests` "AC8: for every adjustment…" (58 cases: 29 stacks × both kinds, at fit and at 100%); `GainMapHDRTests` live and settled, region, refinement. T0: live against settled −0.0004 to −0.0010 stops on seven files. By eye: P1 | Open |
| AC9 | Test, Script | `HDRChoiceOutputTests` "AC9: …" (both kinds, panes' counts too), "The HDR histogram's bins…". T6: Apple-only copy 0.199 above white at 16, 2, 1.5, 1.29, 1.0 and 1.2 | Pass |
| AC10 | Test | `GainMapTimingTests` rerun on six files (table under T0): HDR/SDR at fit 1.16 to 1.50, at 100% 0.88 to 1.13; the file that read 1.50 once gave 1.23 to 1.40 in five repeats (its original 1.33 to 1.45). Recorded in `status.md` | Pass |
| AC11 | Test | `HDRChoiceOutputTests` "AC11: …" (both kinds); every golden passes (script: S12) | Pass |
| AC12 | Test | `HDRChoiceTests` "AC12: the export notice counts…" (script and sheet snapshots: S13, code unchanged) | Pass |
| AC13 | Test | `HDRChoiceOutputTests` "AC13: …" (both kinds) | Pass |
| AC14 | Test | `GainMapRenditionTests`, `PreviewTests` and the merge suites pass in the full run | Pass |
| AC15 | Test | `HDRChoiceTests` "AC15: …", "R17…" (script: S12) | Pass |
| AC16 | n/a | Every check ran on macOS 27.2.1; nothing checks macOS 15 | n/a |
| AC17 | Test | `GainMapHDRTests` every orientation, "A region frame at 100%…"; `GainMapAdjustmentTests` Distortion and spots (both kinds) | Pass |
| AC18 | Test, Person | `GainMapHDRTests` "Design §18.1…", "AC18: each screen's allowance…". T4: grid and back with `refits 0` (overridden reading, so it shows no second fit, not what a screen reports). By hand: P2 | Open |

Counts: 15 pass (6 by test and a script rerun in this pass: AC1, AC2, AC4, AC5,
AC7, AC9; 9 by test in this pass: AC3, AC6, AC10 to AC15, AC17), 1 does not
apply (AC16), 2 open for a person (AC8, AC18), 0 fail.

"Fails without the fix" for Q1: the real app showed 0.000 above white on an
Apple-only copy at `60b95bd` (S1b) and 0.132 now (T1). The new tests compare the
unedited HDR version with the system's decode, so an unapplied map fails them (by
reading; the engineer records 10 of 29 failing without the fix, not rerun here).

### Designer's checks answered by script

- **M18** (F12): run, **fails** (T10, T11; Q6).
- **M19** (Apple-only gain map brightens, badge true): by numbers it passes (T0,
  T1). The eye check is part of P1.
- **M15** (offline): T5, T8, T9, T10. Warning mark and **SDR** beside
  **Offline**; box dimmed and checked; menu item dimmed as **Turn On HDR** in an
  activated run; HDR and the box return in place; choice off reads **SDR** with
  **Offline** and a help tag that does not name Turn On HDR. Not seen: the menu
  title after reconnecting (macOS did not give the app a key window again); it
  reads the same value as the box.
- **M8** (narrow captions): the three cases of Q3 pass (T11). Crowded states fail
  (Q6). Whether the moving marks look jumpy is in P7.
- **M14** (export notice): S13, code unchanged.
- **M1**, in part: box dimmed while cropping (T8). The menu dimmed while comparing
  and cropping could not be verified (`key nil`): P7.
- **M16**, **M17**, in part: at 100% the HDR histogram fills after Show HDR and
  the tile follows overridden headrooms (T4, Apple-only copy). Real brightness
  and System Settings: P3.

## Findings

### Q6. A crowded narrow caption pushes the sidebar and inspector off the window (medium-high; regression)

Design §19.6 ("Nothing is drawn over anything"; "the row is never wider than the
caption"), `review.md` F12 and M18. Brought by `60af4cc`. Affects every photo,
not only gain-map ones.

Steps: T11. A library holding one plain JPEG; window 760 × 560 with sidebar and
inspector shown; rate it 5, pick it; filter to Picked; duplicate; press `\`.

Expected: the loupe stays 240 pt wide (760 less the 220 pt sidebar and 300 pt
inspector), as on `develop` (`4561cb3`) and at `60b95bd`.

Actual, loupe width in points:

| State (plain JPEG) | `develop` | `60b95bd` | `e4c14b2` |
| --- | --- | --- | --- |
| 5 stars, pick | 240 | 240 | 240 |
| Filtered, Copy | 240 | 240 | **261** |
| Filtered, Copy, Original | 240 | 240 | **318** |

On a gain-map photo (5 stars, pick, orange label; T10) at `e4c14b2`: Filtered and
**HDR** 279; **View ▸ Hide HDR** 294; then Original 351; a copy 336; copy and
Original 394; copy, Original and Offline 445; copy and Offline 388. At 900 pt the
offline copy still needs about 388 of 380 pt (snapshot).

What gives: the window stays 760 × 560, and the split view grows wider than the
window, centered, so each side pane moves out by half the excess. Measured: at
274 pt every inspector button sits 17 pt right of its normal place and sidebar
content 17 pt left, and **More adjustment commands** (29 pt wide, centered at 750)
crosses the window edge. At 336 pt it is centered at 782, wholly outside the
window, and points x 180 and x 500, which hit the sidebar and inspector at
`60b95bd`, hit the loupe. At 445 pt about 102 pt of each side pane is outside
(computed from the same rule). Those controls can't be seen or clicked until the
badges go or the window widens. The version badge, warning mark, **SDR** and
**Offline** were whole in every state.

Likely cause (read, not changed): in `LoupeCaption`, `ViewThatFits` takes the
last arrangement even when it doesn't fit, and the badge row and position are
`fixedSize`, so that row's width becomes the column's minimum. Before `60af4cc`
the badge row had a maximum width and was squeezed instead (empty boxes at
`60b95bd`, badges over the stars on `develop`: older faults, but the layout held).
§19.6 "Not covered" already gives the order to shed items. Also seen at 760 pt
with an **HDR** badge and an orange label: the color name wraps to two cut lines,
which the same paragraph rules out.

Missing check: nothing tests that the caption never asks for more than its
column. T11 with `print loupe` shows it.

### Q7. Comparison at the minimum window is wider than its space, more so with version badges (low; design question)

T12. Each pane's width at 760 pt, sidebar and inspector shown, a photo beside its
copy: `develop` 235.75 pt for both a plain JPEG pair and a gain-map pair; so two
panes already need about 483 of 240 pt, a fault older than this branch. At
`60b95bd` and `e4c14b2` the plain pair is 235.75 and the gain-map pair **271.25**:
the version badges, which design §9 never drops, add about 71 pt. The first pass
saw the badge whole and did not measure the width.

For the designer: fix with Q6, or a follow-up. Proposed issue if a follow-up:
**Comparison is wider than the window allows at its minimum size** (`bug`,
Routine). Body: at 760 pt with sidebar and inspector shown, compare two photos;
the comparison needs about 480 pt (550 with gain-map photos, #282) where 240 are
free, and pushes the side panes off the window. Slug:
`comparison-narrow-window-overflow`.

### First-pass findings (Q1 to Q5)

All fixed; see Follow-up. As first written they are in `ac6f297`. Q1's method is
still used here to make Apple-only copies:

```python
import sys

data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(data.replace(b"tmap", b"xxxx"))
```

## Scripts

### Second pass (`e4c14b2`)

Copies of `build/Gus.app` with identifiers ending `.debugtest.qa282b` (this
build), `.qa282bpre` (`60b95bd`, built from `git archive` outside the checkout)
and `.qa282bdev` (`develop`, the same way). Scratch libraries from `photobench
import`. `$R` is a scratch folder; every launch was
`<copy>/Contents/MacOS/Gus --library-root $R/<library> --debug-script "<script>"`,
and T8 used `open -W -n --stdout <log> <copy> --args --library-root …`. For
offline runs the photos sat on a FAT32 disk image, and a helper ran `hdiutil
detach -force` when the output reached `print-DETACH` and `hdiutil attach` at
`print-ATTACH`.

Libraries: `lib1`: IMG_0542, IMG_0546, IMG_0561 (`.HEIC`), APPLE_0542, APPLE_0546,
APPLE_0561 (Apple-only copies), `APPLEJ_0546.jpg` (written by ImageIO from
APPLE_0546 with its maker data and Apple map only), `PLAIN.jpg` (`photobench
scenes` dusty sky). Disk image: IMG_0561, IMG_0546, APPLE_0561, PLAIN.jpg.

#### T0: opt-in tests on copies

```zsh
GAINMAP_SAMPLES=$R/APPLE_0546.HEIC:$R/APPLE_0542.HEIC:$R/APPLE_0561.HEIC swift test --filter "GainMapAdjustmentTests/everyAdjustmentOnRealFiles"
GAINMAP_SAMPLES=$R/IMG_0546.HEIC:$R/IMG_0542.HEIC:$R/IMG_0561.HEIC swift test --filter "GainMapAdjustmentTests/everyAdjustmentOnRealFiles"
HEIC_GAINMAP_SAMPLE=$R/<each file> swift test --filter "GainMapHDRTests/sample"
GAINMAP_TIMING=$R/IMG_0546.HEIC:$R/IMG_0542.HEIC:$R/IMG_0561.HEIC:$R/APPLE_0546.HEIC:$R/APPLE_0542.HEIC:$R/APPLE_0561.HEIC swift test --filter GainMapTimingTests
```

All passed. Frame times, milliseconds:

| File | Fit SDR | Fit HDR | Ratio | 100% SDR | 100% HDR | Ratio |
| --- | --- | --- | --- | --- | --- | --- |
| IMG_0546 | 21.5 | 25.0 | 1.16 | 12.3 | 10.9 | 0.88 |
| IMG_0542 | 19.3 | 23.8 | 1.23 | 10.8 | 10.5 | 0.97 |
| IMG_0561 | 17.0 | 22.5 | 1.32 | 18.3 | 18.9 | 1.03 |
| APPLE_0546 | 20.0 | 24.1 | 1.21 | 11.9 | 10.9 | 0.92 |
| APPLE_0542 | 20.0 | 24.4 | 1.22 | 12.1 | 11.4 | 0.94 |
| APPLE_0561 | 15.8 | 23.7 | 1.50 | 19.0 | 21.5 | 1.13 |

Color Fringes was also checked to change pixels on real files: `photocli render`
of two versions before and after `develop --set colorFringes.color1=purple --set
colorFringes.tolerance1=100 --set colorFringes.color2=green --set
colorFringes.tolerance2=100` differed.

#### T1: Apple-only against both maps (`lib1`)

For each of IMG_0546, APPLE_0546, APPLEJ_0546, IMG_0561, APPLE_0561, IMG_0542,
APPLE_0542, after `wait 2; hdr on; hdr display 16`:

```
focus <name>; loupe; inspector on; tab adjust; wait 4; print hdr; adjust hdr on; wait 5; print hdr; hdr display 2; wait 3; print hdr; hdr display 1.29; wait 3; print hdr; hdr display 16; wait 3
```

ending `focus PLAIN; wait 3; print hdr; buttons; quit`. Share above white: 0.128 /
0.132 / 0.131 (IMG, APPLE, APPLEJ 0546), 0.381 / 0.199 (0561), 0.021 / 0.021
(0542). Rendered 2.62, 4.57 or 4.67, 3.74, then 2.00 and 1.29 badged **HDR**,
fitted. Every one started **SDR** with the choice off.

#### T3: every adjustment (S8 on APPLE_0561 and IMG_0561)

S8 unchanged but for its first step, `focus <name>; loupe; inspector on; tab
adjust; wait 4; adjust hdr on; wait 5`, each on a fresh import. 82 steps each:
choice on, `shown hdr`, histogram `hdr`; badge `none` only at `sharpenmap on` and
`fringemap on`.

#### T4: undo, redo, 100% (APPLE_0561, after T3)

```
wait 2; hdr display 2; focus APPLE_0561; loupe; inspector on; tab adjust; wait 5; adjust exposure -1; wait 2; print STEP-ev-1; print hdr; adjust exposure 1; wait 2; print STEP-ev1; print hdr; print undo; undo; wait 3; print STEP-undo; print hdr; redo; wait 3; print STEP-redo; print hdr; zoom; wait 3; undo; wait 3; print STEP-undo-at-100; print hdr; redo; wait 3; print STEP-redo-at-100; print hdr; quit
```

HDR throughout, above white 0.054, 0.299, 0.054, 0.299, the same at 100%. Then:

```
wait 2; compare animate off; hdr on; hdr display 16; focus APPLE_0561; loupe; inspector on; tab adjust; wait 5; grid; wait 1; hdr off; loupe; wait 4; zoom; wait 4; print STEP-100-hidden; print hdr; hdr on; wait 6; print STEP-100-shown; print hdr; original on; wait 3; hdr display 3; wait 3; print STEP-original-3; print hdr; hdr display 2; wait 3; print STEP-original-2; print hdr; original off; adjust mask add radial; adjust mask overlay on; wait 3; print STEP-overlay-2; print hdr; hdr display 3; wait 3; print STEP-overlay-3; print hdr; adjust mask overlay off; zoom; wait 3; grid; wait 1; loupe; wait 4; print STEP-grid-back; print hdr; compare on; wait 3; print STEP-compare; print compare; compare off; wait 3; print STEP-compare-back; print hdr; quit
```

After Show HDR at 100%: histogram `hdr above white 0.299`; tile 3.00, 2.00,
2.00, 3.00; `refits 0` at every step, grid and back included.

#### T5: original gone while open (disk image)

```
wait 2; hdr on; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; adjust hdr on; wait 3; adjust hdr off; wait 3; adjust hdr on; wait 3; adjust exposure 0.3; wait 2; print STEP-online; print hdr; buttons; print print-DETACH; wait 8; print STEP-offline; print hdr; buttons; click 1140 202; wait 2; print STEP-after-click; print hdr; print undo; undo; wait 3; print STEP-undo-exposure; print hdr; print undo; undo; wait 3; print STEP-undo-turn-on; print hdr; print undo; buttons; redo; wait 3; print STEP-redo-turn-on; print hdr; history open; history wait; history; history revert 5; wait 4; history wait; history; print STEP-revert-to-turn-off; print hdr; buttons; undo; wait 3; print STEP-undo-revert; print hdr; adjust reset all; wait 3; print STEP-reset-all; print hdr; print undo; undo; wait 3; print STEP-undo-reset; print hdr; adjust hdr off; wait 2; print STEP-refused-adjust-hdr-off; print hdr; print print-ATTACH; wait 10; print STEP-reattached; print hdr; buttons; adjust hdr off; wait 3; print STEP-off-after-attach; print hdr; print undo; quit
```

(`1140 202` is the box in that window.) Offline: `can set false`, box disabled,
shown SDR at every step. Choice on: badge `sdr offline`; choice off (after Undo
of Turn On HDR, the revert to **Turn Off HDR**, Reset All): `sdr cached`. The
click and `adjust hdr off` changed nothing. Reattached: `shown hdr`, `can set
true`, box enabled, `adjust hdr off` gives **Turn Off HDR**.

#### T6, T7: reasons and comparison

S6 and S7 with APPLE_0561 and APPLE_0546 in place of IMG_0561 and IMG_0546, on a
fresh import (`flag any; hdr on` added at the start). `hdr fitted` at 2.00, 1.50,
1.29, 1.00 and the system's 1.20; `sdr hidden`, `sdr noHDRDisplay` (`sdr`,
`flat`), `sdr failed`; HDR returns. Each pane states its own version and reason;
the inspector histogram is HDR only with the HDR pane active and HDR shown.

#### T8: menu while offline (activated, disk image)

```
wait 3; compare animate off; hdr on; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; adjust hdr on; wait 4; print STEP-online; print responder; print hdr; menuitems HDR; print print-DETACH; wait 8; print STEP-offline; print responder; print hdr; menuitems HDR; menupress Turn On HDR; wait 2; print hdr; print print-ATTACH; wait 10; print STEP-reattached; print responder; print hdr; menuitems HDR; menupress Turn Off HDR; wait 3; print STEP-menu-off; print hdr; print undo; menuitems HDR; menupress Turn On HDR; wait 3; print STEP-menu-on; print hdr; print undo; menuitems HDR; adjust crop begin; wait 2; print STEP-cropping; print responder; menuitems HDR; buttons; adjust crop cancel; wait 2; compare on; wait 4; print STEP-comparing; print responder; menuitems HDR; compare off; wait 3; hdr off; wait 3; print STEP-hidden; menuitems HDR; hdr on; wait 3; adjust reset all; wait 3; print STEP-reset; print hdr; print undo; undo; wait 3; print STEP-reset-undone; print hdr; quit
```

Key window online: **Turn Off HDR** enabled. Key window offline: **Turn On HDR**
disabled, `menupress` refused, choice unchanged. From the reattach on the app
had no key window (`key nil`), so the later menu lines show nothing; the box was
disabled while cropping. Two more activated runs stayed `key nil` and were not
retried further.

#### T9: opened while offline (disk image detached before launch)

```
wait 2; hdr on; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 4; print STEP-opened-offline-on; print hdr; buttons; menuitems HDR; adjust hdr off; wait 2; print hdr; focus IMG_0561; wait 3; print STEP-opened-offline-off; print hdr; buttons; quit
```

```
wait 2; hdr on; hdr display 16; focus APPLE_0561; loupe; inspector on; tab adjust; wait 4; print STEP-opened-offline-never-on; print hdr; buttons; snapshot $R/offline-never-on.png; focus PLAIN; wait 2; print STEP-offline-plain; print hdr; quit
```

Choice on: `sdr offline`, no **Original** or **HDR** button. Never turned on and
not read in that run: no version badge; the snapshot shows **Offline** alone.

#### T10: M18 (disk image; first `photocli rate`, `flag` and `label`: 5, picked, orange, on IMG_0561)

```
wait 2; windowsize 760 560; wait 2; sidebarpane on; inspector on; hdr on; hdr display 16; focus IMG_0561; loupe; tab adjust; wait 4; adjust hdr on; wait 4; print STEP-hdr-unfiltered; print loupe; print inspectorwidth; snapshot $R/m18-0-hdr.png; flag picked; wait 2; print STEP-hdr-filtered; print loupe; snapshot $R/m18-1-hdr-filtered.png; hdr off; wait 2; print STEP-hidden; print hdr; print loupe; print inspectorwidth; snapshot $R/m18-2-hidden.png; original on; wait 2; print STEP-hidden-original; print loupe; print inspectorwidth; snapshot $R/m18-3-original.png; original off; duplicate; wait 4; print STEP-copy; print copies; print hdr; print loupe; print inspectorwidth; snapshot $R/m18-4-copy.png; original on; wait 2; print STEP-copy-original; print loupe; print inspectorwidth; snapshot $R/m18-5-copy-original.png; print print-DETACH; wait 8; print STEP-copy-original-offline; print hdr; print loupe; print inspectorwidth; snapshot $R/m18-6-offline-original.png; original off; wait 2; print STEP-copy-offline; print loupe; snapshot $R/m18-7-offline.png; hdr on; wait 2; print STEP-copy-offline-shown; print hdr; print loupe; snapshot $R/m18-8-offline-shown.png; windowsize 900 600; wait 2; print STEP-900; snapshot $R/m18-9-w900.png; windowsize 1300 760; wait 2; print STEP-1300; snapshot $R/m18-10-w1300.png; windowsize 760 560; wait 2; print STEP-760-again; print loupe; print inspectorwidth; snapshot $R/m18-11-back.png; print print-ATTACH; wait 8; flag any; wait 1; quit
```

Widths from `print loupe` (magnification times visible width): 239, 279, 294,
351, 336, 394, 445, 388, and 388 back at 760. The inspector's own width stayed
300; the window stayed 760 by 560. The same library, choice off and offline (331
points):

```
wait 2; windowsize 760 560; wait 2; sidebarpane on; inspector on; hdr on; hdr display 16; flag picked; wait 1; focus 2; loupe; tab adjust; wait 4; adjust hdr off; wait 3; print STEP-online-off-copy; print hdr; print loupe; print print-DETACH; wait 8; print STEP-offline-off-copy; print hdr; print loupe; print title; buttons; hit 470 546; snapshot $R/m18off.png; print print-ATTACH; wait 8; flag any; wait 1; quit
```

Positions of the side panes: the first script on a library of T1's photos whose
plain JPEG had already been rated, picked and duplicated, the second on T10's:

```
wait 2; flag any; wait 1; windowsize 760 560; wait 2; sidebarpane on; inspector on; hdr on; hdr display 16; focus IMG_0546; loupe; tab adjust; wait 4; print STEP-narrow; print loupe; buttons; hit 100 300; snapshot $R/shift-narrow.png; flag picked; wait 1; focus PLAIN; wait 3; original on; wait 2; print STEP-wide; print loupe; buttons; snapshot $R/shift-wide.png; original off; flag any; wait 2; quit
```

```
wait 2; flag picked; wait 1; windowsize 760 560; wait 2; sidebarpane on; inspector on; focus 2; loupe; tab adjust; wait 4; original on; wait 2; print STEP-branch-original; print loupe; print title; buttons; hit 150 300; hit 180 300; hit 500 300; hit 530 300; print inspectorwidth; original off; wait 1; flag any; wait 1; quit
```

#### T11: minimal case and Q3's cases

Q6, on a fresh library of `PLAIN.jpg`, run on all three builds:

```
wait 2; flag any; wait 1; windowsize 760 560; wait 2; sidebarpane on; inspector on; focus PLAIN; loupe; tab adjust; wait 3; key 5; key p; wait 1; print STEP-marks; print loupe; buttons; flag picked; wait 2; duplicate; wait 4; print STEP-filtered-copy; print copies; print loupe; buttons; snapshot $R/q6min-copy.png; original on; wait 2; print STEP-filtered-copy-original; print loupe; buttons; snapshot $R/q6min-original.png; original off; flag any; wait 1; quit
```

Q3's cases (the part from `focus IMG_0546` on; on a library that already had the
plain JPEG states of Q6): all 240 points (381 at 900), marks clear of the badges,
warning mark, **SDR** and **Copy** whole; centered again at 900, 1000 and 1300.

```
wait 2; windowsize 760 560; wait 2; sidebarpane on; inspector on; hdr on; hdr display 16; flag picked; wait 1; focus PLAIN; loupe; wait 3; original on; wait 2; print STEP-wide; print loupe; buttons; hit 150 546; hit 340 546; hit 530 546; hit 190 300; hit 490 300; snapshot $R/q6-wide.png; original off; flag any; wait 2; print STEP-narrow; print loupe; hit 150 546; hit 530 546; hit 190 300; hit 490 300; focus IMG_0546; wait 3; tab adjust; key 5; adjust hdr on; wait 4; print STEP-q3-5stars-hdr; print loupe; snapshot $R/q6-q3-hdr.png; hdr off; wait 2; print STEP-q3-5stars-hidden; print loupe; snapshot $R/q6-q3-hidden.png; duplicate; wait 4; print STEP-q3-5stars-hidden-copy; print loupe; snapshot $R/q6-q3-hidden-copy.png; hdr on; wait 3; print STEP-q3-5stars-hdr-copy; print loupe; snapshot $R/q6-q3-hdr-copy.png; windowsize 900 600; wait 2; print STEP-q3-900; print loupe; snapshot $R/q6-q3-900.png; windowsize 1000 640; wait 2; snapshot $R/q6-q3-1000.png; windowsize 1300 760; wait 2; snapshot $R/q6-q3-1300.png; windowsize 760 560; wait 2; hdr off; wait 1; compare on; wait 4; print STEP-compare; print compare; snapshot $R/q6-q3-compare.png; compare off; quit
```

#### T12: comparison widths (Q7), each build

```
wait 2; flag any; wait 1; windowsize 760 560; wait 2; sidebarpane on; inspector on; compare animate off; focus PLAIN; loupe; wait 3; compare on; wait 4; print STEP-PLAIN; print compare; snapshot $R/c-branch-PLAIN.png; compare off; wait 2; grid; wait 1; focus IMG_0561; loupe; wait 3; compare on; wait 4; print STEP-IMG_0561; print compare; snapshot $R/c-branch-IMG_0561.png; compare off; wait 2; grid; wait 1; quit
```

(PLAIN and IMG_0561 each had a copy beside them in these libraries.)

### First pass (`60b95bd`)

Libraries and bundle as described below; its findings are Q1 to Q5.

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

#### S1: which files have the choice (`photos`)

```
wait 2; focus IMG_0546; loupe; wait 4; tab adjust; wait 1; print hdr; buttons; menuitems HDR; focus PLAIN; wait 3; print hdr; buttons; menuitems HDR; focus RAWFILE; wait 4; print hdr; buttons; focus SCENE; wait 3; print hdr; buttons; focus PQFILE; wait 3; print hdr; buttons; focus VIDEO; wait 3; print hdr; buttons; menuitems HDR; quit
```

```
wait 2; focus IMG_0546; loupe; wait 2; inspector on; tab adjust; wait 4; print inspector; buttons; snapshot $R/a-adjust.png; focus PLAIN; wait 4; print inspector; buttons; focus RAWFILE; wait 5; buttons; quit
```

`has choice true`, off, badge `sdr` for the HEIC; `has choice false` for the
others (PQ shows `shown hdr` with badge `none`: its own rendition). Button `HDR`
(state off, with the design's help tag) after `Original` only on the HEIC.

#### S1b: HDR on, both maps against Apple-only (`photos`)

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 6; print hdr; focus APPLE_0546; wait 4; print hdr; adjust hdr on; wait 6; print hdr; focus APPLEJ_0546; wait 3; adjust hdr on; wait 6; print hdr; focus IMG_0561; wait 3; adjust hdr on; wait 6; print hdr; focus IMG_0542; wait 3; adjust hdr on; wait 6; print hdr; quit
```

Share above white: IMG_0546 0.128, APPLE_0546 0.000, APPLEJ_0546 0.000,
IMG_0561 0.381, IMG_0542 0.021. All badge `hdr`, `versions sdr,hdr`.

#### S2: an already cataloged library (copy of the early check's, schema v16)

```
wait 2; hdr on; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 4; print hdr; focus IMG_0561; wait 4; print hdr; focus IMG_0542; wait 4; print hdr; quit
```

Choice off, badge `sdr` on all three; afterwards the catalog is at v17 with
`version.hdr` 0.

#### S3: persistence, undo, History, Reset All (two runs, one library)

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust exposure 0.2; wait 1; adjust hdr on; wait 5; print hdr; print undo; history open; history wait; history; quit
```

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 6; print hdr; adjust hdr off; wait 3; print undo; print hdr; undo; wait 5; print hdr; print undo; redo; wait 3; print hdr; undo; wait 5; print hdr; history open; history wait; history; history revert 3; wait 4; history wait; history; print hdr; undo; wait 5; print hdr; adjust reset all; wait 3; print hdr; history wait; history; undo; wait 5; print hdr; quit
```

Run 2 opens with the choice on. States in order: on, off, on, off, on; revert to
**Turn Off HDR** off; undo on; **Reset Adjustments** off; undo on. History lists
each, with **Turn On HDR** and **Turn Off HDR**.

#### S4: pair file and virtual copy

```
wait 2; hdr display 16; pairs grouped; print items; focus PAIR; loupe; inspector on; tab adjust; wait 4; print hdr; pairfile jpeg; wait 4; adjust hdr on; wait 5; print hdr; pairfile raw; wait 5; print hdr; pairfile jpeg; wait 5; print hdr; focus IMG_0546; wait 3; adjust hdr on; wait 4; duplicate; wait 2; print copies; adjust hdr off; wait 3; print hdr; print copies; quit
```

Same library, then:

```
wait 2; hdr display 16; focus 1; loupe; inspector on; tab adjust; wait 5; print hdr; focus 2; wait 5; print hdr; focus 1; wait 3; duplicate; wait 4; print hdr; print copies; quit
```

Raw file: no choice, before and after the HEIC file was turned on; the HEIC kept
it. Turning the copy off left the original on.

#### S5: paste and presets

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust exposure 0.5; adjust hdr on; wait 4; copyadjust all; preset save HDRsource; focus IMG_0542; wait 4; pasteadjust; wait 4; print hdr; print stacks; preset apply HDRsource; wait 3; print hdr; adjust exposure -0.5; wait 1; copyadjust all; preset save SDRsource; focus IMG_0546; wait 5; pasteadjust; wait 4; print hdr; print stacks; preset apply SDRsource; wait 4; print hdr; adjust reset all; wait 2; adjust hdr on; wait 4; preset apply HDRsource; wait 4; print hdr; quit
```

The SDR target stayed off after paste and preset (stack `[exposure]`); the HDR
target stayed on.

#### S6: headroom, reasons, histogram

```
wait 2; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 5; print hdr; hdr display 2; wait 3; print hdr; hdr display 1.5; wait 3; print hdr; hdr display 1.29; wait 3; print hdr; hdr display 1.0; wait 3; print hdr; hdr display system; wait 3; print hdr; hdr display 16; wait 3; hdr off; wait 3; print hdr; buttons; hdr on; wait 4; print hdr; hdr display sdr; wait 3; print hdr; hdr display flat; wait 3; print hdr; hdr display 16; wait 4; print hdr; hdr fail on; focus PLAIN; wait 3; focus IMG_0561; wait 5; print hdr; hdr fail off; wait 3; print hdr; focus PLAIN; wait 3; focus IMG_0561; wait 5; print hdr; quit
```

`rendered` 4.57, 2.00, 1.50, 1.29, 1.00 with badge `hdr fitted` and both numbers
in the help; `changes 1` throughout. `sdr hidden`, `sdr noHDRDisplay` (`sdr` and
`flat`), `sdr failed` (stays until reopened); box still checked; HDR returns.

#### S7: comparison

```
wait 2; compare animate off; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 4; compare on; wait 3; print compare; compare active right; wait 2; print compare; compare active left; wait 2; print compare; hdr display 1.29; wait 3; print compare; hdr display 1.0; wait 3; print compare; hdr display 16; hdr off; wait 3; print compare; hdr on; wait 4; print compare; hdr display sdr; wait 3; print compare; hdr display flat; wait 3; print compare; hdr display 16; wait 4; print compare; hdr fail on; compare off; focus PLAIN; wait 2; focus IMG_0546; wait 2; compare on; wait 4; print compare; hdr fail off; compare off; focus PLAIN; wait 2; focus IMG_0546; wait 4; print hdr; compare on; wait 4; print compare; menuitems HDR; compare off; wait 3; print hdr; grid; wait 1; loupe; wait 3; print hdr; quit
```

Each pane states its own version and reason, in its badge and VoiceOver value;
the inspector histogram is HDR only with the HDR pane active and HDR shown.

#### S8: AC7, every adjustment (follows S6's library, IMG_0561 on)

```
wait 2; hdr display 2; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; print STEP-arrival; print hdr; adjust temperature 4000; wait 1.2; print STEP-adjust_temperature_4000; print hdr; adjust tint 20; wait 1.2; print STEP-adjust_tint_20; print hdr; adjust exposure 1.0; wait 1.2; print STEP-adjust_exposure_1.0; print hdr; adjust contrast 60; wait 1.2; print STEP-adjust_contrast_60; print hdr; adjust highlights -60; wait 1.2; print STEP-adjust_highlights_-60; print hdr; adjust shadows 40; wait 1.2; print STEP-adjust_shadows_40; print hdr; adjust whites 30; wait 1.2; print STEP-adjust_whites_30; print hdr; adjust blacks -30; wait 1.2; print STEP-adjust_blacks_-30; print hdr; adjust clarity 50; wait 1.2; print STEP-adjust_clarity_50; print hdr; adjust dehaze 40; wait 1.2; print STEP-adjust_dehaze_40; print hdr; adjust vibrance 40; wait 1.2; print STEP-adjust_vibrance_40; print hdr; adjust saturation 30; wait 1.2; print STEP-adjust_saturation_30; print hdr; adjust curve rgb 0,0 0.25,0.15 0.75,0.85 1,1; wait 1.2; print STEP-adjust_curve_rgb_0,0_0.25,0.15_0.75,0.85_1,1; print hdr; adjust mix orange 0 60 0; wait 1.2; print STEP-adjust_mix_orange_0_60_0; print hdr; adjust bw on; wait 1.2; print STEP-adjust_bw_on; print hdr; adjust bw filter red; wait 1.2; print STEP-adjust_bw_filter_red; print hdr; adjust bw off; wait 1.2; print STEP-adjust_bw_off; print hdr; adjust grade highlights 40 60; wait 1.2; print STEP-adjust_grade_highlights_40_60; print hdr; lut Warm; wait 1.2; print STEP-lut_Warm; print hdr; adjust intensity 80; wait 1.2; print STEP-adjust_intensity_80; print hdr; adjust vignette -60; wait 1.2; print STEP-adjust_vignette_-60; print hdr; adjust grain 50; wait 1.2; print STEP-adjust_grain_50; print hdr; adjust amount 100; wait 1.2; print STEP-adjust_amount_100; print hdr; adjust masking 50; wait 1.2; print STEP-adjust_masking_50; print hdr; adjust luminance-nr 50; wait 1.2; print STEP-adjust_luminance-nr_50; print hdr; adjust color-nr 40; wait 1.2; print STEP-adjust_color-nr_40; print hdr; lens vignetting manual; wait 1.2; print STEP-lens_vignetting_manual; print hdr; lens vignetting amount 50; wait 1.2; print STEP-lens_vignetting_amount_50; print hdr; lens distortion manual; wait 1.2; print STEP-lens_distortion_manual; print hdr; lens distortion amount 40; wait 1.2; print STEP-lens_distortion_amount_40; print hdr; adjust fringe fill 1 purple; wait 1.2; print STEP-adjust_fringe_fill_1_purple; print hdr; adjust fringe tolerance 1 50; wait 1.2; print STEP-adjust_fringe_tolerance_1_50; print hdr; adjust align redcyan 10; wait 1.2; print STEP-adjust_align_redcyan_10; print hdr; adjust off light; wait 1.2; print STEP-adjust_off_light; print hdr; adjust on light; wait 1.2; print STEP-adjust_on_light; print hdr; adjust exposure -3; wait 1.2; print STEP-adjust_exposure_-3; print hdr; adjust exposure 0; wait 1.2; print STEP-adjust_exposure_0; print hdr; adjust scrub exposure -1 1 20 30 hold; wait 1.2; print STEP-adjust_scrub_exposure_-1_1_20_30_hold; print hdr; adjust scrub exposure 1 0.2 10 30; wait 1.2; print STEP-adjust_scrub_exposure_1_0.2_10_30; print hdr; zoom; wait 2.5; print STEP-zoom; print hdr; adjust scrub exposure 0.2 -0.5 10 30; wait 1.2; print STEP-adjust_scrub_exposure_0.2_-0.5_10_30; print hdr; original on; wait 1.2; print STEP-original_on; print hdr; original off; wait 1.2; print STEP-original_off; print hdr; adjust scrub contrast 60 20 10 30; wait 1.2; print STEP-adjust_scrub_contrast_60_20_10_30; print hdr; zoom; wait 2.5; print STEP-zoom; print hdr; adjust mask add radial; wait 1.2; print STEP-adjust_mask_add_radial; print hdr; adjust mask set exposure 1; wait 1.2; print STEP-adjust_mask_set_exposure_1; print hdr; adjust mask overlay on; wait 1.2; print STEP-adjust_mask_overlay_on; print hdr; adjust mask overlay off; wait 1.2; print STEP-adjust_mask_overlay_off; print hdr; adjust mask add brush; wait 1.2; print STEP-adjust_mask_add_brush; print hdr; adjust mask brush 0.2 0.2 0.4 0.4 0.6 0.5; wait 1.2; print STEP-adjust_mask_brush_0.2_0.2_0.4_0.4_0.6_0.5; print hdr; adjust mask overlay off; wait 1.2; print STEP-adjust_mask_overlay_off; print hdr; adjust mask select none; wait 1.2; print STEP-adjust_mask_select_none; print hdr; spots on; wait 1.2; print STEP-spots_on; print hdr; spot add 0.5 0.5; wait 2.5; print STEP-spot_add_0.5_0.5; print hdr; spots off; wait 1.2; print STEP-spots_off; print hdr; adjust crop begin; wait 2.5; print STEP-adjust_crop_begin; print hdr; adjust crop rect 0.1 0.1 0.8 0.8; wait 1.2; print STEP-adjust_crop_rect_0.1_0.1_0.8_0.8; print hdr; adjust crop angle 3; wait 1.2; print STEP-adjust_crop_angle_3; print hdr; adjust crop done; wait 2.5; print STEP-adjust_crop_done; print hdr; adjust crop begin; wait 2.5; print STEP-adjust_crop_begin; print hdr; adjust crop cancel; wait 1.2; print STEP-adjust_crop_cancel; print hdr; adjust crop turn right; wait 1.2; print STEP-adjust_crop_turn_right; print hdr; sharpenmap on; wait 1.2; print STEP-sharpenmap_on; print hdr; sharpenmap off; wait 1.2; print STEP-sharpenmap_off; print hdr; fringemap on; wait 1.2; print STEP-fringemap_on; print hdr; fringemap off; wait 1.2; print STEP-fringemap_off; print hdr; preset save QA; wait 1.2; print STEP-preset_save_QA; print hdr; adjust exposure 0.7; wait 1.2; print STEP-adjust_exposure_0.7; print hdr; preset preview QA; wait 1.2; print STEP-preset_preview_QA; print hdr; preset previewend; wait 1.2; print STEP-preset_previewend; print hdr; undo; wait 1.2; print STEP-undo; print hdr; undo; wait 1.2; print STEP-undo; print hdr; redo; wait 1.2; print STEP-redo; print hdr; history open; wait 1.2; print STEP-history_open; print hdr; history revert 3; wait 1.2; print STEP-history_revert_3; print hdr; tab info; wait 1.2; print STEP-tab_info; print hdr; tab adjust; wait 1.2; print STEP-tab_adjust; print hdr; review on; wait 1.2; print STEP-review_on; print hdr; review off; wait 1.2; print STEP-review_off; print hdr; print adjustments; grid; wait 1; loupe; wait 3; print STEP-grid-and-back; print hdr; quit
```

Every step: choice on, `shown hdr`, `hdr fitted` (maps: badge `none`, SDR map
frame, then `hdr fitted` again), inspector histogram `hdr`; at Exposure −3 the
share above white is 0.000 and the version stays HDR. The two `undo` and one
`redo` after the preset preview changed nothing (the script's preview commands
leave empty undo steps), so undo is shown by S11.

#### S9: offline (`$R/qa282.dmg`, FAT32, library of the three HEICs and PLAIN.jpg on it)

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

#### S10: narrow captions (Q3)

```
wait 2; hdr display 16; focus IMG_0561; loupe; inspector on; wait 3; windowsize 760 560; wait 2; key 5; wait 2; tab adjust; adjust hdr on; wait 5; print hdr; snapshot $R/b-min-hdr-5.png; duplicate; wait 5; print hdr; snapshot $R/b-min-hdr-copy.png; hdr off; wait 2; print hdr; snapshot $R/b-min-hidden-copy.png; quit
```

Run after a script that had left HDR hidden (the fifth star over the warning
mark, no copy):

```
wait 2; hdr display 16; focus IMG_0561; loupe; inspector on; wait 3; windowsize 760 560; wait 2; key 5; wait 2; snapshot $R/min-sdr-5.png; tab adjust; adjust hdr on; wait 5; snapshot $R/min-hdr-5.png; duplicate; wait 4; snapshot $R/min-hdr-copy.png; hdr off; wait 2; snapshot $R/min-hidden-copy.png; windowsize 900 600; wait 2; snapshot $R/w900-hidden-copy.png; windowsize 1000 640; wait 2; snapshot $R/w1000-hidden-copy.png; windowsize 760 560; wait 1; hdr on; focus PLAIN; wait 3; key 5; wait 1; duplicate; wait 4; snapshot $R/min-plain-copy.png; quit
```

Comparison caption (in S13's second script).

#### S11: undo and redo (follows S8's library)

```
wait 2; hdr display 2; focus IMG_0561; loupe; inspector on; tab adjust; wait 5; adjust exposure -1; wait 2; print STEP-ev-1; print hdr; adjust exposure 1; wait 2; print STEP-ev1; print hdr; print undo; undo; wait 3; print STEP-undo; print hdr; redo; wait 3; print STEP-redo; print hdr; zoom; wait 3; undo; wait 3; print STEP-undo-at-100; print hdr; redo; wait 3; print STEP-redo-at-100; print hdr; quit
```

HDR throughout; share above white 0.082, 0.470, 0.082, 0.470, and the same at
100%.

#### S12: `photocli` (library of IMG_0542, IMG_0546, PLAIN.jpg; app closed)

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

#### S13: export notice

```
wait 2; hdr display 16; focus IMG_0546; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 4; export window; export print; export windowshot $R/export1.png; export close; focus IMG_0561; wait 3; adjust hdr on; wait 4; grid; wait 1; selectall; wait 1; export window; export print; export windowshot $R/export2.png; export close; focus PLAIN; wait 1; export window; export print; export windowshot $R/export0.png; export close; focus IMG_0561; loupe; wait 4; hdr off; wait 2; snapshot $R/caption-wide.png; windowsize 900 600; wait 2; snapshot $R/caption-narrow.png; windowsize 760 520; wait 2; print hdr; snapshot $R/caption-narrower.png; duplicate; wait 3; rating any; key 5; wait 1; flag any; wait 1; snapshot $R/caption-copy.png; compare on; wait 3; snapshot $R/caption-compare.png; print compare; quit
```

Nothing was exported (`export run` was not used).

#### S14: 100% and returning to the loupe

```
wait 2; compare animate off; hdr on; hdr display 16; focus IMG_0561; loupe; inspector on; tab adjust; wait 3; adjust hdr on; wait 5; grid; wait 1; hdr off; loupe; wait 4; zoom; wait 4; print STEP-100-hidden; print hdr; hdr on; wait 6; print STEP-100-shown; print hdr; original on; wait 3; hdr display 3; wait 3; print STEP-original-3; print hdr; hdr display 2; wait 3; print STEP-original-2; print hdr; original off; adjust mask add radial; adjust mask overlay on; wait 3; print STEP-overlay-2; print hdr; hdr display 3; wait 3; print STEP-overlay-3; print hdr; adjust mask overlay off; zoom; wait 3; grid; wait 1; loupe; wait 4; print STEP-grid-back; print hdr; compare on; wait 3; compare off; wait 3; print STEP-compare-back; print hdr; quit
```

After Show HDR at 100%: histogram `hdr above white 0.381`. Tile 3.00, 2.00, then
2.00, 3.00. `refits 0` throughout. (Comparison ends on the other pane's photo, a
plain JPEG, hence its last SDR line.)

#### S15: menu state (activated)

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

On the final build, after Q6 is fixed. Most important first. VoiceOver, macOS 15
and macOS 26 are left to CI. The early check of 2026-11-25 (design §13.1) passed
and the owner accepted the second change on arrival; it used a first-stage
build, and its record does not say which display or photo each check used.

### Setup

A library for the current build is ready at
`/Users/randy/gus-qa/gain-map-hdr-editing/signoff/library`: copies of the three
photos, `APPLE_0561.HEIC` (a copy of IMG_0561 with only Apple's gain map) and
`PLAIN.jpg` (synthetic, no gain map), every HDR choice off. The app copy beside
it was built at `e4c14b2`; the commands rebuild it. The early check's files are
untouched. Quit any running copy of the app, then run in order:

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

Turn HDR on with the **HDR** box at the top of the Adjust tab. The files go up to
2.6× (IMG_0546), 3.7× (IMG_0542), 4.6× (IMG_0561) and 4.7× (APPLE_0561) SDR
white. The **HDR** badge's help tag names what the display allows now when that
is less. The external display allowed about 1.3× during the build, so HDR looking
close to SDR there is expected.

| P | Do | Pass looks like | Covers |
| --- | --- | --- | --- |
| P1 | Turn HDR on for IMG_0561, IMG_0546 and APPLE_0561. Do this on a screen where the badge's help tag names no display limit, and once where it does. At fit, then at 100% (`Z`): drag and release Exposure, Contrast, a Tone Curve point, Sharpening to its maximum and a radial mask's Exposure. Press `\` | Brightness and color don't shift while dragging or on release, away from the edit too (a soft frame while moving is fine). Original is the unedited photo, still HDR. On a screen with room above white, APPLE_0561 visibly brightens when turned on, as the others do (it need not match IMG_0561 exactly) | AC8; M19; E2 repeated |
| P2 | On a display that allows less than the photo needs: quit, relaunch with the window there and the app in front, open a first HDR photo and wait 3 s. Then other photos, the grid, comparison (`S`), review (`F`), the window to the other display and back | At most one further change, about 1.5 s after HDR appears, on the first photo only. Badge stays **HDR**; its help tag gives the file's number and the display's | AC18; M9 |
| P3 | With an HDR photo open, change screen brightness: at rest, during a slider drag, at 100% with the mask overlay and then with Original, during Crop. Switch apps and back. Move the window between displays (an SDR one if there is one). At 100%: **View ▸ Hide HDR**, wait, **Show HDR**. On the external display at 200% (`⌘=`), panned to a corner, turn its HDR off and on in System Settings; repeat in comparison | The picture follows with no flash, spinner, lasting wrong level or repeated jumps; the histogram doesn't change with brightness and fills within a moment of Show HDR. An SDR display reads **SDR: No HDR Display** and HDR returns. Badge and picture agree, never loading for good; zoom and place stay (if only the System Settings change returns to 100%, note it for the proposed follow-up bug) | AC5; M10 to M12, M16, M17 |
| P4 | Turn HDR off and on, by the box and by `⌘Z`, at fit and at 100%. Arrow through the HDR photos and back; go to the grid and back | At most one change, SDR to HDR, on arrival. Off is SDR at once with no flash of HDR. Under an HDR picture the histogram is the HDR one or briefly its empty frame, never an SDR curve or another photo's | M2, M3 |
| P5 | Over an HDR photo: Crop, straighten, Done; Crop, Esc; Edit Spots (`H`), add a spot; save a preset and hover it; sharpening map on and off; fill a fringe color, Fringe Map on and off, then pick that slot again at 100%. Put crop, mask and spot handles over the brightest areas and paint a brush mask there | No flash of SDR. A map has no version badge and no brightness ramp around it. Picking turns the picture sharp and keeps it HDR. Handles are easy to find; the mask's red reads about as clearly as in SDR | M4 to M6; AC7 by eye |
| P6 | Compare an HDR photo with an SDR one, `A` to switch; then two HDR photos, the first time each is shown after a relaunch; review mode | Each pane has its own badge, with a small spinner if HDR takes over half a second; the histogram follows the active side without showing the other's curve | M13 |
| P7 | Adjust header, with Keyboard Navigation on and Tab. **Adjust** menu on the photo, while comparing and while cropping. **Adjust ▸ Reset All Adjustments**, then Undo. The HDR histogram with Increase Contrast off and on, in Light and Dark system appearance; watch the Tone Curve. Narrow the window to its minimum and step between photos | **HDR** box after **Original**, evenly spaced, reached by Tab. **Turn On / Off HDR** follows the choice and is dimmed while comparing and cropping. Reset turns HDR off, Undo restores it. Histogram line, fill, dashed lines and **HDR** mark readable; the curve's backdrop keeps its axis. The stars moving off center in a narrow caption doesn't read as jumpy | M1, M7, M8 |

## Follow-up

### Second pass, 2026-11-25, `e4c14b2`

| Finding | Result | Check |
| --- | --- | --- |
| Q1: Apple-only gain map showed SDR brightness | **Fixed** | T0 within 0.006 stops of the system's decode (was −0.84 to −0.94); T1 0.132, 0.131, 0.199, 0.021 above white (was 0.000) |
| Q2: choice changeable after an open photo went offline | **Fixed** | T5 (box, command); T8 (menu item, activated) |
| Q3: stars over the version badge at the minimum width | **Fixed** as reported; the fix brought Q6 | T11, Q3's cases |
| Q4: no Apple-only test; drift passed with no gain applied; no Color Fringes; record | **Fixed** | Both kinds in the HDR tests; AC6 checks the system's decode; Color Fringes and identity table cases; opt-in run T0; `status.md` and the PRD corrected (`spike.md` keeps its wording) |
| Q5: AC8 automated for a few stacks | **Fixed** | 58 cases pass |
| Designer's F12 (M18) | **Not fixed**: M18 fails | Q6 |

Open: Q6 (engineer), Q7 (designer's call). P1 to P7 not yet reported done.
