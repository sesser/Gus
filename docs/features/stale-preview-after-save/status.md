# Stale preview after save: implementation status

Owner: swift-macos-engineer. Bug fix (no `prd.md` or `design.md`), reported by
QA on 2026-11-06. Branch `bug/stale-preview-after-save`, cut from `develop`
at `334312c`.

**Status: Done.** Ready for review (code-reviewer, qa-tester).

States: Not started · In progress · Done · Blocked · Deferred.

## The bug

Saving an edit sometimes cached the old look under the new edit-stack render
hash. Cache keys are content hash + render hash + tier + pipeline version and
a cached entry is never regenerated, so the wrong thumbnail stayed after
relaunch. QA saw it on 3 of 4 photos of a `photobench` library, with and
without the sharpening map: on IMG_00003, after `adjust exposure 1.5`,
`thumb/de/de71…-822f9568f0de6aea.jpg` (new hash) was byte-identical to the
unedited `…-6c76a50e5dc3f0cd.jpg` (`6c76a50e5dc3f0cd` is
`EditStack.identity.renderHash`). The loupe showed the edit correctly.

## Root cause

The app showed an edit's new hash before the catalog held the edit, and the
preview service rendered whatever stack the catalog held at that moment under
whatever key it was asked for. Line numbers are those at `334312c`.

1. `AdjustmentEditor.apply` queued the write on the model's write chain
   (`AdjustmentEditor.swift:555-557`, `library.persist { catalog.setEditStack }`)
   and then, synchronously and before that write ran, published the new hash
   (`:572`, `library.setEditStackHash(hash, …)`; `:574`, the editor's item).
   The grid cell and film strip are reconfigured on that change and request
   the new key at once (`PhotoCell.configure`, `FilmStripCell`).
2. `PreviewService.prepare` loads the stack by version id from the catalog
   (`PreviewService.swift:179`, through the loader at `:115`) and stores the
   result under the request's key (`:197-205`), whose hash is the new one. If
   the write has not landed, that is the old stack rendered under the new
   hash, on disk for good. The same holds in memory for
   `fullResolutionImage` (`:223`, `:231`) and `hdrImage` (`:256`, `:265-267`).

The loupe looked right because it showed the live frame and then the frame
seeded into memory (`seedPreviewIfRendered`), which is rendered from the
saved values; the grid's thumbnail came from the race. A JPEG of the same
stack encodes to the same bytes, hence the byte-identical files. The sharpening
map is irrelevant: map frames are never seeded (`Frame.showsPhoto`), and the
race is in the grid's request.

`StalePreviewTests` confirms it (below): with a loader that still returns the
saved-before stack, the unfixed service stored it under the edit's key on
disk and in memory, and kept serving it after the "write" landed.

## Fix

Two layers.

- **PhotoCore invariant** (`PreviewService`). Every path that renders from a
  loaded stack (`prepare` for both disk tiers, `fullResolutionImage`,
  `hdrImage`) now goes through `PreviewService.stack(_:versionID:for:)`, which
  checks that the loaded stack's `renderHash` is the request key's
  `editStackHash`. On a mismatch it throws the new
  `PreviewService.Failure.staleEditStack` before rendering: nothing is
  rendered, stored on disk, kept session-only, put in memory, or recorded as
  standard range. Nothing is retried inside the service: a mismatch means the
  key is not (or no longer) the catalog's, and a retry cannot tell "not
  landed yet" from "superseded" without timing luck. The publishers below
  make sure the right key is requested after the write.
  - Why `renderHash` and not the row's stored `editStackHash`: the row's hash
    is written with the stack in one `UPDATE` (`Catalog.setEditStack`,
    `setEditStacks`, `VersionRecord.makeDefault`, `duplicateVersion`), and
    `EditStackCorpusTests` pins that a decoded stack's `renderHash` equals the
    hash recorded when it was written. So legitimate keys always match.
  - Cases checked against the invariant: identity stacks (key and stack both
    `EditStack.identity.renderHash`); disabled operations (left out of the
    hash on both sides); unreadable or newer-schema stacks (the loader
    already throws, as before; nothing changes); videos (the poster renders
    the loaded stack, checked the same way); ML fallback `storeForSession`
    (keyed by the stack it rendered, so it passes). The live-frame seed
    (`insertIntoMemory`) does not go through a loader; see the audit below.
- **App ordering** (`AdjustmentEditor.apply`). The new hash is shown only
  after the write succeeds: `showSaved(_:forVersion:)` runs inside the
  `persist` closure after `catalog.setEditStack`, so it publishes to the
  library, updates the editor's item and seeds the live frame in write-chain
  order. Until then the loupe keeps the live frame on screen. When the write
  fails (for example a stack this build cannot read), no hash is published
  and the Activity row reports the failure as before. Undo and redo of an
  editor step go through `apply` and get the same ordering.
- **Batch undo/redo** (`AdjustmentActions.registerEditStacksUndo`). Same
  family: it published through `afterPendingWrites`, which also runs when the
  write threw, so a failed undo published hashes the catalog did not have.
  It now publishes inside the `persist` closure after `setEditStacks`
  succeeds. (The forward batch path was already right: `change.value` is set
  only on success.)
- **Grid cell** (`PhotoCell`). A `staleEditStack` failure is not shown as
  "unavailable", just as cancellation is not: a newer stack is saved and its
  hash reconfigures the cell. Without this, a quick second edit could flash
  the unavailable glyph for one main-actor turn. The film strip and loupe
  already use `try?` and keep what they show.

### Audit of other hash publishers

| Path | Before | Now |
| --- | --- | --- |
| Editor commit (sliders, typed values, Reset, group on/off, Auto, crop Done, Rotate outside crop, ML toggle, Decoder) → `commit` → `apply` | published before write | after write |
| Editor undo/redo (`apply` from `registerUndo`) | published before write | after write |
| Paste, presets, grid Rotate, Auto Exposure, Reset All (`changeAdjustments`) | after write, success only | unchanged |
| Batch undo/redo (`registerEditStacksUndo`) | after write, also on failure | after write, success only |
| `catalogChanged` (from `showEditStacks`) | after write | unchanged |
| `reloadItems` | row hash and stack read from the same row | unchanged (a later write makes the request stale, not wrong) |
| `photocli` writes | another process; refused while the app holds `LibraryLock` | unchanged |
| Live-frame seed (`seedPreviewIfRendered`) | see below | runs after the write, from `showSaved` and after each frame |

`seedPreviewIfRendered` puts the loupe's frame in memory under the preview
key only when `frame.showsPhoto` (no mask overlay, not the sharpening map),
the frame's values equal the saved values and the values being edited,
the item's hash equals `committed.editStack.renderHash` (a stored stack that
`Adjustments` normalizes differently is skipped), the last frame was not
interactive (no drafts), and Show Original is off. No hole that puts another
stack's look under the key. One caveat, unchanged: a frame of saved values
that asked for machine learning and fell back seeds memory with the
fallback. That is memory-only and matches what the disk path keeps
session-only (`storeForSession`); an applied frame later replaces it.

