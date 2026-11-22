# HDR merge: QA

Owner: qa-tester. Date: 2026-11-21. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/hdr-merge` at 9e178a8 (the worktree `Gus-hdr-merge`, clean), on a
Mac16,8 (Apple M4 Pro, 24 GB), macOS 27.2.1 (26B131), Xcode SDK 27.2; the bundle's
executable records minos 15.0 and sdk 27.2.

This is the run after the sign-off revision (the reference chosen in the sheet,
Auto-align and De-ghost, `photocli --reference`, `--no-align`, `--no-deghost`), the design
review's F6 to F8 and code review's sixth to ninth passes (C14 to C19). The first
run (d3545ad) and its rerun (d635e12) are kept at the end, under "Earlier runs".

## Verdict

**Passes. Ready for the owner's sign-off: no blocker, no failing criterion.** All 23
acceptance criteria of the PRD as revised 2026-11-21 pass by test (full `swift test`: 1348
tests in 194 suites, 0 failed), and 20 of them also by a script run on a copy of the
bundle against scratch libraries. Four small findings for the engineer (Q7 to Q10, nits
and one missing test; none blocks sign-off) and one scope note for the main session
(the "GPU copy cap 100 MP" is not on this branch, see Scope notes). What only a person can check is
P11 to P20 below (the sheet's look, real input, real cameras), plus P1 to P10 of the
first run, still open as listed under "Earlier runs".

## Results at a glance

- `Scripts/build-app.sh`: builds; the executable records sdk 27.2, minos 15.0.
  `swift build -c release --product photobench --product photocli`: builds.
- `swift test` (the whole suite, the `HDRMergerTests` included): **1348 tests in 194
  suites passed, 0 failed, 710.6 s**, the FAT32 test (`C6`) ran against a real image (it
  was not skipped), and the opt-in suites skipped for their environment variables as
  usual. No golden moved and `UPDATE_GOLDENS` was not run. The count includes the six
  `ImageIOFullDecodeTests` of commit `079bf79`, which goes to #253 (Scope notes).
- No migration (the newest is v14); `Package.swift`, `Scripts/` and the goldens are
  untouched by the branch's later commits; `PreviewCacheKey.currentPipelineVersion` 13.
- Mutation check (scratch clone outside the checkout, `MergeGhosts.swift` put back to
  `245c415`'s reference-black test, the line C19 changed): `stillNoisyBracket` ("A13: a
  still linear bracket with noise…") **fails with 4 issues**, 769, 767, 12,163 and
  12,440 pixels moved (darkest reference, ±2 and ±3 EV, aligned and unaligned), exactly as
  `status.md` records; it passes on `9e178a8`. The clone was deleted.
- Safety after the run: no `Gus` or `photocli` process left; the owner's
  `~/Library/Application Support/Gus` has no file newer than my start marker (its
  `library.lock` and WAL are still from 2026-11-20 16:16); nothing under `~/gus-scratch`
  was written (the three ORFs were copied to a scratch folder first and their SHA-256
  compared); every launch carried `--library-root` on a scratch library; no bare `open`;
  the worktree is clean.

## Acceptance criteria

All 23 criteria of the PRD (issue #150, as revised 2026-11-21). Test names are the
suite's display names in `Tests/PhotoCoreTests`; scripts are in "Scripts" (A to N).

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Test, Script | `MergeRuleTests` (running and sheet up), `MergeSelectionTests` (every refusal), script L: three targets with a video: `canMerge true`, the context menu lists Merge to HDR…, the sheet refuses naming the video; one photo and one video: `canMerge false reason fewer than two`; script A: `canMerge false reason sheet up` while the sheet is open; script J: `reason running`. The menu's enabled state needs a key window: P1 (first run) | Pass |
| AC2 | Test, Script | `HDRMergeJobTests` "AC2, AC3, AC5…" (hashes unchanged, folder, `_HDR-2`), "AC2: an existing file with the result's name is left alone", `MergeSelectionTests` naming. Script D and G: the sources' SHA-256 equal the pristine copies' after merges; the result is in the reference's folder; a repeat is `-2` (script G: `RAW_102_HDR.tif`, `-2.tif`, `-4.tif`) | Pass |
| AC2a | Test, Script | "C3: a file of the same stem in any format, or its sidecar, numbers the result", "AC2a: a TIFF and a DNG… each keep their own sidecar". Script G (`photocli`): TIFF, TIFF, DNG, TIFF of one bracket gave `RAW_102_HDR.tif`, `-2.tif`, `-3.dng`, `-4.tif`; script D: the result's `.xmp` holds its own values | Pass |
| AC3 | Test, Script | `MergeSheetStateTests` "AC3, AC9a…" (0 EV frame second in time is the default), `MergeSelectionTests`, "AC3: with no compensation recorded…". Scripts A, B, D: `RAW_102` (0 EV, shot second) is the reference and names `RAW_102_HDR.tif` | Pass |
| AC3a | Test, Script | `MergeReferenceJobTests` "AC3a…" (two folders, two projects: name, folder, project, capture date, rating, label, title), `MergeSheetStateTests` "AC3a: the Name line follows…", `MergeCommandTests` "AC14: photocli merge takes a reference…". Script A/D: the Name follows the chosen row (`RAW_103_HDR.tif`, `RAW_101_HDR.tif`); script D: with ratings 4 on RAW_102 and 2 on RAW_103, choosing RAW_103 gives `RAW_103_HDR.tif` with rating 2 in the catalog and in its `.xmp`, DateTimeOriginal and ExposureTime of RAW_103, the same project; script C: TwoFolders: the Name and the folder follow the frame in `Open`; script M: real ORFs, reference `10M10355` and `10M10356` name and give their capture date | Pass |
| AC3b | Test, Script | `MergeChoicesTests` "AC3b: the frames are lined up to the chosen reference…", "AC3b: what moved is taken from the chosen reference, at its place there", `MergeReferenceJobTests` "AC3b, AC8a at the job…". Script F (walker, TIFF to PNG, looked at): the red disc is at the reference's place: left with RAW_101, in the middle with RAW_102, right with RAW_103; the pixels differ between references (over 1.1 million pixels differ by more than 1/256) | Pass |
| AC3c | Test, Script | `MergeSheetStateTests` "AC3c, AC9a: a sheet opened again…". Script A: Cancel then `merge sheet` again: RAW_102 and both boxes on, whatever was chosen (RAW_101, align off, deghost off). Script E: after a refused merge, the next sheet has Auto-align on | Pass |
| AC4 | Test, Script | "AC4: DNG writes a linear floating-point DNG the system's RAW decoder reads, catalogued", "AC4: a sidecar is written… only then", `MergeDNGTests`. Script G: `exiftool -validate` OK on a `photocli` DNG (BitsPerSample 16, SampleFormat Float, LinearRaw, BaselineExposure 1.845); script D: the sidecar exists beside the TIFF because the photo has a rating. The loupe at the brightness BaselineExposure gives: first run, P5 | Pass |
| AC5 | Test, Script | "AC2, AC3, AC5…" (every field and the file's), `MergeReferenceJobTests` (the chosen frame's). Script D (above); script M: the real bracket's TIFF carries the reference's ExposureCompensation and DateTimeOriginal | Pass |
| AC6 | Test, Script | "AC6: three JPEGs merge", "AC6: a raw with two JPEGs is refused…", "AC6: a RAW+JPEG pair… counts once". Script K: three JPEGs merge (reference JPEG_103); script C: the mixed series is refused with the mixed message and Merge off; script PAIR: three RAW+JPEG pairs are three frames | Pass |
| AC7 | Test, Script | `MergeAlignmentTests` (derived 0.5 px), "AC7: a frame of another scene is refused, named…". Script E: Unrelated with Auto-align on stops at Aligning: "“UNRELATED_103” doesn't line up with “UNRELATED_102”. Merge photos of the same scene, or turn off Auto-align."; no file | Pass |
| AC7a | Test, Script | `MergeChoicesTests` "AC7a: with Auto-align off nothing is measured or moved, and the merge is the CPU reference's…", "AC7a: with Auto-align off frames of another scene are merged as given…", `MergeReferenceJobTests` "AC7a, design §7.1…", `MergeCommandTests` "AC14, AC7a…". Script E: with Auto-align off the Unrelated bracket merges (`UNRELATED_102_HDR.tif`), details Reading, Merging, Saving, Adding (no Aligning), bar ends 1.000; script G: `photocli --no-align` the same; with it off the walker bracket is not lined up (script F3: every pixel differs from the aligned result) | Pass |
| AC7b | Test | `MergeReferenceJobTests` "AC7b: with Auto-align off the other refusals still apply" (a different size, an offline frame, a video, a read-only folder, each refused, nothing read). No fixture series has two sizes, so no script | Pass |
| AC8 | Test, Script | `HDRMergerTests` "AC8: a moving object shows once, from the reference…", `MergeChoicesTests` "AC8, A13: with Auto-align off too, a moved object's outline is taken out whole…". Script F1: the walker's disc appears once, from the reference (the other frames' discs are gone); the outline looked at 2x on the default, +2 EV and −2 EV references: no speck. The synthetic scene, not a real person: P15 | Pass |
| AC8a | Test, Script | `MergeChoicesTests` "AC8a: with De-ghost off the moving object is blended, as the CPU reference's plain blend…". Script F2: De-ghost off shows the disc at its three places (a plain blend, one a faint ring); where nothing moved, F1 and F2 agree (the 60,291 pixels that differ by more than 1/256 are all inside the box x 87 to 1413, y 102 to 550: the disc's places and the light patches in the window, the things that moved; nothing below y 550) | Pass |
| AC9 | Test, Script | "AC9: stopping mid-merge leaves no file, no partial file and no catalog row". Script J: `merge stop`: "The merge was stopped. Nothing was added to the library.", no new file, no hidden `.partial`; polling `print merge` during runs gave live progress (main thread free); script E: a failure writes its reason in Activity | Pass |
| AC9a | Test, Script | `MergeSheetStateTests` "AC9a: the two boxes are independent…", `MergeChoicesTests` "AC9a: each of the four combinations…". Script A: both on at open and after reopening; each box changes only itself; script F: all four combinations merged (F1 default, F2 de-ghost off, F3 align off, F6 both off) | Pass |
| AC10 | Test | `HDRMergerTests` "AC10: the merge and tone mapping match their CPU reference", "AC10: the result holds shadow and highlight steps…". Not rerun by script (first run) | Pass |
| AC11 | Test | "AC11: the merged photo renders, takes an edit with history, and exports"; the full suite with every golden unmoved. Not rerun by script (first run) | Pass |
| AC12 | Test, Script | `MergeSheetStateTests` "AC12: the read-only folder's refusal follows the reference…", "§6.4…", `MergeReferenceJobTests` "AC12: a read-only folder refuses only while the reference is in it", `MergeSelectionTests` (every refusal), `MergeSafetyTests`. Script C: TwoFolders opens refused (the default reference in `Locked`, the row flagged, Merge off), choosing the `Open` frame lifts it (Merge on, "Merge is available."), choosing the first frame brings it back naming TWOFOLDERS_101; Mixed, 13 frames ("At most 9…") and script L (a video, named and flagged) refuse with Merge off. Script I: a slow answer for a superseded reference is discarded (`merge on` follows the current reference). Offline, unreadable, copies, sizes and the oversize cases: first run | Pass |
| AC13 | Test, Script | "AC13: Undo takes the photo out of the library and leaves the file; Redo brings it back…". Script H: after the merge with RAW_103 as reference: Undo (3 items, "removed" message), Redo (the photo is back, `undo 'Merge to HDR'`), then a rating pressed afterwards reaches the catalog (`RAW_101.dng|5`): the write chain is free | Pass |
| AC14 | Test, Script | `MergeCommandTests` "AC14: photocli merge writes a fixture series and prints the path; refuses while the library is locked", "…takes a reference and off switches…", "…refused naming --no-align…". Script G: defaults print `align true`, `deghost true`; `--reference 9` names `RAW_103_HDR.tif`; `--reference 7 --no-deghost` gives a DNG; a reference outside the `--version`s is `invalidValue`, nothing written; the unrelated series fails naming `--no-align` and merges with it. `photocli`'s pixels are bit for bit the app's for the same choices (three comparisons: default, both off, reference RAW_103). The locked-library refusal: test, and first run | Pass |
| AC15 | Test, Script | "AC15…" in `mergesToTIFF`, "AC15: merging again after the first photo was removed…". Script G: two TIFFs of one bracket (`RAW_102_HDR.tif`, `-2.tif`) have different SHA-256 (`0108…`, `41f4…`), as do the DNG and TIFF written after them (`-3`, `-4`); each is a new photo with its own versionID (22 to 26 and on) | Pass |

The revision's requirements that are not one AC, and the design's checks:

| Item | How | Evidence | Result |
|---|---|---|---|
| Open question 7 / A14: Auto-align off, no different-scene refusal | Test, Script | `unrelatedWithoutAlignment` (core), `MergeReferenceJobTests` job, `photocli` `unrelatedWithSwitch`; scripts E and G | Pass |
| Open question 8 / A13: no warning for an extreme reference | Script (no test, Q8) | Scripts A, C, F and K: choosing the darkest (RAW_101) or brightest (RAW_103, JPEG_103) frame prints `message none … merge on true` and merges; the sheet and `merge reference` show no note | Pass (Q8: no test asserts it) |
| A13, de-ghost after C14 to C19: extreme references, still noisy and non-linear brackets, the rim | Test | `MergeChoicesTests`: `extremeReferences` ("A13 measured…"), "AC8, A13: with Auto-align off too…" (outline and rim), "A13: a still linear bracket with noise…" (mutation-checked above), "A13: a still bracket with a camera-like response…"; `HDRMergerTests` `ghostFree` and `ghostsFollowTheReference`. Real-camera JPEG: P16 | Pass |
| Sheet layout: 560 x 640, nothing scrolled at three frames | Script, snapshot | `merge sheet` at three frames (raws, JPEGs, Unrelated, the walker): `sheet 560x640 (ideal 640) form content 517 shown 522 scrolls false`; with a two-line message (Mixed) 517 against 504 and a three-line folder refusal 531 against 490 it scrolls by 13 and 41 pt (accepted, D-H11 item 7); 13 frames: 681 against 518, the table at its cap. A window shorter than the sheet could not be made by `windowsize`: P18 | Pass (P18 for the short window) |
| F6 folded captions | Snapshot (`sheet-default.png`, looked at) | The reference caption sits under the table in the same group row, the Auto-align and De-ghost captions under their boxes, the Format caption under the picker, the result caption under the Folder; no "Photos" header; the divider falls between the rows, not between a control and its caption | Pass (look: P11) |
| F7 Name line secondary while a refusal shows | Script, snapshot | `merge sheet`/`merge reference` print `(secondary)` on `TwoFolders-0` (folder refusal) and Mixed, and no `(secondary)` once the `Open` frame is chosen; the snapshot shows the Name gray | Pass |
| F8 header thumbnail follows the reference | Test, Script | `MergePreviewItemTests`; script PAIR (three RAW+JPEG pairs): the thumbnail is `RAW_102.dng`, `RAW_103.dng`, `RAW_101.dng` as the reference moves, and `RAW_102.jpg`, `RAW_103.jpg`, `RAW_101.jpg` after `pairfile jpeg`; the snapshots show the thumbnail change (the walker moves). Not seen on a real pair: P19 | Pass |
| D-H13 Return and Esc with the table focused | Person | P13 | Open |
| §7.1 progress without alignment | Test, Script | `MergeProgressScheduleTests`; scripts D (Reading, Aligning, Merging, Saving, Adding) and E, F3 (no Aligning), bar ends 1.000 | Pass |
| §11 announcement | Test, Script | `MergeSheetStateTests` "§11…"; scripts C, A: "Reference RAW_103. Result RAW_103_HDR.tif." and "… Merge is available." / the new refusal | Pass |
| C16 slow-disk spinner | Test, Script | the three `MergeSheetStateTests` spinner tests; script I: spinner off at once for an answered folder, on after the pause for a folder still being asked, off when it answers | Pass |
| A9 de-ghost follows the reference with both off: the reference still names the result | Script | script F6 (both off) writes `RAW_102_HDR.tif`; script G `--reference 8 --no-align --no-deghost` | Pass |

## Findings

For the engineer. None blocks sign-off. Q1 to Q6 were the first run's (all fixed: see
"Earlier runs").

**Q7 (Nit, look). The sheet's Photo column cuts a seven-character name when it carries the
Reference mark.** Steps: script B (`search RAW_10; selectall; merge sheet; snapshot`),
`shots/sheet-default.png`. Expected (design §5.2): the mark stays whole and the name gives
way first, middle-cut with its full text as the tooltip. Actual: that rule holds, but at
the default width the name is cut when it need not be: the row reads `RA…102 Reference`
while the Type, Shutter and Compensation columns have a quarter of the width each, mostly
empty. A name like `IMG_1234` would be cut the same way; with a flagged row's symbol
(script C, TwoFolders) it is `T…2 Reference` for `TWOFOLDERS_102`. The column is the
table's, so M8 (P11) should judge it: widen the Photo column's ideal width at the cost of
Type and Compensation, or let the person drag it.

**Q8 (Nit, missing test). No test asserts "no warning for an extreme reference".**
`MergeSheetStateTests.choosing` picks the darkest frame (IMG_1) but checks only the
reference, not that `message` stays nil and `canStart` true; Open question 8 and A13 say
no warning. Scripts A, C, F and K show none for the darkest and the brightest frame, so
the behavior is right today. Add the two assertions (and the same for each of the four
box combinations) so a later refusal that depends on the reference's exposure is caught.

**Q9 (Observation, no action asked; feeds P16). A JPEG bracket merged with the brightest
frame as reference and De-ghost on has flatter highlights than with De-ghost off.**
Steps: scripts K, K2, K3 (the fixture's three 8-bit JPEGs, `search JPEG_1; selectall;
merge sheet; merge reference JPEG_103; [merge deghost off]; merge start`), results read
back with `tifdiff.py`/`region.py`. The window pane's brightness: standard deviation 0.0030
(reference +2 EV, De-ghost on), 0.0058 (De-ghost off), 0.0086 (default reference); the
snapshot shows the pane as one flat near-white tone with De-ghost on and with blotches
with it off. The same bracket as raws does not do this (script F: the same window pane,
0.0192 to 0.0195 whatever the reference or the box). This is the known limit of JPEG
brackets (the camera's response isn't recovered: the proposed follow-up; status.md
"Seventh review pass"), not a regression, and the fixture JPEGs are 8-bit with no camera
curve, so only a real camera's JPEGs can say whether it matters: P16.

**Q10 (Nit, debug script only). `print merge` goes on printing the sheet's line after the
sheet has closed.** Script L: after `merge cancelsheet`, `print merge` still ends with
`merge sheet reference MVI_00003 disk answered merge on false spinner off` (the model's
`sheet` is kept until the next `begin`). Not visible to a person; it can make a script
read a closed sheet as open. Print it only while `model.showsMergeSheet`.

### Scope notes (not findings)

- **"GPU copy cap 100 MP" is not on this branch.** `ResidentDecode.maximumDimension` here
  is 16,384 pixels on a side (commit `079bf79`). The 100 megapixel limit
  (`maximumPixels`, `lazyReason`, the opt-in soak) is in `bug/core-image-split-render`
  (#253, commit `34a614c`), whose own `qa.md` is `66be81d`. Nothing about it can be
  tested here, and what this run covers of `079bf79` is that its tests pass (the six
  `ImageIOFullDecodeTests`, `LensAlignStaleAreaTests`) in the 1348. When `079bf79` is dropped via
  #253 the count falls and this branch's "Bug: tiles at 100%" section in `status.md` goes
  with it; the sign-off's P5 (the owner's tile bug) is then #253's to confirm. Nothing here
  depends on that commit: the revision and the merge's files do not touch it.
- **#88 merge order** (the `maskRasters` column in `Catalog.removeMergedMaster` and
  `restoreMergedMaster`) is unchanged since the first run: whichever branch merges second
  adds the column there.
- C21 (two clauses of `status.md`'s eighth-pass text) is a docs nit for the engineer,
  recorded by the reviewer; it needs no QA.

## Scripts

Every launch: a copy of the bundle with `CFBundleIdentifier`
`me.sesser.gus.debugtest.qa150c`, re-signed ad hoc, on a scratch library made by
`photobench`, a fresh copy of the sources and a fresh import per run, `--library-root`
on every launch, no `open`. Set up (zsh, from the worktree; `$S` is a scratch folder):

```zsh
cd ~/Projects/Gus-hdr-merge && Scripts/build-app.sh && swift build -c release --product photobench --product photocli
cp -R build/Gus.app $S/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qa150c $S/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/Gus.app
.build/release/photobench generate --output $S/src --jpeg 2 --dng 0 --heic 0 --videos 1 --brackets 1
```

`run.sh NAME "SCRIPT"` is: `R=$S/runs/NAME; cp -R $S/src $R/src; photobench import
--library-root $R/lib --source $R/src; timeout 240 $S/Gus.app/Contents/MacOS/Gus
--library-root $R/lib --debug-script "SCRIPT"`. Every script starts `wait 2; rating any;
flag any;` (the copy keeps its own filters) and ends `quit`; after `search` a `wait 1`. A
`snapshot` taken while the sheet is up writes the sheet itself (1120 x 1280 for 560 x 640).

- **A. Defaults, choosing, boxes, table, reopening:** `search RAW_10; wait 1; selectall;
  print merge; merge sheet; print merge; merge reference 3; merge reference RAW_101;
  merge format dng; merge format tiff; merge align off; merge deghost off; merge table
  deselect; merge table select 2; merge table deselect; merge cancelsheet; print merge;
  merge sheet; merge cancelsheet`. Showed: three frames, reference RAW_102 (0 EV, shot
  second), no message, Name `RAW_102_HDR.tif`, both boxes on, the caption naming the
  reference, `sheet 560x640 (ideal 640) form content 517 shown 522 scrolls false`; `print
  merge` `canMerge false reason sheet up` with the sheet open; choosing 3 then RAW_101: the Name,
  announcement and thumbnail follow, Merge stays on; the format changes only the extension and
  caption; each box changes only itself; `table deselect` leaves row 1 (then row 2) chosen; after
  Cancel and `merge sheet` the sheet is RAW_102 with both boxes on.
- **B. Sheet snapshots:** `windowsize 1400 900; search RAW_10; selectall; merge sheet;
  snapshot sheet-default.png; merge reference 3; snapshot sheet-ref3.png`. Looked at both
  (dark): the folded captions, the Reference mark moving, the thumbnail changing (the
  walker moves), the Photo column cut (Q7).
- **C. Refusals, snapshots:** `search TWOFOLDERS; selectall; merge sheet; snapshot
  sheet-folder-refusal.png; merge reference 3; merge reference 1; merge cancelsheet; search
  MIXED; …; search .dng; …` (13 frames). TwoFolders: refused naming TWOFOLDERS_102 in
  `Locked`, the Name gray, Merge off, form 531 against 490; row 3 (`Open`): none, Merge on, "Merge is
  available."; row 1: refused again naming TWOFOLDERS_101 and flagged. Mixed: the mixed
  message, 517 against 504. 13 frames: "At most 9 photos can be merged at once. Select
  fewer.", the table at its cap, 681 against 518.
- **D. A real merge with the +2 EV frame as reference** (ratings 4 on RAW_102, 2 on
  RAW_103): `search RAW_10; focus RAW_102; key 4; focus RAW_103; key 2; selectall; merge
  sheet; merge reference RAW_103; merge start; search HDR; print items`. `RAW_103_HDR.tif`
  beside RAW_103, `items RAW_103_HDR:2`, its `.xmp` rating 2, DateTimeOriginal
  `10:00:02` (RAW_103's), same project; the masters' SHA-256 equal the pristine copies';
  details Reading, Aligning, Merging, Saving, Adding.
- **E. Unrelated scenes:** `search UNRELATED; selectall; merge sheet; merge start; merge
  sheet; merge align off; merge start; sidebar builtin all; search HDR; print items`. The first
  ends at Aligning (0.700): "The photos couldn't be merged. Nothing was added to the library.
  “UNRELATED_103” doesn't line up with “UNRELATED_102”. Merge photos of the same scene, or turn off
  Auto-align."; the second sheet opens with Auto-align on again; with it off the merge
  runs (Reading, Merging, Saving, Adding) and adds `UNRELATED_102_HDR`.
- **F. The walker bracket, six choices, one fresh library each** (`search RAW_10; selectall;
  merge sheet;` then): F1 `merge start`; F2 `merge deghost off; merge start`; F3 `merge align
  off; merge start`; F4 `merge reference RAW_103; …`; F5 `merge reference RAW_101; …`; F6
  `merge align off; merge deghost off; …`. TIFFs read with a stdlib reader
  (`tifdiff.py`, a scratch script) and converted with `sips` to look at. F1: the red disc once
  (the reference's place); F2: three discs (blend); F4 and F5: the disc at the +2 EV and −2 EV
  frames' places; the discs' outlines at 2x clean; F1 against F2 differ only where things moved
  (60,291 pixels, box x 87 to 1413, y 102 to 550); the others differ everywhere (a different frame to align to, or no
  alignment); F1/F2 window pane 0.0192 sd for every choice.
- **G. `photocli merge`** on `runs/G` (no app running): the seven calls listed under AC14
  and AC2a (`--format tiff|dng`, `--reference`, `--no-align`, `--no-deghost`; the unrelated
  series; a reference not among the versions), then a DNG and a TIFF again. JSON as
  listed; `exiftool -validate` OK on the DNG.
- **H. Undo and Redo:** `sidebar builtin all; search RAW_10; selectall; merge sheet; merge
  reference RAW_103; merge start; print items; undo; wait 1; print items; print messages;
  redo; wait 2; print items; print undo; search RAW_101; wait 1; focus RAW_101; key 5; wait 2`.
  Four items, three, then four again; the rating 5 after the Redo is in the catalog.
- **I. Slow disk** (`search TWOFOLDERS; selectall; merge sheet; merge slowdisk 3000; merge
  reference 3 nowait; print merge; wait 0.8; print merge; merge reference 2 nowait; print merge;
  wait 3.5; print merge; merge reference 3 nowait; print merge; wait 3.5; print merge`): the
  spinner off at first, on after the pause for `Open`, off at once on returning to the answered
  `Locked`, and `Open` answered afterwards (kept) gives Merge on and no spinner.
- **J. Stop, then another merge:** `search RAW_10; selectall; merge sheet; merge start
  nowait; print merge; merge stop; print items; print messages; merge sheet; merge reference 1;
  merge deghost off; merge start nowait; print merge; wait 0.3; print merge; merge wait`.
  `canMerge false reason running`, `canRemove false`, `stop merge`; stopped: "The merge was
  stopped. Nothing was added to the library.", no new file and no `.partial`; the next merge
  writes `RAW_101_HDR.tif`.
- **K. JPEG bracket:** `search JPEG_1; selectall; merge sheet; merge reference JPEG_103; merge
  start` (K2 default; K3 adds `merge deghost off`; K4 also `merge align off`): Q9.
- **L. AC1 and a video:** `search 0000; selectall; print merge; contextmenu cell 0; merge
  sheet; merge reference 3; print merge; merge cancelsheet; focus 0; print merge; search MVI;
  selectall; print merge`. `canMerge true`, the menu lists Merge to HDR…, "“MVI_00003” is a
  video. Only photos can be merged." with the video flagged; then `fewer than two` for one
  photo and one video; Q10.
- **M. Real ORFs** (`10M10354/55/56.ORF` copied from `~/gus-scratch`, hashes compared;
  imported in place), three libraries: default; `merge reference 10M10355`; `merge reference
  10M10356; merge deghost off`. Default reference `10M10354` (0 EV); the others name and take
  the metadata of the chosen frame; the TIFFs look right (trees, clouds, the reservoir, no
  doubled edge at fit).
- **N. Short window:** `windowsize 900 520; merge sheet`: the sheet stays 560 x 640 (the
  window has a minimum size); the clamp is P18's.
- **PAIR. Header thumbnail with RAW+JPEG pairs** (the three raws with three JPEGs renamed
  beside them): `search RAW_10; selectall; merge sheet; merge reference 3; merge reference 1;
  pairfile jpeg; …`: as listed under F8.

## For a person

VoiceOver, macOS 15 and macOS 26 are not asked (standing ruling). The first run's P1,
P3 to P10 are unchanged and listed under "Earlier runs"; P2 (the sheet's look) and P7 (long
names) are covered by P11 and P20 below.

- **P11 (design M8, M15; Q7). The sheet's look at the default size.** Select the three
  `RAW_10x` frames, ⇧⌘L. At three frames: no scrolling; the "Reference" mark whole; the
  Auto-align and De-ghost captions indented to their labels on one line; each caption inside its
  control's row with no divider between them; no "Photos" header; the Name line gray while a
  refusal shows and black when Merge is on. Light, Dark, Increase Contrast, Reduce
  Transparency (my snapshots are dark only). Say whether the Photo column's cut names
  (`RA…102 Reference`, Q7) are acceptable. Nine frames: the Form scrolls, header and buttons
  stay.
- **P12 (design M9). Choosing by pointer.** Click each row; ⌘-click the chosen row; click the
  empty space under the rows: one stays chosen (any one-frame flicker?). Is it clear from the
  caption alone that rows can be clicked? (If not, the pop-up fallback of design §5.5.)
- **P13 (design M10, D-H13). Keyboard, Full Keyboard Access on.** Tab order (table,
  Auto-align, De-ghost, Format, Cancel, Merge); arrows move the reference at once; Space toggles a box;
  **Return and Esc with the table focused**: after a click on a row, after Tab, and as the sheet opens
  (Return presses Merge when it is on, Esc cancels). What has the focus when the sheet opens? Reopen: the
  defaults again.
- **P14 (design M11). The folder refusal on a real slow volume.** `TwoFolders-0` is in the scratch
  library (`search TWOFOLDERS`): the refusal names the default reference, choosing the frame in
  `Open` lifts it, the other brings it back. Optional: one frame on a slow network share or a
  USB stick: the spinner appears only after a pause and Merge never comes on with a stale Name
  (scripted with `merge slowdisk`, script I; not tried on a real slow disk).
- **P15 (design M12; AC8's real case; "no colored speck"). A real merge with another frame as the
  reference.** On a hand-held bracket of yours with something moving (a person, branches),
  merge twice, the default and with another frame as the reference (copies of your files):
  name, folder, project and Info tab values are the chosen frame's; the moving thing appears
  once, in the chosen frame's place; at 100%, along the outline of whatever moved
  (also with the darkest and the brightest frame as the reference, De-ghost on): **no
  colored speck on the outline** (code review C18); no doubled edge.
- **P16 (design M12/M13, code review C14; Q9). A JPEG bracket from a real camera, the
  brightest frame as the reference.** Three JPEGs (not raws) of a scene with a bright window
  or sky, the brightest as the reference, De-ghost on: **no clipped band along the bright
  area's edge**; then De-ghost off where nothing moved: compare the highlights (on the fixture
  the on result is flatter, Q9). Say whether the difference matters on a real camera's files.
- **P17 (design M13). The two boxes on real files.** Frames of two different scenes with
  Auto-align on (refused, Activity ends "or turn off Auto-align") and off (merged, no
  "Aligning"); a tripod series with Auto-align off; a still scene with a flickering light with
  De-ghost off.
- **P18 (design M14). Height on a 13-inch laptop and in a short window.** The sheet fits the
  screen and a library window shorter than it (it clamps and the Form scrolls with the header and buttons
  in place); a two-line refusal; the "same exposure" note (no fixture has it). Script N could not make the
  short window.
- **P19 (design M16). The header thumbnail with RAW+JPEG pairs** shown as the JPEG (RAW+JPEG
  Pair ▸ Show JPEG): choosing another frame changes the thumbnail. Scripted on a made-up pair
  library, not seen.
- **P20 (carried from the first run's P2 and P7). Long names.** A frame with a 40-character
  file name: in the table (middle-cut, full name as the tooltip), the Name row (one line, middle-cut,
  tooltip), the Folder row with a long path (cut at its head), the toolbar's Activity item while it
  merges.

The owner's command (zsh, from the worktree; builds the bundle, gives it its own identifier,
a scratch library with a bracket series, the real ORF bracket and `TwoFolders-0`, and opens it on
`--library-root`; add your own bracket's copy under `$S/src/Mine` before the import):

```zsh
cd ~/Projects/Gus-hdr-merge && Scripts/build-app.sh && S=$(mktemp -d /tmp/gus-hdr-signoff.XXXXXX) && cp -R build/Gus.app $S/Gus.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.hdrmerge $S/Gus.app/Contents/Info.plist && codesign --force --deep --sign - $S/Gus.app && swift run -c release photobench generate --output $S/src --jpeg 2 --dng 0 --heic 0 --videos 1 --brackets 1 && mkdir -p $S/src/Real && cp ~/gus-scratch/photos/2016-05-21/10M1035[456].ORF $S/src/Real/ && swift run -c release photobench import --library-root $S/lib --source $S/src && open -n $S/Gus.app --args --library-root $S/lib
```

Search `RAW_10` for the walker series (`Brackets/Raw-0`; the red disc is the moving thing),
`10M` for the real bracket, `TWOFOLDERS` for the reference-folder refusal, `UNRELATED` for the
different scenes, `JPEG_1`, `MIXED`, `READONLY` for the rest. Merged files land beside their
reference in `$S/src`.

## Follow-up

### Rerun 2026-11-21 (this run, 9e178a8)

First-run findings: Q1 to Q4 **Fixed** (rerun at d635e12, below), Q5 recorded in
`docs/PROFILING.md`, Q6 (a refused Redo leaves the undo step offered) left as a nit; script H
repeats Q1's check on this build with a chosen reference and it holds. New: Q7 to Q10 above,
open, none blocking.

### Sign-off 2026-11-22

The owner signed off on 2026-11-22 (relayed by the main session), commit 36ca94e, after
running the scratch app on 2026-11-21 and 2026-11-22: P11 to P20 and the first run's P1 and
P3 to P10 pass. No checks left open ("nothing left open").

- Q7 (cut names in the Photo column): accepted as is by the owner; the Photo column is not
  widened.
- Q8 (no test for the extreme-reference choice) and Q10 (the debug script's print after close):
  left as nits.

---

## Earlier runs (kept as written)

The first run at d3545ad and its rerun at d635e12 (2026-11-20; before the sign-off revision).
Their P1 to P10 are open unless the owner reports them done.

### First run, d3545ad (2026-11-20)

Tested: `feature/hdr-merge` at d3545ad, the same Mac. The first run's text follows, its headings one level down (its Follow-up holds the rerun at d635e12).

### Verdict

**Superseded by the rerun in Follow-up (d635e12): Q1 to Q5 are fixed and the feature is ready for the owner's sign-off.** What follows is the first run, at d3545ad.

**Does not pass yet: one Blocker (Q1).** Redo of "Merge to HDR" deadlocks the
window's catalog write chain: the redone photo never comes back on screen, and
every later write of the session (a rating, an edit, the next merge's catalog
step) never lands, so the next merge hangs and a rating pressed after the Redo
is lost at quit. All 15 acceptance criteria (AC1 to AC15, AC2a included) pass
by test or script (AC13 is Undo only, as the PRD words it; Redo is design §9 and
fails), the full `swift test` is green on the second run, and every other path I
drove (TIFF and DNG, repeat merges, same-stem numbering, Stop, Undo, every
refusal, FAT32, `photocli`, the owner's real bracket) works.

### Results at a glance

- `swift build`: clean. `Scripts/build-app.sh all`: builds both apps.
- `swift test`: run 1, 1307 tests in 188 suites, **1 failure**:
  `ImportHashMemoryTests.aVerifiedCopyHoldsOneChunkNotTheFile` (the copy loop
  "grew the footprint by 589,366,448 bytes", limit 512 MiB). Not the known flake
  #229 (`DeferredRenderTests`) and not a merge test; it measures the whole
  process's footprint, so another suite's memory counts against it (Q3). Run
  alone: passes (5 of 5). Run 2 (whole suite again): **1307 passed, 0 failed**
  (224.6 s). The FAT32 test ran in both (`hdiutil` could attach). No golden
  moved; `UPDATE_GOLDENS` was not run.
- No migration: the newest is v14 (`CatalogSchema.swift`); the branch adds none
  (#88's v15 is a different branch, see Known limits). `Package.swift`,
  `Scripts/` and `Tests/.../Goldens` are untouched by the branch.
- Safety checks after the run: no `Gus` or `photocli` process left; the owner's
  `~/Library/Application Support/Gus/Library` has no file newer than my start
  (its `library.lock` and WAL are from 16:16, before I began); nothing under
  `~/gus-scratch` was written (the three ORFs were copied to a scratch folder
  first); every launch passed `--library-root` on a scratch library; no bare
  `open`. The worktree is clean.

### Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Script, Person | Scripts 1, 2, 5, 9: `print merge` gives canMerge true with 2+ targets (also with a video among them, where the sheet opens and refuses), false with one photo ("fewer than two"), one video, while the sheet is up ("sheet up") and while a merge runs ("running"). `contextmenu cell 0` lists Merge to HDR… after Duplicate for 3 photos, not for 1 photo or a video. `menuitems` shows File ▸ Merge to HDR… with ⇧⌘L. The menu's enabled state needs a key window; macOS would not activate the copy (`key nil`) twice, so I stopped | Pass (menu state: P1) |
| AC2 | Test, Script | `HDRMergeJobTests.mergesToTIFF` (hashes unchanged, folder, `_HDR-2`), `existingFileUntouched`, `MergeSelectionTests.naming` (a master's name, even a missing one's). Scripts 3, 8, 10: masters' SHA-256 equal before and after (synthetic, FAT32, real ORFs); the repeat gives `_HDR-2` | Pass |
| AC2a | Test, Script | `numbersPastTheStem` (DNG after TIFF is `-2`; an orphan `.xmp`; `X_HDR.DNG` against `.dng`; `-3` after `.tif` and `-2.dng`), `mergesToTIFF` (TIFF, TIFF, DNG gives `-3.dng`), `ownSidecars`. Script 3: TIFF then DNG gives `RAW_102_HDR.tif`, `RAW_102_HDR-2.dng`, then `-3`; script 10: the real bracket's TIFF and DNG each have their own `.xmp`; script 8: `photocli` on FAT32 gives `.tif`, `-2.dng`, `-3.tif` | Pass |
| AC3 | Test, Script | `mergesToTIFF` (0 EV frame second in time names it), `firstByTimeNames`, `MergeSelectionTests.orderAndReference`, `earliestWithoutCompensation`. Script: `RAW_102` (0 EV, middle in time) names `RAW_102_HDR` | Pass |
| AC4 | Test, Script | `mergesToDNG` (floating-point, linear, `SystemRAWDecoder.reads`), `MergeDNGTests.dngRoundTrip` (values back within 3 %), `sidecarWhenEnabled`, `mergesToTIFF` (16-bit, 3 samples, Display P3, catalogued with hash in the project). Script 3: `exiftool -validate` says OK on merged DNGs (BitsPerSample 16, SampleFormat Float, LinearRaw, WhiteLevel 1, BaselineExposure 1.845); script 10 on the real bracket: DNG valid, loupe shows it as the reference looks plus an HDR badge, TIFF looks normal (snapshots looked at). A sidecar appears only when sidecars are on and there are values | Pass |
| AC5 | Test, Script | `mergesToTIFF` (library values equal; the file's title, caption, keywords, rating, label, camera). Script 4: rating 4 set on the reference shows on both results (`print items`); real bracket: Artist, Copyright, Make, Model, lens, exposure time and DateTimeOriginal equal the ORF's, sidecars hold creator, rights, description | Pass |
| AC6 | Test, Script | `mergesToTIFF` (three raws), `mergesJPEGs`, `mixedRefused`, `pairCountsOnce`. Scripts 1, 2: JPEG series offers Merge; the mixed series is refused with the raw flagged, nothing written | Pass |
| AC7 | Test, Script | `MergeAlignmentTests` (0.5 px derived tolerance), `HDRMergeJobTests.unrelatedSceneRefused`. Script 6: Unrelated series stops, Activity "“UNRELATED_103” doesn't line up with “UNRELATED_102”. Merge photos of the same scene.", no file | Pass |
| AC8 | Test | `HDRMergerTests.ghostFree` (object once from the reference, no ghost where others were, equal to a no-ghost merge elsewhere to 1e-5). No synthetic moving scene exists in the library series, so no script | Pass (real moving subject: P6) |
| AC9 | Test, Script | `cancelLeavesNothing` (no file, no partial, no row). Script 5: `merge stop` mid-run: "The merge was stopped. Nothing was added to the library.", folder identical, no `.partial`; polling `print merge` every few hundred ms during a run returned live progress (Reading 1 of 3, Aligning 3 of 3, fractions), so the main actor stayed free; the failure case (unrelated) writes its reason to Activity | Pass |
| AC10 | Test | `HDRMergerTests.matchesReference` (CPU reference, derived tolerance 2^-17), `holdsTheRange`, `recoversRadiance` | Pass |
| AC11 | Test, Script | `resultIsAPhoto` (renders, edit with history, exports); the full suite, goldens included, passed with no golden touched; the loupe opened both formats in scripts 4 and 10 | Pass |
| AC12 | Test, Script | `MergeSelectionTests` (every refusal and their order, flagged sets), `readOnlyFolderRefused`, `MergeSafetyTests.refusedBySize`, `refusedByHeader`. Scripts 1 to 7: a video among three (named, flagged), a photo with its copy (named, copy flagged), differing sizes, 121 selected ("At most 9…"), mixed, read-only folder (case ReadOnly-0: "can't be written to", disk refused), offline (the FAT32 volume detached: "4 of these photos are offline"), unreadable (`chmod 000`: "“RAW_103” can't be read"), two 180 MP PNGs ("“OVER_1” is too large to merge. A photo can have at most 150 megapixels."), same exposure ("These photos have the same exposure settings…" note beside a copy refusal). In each, Merge is off and `merge start` writes nothing. The memory refusal is unreachable by script on this 24 GB Mac (budget 12 GB = 1.5 gigapixels; nine 150 MP frames are 1.35), so only the test shows it | Pass |
| AC13 | Test, Script | `undoAndRedo` (catalog level). Script 5: `print undo` reads "Merge to HDR", Undo takes the photo out, the selection goes back to the three frames, Activity says "“RAW_102_HDR.tif” was removed from the library. The file is still at …", the file stays. **Redo fails at the window level: Q1** | Pass for AC13 (Undo); Redo Fail, Q1 |
| AC14 | Test, Script | `MergeCommandTests.mergesFromTheCommandLine` (path printed, locked refusal, `tooFew`). Script 8: release app copy open on the library: `photocli merge` prints `libraryLocked`, exit 1; with the app closed it prints format, frames, path, reference, versionID and writes the file; a bad `--format` and one frame are refused | Pass |
| AC15 | Test, Script | `mergesToTIFF` (a second merge: own row, different SHA-256, same pixels; then a DNG), `againAfterRemoval`, `sameContentRefused`. Script 3: one library, four merges of the same frames (TIFF, DNG, DNG, TIFF) give four files with four different SHA-256, four distinct `xmpMM:DocumentID`s, four rows (`print items`) and no failure; script 9: the first results removed from the library with the files left, the next merge is `-4` and catalogued. A TIFF and a DNG are not compared for pixels (the DNG is unmapped, so they differ by design) | Pass |

Rules the build adds (design), by script: the landing rule (script 7: a photo
picked meanwhile keeps the selection; untouched, the new photo is selected and in
view), the quit text (`about quitask merging`: "Quit While Merging?", "The merge
is stopped and nothing is added.", Keep Merging, on the library window), removal
off while merging (`canRemove false` in the run), File ▸ Stop's job is the merge.

### Findings

**Q1 (Blocker). Redo of "Merge to HDR" deadlocks the window's catalog write
chain.** (`Sources/PhotoApp/Model/MergeModel.swift`, `registerUndo`, lines
352 to 355; `Sources/PhotoCore/Support/WriteChain.swift`.)

- Steps (script 11): scratch library; `search RAW_10; selectall; merge sheet;
  merge format tiff; merge start` (completes); `undo; wait 1; redo; wait 2`;
  then `search RAW_101; focus RAW_101; key 5; wait 2; print metadata`; `quit`.
- Expected: Redo puts the photo back (design §9, H10: "Redo checks the file" and
  puts the same photo back), the list shows it, and later changes save.
- Actual: after Redo, `print undo` says undo 'Merge to HDR' (the step moved), but
  the photo is not in `print items`, no message is posted (neither "added back"
  nor "couldn't"), and the catalog has the row. A rating of 5 pressed afterwards
  shows in the grid and is **never written**: after quit `catalog.sqlite` has
  rating 0 for `RAW_101` (read with `sqlite3`). A merge started after the Redo
  writes its file (`RAW_102_HDR-2.tif`) and then hangs at "Reading 1 of 3" until
  the process is killed (twice: scripts 5 and 11).
- Cause (by reading, matching the behavior): the Redo closure runs inside
  `model.persist { … }`, i.e. as the current tail of `WriteChain`; it then calls
  `self?.show(…)`, which calls `library.writes.read { … }`, and `read` starts with
  `settled()`, which awaits `tail?.value`, the very task that is running. It waits
  for itself. Undo is fine because `hide` doesn't call `read`.
- Impact: one Undo then Redo (a plausible pair of keystrokes) silently disables
  saving for the rest of the session. This is data loss for later edits, ratings
  and keywords (they show on screen and never reach the catalog).
- Why no test caught it: `undoAndRedo` calls `removeMergedMaster` and
  `restoreMergedMaster` on the catalog directly; nothing exercises the
  `registerUndo` closure on a `LibraryModel`. status.md's "`undo`/`redo` as AC13"
  line shows the script check read the undo name only.
- For the engineer: call `show` (or a `read`-free version of it) outside the
  chain, for instance after `persist` returns (`writes.afterPendingWrites`) or by
  fetching with `catalog.libraryItems` directly inside the chain, and add a
  test that fails now: a `WriteChain` test that calls `read` from inside
  `enqueue` is not enough on its own (it would deadlock the test); the useful
  test drives `LibraryModel`'s undo then redo and then a `persist`ed write, or
  adds a debug-script check `undo; redo; print items` that expects the photo
  back. Rerun this script after the fix.

**Q2 (Nit, tooling). The debug script's `quit` hangs while the merge sheet is
up.** `DebugScript.swift` `case "quit"` closes the export, look-up table and
preset sheets by their bindings but not `model.showsMergeSheet`; with the merge
sheet open the app never terminates (`timeout` had to kill it, exit 124; script
9's `merge sheet; quit`). Fix: set `model.showsMergeSheet = false` there. For a
real ⌘Q with the sheet up, see P4.

**Q3 (Flake, for the engineer to look at). `ImportHashMemoryTests` measures
process-wide footprint and failed once beside the merge suites.** Run 1 of the
full suite: "the copy loop grew the footprint by [589366448] bytes" against a
limit of 536,870,912, at the moment the merge suites (gigabyte frames) ran in
parallel. It passes alone and in run 2. The new merge tests raise the odds of a
red CI run for an unrelated suite. Suggest `.serialized` with the merge suites
(or a trait that keeps the memory-measuring suites from overlapping with them).
Not #229.

**Q4 (Question, minor). Creation dates in the written files.** On the merged
TIFF, `XMP:CreateDate`, `ExifIFD:CreateDate` and the IPTC digital creation
date are the merge's time (UTC), while `DateTimeOriginal` is the reference's
capture date; on the DNG, `ExifIFD:CreateDate` is the capture date but
`XMP:CreateDate` is the merge time. The library's capture date is right (test),
but a viewer that reads XMP's CreateDate first shows the merge time as when the
photo was taken, and the two formats disagree. R19's uniqueness already comes
from the random `DocumentID`; if the date was added only for uniqueness it can
stay the reference's (R7: "capture date"). Engineer to say whether it is
intended.

**Q5 (Info, not a defect). `photocli merge` from the debug build is slow.**
`.build/debug/photocli` (what `swift run photocli` runs) took about 30 s a merge
of three 1536 × 1024 frames (the time is in `MergeToneMap.plan`'s sort, sampled);
the release app does the same in a few seconds. Worth a sentence in the user
guide or PROFILING if anyone is to merge by `photocli` from a source checkout.

No test is missing for a criterion except the app-layer Redo of Q1.

### Scripts

Every launch: a copy of the bundle with `CFBundleIdentifier`
`me.sesser.gus.debugtest.qa150`, re-signed ad hoc, on a scratch library made by
`photobench`, a fresh copy of the sources and library per run, `--library-root`
on each:

```zsh
S=<scratch>; B=.build/release/photobench
cp -R build/Gus.app $S/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qa150 $S/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/Gus.app
$B generate --output $S/src --jpeg 2 --dng 0 --heic 0 --videos 1 --brackets 1
# per run R: cp -R $S/src $R/src; $B import --library-root $R/lib --source $R/src
$S/Gus.app/Contents/MacOS/Gus --library-root $R/lib --debug-script "<script>"
```

The app keeps its filters and Format between launches (the copy's own
preferences), so each script starts with `rating any; flag any`. After `search`
add `wait 1`.

1. **Sheet, formats, limits** (shows 121 photos too many, then 3 raws):
   `wait 2; search RAW_1; selectall; merge sheet` (without `wait 1` this selected
   everything: "At most 9 photos can be merged at once", the tenth onward flagged)
   and `wait 2; rating any; flag any; search RAW_1; wait 1; selectall; print merge;
   merge sheet; print merge; merge format dng; merge format tiff; merge cancelsheet;
   print merge; quit`. Showed: three frames, reference RAW_102, no message, disk
   clear, name `RAW_102_HDR.tif` then `.dng`, captions, canMerge true, "sheet up"
   while open, "fewer than two" with the selection gone.
2. **Refusal sheets**: `search JPEG_1 / MIXED / READONLY / UNRELATED; wait 1;
   selectall; merge sheet; merge cancelsheet` in one run. JPEG: no message,
   Merge on. Mixed: the raw flagged with the mixed message. ReadOnly: reference
   flagged, "can't be written to", disk refused. Unrelated: passes the sheet.
3. **Merge four times, same frames, one library** (`B.txt` style): `rating any;
   flag any; search RAW_1; wait 1; selectall; album Frames; sidebar album 0;
   wait 1; selectall; merge sheet; merge start; … ` repeated with `merge format
   dng`, `dng`, `tiff` and `sidebar album 0; wait 1; selectall` before each (the
   album keeps the three frames selectable once results exist). Names
   `RAW_102_HDR.tif`, `-2.dng`, `-3.dng`, `-4.tif`; four SHA-256 differ; four
   DocumentIDs differ; masters' hashes equal the source's; `exiftool -validate`
   OK on the DNGs; no `.partial`.
4. **Metadata and look**: `rating any; flag any; search RAW_10; wait 1; focus
   RAW_102; key 4; selectall; album Frames; wait 2; selectall; merge sheet;
   merge format tiff; merge start; sidebar builtin all; …; search HDR; wait 1;
   print items; focus 0; loupe; wait 2; snapshot <png>; key right; wait 2;
   snapshot <png>`. Both results rating 4 (`RAW_102_HDR:4`). TIFF snapshot: the
   shadow blocks and highlight steps are both distinct, normal brightness; DNG
   snapshot: dark and contrasty, "HDR" badge (the snapshot clips HDR at white).
5. **Stop, Undo, landing** (`E`): `…selectall; merge sheet; merge format tiff;
   merge start nowait; print merge; merge stop; print merge; print items; print
   messages; print undo; merge sheet; merge start nowait; print merge; wait 0.2;
   print merge; merge wait; print items; print selection; undo; wait 1; print items;
   print selection; print messages`. Stop: "The merge was stopped…", no file;
   running: `canMerge false reason running`, `canRemove false`, `stop merge`,
   fraction 0.167 then 0.800; done: the new photo selected (landing); Undo: three
   items, selection the three frames, message with the path. (Then `redo`: Q1.)
   Landing rule alone: `…merge start nowait; focus RAW_103; merge wait; print
   selection` keeps RAW_103 selected; the result is in the list.
6. **Failure and quit text** (`H`): Unrelated series: `merge start` ends with a
   warning naming the frame; `merge start nowait; wait 0.3; about quitask
   merging` prints the quit question's texts.
7. **Real bracket, copied** (`10M10354/55/56.ORF` copied to a scratch folder,
   imported in place): `rating any; flag any; search 10M; wait 1; selectall;
   merge sheet; merge format tiff; merge start; merge sheet; merge format dng;
   merge start; print items; print messages; quit`: reference `10M10354` (0 EV),
   names `10M10354_HDR.tif` and `10M10354_HDR-2.dng`, one `.xmp` each, ORFs'
   hashes unchanged, DNG valid. Peak resident set of the app process
   1.6 GB. Snapshots looked at: the TIFF lifts the trees' shadows with clouds
   intact, the DNG opens at the reference's brightness, no doubled edges in the
   branches or the skyline at fit.
8. **`photocli merge`**: `photocli merge --version 7 --version 8 --version 9
   --format tiff|dng|tiff --library-root $R/lib` prints the JSON (format, frames,
   path, reference, versionID); `--format png` and one `--version` are refused;
   with the app copy running on that library (`wait 14; quit`) it prints
   `libraryLocked`, exit 1. A FAT32 image (`hdiutil create -size 120m -fs "MS-DOS
   FAT32"`, attached with `-mountpoint`, the three DNGs copied in, imported in
   place): `photocli` merged to `.tif`, `-2.dng`, `-3.tif`; the app merged
   `-4.dng`; masters' hashes unchanged; no `.partial`; `exiftool -validate` OK.
