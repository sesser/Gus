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

### Fourth pass (2026-11-12)

Reviewed: the one commit that changed source or tests since the third pass, "Side by side
comparison: following keeps each pane's own zoom (D12)" (`553fc23`, the head).
Build and tests: `swift build` complete; `swift test` 777 tests in 119 suites passed with 1 known
issue (the Live render session's existing one); `--filter ComparisonTests` 52 tests passed.
Scripted checks ran against a copy of the bundle built from this commit, with its own bundle
identifier and a scratch library from `photobench generate` (two 800 × 600 JPEGs, three
3000 × 2000 raws), every one with `compare animate off` (the display was asleep): the animated
paths and a real pinch were read, not run. The rule was also stepped outside the app:
`ComparisonLink.follow` as committed, copied into a scratch script and driven event by event
the way `ComparisonPane.zoom(by:)` and a pinch drive it.

**Verdict.** C11 is fixed, and C2, D10 and D11 hold. The fix brought two new findings, C12 and
C13 (both Should fix): each puts linked panes back in the state C9 was raised for, one zoomed
in and one fitted at different sizes, after an ordinary zoom gesture on two equal photos. Both
follow D12 as it is written, so they go to the designer first (Questions). Not ready for QA's
second pass until they are ruled. No `CLAUDE.md` rule is broken, no rendering changed,
`/security-review` is still not needed.

| # | Result | How it was confirmed |
|---|---|---|
| C11 | Fixed, `553fc23` | `ComparisonLink.follow` (`Comparison.swift:378-388`) gives the follower its own result, and `ComparisonView.follow` (`ComparisonView.swift:376-386`) does nothing on nil. Run, a raw (left, fit 0.289) beside an 800 × 600 JPEG (right, active, fit 1.000): `zoomstep in` twice gives 1.000 `actualSize` / 1.000 `fit`; `pan 300 200` on the raw leaves the JPEG `1.000 zoom fit rendition preview`, `isZoomed: false`; `Z` gives 1.000 / 1.000, both `actualSize`; a pan there leaves both so; `Z` again 0.289 / 1.000, both `fit`. The reverse: a 3% Option-scroll on the fitted JPEG leaves the raw where it was, a larger one takes both to 1.111, zoomed in. Tests `aPanOnTheZoomedPhotoLeavesTheFittedOneFitted`, `aSmallGestureOnTheFittedPhotoLeavesTheZoomedOneAlone`, `aFollowerBroughtDownToItsFitIsFitted`. |

Regressions looked for, as asked:

- **C2: holds.** `Z` from either side with fits 1.000 and 0.289 (run) and 0.97 (traced): the
  follow when the command ends finds the follower at the magnification it would take, so it
  keeps the zoom the command gave it; the second `Z` fits both.
- **C9: holds for one jump, not for a gesture made of small ones.** See C13. The second pass's
  own run (one 3% Option-scroll, then a second) still gives both fitted, then both zoomed in.
- **D10, D11: unchanged.** `step` changed only in its comment; `stepZoom` still passes no leader.
- **Not linked: unchanged.** Every call of `follow` and `ComparisonLink.follow` is behind
  `linked` (`paneDidScroll`, the end of `animate`, the walk in `update`, `relink`).
- **Walking at 100%.** Run: both at 1.000, `key right`: the new raw opens `1.000 zoom
  actualSize rendition full` at the other pane's unit rect. `show(_:)` has already put a new
  photo at fit, so the state `followerIsNew` passes is the pane's real one.
- **Relinking.** A zoomed-in leader never gives nil, so the inactive pane always gets a result;
  the follow at the animation's end finds it there and keeps it. A fitted leader is unchanged.
- **Nil.** Reached only with a fitted leader and a zoomed-in follower; nothing is shown,
  scrolled or set. That is right in D10's mixed state and wrong in C12's.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C12 | Should fix | `Sources/PhotoCore/Browser/Comparison.swift:382-384`; `Sources/PhotoApp/Loupe/ComparisonView.swift:1055-1071` (`zoom(by:)`), `:1077-1080` (`didEndMagnify`) | "A fitted leader leaves a zoomed-in follower alone" also applies when a gesture has just brought the leader down to fit. An Option-scroll sets the leader's zoom from its magnification before the other pane follows (`adoptMagnification`, then `paneDidScroll`), so on the event that takes it to within 1.05 × fit the follow returns nil and the other pane stays where the event before left it. A regression: before this commit the follower went to its own fit with the leader. | Run: two 3000 × 2000 raws, linked, `Z` (1.000 / 1.000), then `optionscroll 300 400 -10` on the left: left `0.329 zoom fit`, right `1.000 zoom actualSize`. With a wheel's notches in a larger window (fit 0.389; `optionscroll 300 400 -1`, eight times): left `0.389 fit`, right `0.472 actualSize`. So zooming one photo out to fit leaves the other zoomed in, at another size, holding its full-resolution render. A pinch ends the same way when it stops between 1.01 and 1.05 × fit (stepped outside the app, not run: leader `fit`, follower `actualSize`, nil at the end). | Correctness; design §5 (Option-scroll, pinch: both take the same magnification, each stopping at its own fit); a regression of C9 |
| C13 | Should fix | `Sources/PhotoCore/Browser/Comparison.swift:385-387`; `Tests/PhotoCoreTests/ComparisonTests.swift:511-534` | "Unchanged" compares the follower's new magnification with the one the previous event gave it, within 0.01 × its fit. A gesture arrives as many small events, so a slow one never "changes" the follower: it takes every magnification and keeps the zoom it started with. A trackpad Option-scroll of 1 point per event is 0.5% (`ScrollZoom.logFactorPerPoint`), and a pinch that doubles the size in more than about a second is under 1% per event. The test's loop gives the follower each size in one jump from fit, so it does not see this. | Run: two equal raws, linked, both at fit 0.389; `optionscroll 300 400 0.0333` (0.5%) thirty times: left `0.452 zoom actualSize rendition full`, right `0.452 zoom fit rendition preview`, `isZoomed: false` with the right photo active. Then `windowsize 1700 1000`: right refits to 0.456, left stays at 0.452, under its own fit of 0.456; `Z` on the left then fits instead of going to 100%. This is C9's failure again. The other way round (both zoomed in, a slow pinch out to fit) the follower stays `actualSize` at its fit, and C12 then keeps it so. From Q1's state (stepped outside the app) a slow scroll in on the raw carries the fitted JPEG to 1.502 still `fit`. | Correctness; D10's fifth bullet (above its fit a pane is zoomed in); a regression of C9 |

#### Questions

- **For the designer (C12), blocking.** D12's rule 2 leaves a zoomed-in follower alone whenever
  the leader is fitted. It was written for D10's mixed state, where the fitted photo was fitted
  all along. Say what the follower does when a pinch or an Option-scroll has just brought the
  leader down to its fit (§5's second row says it goes to its own fit too), and how the two
  cases are told apart; the two panes' states alone do not say which it is.
- **For the designer (C13), blocking.** D12's rule 1 keeps the follower's zoom "if its
  magnification did not change". Across a gesture's many small events that is always true. Say
  what decides a follower's zoom while it is carried along: for example its own result whenever
  the new magnification is above its fit, and "unchanged" only at its fit (C2's case).
- **For the designer, not blocking.** Rule 3 with rule 1: walking at 100% to a photo no larger
  than its pane (fit 1.000) opens it at 1.000 and fitted, beside a photo zoomed to 1.000, so the
  first `Z` there changes nothing on screen. This follows from D12 ("mixed, with the fitted
  photo active, `Z` takes both to 100%"); traced, not run. Confirm it is meant for a walk too.

#### Not verified (display asleep; for qa-tester or a person)

- C12 and C13 with a real pinch and a real trackpad Option-scroll (momentum included).
- Everything animated, as listed under the second and third passes, now with the follow at the
  end of `Z`, Fit, a click and relinking going through `ComparisonLink.follow`.

#### Checked and fine in this commit

- `ComparisonLink.follow` is pure, in PhotoCore, and what both `ComparisonView.follow` and
  `relink` call; `magnification(following:)` is unchanged. No new string, brand value,
  dependency, migration, launch option or debug-script command; no rendering or cache key change.
- `docs/USER_GUIDE.md` and the `step` comment carry D13's wording (F7). `status.md`'s counts
  match the run (777 tests).

### Merge with develop (#155, #156) (2026-11-12)

Reviewed: the merge `bf3f55e` (parents `ea2ac1c`, this branch, and `811d3af`, develop with
#155 rename-albums-in-place and #156 virtual-copies; merge base `c72d48e`), by
`git show --remerge-diff bf3f55e`, and the files both sides changed. The Ship record committed
on top of it while this ran (`4566230`: `CLAUDE.md`, `README.md`, `docs/roadmap.md`) is docs
only and was not reviewed. Build and tests, on `4566230`: `swift build` complete;
`swift test --filter "LocalizationTests|BrandingTests|ComparisonTests|VirtualCopiesTests"`
89 tests in 4 suites passed. The full run is the main session's (815 tests in 121 suites, 1
known issue). The app was not launched: C14 and C15 are traced, not run.

**Verdict.** The conflicts are resolved correctly and nothing from either side was dropped.
The two features do not yet work together, though: Duplicate and its undo replace the list
without telling the comparison (C14, Blocker), and the comparison names a copy by its
original's file name (C15, Should fix). Neither is a fault of the resolution; no review of
either branch alone could have seen them. Not ready for the pull request until C14 is fixed.
No `CLAUDE.md` rule is broken, no rendering changed, `/security-review` is not needed.

#### The resolutions

- **`Sources/PhotoApp/Model/DebugScript.swift`.** Comments only: the header keeps both blocks,
  the `compare` commands and `print compare`, then `duplicate`, `duplicate fail` and
  `print copies`. Both dispatches are there (`case "compare"`, `"compareclick"`,
  `"duplicate"`), merged by git.
- **`Sources/PhotoUI/Resources/Localizable.xcstrings`.** Compared by key against the base and
  both parents with a script: valid JSON, no duplicate key, `sourceLanguage` and `version`
  unchanged; 1,088 keys = 1,038 in the base + this branch's 32 + develop's 18, none added by
  both, none removed; every value equals the side that changed it, including develop's seven
  edited comments (`Photo`, `Remove “%@” from the library?`, `Removed “%@” from the library.`,
  `Rename Album`, `Rename “%@”`, `Rename “%@”…`, `The name can't be empty.`). Keys are in the
  same sorted order, and the file is byte for byte what the same serializer gives for both
  parents (two-space indent, ` : `, final newline): against develop the merge only adds lines
  (352 added, 0 removed), against this branch it adds 265 and changes the 7 comment lines.
- **`README.md`, `CLAUDE.md`, `docs/roadmap.md`.** Identical to develop's at the merge, as
  intended; Ship has since been run again.
- **Everything else in `Sources`, `Tests`, `Scripts`, `Package.swift`.** 19 files changed only
  on this branch and 33 only on develop are each byte-identical to their side. Eight were
  changed on both: the two above and `PhotoContextMenu`, `FilmStripCell`, `LoupeView`,
  `LibraryModel`, `WindowTitle`, `LibraryCommands`, `LibraryMenuContext`, merged by git with no
  conflict. Read each side's diff against the result: every hunk is there.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C14 | Blocker | `Sources/PhotoApp/Model/LibraryModel.swift:885-900` (`replaceItems`, from #156), against `:819-877` (`apply`); `Sources/PhotoApp/Model/DuplicateActions.swift:34-37`, `:133`, `:149`; `Sources/PhotoApp/Grid/PhotoContextMenu.swift:94-98`, `:193` | Duplicate, its undo and its redo put their list in place with `replaceItems`, which knows nothing of `comparison`: it sets the focus and, in the loupe, a selection of one photo, and never calls `ComparisonRules.reconcile` or `selectComparison` as `apply` does. Nothing keeps Duplicate off while comparing either: `canDuplicateTargets` does not read `isComparing`, so File ▸ Duplicate (⌘D) is enabled and the pane's context menu, built from the shared `addPhotoItems`, now offers it. The comparison rests on "the focus is the active photo and the selection is the pair" (`ComparisonActions.swift:5-9`); after either path that no longer holds. | (a) Comparing A (left, active) and B; ⌘D. `showCopies` calls `replaceItems(…, selecting: [A′], focusVersionID: A′)`: focus and selection are the copy A′, `comparison` is still A and B, the ring is still on A. The window title and the Info tab are A′'s, and `5` or `P` rates A′, a photo in neither pane (`actionTargets` is the focus); a click on the ringed pane does not put it right (`setComparisonActive` returns when the side is already active). (b) In the grid ⌘D on A, `S` (compares A′ with its neighbor), ⌘Z. `hideCopies` takes A′ out of the list; `comparison` still names it. Its pane goes blank (`show(nil)`) with the ring on it and no caption; the arrows and film strip clicks do nothing (`walkComparison` and `comparisonStripClick` need both photos in the list); `A` moves the ring but the focus stays on A, which is not on screen, so culling keys rate it. Only `S` or Esc gets out. Design §4 dims Remove from Album and Remove from Library because "they take a compared photo out from under the comparison", and §6 ends the comparison when a compared photo leaves the source; undo of Duplicate does the same thing unchecked. | Correctness: two sources of truth out of step; side-by-side-comparison AC2 (a rating key changes only the active photo's rating), design §4, §6 |
| C15 | Should fix | `Sources/PhotoApp/Loupe/ComparisonCaption.swift:85`, `:99-118`; `Sources/PhotoApp/Model/ComparisonActions.swift:125`, `:187`, `:205` | #156 named a copy everywhere a photo is named (`PhotoName.display` / `inFull`: window title, grid, VoiceOver labels, removal) and gave the loupe caption a Copy badge. The comparison's own code, written before copies existed, still uses `fileName` and `baseName` and has no badge. | Compare `IMG_0412.RW2` with its copy (what Duplicate is for): both captions read `IMG_0412.RW2`, neither has a Copy badge, so only the position tells them apart, and that is the first thing a narrow caption drops. VoiceOver says "Comparing IMG_0412 and IMG_0412. Left photo active." and "Right photo active: IMG_0412", while a walk to the same copy says "IMG_0412 copy" (`PhotoAccessibility.loupeMove` was updated). The window title does name the active copy. | Correctness: one photo named two ways; virtual-copies design §6.3 |

#### Questions

- **For the designer (C14), blocking.** Neither design covers Duplicate while comparing. Rule
  on it: dimmed and left out of the pane's menu, like Remove (the simplest, and what §4's
  reasoning suggests), or allowed, and then what the comparison shows afterwards (the copy
  takes the active side, or the pair stays and the copy is only added to the list). Whatever
  the ruling, undo and redo of a Duplicate made earlier still reach `replaceItems` while
  comparing, so the engineer's fix has to reconcile the comparison there too (end it on the
  photo that remains, as §6 says for a removal).
- **For the designer (C15).** What a copy's caption shows while comparing: its name
  ("IMG_0412 copy"), the Copy badge, or both, and where the badge goes in the order a narrow
  caption drops things.
- **For the product manager.** The PRD's first non-goal, "Comparing versions of one photo
  (depends on virtual copies, #62…)", is now possible with nothing built for it: an original
  and its copy enter comparison like any two photos (a copy is never half of a pair, so RI-3
  does not refuse it). Say whether that is in scope as it stands, so Ship and the user guide
  describe it or not. The Ship record of `4566230` says nothing either way.

#### Checked and fine

- **Menus.** File has Duplicate (⌘D, by key, `canDuplicate`) before Show in Finder and Remove
  from Library…, which keeps this branch's `!isComparing`; the Rename item is develop's
  (`beginSidebarRename`, `renameTitle(for:)`); View has the three comparison items after Enter
  / Exit Review. `LibraryMenuState` has both sides' fields and both assignments in `init`.
- **Context menus.** Grid: Open in Loupe, Compare Side by Side, then the photo items with
  Duplicate before Export…. Loupe: zoom, Compare, the photo items with Duplicate. Video:
  Compare, no Duplicate (`canDuplicate` is false for a video). `addPhotoItems` has this
  branch's `!isComparing` on Remove from Album, Paste and Apply Preset and develop's Duplicate
  group and separator rule together.
- **`LibraryModel`.** `apply(_:focusVersionID:keepsComparison:)` and `replaceItems` are both
  whole; `showCopies`' fallback (`reloadItems(keepFocus: true)`) goes through `apply` and is
  reconciled. `actionTargets` (`ActionTargets.indices`) and `replaceItems` agree that the loupe
  acts on the focus alone. `comparisonMemory` naming a copy that an undo removed is harmless:
  `rememberedComparison` needs the partner in the list and otherwise falls back.
- **`WindowTitle`.** Develop's `PhotoName.inFull` title and this branch's "Comparing · …"
  subtitle are both there; while comparing the title is the active photo's, a copy's name for
  a copy.
- **`FilmStripCell`.** The compared fill and accessibility value (this branch) and the copy
  mark's layers, layout and `showsCopyMark` (develop) do not touch the same state.
- **`LoupeView`.** The comparison canvas and caption switch, `LoupeRendition`, the `S` key and
  `onActivate` (this branch) with the Copy badge in `LoupeCaption` (develop); `CaptionBadge` is
  no longer private, which C15's fix can use.
- No migration, dependency, brand value, launch option or rendering change comes from the
  resolution; `LocalizationTests` and `BrandingTests` pass.

#### Not verified

- C14 and C15 in the running app. For qa-tester once fixed, and to confirm before:
  `compare on`, `duplicate`, `print compare`, `print copies` (the focus against the active
  side), and `duplicate` in the grid, `compare on`, an undo, `print compare`.

### Fifth pass (2026-11-12)

Reviewed: the one commit that changed source or tests since the merge review, "Side by side
comparison: Duplicate while comparing and a copy's name (D14, D15)" (`6345a70`), against
`design.md` §16 D14 and D15, `review.md` "Fifth pass" F8 and F9 and PRD decision 16. The
commits around it (`af51257`, `9d353b8`, `f12afda`) are docs only. Build and tests, on
`f12afda` (the same source): `swift build` complete;
`swift test --filter "LocalizationTests|BrandingTests|ComparisonTests|VirtualCopiesTests"`
90 tests in 4 suites passed (89 before, plus the new one). The app was not launched: everything
below is read and traced, and the engineer's scripted runs (a) to (d) in `status.md` are for
qa-tester to repeat.

**Verdict.** C14 and C15 are fixed as D14 and D15 rule, and nothing new is broken. One Nit
(C16): the new unit test does not guard the fix. Ready for qa-tester. No `CLAUDE.md` rule is
broken, no rendering, migration, string, dependency or cache key changed, `/security-review`
is not needed.

| # | Result | How it was confirmed |
|---|---|---|
| C14 | Fixed, `6345a70` | **Duplicate is off.** `canDuplicateTargets` (`DuplicateActions.swift:36-39`) requires `!isComparing`. It is the one gate: `duplicateTargets` guards on it, `LibraryMenuState.canDuplicate` reads it (File ▸ Duplicate, ⌘D by key), `PhotoContextMenu.addPhotoItems` leaves the item out and counts it in its separator rule, and the debug script's `duplicate` prints `duplicate unavailable`. **One rule for both writers.** `items` is assigned in two places only, `apply` and `replaceItems` (`LibraryModel.swift:821`, `:932`), and both now read `comparedPairPartners()` before and call `reconcileComparison` after; `apply`'s body is the old code moved, with the same outcomes (`keeps` false still ends with no photo and no announcement). **`replaceItems`, traced.** Kept (every redo; an undo of copies that are not compared; a ⌘D pressed in the single loupe whose copies land after `S`): `ComparisonRules.selection` sets the focus and the pair, the `selecting` and `focusVersionID` arguments are not read, sides, active side and `comparisonHDRHeadroom` are untouched, and the panes see the same version IDs (`ComparisonController.update` shows the same item again, as after a reload). Ended, one copy gone: `remaining` (the active photo if present, else the other) takes the focus, `selected` is emptied, the loupe's rule selects it alone; a copy's original never takes its side (no pair partner for a copy). Ended, both gone: `activeOriginal`, read from the old list before it is replaced (the non-copy item of the active copy's image in the new list), then the undo's own focus, then the first photo; an emptied list goes to the grid. After an undo ended it, a redo finds `comparison` nil and follows virtual-copies §4.3 unchanged. |
| C15 | Fixed, `6345a70` | Caption name `PhotoName.inFull` (`ComparisonCaption.swift:87`). The Copy badge is built exactly as `LoupeCaption`'s (`DuplicateText.badge`, `badgeHelp(item.fileName)`), after HDR and before Offline, inside `badges`, which all four `ViewThatFits` rows call and only HDR is conditional in, so no fallback drops it. `setComparisonActive` and `announceComparison` use `PhotoName.display`; the refusal alerts `PhotoName.inFull`; walking already went through `PhotoAccessibility.loupeMove`. The only `fileName` left in the comparison's code is the badge's tooltip (the master's, as designed) and the debug pane line. No new string; `LocalizationTests` passes. |

Looked for, as asked:

- **`apply` now announces the photo left alone.** Only when the reload keeps the source and a
  compared photo left it (`comparisonEnded`), after the observers are told; `announceLoupePhoto`
  does nothing outside the loupe, so a source emptied to the grid says nothing. This is §10's
  Leaving row for §6's "it leaves the source" (a filter or search change, an undo of Add to
  Album, an outside change, D9). For D9 the removal's own announcement is still made after
  its refreshes (`removalDidFinish`), as before; both are high priority, so which one
  VoiceOver finishes was not checked.
- **Undo registration.** Unchanged: `registerDuplicateUndo` still runs on `persist` and
  registers its opposite. A refused Duplicate returns before anything is registered, so no
  empty undo step. `step.selectionBefore` and `focusBefore` are ignored only while a comparison
  stays or ends; they are not changed, so later undos and redos in the single loupe use them.
- **`replaceItems` when nothing is compared.** The same statements as before, plus two things
  `apply` already did: `comparisonLeaving = nil` (a leaving animation still running when the
  copies land is cut short; the single loupe is underneath) and `comparisonMemory = [:]` when
  the list empties.
- **#62's placement and focus rules.** `DuplicatePlacement.inserting` is untouched and still
  decides where copies go while comparing; only the selection and focus it asks for are set
  aside. `hideCopies`' `endCrop` does nothing while comparing (no crop session is open there).
  `comparisonMemory` naming a copy an undo took is still harmless, and comes back to life if
  the redo restores that copy.
- **#155's rename.** `renameProject`, `renameAlbum` and their undos change `projects` and
  `albums` and never call `replaceItems`; the sidebar refresh that follows reloads the list
  only in Last Import after a new import run, through `apply` with the comparison kept. A
  rename leaves a comparison as it is.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C16 | Nit | `Tests/PhotoCoreTests/ComparisonTests.swift:372-393` (`undoAndRedoOfDuplicateKeepOrEndTheComparison` and its comment) | The test calls only `ComparisonRules.reconcile`, which this commit did not change (`git diff 9d353b8 6345a70 -- Sources/PhotoCore` is empty), so it passes with the fix taken out. What the fix added is in the app target, which has no tests: `!isComparing` in `canDuplicateTargets`, `replaceItems` calling the rule, the arguments it sets aside, and `remaining ?? activeOriginal ?? focusVersionID`. | Remove `reconcileComparison` from `replaceItems`, or `!isComparing` from `canDuplicateTargets`: C14 is back and `swift test` is green. The test is what `review.md` F8.4 asked for, and the other `!isComparing` gates (Remove from Library…) are checked by script too, so this is not a blocker; but then the scripted checks are the only guard. Either move the choice of focus after a replacement into `ComparisonRules` (a pure function of the state, the lists and the undo's focus) and test it there, or say in the test's comment that it pins the rule and that the wiring is checked by script. | Tests: a test that would fail without the change |

#### For qa-tester

- Map D14 to the scripted checks in `status.md` (a) to (d) and `compare on; duplicate`
  (`duplicate unavailable`, `print copies` `canDuplicate false`, no Duplicate in the pane's
  menu), and D15 to `print compare` on a photo beside its copy. They are the only guard (C16).
- One more worth a run: a ⌘D in the single loupe followed at once by `S`, so the copies land
  while comparing (`print compare` unchanged, the copy in the list, focus the active photo).
- `print announcement` after a compared photo leaves by a filter change: the loupe's photo.
