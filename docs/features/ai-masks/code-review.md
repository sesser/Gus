# AI masks: code review

Owner: code-reviewer. Date: 2026-11-20. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/ai-masks`, `ed423d7..20311d9` (13 commits). Build and tests:
`swift build` clean; `swift test` 1,298 tests in 185 suites passed (88.8 s) on
this Mac (macOS 27.2.1). Not run: `AI_MASK_SAMPLES`, and CI on macOS 15 and 26.

## Verdict

No blockers. The storage, the strict reading, the render hash and the guided
filter hold up. The findings are in the app's landing logic: an Update matched
by index, a landing during the lens frame question, failure wording that takes
the wrong request, and a launch cleanup that can delete a row that was just
written. The AC11 test also depends on a false positive. Fix C1 to C5, or have
the owner rule on them, before QA.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/MaskDetectionEditing.swift:172`, `:285-299` | An Update stores the component *indices* it started on, and the landing applies results by index. Undo, Remove from Mask and the rest of editing stay live while a detection runs, so the indices can point at different components by the time the result lands. | Mask [People, Subject]. Remove People, so the mask is [Subject]. Choose Update Detection, which stores indices [0] and runs the foreground request. Press ⌘Z before the result lands, so the mask is back to [People, Subject]. At landing, index 0 is People and `results[.person]` is nil, so People gets a key in `failedUpdates` and its caption reads "Detection failed…" although it was never detected again. Subject is not updated, and the new row is orphaned. With a Linear shape in place of People, the Update does nothing and announces an empty caption. Match components by (kind, raster) captured at the start, or cancel the pending Update when the target mask's components change. | Correctness; R5 (Update writes the new digest), design §7 |
| C2 | Should fix | `MaskDetectionEditing.swift:258`, `:271`; `MaskEditing.swift:115-125`; `AdjustmentEditor.swift:695` | `changeMasks` returns `true` even when `change` drops the edit. `change` returns without doing anything while `isAskingLensFrame` is set. A landing is asynchronous, so it can arrive while the lens frame alert is up. | Choose Add to Mask ▸ Subject on a photo that has masks. Before the result lands, drag the Distortion Amount slider and let go: the frame question opens. The result then lands. `changeMasks` reports success while nothing was added, so `land()` sets `selectedMaskID` to a mask that is not in the stack, announces "Subject mask added. …", starts the overlay flash, and the result is lost. Separately, the input was rendered with the old Distortion, so a result that lands after the frame changes is in the old frame. Hold the landing until the question is answered (or drop it), and make `changeMasks` return `false` when `change` refuses. | Correctness; AC3 (one undo step when the result lands) |
| C3 | Should fix | `MaskDetectionEditing.swift:241-245`, `:316-325` | When an Update runs two requests (a mask with Subject and People), a failure is recorded against `pending.kind`, the kind of the first index, and not against the request that failed. | Mask [Subject, People]. Choose Update Detection; foreground succeeds and person throws `.unavailable`. The success loop removes `.foreground` from `unavailableRequests`, then the failure loop inserts `.foreground` again and never inserts `.person`. For the rest of the session, every digest-less Subject component on any photo shows "Detection isn't available on this Mac" in place of "Detection failed…". The Activity warning says "Couldn't detect a subject in X" when People failed. Iterate `results` with its keys and use the failed request for both. | Correctness; design §4, §6 |
| C4 | Should fix | `Sources/PhotoApp/Model/LibraryModel.swift:801`, `:1762-1775`; `MaskDetectionEditing.swift:239` vs `:258`; `Sources/PhotoCore/Commands/MaskCommands.swift:107-110` | The launch cleanup runs on a detached task in its own write transaction, not on the `persist` chain. A landing writes the row and the stack as two queue items, so the cleanup's transaction can run between them. | Open a photo in the loupe right after launch and add Subject while `removeUnreferencedMaskRasters` is waiting for or holding the writer (a full scan of `version` on a large library). The row is inserted, the cleanup sees it named by no stack or history entry and deletes it, and then the stack is saved naming it. In this session the in-memory store hides the loss. After the next launch, or once 48 newer results push it out of the store, the component shows Missing, and the result can only be detected again, possibly with different values (status.md §3, device dependence). The same gap exists between `photocli mask add`'s two transactions if the app launches between them. Low likelihood, one-line fix: enqueue the cleanup with `persist`, or delete only rows with `createdAt` before the cleanup started. | R5 (a row still referenced is kept), AC5 |
| C5 | Should fix | `Tests/PhotoCoreTests/MaskDetectionTests.swift:74-76` | AC11's size check passes only if the person request finds something in a red disc on blue or a plain gray field (`people >= 1`). That is a false positive of the model, and nothing promises it on macOS 15 or 26. The spike found People empty on every scene without a person except the flower close-up. | On a CI runner whose People model finds nothing in these fixtures, the test fails with "People found something in 0 of 4 fixtures" even though both requests ran and Vision works. That blocks the pull request (WORKFLOW step 7), independently of RI-E1. Check the sizes without depending on instances, for example from the observation's `instanceMask` label map if Vision returns an observation when it finds nothing (to be confirmed on 27.2). Otherwise ask the product manager to restate AC11 (Q1). | Tests are deterministic; AC11 |
| C6 | Nit | `Sources/PhotoCore/Suggestions/MaskDetector.swift:31`, `:67`, `:73` | `.unreadable`'s detail ("The photo could not be rendered for detection."), "Vision gave a mask in a format this build doesn't read." and "The mask could not be stored: …" are sentences written by the app, and they reach the Activity entry unlocalized. Design §14 leaves only *the system's* error text unlocalized. | An English sentence of the app's own under a localized warning in Activity. | Every UI string has a catalog entry |
| C7 | Nit | `MaskDetectionEditing.swift:196-208`; `MaskDetector.swift:125-131` | An Update with Subject and People renders the 2,560 px input once per request. The spike measured the render as most of a detection's cost (100 to 410 ms against 8 to 27 ms for the request). | Twice the wait for a two-request Update. | Performance |
| C8 | Nit | `MaskDetectionEditing.swift:201`, `MaskDetector.swift:44-51` | Cancel cancels the Swift task, but `MaskDetectionRun.run` checks only before and after the render, and the Vision request itself is never cancelled (`VNRequest.cancel()`). The detached work runs to its end, about 0.5 s, or 2 s on the first run after a build. Nothing is added (AC3 holds), but a detection started next shares the GPU with it. | A short overlap after Cancel. | R4 (cancellable) |

