# HDR merge: code review

Owner: code-reviewer. Date: 2026-11-20. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/hdr-merge`, `ed423d7..cda61fd` (7 commits). Build and tests:
`swift build` clean, no warnings; `swift test` 1291 tests in 186 suites passed
(200.7 s). Also run here: `photobench generate --brackets 1` and `import` into a
scratch library, then `photocli merge` on the RAW bracket twice as TIFF and once
as DNG; `exiftool -validate` on the DNG says OK.

## Verdict

Not ready for QA. One blocker (C1): merging the same frames a second time writes
a file that the library can't take. The file is left in the masters' folder with
no catalog row, and Activity says the merge worked. Two should-fix findings
concern files left in the masters' folder on quit (C2) and two merged photos
sharing one sidecar (C3). The pipeline, the writers, the catalog step, undo, the
guards and the concurrency are sound.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Blocker | `Merge/HDRMergeJob.swift:206-207`, `Catalog/MergedMasters.swift:41-46`, `PhotoApp/Model/MergeModel.swift:277-283` | The merge's output is deterministic, so merging the same frames again in the same format writes a byte-identical file. The catalog accepts each content hash once, so `insertMaster` skips the new file. `insertMergedMaster` then throws `alreadyInLibrary` with the **first** merge's version, and the job returns that as a success. | Reproduced with `photocli merge --version 7 --version 8 --version 9` run twice on a scratch library. `RAW_102_HDR.tif` and `RAW_102_HDR-2.tif` have the same SHA-256 (`d1e38ffd…`). Both runs print `"versionID" : 18`, and the catalog holds one `_HDR` row. In the app, Activity says "Merged 3 photos into …/RAW_102_HDR-2.tif.", the first merge's photo is selected, no undo step is registered, and `_HDR-2.tif` sits in the masters' folder, unknown to the library. A DNG merge has no timestamps either, so it behaves the same. `mergesToTIFF` checks only the second run's name, so it passes. Fix suggestion: make each merge's file unique, for example an XMP `xmpMM:DocumentID`/`InstanceID` UUID or the merge time as `xmp:CreateDate`/`MetadataDate`, which is honest metadata. Keep `alreadyInLibrary` for the path case only, and assert `again.master != nil` in the test. | PRD R6, AC2, AC4; design §9 ("Merging again") |
| C2 | Should fix | `PhotoApp/PhotoApplication.swift:118-123` | Stop and Quit calls `library.merge.cancel()` and then `NSApp.terminate(nil)` right away. The second `applicationShouldTerminate` returns `.terminateNow` (`QuitGuard.allowsQuit`), so the process exits before the merge task reaches a cancellation check or `writeInPlace`'s `defer`. | Quitting during **Saving** leaves the hidden `.RAW_102_HDR.tif.<UUID>.partial` in the masters' folder. For a DNG it exists for the whole banded render; for a TIFF, during `CGImageDestinationFinalize` and the link. Quitting during **Adding** (hashing, metadata read and catalog write, after the link) leaves a complete `_HDR` file with no catalog row and no Activity row, after an alert that said "nothing is added". Fix suggestion: after cancelling, `await library.merge.waitUntilDone()` before `NSApp.terminate`. Cancellation is checked between 512-row bands, so the wait is short, and design §7.1 already accepts that a stop during Adding finishes the photo. Export has the same pattern, but its partial files land in a folder the user chose. Here they land beside masters. An interrupted `photocli merge` (Ctrl-C) can leave the same `.partial` file. That is less important, but worth a line in the user guide or a signal handler. | PRD R11, AC9; design §7.2, §7.4 |
| C3 | Should fix | `Merge/MergeSelection.swift:231-235` (`ExportNaming.freeName`), with the existing `Sidecars/SidecarFiles.swift:25-27` and `SidecarSync.swift:163-166` | The result is numbered only when its exact name is taken. A bracket merged once as TIFF and once as DNG (the obvious way to try both formats) gets `RAW_102_HDR.tif` and `RAW_102_HDR.dng`: two unpaired masters with one stem. With sidecars on, the first gets `RAW_102_HDR.xmp`. For the second, `sidecarTargets` prefers `RAW_102_HDR.dng.xmp` (`stemIsShared`), but `findSidecar` falls back on `stem.xmp`, finds the first one's file and adopts it, or flags it if the values differ. | Trace: TIFF merged (reference rated 4), so `RAW_102_HDR.xmp` is written. DNG merged: `syncForced` → `findSidecar` → the TIFF's file → values match → the DNG's `metadataSync.sidecarName` is `RAW_102_HDR.xmp` too. Rate the DNG 5: the app writes rating 5 into the file the TIFF owns. The TIFF's next check finds its sidecar "changed by another app", flags it for review, and "Use file" gives the TIFF 5 stars. If the reference's values changed between the two merges, the new photo is flagged for review as soon as it lands. The root cause is in SidecarSync and is older than this branch (any unpaired same-stem masters), but this feature makes it routine. Options: number the result past any master, file or sidecar sharing its stem in the folder (`RAW_102_HDR-2.dng`), which changes how R4's "name clash" reads (see Questions); or a follow-up issue on SidecarSync's candidate order for shared stems. | CLAUDE.md XMP sidecars ("never overwrite a sidecar another app changed"); PRD R6, A8 |
| C4 | Nit | `PhotoApp/Model/MergeModel.swift:337-352` | The inverse step is registered whatever the persisted work finds. After a Redo that can't put the photo back (file changed or gone; "couldn't be added back" is shown), Edit ▸ Undo Merge to HDR is still offered. | Choosing it runs `removeMergedMaster`, which returns nil, and still posts "“RAW_102_HDR.tif” was removed from the library. The file is still at …". The photo wasn't in the library, and the file may be gone. Report only when `step.removed != nil` (and skip `hide`). | Undo: each step records exactly what it changed |
| C5 | Nit | `Merge/MergeOutput.swift:7-8`, `Merge/LinearDNGWriter.swift:3-4, 63` | After RI-E1, the doc comments still say the DNG is 32-bit floating point, and `LinearDNGWriter.init` defaults `bitsPerSample` to 32. Every caller passes `MergeOutput.dngBitsPerSample` (16), so nothing is wrong at run time. | A reader of `MergeFormat` or the writer is told the wrong format. | — |

## Questions

- **RI-E1 (16-bit float DNG), for the product manager.** Technically I agree with
  option (a). Half floats hold 24 stops below the normalized white (subnormals
  included) at 11 bits of precision, which covers 9 frames at 2 EV apart with
  room to spare. The system decoder reading the file is what makes the loupe's
  HDR view and other apps work, and `exiftool -validate` passes. The PRD's Open
  question 1 and R5 still say 32-bit, so the ruling needs recording.
- **The quit alert's buttons, for the designer.** Reusing QuitGuard's **Stop and
  Quit** and **Keep Merging** matches the other quit alerts. I see no reason to
  differ, but the wording is the designer's call (design §7.4).
- **The landing rule in the loupe, for the designer.** `MergeLanding.selects`
  requires the grid, so a merge that ends while the loupe shows leaves the
  selection alone. That is a fair reading of the two sentences of §8.3, which
  conflict, but the designer should confirm it.
- **C3's fix and R4, for the product manager and the designer.** If the fix
  numbers the result when another file in the folder already has its stem,
  merging to DNG after a TIFF merge gives `IMG_1234_HDR-2.dng`. That is
  defensible as a "name clash", but it is a reading of R4 the owners should
  confirm. The alternative leaves names as they are and fixes SidecarSync
  instead, as a follow-up issue.
- **For the main session, a semantic conflict with #88 (`feature/ai-masks`).**
  Its v15 adds `editHistory.maskRasters`, and it updates
  `RemovedCopy.HistoryRow` and Copies.swift to carry the column. The new field
  is an optional `var`, so the memberwise call in `removeMergedMaster` still
  compiles after both branches merge. The fixed column lists in
  `removeMergedMaster`/`restoreMergedMaster` (`MergedMasters.swift:88-93`,
  `122-126`) would then silently drop `maskRasters` on Undo/Redo of a merge,
  and history entries would lose their raster references (which #88's launch
  cleanup then deletes). Whichever branch merges second must update those two
  queries. This branch has no migration of its own.

## Checked and fine

- **Masters are never written.** The only file writes are the result and its
  sidecar. The file is written to a hidden `.partial` beside the target, the
  partial is removed in a `defer` on failure or cancellation (cancellation is
  checked between bands and after the body), and it is put in place with
  `link(2)`. That fails with `EEXIST` rather than replace anything. The move
  fallback (file systems without hard links) checks the name first, and a taken
  name retries with the next free one up to 3 times. `freeName` avoids files and
  catalog masters (`MasterFiles.Names`). AC2's hashes are unchanged in tests and
  in my photocli run. Names come from the catalog's file name, so there is no
  path from file contents.
- **The `insertMasters` refactor.** The loop body moved verbatim into
  `insertMaster` (`continue` became `return`), and pairing and the companion
  `metadataSync` cleanup stay in `insertMasters`. There is no behavior change.
- **The catalog step.** It is one transaction: insert, the reference's values
  (rating, flag, label, keywords, descriptive fields) and pairing. It runs on
  the model's write chain (`onWriteChain`) inside a detached task, so a Stop
  during Adding doesn't cut it. The path-conflict case (an import that took the
  file first) is handled and tested (`importBesideMerge`). There is no migration
  and no schema change. Ids are `AUTOINCREMENT`, so a restore with the same ids
  can't collide with rows made after Undo.
- **Undo and redo.** There is one step, registered after the catalog write, in a
  group of its own when none is open. Undo and Redo run through `persist`. Undo
  keeps the rows, Redo checks size and date before restoring, and the file and
  sidecar stay on disk.
- **Swift 6 concurrency.** `HDRMergeJob.run` and the pipeline are nonisolated
  async on a Sendable struct; the package uses Swift 6 mode with no
  `NonisolatedNonsendingByDefault`, so they run off the main actor. The
  preflight is detached. Progress hops to the main actor and never moves
  backward, and late reports are ignored once the job ends. LibRaw's
  `CancellationError` is passed through. No `@unchecked Sendable` or
  `nonisolated(unsafe)` is added.
- **Memory.** Frames are held as half floats (8 bytes a pixel) with decoders let
  go per frame in `autoreleasepool`. Output is rendered in 512-row bands, the DNG
  is streamed in strips under 1 MiB, and the merge has its own `CIContext` with
  `cacheIntermediates` off.
- **The DNG writer** follows the DNG Specification 1.4: LinearRaw, IEEE float
  `SampleFormat`, `DNGBackwardVersion` 1.4, `ColorMatrix1` as XYZ to Rec. 2020
  under D65, `AsShotNeutral` 1,1,1, `WhiteLevel` 1, and `BaselineExposure` =
  log2(brightest) + the reference's default exposure. The IFD layout is sorted,
  word-aligned, and has correct strip offsets and counts. `exiftool -validate`
  says OK, with BitsPerSample 16 and float samples. **The TIFF writer** is
  16-bit RGB in Display P3, takes metadata through `ExportMetadata` (orientation
  1, since the pixels are upright), and carries an XMP with the library values.
- **The kernels and the CPU reference.** `mergeAccumulate`, `mergeResolve` and
  `mergeToneMap` match `MergeMath` and `MergeToneMap`. `MergeReference` is plain
  Swift in Double precision. The 2^-17 relative tolerance is derived (float
  roundings, Metal log and exp ulps, sample-position rounding per pixel), and the
  pixels left out, at most 5%, are named: shares on a tap decision or the steep
  hat shoulders. No golden moved, `UPDATE_GOLDENS` was not run, and
  `currentPipelineVersion` is still 13.
- **The selection rules.** A pair counts once, as its raw. The reference is the
  0 EV frame only when the metadata singles one out; otherwise it is the
  earliest. Refusals come in design §6's order with their flagged frames, the
  disk preflight runs at open and again at start, and sizes are checked from the
  catalog and again after decoding.
- **Guards.** Remove from Library is off while merging (`isMerging`); the quit
  question has `.merging`; File ▸ Stop names the merge; the sheet is in
  `LibraryModal`; `canMerge` uses `can`, as Export does; the context item is in
  the grid only.
- **`photocli merge`.** It is `access: .write`, so the registry takes the
  library lock, and refusal while locked is tested. It resolves pairs as the app
  does, prints `path`, `format`, `frames`, `reference` and `versionID`, and has
  no `--dry-run` (none required). It writes no sidecar; the queue entries from
  its catalog triggers are written by the app on its next sync.
- **Strings.** 53 new catalog keys and 1 comment updated. The plurals ("Merge %lld
  Photos to HDR", "Merged %lld photos into %@.", "At most %lld…", "%lld of these
  photos are offline…") have one/other variants, there is no product name, and
  `LocalizationTests` and `BrandingTests` pass.
- **Persisted names.** These are the preference key `merge.format` and the JSON
  keys of `photocli`. They are generic.
- **Dependencies.** Only Apple frameworks (Vision, Core Image, ImageIO). No
  package or vendored code is added.
- **Fixtures.** The `SyntheticDNG` and `SyntheticImages` options default to the
  old values, so the existing fixtures are unchanged. The `StoppableJob` tie test
  was updated for the new last case, under the same rule.

## Follow-up

(Filled in on the second pass.)
