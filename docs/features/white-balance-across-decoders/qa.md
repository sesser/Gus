# White balance and baseline look across decoders: QA

Owner: qa-tester. Date: 2026-11-14. Step 4 of `docs/WORKFLOW.md` (feature, issue #170).
Tested: `feature/libraw-color-pipeline` at `afba824`, on this Mac (Apple silicon), macOS 27.2.1 (26B131), macOS
SDK 27.2. The bundle reports `vtool` sdk 27.2, minos 15.0. Compared against `develop` at `868f8f6`.

## Verdict

Passes, with no findings. Thirteen of the fourteen acceptance criteria pass by test, and the parts that can be
scripted also pass by script. AC5 is recorded as **measured, accepted by the owner 2026-11-14**, not passed:
- For the X-T3, LibRaw's as-shot Kelvin is 14% to 30% below the system decoder's.
- The X-E3 file that both decoders read is 1.5% below.

Nothing changed for photos the system decoder reads, or for JPEGs: their `photocli` renders are byte for byte
`develop`'s. Ten checks need a person (P1 to P10), including AC6's side-by-side look.

Runs at `afba824`:

- `swift test`: 993 tests in 144 suites passed, with 1 known issue (`LiveSessionTests`, as on `develop`).
- `RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF swift test --filter LibRawFallbackTests`: 9 passed.
- `RAW_LOOK_SAMPLES=<9 files> swift test --filter BaselineLookMeasurementTests`: passed. The built-in curve is
  within 0.0006 of the fresh measurement; exposure 0.070 EV against 0.070.
- `RAW_BOTH_SAMPLES=<11 files> swift test --filter LibRawAgainstSystemTests`: passed. Every printed number is the
  one in `status.md`'s table.
- `Scripts/build-app.sh all`: both bundles built.

The sample files are listed under Scripts.

## Acceptance criteria

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| AC1 (R1, R2). Nine modes and Kelvin on an X-E3; Tungsten is 2850 K / 0 and changes the render | Test, Script | `WhiteBalanceAcrossDecodersTests.libRawPhotoHasARawsWhiteBalance`. S2: `DSCF5123` shows `wb state kelvin asShot 5318 K tint 2` with the nine modes. `adjust wb pick tungsten` gives `'Tungsten'`, `2,850 K`, tint `0`, and `{"preset":"tungsten","temperature":2850,"tint":0}`. The loupe turns blue (`shots/review.png`). Undo gives As Shot. Shade gives `7,500 K`, `+5` | Pass |
| AC2 (R1, R9). Daylight and 2500 K change the render on both decoders | Test, Script | `kelvinAppliesOnBothDecoders`. S3, `photocli --long-edge 600` on X-E3 `DSCF5124`: unedited `7d717e46`, Daylight `919405e1`, Custom 2500 K `764bc523`, Tungsten `78866bfc`. On `develop` all four are `ec73c29b`. X-T3: unedited `6c07dff3`, 2500 K `b22f1021`, Daylight `9ca252bc`. `--set whiteBalance.temperature=2500` without `preset=custom` gives the unedited hash on both decoders (RI-E3, a known wording point in AC2) | Pass |
| AC3 (R4). Auto on an X-E3 stores Kelvin and tint | Test, Script | `LibRawFallbackPipelineTests.autoWhiteBalanceFollowsTheDecoder`. S2: `{"preset":"auto","temperature":5486,"tint":-12}`, shown as `'Auto'`, `5,486 K`, `−12` | Pass |
| AC4 (R3). The color step against a CPU reference, one and two illuminants | Test | `CameraColorStepTests.stepMatchesReference`, `CameraColorTests`, `calibrationAndAnalogBalance` | Pass |
| AC5 (R5). LibRaw against the system decoder on a camera both read | Test (measured) | `LibRawAgainstSystemTests.compare` with 11 files, as printed in S1. The X-E3 (public `DSCF2175`): 3864 K against 3923 K (−1.5%), tint −13. The six X-T3 files: −14.1% to −29.7%, tint +7 to +13; ΔE at 5500 K from 9.2 to 17.5 | **Measured, accepted by the owner 2026-11-14** (not met for the X-T3; RI-E1) |
| AC6 (R6). Unedited LibRaw close to the system render | Test, Person | Same test. X-E3: +0.039 EV, tone spread +0.3%, ΔE 2.7. X-T3: −0.033 to +0.160 EV, tone spread within ±1.6%. The owner's visual check is P1 | Pass (numbers); look is P1 (open) |
| AC7 (R7). The white level does not depend on content | Test | `LibRawDecoderTests.whiteLevelIsTheFiles` | Pass |
| AC8 (R8). A stand-in profile changes the render; an unknown profile reference loads and is kept | Test | `standInProfile`, `unknownProfileReference` | Pass |
| AC9 (R9). Decoder swap leaves the stack byte-identical; JPEG Kelvin inert, relative applies | Test, Script | `decoderSwap`. S3, JPEG `IMG_00002`: Kelvin 2500 / 10 gives the unedited hash (`7848b4f9`); relative 60 / 30 changes it (`e8113080`). Both are the same on `develop` | Pass |
| AC10 (R10). Relative 60 / 30 on an X-E3: not rewritten, renders as shot, shows As Shot; on a JPEG it still changes the render | Test, Script | `relativeValuesOnARaw`, `kelvinModeShown`. S2: `DSCF5126` with `{"relativeTemperature":60,"relativeTint":30}` shows `'As Shot'`, `5,088 K`, `+5`. Choosing Custom stores the numbers beside the relative values (`"preset":"custom","relativeTemperature":60,"relativeTint":30,"temperature":5087.98…,"tint":4.515…`) and shows `'Custom'`. One undo returns the relative values alone and As Shot. S3: the X-E3 render with relative values is the unedited one's hash (`7d717e46`); on `develop` it changed. JPEG: see AC9 | Pass |
| AC11 (R11). Full `swift test`, no golden moved; X-T3 and JPEG renders keep their SHA-256 | Test, Script | Full run above. `git diff 868f8f6..afba824 -- Tests/PhotoCoreTests/Goldens` is empty. S3, branch against `develop` (`868f8f6`), the same for all ten renders: X-T3 at 600 px unedited, 2500 K, Daylight and +1 EV, at 1920 px and at full size; JPEG unedited, relative, Kelvin, and at full size | Pass |
| AC12 (R12). Previews cached before are regenerated for LibRaw photos; carry-over as `status.md` says | Test, Script | `cachedPreviewsAreRegenerated`, `carryOverSurvivesAFailedRemoval`. S5: a `v8` cache made by `develop`'s `photobench` (see AC12 detail below the table) | Pass |
| AC13 (R13). Paste both ways, one undo; a preset with Kelvin | Test, Script | `pasteBetweenDecoders` (paste and preset). S4: Daylight copied from the X-T3 and pasted onto X-E3 `DSCF5127` shows `'Daylight'`, `5,500 K`, `0`. One undo (`Paste Adjustments`) leaves the empty stack. 4000 K copied from an X-E3 and pasted onto the X-T3 shows `'Custom'`, `4,000 K`. One undo restores its earlier stack | Pass (preset by test only) |
| AC14 (R14). A raw with no usable color data renders as shot; the tab says white balance is unavailable | Test, Script | `unusableColorData`. S4, on a 256 x 192 `--dng-without-color` file that LibRaw reads (W1, W2 and As Shot detail below the table) | Pass; look is P7 |

**AC12, the carry-over (S5).** Five photos, with renditions of both tiers made by `develop`'s `photobench`:

- The X-T3 and the two JPEGs were dated 2026-11-01. The two X-E3 photos were left dated today.
- One JPEG's master was moved away, so it was offline.
- After one launch of the branch's bundle:
  - `v8` was gone.
  - The six renditions dated 2026-11-01 were under `v9`, byte-identical, with their dates kept. These include the
    offline JPEG's, which still shows in the grid.
  - The four X-E3 renditions written today were removed. The two thumbnails were made again with the new look;
    the previews will be made on demand.

**AC14, the colorless DNG (S4).** The file is a 256 x 192 `--dng-without-color` DNG, which LibRaw reads.

- **W1:** `wb state unavailable`. The Mode pop-up is `'As Shot'`, disabled, with the single item `[As Shot]`. Its
  tip is "Not available for this photo: its color data can't be read." There are no sliders. Auto and Custom
  change nothing.
- **W2:** after a pasted Daylight, `wb state unapplied`. The modes are `[As Shot, Daylight]`, enabled, with the
  tip "Not applied: this photo's color data can't be read. It's shown as shot."
- **As Shot** removes the pasted Daylight and brings W1 back. Undo brings W2 back.
- **The colored small DNG,** through LibRaw, reads `6503 K tint 10`. The same picture at 6000x4000, through the
  system decoder, reads `6502 K tint 10`.

**Also checked by script (S2, S4, S6):**

- **Custom sticks.** On an X-E3, `adjust wb pick custom` stores the as-shot numbers unrounded (`5318.44…`,
  `1.7407…`) and shows `'Custom'`. Picking it again changes nothing. On an unedited X-T3, Custom stores `6246.41…`
  / `23.85…`, and undo gives As Shot.
- **Relative values on the X-T3.** Relative 60 alone shows `'As Shot'` at 6,246 K.
- **The Temperature field.** Typing 4000 stores Custom 4000 K with the as-shot tint (undo `Temperature`).
- **The JPEG is unchanged.** It shows `wb state relative`, the modes `[As Shot, Auto, Custom]`, and sliders at 0.
  Custom stores `{"preset":"custom"}`.
- **The note.** It reads "macOS can't decode this raw file, so it's shown with a built-in profile that can't be
  changed. Color noise reduction isn't available."
- **Grid and loupe from an empty cache.** All six X-E3 photos, the X-T3, the DNGs and the JPEGs render; the X-E3
  photos look brighter and fuller than on `develop` (`shots/grid.png`).
- **Drag at 100% (M8's scripted part).** Once the full decode is ready, a Temperature drag of 20 steps gives 20
  sharp region frames (`region 1760x1368 … of 6000x4000 applied`, 2 to 7 ms each) with no decode between them.
  Before that, the first 100% interaction's frames are soft while the full decode runs (about 10 s), as for any
  LibRaw edit at 100% since #161.

**Q7, export and `photocli` sizes:**

- **Q7, six X-E3 photos at 100%, 1.5 s apart (S6).** The last was sharp about 11 s after it was shown (one alone:
  about 9 s). Resident memory peaked at 1.61 GiB at 45 s and settled at 1.14 GiB. In #161's second run the
  figures were 10 s and 1.49 GiB.
- **Export (S7).** Unedited X-E3 `DSCF5128`: full-size JPEG 6000x4000, 16-bit TIFF at long edge 2000
  (2000x1333), JPEG at 50% (3000x2000). No failures, and the new look.
- **`photocli` on X-E3 `DSCF5124` (S3):**

  | Long edge | Time | Peak memory |
  | --- | --- | --- |
  | 256 | 3.2 s (first run, cold) | 475 MB |
  | 600 | 0.8 s | |
  | 1920 | 1.1 s | |
  | 2560 | 1.4 s | 532 MB |
  | 3000 | 1.7 s (half-size decode) | |
  | 4000 | 10.5 s | 1.25 GB |
  | Full, 6000x4000 | 12.4 s | 1.0 GB |

## Findings

None.

Not findings, for the record:

- **Debug script: no-op steps.** A scripted command that changes nothing leaves an empty, unnamed undo step: the
  debug script's own undo group around `adjust …`. The same happens with `adjust exposure 0.5` twice, and on
  `develop`. So in S2, a ⌘Z after re-picking Custom undid that empty step. Whether the real pop-up leaves one is
  P6.
- **Debug script: relative keys.** `adjust warmth` and `adjust shift` write the relative keys without touching
  `preset`. That is how S2 made #161-style leftover values.
- **AC14's file size.** A `--dng-without-color` DNG at the generator's default 6000x4000 is read by the *system*
  decoder, which shows it as a normal raw (as shot 5502 K, tint 10; nine modes). W1 and W2 need a size the system
  decoder gives no image for (256 x 192 here). `status.md` does not say which size it used; worth one line there.
- **Open items owned by others.** RI-E2 (tables carried, not applied), RI-E3 (AC2's command), RI-E5 (one
  exposure for every maker) and the proposed issues stand as `status.md` lists them.

## Scripts

`$N` is `/private/tmp/claude-501/-Users-randy-Projects-Gus/b35c93c8-ca57-4c41-a9c1-42b12b1359d5/scratchpad` and
`$Q` is `$N/qa170`.

- **Bundle:** a copy of the worktree's `build/Gus.app` in `$Q/Gus.app`, identifier
  `me.sesser.gus.debugtest.wb170qa` (new, so no saved toolbar), re-signed ad hoc and run by its executable. Each
  script starts with `inspector on`.
- **Library:** `$Q/lib`, from `photobench import`, with an empty cache at first. It holds X-E3 `DSCF5123` to
  `DSCF5128`, X-T3 `DSCF4583`, two `photobench generate` JPEGs, and four DNGs from
  `generate --dng 2 --dng-without-color 1`:
  - at the default 6000x4000;
  - at `--dng-size 256x192` (renamed `_small`).
- **`develop`:** a clone at `868f8f6` in `$Q/dev`, with its release `photocli` and `photobench`.

**S1, sample suites.** Each run passed; the printouts are in `$Q/both.log` and `$Q/look.log`.

- `RAW_BOTH_SAMPLES` (11 files):
  - `$N/xe3-public/DSCF2175.RAF`
  - `$N/xt3/DSCF0227.RAF`, `DSCF2901.RAF`, `DSCF5562.RAF`, `DSCF5991.RAF`, `DSCF6604.RAF`
  - `/private/tmp/claude-501/cmp/in/DSCF4583.RAF`, `DSC00041.ARW`, `IMG_6883.CR2`, `P8060001.ORF`, `_1020857.RW2`
- `RAW_LOOK_SAMPLES` (9 files): the same, without `DSCF5991` and `DSCF6604`.

**S2, the X-E3's White Balance** (abridged; the full output was read):

```
Gus --library-root $Q/lib --debug-script "wait 3; windowsize 1400 900; inspector on; focus 0; loupe; tab adjust; ml ready; wait 3; print ml; print adjustments; adjust wb pick tungsten; wait 1; print ml; print adjustments; undo; wait 1; print ml; adjust wb pick custom; wait 1; print ml; print adjustments; adjust wb pick auto; wait 1; print ml; print adjustments; undo; wait 1; editvalue Temperature; text 4000; key return; wait 2; print ml; print adjustments; undo; wait 1; adjust wb pick shade; wait 1; print ml; print adjustments; quit"
Gus --library-root $Q/lib --debug-script "wait 3; windowsize 1400 900; inspector on; focus 3; loupe; tab adjust; ml ready; wait 3; adjust warmth 60; adjust shift 30; wait 2; print ml; print adjustments; adjust wb pick custom; wait 2; print ml; print adjustments; undo; wait 1; print ml; print adjustments; focus 6; ml ready; wait 3; print ml; print adjustments; adjust wb pick custom; wait 1; print ml; print adjustments; undo; wait 1; print ml; adjust warmth 60; wait 1; print ml; print adjustments; quit"
```

**S3, `photocli`.** The branch's release build and `develop`'s render the same arguments, and the PNGs are compared
by SHA-256:

```
photocli render <file> --out <png> --long-edge 600 [--set whiteBalance.preset=custom --set whiteBalance.temperature=2500 | --set whiteBalance.preset=daylight --set whiteBalance.temperature=5500 --set whiteBalance.tint=0 | --set exposure.ev=1 | --set whiteBalance.preset=custom --set whiteBalance.relativeTemperature=60 --set whiteBalance.relativeTint=30 | --set whiteBalance.preset=tungsten --set whiteBalance.temperature=2850 --set whiteBalance.tint=0]
photocli render <file> --out <png> [--long-edge 256|1920|2560|3000|4000]
```

`$Q/r/x/wb-montage.png` shows, left to right: `develop` unedited, then the branch unedited, Daylight, Tungsten and
2500 K.

**S4, paste both ways, W1 and W2, the JPEG:**

```
Gus --library-root $Q/lib --debug-script "wait 3; windowsize 1400 900; inspector on; focus 6; loupe; tab adjust; ml ready; wait 3; adjust wb pick daylight; wait 1; copyadjust; undo; wait 1; focus 4; ml ready; wait 3; pasteadjust; wait 3; print ml; print adjustments; undo; wait 2; print ml; print adjustments; editvalue Temperature; text 4000; key return; wait 2; copyadjust; undo; wait 1; focus 6; ml ready; wait 3; pasteadjust; wait 2; print ml; print adjustments; undo; wait 2; print ml; print adjustments; focus 8; ml ready; wait 2; print ml; print adjustments; adjust wb pick custom; wait 1; print ml; print adjustments; quit"
Gus --library-root $Q/lib --debug-script "wait 3; windowsize 1400 900; inspector on; focus 6; loupe; tab adjust; ml ready; wait 2; adjust wb pick daylight; wait 1; copyadjust; undo; wait 1; focus RAW_00001_small; ml ready; wait 2; print ml; print adjustments; adjust wb pick auto; wait 1; adjust wb pick custom; wait 1; print adjustments; pasteadjust; wait 2; print ml; print adjustments; adjust wb pick asShot; wait 1; print ml; print adjustments; undo; wait 1; print ml; print adjustments; focus RAW_00002_small; ml ready; wait 2; print ml; quit"
```

**S5, the carry-over:**

```
photobench import --library-root $Q/cm/lib --source $Q/cm/src        (develop's photobench)
photobench previews --library-root $Q/cm/lib --tier thumbnail; … --tier preview
touch -t 202611010900 <the X-T3's and the JPEGs' renditions>; mv $Q/cm/src/IMG_00002.JPG $Q/cm/off/
Gus --library-root $Q/cm/lib --debug-script "wait 4; print items; windowsize 1400 900; size 200; wait 10; snapshot $Q/shots/carry-grid.png; quit"
```

Before and after: the file list with dates (`stat`), and SHA-256 per rendition (`$Q/cm/before-sha.txt`,
`after-sha.txt`).

**S6, at 100%.** Memory was sampled with `ps -o rss` once a second. Sharpness is taken from `print viewport`'s
`nearest true`.

```
Gus --library-root $Q/lib --debug-script "wait 3; windowsize 1400 900; inspector on; focus 8; loupe; tab adjust; wait 3; zoom; wait 1; focus 2; ml ready; wait 5; adjust scrub temperature 5000 4900 2 16; wait 15; print viewport; print frames; adjust scrub temperature 4900 3500 20 50 hold; print viewport; print frames; adjust scrub temperature 3500 3500 1 16; wait 4; print viewport; quit"
Gus --library-root $Q/lib --debug-script "wait 2; windowsize 1400 900; focus 8; loupe; wait 3; zoom; wait 1; print viewport; focus 0; wait 1.5; focus 1; wait 1.5; focus 2; wait 1.5; focus 3; wait 1.5; focus 4; wait 1.5; focus 5; <wait 1; print viewport> x 60; quit"
```

**S7, export:**

```
Gus --library-root $Q/lib --debug-script "wait 2; windowsize 1400 900; focus 5; loupe; wait 3; print adjustments; export window; export set format=jpeg size=full dest=$Q/export; export run; export set size=long:2000 format=tiff bits=16; export run; export set size=percent:50 format=jpeg; export template half-{name}; export run; print messages; quit"
```

After the runs:

- No instance of the app is running.
- Nothing under `~/Library/Application Support/Gus` is newer than the start of QA, and neither is
  `me.sesser.gus.plist`.
- The worktree is clean, apart from this file.

## For a person

Build the bundle in the worktree (`Scripts/build-app.sh`). Launch it with `--library-root` on a scratch library
holding:

- an X-E3 RAF (`DSCF5124`; macOS can't decode it);
- the X-T3 `DSCF4583.RAF`;
- a JPEG;
- for P7, a small colorless DNG (`photobench generate --dng 1 --dng-without-color 1 --dng-size 256x192`).

Open the inspector, the Adjust tab, in the loupe.

- **P1 (AC6). X-E3 beside X-T3.** Open an X-E3 photo and an X-T3 photo of similar scenes, unedited, side by side
  (View ▸ Compare Side by Side, or one after the other). They look comparable in brightness, contrast and color.
  Neither is clearly flat or dark against the other. This is the owner's check.
- **P2 (M1). The note.** On the X-E3, under "Profile", the note wraps cleanly at the inspector's narrowest width,
  with clear space before White Balance. There are no pop-ups under Profile.
- **P3 (M2). White Balance on the X-E3, by hand.**
  - The nine modes are listed.
  - Unedited, Temperature shows a plausible Kelvin.
  - Tungsten turns the photo clearly blue and shows 2,850 K, tint 0; Shade warms it.
  - Double-clicking Temperature returns it to the as-shot value.
- **P4 (M3). Auto on the X-E3.** The pop-up dims briefly, then shows Auto with a Kelvin and tint, and the photo
  looks neutral. Note whether the wait reads as working or as a hang.
- **P5 (M4). Paste both ways, with the real menus or keys.** Paste Daylight from the X-T3 onto the X-E3, then
  4,000 K from the X-E3 onto the X-T3. Each changes the receiving photo, and ⌘Z undoes each paste in one step.
- **P6 (M5, M6). Switching photos, and Custom with the mouse.**
  - Arrow X-T3, X-E3, JPEG, X-E3. The raws show the same group; only the JPEG shows three modes and −100 to 100.
    Nothing carries over, and nothing visibly jumps while the X-E3 loads.
  - On an X-E3 edited with a #161 build (relative values), or after setting them: Mode shows As Shot. Choosing
    Custom keeps it Custom with the same numbers, and the photo does not visibly change. One ⌘Z returns As Shot.
  - Choosing Custom a second time leaves no extra ⌘Z step. The script cannot tell this; see Findings.
  - Repeat on an unedited X-T3.
- **P7 (M7, M9). Unavailable and not applied, and caption spacing.**
  - On the colorless DNG: the dimmed pop-up on As Shot, with the caption under it starting at the pop-up's left
    edge. Check its wrap and legibility with Increase Contrast on and off. Hovering shows the same text.
  - Paste a Daylight onto it: the orange triangle caption and the two-item pop-up appear. As Shot brings the
    dimmed state back, and ⌘Z brings Daylight back.
  - The captions sit the same distance under their control as the machine learning caption does.
- **P8 (M8). Live drag with the mouse.** Drag Temperature on the X-E3 at fit and at 100%. The loupe follows while
  the slider moves, not only on release. At 100% the first drag after opening a photo is soft for about 10 s while
  the full decode runs (S6).
- **P9 (M10). Light beyond the sliders' ends.** Only if a LibRaw raw shot below 2,000 K is at hand: unedited, it
  reads 2,000 K. Custom shifts the photo once; As Shot brings the camera's look back. Skip otherwise.
- **P10. The look across the library.** After the first launch on a library holding X-E3 photos cached by a #161
  build, their thumbnails come back with the new look (not #161's flat one), and other photos' thumbnails are not
  made again. S5 checked this on a scratch copy; this is a look at a real library, if the owner wants it.

## Follow-up

**Sign-off (2026-11-14).** The owner signed off on `3013abf`, as the main session relayed. That commit is
`afba824` plus this file (`git diff afba824..3013abf` touches only `qa.md`), so the code signed off is the code
tested above. The owner ran the scratch-library bundle.

Checks left open: P1 to P10, all of them. The owner named none as done on its own.

- P1 (AC6): the X-E3 beside the X-T3.
- P2 (M1): the note.
- P3 (M2): White Balance on the X-E3 by hand.
- P4 (M3): Auto's wait.
- P5 (M4): paste with real menus or keys.
- P6 (M5, M6): switching photos, and Custom with the mouse, including no extra undo step.
- P7 (M7, M9): the unavailable and not-applied captions and their spacing.
- P8 (M8): live drag with the mouse.
- P9 (M10): light beyond the sliders' ends.
- P10: the new look on a library cached by a #161 build.

AC5 stays "measured, accepted by the owner 2026-11-14". The open checks stay in "For a person" above. Per
`docs/WORKFLOW.md`, they also go to the standing manual-checks issue (#82) and are named in the pull request.

## Summary for the issue

QA (2026-11-14), `feature/libraw-color-pipeline` at `afba824`: **passes, no findings.**

- **Criteria:** AC1 to AC4 and AC7 to AC14 pass by test, and the parts that can be scripted pass by script. AC5 is
  **measured, accepted by the owner 2026-11-14** (X-T3 as-shot Kelvin 14% to 30% below the system decoder's; the
  X-E3 is 1.5%). AC6 passes by numbers; its look is the owner's.
- **No regressions:** X-T3 and JPEG `photocli` renders are byte for byte `develop`'s (ten renders).
- **Scripted on X-E3s:** nine modes, Tungsten 2,850 K, Auto stores Kelvin, Custom sticks, leftover relative
  values show As Shot.
- **Elsewhere:** paste works both ways with one undo, and the colorless DNG shows the W1 and W2 states.
- **Cache:** previews from before 2026-11-13 were carried to v9, offline master included; the X-E3's were remade.
- **At 100%:** six X-E3 photos peak at 1.61 GiB, and the last is sharp in about 11 s.
- **Tests and build:** `swift test` 993 passed (1 known issue), all three sample suites passed, both bundles
  built.

Open for a person: P1 to P10 (AC6's side-by-side look, plus the designer's M1 to M10).
Full record: `docs/features/white-balance-across-decoders/qa.md`
