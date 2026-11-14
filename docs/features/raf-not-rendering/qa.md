# RAF not rendering: QA

Owner: qa-tester. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md` (bug fix, issue #161).
Tested: `bug/raf-not-rendering` at `8aedc11` (second run; the first run, at `a7ff0c7`, is under Follow-up), on
this Mac (Apple silicon), macOS 27.2.1 (26B131), macOS SDK 27.2 (bundle: `vtool` sdk 27.2, minos 15.0).

## Verdict

Passes, with no findings. The bug shows on `develop`, where an X-E3 RAF is `undecodable` and the Bug section's
test fails. On this branch, X-E3 photos render in the grid, the loupe, `photocli` and export. They render in the
camera's 6000x4000 frame and with its lens corrections. The window frame in `DSCF5124` is straight and sits where
the camera's own JPEG puts it, to within 3 JPEG pixels. Unlike the first run's render, the corners are no longer
dark. A clipped sky at Exposure −2 is flat from 0.3 of the radius out to the corners. The X-T3 renders byte for
byte as on `develop`. Seven checks need a person (P1 to P7).

Runs at `8aedc11`:

- `swift test`: 906 tests in 133 suites passed, with 1 known issue (`LiveSessionTests`, as before).
- `RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF swift test --filter LibRawFallbackTests`: 7 tests passed.
  The same suite also passed with `DSCF5124`, `DSCF5139` and `DSCF5170` as the sample (numbers below).
- `Scripts/build-app.sh all`: both bundles built.
- The app ran on a new scratch library with an empty preview cache, so none of the earlier builds' cached previews
  were shown.

## Acceptance criteria

The Bug section of `status.md`, the fixes reviewers asked for, and the new scope: the camera's frame and Fujifilm
lens corrections. "Script" includes `photocli` runs.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. Bug reproduces on `develop` | Script, Test | First run, S1. On `develop` (`ef592d9`, which has not changed), `photocli render` of an X-E3 RAF gives `undecodable`. The engineer's test, cut to `develop`'s API, fails with `undecodable` | Pass (bug shown) |
| B2. A raw the system decoder gives no image for renders | Test | `LibRawFallbackPipelineTests.rawWithoutSystemImageRenders` (suite "LibRaw fallback") | Pass |
| B3. On real X-E3 files | Test | `LibRawFallbackTests` with `RAF_SAMPLE`: 7 tests, including `theFrameIsTheCameras` and `theCorrectedRenderLinesUpWithTheCamerasJPEG`, on `DSCF5123`, `5124`, `5139` and `5170` | Pass |
| B4. Grid thumbnails from an empty cache | Script | S2: all six X-E3 tiles and the X-T3 tile show their photos. No grey tiles, no Activity message | Pass |
| B5. Loupe, fitted | Script | S2: `DSCF5124` fills the loupe, with straight window jambs (`shots2/loupe-5124.png`). Its preview and thumbnail are cached on disk | Pass |
| B6. Sharp at 100% | Script | S4: one X-E3 alone is sharp about 9 s after it is shown. The 100% snapshot shows grass detail | Pass |
| N1. The camera's frame, 6000x4000 | Script, Test | S3: the full `photocli` render is 6000x4000 (it was 5998x3997). Export at full size is 6000x4000, at 50% 3000x2000, at long edge 2000 2000x1333. A 0.3 crop at 2560 gives 1800x1200. `theFrameIsTheCameras` | Pass |
| N2. Straight lines, as in the camera's JPEG | Script, Test | S5: the bright column of `DSCF5124`'s right jamb, in four row bands, at 1920 px. Corrected: 1825, 1810, 1808, 1807. Camera JPEG: 1828, 1810, 1809, 1808. Uncorrected (first run's build): 1782, 1792, 1794, 1790, a bowed line. The left jamb is within 1 px of the camera's. Block match (`theCorrectedRenderLinesUpWithTheCamerasJPEG`): see S5 | Pass (numbers); look is P1 |
| N3. Corner shading undone | Test, Script | Light far from the center, against the camera's JPEG, relative to near it: `DSCF5139` 1.0006 (the lens passes 0.66 at 0.85 of the radius), `DSCF5170` 1.003 (lens 0.56). `DSCF5124` and `DSCF5123` are too dark to measure. S5: `DSCF5124`'s 5x5 grid, corrected over uncorrected, gives about 1.02 in the middle and 1.36 to 1.43 in the corner cells | Pass (numbers); look is P2 |
| N4 (C19). A clipped highlight at Exposure −2 is flat to the corners | Script, Test | `gainEndsAtWhite`. | S6: `DSCF5134` (XF 35mm, sky clipped in both top corners). The pixels clipped at Exposure 0 read 0.5371 to 0.5375 on average at Exposure −2, in every tenth of the radius from 0.3 to 0.9 and in every column band. Spread within a band: 0.5366 to 0.5429 | Pass |
| N5. Raws the system decodes are unchanged | Script, Test | S3: the X-T3 `DSCF4583.RAF` from the branch's and `develop`'s `photocli`, compared by SHA-256: same at 600 px unedited, +1 EV, Custom 4000 K tint 10, at 1600 px −2 EV, and as a full-size TIFF (`cmp`). Goldens and references pass | Pass |
| N6. `photocli` at several sizes | Script | S3: 256 (1.1 s, 427 MB), 600 (0.8 s), 1920 (1.1 s), 2560 (1.4 s, 482 MB), 3000 (1.7 s, 419 MB, half-size decode), 4000 (10.5 s, 1.15 GB), full (12.3 s, 1.04 GB), all 3:2 | Pass |
| N7. Export | Script | S7: full JPEG 6000x4000, 16-bit TIFF at long edge 2000 (2000x1333), JPEG at 50% (3000x2000). No failures. The top-right corner of the full export has a straight jamb (`r2/cmp-export-tr.png`) | Pass |
| C1. Concurrent LibRaw decodes are correct | Test | `concurrentDecodesMatchSoloDecodes`, `buildIsThreadSafe` | Pass |
| C2, Q3. The Adjust tab offers only what applies | Script, Test | S2: X-E3 shows `decoder fallback`, modes [As Shot, Auto, Custom], relative Temperature, no Color or Decoder. X-T3 shows `decoder system`, nine modes, 6,246 K, Color and Decoder. `oneTestOfWhatIsDecodedAsRaw`, `rendererAdjustsTheLibRawImage` | Pass |
| C2. Adjustments reach the render | Script, Test | S2: Temperature typed as 40 saves `custom` +40 and the loupe warms (`shots2/loupe-5124-warm.png`). Auto White Balance stores `auto`, relative 26, −25. `adjustmentsChangeTheRender` | Pass |
| C3, C4, C13, C16 to C18, C20, C21 | Test | `decodeSettingsDoNotDecodeAgain`, `cropDecodesLargeEnough`, `decodeIsOriented`, `frameFromSizes`, `decoderOrder`, `sensorSizeLimit`, `cameraFrameAndSensorLayout`, `readsARealNineKnotLayout`, `decodeFramesAndCorrects`, `whichTablesADecodeUses`, plus `FujifilmRAFTests` and `EmbeddedLensTests` (all in the default run) | Pass |
| C7, F3. The machine learning reason is the camera | Script, Test | S2: dimmed check box, with "Not available for this camera." as caption and tip. `machineLearningReasonIsTheCamera` | Pass |
| F1. Machine learning pasted onto an X-E3 | Script | S2: paste from the X-T3. Check box on and enabled, triangle shown, "Not applied: this camera isn't supported. Luminance applies instead." The badge's help ends "…It's shown with Luminance instead." The render is kept for this session only. `ml off` brings the dimmed state back | Pass (text); look is P5 |
| F2, D5. Mode shows what renders | Script, Test | S2: a pasted Daylight (5500 K kept) shows As Shot. Custom stored at 0/0 shows Custom, and undo shows As Shot, on the X-E3 and on a JPEG. Typing a Temperature shows Custom. `relativeModeShown` | Pass (model); the pop-up's own pick is P7 |
| F4. The note's text | Script | S2: `print ml` prints it word for word | Pass (text); look is P3 |
| M5. Switching photos keeps each photo's controls | Script | S2: X-E3, then X-T3, then X-E3: each prints its own decoder, modes and Temperature | Pass (state); a visible jump is P6 |
| Q7. Several LibRaw photos at 100% | Script | S4: six X-E3 photos 1.5 s apart at 100%. The last was sharp about 10 s after it was shown (one alone: about 9 s). Resident memory peaked at 1.49 GiB at about 47 s and stayed there to the end (one alone: 1.40 GiB, after a JPEG at 100%) | Pass (measured) |
| M1 to M4, M6, the look of the corrections | Person | P1 to P7 | Open |

Note on Q7: decodes started for photos already left keep running, so memory climbs for about 30 s after the last
step. They did not delay the photo on screen. This was measured, not filed as a finding.

## Findings

None.

Not findings, for the record:

- **Debug script:** `adjust warmth` and `adjust wb` set values directly, without the slider's rule that also sets
  Mode to Custom. The real field (`editvalue Temperature`) does set Custom.
- **Debug script:** `menupick` drives only `MenuPopUpButton`s, so the Mode pop-up's own pick cannot be scripted
  (P7).
- **Debug script:** `zoom` sometimes does not reach the loupe right after `loupe` on a scripted launch
  (magnification stays 0.244). Zooming on another photo first, then focusing the one to time, works.
- **Lens corrections:** the outer quarter of the radius is about 3 full-size pixels off the camera's JPEG with the
  35mm (the block-match tables in S5 show it). The engineer and reviewer list this as the owner's call, together
  with Q12 to Q14 and C23.

## Scripts

`$S` is `/private/tmp/claude-501/-Users-randy--claude-spares-spare-P85ePi/b35c93c8-ca57-4c41-a9c1-42b12b1359d5/scratchpad`.

- **Bundle:** a copy of `build/Gus.app` at `8aedc11` in `$S/Gus.app`, identifier `me.sesser.gus.debugtest`,
  re-signed ad hoc and run by its executable.
- **Library:** `$S/lib2`, made new by `photobench import --library-root $S/lib2 --source $S/masters`, with an
  empty `Previews` folder. Grid order: 0 X-T3 `DSCF4583`, 1 to 6 X-E3 `DSCF5123` to `DSCF5128`, 7 and 8 JPEG.
- **Extra X-E3 copies** for `photocli` only, in `$S/masters2`: `DSCF5129`, `5134`, `5139`, `5162`, `5163`,
  `5170`.
- **Camera JPEGs:** `exiftool -b -PreviewImage` (1920x1280).
- **Measuring helpers:** `stats`, `clip`, `profile` and `compose` in `$S/tools`. Each is a small Swift program
  that reads images through ImageIO; they are not part of the repository.

**S2, grid, loupe, Adjust tab, white balance, paste (empty cache):**

```
Gus --library-root $S/lib2 --debug-script "wait 3; print items; windowsize 1400 900; size 200; wait 10; snapshot $S/shots2/grid.png; print messages; focus 2; loupe; tab adjust; ml ready; wait 4; snapshot $S/shots2/loupe-5124.png; print ml; print previews; adjust wb custom; wait 1; print ml; print adjustments; undo; wait 1; print ml; editvalue Temperature; text 40; key return; wait 3; print ml; snapshot $S/shots2/loupe-5124-warm.png; undo; wait 1; print ml; adjust auto wb; wait 2; print adjustments; undo; wait 1; focus 0; ml ready; wait 3; snapshot $S/shots2/loupe-xt3.png; print ml; adjust wb daylight; ml on; wait 2; copyadjust; focus 2; ml ready; wait 3; pasteadjust; wait 3; print ml; print adjustments; ml off; wait 1; print ml; adjust wb custom; wait 1; print ml; focus 7; ml ready; wait 2; adjust wb custom; wait 1; print ml; undo; wait 1; print ml; quit"
```

What it showed (abridged):

- **Thumbnails:** all nine filled; `messages 0`.
- **`DSCF5124` as loaded:** `decoder fallback wb mode 'As Shot' modes [As Shot, Auto, Custom] temperature … value
  0 note 'macOS can't decode this raw file, so it's shown without a profile. Temperature and Tint are relative to
  the camera's white balance, and Color noise reduction isn't available.'`; `ml checkbox off enabled false tip
  'Not available for this camera.'`; `previews … disk preview true disk thumbnail true`.
- **White balance edits on `DSCF5124`:**
  - `adjust wb custom` shows `'Custom'`, stack `{"preset":"custom"}`. After `undo`: `'As Shot'`.
  - Temperature 40: `'Custom'`, `value +40`, undo `Temperature`.
  - Auto: `{"preset":"auto","relativeTemperature":26,"relativeTint":-25}`.
- **X-T3:** `decoder system`, nine modes, `6,246 K`, check box enabled, Decoder `8 (default)`.
- **Paste onto `DSCF5124`:** `{"preset":"daylight","temperature":5500,"tint":0}` plus machine learning on. Mode
  `'As Shot'`, the F1 caption with the triangle, check box on and enabled, the badge and its help. After
  `ml off`: dimmed again. Then `adjust wb custom` shows `'Custom'`.
- **JPEG:** `adjust wb custom` shows `'Custom'`; `undo` shows `'As Shot'`.

**S3, `photocli`** (release build at `8aedc11`; `develop`'s release build from the first run, in `$S/dev`):

```
photocli render $S/masters/xe3/DSCF5124.RAF --out … --long-edge 256|600|1920|2560|3000|4000
photocli render $S/masters/xe3/DSCF5124.RAF --out …
photocli render $S/masters/xe3/DSCF5124.RAF --out … --long-edge 2560 --set crop.x=0.3 --set crop.y=0.3 --set crop.width=0.3 --set crop.height=0.3
photocli render $S/masters/xt3/DSCF4583.RAF --out … --long-edge 600 [--set exposure.ev=1 | --set whiteBalance.preset=custom --set whiteBalance.temperature=4000 --set whiteBalance.tint=10]
photocli render $S/masters/xt3/DSCF4583.RAF --out … --long-edge 1600 --set exposure.ev=-2
photocli render $S/masters/xt3/DSCF4583.RAF --out full.tif
```

Sizes, times and memory are in N1 and N6. All five X-T3 outputs are identical to `develop`'s.

**S4, Q7 at 100%** (resident memory sampled from outside once a second):

```
Gus --library-root $S/lib2 --debug-script "wait 2; windowsize 1400 900; focus 1; loupe; ml ready; wait 3; zoom; wait 1; print viewport; focus 2; wait 1.5; focus 3; wait 1.5; focus 4; wait 1.5; focus 5; wait 1.5; focus 6; <wait 1; print viewport> x 60; quit"
Gus --library-root $S/lib2 --debug-script "wait 2; windowsize 1400 900; focus 7; loupe; wait 3; zoom; wait 1; print viewport; focus 6; wait 0.2; print viewport; <wait 0.5; print viewport> x 30; snapshot $S/shots2/xe3-100.png; quit"
```

- **Indicator:** magnification stayed at 1.000. The loupe's image view switches to `nearest true` when the
  full-resolution rendition arrives, and that switch is used as "sharp".
- **First run:** the switch came at the 10th poll after the last step, about 10 s. Memory: 0.72 GiB at 5 s,
  1.11 GiB at 10 s, 1.47 GiB at 26 s, peak 1.49 GiB at about 47 s.
- **Second run:** the switch came at about 9 s, with a peak of 1.40 GiB. The 100% snapshot is sharp.

**S5, the corrections against the camera's JPEG (`DSCF5124`, XF 35mm f/2):**

- **Inputs:** the corrected render at 1920 px (`photocli`), the camera's embedded JPEG (1920x1280), and the first
  run's uncorrected 2560 px render scaled to 1920.
- **Visual:** `$S/r2/cmp-whole.png` and `$S/r2/cmp-left.png` (uncorrected | corrected | camera). The uncorrected
  left jamb bows; the corrected one is straight like the camera's.
- **Jamb positions:** `profile` finds the brightest column of the right jamb (x 1700 to 1900) in row bands
  0.05–0.15, 0.25–0.35, 0.45–0.55 and 0.65–0.75. The figures are in N2.
- **`theCorrectedRenderLinesUpWithTheCamerasJPEG`**, in JPEG pixels (one JPEG pixel is 3.1 full-size pixels):

  | File | Blocks | Median | 90th percentile | Beyond 0.75 of the radius | Uncorrected median | Light far / near |
  | --- | --- | --- | --- | --- | --- | --- |
  | `DSCF5124` | 536 | 0.36 | 1.07 | 0.89 | 5.6 | too dark |
  | `DSCF5139` | 866 | 0.43 | 1.43 | 0.95 | 5.0 | 1.0006 |
  | `DSCF5170`, 14mm | 858 | 0.27 | 0.73 | 0.43 | 1.9 | 1.003 |

**S6, a clipped highlight at Exposure −2 (`DSCF5134`, XF 35mm, sky clipped in the top corners):**

```
photocli render $S/masters2/DSCF5134.RAF --out hl-5134-0.png --long-edge 1500
photocli render $S/masters2/DSCF5134.RAF --out hl-5134-m2.png --long-edge 1500 --set exposure.ev=-2
clip hl-5134-0.png hl-5134-m2.png 0.15
```

Pixels with all channels at 0.999 or more at Exposure 0, read at Exposure −2, by tenth of the half diagonal:

| Radius | 0.3 | 0.4 | 0.5 | 0.6 | 0.7 | 0.8 | 0.9 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Mean | 0.5375 | 0.5372 | 0.5372 | 0.5371 | 0.5372 | 0.5374 | 0.5373 |

Column bands of the top 15% read 0.5371 to 0.5374. Flat, with no lift toward the corners.

Other photos were tried first and set aside:

- `DSCF5128` and `DSCF5170`: only the sun is clipped.
- `DSCF5129`: its sky is not clipped in the raw. At Exposure −2 it shows a smooth gradient, so it shows neither
  way.

**S7, export (`DSCF5124`):**

```
Gus --library-root $S/lib2 --debug-script "wait 2; windowsize 1400 900; focus 2; loupe; wait 3; export window; export set format=jpeg size=full dest=$S/export2; export run; export set size=long:2000 format=tiff bits=16; export run; export set size=percent:50 format=jpeg; export template half-{name}; export run; print messages; quit"
```

`DSCF5124.jpg` 6000x4000, `DSCF5124.tif` 2000x1333 and `half-DSCF5124.jpg` 3000x2000. Each export reported
`failed 0`.

After the runs:

- No instance of the app is running.
- Nothing under `~/Library/Application Support/Gus` is newer than the start of this run, and neither is
  `me.sesser.gus.plist`.
- The working tree is clean, apart from this file.

## For a person

Build the bundle (`Scripts/build-app.sh`) and launch it with `--library-root` on a scratch library. Delete the
preview cache first if the library was opened by an earlier build of this branch. Put in it `DSCF5124.RAF` (X-E3,
which macOS can't decode), the X-T3 `DSCF4583.RAF` and a JPEG.

- **P1. `DSCF5124`'s window frame (the owner's screenshot).** Open it in the loupe, fitted and at 100%. The
  window's vertical jambs, left and right, are straight lines from top to bottom with no bow. The window sits in
  the picture where the camera's JPEG has it (compare with that JPEG, or with `$S/r2/cmp-whole.png`). Nothing
  looks stretched near the edges.
- **P2. The corners.** In `DSCF5124` and a brighter X-E3 photo with the 35mm (`DSCF5139`, `DSCF5134`), the
  corners are not darker than the camera's JPEG shows them. There is no dark ring and no bright ring, and no
  color fringe on high-contrast edges near the corners. At Exposure −2, a blown sky in a corner stays an even
  grey.
- **P3 (M1). The note's look.** X-E3, Adjust tab. Under "Profile" (no check box), the note wraps inside the
  inspector at its narrowest width, in 3 or 4 lines, with clear space before White Balance. It is readable with
  Increase Contrast on. There are no pop-ups under Profile.
- **P4 (M2, M3). White Balance and Noise Reduction by hand.**
  - White Balance: Mode lists As Shot, Auto and Custom. Dragging Temperature and Tint warms and tints the photo,
    and Mode shows Custom. Auto changes the photo and shows Auto. As Shot puts both sliders back to 0.
  - Noise Reduction: Use machine learning is dimmed, with "Not available for this camera." under it and as its
    tooltip. There is Luminance only, with no Color row.
- **P5 (M4). Paste from the X-T3.**
  - On the X-T3, set Daylight and turn on Use machine learning, then Copy Adjustments. Paste onto the X-E3 with
    the menu or the keyboard shortcut.
  - Mode shows As Shot, and the photo's color does not change.
  - The check box is on, with the triangle and its caption. The loupe caption shows the Machine Learning Not
    Applied badge, and its tooltip ends "…It's shown with Luminance instead."
  - Turning the check box off removes both.
- **P6 (M5). Switching photos.** In the loupe, with the Adjust tab open, arrow between the X-T3 and the X-E3.
  The Profile group and the note swap, the Kelvin and relative sliders swap, and no value or mode carries over.
  Note any visible jump while the X-E3 loads.
- **P7 (M6). Custom sticks, with the pop-up.** On the JPEG and on the X-E3, with Temperature and Tint at 0,
  choose Custom from the Mode pop-up with the mouse. It stays Custom, and ⌘Z returns it to As Shot. Choosing As
  Shot again leaves the sliders at 0.

## Follow-up

**First run (2026-11-13, at `a7ff0c7`, before the camera frame and lens corrections).**

- **Verdict:** passed, no findings.
- **Bug on `develop`:** `photocli` gave `undecodable`, and the engineer's test, cut to `develop`'s API
  (`QARawFallbackOnDevelopTests` in a scratch clone of `develop`), failed with `undecodable`.
- **Tests and build:** `swift test` 879 passed; the sample suite 5 passed; both bundles built.
- **Frame:** LibRaw's inset crop, 5998x3997.
- **Q7:** the last photo was sharp in about 10 s. Memory peaked at 1.57 GiB. The first version of this file said
  "1.65 GB" for the same figure, 1,645,888 KB; that is 1.69 GB decimal, so it was a slip.

**Second run (2026-11-13, at `8aedc11`):** this file above. Everything above was re-checked on a new library with
an empty cache. The new checks are N1 to N7, C16 to C21, and P1 and P2.

## Summary for the issue

QA second run (2026-11-13), `bug/raf-not-rendering` at `8aedc11`: **passes, no findings.** The run started from a
new scratch library with an empty cache.

- **Frame and lines:** X-E3 photos render in the camera's 6000x4000 frame. Grid, loupe (sharp at 100% in about
  9 s), `photocli` at 256 px to full size, and export (full, 50%, long edge 2000) all checked. `DSCF5124`'s window
  jambs are straight and within 3 JPEG pixels of the camera's JPEG (uncorrected: up to 43 px off).
- **Light:** the corner light against the camera's JPEG is 1.0006 (35mm) and 1.003 (14mm). A sky clipped at
  Exposure −2 is flat to the corners (0.537 at every radius).
- **Unchanged files:** the X-T3 is byte for byte as on `develop` (five renders).
- **Adjust tab:** checked by script, D5 included.
- **Q7:** six X-E3 photos at 100% in a row peak at 1.49 GiB; the last is sharp in about 10 s.
- **Tests and build:** `swift test` 906 passed (1 known issue). The `RAF_SAMPLE` suite passed (7 tests) on four
  files. Both bundles built.

Open for a person: P1 to P7. These are the window frame and the corners by eye, plus the designer's M1 to M6.
Full record: `docs/features/raf-not-rendering/qa.md`
