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

Second pass, 2026-11-20, on `46b5107` and `a3a597d` (status `8ad8f77`). See
**Second pass** below for what I ran and for the new findings C6 to C9.

| # | State | Commit | Note |
|---|---|---|---|
| C1 | Fixed | `46b5107` | Every merge's XMP (TIFF and DNG) carries a new `xmpMM:DocumentID`/`InstanceID` and `xmp:CreateDate`. `alreadyInLibrary` now means only the same path with the same hash. A different master with the same content gives `sameContent`: the job fails and removes its own file, but only while the name still holds the inode it wrote. Checked with `photocli merge` run twice as TIFF, then once as DNG, on a scratch APFS library: three rows (versions 4, 5, 6), three different SHA-256 values, three different document ids (exiftool). `mergesToTIFF` now requires `again.master`. The job's removal path itself has no test (C8). |
| C2 | Fixed, with a new finding | `46b5107` | Stop and Quit now waits for the merge before `terminate`. But the 10 s limit doesn't hold (C7). |
| C3 | Fixed | `46b5107` | `MergeNaming.name` numbers the result past any stem in the folder listing (any extension, case- and normalization-folded, sidecars and orphan `.xmp` files included) or in the library's masters there (`containsStem`). Checked: TIFF, TIFF, then DNG gave `_HDR`, `_HDR-2.tif` and `_HDR-3.dng`. `ownSidecars` shows each file keeps its own sidecar. SidecarSync's fallback is bug #248. Residual race: a same-stem file with another extension that appears between naming and `link` isn't seen (`link` only stops the exact name). Only an import into that folder at that moment can cause it, and the result is #248's case. I accept it. |
| C4 | Fixed | `46b5107` | Undo after a failed Redo reports and hides only when a photo was taken out. Traced: the next Redo then does nothing, silently. |
| C5 | Fixed | `46b5107` | `LinearDNGWriter.bitsPerSample` is a constant 16, and the comments say half floats. No 32-bit wording is left in the merge code. |
| Security M1 | Fixed | `a3a597d` | 150 MP per frame, checked from the catalog in the sheet, then from each decoder's own size (`nativeSize`, the LibRaw extent, or the ImageIO header) before any render at that size. A budget of half the physical memory, at 8 bytes a pixel, is checked in the sheet and again per frame before `held` allocates, with overflow-safe arithmetic. The TIFF is encoded from a sequential provider that renders 512-row bands, so there is no whole-image `Data`. The provider's `@unchecked Sendable` has a reason that holds: the encoder reads it synchronously on the job's thread. `refusedByHeader` (a 180 MP PNG under 1 MiB) and `budgetBeforeHolding` pass. |
| Security M2 | Fixed | `a3a597d` | `LinearDNGWriter.fits` runs before `createFile`, with overflow-checked multiplication. With the 150 MP cap a DNG is at most about 900 MB, so the check can't be reached in practice, but it holds. |
| Security L1 | Fixed | `a3a597d` | The hidden name is `.merge-<UUID>.partial` (51 bytes), and the stem is shortened to fit 255 bytes with room for `_HDR-999.ext`. |
| Security L2 | Fixed | `a3a597d` | Removal is by `lstat` device and inode, compared with the identity of the file the job linked. |
| Security L3 | Fixed | `a3a597d` | Exposure values that aren't finite, aren't positive, or give a ratio outside 2^±16 count as unknown. The same-exposure note ignores non-finite values. |
| Security L4 | Fixed | `a3a597d` | `photocli merge` treats a volume as online by its identity only. |
| Security L5 | Fixed | `a3a597d` | Every merge error is logged `.private`. |
| Security L6 | Not fixed (accepted) | — | No sweep for old partial files. The guide mentions Control-C. |
| Security L7 | Fixed, with a regression | `a3a597d` | The fallback now runs only for ENOTSUP, EOPNOTSUPP and EPERM, and uses `renamex_np(RENAME_EXCL)`. On FAT32 and exFAT that call fails with ENOTSUP too, so every merge beside masters on those volumes now fails (C6, Blocker). |
| Security L8 | Fixed | `a3a597d` | `MergeNaming.isPlainPlace` rejects an absolute path, an empty part, `.`, `..`, a NUL, or a file name that isn't the path's last part. The catalog derives `fileName` from `relativePath` (`Catalog.insertMaster`), so real libraries always pass. |

## Second pass

Owner: code-reviewer. Date: 2026-11-20. Reviewed: `feature/hdr-merge`,
`cda61fd..8ad8f77` (`46b5107`, `a3a597d`; the reviewers' files `ca5eae6`,
`58841d5`; status `8ad8f77`). Build and tests: `swift build` clean; `swift test`
1303 tests in 187 suites passed (237.0 s). Also run here:

- `photobench generate --brackets 1`, imported into scratch libraries, then
  `photocli merge` on the RAW bracket.
  - On APFS: TIFF, TIFF again, then DNG. All three were catalogued with
    different hashes and document ids.
  - On a FAT32 disk image and on an exFAT disk image (`hdiutil create -fs`,
    attached under the scratchpad, detached afterwards): both merges failed
    (C6).
- A 20-line C probe of `link`, `renamex_np(RENAME_EXCL)`, `open(O_EXCL)` and
  `rename` on APFS, FAT32 and exFAT.
- A standalone Swift 6 program for C7.

### Verdict

Not ready for QA. C1 to C5 and the security findings are fixed as described.
One regression is a blocker: the L7 fix stops every merge whose reference is on
a FAT32 or exFAT volume (C6). External drives and cards are usually formatted
that way. The Stop and Quit wait has no real 10 s limit (C7). Both fixes are
small.

### Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C6 | Blocker | `Merge/MergeOutput.swift:247-255` (`writeInPlace`) | On FAT32 and exFAT (macOS 27.2, FSKit mounts), `link(2)` fails with ENOTSUP, as intended. `renamex_np(…, RENAME_EXCL)` then also fails with ENOTSUP (errno 45), whether or not the target exists. The code turns that into `writeFailed`. Before `a3a597d`, the fallback was `fileExists` then `moveItem`, which worked there. `linkFallback` stubs `link` but runs the real `renamex_np` on APFS, so it passes. | `photocli merge --version 1 --version 2 --version 3` on a library imported in place from an exFAT image, and again from a FAT32 image, prints `{"code":"writeFailed","error":"writeFailed(\"The operation couldn’t be completed. Operation not supported\")"}`. Nothing is written, so no data is at risk. In the app the sheet's preflight passes (the folder is writable), the whole merge runs, and the job fails at the last step. Probe results: on APFS, `link` gives 0 and `renamex_np` EXCL gives EEXIST onto a taken name. On FAT32 and exFAT, both give ENOTSUP. On FAT32 and exFAT, `open(target, O_CREAT\|O_EXCL)` reserves a free name, refuses a taken one with EEXIST, and `rename(temporary, target)` then replaces that placeholder. Fix suggestion: when `renamex_np` gives ENOTSUP, reserve the name with `O_CREAT\|O_EXCL` (EEXIST means `nameTaken`) and `rename` over the placeholder. Compare the placeholder's inode first if that's wanted. Make the rename injectable, as `linkFile` is, so a test can drive the ENOTSUP-then-ENOTSUP path. A test on a FAT32 image (CLAUDE.md, "A FAT32 disk image") would pin it for real. | PRD R3 and R6 (the result is written beside the reference, wherever the masters are); CLAUDE.md "Volumes can go offline" (external volumes are first-class) |
| C7 | Should fix | `PhotoApp/Model/MergeModel.swift:248-256`, `PhotoApp/PhotoApplication.swift:126` | `waitUntilDone(timeout:)` races `task.value` against `Task.sleep` in a `withTaskGroup`. A task group waits for all of its children before it returns. `group.cancelAll()` doesn't end the child awaiting `task.value`, because awaiting another task's value doesn't respond to cancellation. So the wait lasts until the merge ends, however long that takes. The 10 s limit in the code, its comment and `status.md` never applies. | A standalone program with the same function, a detached task that takes 4 s without checking for cancellation, and `timeout: .seconds(1)` printed "returned after 4.01 s (timeout 1 s)". In the app, Stop and Quit waits as long as the merge's remaining non-cancellable work takes: a full-frame render in `held`, hashing the file, the ExifTool metadata read, or the catalog step queued on `persist` behind other writes. If any of those hangs (ExifTool, say), the app never quits. A second ⌘Q asks again and starts another wait, so the only way out is Force Quit. Fix suggestion: poll on the main actor, `let deadline = ContinuousClock.now + timeout; while task != nil, .now < deadline { try? await Task.sleep(for: .milliseconds(100)) }` (`task` is set to nil in the job task's `defer`). Or resume a continuation once from two unstructured tasks. | Code review C2; design §7.4 |
| C8 | Nit | `Merge/HDRMergeJob.swift:235-246` | `sameContentRefused` checks only `Catalog.insertMergedMaster`. The job's own handling has no test: it removes the file only while its inode matches, then throws `.sameContent`. Status says "By reading". After C1 this path is practically unreachable, so nothing fails today. | If a later change breaks the inode comparison (a `stat` that follows links, say, or an identity taken from the final name before linking), the refused file is either left beside the masters or removed when it shouldn't be, and no test notices. A test can catalogue a master with the merged file's content in another folder first, or give the job a `catalogue` closure that throws `sameContent`, then check that the file is gone. A second case can replace the file at `url` before the throw and check that the replacement stays. | Tests: every behavior has a test that fails without it |
| C9 | Nit | `Merge/LinearDNGWriter.swift:180` | Since C1, every merged DNG carries XMP (tag 700). It is written as UNDEFINED, with no `<?xpacket` wrapper. On the first pass most DNGs had no XMP and `exiftool -validate` said OK. | `exiftool -validate` on `RAW_102_HDR-3.dng`: "Non-standard format (undef) for IFD0 0x02bc ApplicationNotes" and "[minor] XMP is missing xpacket wrapper". The system decoder still reads the file (`dngRoundTrip`), so this is about strict readers only. Writing the tag as BYTE (type 1), as the TIFF/XMP convention and ExifTool expect, and wrapping the packet would clear both warnings. | — |

### Checked and fine (second pass)

- **Naming against placement.** The name is chosen from a directory listing
  and the catalog right before the write. The write goes to a fresh hidden
  name, and `link` refuses any existing target (exact name, dangling links,
  case variants), with up to three retries on a new free name. A file of the
  same stem with another extension that appears during the write is not seen
  (C3's residual race, accepted above). `MasterFiles.Names.containsStem`
  compares folded stems, as `contains` does.
- **The `renamex_np` call on APFS** gives EEXIST on a taken name or a case
  variant, so where it is supported it never replaces anything. The problem is
  only where it is not supported (C6).
- **Memory budget arithmetic.** In the sheet, the total is a `Double`, so it
  can't overflow. Frames with no catalog size count 0 and are caught by the
  job. In the job, `heldBytes` saturates at `Int.max` on overflow, each frame
  is checked against what is left before `held` allocates, and what is left
  never goes below zero. `frameMemoryBudget` clamps `physicalMemory / 2` to
  `Int`. The budget covers the held frames only. That is the stated policy:
  the TIFF and DNG are now banded, and the reduced copies are 2048 pixels.
- **Cancellation.** The TIFF provider returns no bytes once its task is
  cancelled, `Finalize` fails, then `checkCancellation` and `writeInPlace`'s
  `defer` remove the hidden file. The DNG checks between 512-row bands. Once
  the file is linked, the job finishes, and the catalog step is detached, as
  before.
- **Sidecar ownership.** Stems are now unique in the folder, so a merged
  master never shares `stem.xmp` with another master or an orphan sidecar.
  `sameContent` removal happens before any sidecar is written (the model
  writes sidecars only after success). Undo leaves the file and its sidecar,
  and the next merge numbers past both (`againAfterRemoval`).
- **Strings.** Four new keys with comments. Positional arguments in the
  two-argument string. No product name. `LocalizationTests` and
  `BrandingTests` pass. The wording is the designer's to confirm (status.md,
  Design questions).
- **`photocli merge`.** Online is decided by identity only. The output is as
  before. A same-content refusal maps to a failure with nothing left on disk.
- **The test helper `import zlib`** is the SDK's system module, not a package.
  No dependency is added.

### A merged DNG selected beside its own source raws

The engineer notes that a merged DNG passes every refusal as a frame. It is a
raw to the app, the same size, with the reference's metadata. The design
already ruled on this: RI-H4, D-H5c, "no detection in v1". I agree that this
branch needs no rule. Nothing is lost: masters are only read, the result is a
new file with its own name, and Undo takes it out. The worst outcome is a poor
merge, which the sheet makes visible by listing the frames by name (an
`_HDR` name among them).

If the owner wants detection later, the file already marks itself, with no
migration needed: a merged DNG is `PhotometricInterpretation` LinearRaw. A
merge could refuse a LinearRaw DNG beside mosaic raws as `mixedKinds`. That is
also principled for linear DNGs from other tools, which have been demosaiced
and often tone-processed, unlike mosaic raws. This is a follow-up for the
product manager, not a finding.

### Still open for the main session

- The #88 semantic conflict from the first pass (`maskRasters` in
  `removeMergedMaster` and `restoreMergedMaster`) still applies. `status.md`
  records it for whichever branch merges second.
- `/security-review`: this pass changes file placement (`writeInPlace`'s
  fallback), and C6's fix will change it again. A short re-run of
  `/security-review` on the C6 fix is worthwhile, limited to `writeInPlace`.
