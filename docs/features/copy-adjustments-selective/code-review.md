# Copy Adjustments, choose what to copy: code review

Owner: code-reviewer. Date: 2026-11-22. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/copy-adjustments-selective`, 42319c8..890588c (5 commits;
27 files, +2729/−115). Build and tests: `swift build --build-tests` clean;
`swift test` 1449 tests in 206 suites passed (79 s), on this Mac, macOS 27.2.

## Verdict

Close, but not ready yet. The core (`CopyItem`, `CopySheetState`,
`CopiedAdjustments`, `SpotPastePlan`) is correct and well tested, and R5 holds
(masks, stored decode, unknown operations and unreadable stacks are untouched).
One Should fix remains: the lens frame question (R7) counts spots that the
paste itself brings, so copying Spots with a Lens group asks about photos that
have no spots or masks, or ones that won't get the spots at all. The rest are
nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/CopyAdjustmentsActions.swift:125`; `LensCorrectionActions.swift:101`, `:286–288`, comment `:308` | The frame question is given `copied.pasted(onto:)` with `pastingSpots` at its default `true`. `frameCandidates` and `asksLensFrameQuestion` count `max(before, after)` masks and spots, so the spots the paste brings count as the target's own. The comment at `:308` ("a paste never brings any") is no longer true. | A has 2 spots and Distortion Manual 10. Copy Spots and Distortion, then paste onto B, which has no masks or spots and Distortion off. Trace: `after.spots.count` is 2, so B becomes a candidate. `movesFrame` is `warp != other.warp`, which is true, so the alert asks about "1 of 1" photo. B had nothing to move, and the pasted spots arrive with the source's matching Distortion. The same happens with a B of another size, which keeps no spots at all (R8) and still counts as affected. In a batch, the "‹n› of ‹m›" count is too high. Copy Distortion without Spots and nothing is asked, which is correct. | PRD R7 ("a target that has spots or masks"); design §5.2. Suggested fix: test the question against `copied.pasted(onto: $0, pastingSpots: false)`. The warp change is the same, and only the target's own masks and spots count. Then update the `:308` comment. |
| C2 | Nit | `Sources/PhotoCore/Preview/PreviewGenerator.swift:182–203`; `status.md` "reads headers only" | `maskFrameSize(of:)` says "Read from the file's header; nothing is decoded". For an Olympus, OM System or Panasonic raw with a camera crop, `CameraFrame.fullFrameFilter` calls `fullFrameData`, which reads the whole file into memory (`Data(contentsOf:)`, `CameraFrame.swift:182`). Four of these run at a time in `pasteMeasuringSpotFrames`. | A Spots paste onto 200 RW2 files reads about 200 × 20 MB from disk, with up to about 80 MB held at once, where the comment and `status.md` promise a header read. Nothing breaks; only the claim is wrong, and so is the cost it implies. | Correctness of the record. Fix the comment and the `status.md` line. |
| C3 | Nit | `CopyAdjustmentsActions.swift:185–186` | `SpotPastePlan` counts every id in the selection, including photos the change never reaches: stacks the catalog skips as unreadable (`changeAdjustments` reports them), and, on the measuring path, photos whose originals couldn't be read or that have no `sourceURL` (left out whole, with their own warning). | Paste Spots onto a selection where one photo has a schema-99 stack and another size. Activity shows "1 photos were left unchanged: their edits can't be changed…" and also "Spots were not pasted onto 1 photo: its size differs…" for the same photo. Both are true, but the second reads as if the rest of the paste reached it. | Design §5.1 (the count is photos the spots skipped). Either count only the ids the change writes, or accept and say so. |
| C4 | Nit | `CopyAdjustmentsActions.swift:126–127, 145–200` | A paste that includes Spots always measures frames before it writes, also in the loupe on one photo. The undo step is registered only after that `await`. This is the same known limit as the measuring paste ("⌘Z during a grid paste's file read undoes the step before the paste", #87). It is new for single-photo loupe pastes, which before this branch registered undo before `pasteAdjustments` returned (lens-corrections code review C3). | In the loupe, ⇧⌘V (with Spots copied) followed at once by ⌘Z undoes the edit before the paste. The window lasts as long as reading two headers: milliseconds for a JPEG, about 20 to 100 ms for a raw, longer for a cropped RW2 or ORF (C2). After that, the paste lands on top of the undone state. | Undo rule (each step undoes what it changed, in order). Optional: measure the source's frame when Copy confirms (the sheet already holds `sourceURL`), and in the loupe take the target's frame from the editor's decode. Or record this as accepted beside the #87 limit. |

## Questions

None for the designer or product manager beyond the engineer's open DQ-1 and
DQ-2 in `status.md`, which are the designer's to rule. C1 is a code finding
against R7 and design §5.2 as written, not a spec question.

## Checked and fine

- **`CopiedAdjustments.pasted(onto:pastingSpots:)`** starts from the target
  and takes only the copied items' module values and their on/off state
  (`copyModule` copies `disabled` both ways). `decode`, `cameraProfile`,
  `local`, `preserved` and every module that wasn't copied stay the target's.
  Unreadable stacks never reach the transform: `catalog.changeEditStacks` and
  `savedEditStacks` skip them. Pasted spots replace the target's, never add to
  them, so a paste can't exceed `SpotLimits.spots` (the source's stack was
  readable, so it holds 100 or fewer). The old `Adjustments.pasted(onto:)`
  carried the source's `disabled` flag for `localAdjustments` onto the
  target's masks, and the new one doesn't. That is a quiet fix.
