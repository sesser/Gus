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

## Third pass

Owner: code-reviewer. Date: 2026-11-20. Reviewed: `feature/hdr-merge`,
`8ad8f77..992ab25` (the reviewers' files `0872d69`, the fixes `992ab25`).
Build and tests: `swift build` clean; `swift test` 1307 tests in 188 suites
passed (235.9 s), with `fat32` running against a real image (it printed no
"not available" line). Also run here, with the built `photobench` and `photocli`:

- `photobench generate --brackets 1`, the three `RAW_10x` frames copied onto
  each volume, `photobench import` in place, then `photocli merge` on them as
  TIFF, TIFF again, then DNG:
  - On APFS (scratchpad folder), on a 200 MB FAT32 image and on a 200 MB exFAT
    image (`hdiutil create -fs`, both FSKit mounts, detached afterwards).
  - Every volume gave versions 4, 5 and 6: `RAW_102_HDR.tif`, `_HDR-2.tif` and
    `_HDR-3.dng`, with three different SHA-256 values. The masters' SHA-256
    values were unchanged (`shasum -c`).
  - No `.merge-*.partial` and no `._.merge-*` AppleDouble file was left. On
    FAT32 and exFAT each result has its `._` companion, as the masters do.
  - `exiftool -validate -warning -a` on each `_HDR-3.dng` printed `OK` and no
    warnings. Tag 0x02bc is `int8u` and starts with `<?xpacket begin=`, and
    the DNG still carries `xmpMM:DocumentID` and `xmp:CreateDate`.
- A C probe on APFS, FAT32 and exFAT, for the security questions below.

### Verdict

Ready for QA. C6 to C9 are fixed, and so are design review's F3 to F5. The C6
fallback never replaces a file that was there when it reserved the name, and it
leaves nothing behind on the paths it controls. One new nit (C10): the FAT32
test passes without running where `hdiutil` can't attach an image.

### Follow-up (C6 to C9)

| # | State | Commit | Note |
|---|---|---|---|
| C6 | Fixed | `992ab25` | When `renamex_np` gives ENOTSUP or EOPNOTSUPP, `renameOverPlaceholder` (`MergeOutput.swift:282`) reserves the name with `open(O_WRONLY\|O_CREAT\|O_EXCL)`. EEXIST there is `nameTaken`, which the job retries with a new free name, as before. It then `rename`s the hidden file over that placeholder. If the rename fails, the placeholder is removed only while `lstat` still finds the inode `fstat` gave at creation. Real merges work on FAT32 and exFAT (above). `linkFallback` drives the ENOTSUP-then-ENOTSUP path with stubs (placed, then `nameTaken` with the first file untouched). `fat32` runs the default calls on a real image (placed, never replaced, no `.partial`). `link` and the exclusive rename are injectable, and the stubs now return an errno instead of setting the global one. |
| C7 | Fixed | `992ab25` | `MainActorWait.whileTrue` polls on the main actor, so its deadline holds whatever the merge is doing. `MergeModel.waitUntilDone` asks whether `task` is still set, and the merge task's `defer` clears it on the main actor, which the wait lets run each time it sleeps. The injected-clock test pins the limit (returns false at exactly 10 s after 100 sleeps) and the early end (300 ms when the condition stops on its fourth check). It doesn't depend on load. `realClockReturns` checks the real clock path. The tests pin the helper, not `waitUntilDone`, which is now one line over it. Traced: Stop and Quit calls `terminate` no later than 10 s after it starts waiting. |
| C8 | Fixed | `992ab25` | `refusedFileRemoved` covers both halves. A `catalogue` that throws `sameContent` leaves the folder as it was. When another file replaces the merged file under its name first, that file survives with its own bytes. Without the identity check the second half fails, and without the removal the first half fails. |
| C9 | Fixed | `992ab25` | Tag 700 is BYTE, and `LinearDNGWriter.packet` wraps the XMP in an `xpacket` and leaves a packet that is already wrapped alone. `exiftool -validate` reports OK with no warnings (above), and `dngRoundTrip` passes. |
| F3 (design) | Fixed | `992ab25` | The literal, the catalog key and its `en` value all match the designer's text word for word. The `%@` and the comment are kept, and `LocalizationTests` passes. |
| F4, F5 (design) | Fixed | `992ab25` | The guide's refusal bullet adds the 150 MP limit and the memory limit, worded as the sheet words them ("too large to merge", select fewer). The F5 sentence sits at the end of that bullet rather than after the paragraph that says nothing links the photo to its sources. Where it goes is the designer's call. |

### Findings (third pass)

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C10 | Nit | `Tests/PhotoCoreTests/MergeSafetyTests.swift:225-238` | When `hdiutil` can't make or attach the image, `fat32` prints a line and passes. Swift Testing records it as passed, the same as a real run. | On a runner where `hdiutil attach` is refused (a sandboxed CI image, say), a change that broke the real FAT path again would stay green. Only the stubbed `linkFallback` would check the logic, and the C6 regression showed that stubs aren't enough. Suggestion: make the image in a trait (`.enabled(if:)` with a check that attaches and detaches once), so the result says "skipped", which works on Swift 6.2. Or keep it as it is and have QA read the line in the log. | Tests: deterministic, and a skip shows as one |

### Security re-check, limited to `writeInPlace` and placement

Probe results (APFS, FAT32 and exFAT all behaved the same unless noted):

- **Inode identity on FAT.** FSKit's msdos and exFAT give a file with content a
  stable number, and the number survives `rename`: the hidden file's number is
  the placed file's number, before and after other files in the folder are
  made and removed. Empty files get large synthetic numbers that are never
  reused (a removed empty file made again at the same name gets a new one), and
  an empty file's number is stable while it exists. So `placed()`, which reads
  from the name after placing, gives the job the merged file's real identity on
  every volume. The placeholder check after a failed rename can't match another
  process's file.
- **Symbolic link at the name.** FAT32 and exFAT accept `symlink(2)` here, and
  on all three file systems `open(O_CREAT|O_EXCL)` on a link gives EEXIST, even
  for a dangling link. The result is `nameTaken`, nothing is followed, and the
  job retries with a new name. A link put there after the reservation is
  replaced as a link by `rename` (never followed). A directory put there makes
  `rename` fail with EISDIR, and the placeholder check then leaves the
  directory alone.
- **Race between the reservation and the rename.** This window stays open: if
  another process removes the empty placeholder and puts its own file at that
  name in the microseconds between `open` and `rename`, `rename` replaces that
  file (shown by the probe on all three file systems). Only a process that
  deletes a file it didn't make can do this, and such a process could delete
  masters anyway. FAT32 and exFAT give no exclusive rename to close it. A check
  of the placeholder's identity just before `rename` would narrow the window
  but not close it. **Accepted residual**, not a finding.
- **Crash or kill between the reservation and the rename.** That would leave a
  0-byte file at the result's name and the complete `.merge-<UUID>.partial`.
  The window is a few system calls with no cancellation check, so Stop can't
  land there. The next merge numbers past the empty file, since its stem is
  taken. This is the same class as L6 (no sweep for old partial files, accepted
  in the second pass). **Accepted residual.**
- **Permissions.** The placeholder is made `0644` (then the umask; FAT shows
  `0700`, synthetic on `noowners` mounts) and is replaced by the rename, so the
  result keeps the hidden file's mode, as on APFS. Nothing is world-writable.
- **Cleanup of `.merge-<UUID>.partial`.** The `defer` removes the hidden name
  on every path: after `link` it is the second name of the placed file, so only
  that name goes. After a rename it no longer exists, so the removal is a no-op
  (`try?`). On failure or cancellation it is the whole file. On FAT32,
  unlinking a file also removes its `._` companion (checked), and after the
  three merges no `._.merge-*` file was left. The name is a fresh UUID in the
  same folder, so it never collides.
- **Identity read after `link` on APFS.** `placed()` now reads the identity
  from the result's name, not from the hidden file. After a successful `link`
  both names are the same inode. If another process replaced the result in the
  microseconds before the `lstat`, the job would hold that file's identity, and
  only the `sameContent` refusal (practically unreachable since C1) acts on it.
  This is negligible and the same class as above.

No new parser, subprocess (the test's `hdiutil` is a fixed argument array in
the test target only) or network code. I see no need for another
`/security-review` run beyond this check.

### Still open for the main session

- The #88 `maskRasters` heads-up (first pass) still applies to whichever branch
  merges second.
- Where F5's sentence goes in the guide is the designer's to confirm.

## Fourth pass

Owner: code-reviewer. Date: 2026-11-20. Reviewed: `feature/hdr-merge`,
`d3545ad..bb2ab53` (QA's file `046a93f`, the fixes `bb2ab53`); also `d3545ad`
itself for C10's follow-up. Build and tests: `swift build` clean; `swift test`
1307 tests in 189 suites passed (258.9 s; the 189th is the new `MemoryHeavy`
parent), with `fat32` running against a real image. `swift test --filter`
with `ImportHashMemoryTests`, `HDRMergerTests`, `MergeSafetyTests` and
`HDRMergeJobTests/mergesToTIFF|HDRMergeJobTests/mergesToDNG` all select and
pass their tests. Also run here: ImageIO and exiftool probes of the dates Q4
writes (below). The app was not launched (that is QA's).

### Verdict

Ready for QA's rerun. Q1's deadlock is fixed: the Redo's `show` now waits for
the Redo's own write instead of being part of it, and no other merge path reads
through the chain from inside a write. Q2 to Q5 are fixed or recorded as asked.
Two new nits, neither blocking: a blank EXIF time offset ends up in the DNG's
`xmp:CreateDate` (C11), and the primitive the Q1 fix rests on could be pinned
by a PhotoCore test (C12).

### Follow-up (C10, Q1 to Q5)

| # | State | Commit | Note |
|---|---|---|---|
| C10 | Fixed | `d3545ad` | `fat32` carries `.enabled(if: canAttachFAT32, …)`. The probe makes and attaches an image once (a lazy `static let`), so where `hdiutil` can't, the result reads "skipped". Where the probe works and the test's own image doesn't, `#expect(ran)` fails. Inside `extension MemoryHeavy` the trait's `MergeSafetyTests` resolves to the nested type, and the test ran in this pass. |
| Q1 | Fixed | `bb2ab53` | Traced in "Q1 traced" below. |
| Q2 | Fixed | `bb2ab53` | `quit` sets `showsMergeSheet = false` beside the other three sheets. Its `didSet` calls `merge.sheetClosed()`, which cancels the sheet's reads. A merge already running is not this command's business: QA's script has no merge running at `quit`. |
| Q3 | Fixed | `bb2ab53` | Traced in "Q3 checked" below. |
| Q4 | Fixed, one nit (C11) | `bb2ab53` | Traced in "Q4 checked" below. |
| Q5 | Fixed (docs) | `bb2ab53` | `PROFILING.md`'s HDR merge section says a debug build takes about 35 s to measure three 1536 x 1024 frames, why (per-pixel Swift loops the optimizer makes fast), that the Accelerate sort was tried and not kept, and to time `swift run -c release photocli merge`. `photobench merge` exists (`PhotoBench/main.swift:167`). Matches `status.md`. |

### Q1 traced

- **The fix.** `registerUndo`'s Redo branch (`MergeModel.swift:354-361`) runs
  inside `model.persist`, that is, as a `WriteChain.enqueue` task T. After
  `restoreMergedMaster` returns true, it calls
  `model.writes.afterPendingWrites { show }`. `afterPendingWrites`
  (`WriteChain.swift:41`) captures `tail` at the call and starts its own
  unstructured task, which awaits that tail and then runs the body.
- **It can't run before the write ends.** While T runs, `tail` is T or a write
  queued after it. `tail` only ever moves forward and is never cleared, so the
  captured task is T or later, and awaiting it waits for all of T. That
  includes what `persist` does after `work` (`scheduleSidecarSync`). T doesn't
  await the new task, so nothing waits on itself. `show`'s `writes.read` then
  calls `settled()`, which awaits the current tail: T is finished by then, or a
  later write that finishes on its own.
- **It isn't skipped.** The task awaits a `Task<Void, Never>` and has no
  cancellation path. It is not scheduled on failure, which is right. If
  `restoreMergedMaster` throws, `persist` reports "Could not save the change",
  and there is nothing to show. If it returns false, the branch reports
  `notAddedBack`, as before.
- **Ordering with other writes.** A rating made right after Redo (W2) is queued
  after T. `show` may capture T or W2, but `read` settles past every write
  queued before it fetches, and refetches if one is queued while it reads, so
  its list includes W2. Undo right after Redo (W3) runs `hide` inside W3.
  `show`'s `read` settles past W3 too, so it fetches the list without the
  photo, and its `apply` keeps the selection (`MergeLanding.selects` is false
  when the photo isn't shown). The screen ends consistent with the catalog
  whichever finishes last.
- **No other self-wait in the merge.**
  - Undo calls `hide` inside the write. `hide` calls `replaceItems`, which is
    synchronous, and then `refreshProjects` and `refreshKeywords`. Those read
    the catalog directly, not through `writes.read`, and start their follow-on
    refreshes (`scheduleSidebarRefresh`, `refreshProjectFolders`) as separate
    tasks.
  - The catalogue step (`onWriteChain`) only runs `insert` and resumes a
    continuation. `finished`, and the landing `show` inside it, run on the
    merge's own task after that continuation resumes, never inline in the
    chain's task. Its `read` then waits for the catalogue write, which ends
    right after the resume.
  - The sidecar step only calls `writeSidecars`.
  - `DebugMergeCommands` uses `afterPendingWrites` from outside the chain.
  - `writes.read` appears in exactly one place in the branch's app code
    (`show`), and its doc comment now says never to call it from a write.
- **Test.** Only QA's debug script covers the app-level path. `MergeModel` is
  in the app target, which `swift test` can't load, so no unit test can catch
  that call moving back inside the write. The primitive the fix relies on can
  be tested, though: see C12. The proposed follow-up in `status.md` (`read`
  refusing, or reading without waiting, when called from the chain's own tail)
  is the structural guard. A task-local set while a chain task runs would
  detect it. I agree it should be an issue.

### Q3 checked

- **Whitespace ignored, the diff is wrappers only.** Each of the five files
  wraps its suites in `extension MemoryHeavy { … }`, and `extension
  HDRMergerTests` became `extension MemoryHeavy.HDRMergerTests`. The only other
  changes are Q4's assertions and `dates(_:)`.
- **Nothing lost or disabled.** `@Test` counts per file are the same before and
  after: 24, 5, 5, 1 and 9. No test title, function name or `.serialized`
  trait changed. The only condition trait is C10's. The full run's 1307 tests
  match the third pass's count.
- **`.serialized` reaches nested suites.** It is recursive in Swift Testing, so
  the merge suites and `ImportHashMemoryTests` never overlap each other. That
  is what QA saw fail.
  - `MergeRuleTests`, `ProgressLog` and `MergeLibrary` stay at top level, as
    before. They are light.
  - **Residual, not a finding:** suites outside `MemoryHeavy` (goldens,
    demosaic, color alignment) still run beside `ImportHashMemoryTests`. That
    was true before this branch.
  - **Cost:** the suite takes about 20 s longer here (258.9 s against 235.9 s
    in the third pass).
- **Filters.** Test IDs now read `PhotoCoreTests.MemoryHeavy/HDRMergeJobTests/…`.
  `--filter` matches by regular expression, so the suite names alone still
  work (checked above). `CLAUDE.md` names none of these suites in a filter, so
  nothing there changes.

### Q4 checked

- **`Metadata.created` is gone.** The build would fail on any caller left. The
  XMP's `xmp:CreateDate` is `xmpCaptureDate`: the reference's EXIF
  `DateTimeOriginal`, rewritten as `YYYY-MM-DDTHH:MM:SS`, plus
  `OffsetTimeOriginal` when there is one. With no capture date, nothing is
  written.
- **TIFF.** ImageIO turns the XMP CreateDate into EXIF `DateTimeDigitized` and
  the IPTC digital creation date, and doesn't keep it in the XMP. Probe:
  `xmp:CreateDate` `2016-05-21T08:43:02+02:00` gave `ExifIFD:CreateDate`
  `2016:05:21 08:43:02` and IPTC `DigitalCreationTime` `08:43:02+02:00`. The
  TIFF dictionary keeps the reference's own `DateTime` (`ExportMetadata`'s kept
  keys): the reference's date, not the merge's.
- **DNG.** `LinearDNGWriter` writes `DateTimeOriginal`, `DateTimeDigitized` and
  `OffsetTimeOriginal` from the reference. Its tag 700 carries the same XMP,
  CreateDate included.
- **Read back.** `mergesToTIFF` and `mergesToDNG` read both EXIF dates and the
  XMP CreateDate back as the fixture's capture date. The fixture has no time
  offset, so the offset branch has no test (see C11).
- **Uniqueness.** `documentID` defaults to `UUID()` for each `Metadata`, and
  `DocumentID` and `InstanceID` are both written. `mergesToTIFF` still checks
  that two merges of the same frames give different SHA-256 values with the
  same pixels. The DNG embeds the same XMP, so it differs the same way.
- **Catalog.** The merged photo's capture date comes from reading the written
  file (`newMaster`), so it is the reference's. A reference with no
  `DateTimeOriginal` gives a file with none, as before.

### Findings (fourth pass)

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C11 | Nit | `Sources/PhotoCore/Merge/MergeOutput.swift:59-67` | `xmpCaptureDate` appends `OffsetTimeOriginal` exactly as read. EXIF 2.31 writes an unknown offset as blanks with the colon (`"   :  "`), and ImageIO hands that back verbatim. Probe: a JPEG given that value by exiftool reads `[   :  ]` through `CGImageSourceCopyPropertiesAtIndex`. | For a reference with a blank offset, the XMP gets `xmp:CreateDate` `2016-05-21T08:43:02   :  `. In the DNG that packet is stored as is: exiftool reports "[minor] Invalid date/time format for XMP:CreateDate", and a reader that prefers XMP dates may drop the date. In the TIFF, ImageIO converts it, and the only trace is a minor exiftool warning on IPTC `DigitalCreationTime`. The EXIF dates and the catalog are right in both formats. Suggestion: append the offset only when it matches `[+-]HH:MM` (or `Z`), and add a fixture case with an offset to `mergesToDNG`. | Correctness (dates written to outside files) |
| C12 | Nit | `Tests/PhotoCoreTests/WriteChainTests.swift` | Q1's fix rests on `afterPendingWrites`, called from inside a running write, waiting for that write and then letting `read` complete. No test pins that, and it is cheap with the suite's `Latch` and `Store`: enqueue a write held by a gate that calls `chain.afterPendingWrites { try await chain.read { … } apply: { … } }`, queue a second write, open the gate, and expect the read to have run after both, with their effects. | If `afterPendingWrites` were changed to wait only on writes queued before it was registered (which, from inside a write, is the write itself), or `read` to special-case the tail, Q1's Redo would hang again, and nothing in `swift test` would fail. The test would not catch `show` moving back inside the write in `MergeModel` (app target). Only QA's script 11 or the proposed `read`-refuses guard can catch that. | Tests |

### Still open for the main session

- The #88 `maskRasters` heads-up (first pass) still applies to whichever branch
  merges second.
- Where F5's sentence goes in the guide is still the designer's to confirm.
- The follow-up `status.md` proposes (`WriteChain.read` from its own tail
  should fail fast rather than hang) is worth filing.
- No `/security-review` is needed for this pass. It adds no parser, subprocess,
  file placement or network code: the date change only formats values already
  read from the reference.

## Fifth pass (short)

Owner: code-reviewer. Date: 2026-11-20. Reviewed: `feature/hdr-merge`,
`bb2ab53..d635e12` (one commit: C11 and C12). Build and tests: `swift build`
clean; `swift test` 1309 tests in 189 suites passed (262.2 s), the FAT32 test
(C6) and both new tests included. Also run here: `exiftool -validate` on XMP
packets carrying the edge-case dates below.

### Verdict

Ready for QA's rerun. C11 and C12 are fixed. One new nit (C13), not blocking:
the offset check tests the shape, not the range, so an out-of-range offset from a
damaged file still reaches `xmp:CreateDate`.

### Follow-up (C11, C12)

| # | State | Commit | Note |
|---|---|---|---|
| C11 | Fixed, one nit (C13) | `d635e12` | `xmpCaptureDate` appends `OffsetTimeOriginal` only when `isTimeOffset` accepts it: exactly `Z`, or six characters `[+-]DD:DD` with ASCII digits (`isASCII && isNumber`, so full-width or other Unicode digits are refused). The edge cases: `+5:30` (5 characters), lowercase `z`, `+02:00 ` with a trailing space, the blank `   :  ` and an empty string are all refused, and the date is written without an offset. That date is valid XMP: W3C-DTF allows a local time with no zone, and exiftool `-validate` gives `2016-05-21T08:43:02` OK. Losing the offset in those cases is right. EXIF 2.31 writes `±HH:MM` only, never `Z` or `z`, and ImageIO drops the terminating NUL, so no well-formed camera value is lost. `+24:00` is accepted: see C13. `MergeSafetyTests.captureDateOffset` covers `+02:00`, `-05:30`, `Z`, the blank offset, `+2:00`, no offset and no date. A unit test on `xmpCaptureDate` instead of a fixture case in `mergesToDNG` is fine: `writeXMP` (`MergeOutput.swift:479`) writes the string as it is, and `status.md` records an exiftool check of real merged DNGs and TIFFs with all three kinds of offset. |
| C12 | Fixed | `d635e12` | `afterPendingWritesFromInsideAWrite` traced. W1 runs, calls `afterPendingWrites` (body A waits on the tail, which is the held write W3, queued before W1 ran), queues W5 (savedRating 9), then appends 2. A cannot start before the gate opens, so `!contains(4)` holds deterministically. Once the gate opens, W3 sets 7 and appends 3. A and W5 both wait on W3 and may resume in either order, but A's `read` goes through `settled()`, which waits for W5, so `read == 9` either way. The prefix `[1, 2, 3]` holds either way. Mutations it catches: an `afterPendingWrites` that does not wait fails the order checks. One that becomes a write itself (`enqueue`) deadlocks the inner `read` (it waits for its own task), and the test hangs, as Q1's Redo did. The suite uses no `.timeLimit`, so a hang is its failure, the same as the rest of the repository. As said in the fourth pass, nothing in `swift test` can catch `show` moving back inside the write in `MergeModel`. |

### Findings (fifth pass)

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C13 | Nit | `Sources/PhotoCore/Merge/MergeOutput.swift:73-80` | `isTimeOffset` checks the form `[+-]DD:DD` but not the range of the hours and minutes. | A reference whose `OffsetTimeOriginal` reads `+24:00`, `+15:00` or `+99:99` (a damaged or hand-edited file: cameras write offsets from -12:00 to +14:00) gets `xmp:CreateDate` `2016-05-21T08:43:02+24:00`. exiftool `-validate` reports "[minor] TZhr out of range for XMP:CreateDate" (for `+99:99`, "TZhr+TZmin out of range"); `+14:00` and `-12:00` validate OK. The EXIF dates and the catalog are unaffected. Same family as C11, much rarer. A related case outside C11: `DateTimeOriginal` itself is reshaped but not checked, so a camera with an unset clock that writes `0000:00:00 00:00:00` gives `0000-00-00T00:00:00` ("Month+Day out of range"). That copies what the reference already says in its EXIF. Suggestion, optional: accept hours up to 14 and minutes up to 59, or close this as accepted. | Correctness (dates written to outside files) |

### Still open for the main session

- Unchanged from the fourth pass: the #88 `maskRasters` heads-up, F5's place in
  the guide (designer), and filing the `WriteChain.read`-from-its-own-tail
  follow-up.
- No `/security-review` is needed for this pass: no parser, subprocess, file
  placement or network code changed.

## Sixth pass: the sheet revision

Owner: code-reviewer. Date: 2026-11-21. Reviewed: `feature/hdr-merge`,
`a787feb..d9b1461` (`be5bf92` engine, `498dc9f` reference and `photocli`,
`51c4297` sheet, `d9b1461` Name line, debug script, guide, status), against the
PRD as revised 2026-11-21 and design §20 (D-H6 to D-H10). `079bf79` (the Core
Image fix moving to bug #253) is not reviewed here. Build and tests: `swift
build` clean on `d9b1461`; full `swift test` 1340 tests in 193 suites, 1339
passed and 1 failed (512.2 s). The failure is `079bf79`'s `ImageIOFullDecodeTests`
"An EXIF orientation is still applied to the full-size decode" (bytes differ
under the full run's load). It passed 3 times out of 3 run alone, so it is
flaky, and it belongs to bug #253, not to this range. Every test this range adds
or changes passed. Also run here: two throwaway probes of the de-ghost rule, in
a clone of the worktree in the scratchpad (since deleted). Each compared the
masks of the rule before `be5bf92` and after it on still brackets, and how far
each merge's light is from the same plan with no masks:

- **Probe 1.** No movement, alignment off, ±1 and ±2 EV, each frame as the
  reference. The frames were linear, linear with noise σ 0.002, or given a
  camera-like toe `L·L/(L+c)` (c 0.005 or 0.01, with and without that noise).
- **Probe 2.** The hand-held ±1 and ±2 EV brackets of `alignmentFollowsTheReference`,
  aligned, linear.

The app was not launched (QA's job). Note for the main session: while this pass
ran, uncommitted changes appeared in the worktree (`MergeSheet.swift`,
`MergeModel.swift`, `MergeSelection.swift`, `MergeSelectionTests.swift`, the
String Catalog, `design.md`, `review.md`), timestamped after the full test run
ended. This pass covers `d9b1461` as committed.

### Verdict

Ready for QA once C14 is decided. The reference choice, the two boxes, the
align-off and de-ghost-off paths, `photocli`'s three choices, the sheet state
and the progress rescale are correct and tested. One should-fix (C14): the
de-ghost change that every merge gets is exact on linear frames. On frames
whose response bends near black (a JPEG bracket's camera curve) with the
brightest frame as the reference, it clips a band along the bright window that
the old rule left alone. Two nits: C15 (the CPU reference's bound changed in a
code commit; it is justified) and C16 (the slow-disk spinner across reference
changes).

### Findings (sixth pass)

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C14 | Should fix | `Sources/PhotoCore/Merge/MergeGhosts.swift:106-125` | The new one-sided tests treat a black frame's values as an upper bound on the light and a clipped frame's as a lower bound. That holds only when the values are proportional to the light. `status.md` says "on a still scene neither test can fire". That is true for raws, but not for a JPEG bracket (R8 allows them; the PRD leaves response-curve recovery to a follow-up), whose camera curve crushes the toe below proportional. The black-frame branch (`frame.high / exposure * 1.5 < reference.low`) then fires across a still wall. The 3 x 3 cleaning, the growth and the feather carry the mask into the window, where the dark frame is the only unclipped one. There the merge falls back on the reference's floor weight, so it takes the reference's clipped pixels. | Probe 1, still scene, toe c = 0.01, ±2 EV, the +2 EV frame as reference (the PRD's own scenario of choosing the bright frame): the −2 EV frame's mask covers 147,051 of 240,000 pixels (old rule: 0). 1,836 pixels move by more than 1% against the plan with no masks, 366 of them in the window, worst 95% (old rule: 0). With c = 0.005: 131,204 mask pixels and 317 moved, 198 in the window, worst 93%. In light terms this is a clipped band along the window's edge, about the mask growth wide (2 px at 600 px; `growRadius` is 8 on a 2048-pixel copy, about 23 px on a 6000-pixel frame). With the default reference the same toe gives 5,512 mask pixels but only 5 moved pixels, worst 1.3%, so the defaults are barely touched. Linear frames, with or without noise σ 0.002, and every hand-held linear case in probe 2 give the same masks under both rules, to the pixel, except two hand-held ±1 EV cases (81 more mask pixels each; moved pixels 26 against 28, and 86 against 85). With noise σ 0.002 the toe case shows no difference either, so how often real JPEGs trip it is open. Nothing checks this today: every de-ghost test uses linear fixture frames. Suggestions (the engineer's choice): add a still-bracket test with a nonlinear response (a toe like the probe's, extreme reference) that requires no mask, or no moved pixel, in the window. Then narrow the black-frame test, for example by comparing the reference against what the frame's black threshold can hide (`reference.low > lowF / exposure * 1.5`, the form the reference-black branch already uses with `lowR`) rather than against the frame's own crushed values, and check the clipped-frame branch the same way against a shoulder. Or keep the one-sided masks out of pixels where the masked frame is the only unclipped one. Whatever is chosen, A13's answer in `status.md` should say what holds for non-linear frames, and M12/M13 should include a JPEG bracket with the brightest frame as reference. | PRD A13, R8, R10, AC8; correctness |
| C15 | Nit (recorded, no change asked) | `Tests/PhotoCoreTests/Reference/MergeReference.swift:84-89`, in `be5bf92` with engine code | The CPU reference's per-pixel bound changed in the same commit as the engine change. That is the pattern the review rules flag ("a loosened tolerance … in the same commit as a code change"). I checked it. It is a correction, not a loosening to hide an error. The bilinear mix of channel c moves with the sample position by at most that channel's spread over the four taps. The old bound used the spread of each tap's brightest channel, which bounds only the brightest channel (a red edge under an even blue escapes it). The new bound is the derived one, `max(spread, peaks…)` reduces to the per-channel spread (max is 1-Lipschitz), and since the allowance is divided by the pixel's brightest value and then applied to each channel's own value, it stays conservative for the smaller channels. Measured: AC8a's worst pixel is 0.31 of its tolerance, AC10's 0.37 (was 0.61). `status.md` records the probe of the failing pixel and the two tries not kept. No golden moved. Next time, a separate commit with a one-line reason. | CLAUDE.md "Checking image code" (tolerances changed only on purpose) |
| C16 | Nit | `Sources/PhotoApp/Model/MergeModel.swift:216-232` (`startSlowTimer`, `diskAnswered`) | The spinner state is shared across references, but only cleared when the current reference's disk answers are in. A change of reference doesn't re-decide it, and a timer that has fired stays in `slowTask`, so `startSlowTimer`'s `slowTask == nil` guard blocks the next one. | Traced with three folders. (A) The reference moves to slow folder B, the spinner shows at 0.5 s, then the reference moves back to a folder already answered writable: Merge turns on and the spinner keeps spinning beside it until B answers, forever on a hung volume. (B) The reference moves to slow B, then within 0.5 s to answered folder C (the timer fires, finds C answered, sets nothing, stays in `slowTask`), then to another slow folder D: no timer starts, and D's check runs with Merge off and no spinner (design §5.8: "the small spinner … appears only after about half a second", applied again on each change). Suggestion: set `slowTask = nil` when it fires, and re-decide `isCheckingSlowly` (false when `isDiskChecked`) in `chooseReference`. `merge slowdisk` can show both. | Design §5.4, §5.8 |

### Checked and fine (sixth pass)

- **Align off.** `plan` makes no Vision request, the homographies are
  `.identity`, the copies are used as they are (not warped), no `misaligned` is
  thrown, and the `aligned` callback is never called. `withoutAlignment` checks
  the kernels against the CPU reference with identity movements (worst 0.03),
  and `unrelatedWithoutAlignment` and the job and `photocli` tests merge an
  unrelated frame. The other refusals still apply with both boxes off
  (`refusalsWithoutAlignment`: size, offline, video, read-only before any
  read).
- **De-ghost off.** The masks are empty `MergePlane`s of the copy's size and the
  rest of the plan is identical (`plain.frames == checked.frames`). The
  reference's floor weight stays, so the reference decides only pixels where no
  other frame has weight, which R10 allows. Against de-ghost on, the result
  differs by 0.0 where nothing moved.
- **The de-ghost change on linear frames.** It is deterministic (plain CPU
  loops, no randomness). With the default reference on the walker it is exact,
  and it matches the old rule to the pixel on every linear still bracket I
  probed with no movement. On the hand-held ±1 EV bracket it masks 81 more
  pixels, with moved pixels 26 against 28 and 86 against 85. The extreme-reference record (`extremeReferences`)
  printed `elsewhere 0.0` for both ±2 EV extremes in this run, although the test
  doesn't assert it. Merges are new files, so no cached or stored render
  changes, and `currentPipelineVersion` correctly stays 13. `status.md`
  documents the change and its table. The gap is only C14.
- **Pre-existing, not this pass's.** Probe 2 also shows the default reference
  of a hand-held ±2 EV still bracket moving 40 pixels by over 1% (6 in the
  window) through masks at edges where a fraction of a pixel of alignment error
  remains. The old and new rules give identical numbers. This is what the
  comment in `alignmentFollowsTheReference` refers to. It is worth an eye in
  M12/M13, not a finding against this range.
- **Progress without alignment.** `Schedule(aligns: false)` scales the
  remaining shares by 1/0.7. The measuring that remains reports as Merging,
  starting at the reading share, so the bar never goes back
  (`unrelatedMergesWithoutAlignment`: monotonic, ends at 1, no `.aligning`;
  `MergeProgressScheduleTests`). With alignment on the values equal the old
  constants.
- **The reference in the job and `photocli`.** `MergeSelection.choosingReference`
  returns nil for a version that isn't a frame. The sheet ignores it
  (`chooseReference`), and `photocli` throws `invalidValue` before
  `job.run`, so nothing is read or written (checked in code and by
  `referenceAndSwitches`). A pair's JPEG given as `--reference` resolves to its
  raw, as the frames do. The job's own preflight repeats case 8 and case 9 for
  the chosen reference, so a folder that turned read-only after the sheet's
  check is still refused before any read (`readOnlyFollowsTheReference`).
- **Sheet races.** Everything runs on `MergeModel`'s main actor. The disk is
  asked in `Task.detached`, and answers come back to the main actor.
  `MergeSheetState` keys folder answers by standardized path, asks each folder
  once, keeps an answer that arrives for a superseded reference as a fact about
  its folder, and lets it decide nothing on screen. Merge stays off until the
  current reference's folder is answered. Name answers are keyed by reference
  and format, so a late one is ignored, and each change cancels the previous
  name task. The preview ignores a thumbnail for a superseded reference.
  Closing or reopening cancels every sheet task and makes a new state (AC3c,
  AC9a). A detached folder check on a hung volume isn't cancelled by that, but
  its answer is dropped and it holds nothing. `folderAskedOnce`, `nameFollows`
  and `folderRefusalFollows` pin the rules. The view's `@State` row is put back
  when the table clears or the model refuses a row, which the debug script
  showed holding.
- **An empty frame list.** `begin` now closes the sheet instead of building a
  state with no frames, which would have indexed `frames[defaultReference]`.
- **Different sizes.** Named from the chosen reference, every other-size frame
  flagged (`sizeRefusalFollows`), as design §6.1 case 6 and §6.4 say.
- **`photocli merge`.** Three new parameters through the registry
  (`--reference`, `--no-align`, `--no-deghost`). The JSON gains `align` and
  `deghost` and is otherwise unchanged, and the misaligned failure names
  `--no-align` (D-H10). The summary and `USER_GUIDE.md` describe them. The
  command is still `.write` (library lock).
- **Strings.** Six keys added, three replaced, the old three removed. Each has
  a comment. "Reference %@. Result %@." uses positional arguments. There is no
  product name, the texts match design §20 word for word, and
  `LocalizationTests` and `BrandingTests` passed in the full run.
- **Swift 6.2 and CI.** Checked by reading only; Xcode 26.3 isn't on this Mac.
  `Table(_:selection:)`, `.onChange(of:initial:)`, `.toggleStyle(.checkbox)`
  and `Task.sleep(for:)` are all from macOS 14 or earlier. There is no
  `Test.cancel`, `@concurrent`, `nonisolated` or macOS 27 symbol. The one new
  `@unchecked Sendable` is the test-only `PhaseLog`, lock-guarded, with its
  reason written.
- **Persisted names and dependencies.** No preference for the reference or
  the boxes (Format keeps `merge.format`). No migration, no new package.
- **Debug script.** `merge reference`, `align`, `deghost`, `slowdisk` and
  `table` change sheet state only, never photos, so they need no undo group.
  `merge start` is as before.
- **Fixtures.** `photobench generate --brackets` adds `TwoFolders-n` (`Locked`
  made 0555 in the generated scratch folder only). `radianceImage(as:)`
  defaults to the old behavior.

### Still open for the main session

- C14 is for the engineer. Whether a JPEG bracket's de-ghost may trade halos
  for ghosts with an extreme reference is also A13's question for the product
  manager if the engineer can't make both hold.
- `079bf79`'s `ImageIOFullDecodeTests` orientation test flaked once in the full
  run (passed 3 of 3 alone). That is for bug #253's branch.
- Unchanged: the #88 `maskRasters` heads-up, F5's place in the guide
  (designer), and filing the `WriteChain.read`-from-its-own-tail follow-up.
- No `/security-review` is needed for this pass. It adds no parser,
  subprocess or network code, and placement is unchanged. The result still
  goes beside the reference, now any frame of the series, whose folder comes
  from the catalog and passes `isPlainPlace`. `--reference` is an integer
  checked against the series before anything is read.
