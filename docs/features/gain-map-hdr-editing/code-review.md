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

Third pass, 2026-11-25. Reviewed `81ccfb8..1f5dd6a` (`c629de3`, `1215ef4`,
`033458e`, `1f5dd6a`): the fixes for C8 and C9 and for the designer's F1 (its
rest, at 100%) and F11. Build and tests at `1f5dd6a`: `swift build` clean; full
`swift test` **1574 tests in 221 suites passed** (81.6 s); the HDR suites
(`GainMapHDRTests`, `HDRChoiceTests`, `HDRChoiceOutputTests`,
`GainMapAdjustmentTests`, `GainMapTimingTests` skipped as opt-in: 41 tests in 5
suites) passed 10 of 10 repeated runs (`--skip-build`). The app was not
launched.

**Verdict, third pass:** ready for QA. C8 and C9 are fixed, the F1 and F11 fix
is sound, and this pass adds no new finding.

| # | Outcome | Commit | Check |
| --- | --- | --- | --- |
| C8 | Fixed | `1215ef4` | `GainMap.read` throws `ReadFailure.unreadable` when the header, gain-map or HDR decode fails and `isReadableFile` is false, and returns nil only for a file it read (or one whose name isn't HEIC or JPEG). `PreviewGenerator.gainMapHDRImage` and `gainMapHDRHistogram` call it, so the throw leaves the lane job before `PreviewService.gainMapHDRImage` reaches `standardRange.insert`. `supersedes` doesn't list it, so the outcome is `.failed` for that visit (right while the file can't be read), and the next visit, or the in-place reload a remount triggers (C1, C9), asks again. The comparison pane's histogram reads it through `try?`, so a throw is the same nil as before. The live renderers and the refiner still use `load` (nil either way); their gain map is per session, so a reopen loads it again. The new test moves the file away and back between two requests with the same key; by its code, without the fix the first nil would be remembered and the second request would fail as `status.md` says. A race where the file comes back between the failed decode and `isReadableFile` would still be remembered; that window is a few microseconds and needs a remount timed to it, so it's not a finding. |
| C9 | Fixed | `033458e` | `reloadIfHDRPossibilityChanged` now sets `reloadsSameKey` and `beginsVisitInPlace` and calls `show`, so `sameVersion` holds: no frame resize, no `applyZoom`, no `cancelPendingClick`. `inPlace` begins a new visit, which resets `visitFailed` and `visitHDRPossible`. It takes the general rendition branch, where `rendition` goes to `.placeholder` before `immediateImage` is shown, so an SDR preview can replace an HDR picture on the way offline. It clears the tile and runs `loadFullResolution` at 100%. The flag is cleared in the same `show` that reads it, and every path that sets it calls `show` right away; a `show` that returns early leaves `shownKey` nil, and then `sameVersion` is false. The guard's early-return branch calls this function, but `reloadsSameKey` makes the inner `show` pass the guard, so there's no recursion loop. |

New code from the designer's findings, checked and fine:

- **F1, F11 (`c629de3`).** `requestedHeadroom` is the `hdrHeadroom` argument
  in both renderers (nil for SDR), set even when the file has no gain map and
  the frame comes out SDR. The editor's two skips in `requestRender` now also
  need `LiveFrameRules.rendered(for:wanted:)`: both nil, or both set and within
  `GainMapHeadroom.tolerance`. The editor computes `headroom` once per loop
  pass and uses it for the check and for both renders, so a check and its
  render can't ask for two different headrooms. When no HDR is wanted, both
  sides are nil, so SDR skips (pans with nothing changing) work as before. At
  100%, the `hdrDisplayHeadroom` nil-to-value `requestRender` now re-renders
  the tile and the whole frame (the frame that gives the HDR counts). A
  headroom change with live frames up re-renders the tile. The refiner's photo
  frame records no `requestedHeadroom`. It's built only while a fringe slot is
  replaced, which `canRenderRegion` excludes from both skips, so at most it
  costs one extra whole-frame render once picking ends. `sharpFrameIsOnScreen`
  ignores the headroom on purpose (design §6.3, no spinner while following the
  display). The new test checks the rule in both directions, the tolerance,
  values and overlay, and what both renderers record.
- **Debug script.** `print hdr` adds `tile hdr <h>|sdr|none` from
  `editor.regionFrame`. It changes nothing.
- **SDR output.** No path for previews, export or `photocli render` changed.
  AC11's byte-equality test and the goldens pass.
- **Determinism.** The two new tests render fixed synthetic files or check a
  pure rule. The C8 test uses its own service and temporary folder, a distinct
  memory key per case, and moves files only between awaited requests. Nothing
  depends on timing or shared state. I accept that structural argument, and 10
  of 10 runs agree with it.

No `/security-review` is needed for this pass. `GainMap.read` reads the same
headers as before and adds one `isReadableFile` check. It adds no parser,
subprocess, file writing or network code.

Fourth pass, 2026-11-25. Reviewed `ac6f297..e1e6fa0` (`c3f21e7`, `21e4782`,
`6ebce7a`, `60af4cc`, `4b1523e`, `e1e6fa0`): the fixes for QA's Q1 to Q5
(`qa.md`, first pass) and their record in `status.md`. Build and tests at
`e1e6fa0`: `swift build` clean; full `swift test` **1575 tests in 221 suites
passed** (97.3 s); the HDR suites (`GainMapHDRTests`, `HDRChoiceTests`,
`HDRChoiceOutputTests`, `GainMapAdjustmentTests`; `GainMapTimingTests` skipped
as opt-in: 42 tests in 5 suites, parametrized cases not counted separately)
passed 10 of 10 repeated runs (`--skip-build`). The opt-in
`HEIC_GAINMAP_SAMPLE` test on one of the owner's files (both kinds of gain map,
read in place, nothing copied or recorded) passed: +0.006 stops against the
system's HDR decode, as `status.md` gives, so the maker dictionary now set on
the receiving image leaves an ISO map's render alone. The app was not
launched.

**Verdict, fourth pass:** ready for the designer's confirmation of DQ-2 and
then QA. Q1, Q2, Q4 and Q5 are fixed and sound. Q3's layout is correct (no
badge can cover the marks once an arrangement is chosen), but it adds one nit
(C10) that belongs with DQ-2: transient badges, not only a change of version
badge, can move the marks at some widths.