## Questions

- **Q1 (product manager, with RI-E1).** CI's macOS 15 and 26 runners are
  virtual machines with no Neural Engine and a paravirtualized GPU, and the
  foreground request refuses the CPU (`VNErrorUnsupportedComputeDevice`,
  status.md RI-E1). AC11 may therefore fail at the pull request because of
  where it runs, not because of the code. Rule on this now, not after a red
  run. Should AC11 accept a classified `.unavailable` (the request class exists
  and answers "can't run here") as a pass, with the error recorded, while
  `.failed` still fails? The test has to branch on the error itself:
  `Test.cancel` is not in Swift 6.2 on the macOS 15 job (see CLAUDE.md, GPU
  demosaic entry). I agree with the engineer's recommendation of yes. C5 is
  the second CI risk in the same test.
- **Migration numbering (main session).** v15 is free today. No other local
  branch or worktree registers it, and `feature/hdr-merge` (#150) plans no
  migration (its design.md §8.2, RI-H3). If any branch adds a migration before
  this one merges, the branch that merges second renames its migration before
  it ships, since nothing has shipped yet. After a merge, migration names never
  change.

## Checked and fine

- **Migration v15** (`CatalogSchema.addMaskRasters`) is new and last. No
  existing migration is edited. `MaskRasterCatalogTests.migration` migrates to
  v14, adds rows, then migrates to v15 and checks the data is unchanged.
  `editHistory.maskRasters` is nullable, null for older entries.
- **Rows are written once.** `INSERT OR IGNORE`, keyed by the SHA-256 of the
  PNG bytes. The only `UPDATE` is the debug script's `damageMaskRasterForChecks`.
- **Every history writer fills `maskRasters`.** `recordHistory` (all stack
  writes, in the same transaction) and the `RemovedCopy` restore. No other
  `INSERT INTO editHistory` exists.
- **The cleanup counts stacks this build can't read** (it scans text for
  `"raster":"<64 hex>"`, and stacks are canonical JSON with sorted keys and no
  whitespace) and history entries. Running only at launch is safe against
  undo, redo and history within a session (C4 is the one gap). Duplicate copies
  the reference and adds no row. Removal orphans rows until the next launch,
  as documented.