## Repair of previews already cached wrong

Decision: **bump `PreviewCacheKey.currentPipelineVersion` from 6 to 7.** At
launch `removeObsoletePipelineVersions` deletes the `v6` folder and every
rendition regenerates on demand.

Why not a targeted repair: a wrong entry can sit under any hash a version
ever had, not only its current one. An undo back to no edits publishes the
identity hash before its write, so the identity entry of a photo that shows
no edits today can hold an edited look. The catalog keeps only the current
stack, with no edit history, so there is no way to tell which entries are
wrong short of rendering every stack every version ever had. The race exists
since `ba97c76` (2026-10-26, live editing in the Adjust tab), so any library
edited since then can be affected.

Cost: every thumbnail and preview regenerates once, as cells come on screen
(the background warm covers freshly imported projects only). For a large
library that is a first scroll at generation speed rather than cache speed
(`docs/PROFILING.md` has the numbers). Masters on volumes that are offline at
first launch lose their cached renditions until the volume is connected
again; this is how earlier bumps (3 to 6) behaved, and the cache is
documented as safe to delete. Rendering does not change: no golden was
updated, `UPDATE_GOLDENS` was never run, and all goldens pass unchanged.

## Build and test

- Baseline at `334312c`: `swift build` clean. `swift test`: 551 tests in 96
  suites passed, 1 known issue (`LiveSessionTests.swift:258`, "Values above
  white survive the cached stages", pre-existing `withKnownIssue`). One
  pre-existing warning: `SmartAlbumTests.swift:165` (unused result).
- Latest: `swift build` clean, no new warnings. `swift test`: **554 tests in
  97 suites passed**, 1 known issue (the same). Large-render and camera-RAW
  suites skipped as usual (environment variables not set).
- No linter or formatter is configured in the repository.

### The regression test

`Tests/PhotoCoreTests/StalePreviewTests.swift`, suite "Previews of a stack
not saved yet":

- `sdrRenditionsWaitForTheSavedStack`: a `PreviewService` whose loader
  returns the stack saved before the edit (identity) while the request's key
  carries the edit's hash (+1.5 EV). `prepare`, `image` (thumbnail) and
  `fullResolutionImage` must throw `staleEditStack`, and neither disk tier
  nor memory may hold the key. Then the loader returns the edit (the write
  landed) and the same requests must return renders clearly brighter than
  the original.
- `hdrRenditionsWaitForTheSavedStack`: the same for `hdrImage` at fit and
  full resolution, on a gain-map JPEG with a -2 EV edit.
- `catalogWritesDecideWhatRenders`: the app's real sequence on an in-memory
  catalog with the catalog-backed service: the edit's hash before
  `setEditStack` is stale; after it, the row's hash renders the edit; after
  an undo to the identity stack, the identity key renders the original.

**Proof it failed before the fix.** The first two tests were run against the
unfixed `PreviewService` (with `#expect(throws: (any Error).self)`, since the
new error case did not exist yet). Result: 2 tests failed with 14 issues:
no error thrown for `prepare`, `image`, `fullResolutionImage` and both
`hdrImage` calls; `cache.contains` true for the edit's preview **and**
thumbnail keys; the thumbnail and HDR renditions in memory under the edit's
key; and after the loader switched to the edit, all five renditions
(thumbnail, preview, 1:1, HDR fit, HDR full) still had the original's level,
i.e. the old look was served under the new hash, which is QA's report.
After the fix all three tests pass.

### Tests changed

- `PreviewTests.offlineMastersAreServedFromCacheOnly`: its cached key used an
  arbitrary hash (`hashB`) with a loader that returns the identity stack.
  That is exactly the mismatch now refused, so the key uses
  `EditStack.identity.renderHash`. What the test checks (an offline master is
  served from cache, and a missing one fails with `sourceUnavailable`) is
  unchanged.
- `PreviewTests.diskCacheStoresLoadsAndCanBeWiped`: its "older pipeline"
  key hard-coded version 7, which is now current. It uses
  `currentPipelineVersion - 1`, which keeps the test's intent through future
  bumps.

## Acceptance (from the task)

| # | Criterion | How checked | State |
| --- | --- | --- | --- |
| 1 | Root cause stated with file:line, confirmed by a test | Above; `StalePreviewTests` failed on the unfixed code | Done |
| 2 | Deterministic test that fails before and passes after | `StalePreviewTests` (no sleeps; the loader's answer is set explicitly) | Done |
| 3 | PhotoCore invariant and app-side ordering | `staleEditStack` check in `PreviewService`; `showSaved` in `AdjustmentEditor`; batch undo in `AdjustmentActions` | Done |
| 4 | Repair of wrong entries decided and recorded | Pipeline version 7, above | Done |
| 5 | `swift build` and `swift test` green | 554 tests, 97 suites, 1 known issue (pre-existing) | Done |
| 6 | User-visible strings through the catalog | None added: `staleEditStack` is never shown to a person | Done |
| 7 | `USER_GUIDE.md` only if visible behavior changes | Unchanged: it already says previews are safe to delete and regenerate on demand; the one-time regeneration is not ongoing behavior | Done |

## For QA (in the bundled app)

Not run by engineering. Use a copy of the bundle with its own bundle
identifier and a scratch `photobench` library, and pass `--library-root` on
every launch.

1. Repeat QA's run: open a photo in the loupe, `adjust exposure 1.5`, close
   the loupe, quit. The cache folder is now `v7`: the edited photo's
   `thumb/<xx>/<contentHash>-<new hash>.jpg` must differ from the unedited
   `…-6c76a50e5dc3f0cd.jpg`, and the grid thumbnail must show the edit after
   relaunch. Repeat on 4+ photos, with and without the sharpening map.
2. Undo back to no edits, quit, relaunch: the grid shows the original.
3. Several quick slider commits in a row: the grid thumbnail ends on the last
   one and never shows the unavailable glyph.
4. Launch with an existing `v6` cache folder: it is deleted at launch and
   thumbnails regenerate as they scroll into view.

## Notes (not fixed here)

- `AdjustmentEditor.follow` loads the stack of a newly shown photo straight
  from the catalog without waiting for pending writes. Leaving a photo and
  coming back to it within one write's latency can load the stack from before
  the last commit; a commit made then writes those values back, dropping the
  earlier edit. Not a cache problem; pre-existing; rare.
- Between a commit and its write landing, a path that hands the loupe back to
  its cached renditions without seeding (ending a hover preview with
  `endPreview`, turning Show Original off) shows the previous hash's preview
  for that write's duration, then the new one. Before this fix those paths
  could show the stale-cached rendition instead, permanently.
- The live-frame seed stores a loupe-sized frame in the preview tier's
  memory slot; quality only, memory only.

## Open questions

None. No design questions; no requirements issues.

## README

No change: requirements, build commands and repository layout are unchanged.
