# Info tab fields run under a legacy scroller: code review

Owner: code-reviewer. Date: 2026-11-22. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/info-tab-legacy-scroller`, `develop`..`9825316` (one commit). Build and tests: `swift build` clean; `swift test` not re-run (the commit changes one PhotoApp file, which no test target imports; the engineer records 1452 tests passing and a clean Swift 6.2.4 `--build-tests`). `Scripts/build-app.sh` built the bundle at this commit.

## Verdict
Ready for the next step (qa-tester). The one-override fix is small and correct, it reproduces and fixes the bug here, and I found nothing that needs changing; two nits below.

## Findings
| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Nit | `Sources/PhotoApp/Views/AppKitScrollView.swift:89-93` | Every width change queues its own `DispatchQueue.main.async` closure. `NSScrollView.tile` can resize the clip view more than once in one pass, so several closures can queue for one turn, each doing the same `needsLayout = true`. | None visible: the flag is idempotent and the work is four constraints. Only wasted closures. A pending flag would coalesce them. | None |
| C2 | Nit | `docs/features/info-tab-legacy-scroller/status.md`, Root cause | Two statements have no evidence in the file: "a window resize does not touch it either", and that the flag "is cleared at the end of the pass in progress". They are a hypothesis that fits the experiments (clip `needsLayout` fixes it, document `needsLayout` and a synchronous mark do not), not a shown mechanism. | None for the fix, which is checked by its effect. Only the account is stronger than its evidence. | None |

## Questions
None for the designer or product manager.

## Checked and fine
- **Reproduced and fixed here.** I built the bundle at `HEAD~1` and at `HEAD` (own bundle ids, ad hoc signed, a fresh `photobench` library copy per run, always `--library-root`) and ran the engineer's script with `AppleShowScrollBars` forced per copy:
  - legacy, before: Info `visible 283 controls 12...288 widest NSTextField 276 overflow`, also on Info again after Adjust and scroll to bottom.
  - legacy, after: Info `controls 12...271 … 259 fits`, in both Info visits.
  - Adjust tab legacy `controls 8...275 … 259 fits` before and after; overlay (`WhenScrolling`) before and after identical (`visible 300`, `12...288`, `fits`).
  This matches status.md's table. These are separate state checks, not a timing race, so I count them as the before/after evidence rather than as a determinism claim; the fix defers by one run-loop turn, which by construction runs after the pass that resized the clip view.
- **Other users of `FlippedClipView`.** Only `AppKitScrollView` creates it (the Info tab in `InspectorView.swift:68` and two Adjust scroll views in `AdjustView.swift:21`, `:74`); `DebugScript` only tests `contentView is FlippedClipView`. All are inspector scroll views, so the change reaches nothing else. The importer and `PhotoUI` do not use it.
- **No loop.** `setFrameSize` queues a closure only when the width actually differs, so an unchanged width ends the chain. A loop needs scroller appears, clip narrows, document re-laid at the narrower width, content gets shorter, scroller goes, clip widens, and so on. A narrower column makes wrapped text equal or taller, so the scroller stays once shown; a column too short for a scroller at the wider width never shows one. Not tested with content built to sit at the threshold; I judge a flip-flop unlikely (it would need text that wraps shorter when narrower).
- **Cost during an inspector-edge drag.** One extra `needsLayout` per width change, on a clip view with four constraints; the window lays out each frame anyway. Not measured (the script cannot set the pane width); the engineer says so under Not verified.
- **Swift 6 concurrency.** `swift build` is clean in language mode 6 and the engineer's Xcode 26.3 `--build-tests` is clean. The closure captures `self` weakly, runs on the main queue, and touches only the main-actor view's `needsLayout`. No new `@unchecked Sendable` or `nonisolated(unsafe)`.
- **Override correctness.** It calls `super.setFrameSize` first, compares against the old `frame.width` (height-only changes do nothing), and leaves bounds and flipping alone.
- **Tests.** PhotoApp has no test target (`Package.swift`: `PhotoCoreTests` only), so the engineer's statement holds, and the repository's `inspectorwidth` check is the debug script (`InspectorSegmentedWidthTests` covers only the pure verdict in PhotoCore). The Bug section names that check, with `overflow` before and `fits` after, and I reproduced both. For qa.md: this check is manual only; there is no automated guard against a regression.
- **Project rules.** No `ScrollView` introduced; no strings, branding, catalog, migration, rendering, pipeline-version, golden or dependency change. `docs/USER_GUIDE.md` does not describe this layout.

## Follow-up
Pending the engineer's reply (nits only; none need fixing).
