Issue: #63

# Side by side comparison: code review

Owner: code-reviewer. Date: 2026-11-11. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/side-by-side-comparison`, `c72d48e`..`b32190d` (the merge base with `origin/develop`).
Build and tests: `swift build` complete; `swift test` 762 tests in 119 suites passed with 2 known
issues (the Live render session's existing one, and DQ-2's contrast marker). The app was not
launched: findings are from reading the code and tracing it, and say so where that matters.

## Verdict

Ready for the designer's review and QA once C1 and C2 are fixed or ruled on; neither is a blocker
and no `CLAUDE.md` rule is broken. No rendering changed, so no pipeline version bump is owed.
AC6b does not hold as written until DQ-3 / RI-E2 is ruled (see Questions).

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/LibraryModel.swift:820`, `Sources/PhotoApp/Model/LibraryOpsActions.swift:313`, `Sources/PhotoCore/Browser/Comparison.swift:238-243` | `apply` hands every reload's `focusVersionID` to `ComparisonRules.reconcile` as `replacement`. That parameter was meant for the pair's other file (`setPairCovers`), but a removal also passes one: the photo after the last removed photo. `reconcile` puts it in the active side without asking whether it can be compared or whether the person chose it. | Source All Photos, comparing P1 (project X, active) with P2 (project Y). Right-click project X in the sidebar ▸ Remove Project from Library…, confirm. P1 is gone; `RemovalFocus` gives the next photo Q; `reconcile(left: P1, right: P2, replacement: Q)` returns `.kept(left: Q, right: P2)`. The comparison goes on with Q, which can be a video, an offline photo or (pairs shown separately) the other file of P2's pair. Design §6 says the comparison ends and the loupe shows the remaining photo alone; §6 and RI-3 say a side never shows what can't be compared. Traced, not run. | Correctness; design §6, PRD decision 11 |
| C2 | Should fix | `Sources/PhotoApp/Loupe/ComparisonView.swift:368-378` and `:955-965`, `Sources/PhotoCore/Browser/Comparison.swift:289-293` | After every zoom animation `finish` calls `adoptMagnification()` on all panes and then `follow(leader, …)`. `adoptMagnification` calls a pane zoomed only when its magnification is over 1.05 × fit, and `ComparisonLink.magnification` treats a leader at or under 1.001 × fit as "at fit". For a photo whose fit magnification is about 0.95 or more (it is smaller than, or about the size of, its pane) 100% is not told apart from fit. | Linked, active photo smaller than its pane (fit = 1; a 2048 px JPEG in a pane over about 1,080 pt wide on a 2× display, such as review on a 27" display, or any photo under about 800 px wide in a 470 pt pane), the other a 24 MP raw. `Z`: both go to 100%, then `follow` computes `magnification(following: 1, leaderFit: 1, followerFit: 0.12)` = 0.12 and the raw snaps back to fit; the menu still says Zoom to 100%. With fit between 0.953 and 1: `Z` goes to 100%, the pane's `zoom` is reset to `.fit`, and the next `Z` asks for 100% again, so `Z` never returns to fit. AC3 fails for these pairs. The single loupe keeps the zoom the command set, so it has neither problem. Traced. | Correctness; AC3 |
| C3 | Should fix | `Tests/PhotoCoreTests/ComparisonTests.swift:175`, `:192`; `status.md` AC table | The tests `status.md` maps to AC2 and AC4 check only `ComparisonState`'s accessors (`activeVersionID`, `versionIDs`, `switchActive`). Neither would fail if a culling key reached both photos, if undo did not revert it, or if leaving left another selection: that behavior is `actionTargets`, `selectComparison` and `stopComparing` in the app target, covered only by the scripted checks. | Change `LibraryModel.actionTargets` to return the selection in the loupe: both compared photos are rated, and `commandsActOnTheActivePhotoOnly` still passes. | Tests: each testable criterion has a test that fails without the change |
| C4 | Nit | `Sources/PhotoApp/Loupe/ComparisonView.swift:906-918` | `setFrame(animatesFit: true)` (the refit after a film strip change) starts its magnification animation outside `ComparisonController.animate`, which is what holds `followSuspensions` until an animation ends. See the unverified item under Questions for what may follow from it. | See Questions. | Correctness (unverified) |
| C5 | Nit | `Sources/PhotoApp/Loupe/ComparisonView.swift:707-862` against `Sources/PhotoApp/Loupe/LoupeView.swift:324-622` | The pane's copy of the loupe's rendition loading. I compared the two line by line: the same requests, keys, priorities, rendition order and filtering rule, so a pane shows what the loupe shows today. Differences: no tile or editor bookkeeping (right, nothing is edited); `resizeDocument` keeps the visible center where the loupe recenters; `preloadNeighbors` (`:523`) does not prefetch the HDR rendition, so on an EDR display a walked side shows SDR first; the 24 pt fit margin and the 1.05 threshold are literals in both files. Acceptable for this slice; a later fix to one copy will not reach the other. | None today. | Maintainability; file the follow-up issue the engineer proposes |
| C6 | Nit | `Tests/PhotoCoreTests/PaletteContrastTests.swift:103`, `:120`; `Tests/PhotoCoreTests/ComparisonTests.swift:392-402` | Two tests depend on the machine. The ring test resolves `controlAccentColor` as this Mac has it set (hence `isIntermittent`), and the fixed system colors beside it are not the values the accent setting gives (4.47:1 against `systemBlue`'s 5.55:1), so the other seven accent choices are not really checked. `symbolsResolveOnMacOS15` reads a private plist inside `CoreGlyphs.bundle` and fails on `#require` if a macOS release moves or reshapes it; CI on macOS 15 and 26 is the first place that runs. | A red test on another Mac or macOS with no code change. | Tests are deterministic |
| C7 | Nit | `Sources/PhotoApp/Model/LibraryModel.swift:1334-1348` with `:820` | Undoing RAW+JPEG Pair ▸ Show … after switching sides ends the comparison. `setPairCovers` takes its focus from the focused photo, which is now the other side, so no replacement is offered for the side whose file changes back. | Compare pair A (active) with B; Show the JPEG File on A (kept, as tested); press `A`; Undo. A's JPEG version leaves the list, `reconcile` returns `.ended(remaining: B)`, and the loupe shows B alone. | Correctness, minor |
| C8 | Nit | `docs/features/side-by-side-comparison/status.md:18`, `:310-311` | The commits named (`93cca7a`, `cca0b91`, `85d5cb8`, baseline `fc65c9b`) are not ancestors of the branch; after the rebase they are `6aed47b`, `95c8804`, `543f832`, on base `c72d48e`. | A reader can't find the commits. | Docs |

## Questions

For the designer and product manager (the engineer's open items, judged only for correctness):

- **DQ-3 / RI-E2 decides whether AC6b passes.** As built, right after `S` from the loupe the arrows
  and a strip click replace the *left* photo, the one that was in the loupe; AC6b as approved says
  they replace the right one. This is the only open item where the build and an approved criterion
  disagree, so it needs a ruling before QA can pass AC6b. The code is consistent either way.
- **DQ-2.** The default accent ring is 4.47:1 against a required 4.5:1 with Increase Contrast, and
  the test carries a known-issue marker for it. Not a code defect, but the marker should not ship:
  rule on it, then the test either asserts the agreed figure or the color changes.
- **DQ-1, RI-E1, RI-E3.** No correctness issue. Esc does what design §1 and §4 say; AC7's number
  and the long frame when a full-resolution picture arrives are measurements and scope, and that
  frame comes from the same `LoupeImageView.setImage` the single loupe uses.
- **Remove Project from Library… stays enabled while comparing** (File menu and the sidebar row's
  menu), while Remove from Library… and Remove from Album are dimmed. With C1 fixed the reload ends
  the comparison correctly, so this may be fine as it is; say so, or dim it too.

Not verified, for qa-tester (I could not make it concrete without launching the app):

- **Film strip toggled while comparing, linked, both at fit (C4).** If the animated refit posts
  clip-view bounds changes while it runs, as the comments on `animate` and on the single loupe's
  `applyZoom` say such animations do, each pane follows the other mid-animation. When the strip
  appears the panes shrink, the leader's magnification is above its new fit, and the follower would
  be set to it and adopt `.actualSize`, which starts a full-resolution render of a photo that is at
  fit. Check: `compare on; filmstrip off; wait 1; filmstrip on; wait 2; print compare`. Each pane
  should report `zoom fit` and a rendition that is not `full`.

## Checked and fine

- **Rendering and caches.** No file under `Edits/`, `Preview/` or `Kernels/` changed; no golden,
  tolerance or `PreviewCacheKey` changed. The panes call `PreviewService` with the loupe's requests.
- **Main thread.** Panes decode nothing: `memoryCachedImage` for the immediate picture, async
  `image`, `hdrImage` and `fullResolutionImage` for the rest, results applied on the main actor
  behind a `shownKey` check; tasks are cancelled on a new photo and at teardown.
- **Memory.** One full-resolution picture per pane, released at teardown; the service's one-entry
  cache shares one of them. The editor's copy is released on entering: `LoupeController.tearDown`
  calls `editor.follow(nil)`, and `finishSession` drops the session and the region renderer.
- **Swift 6.** No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` added. The new
  types are main-actor; the display link and observers are removed in `tearDown`.
- **Single loupe.** `LoupeRendition` in PhotoCore has the same cases, order and `isHDR` (the old
  enum is now a typealias). `LoupeScrollView.onActivate` is nil for the loupe, so its clicks are
  unchanged. The `ZStack` in `LoupeView`, `setFocus`, `apply`, `perform` and the film strip's
  refresh take the old path when `comparison` is nil.
- **Active photo only.** `selection` is `private(set)` and every command goes through
  `actionTargets`, which is the focus in the loupe. Copy Adjustments reads the catalog when the
  editor follows nothing. Paste and Apply Preset, which bypass the editor, are off in the menu
  bar, toolbar and context menus; the editor's own commands are off because its state is idle.
- **Undo.** Culling keeps its existing step on the `persist` chain; an edit's undo works on a
  compared photo (`apply(_:toVersion:)` takes any version) and the pane reloads on the new hash.
  The new debug-script commands change no photo, so they need no undo group.
- **Keys.** `S` and `A` clash with nothing in `CullingKeymap`, `NavigationKey`, the loupe's handler
  or `LibraryCommands`. Both menu items use `canByKey`; `isBrowser` knows `ComparisonHostView`.
  `S` during a crop does nothing; `S` on a video shows the alert.
- **Menus** read `LibraryMenuState` through the focused value; nothing new is passed into `Commands`.
- **Localization and branding.** 32 new keys in `Localizable.xcstrings`; `LocalizationTests` and
  `BrandingTests` pass. The defaults key `compare.linksViews` and toolbar item `compare` are generic.
- **Other rules.** No migration, catalog or edit-stack change, no new dependency, no launch
  option, no SwiftUI `ScrollView` (the Adjust tab's state is a `ContentUnavailableView`).
- **Security.** No parser, subprocess, network code or file writing outside the library.
  `photobench compare` reads two raws and writes its synthetic ones to a temporary folder.
  `/security-review` is not needed.

## Follow-up

### Second pass (2026-11-12)

Reviewed: `a009995`..`16fb7ac` ("Side by side comparison: review fixes"), the one commit that
changed source or tests. Build and tests: `swift build` complete; `swift test` 768 tests in 119
suites passed with 1 known issue (the Live render session's existing one; DQ-2's marker is gone).
Scripted checks ran against a copy of the bundle built from this commit, with its own bundle
identifier and a scratch library from `photobench generate`. The display was asleep, so every
scripted check used `compare animate off`: the animated paths were read, not run.

**Verdict.** C1 to C8 are closed. The C2 change brought one new finding, C9 (Should fix), and
there is one nit, C10. No `CLAUDE.md` rule is broken, no rendering changed, and
`/security-review` is still not needed. C9 should go to the engineer before QA, so QA does not
check linked zoom twice.

| # | Result | How it was confirmed |
|---|---|---|
| C1 | Fixed, `16fb7ac` | `reconcile` takes no reload focus (`Comparison.swift:270-281`); `apply` offers only the pair's other file, read from the list before it is replaced (`LibraryModel.swift:814-842`). Test `aRemovedPhotosNeighbourNeverTakesItsSide`. Scripted: comparing two raws, `compare active left; removephotos; alert press Remove`: `compare off`, `mode loupe`, the loupe on the remaining photo alone. |
| C2 | Fixed, `16fb7ac`; see C9 | A pane keeps the zoom a command gives it; `follow` reads `ComparisonLink.isFitted`. Test `aPhotoAsSmallAsItsPaneStillTakesTheOtherTo100Percent`. Scripted with an 800 × 600 JPEG (fit 1.000) beside a HEIC (fit 0.290): `Z` gives 1.000 and 1.000 with `isZoomed: true`, `Z` again 1.000 and 0.290 with `isZoomed: false`, with either side active. |
| C3 | Fixed where it can be unit tested, `16fb7ac`; accepted | `ActionTargets.indices` and `ComparisonRules.selection` are in PhotoCore and are what `actionTargets`, `selectComparison` and `apply` call; `commandsActOnTheActivePhotoOnly` and `theGridActsOnItsSelection` fail if the rule changes. Undo and the single loupe coming back stay scripted only, and `status.md` now says so. |
| C4 | Fixed by reading, `16fb7ac`; the animated run is still open | Both refits are one animation group in `layoutPanes` and `followSuspensions` is held until its completion handler (`ComparisonView.swift:194-208`). With `compare animate off`, `filmstrip off; filmstrip on; print compare` gives `zoom fit`, `rendition preview` on both panes. The check in Questions needs the display awake: for qa-tester or a person. |
| C5 | Stands as the proposed follow-up issue | One difference closed: `preloadNeighbors` prefetches the HDR rendition exactly as `LoupeView.preloadNeighbors` does. |
| C6 | Fixed, `16fb7ac` | The ring test asserts 3:1 (design §16 D2: the requirement changed by ruling, not a tolerance loosened to pass) against a lowest measured 4.47:1, so the accent this Mac has set can't fail it. `symbolsResolve` always runs; `symbolsDateFromBeforeMacOS15` skips with a reason where the private list is missing or reshaped (it ran here, macOS 27.2.1). |
| C7 | Fixed, `16fb7ac` | Either side follows its pair's other file. Test `aSideFollowsItsPairsOtherFile`. Scripted: `compare active left; pairfile jpeg; compare active right; undo; redo`: the comparison and the active side stay each time. |
| C8 | Fixed, `16fb7ac` | `status.md` names commits by subject. |

Designer's F1 to F3, checked for correctness only: F1 (`entry` makes the partner active with one
photo and returns a remembered state unchanged; `enteringSide` moves the pane the loupe's photo
goes to) passes its tests and the scripted `S`, `S` run (same sides, same active photo, after `A`
and after a walk); F2 (`concernsOnePhoto`) and F3 (3:1) pass their tests.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C9 | Should fix | `Sources/PhotoApp/Loupe/ComparisonView.swift:363-373` (`follow`), `:1008-1018` (`adoptMagnification`); `Sources/PhotoCore/Browser/Comparison.swift:320`, `:333-335` | Two thresholds now decide "at fit". A pane a gesture ends on calls itself fitted up to 1.05 × fit (`adoptMagnification`); the pane that follows it is told `.fit` only when the leader is within 1.001 × fit (`isFitted`), otherwise `.actualSize`. Before this commit the follower took its zoom from its own magnification with the same 1.05, so the two agreed. A regression from the C2 change. | Run: two 3000 × 2000 raws, linked, both at fit (0.329). `optionscroll 400 400 0.2` (a 3% Option-scroll on the left pane): left `magnification 0.339 zoom fit rendition preview`, right `magnification 0.339 zoom actualSize rendition full`, menu state `isZoomed: true` with the right photo active. So a small scroll or pinch renders one photo at full resolution and holds it. Then `windowsize 1500 900`: left refits to 0.389, right stays at 0.339, below its own fit of 0.389: linked panes at different sizes. Then `Z` with the right photo active goes to fit, not to 100%. A pinch ends through the same two calls (`didEndMagnify`); not run. | Correctness; AC3 |
| C10 | Nit | `Sources/PhotoApp/Model/LibraryModel.swift:835-836`; `Sources/PhotoApp/Model/ComparisonActions.swift:94-105` | The remembered pair is recorded on entering, switching sides and walking, but not when a reload changes a side's version (RAW+JPEG Pair ▸ Show …, C7's path). The memory then names a version that is no longer in the list, and `rememberedComparison` finds nothing. The old `comparisonPartners` had the same gap; D3 and AC6c now promise more. | Run: comparing RAW_00005 (left) with a grouped pair (right, active); `pairfile raw; key s; key s`: the comparison comes back as the pair on the left with RAW_00004 on the right, not the two that were left. Also, traced: the memory is cleared only in `closeLoupe`, and `apply` goes to the grid on an empty source without it (`LibraryModel.swift:857`). | Correctness, minor; AC6c |

#### Questions

- **For the designer, not blocking.** Linked, with the active photo no larger than its pane (fit
  1.000): ⌘− from 200% is that photo's fit, so the other photo goes from 200% straight to its own
  fit and never stops at 100% (run: 2.000 and 2.000, then 1.000 and 0.290). `Z` still reaches
  100% on both. Say whether that is what §5's "at the low end each stops at its own fit" means.

#### Not verified (display asleep; for qa-tester or a person)

- `Z`, zoom steps and relinking with animation on (C2's fix through the completion handler), the
  entering animation into the right pane (F1), and C4's check as written under Questions above.
- C9 with a real pinch.

#### Checked and fine in this commit

- `ActionTargets` (PhotoCore, no AppKit, a neutral name) is the old rule moved, not changed.
- `apply` still ignores a reload's focus while the comparison is kept, as before; when it ends,
  the focus is the remaining photo, or the reload's when neither remains.
- `compare animate on|off` sets a main-actor static the app never writes; it changes no photo, so
  it needs no undo group. `panbench`'s display-link probe invalidates its link and gives up after
  2 s.
- No new string without a catalog entry (`LocalizationTests`), no brand value, no new dependency,
  no migration, no rendering or cache key change.

### Third pass (2026-11-12)

Reviewed: the two commits that changed source or tests since the second pass, by subject (the
branch's hashes were rewritten during this pass): "Side by side comparison: second-pass fixes"
(`222e274`) and "Side by side comparison: linked Zoom In (D11)" (`b7a0024`); head `ce59380`.
Build and tests: `swift build` complete; `swift test` 773 tests in 119 suites passed with 1
known issue (the Live render session's existing one), once on the first commit's sources and
again at the head with a clean tree. The app was not launched in this pass. The step rule was
also run outside the app: `LoupeZoomSteps` and `ComparisonLink` as committed, copied into a
scratch script and stepped through several pairs of fits (the sequences quoted below). The
engineer's scripted runs in `status.md` were not repeated: everything in the app target
(`follow`, `stepZoom`, `publishZoom`, `apply`) is confirmed by reading, and the animated paths
are still unrun (display asleep).

**Verdict.** C9, C10, D10 / F4 and D11 / F5 are confirmed. One new nit, C11, and one question
for the designer; neither blocks QA. No `CLAUDE.md` rule is broken, no rendering changed,
`/security-review` is still not needed. Ready for qa-tester.

| # | Result | How it was confirmed |
|---|---|---|
| C9 | Fixed, "second-pass fixes" | One rule and one figure: `ComparisonLink.isZoomedIn` with `zoomedInThreshold` 1.05 (`Comparison.swift:328-343`); `isFitted` and the 1.001 tolerance are gone. `adoptMagnification` (`ComparisonView.swift:1036-1041`), `ComparisonPane.isZoomedIn` (`:988`) and `follow` (`:363-375`) all ask it, and the follower takes the leader's answer. The second pass's run, traced: fit 0.329, a 3% Option-scroll gives the leader 0.339 `.fit` and the follower 0.329 × 1.03 = 0.339 `.fit`, so nothing renders at full resolution, a resize refits both (`setFrame` refits a `.fit` pane) and `Z` goes to 100%. C2 still holds: a pane a command zoomed in stays zoomed in at any magnification. Tests `aSmallGestureLeavesBothLinkedPanesFitted`, `aResizeAfterASmallGestureRefitsBothLinkedPanes` (the rule only; the resize itself is the app's and is covered by the engineer's script). |
| C10 | Fixed, "second-pass fixes" | `apply` (`LibraryModel.swift:836-844`): when a reload gives a side its pair's other file, the old version's entry is dropped and both sides' entries become the new state, so `rememberedComparison` finds the pair under the file now shown; the same on undo. An emptied source clears the memory with the loupe (`:865-869`), as `closeLoupe` does. Entries other photos hold for the old file find no partner and fall back to the next photo, as before. No unit test (app target); the engineer's script covers it. |
| D10 / F4 | Confirmed, "second-pass fixes" | `ComparisonLink.step` (`Comparison.swift:391`); `stepZoom` passes no leader to `animate`, so nothing overrides each pane's own result at the end; `publishZoom` takes `canZoomIn` / `canZoomOut` from the same function, and the View menu and both context menus read only those two flags (`LibraryCommands.swift:238-241`, `PhotoContextMenu.swift:34-35`, `:100-101`). Run: fits 1.000 and 0.290 from 2.000, either side active: 1.000 / 1.000, 1.000 / 0.500, 1.000 / 0.290, then dimmed. Test `aLinkedZoomOutStepNeverSkips100PercentOnOneSide`. |
| D11 / F5 | Confirmed, "linked Zoom In (D11)" | Zoom In lands on the smallest of the panes' next steps (`targets.min()`), Zoom Out still on the active pane's first. Run, either side active: fits 1.000 / 0.290 from fit give 1.000 / 0.500, 1.000 / 1.000, 2.000 / 2.000 and ⌘− goes back the same way; equal fits step exactly as the single loupe (0.5, 1, 2, 4, 8, dimmed); panes at 2.000 and 0.500 give 2.000 / 1.000, 2.000 / 2.000, 4.000 / 4.000, so the guard at `:406` never takes a pane back out. No pane under 100% can pass it: its own next step is at most 1 and the landing is the smallest. The pane whose step is the smallest always moves, so an enabled Zoom In always does something, and it is dimmed only when every pane is at the top. Test `aLinkedZoomInStepTakesBothToTheSameMagnification`. |

Also checked, as asked:

- **Not linked: unchanged.** `reached(by:)` gives the one pane, so `step` is `LoupeZoomSteps` on
  it (run: 0.290, 0.5, 1, 2, 4, 8, dimmed, and back; the guard can't fire for one pane). Zoom Out
  on a fitted pane is nil, which the menu already required (`zoom != .fit`). Test
  `anUnlinkedStepIsTheLoupes`.
- **`Z`, Fit and clicks: unchanged.** `toggleZoom` and `setZoom(_:on:unit:)` are not in either
  diff; they still pass a leader, and `follow` at the end gives 100% / 100% (leader zoomed in) or
  each pane's own fit (ratio 1).
- **Menu state during an animated step.** `publishZoom(magnifications:)` uses the magnifications
  the step is heading for and the zooms already set, then publishes again when the animation ends.
- **Docs.** `docs/USER_GUIDE.md` says what D10 and D11 do. `status.md`'s counts match the run.

#### New finding

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C11 | Nit | `Sources/PhotoApp/Loupe/ComparisonView.swift:363-375` (`follow`) against `Sources/PhotoCore/Browser/Comparison.swift:391-409` (`step`) | Two rules now set a linked pane's zoom state. A step gives each pane its own (D10: "a pane at its fit reports fit"); `follow` gives the follower the leader's. D10 and D11 leave one pane at its fit and the other zoomed in (any two photos with different fits, on the way in and out), and the first pan there replaces the step's answer. | Traced, not run. Fits 1.000 (active) and 0.290, linked, both at fit; ⌘=: 1.000 `fit` / 0.500 `actualSize`, menu "Zoom to 100%". Scroll the other photo: `follow` gives the active pane `magnification(following: 0.5, …, followerFit: 1)` = 1.000 with zoom `.actualSize`. It now reports zoomed at its fit: the menu says "Zoom to Fit", `Z` takes both to fit instead of 100%, the pane starts its full-resolution render (for a landscape raw beside a portrait one, fits 0.329 / 0.220 at 0.329 / 0.250, a 24 MP render of a fitted photo), and a larger window does not refit it until the next scroll. The reverse: a 3% Option-scroll or the start of a pinch on the fitted pane sends the other from 0.500 to 0.29 × 1.03 = 0.299 `.fit`, and past 5% up to the leader's magnification, so a zoom in on one photo first zooms the other out. The next step or `Z` puts both right again. | Correctness, minor: state set by two rules; design §16 D10, fifth bullet |

#### Questions

- **For the designer, not blocking (with C11).** In the state a step leaves with one pane at its
  fit and the other zoomed in, say what a pan or a small pinch on either pane does to the other
  pane's zoom state: D10's "each pane's zoom state follows its result" or C2's "linked panes share
  the zoom". The engineer needs that to fix C11.
- **For the designer, not blocking.** D11 says Zoom In retraces Zoom Out. It does when the fitted
  pane's fit is itself a step (1.000). When it is not, Zoom Out with that pane active stops once
  more, at its fit, and Zoom In has no such stop. Run, fits 0.329 (active) and 0.220: ⌘= from fit
  gives 0.329 / 0.250, then 0.500 / 0.500; ⌘− from there gives 0.329 / 0.329, then 0.329 / 0.250,
  then 0.329 / 0.220. With the other photo active ⌘− retraces exactly. 100% is never skipped
  either way. Accept, or say which side changes.

#### Not verified (for qa-tester or a person)

- The engineer's scripted runs for C9, C10, D10 and D11, which this pass did not repeat, and
  C11's state: after `zoomstep in` from fit with two photos of different fits, `pan` the zoomed
  photo, then `print compare` and `print menustate` (the fitted pane's `zoom` and `isZoomed`).
- Everything animated, as listed under the second pass, now including ⌘= / ⌘−: whether a bounds
  change arriving after an animated step's completion makes a pane follow (C11's state without a
  pan), and C9 with a real pinch.