| QA finding | Outcome here | Commit | Check |
| --- | --- | --- | --- |
| Q1 | Fix sound | `c3f21e7` | `GainMap.receiving` sets the file's Apple maker dictionary on the image the map is applied to, and `ceiling(of:headroom:receiver:)` does the same for its white image. There are only two `applyingGainMap` calls in `Sources/` (`GainMap.hdr` and `ceiling`), and every HDR path goes through `hdr`: `fullHDR`, `PreviewGenerator.gainMapHDRImage` and `gainMapHDRHistogram`, `LiveRenderSession`, `LiveRegionRenderer`, `SharpeningMapRefiner`. So one change covers the loupe, panes, tiles, refinement and both histograms. With no maker dictionary the image passes through unchanged, so a Core Image ISO file renders exactly as before (AC11's byte-equality test passes for both kinds). The `@unchecked Sendable` reason now names the dictionary: a `let` of ImageIO's property dictionary, never mutated, which holds. No pipeline bump is needed: HDR versions are memory only, and no SDR output path changed (goldens pass). |
| Q4 | Fixed | `c3f21e7` | `writeAppleGainMap` writes only Apple's auxiliary gain map, and the `loads` test asserts that (no ISO map, Apple map present, headroom exactly 4). Every HDR-making test is parametrized over both kinds. AC6 now checks the unedited HDR version against the system's decode, so a map left unapplied fails instead of drifting by nothing. Two assertions changed shape for the Apple kind, and neither is a loosened tolerance. `fitsToDisplay` expects `GainMapHeadroom.tag(display:ceiling:)` instead of `display`, which is the same value for the ISO file at the three headrooms it passed before, and it adds a per-cell check against Core Image's own rule for both kinds. `regionMatchesFullResolution` keeps `maximum > 1.05` for ISO and checks the Apple tile is over 0.3 stops above its SDR tile, with the reason written. The identity table is installed with `try?`, but a failed install would make AC6's small case equal the default, and `small != Adjustments()` would then fail, so it can't pass silently. "Fails without the fix": the engineer reports 10 of 29 tests failing without it, every one the Apple kind. The structure agrees: without the receiver's dictionary the Apple fixture isn't brightened, and `matchesSystemDecode` compares with the system's decode, where the bright part is two stops up. |
| Q5 | Fixed | `21e4782` | "AC8: for every adjustment…" covers 29 stacks × 2 kinds, at fit (the first frame of a fresh session, interactive, then a settled-size frame) against the settled render at headroom 2, and at 100% (a region tile against the same quarter of the full-resolution render at 1.8), by mean and by a 6 × 4 grid. The limits are at least twice the measured values `status.md` gives, and within AC8's 0.05 stops. |
| Q2 | Fixed | `6ebce7a` | `AdjustmentEditor.canSetHDR` (gain map, no crop session, original online) gates `setHDR`, the check box and `LibraryMenuState.canSetHDR`. `isOffline` reads `onlineVolumeIDs`, which is observed on `LibraryModel`, so the box and the menu state follow a volume going and coming back without a reopen. While offline, the menu shows a dimmed **Turn On HDR**, whatever the choice. That matches design §2.2 ("otherwise … dimmed with the title Turn On HDR"). Undo, Redo, History and Reset All are left to RI-8. |
| Q3 | Layout correct; see C10 and DQ-2 | `60af4cc`, `4b1523e` | `CenteredCaptionRow`'s ideal width is the marks plus twice the wider side (position + 8, or badges + 8), so when `ViewThatFits` picks it the marks are centered and nothing reaches them. Once chosen it takes the proposed width. The badges are `fixedSize`, never squeezed. Only the last fallback can overflow: `status.md` says by a few points, into the caption's 12 pt padding, for a copy with a pick flag at 760 pt. Whether the marks may leave the center is DQ-2. The user guide's new sentence describes the build. |