9. **Offline, unreadable, removed-first, oversize**: with the FAT32 image detached
   the sheet says "4 of these photos are offline" with all frames flagged; with
   `chmod 000` on one master it says "can't be read"; on the FAT32 library
   `search HDR; selectall; removephotos; alert press Remove; …` then merging the
   three raws numbers past the leftover files to `-4`. Two 14000 × 13000 PNGs
   (about 530 KB each, a short Python script) and ten 11000 × 11000 ones imported
   in place: the first pair "too large… at most 150 megapixels", the ten "at most 9".
10. **Menu items and context menu**: `contextmenu cell 0` (3 selected, 1 photo,
   a video) as in AC1; `open -W -n --stdout <log> <copy> --args --library-root …
   --debug-script "…; menuitems Merge; …"` twice (the second after bringing the
   process forward by ID with System Events): `key nil`, the item reads
   `File/Merge to HDR… key shift+cmd+"l"` and "disabled" every time (no key
   window); not retried.
11. **Q1**: see Findings.

Also: `swift run -c release photobench generate --brackets 1 --bracket-size
6000x4000` and `photobench merge --files RAW_101.dng:RAW_102.dng:RAW_103.dng
--output DIR --format both` (three 24 MP synthetic DNGs): copies decoded to a
888 MB footprint, frames held at 1.96 GB, plan 2.55 s, TIFF 0.22 s, DNG 0.29 s,
**peak 2.73 GB** (the PRD's placeholder: about 3 GB). Synthetic, not a real
24 MP raw (P8).

### Known limits (accepted or not for this feature)

- R18 ("Show in Library" on the Activity row) not built (design D-H3, a Could).
- No detection of a merged DNG chosen as a frame beside its own source raws
  (RI-H4, D-H5c): script 9's M8 check selected the three raws and the merged
  DNG: the sheet shows four rows, no refusal, reference `RAW_102_HDR` (the DNG
  is at 0 EV and sorts first), name `RAW_102_HDR_HDR.dng`; Cancel writes nothing.
- Accepted placement residuals (code review, third pass): the window between
  reserving the name on FAT/exFAT and the rename; a crash between them leaves
  a 0-byte file and the hidden `.partial` (the next merge numbers past it); no
  sweep of old `.partial` files; Control-C on `photocli merge` can leave one.
- The memory refusal can't be reached by script on this Mac; only
  `MergeSafetyTests` show it.
- JPEG brackets are linearized by the color profile only (the camera's curve
  isn't recovered): proposed follow-up in status.md.
- **#88 (`feature/ai-masks`) merge order**: its migration v15 adds
  `editHistory.maskRasters`; `Catalog.removeMergedMaster` and
  `restoreMergedMaster` (`MergedMasters.swift` lines 94 and 129) list the
  history columns by name, so whichever branch merges second must add the
  column there (also status.md's heads-up). This branch has no migration, as the
  PRD expects.
- The standing ruling: VoiceOver, macOS 15 and macOS 26 are never asked of the
  owner; CI covers them.

### For a person

The owner can run everything below on the scratch library built by the command
at the end of this section.

- **P1 (design M2). The menu's key and enabled state with a real keyboard.**
  With a real ⇧⌘L: nothing selected, one photo, one video: the item is dimmed;
  two or more photos (also with a video among them) it is on and ⇧⌘L opens the
  sheet; with the search field focused ⇧⌘L still works; while a merge runs and
  while the sheet is up it is dimmed. (Scripted launches never had a key window.)
- **P2 (design M1). The sheet's look.** Header with thumbnail and count; the
  Photos table in capture order with the Reference mark; the flagged-row symbol
  and message in a refusal (try the `ReadOnly-0` series and a video among three);
  the Name row with a very long file name (one line, truncated in the middle,
  full name as the tooltip); the Folder row with a long path; both format
  captions.
- **P3 (design M3). Stop with real input.** Press Merge on the real bracket and
  Stop in the Activity popover with the mouse; again with ⌘.; and File ▸ Stop
  Merge. Nothing is added; the folder has no new file (look with Finder's hidden
  files shown: no `.merge-….partial`).
- **P4 (design M4). Quit during a merge.** ⌘Q while a merge runs: the question
  "Quit While Merging?" on the library window; Keep Merging continues; Stop and
  Quit leaves no hidden `.partial` file and no new photo. Also ⌘Q (and ⌘W) with
  the merge sheet open (the scripted `quit` was fixed, Q2): say whether a real
  ⌘Q quits.
- **P5 (design M5). The result's look in the loupe and another viewer.** Open the
  real bracket's `10M10354_HDR.tif` in Preview or Quick Look (should look like a
  normal picture) and the DNG in the loupe (opens at the reference's brightness,
  flat, highlights recoverable in the Adjust tab; on an HDR display the highlights
  go beyond white). Also compare the TIFF with any other app's merge of the same
  frames if you have one.
- **P6 (AC8's real case, PRD success line). A moving subject.** A hand-held
  bracket with a person or branches moving: the result shows the person once, no
  doubled outline. The scratch copy has no such series; use one of yours (copy it
  first).
- **P7 (design M6). The Activity item with a long name.** Merge a photo whose
  name is long (30+ characters): the toolbar item shows the job without
  overflowing.
- **P8 (design M7, and the PRD's 24 MP target). Undo, Redo and merge again with
  real menus, and a real 24 MP bracket.** Edit ▸ Undo Merge to HDR, then Edit ▸
  Redo Merge to HDR (the photo comes back in the grid and is selectable), press a
  rating on any photo, then merge again (`_HDR-2`). The scripted run of this now
  passes (Follow-up, F1); what is left for you is the real menu and keys. Also try
  Undo, then change the merged file in the Finder, then Redo: Activity should say
  it couldn't be added back. For the bracket: three real 24 MP raws, watch
  Activity Monitor: the PRD's placeholders are under a minute and about 3 GB above
  the start. I only had 16 MP raws (about 6 s) and a synthetic 24 MP bracket
  (2.7 GB peak).
- **P9 (design M8). A merged photo among its sources.** Select the three raws
  and a merged DNG and press ⇧⌘L: four rows, no refusal, the merged DNG is the
  Reference and the Name row reads `…_HDR_HDR.dng`; say whether that is clear
  enough. Cancel.
- **P10 (not scripted). Failures only a disk can give.** A full disk image (the
  "Space" message) and a master deleted mid-merge (the "Read" message): built,
  not run by the engineer or me.

To build the bundle and run it on a scratch library with a bracket (zsh, from
the worktree; the library is `$S/lib`, never the real one):

```zsh
cd ~/Projects/Gus-hdr-merge && Scripts/build-app.sh && S=$(mktemp -d /tmp/gus-hdr-signoff.XXXXXX) && cp -R build/Gus.app $S/Gus.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.hdrmerge $S/Gus.app/Contents/Info.plist && codesign --force --deep --sign - $S/Gus.app && swift run -c release photobench generate --output $S/src --jpeg 2 --dng 0 --heic 0 --videos 1 --brackets 1 && mkdir -p $S/src/Real && cp ~/gus-scratch/photos/2016-05-21/10M1035[456].ORF $S/src/Real/ && swift run -c release photobench import --library-root $S/lib --source $S/src && open -n $S/Gus.app --args --library-root $S/lib
```

Search `RAW_10` for the synthetic raws (`Brackets/Raw-0`), `10M` for the
real bracket, `JPEG_1`, `MIXED`, `READONLY`, `UNRELATED` for the refusals. The
merged files land next to the sources in `$S/src`.

### Follow-up

#### Rerun 2026-11-20 at d635e12 (fixes bb2ab53 and d635e12)

Tested: `feature/hdr-merge` at d635e12 (worktree `Gus-hdr-merge`; the only
uncommitted change in it is `code-review.md`, not mine), same Mac (Mac16,8,
macOS 27.2.1, SDK 27.2). A fresh copy of the bundle built from that commit, with
its own identifier (`me.sesser.gus.debugtest.qa150b`), re-signed ad hoc, scratch
libraries from `photobench`, `--library-root` on every launch, no bare `open`.
Nothing in `Sources/`, `Tests/`, `Scripts/` or `Package.swift` was edited; no
`UPDATE_GOLDENS`.

| Item | State | Evidence |
|---|---|---|
| Q1 (Blocker) | **Fixed** | F1 |
| Q2 | **Fixed** | F2 |
| Q3 | **Fixed as far as one run shows** | F3 |
| Q4 | **Fixed** | F4 |
| Q5 | Recorded in `docs/PROFILING.md` (the fix I suggested was a sentence somewhere; it isn't in the user guide, which is fine: the guide describes `photocli merge`, not debug builds) | read |
| Q6 (new, Nit) | Open, no action needed for sign-off | F1 |
| C11, C12 | Checked | F4, F3 |
| P1 to P7, P9, P10 | Open (a person) | list above |
| P8 | Open, now doable | list above |

**F1. Q1, script 11 on a fresh bundle and scratch library.** Library: `photobench
generate --jpeg 2 --dng 0 --heic 0 --videos 1 --brackets 1`, imported. Run A (all-photos
view, so the result shows in the list):

```
wait 2; rating any; flag any; search RAW_10; wait 1; selectall; merge sheet; merge format tiff; merge start; print items; undo; wait 1; print items; redo; wait 2; print items; print undo; search RAW_101; wait 1; focus RAW_101; key 5; wait 2; quit
```

It printed `items RAW_101 RAW_102 RAW_102_HDR RAW_103` after the merge, `RAW_101
RAW_102 RAW_103` after Undo, and **`RAW_101 RAW_102 RAW_102_HDR RAW_103` after
Redo**; `print undo` read undo 'Merge to HDR'; after quit `sqlite3` on
`Library/catalog.sqlite` gave `RAW_101.dng|5` (the rating pressed after the Redo)
and a row for `RAW_102_HDR.tif`.

Run B adds the second merge in the same session. To keep the three frames selectable
once a result exists it makes an album first (`album Frames; sidebar album 0; wait 1;
selectall` before the merge, as in script 3), and after the Redo it goes on:

```
sidebar builtin all; wait 1; search RAW_101; wait 1; focus RAW_101; key 5; wait 2; sidebar album 0; wait 1; selectall; print selection; merge sheet; print merge; merge format tiff; merge start; print merge; print items; print messages; quit
```

The sheet named `RAW_102_HDR-2.tif`, the merge ended "Merged 3 photos into
…/RAW_102_HDR-2.tif", Activity held three messages (merged, removed, merged),
`canMerge true` afterwards, the app quit by itself, and the catalog has
`RAW_101.dng|5`, `RAW_102_HDR.tif` and `RAW_102_HDR-2.tif`; both files are in the
folder. (The album view shows only the frames, so Run B's `print items` doesn't list
results; Run A shows the Redo.)

Run C, four merges in one session (TIFF, DNG, DNG, TIFF), then `undo; wait 1; redo;
wait 2` and `search HDR`: all four results are back (`RAW_102_HDR`, `-2`, `-3`, `-4`)
and the next sheet is named `-5`. Run D, the real bracket (the three ORFs, copied):
merge, `undo`, `redo`: `10M10354_HDR` is back in `print items`.

The refusal path (Undo, change the merged file in a second shell, Redo): the
script `…merge format tiff; merge start; undo; wait 14; redo; wait 2; print
messages; sidebar builtin all; search RAW_101; focus RAW_101; key 3; wait 2` while
a shell appended a byte to `RAW_102_HDR.tif` at the 9th second after it appeared:
Activity said "“RAW_102_HDR.tif” couldn't be added back because the file has
changed or is missing.", the photo stayed out, and the rating 3 pressed afterwards
reached the catalog (`RAW_101.dng|3`): the refused Redo does not hang the chain
either.

**Q6 (Nit, new).** After a refused Redo `print undo` reads undo 'Merge to HDR'
again (the undo manager moved the step back), so Edit ▸ Undo Merge to HDR is
offered and does nothing visible (no message, no crash, no hang: ran Undo then
Redo again). The same ordinary AppKit behavior as any undo whose reversal found
nothing to do. For the engineer to take or leave; not a blocker.

**F2. Q2.** Run C's script ended `…; merge format dng; merge sheet; quit` with the merge sheet open: the app quit and the wrapper's `timeout` did not fire (exit 0); no
`Gus` process left.

**F3. The full suite and builds.** `swift build`: clean. `Scripts/build-app.sh
all`: built both apps. `swift test`: **1309 tests in 189 suites passed, 0 failed**
(257.8 s), including the FAT32 test (it ran: `hdiutil` attached) and the new
`afterPendingWrites from inside a running write …` (C12) and `C11: the capture
date's offset reaches XMP only when it is a real one`. No red test, so neither
#229 (`DeferredRenderTests`) nor the memory test failed; `ImportHashMemoryTests`
now sits in the serialized `MemoryHeavy` parent suite (the 189th suite) with the merge suites and
passed (`aVerifiedCopyHoldsOneChunkNotTheFile`, 0.81 s). One green run cannot
prove a flake gone: Q3 is fixed as far as I can show, and the first run's failure
needed the overlap the serialization removes. The suite's long skips are the
usual environment-variable ones.

**F4. Q4 and C11, by exiftool on files written by the new build.** The reference's
capture date is `2026:05:01 10:00:01` (synthetic) and `2016:05:21 08:43:02` (the
real ORF). In every output (TIFF and DNG, four merges of the synthetic bracket, and
the real bracket's TIFF): `ExifIFD:DateTimeOriginal`, `ExifIFD:CreateDate`,
`XMP-xmp:CreateDate` (and in the TIFFs `IFD0:ModifyDate`, `IPTC:DigitalCreationDate`
and `Time`) are that date, nothing is the merge's time. The four synthetic merges'
SHA-256 all differ (`0c64…`, `332f…`, `2ff5…`, `99cf…`) and their `xmpMM:DocumentID`s
are four different values. A JPEG bracket whose frames I gave
`OffsetTimeOriginal=+02:00` (exiftool on the scratch copy): TIFF and DNG carry
`xmp:CreateDate 2026:05:01 10:01:01+02:00`, the DNG validates OK, so the offset is
carried when real. (The blank-offset case needs ImageIO to write it; the unit test
`captureDateOffset` covers it, and I did not reproduce it by script.)
`exiftool -validate` on the DNGs: OK, all merged DNGs (four). **The TIFF warnings
are not identical to the pre-fix ones, by one minor line.** I built `d3545ad`'s
`photocli` in a scratch copy (outside the checkout) and merged the same three
frames to a TIFF: its warnings are 7 (3 minor); the new TIFF's are 8 (4 minor).
The same seven appear in both (XMP missing xpacket wrapper, IPTC-NAA undef type,
missing ExifVersion, FlashpixVersion and ColorSpace, ExifImageWidth and
ExifImageHeight not allowed in TIFF), and the new one is "IPTC DigitalCreationTime
too short (6 bytes; should be 11)": ImageIO writes the IPTC time as `HHMMSS` when
the date has no offset, and the old build's merge time carried `+00:00`, which made
it 11 bytes. So it is ImageIO's own writing, as the engineer says, and it is the
price of not stamping a fake UTC offset on a camera's local time. All warnings are
ImageIO's TIFF/IPTC structure; none is ours. The JPEG-bracket TIFF with the real
offset shows two more minor "Odd offset" lines, also ImageIO's layout.

**F5. No migration, no golden.** The branch's newest migration is still v14
(`CatalogSchema.swift`); `git diff develop...HEAD` touches no migration, no file
under `Tests/PhotoCoreTests/Goldens`, `Package.swift` or `Scripts/`; the two fix
commits touch `DebugScript.swift`, `MergeModel.swift`, `MergeOutput.swift`, tests and
docs only. `PreviewCacheKey.currentPipelineVersion` is unchanged.

**F6. User guide.** The two fix commits changed no guide text (the guide's merge
section came in `06d2435`). The sentences that matter here are true as built: "Edit ▸
Undo Merge to HDR takes the new photo out … and leaves its file on disk (Activity
says where); Redo puts it back if the file hasn't changed" (F1: Redo brings it back;
a changed file is refused with the message), "Merging again after Undo writes
`_HDR-2`" (F1), the name rule for TIFF then DNG (`-2.dng`), and for `photocli
merge`: it prints the file's `path`, writes no sidecar (no `.xmp` beside its
output, while the app's merge of a photo with values writes one) and is refused
while the app has the library open (first run, script 8). Q5's slowness is in
`docs/PROFILING.md`, not the guide.

**The owner's paste command.** Run step by step in a scratch folder (the same
commands, `mktemp` swapped for my scratch path, the last `open -n` swapped for the
bundle's executable with a debug script that quits): `Scripts/build-app.sh`'s bundle
copied and re-identified, `swift run -c release photobench generate …
--brackets 1`, the three `10M1035[456].ORF` copied (hashes equal to the originals,
which are not written), `photobench import` (21 imported), and the app opens on that
library: `merge sheet` for `10M` lists 10M10354 (0 EV, reference), 10M10355 (−1 EV),
10M10356 (+1 EV), no message, name `10M10354_HDR.tif`. It works as written.

**Safety.** After the run: no `Gus` or `photocli` process; the owner's
`~/Library/Application Support/Gus` has no file newer than my start marker (its
`library.lock` and WAL are still from 16:16, before I began); the scratch source
folders were copies (the ORFs under `~/gus-scratch` were copied, never merged in
place).

Owner's sign-off, the commit signed off, its date and any checks left open: not
yet given.
