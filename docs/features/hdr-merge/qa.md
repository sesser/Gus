# HDR merge: QA

Owner: qa-tester. Date: 2026-11-20. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/hdr-merge` at d3545ad (clean worktree `Gus-hdr-merge`), on a
Mac16,8 (Apple M4 Pro, 24 GB), macOS 27.2.1 (26B131), Xcode SDK 27.2; the bundle's
executable records minos 15.0 and sdk 27.2.

## Verdict

**Does not pass yet: one Blocker (Q1).** Redo of "Merge to HDR" deadlocks the
window's catalog write chain: the redone photo never comes back on screen, and
every later write of the session (a rating, an edit, the next merge's catalog
step) never lands, so the next merge hangs and a rating pressed after the Redo
is lost at quit. All 15 acceptance criteria (AC1 to AC15, AC2a included) pass
by test or script (AC13 is Undo only, as the PRD words it; Redo is design §9 and
fails), the full `swift test` is green on the second run, and every other path I
drove (TIFF and DNG, repeat merges, same-stem numbering, Stop, Undo, every
refusal, FAT32, `photocli`, the owner's real bracket) works.

## Results at a glance

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

## Acceptance criteria

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

## Findings

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

## Scripts

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

## Known limits (accepted or not for this feature)

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

## For a person

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
  the merge sheet open: the scripted `quit` hangs there (Q2); say whether a real
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
  real menus, and a real 24 MP bracket.** Edit ▸ Undo Merge to HDR, Redo, then
  merge again (`_HDR-2`): **blocked by Q1 until it is fixed; rerun after.** For
  the bracket: three real 24 MP raws, watch Activity Monitor: the PRD's
  placeholders are under a minute and about 3 GB above the start. I only had
  16 MP raws (about 6 s) and a synthetic 24 MP bracket (2.7 GB peak).
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

## Follow-up

Reruns after fixes (Q1 to Q4) and the owner's sign-off are recorded here.

| Item | State |
|---|---|
| Q1 | Open |
| Q2 | Open |
| Q3 | Open |
| Q4 | Open (question) |
| P1 to P10 | Open |