- **Strict reading.** Unknown keys, or a `raster` that is not 64 lowercase hex,
  make the stack unreadable. `kindVersion` stays 1, so develop's builds throw on
  the new shape names and never write over such a stack (checked against
  develop's `MaskShape.init` `default:` branch). `unreadableIsNotOverwritten`
  covers it.
- **Render hash and pipeline version.** The digest is a component parameter,
  so it is in the render hash (`renderHashFollowsTheDigest`). The shapes that
  already exist still return an alpha, so every existing mask combines exactly
  as before. Only a mask whose components are all detections without a result
  takes the new `contributingAlpha == nil` path, and it renders byte for byte
  as without the mask. No existing stack's render changes, so no bump is right.
  Three new goldens sit in their own commit (`ad7899c`); no existing golden or
  tolerance changed.
- **Guided filter.** The variance and covariance are never computed as
  E[I²] − E[I]². Per-row moments are taken about the row's mean in float, then
  combined exactly over equal-count rows (R7). The ROI callbacks match each
  pass's reach. Every kernel is in a Metal library of its own, as with the Lens
  kernels. If they don't compile, the result is stretched only and a log notice
  is written. The CPU reference is plain double-precision Swift, and its
  per-pixel tolerance is derived from half-float unit roundoff and propagated
  through the formulas, not tuned. The radius (one mask pixel, rounded up) and
  ε = 10⁻³ are pinned by tests. The 100% region renders crop a full-frame graph
  (`LiveRegionRenderer.render`), so the window's edges are the photo's, not the
  viewport's.
- **PNG read** (`MaskRaster.pixels`). It requires 8-bit gray with no alpha and
  at most 4,096 px a side. It checks the size before the pixels are decoded
  (`dataProvider.data` comes last in the guard) and checks the byte count
  against `bytesPerRow`. The row's width and height must match the PNG.
  `levels(of:)` reads only one-component formats with their own row stride.
- **Concurrency.** Detection runs on a detached task, is cancelled through a
  cancellation handler, and the landing checks the pending id and the version.
  `MaskRasterStore` reads the catalog with a blocking call, but only from the
  `LiveRenderSession` and `LiveRegionRenderer` actors, preview and export work,
  and `loadDetectionResults`' detached task. The main actor calls only
  `cached`. The store has no `@unchecked Sendable` or `nonisolated(unsafe)`;
  `Mutex` is available on macOS 15.
- **Every library renderer has the store.** That covers the app's generator
  (previews, live, region, preset hover, export) and `photocli render` and
  `export`. `photocli develop`'s Color Alignment measurement goes without it,
  which is fine, since it renders no masks.
- **Paste, presets and sync** carry no masks at all, so they carry no
  detections (`pasteAndPresetsOmitDetections`). Duplicate copies the reference.
  Each file of a pair has its own stack.
- **photocli.** `mask add --shape subject|people|background` refuses
  `--params`; `--dry-run` stores nothing; a missing original gives
  `fileNotFound`; the row is written before the stack. `mask list` reports each
  detection's state. Tests use the hermetic detector.
- **AC10.** No network API, no new package, and `Package.swift` is unchanged.
  `GenerateIterativeSegmentationRequest` is not referenced. The spike was added
  and deleted on this branch, so the net `Sources/PhotoBench` diff is empty.
- **UI rules.** The menu items read `LibraryMenuState` through focused values,
  the new controls are `AppKitMenuButton` and `AppKitButton`, and no SwiftUI
  `ScrollView` was added. The debug script's detection commands run under
  `adjust`, inside its undo group, and wait for the landing. Every new string
  has a catalog entry, with plural variants for the counts. No brand values.

## Security

The diff adds an ImageIO decode of blobs stored in the catalog
(`MaskRaster.pixels`), a hand-written text scanner (`MaskRasterReferences`)
and a reader of Vision pixel buffers. It adds no subprocess, no network code
and no file writing outside the library. The blobs are the library's own data,
but the PRD expects damaged or partly copied catalogs (R14), so run
`/security-review` on the branch, limited to those three.

## Follow-up

(Second pass: each finding with Fixed, Not fixed (and why) or Withdrawn, and the commit.)
