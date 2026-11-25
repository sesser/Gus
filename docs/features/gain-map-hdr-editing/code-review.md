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

Second pass, 2026-11-25. Reviewed `6b8fff9..2e98a11` (`507edc2`, `27f5899`,
`4790f7f`, `d5e2486`, `2e98a11`), the fixes for this file and for `review.md`.
Build and tests at `2e98a11`: `swift build` clean; full `swift test` **1572
tests in 221 suites passed** (88.6 s); the HDR suites (`GainMapHDRTests`,
`HDRChoiceTests`, `HDRChoiceOutputTests`, `GainMapAdjustmentTests`, with
`GainMapTimingTests` skipped as opt-in: 39 tests in 5 suites) passed 10 of 10
repeated runs (`--skip-build`). The app was not launched.

**Verdict, second pass:** ready for QA. Every first-pass finding is fixed or
closed by the owner, and the new code is sound. Two new nits (C8, C9) are
narrow and can be fixed now or filed as follow-ups. Neither blocks.

| # | Outcome | Commit | Check |
| --- | --- | --- | --- |
| C1 | Fixed | `4790f7f`, `27f5899` | `possibleHeadroom` (loupe and pane) is nil while `model.isOffline(item)`, so `immediateImage` no longer returns the memory-cached HDR version offline, and no HDR request goes out. `reloadIfHDRPossibilityChanged` runs from `show`'s same-key branch and from the 0.25 s poll. When going offline or coming back flips the possibility, `reload()` sets `shownKey = nil`, so `show` takes `!sameVersion` and `beginVisit` resets `visitFailed`. A remount then brings HDR back without reopening. `gainMapHDROutcome` maps a nil source URL to `.superseded`. I checked `WorkLane`: cancellation is per waiter, and a shared job runs on while any waiter remains, so a visible request never gets a `CancellationError` that belongs to a cancelled prefetch. One narrower path remains: C8. |
| C2 | Fixed | `4790f7f` | `ComparisonPane.display` is `guard kind >= rendition`, as in the loupe. A refit renders at the size already shown (`full = rendition == .hdrFull`), so it still passes. |
| C3 | Fixed | `27f5899`, `4790f7f` | `PreviewService.supersedes` treats `CancellationError`, `staleEditStack` and `sourceUnavailable` as replaced requests, not failures. Both loupe paths and both pane paths switch on the outcome, and `.superseded` does nothing. The save that made the stack stale calls `show` with the new hash, and that asks again. The `outcomes` test covers each case. |
| C4 | Fixed | `507edc2` | `Adjustments.hdrIsOn` reads `hdr.isOn && !disabled.contains(.hdr)`, which matches `EditStack.hdrChoice`. Its setter turns the operation back on. Every app read and write goes through it (grep: no `hdr.isOn` left outside `Adjustments.swift`). That includes the frame-fit checks, `originalValues`, the menu, the check box and the editor's `hdrHeadroom(for:)`. `turnedOffOperationIsOff` checks both readings and the unchanged write-back. |
| C5 | Withdrawn (owner's ruling) | — | The owner, 2026-11-25, asked whether an older build ever needs to edit a library this build has opened: "No, ignore it". Q1 is closed with it. |
| C6 | Fixed | `507edc2` | The v17 comment now sits above `addHDRChoice`, and the v16 comment above `addRemoteServices` again. Only the function moved: the migration list and the migration body are unchanged. |
| C7 | Fixed | `507edc2` | Both comments are corrected (`LiveRenderSession.render`, `GainMap.hdr`). |

New code from the designer's findings, checked and fine:

- **F1, F2 (histogram).** The editor requests a non-interactive frame when
  `hdrDisplayHeadroom` goes from nil to a value with the choice on. That frame
  is never shown unless the editor is live, because the loupe checks
  `showsLive`. An SDR frame of other values clears the HDR counts. Every HDR
  frame that is not overlaid carries both histograms
  (`LiveRenderSession.render`), so HDR drags don't clear them.
  `showsHDRHistogram` and `hdrHistogramCounts` replace the inspector's private
  property, and comparison clears the old counts when a new active key comes in.
- **F3 (stale frames).** `frameFits` and `tileFits` drop a frame of the other
  choice, and an HDR frame once `gainMapHeadroom` is nil, without moving
  `shownFrameRevision`, so the next frame of the right values is still shown.
  The editor's headroom (`editorHeadroom`) and the loupe's (`gainMapHeadroom`)
  are both nil after a failure or while offline, so the editor stops making
  frames the loupe would refuse.
- **F5 (refiner in HDR).** `SharpeningMapRefiner.renderWhole` applies the gain
  map only for content `.photo` with a headroom. It uses the same
  `placed(over:values:context:)` and `makeHDRCGImage` as
  `PreviewGenerator.gainMapHDRImage`, and the new test pins it to that render
  within 0.005 and 0.01 stops. Maps stay SDR.
- **F6, F7 (screen changes, a failure with HDR on screen).** `failVisit` reloads
  with `reloadsSameKey`, keeping `shownKey`, so `sameVersion` holds and
  `visitFailed` survives. `failGainMap` does the same through `keepsFailure`,
  and the pane's `reloads` keeps its zoom. The `.failed` branch in both full
  loads falls through to SDR after a cancelled reload. That is duplicate work
  only: the shown key is unchanged, so its result is still correct.
- **F4, F8, F9.** The spinner task is main-actor and cancelled in teardown,
  and `publishHDRStatus` clears it once the status leaves `.loading`. The new
  help string is in the String Catalog. The pane's value has the version
  phrase, and change detection leaves the phrase out (`withVersion: false`).
- **HEIC and JPEG only.** `eligibleSource` checks the name (`FileKind`) and the
  content type (`public.heic`, `public.heif`, `public.jpeg`), so
  `GainMap.exists`, `load`, `photocli develop` and the editor agree. The test
  fails without the fix (`status.md`), and I accept that.
- **Determinism.** The four tests added in this pass render fixed synthetic
  files or test pure values, and none shares state or depends on timing. The
  outcome test's stale case depends only on the service's stack closure. I
  accept the structural argument, and the 10 of 10 runs agree with it.

New findings, second pass:

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C8 | Nit | `Sources/PhotoCore/Preview/PreviewService.swift:389` (`guard let made else { standardRange.insert … }`), `:426`; `GainMap.load` | `gainMapHDRImage` treats a nil from `GainMap.load` as "this file has no gain map" and remembers that in `standardRange` under the photo's memory key for the rest of the run. `GainMap.load` also returns nil when the file can't be read. `gainMapHDROutcome` now turns that remembered nil into `.failed` whenever the request has a source URL. | A request is made while the original is readable, or while the app still thinks it is. Then the file stops being readable before the lane job reads it: the volume is ejected with an HDR render queued, or a network volume stops answering but stays mounted. The photo shows **SDR: HDR Failed**, which is right at that moment. After a remount or a reconnect, the possibility check reloads it, but every request now returns the remembered nil, so it stays **SDR: HDR Failed**. Opening the photo again doesn't help either, although the user guide says "open the photo again to retry". It clears only when the stack's render hash changes (any edit) or the app quits. Found by reading; timing-dependent and not reproduced. Fix: remember only a file that was read and has no gain map (for example, `GainMap.load` distinguishing an unreadable file, or throwing `sourceUnavailable`), so an unreadable file is `.superseded` or a retryable failure. | C1's intent (a remount brings HDR back); user guide |
| C9 | Nit | `Sources/PhotoApp/Loupe/LoupeView.swift:846` (`reloadIfHDRPossibilityChanged`) → `:420` (`reload()`) → `:499` (`applyZoom`) | In the single loupe, the new possibility reload goes through `reload()`, which clears `shownKey`. `show` then counts it as another photo (`!sameVersion`): it sets the frame size, clears the tile and calls `applyZoom(animated: false)`, which centers on the photo's middle. The comparison pane's reload keeps `sameVersion` (`reloads`), so it doesn't do this. | An HDR-on photo at 100%, panned to a corner. Its volume goes offline or comes back, or its screen starts or stops reporting extended range in place. The loupe jumps to the photo's center. Before this pass nothing reloaded in these cases. A View ▸ Show / Hide HDR or a screen move already recentered this way, so this is the same behavior on new triggers. Found by reading, not reproduced. Fix if wanted: reload the possibility change as the pane does, as the same version with a new visit, keeping zoom and position. | R8 spirit (no jump the person didn't cause) |

Neither nit needs `/security-review`: this pass adds no parser, subprocess,
file writing or network code. The `.heic` and `.jpg` check narrows what is read.
