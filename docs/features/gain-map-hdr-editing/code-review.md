# Edit and show gain-map photos in HDR: code review

Owner: code-reviewer. Date: 2026-11-25. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/gain-map-hdr-editing`, `cb8338d..3c3867f` (merge base with
`origin/develop` to HEAD, 11 commits). Build and tests: `swift build` clean;
full `swift test` 1568 tests in 221 suites passed (81.3 s); the four new suites
(`GainMapHDRTests`, `GainMapAdjustmentTests`, `HDRChoiceTests`,
`HDRChoiceOutputTests`) passed 10 of 10 repeated runs (`--filter`, `--skip-build`).
The app was not launched.

## Verdict

Not ready for QA yet. The stored choice, the render hash, the catalog column,
the SDR output and the gain map's geometry are sound and well tested. Two
loupe and comparison paths break R4 and R8: an offline photo can show its HDR
version labeled SDR, or come back after a remount labeled "HDR Failed" (C1);
and a comparison pane at 100% can swap its full-resolution HDR picture for the
preview-size one (C2). Both are small, local fixes. The rest are nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Should fix | `Sources/PhotoApp/Loupe/LoupeView.swift:801` (`gainMapHeadroom`), `:543` (`immediateImage`), `:525` and `:1036` (`failVisit`); the same in `Sources/PhotoApp/Loupe/ComparisonView.swift:949`, `:930`, `:1132`; `Sources/PhotoCore/Preview/PreviewService.swift:315` | Nothing on the HDR path checks whether the original is offline. `gainMapHeadroom` is non-nil for an offline photo with the choice on (it checks only the choice, the View setting, the display and an earlier failure), so the loupe and panes still look for and ask for the HDR version. `PreviewService.gainMapHDRImage` answers from memory first and returns nil when `request.sourceURL` is nil, and the loupe and panes treat that nil as a render failure. | (a) A photo with HDR on whose HDR version is in memory (viewed earlier in this run) goes offline: the volume is ejected, or a network volume drops. Return to it: `immediateImage` shows the memory-cached HDR version (`.hdrPreview`) and the SDR preview is then refused (`kind < rendition`), while `HDRVersionBadge` puts the offline reason first and the caption shows the warning triangle and **SDR** beside **Offline**. So the caption says SDR while HDR is on screen, which breaks R4 and design §5 row 1 ("the cached SDR preview is shown"). (b) The same photo, not in memory: `gainMapHDRImage` returns nil and `failVisit()` runs. When the volume is mounted again while the photo stays open, `isOffline` turns false, but the visit stays failed: the badge reads **SDR: HDR Failed** (nothing failed), and the editor, which becomes available, renders SDR live frames (`editor.hdrDisplayHeadroom` nil) until the photo is opened again. AC4's offline case was checked by the badge rule's test only (`status.md`), so neither path ran. Fix: make `gainMapHeadroom` nil while `model.isOffline(item)` (loupe and pane), and count only a real render error as a failure. See also C3. | R4, R8; design §5 |
| C2 | Should fix | `Sources/PhotoApp/Loupe/ComparisonView.swift:1052` | `display(_:as:gainMap:)` accepts `kind >= rendition \|\| (gainMap && rendition.isHDR)`. Given the order `placeholder < preview < hdrPreview < full < hdrFull`, the extra clause only ever lets a gain-map `.hdrPreview` replace a `.hdrFull`. Refits don't need it, because `followHeadroom` renders at the size already shown (`full = rendition == .hdrFull`), and the single loupe (`LoupeView.swift`, `guard kind >= rendition`) has no such exception. | A pane at 100% (`zoom == .actualSize`) starts `fullTask` (`gainMapHDRImage(fullResolution: true)`) and `hdrTask` (preview size) together. When the full-resolution version comes back first (it is in memory from an earlier 100% view and the preview isn't, or the preview job waits behind neighbor prefetches in the two-slot `gainMapLane`), the preview lands afterwards and replaces it. The pane then shows a 2560 px picture stretched at 100%, and later refits stay at preview size. This is timing-dependent and was not reproduced; the code allows it. Fix: drop the `\|\|` clause. | R8 (no worse picture once shown), side-by-side design (100% is the photo's own pixels) |
| C3 | Nit | `Sources/PhotoApp/Loupe/LoupeView.swift:518–526`, `ComparisonView.swift:926–930` | Every nil from `try? previews.gainMapHDRImage` counts as a failure, sticky for the rest of the visit, `PreviewService.Failure.staleEditStack` included. | A write of a new stack (an undo or redo, a History revert) lands while the visible HDR job is queued in the lane. The job then reads the new stack, finds its hash differs from the request's and throws `staleEditStack`. If the `hdrTask` resumes on the main actor before the write's `showSaved` continuation, `shownKey == key` still holds and `failVisit()` runs. The following `show()` sees only a hash change (no new visit), so the photo stays **SDR: HDR Failed** with SDR live frames until it is reopened. The window is a few milliseconds: not reproduced, listed because the C1 fix (count only a real render error) covers it. | R8 |
| C4 | Nit | `Sources/PhotoCore/Edits/HDRChoice.swift:53` against `Sources/PhotoCore/Edits/Adjustments.swift:89–97` | `EditStack.hdrChoice` (which feeds `version.hdr`, the export count and the comparison panes) counts only an *enabled* `hdr` operation. `Adjustments.hdr`, which the editor and the single loupe use, reads the operation's `on` whatever its `isEnabled`. | A stack holding `{"kind":"hdr","isEnabled":false,"parameters":{"on":true}}` (nothing in this build writes one, but `hdr` isn't a group, so only a hand edit or a later build could): the catalog column and comparison say off, while the opened loupe shows HDR and the check box is on. Fix: read the choice one way in both places, for example `hdr.isOn && !disabled.contains(.hdr)`, or have `hdrChoice` go through `Adjustments`. | One source of truth |
| C5 | Nit | `Sources/PhotoCore/Edits/HDRChoice.swift:46–49`, `EditStack.renderHash` | Leaving the enabled `hdr` operation out of the render hash makes the hash formula differ between this build and older ones, which hash every enabled operation, unknown ones included. | Turn HDR on for a photo here, then edit it in an older build of the app on the same library (nothing refuses a catalog at v17). The older build writes `editStackHash` over the stack with `hdr` included. Back in this build, `PreviewService.stack` computes a hash without it, finds a mismatch, and throws `staleEditStack` for every preview request of that photo. The grid tile stays blank (`PhotoCell` ignores the error) until the photo is edited here. The editor's reconcile on open compares only `version.hdr`, so it doesn't repair this. It only matters if mixed builds on one library are supported (Questions, Q1). | Unknown operations survive (holds); render hash |
| C6 | Nit | `Sources/PhotoCore/Catalog/CatalogSchema.swift:470–487` | `addHDRChoice` was inserted between `addRemoteServices` and its doc comment. The v16 comment ("Servers photos are imported from…") now heads the v17 function, and `addRemoteServices` has none. | Misleading docs only. | — |
| C7 | Nit | `Sources/PhotoCore/Edits/LiveRenderSession.swift:291`; `Sources/PhotoCore/Preview/GainMap.swift:126` | Stale doc comments. `render(…hdrHeadroom:)` says an HDR frame's histogram "is the SDR frame's, until the HDR one is built", but the HDR histogram is built (`Frame.hdrHistogram`). `GainMap.hdr` says `placed` comes "from `placed(over:crop:)`", which is now the test-only overload; the app uses `placed(over:values:context:)`. | Misleading docs only. | — |

## Questions

- **Q1 (for the owner, through the main session; C5).** Must the library work
  when an older build edits it after this one? Nothing refuses a catalog from a
  newer build, and CLAUDE.md's "unknown operations survive" rule suggests mixed
  builds are meant to work. If they are, the render hash's exception needs a
  repair path. One option: reconcile `editStackHash` against the stack on
  editor open and on item load. Another: give `hdr` its own column only, out of
  the stack, which would change R2's History and undo route. If they aren't,
  C5 can be closed.
- **For the owner's CLAUDE.md (not a finding).** The edit stack rule says "The
  render hash covers enabled operations only". After this branch it covers
  enabled operations except `hdr`, which changes no SDR pixel. `status.md`
  (README) proposes the wording. The rule's intent holds: stacks that render
  the same share previews.

## Checked and fine

- **Stack format.** `hdr` is one operation (kindVersion 1, schema 1, left out
  when off), not a `Group`, so `replacing`, `CopiedAdjustments.pasted` and
  preset saves never carry it (`HDRChoiceTests` AC3). `resettingAll` removes it
  and `resetting(section)` keeps it. `isDefault` counts it, so Reset All is
  enabled for an HDR-only photo. `AdjustmentParameters.swift` describes it
  (`AdjustmentParameterTests` and `CommandTests` pass). Older builds keep it as
  an unknown operation.
- **Render hash.** It changes only by filtering out `hdr`, so every existing
  stack keeps its hash. No pipeline bump is needed, and none was made. No
  golden changed (none in the diff; `GoldenTests` pass). `EditStack.isIdentity`
  changed the same way and has no caller in `Sources/`.
- **Migration v17.** New, numbered next, no existing migration edited, generic
  column name `hdr`. `version.hdr` is written in the one stack writer
  (`setEditStacks`, which `setEditStack`, the batch writers, History revert and
  `photocli develop` all use). Duplicate copies the column; restoring copies
  sets it from the stack (`storeHDRChoice`). Every query that builds a
  `CatalogItem` selects the sixteenth column. No sidecar trigger watches the
  column.
- **SDR output.** The previews, export and `photocli render` paths are
  untouched. `LiveRenderSession`'s SDR branch makes the same calls in the same
  order. AC11's byte-equality test covers previews and `photocli render`.
  Automatic measurements read SDR (AC13 test).
- **App-side choice.** `ShownKey` adds the choice, since the hash leaves it
  out. `showSavedEditStack` updates `items[].hdr` on every save and batch.
  `seedPreviewIfRendered` puts an HDR frame only into the gain-map memory key,
  never as the SDR preview, and an SDR frame of an HDR-on photo (View setting
  off) as SDR. `setHDR` is blocked during a crop session.
- **Gain map geometry (R19).** `gainMapGeometry` applies Distortion's warp,
  spots and crop in the renderer's order, used by the settled, live and region
  paths. The AC17 Distortion test checks within itself that an unwarped map is
  caught, and the spot cases failed with the spot step removed (`status.md`).
- **Concurrency.** Gain maps load off the main actor: lane jobs, the
  `LiveRenderSession` and `LiveRegionRenderer` actors, and detached header
  reads. Timers and observers run on the main run loop with
  `MainActor.assumeIsolated`, and are invalidated or removed in teardown.
  `GainMap`'s `@unchecked Sendable` gives a reason that holds (immutable
  `CIImage`). HDR frames are rendered to owned half-float pixels before they
  reach a layer.
- **UI and menu.** Adjust ▸ Turn On / Off HDR reads `LibraryMenuState` through
  the focused value, not a model passed into `Commands`. The check box is an
  `AppKitCheckbox`, with no SwiftUI `ScrollView`. The debug script's `adjust
  hdr` is inside `changing` (the `adjust` verb). Strings are in the catalog
  (`LocalizationTests` pass), and `BrandingTests` pass.
- **R16.** HLG, PQ and DNG live frames stay SDR with the old badge, and the
  existing tests pass.
- **`photocli develop`.** It refuses `hdr.on` for an unreadable original
  (`fileNotFound`) and for a file without a gain map (`invalidEdit`), before
  `--dry-run` (AC15 test).
- **Export notice.** `hdrCount` resolves pairs as `resolve` does (AC12 test).
- **Dependencies, clean room.** No package or vendored code added. Gain maps
  are read with ImageIO and Core Image only.
- **Determinism.** The new tests compare renders of fixed synthetic files with
  tolerances well above half-float rounding, or pure values with fixed inputs
  and times. They share no state and depend on no timing. I accept that
  structural argument. 10 of 10 repeated runs of the four suites passed, which
  only rules out a flake rate above about 30%; the argument carries the claim.

## Follow-up

(After the engineer's fixes.)