New finding, fourth pass:

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C10 | Nit (a design call, with DQ-2) | `Sources/PhotoApp/Loupe/LoupeView.swift:1978–2001` (`LoupeCaption.body`), `:2017–2071` (`badges`), `:2110` (`spinnerLabel`) | `ViewThatFits` picks the arrangement from the badges on screen now, and several of them are transient: the caption spinner (0.5 s after input while a sharp frame, a map refinement, a machine-learning frame or the HDR version is awaited), **Original** (`\`), the sharpening and fringe map badges, and **Spot Limit**. `status.md`'s option (a) says only a version badge change (Hide HDR) can move the marks. Any of these can do it too. | Take a loupe width where the second arrangement (marks centered, short badge) fits with nothing to spare, the marks with an **SDR** or **HDR** badge, and no room for a spinner. The band is about twice the spinner's width (a mini `ProgressView` plus 6 pt), because the centered row needs that space on both sides. At 100%, release a slider or pan. 0.5 s later `isAwaitingSharpFrame` shows the spinner, the row no longer fits, and the stars, flag and label jump left, after the position. When the sharp frame lands they jump back. Pressing `\` does the same over a wider band, since **Original** is wider. Before `60af4cc` the marks never moved, though badges could run into them. Found by reading the layout, not run. A fix, if the designer wants one, is option (b) of DQ-2, with the transient slots counted in the reserved width (or the spinner given a fixed slot). | Design §4 ("changing the badge never … moves the culling marks"); DQ-2 |

No `/security-review` for this pass. `GainMap` passes through a dictionary
ImageIO already parsed and adds no parser. `HDRTestImages` writes test files to
temporary folders only. There is no subprocess, no file writing near masters
and no network code.

Fifth pass, 2026-11-25. Reviewed `b391a9c..06338f7` (`4b7ad86`, `39c5057`,
`66a935f`, `06338f7`): the fixes for QA's Q6 and Q7 (`qa.md`, second pass) as
design §20.1 and §20.2 rule them, the user guide and their record in
`status.md` ("QA round 2"). Build and tests at `06338f7`: `swift build` clean;
full `swift test` **1581 tests in 222 suites passed** (100.0 s), the six new
`LoupeCaptionLevelsTests` included. The app was not launched; the widths below
are the engineer's debug-script measurements, which I read against the code.

**Verdict, fifth pass:** ready for the designer's confirmation and QA's third
pass. Q6's guarantee and order and Q7's extra arrangement are built as §20.1
and §20.2 say. One new nit (C11) is a design call: the transient parts are
counted when the caption chooses its level, so a spinner can drop the film
strip button or compact the stars while not shown itself.

| # | Outcome | Commit | Check |
| --- | --- | --- | --- |
| C10 | Closed by the design ruling | — | Design §19.6 chose option (a) and names the transient movers it accepts (Hide HDR, Copy, a map, Show Original, the caption spinner). C11 is what §20.1's longer order adds to it. |
| Q6 (QA) | Fix sound | `4b7ad86` | **Guarantee.** `LoupeCaption` ends in `.padding(.horizontal, 12)`, then `.frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)`, `.frame(height:)`, `.clipped()`, as §20.1 gives it, with the frame outside the padding. When even the last level doesn't fit, its `HStack` of fixed-size parts reports more than the proposal. The flexible frame takes the proposal, aligns the content trailing, and the clip cuts the leading edge, so the version badge and **Offline** stay. That matches the engineer's 20 pt column run (the trailing end of **Offline** shown, the window and the inspector unmoved). **Order.** `ViewThatFits` over `ForEach(LoupeCaptionLevel.all)` takes each level as a candidate, as the measured levels 1 to 13 show. Every part the table can drop or reshape is read from the level in the view: `filtered`, `original`, `spotLimit`, `spinner`, `machineLearning`, `copy`, `filmStripToggle` and `position` through `shows`, the version badge, rating, label name and map badge through `form`, and the mark spacing. The never-dropped parts (version badge, HDR badge, **Offline**, flag, dot, rating) are drawn without a level check, which agrees with the table. Levels 1 and 2 keep the position, which `CenteredCaptionRow`'s three subviews need (tested). From level 3 the row is the position, 8 pt, the marks, a spacer of at least 8 pt and the badges, at spacing 0. That is §20.1's 8 pt in all. The marks and badges have layout priority 1, so a truncating name or map badge gets the room before the spacer does. **Truncation.** `TruncatingSlot`'s ideal width is its minimum (`min(minimumWidth, whole)`), so `ViewThatFits` tests levels 11 to 13 at their narrowest. Laid out, it takes `min(whole, max(floor, offered))`. The label name's slot is clipped, so at level 13 the ellipsis Text drawn wider than 0 pt doesn't spill. The map badge's Text truncates inside its border down to 80 pt. Each badge is now `fixedSize` on its own; the row-wide `fixedSize` that made the row the column's minimum is gone. **Compact marks.** One `star.fill` in the rating color, 2 pt, the digit (`Text(_:format: .number)`, secondary), nothing when unrated, 6 pt between marks; the VoiceOver label and a help tag with the five stars' words. The label name is one line at every level (`lineLimit(1)`, `fixedSize` until level 11), with the "%@ label" help tag. No new UI string. The `LoupeCaptionLevelsTests` table test restates §20.1's rows and fails on any drift in either direction; the guarantee itself is a layout property that PhotoCore can't test, and the debug script's `print loupe` (column, level, caption width) is the right check. |
| Q7 (QA) | Fix sound | `39c5057` | One more arrangement at the end of the pane caption's list, the fifth with `CullingMarks(compact: true, spacing: 6)`. No clamp on the comparison caption, as §20.2 says. `CullingMarks`'s other users keep their behavior through the defaults (spacing 10, not compact, name whole). The name's new `lineLimit(1).fixedSize()` changes nothing in the pane, where the marks were already `fixedSize`. `CaptionBadge`'s new `lineLimit(1)` changes nothing either, since the pane's badge row is `fixedSize`. The engineer's widths fall below `develop`'s in every pair (`status.md`), which is §20.2's condition for keeping the fix. |
| User guide | Matches | `66a935f` | The paragraph is design §20.1's text, word for word, and describes what the build does. |

New code, checked and fine:

- **Debug script.** `print loupe` adds the column (the scroll view's frame), the
  level last shown (`onAppear` of the chosen candidate) and the caption width
  (`onGeometryChange`). `LoupeCaptionReport` is main-actor static state read
  only by the script. `panes [<split> <divider> <x>]` lists split views and can
  move a divider with `setPosition(_:ofDividerAt:)`. It changes no photo, so it
  needs no undo group.
- **Concurrency, rules.** All of it is main-actor view code. No rendering path,
  stack, catalog, sidecar or pipeline version is touched, and no golden moved.
  `LocalizationTests` and `BrandingTests` pass in the full run.
- **Determinism.** `LoupeCaptionLevelsTests` reads a constant table built once
  from constants: no rendering, timing, shared mutable state or pool order. I
  accept that structural argument.

New finding, fifth pass:

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C11 | Nit (a design call) | `Sources/PhotoApp/Loupe/LoupeView.swift:1978–1983` (`ViewThatFits` over the levels), `:2060` (the spinner, shown at levels 1 to 5), `:2048` (Original, to level 11), `:2054` (Spot Limit, to level 9); `Sources/PhotoCore/Browser/LoupeCaptionLevels.swift:108` (level 6) | The caption chooses its level by what is on screen now, transient parts included. A transient part that doesn't fit at the current level pushes the caption to a later one, which can take away something unrelated, or the part itself. The sharpest case is level 6, which drops the spinner and makes the marks compact in one step. | Take a width where level 5 fits with less than about 20 pt to spare, for example a 5-star photo with a flag and label in a narrow window. At 100%, pan or release a slider. 0.5 s later `isAwaitingSharpFrame` adds the spinner, level 5 no longer fits, and level 6 is chosen: the spinner is dropped, so it doesn't appear, and the five stars turn into **★ 5** until the sharp frame lands, then turn back. The same happens on opening a gain-map photo while its HDR version loads for more than 0.5 s. One level higher, the spinner hides the **Film Strip** button (4 → 5) or the position (3 → 4) for the wait. On a gain-map photo with a reason, it can shorten the version badge (1 → 2). Pressing `\` (Original) at a tight width can likewise drop **Copy** and **Filtered** and end at level 12, where Original isn't shown either: the photo changes and the caption shows nothing new. Found by reading the layout and the table; no width was measured for a specific photo. §19.6 accepted marks that move with the spinner; flicker of the stars' form and of a control is more than that. Options for the designer: measure levels 1 to 5 with the spinner's slot reserved whether or not it shows, or drop the spinner before anything else (a level of its own before level 2). | Design §20.1; §19.6's scope |

No `/security-review` for this pass: SwiftUI layout and debug-script commands
only. No parser, subprocess, file writing or network code.