- **Claim 4 (behavior changes).** A paste no longer carries the source's
  `cameraProfile`. That is consistent with R5 ("everything not copied is left
  exactly as the target has it"), and no build writes that value
  (`Adjustments.swift:21–23`). `copyAdjustments`, `pasteAdjustments` (old) and
  `applyAdjustments` have no callers left. `Adjustments.pasted(onto:)` is used
  by tests only, and `PresetTests:92` still equates it with a full preset. The
  debug script's `copyadjust` copies the defaults without the sheet and needs
  no undo group, since it doesn't change photos. `pasteadjust` already waits in
  its undo group (`waitForBatchMeasuring` → `waitForBatchWork` polls
  `batchAutoTask`), and the spots path keeps `batchAutoTask` set until its
  write, including when it chains into the measuring paste.
- **Claim 1 (`pasteMeasuringSpotFrames`).** Header reads run off the main
  actor. The source read uses `Task.detached`. The targets are read in
  `TaskGroup` children: I checked with a Swift 6 build that `addTask` children
  of a `@MainActor` task run off the main thread, since `addTask` doesn't
  inherit isolation. `frames` is mutated only in the main-actor parent. Stop
  and a newer batch are honored between chunks (`Task.isCancelled`,
  `batchAutoRun.owns(run)`). Chaining into
  `changeAdjustmentsMeasuringAlignment(then:)` cancels and replaces the
  current task. The outer `defer` then doesn't clear the new run's progress
  (`owns(run)` is false), and `then` runs only after `changeAdjustments` has
  queued the write. The spots warning is posted through `afterPendingWrites`,
  after the change has landed. The write and its undo go through the existing
  `changeAdjustments` (`persist`, one undo step, history label, the
  machine-learning and non-raw rule). On the measuring path, offline photos
  are kept out of the plan's count, so they are reported once.
- **Claim 2 (`maskFrameSize` and the tripwire).** The image comes from
  `RAWDecodeGraph.output(of:)`, and only its `extent` is read. Nothing is
  rendered, so the rule behind `rawFiltersAreMadeInKnownPlaces` (every
  rendered RAW image is keyed) holds. The move into `PreviewGenerator.swift`
  is legitimate, not a dodge: a new file would have needed only a `false`
  entry. The order (whole-sensor filter, plain filter, LibRaw's
  `frameSize().orientedSize`, then ImageIO with orientation) mirrors
  `decodeRAW` and `rawImage`. The renderer decodes the whole sensor whenever
  spots render (`AdjustmentRenderer.swift:999`), so both sides of the
  comparison use the same frame. The Lens warp keeps the frame's extent.
  Spots are stored in unit coordinates, so an equal size is all R8 needs. The
  test pins the measured size to the renderer's full-frame decode for an
  upright JPEG, a turned JPEG and a DNG. Not checked on real files: cropped
  RW2 or ORF, or a RAF that LibRaw decodes.
- **Claim 3 (sheet source).** In the loupe it uses `editor.savedAdjustments`,
  not a running drag or hover. Elsewhere it uses
  `writes.savedAdjustments`, read after pending writes. Values are frozen in
  `CopySheetState`. A second request while the read runs does nothing.
  Unreadable edits open no sheet and post the existing warning.
  `presentCopySheet` checks again whether another modal opened while the read
  ran.
- **R7 apart from C1.** The partial paste is the transform the question
  tests, so a paste without a Lens group never asks. Color Alignment is
  measured only when it was copied (`copied.values.needsAlignmentMeasurement`,
  tested).
- **The sheet.** It is listed in `LibraryModal`, with `onDismiss:
  modalDidClose()` and `LibraryModalTests` updated. `canCopyAdjustments`
  covers the menu, toolbar and ⋯ menu, and the menus read focused values.
  The check boxes are system `NSButton`s with a mixed state. The `ScrollView`
  sits in a sheet, not under the toolbar (design §3.8, as
  `LookTableBrowserSheet`). The `AppKitCheckbox` change keeps the inspector's
  small boxes at 11 pt.
- **Strings and branding.** Every new UI string has a catalog entry, with
  plurals where a count appears. The removed key has no remaining user. No
  brand values appear, and nothing is persisted (item names exist in the
  debug script only).
- **Not touched.** No migration, no stack format or `AdjustmentParameters`
  change, no `PreviewCacheKey.currentPipelineVersion` bump needed (the
  renderer is unchanged), no golden or tolerance moved, no new dependency, no
  `Process`, no network.
- **Tests.** Every testable acceptance criterion has a Swift Testing test
  that would fail without the new types (AC2 to AC7, AC9, AC10). The app-level
  orchestration (Activity rows, the sheet) is checked by the debug script, as
  the app target has no unit tests. No determinism claims are made. The new
  tests are pure functions, except `maskFrameSizeMatchesTheDecode`, which
  reads files of its own in a temporary folder off the cooperative pool and
  shares no state. That is a structural argument, so no run count is needed.

## Follow-up

(After the engineer's fixes.)
