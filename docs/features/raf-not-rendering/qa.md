# RAF not rendering: QA

Owner: qa-tester. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md` (bug fix, issue #161).
Tested: `bug/raf-not-rendering` at `a7ff0c7`, on this Mac (Apple silicon), macOS 27.2.1 (26B131), macOS SDK 27.2
(bundle: `vtool` sdk 27.2, minos 15.0).

## Verdict

Passes. The bug shows on `develop` (X-E3 RAF `undecodable`; the engineer's test, cut to `develop`'s API, fails
there) and is gone on the branch: X-E3 photos render in the grid, the loupe (fitted and sharp at 100%),
`photocli` and export, and an X-T3 raw renders byte for byte as on `develop`. No findings. Six checks need a
person (P1 to P6).

Runs: `swift test` 879 tests in 131 suites passed, 1 known issue (`LiveSessionTests`, as before).
`RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF swift test --filter LibRawFallbackTests` 5 tests passed
(31 s). `Scripts/build-app.sh all` built both bundles.

## Acceptance criteria

The Bug section of `status.md` and the fixes reviewers asked for. "Script" includes `photocli` runs.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. Bug reproduces on `develop` | Script, Test | S1: `develop`'s `photocli render` of an X-E3 RAF gives `undecodable`. A scratch copy of `develop` with the engineer's test cut to its API (`QARawFallbackOnDevelopTests`, S1) fails with `undecodable` | Pass (bug shown) |
| B2. A raw the system decoder gives no image for renders (the Bug section's failing test) | Test | `LibRawFallbackPipelineTests.rawWithoutSystemImageRenders` (suite "LibRaw fallback") passes on the branch. Read: it decodes at three sizes and renders through `PreviewGenerator`; without the fallback it throws, as B1 shows | Pass |
| B3. On a real X-E3 file | Test | `LibRawFallbackTests` with `RAF_SAMPLE` (5 tests: no system image, pipeline, adjustments change the render, crop size, full and small sizes) | Pass |
| B4. Grid thumbnails of X-E3 photos | Script | S2: all six X-E3 tiles and the X-T3 tile show their photos (`shots/grid.png`), no grey tiles, no Activity message | Pass |
| B5. Loupe and film strip render | Script | S3: fitted loupe of `DSCF5123.RAF` shows the photo; film strip tiles filled; preview and thumbnail cached on disk (`print previews`) | Pass |
| B6. Sharp at 100% | Script | S5: after about 9 s the loupe holds the 5998x3997 rendition (bounds 2999x1998 points); the 100% snapshot is sharp (dog's fur, eyelashes) | Pass |
| B7. `photocli render` small, preview, full, crop | Script | S4: 600x400 (0.8 s, 385 MB peak), 2560x1706 (1.4 s, 442 MB), full 5998x3997 (12.4 s, 887 MB), a 0.3 crop at 2560 gives 1799x1199 (code review C4) | Pass |
| B8. Export | Script | S6: one X-E3 photo as full-size JPEG (5998x3997) and as 16-bit TIFF at long edge 2000 (2000x1333), no failures; the JPEG looks right | Pass |
| B9. Raws the system decodes are unchanged | Script, Test | S4: X-T3 `DSCF4583.RAF` at 600 px: same SHA-256 from the branch's and `develop`'s `photocli`. Goldens and references pass in `swift test` | Pass |
| C1. Concurrent LibRaw decodes are correct | Test | `concurrentDecodesMatchSoloDecodes`, `buildIsThreadSafe` | Pass |
| C2, Q3. One test of "raw"; the Adjust tab offers only what applies | Script, Test | S3: X-E3 `decoder fallback`, modes [As Shot, Auto, Custom], Temperature relative (0), Color and Decoder not shown; X-T3 `decoder system`, nine modes, 6,246 K, Color and Decoder shown. `oneTestOfWhatIsDecodedAsRaw`, `rendererAdjustsTheLibRawImage` | Pass |
| C2. Adjustments reach the render | Script, Test | S3: Temperature +40 visibly warms the X-E3 loupe (`loupe-xe3-warm.png`). `adjustmentsChangeTheRender` (real file) | Pass |
| C3. Decode settings do not decode again | Test | `decodeSettingsDoNotDecodeAgain` | Pass |
| C4. A crop decodes large enough | Test, Script | `cropDecodesLargeEnough`, `aCropDecodesLargeEnough`; S4 crop 1799x1199 | Pass |
| C7, F3. Machine learning reason is the camera | Script, Test | S3: dimmed check box, "Not available for this camera." as caption and tip. `machineLearningReasonIsTheCamera` | Pass |
| C13. Mirrored quarter turns | Test | `decodeIsOriented`, `frameFromSizes` | Pass |
| Auto White Balance follows the decoder | Test | `autoWhiteBalanceFollowsTheDecoder` (not scripted by me; the engineer's script in `status.md` shows relative 16, −22) | Pass |
| F1. Pasted machine learning on an X-E3 | Script | S3: after a paste from the X-T3: check box on and enabled, triangle, "Not applied: this camera isn't supported. Luminance applies instead."; badge "Machine Learning Not Applied" with "…It's shown with Luminance instead."; the render kept for the session only; turning it off gives the dimmed state back | Pass (text); look is P4 |
| F2, D5. Mode shows what renders | Script, Test | S3: pasted Daylight (5500 K kept in the stack) shows As Shot; Custom stored at 0/0 shows Custom and undo shows As Shot, on the X-E3 and on a JPEG; S5b: Temperature typed as 25 in its field saves `custom`, +25 and shows Custom. `relativeModeShown` | Pass (model); the pop-up's own pick is P6 |
| F4. The note's text | Script | S3: `print ml` prints the note word for word as F4 | Pass (text); look is P1 |
| M5. Switching photos keeps each photo's controls | Script | S3: X-E3 → X-T3 → X-E3 each print their own decoder, modes and Temperature; no value carried over | Pass (state); a visible jump is P5 |
| Q7. Several LibRaw photos at 100% | Script | S5: see Scripts. Stepping through six X-E3 photos 1.5 s apart at 100%: the last was sharp about 10 s after it was shown (about 8.5 s for one photo alone); memory rose to 1.65 GB resident at about 36 s and was 1.42 GB at 72 s (one photo alone: 1.26 GB peak) | Pass (measured, see note) |
| M1 to M4, M6 (look and real pointer) | Person | P1 to P6 | Open |

Note on Q7: the decodes started for photos already left keep running (memory climbs for about 35 s after the
last step), but they did not hold up the photo on screen (10 s against 8.5 s). Not a finding; it is what the
reviewer expected of an uncancellable decode, measured.

## Findings

None.

Not findings, for the record:

- The debug script's `adjust warmth` and `adjust wb` set values directly, without the slider's rule that
  also sets Mode to Custom, so `adjust warmth 40` leaves Mode on As Shot. The real field (`editvalue
  Temperature`) sets Custom (S5b). `menupick` drives only `MenuPopUpButton`s, so the Mode pop-up's own pick
  cannot be scripted (P6).
- The code review's nits C16 (no test of the retry without the stack's choices) and C17 (no frame size cap)
  stand as the reviewer recorded them.

## Scripts

`$S` is the scratch folder
`/private/tmp/claude-501/-Users-randy--claude-spares-spare-P85ePi/b35c93c8-ca57-4c41-a9c1-42b12b1359d5/scratchpad`.
The bundle copy is `$S/Gus.app` (identifier `me.sesser.gus.debugtest`, re-signed ad hoc), run by its
executable. Library: `photobench import --library-root $S/lib --source $S/masters` over copies of six X-E3
RAFs (`DSCF5123` to `DSCF5128`), the X-T3 `DSCF4583.RAF` and two `photobench generate` JPEGs. Grid order:
0 X-T3, 1 to 6 X-E3, 7 and 8 JPEG.

**S1, the bug on `develop`** (a clone of `develop` at `ef592d9` in `$S/dev`):

```
swift build -c release --product photocli
.build/release/photocli render $S/masters/xe3/DSCF5124.RAF --out $S/dev-xe3.png --long-edge 600
```

`{"code":"failed","error":"undecodable(…/DSCF5124.RAF)"}`. The X-T3 renders (600x400). The scratch test
(`Tests/PhotoCoreTests/QARawFallbackOnDevelopTests.swift` in that clone only): a 256 x 192 `SyntheticDNG`,
`PreviewGenerator.decode` at three sizes and `cgImage` at 200: `Caught error: .undecodable(…/small.dng)`,
failed.

**S2, grid:**

```
Gus --library-root $S/lib --debug-script "wait 3; print title; print items; windowsize 1400 900; size 200; wait 8; snapshot $S/shots/grid.png; print messages; quit"
```

9 photos; every tile shows its photo; `messages 0`.

**S3, loupe, Adjust tab, white balance, paste:**

```
Gus --library-root $S/lib --debug-script "wait 2; windowsize 1400 900; focus 1; loupe; tab adjust; ml ready; wait 4; snapshot $S/shots/loupe-xe3.png; print ml; print previews; adjust wb custom; wait 1; print ml; print adjustments; undo; wait 1; print ml; adjust warmth 40; wait 2; print ml; snapshot $S/shots/loupe-xe3-warm.png; adjust wb asShot; wait 1; print ml; focus 0; ml ready; wait 3; snapshot $S/shots/loupe-xt3.png; print ml; adjust wb daylight; ml on; wait 2; copyadjust; focus 2; ml ready; wait 3; pasteadjust; wait 3; print ml; print adjustments; snapshot $S/shots/loupe-xe3-pasted.png; ml off; wait 1; print ml; adjust wb custom; wait 1; print ml; focus 7; ml ready; wait 2; print ml; adjust wb custom; wait 1; print ml; undo; wait 1; print ml; quit"
```

Showed (abridged):

- X-E3: `decoder fallback wb mode 'As Shot' modes [As Shot, Auto, Custom] temperature … value 0 note 'macOS
  can't decode this raw file, so it's shown without a profile. Temperature and Tint are relative to the
  camera's white balance, and Color noise reduction isn't available.'`; `ml checkbox off enabled false tip
  'Not available for this camera.'`; `ml color not shown`; `ml decoder not shown`; `previews … disk preview
  true disk thumbnail true`.
- `adjust wb custom`: `wb mode 'Custom'`, stack `{"preset":"custom"}`, undo `Debug wb`; after `undo`: `'As Shot'`.
- X-T3: `decoder system wb mode 'As Shot' modes [As Shot, Auto, Daylight, Cloudy, Shade, Tungsten,
  Fluorescent, Flash, Custom] temperature … 6,246 K note none`; check box enabled; Color 50; Decoder `8 (default)`.
- Paste onto X-E3 `DSCF5124`: stack `{"preset":"daylight","temperature":5500,"tint":0}` and
  `{"machineLearning":true}`; `wb mode 'As Shot'`; `ml caption 'Not applied: this camera isn't supported.
  Luminance applies instead.' triangle true`; `checkbox on enabled true`; `badge 'Machine Learning Not
  Applied' help 'This photo is set to use machine learning noise reduction, which doesn't support its
  camera. It's shown with Luminance instead.'`; `sessionReason cameraNotSupported` (not on disk).
  `ml off`: dimmed "Not available for this camera." again.
- JPEG `IMG_00001`: `decoder not raw`, `adjust wb custom` shows `'Custom'`, `undo` shows `'As Shot'`.

**S4, `photocli`** (release build of the branch):

```
photocli render $S/masters/xe3/DSCF5124.RAF --out $S/br-xe3-600.png --long-edge 600
photocli render $S/masters/xe3/DSCF5124.RAF --out $S/br-xe3-2560.png --long-edge 2560
photocli render $S/masters/xe3/DSCF5124.RAF --out $S/br-xe3-full.png
photocli render $S/masters/xe3/DSCF5124.RAF --out $S/br-xe3-crop.png --long-edge 2560 --set crop.x=0.3 --set crop.y=0.3 --set crop.width=0.3 --set crop.height=0.3
photocli render $S/masters/xt3/DSCF4583.RAF --out $S/br-xt3-600.png --long-edge 600
```

Under `/usr/bin/time -l`: 600x400 0.82 s, 385 MB peak footprint; 2560x1706 1.44 s, 442 MB; full 5998x3997
12.4 s (render 8.9 s), 888 MB; crop 1799x1199, full detail at 1:1. X-T3 PNG SHA-256 `6c07dff3…` equal to
`develop`'s.

**S5, Q7 at 100%** (memory sampled from outside with `ps -o rss` once a second):

```
Gus --library-root $S/lib --debug-script "wait 2; windowsize 1400 900; focus 1; loupe; ml ready; wait 3; zoom; wait 1; print viewport; focus 2; wait 1.5; focus 3; wait 1.5; focus 4; wait 1.5; focus 5; wait 1.5; focus 6; <wait 1; print viewport> x 60; print frames; quit"
```

Magnification 1.000 kept across photos. The sixth photo's bounds went from 3000x2000 (preview) to 2999x1998
(the 5998x3997 rendition, nearest filtering on) at the 10th poll, about 10 s after it was shown. Resident
memory: 0.6 GB at 5 s, 1.13 GB at 16 s, 1.46 GB at 26 s, peak 1.65 GB at 36 s, 1.42 GB at 72 s. Alone (the
same with `focus 6` only, polled every 0.5 s): sharp at about 8.5 s, peak 1.26 GB. A snapshot at 100% after
12 s (`shots/xe3-100.png`, `DSCF5126`) is sharp.

**S5b, the Temperature field:**

```
Gus --library-root $S/lib --debug-script "wait 2; windowsize 1400 900; focus 3; loupe; tab adjust; ml ready; wait 3; print ml; editvalue Temperature; text 25; key return; wait 2; print ml; print adjustments; quit"
```

`wb mode 'Custom' … temperature … value +25`, undo `Temperature`, stack `{"preset":"custom","relativeTemperature":25}`.

**S6, export:**

```
Gus --library-root $S/lib --debug-script "wait 2; windowsize 1400 900; focus 4; loupe; ml ready; wait 2; zoom; wait 12; print viewport; snapshot $S/shots/xe3-100.png; grid; focus 4; export window; export set format=jpeg size=full dest=$S/export; export run; export set size=long:2000 format=tiff bits=16; export run; print messages; quit"
```

`exported 1 … failed 0`, `DSCF5126.jpg` 5998x3997 and `DSCF5126.tif` 2000x1333; Activity "Exported 1 photo."

After the runs: no instance of the app running; nothing under `~/Library/Application Support/Gus` and not
`me.sesser.gus.plist` newer than the start of QA.

## For a person

Use a scratch library with an X-E3 RAF (macOS can't decode it), the X-T3 RAF and a JPEG, in the bundle
(`Scripts/build-app.sh`), launched with `--library-root`.

- **P1 (M1). The note's look.** X-E3, Adjust tab: under "Profile" (no check box) the note wraps inside the
  inspector at its narrowest width, in 3 or 4 lines, with clear space before White Balance, readable with
  Increase Contrast on. No pop-ups under Profile.
- **P2 (M2). White Balance by hand.** X-E3: Mode lists As Shot, Auto, Custom. Drag Temperature and Tint
  (−100 to 100, start at 0): the photo warms and tints while dragging, and Mode shows Custom. Auto changes
  the photo and shows Auto; As Shot puts both sliders back to 0.
- **P3 (M3). Machine learning, dimmed.** X-E3, Details ▸ Noise Reduction: Use machine learning dimmed,
  "Not available for this camera." under it and as its tooltip; Luminance only, no Color row.
- **P4 (M4). Paste from the X-T3.** On the X-T3 set Daylight and turn on Use machine learning; Copy
  Adjustments; paste onto the X-E3 with the menu or ⌘ keys. Mode shows As Shot; the photo's color did not
  change; the check box is on with the triangle and its caption; the loupe caption's Machine Learning Not
  Applied badge shows, and its tooltip ends "…It's shown with Luminance instead." Turning it off removes both.
- **P5 (M5). Switching photos.** Arrow between the X-T3 and an X-E3 in the loupe with the Adjust tab open:
  the Profile group and the note swap, Kelvin and relative sliders swap, no value or mode carries over. Note
  any visible jump while the X-E3 loads.
- **P6 (M6). Custom sticks, with the pop-up.** On the JPEG and on the X-E3 with Temperature and Tint at 0,
  choose Custom from the Mode pop-up with the mouse: it stays Custom; ⌘Z returns it to As Shot; choosing As
  Shot again leaves the sliders at 0.

## Follow-up

None yet.

## Summary for the issue

QA (2026-11-13), `bug/raf-not-rendering` at `a7ff0c7`: **passes, no findings.** The bug reproduces on
`develop` (X-E3 RAF `undecodable`; the Bug section's test fails there) and is gone on the branch: grid
thumbnails, loupe (sharp at 100% in about 9 s), `photocli` (600 px 0.8 s, full 12 s, crop 1799x1199) and
export (full JPEG, 16-bit TIFF) all render X-E3 files; the X-T3 renders byte for byte as on `develop`.
`swift test` 879 passed (1 known issue), `LibRawFallbackTests` with `RAF_SAMPLE` 5 passed, both bundles built.
White balance modes, D5's Mode rule, the note and machine learning texts checked by script. Q7: six X-E3
photos at 100% in a row peak at 1.65 GB, the last sharp in about 10 s.
Open for a person: P1 to P6 (the designer's M1 to M6: looks and real mouse use).
Full record: `docs/features/raf-not-rendering/qa.md`
