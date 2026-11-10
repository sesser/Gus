# Activity popover: code review

Owner: code-reviewer. Date: 2026-11-10. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/activity-popover-anchor`, the uncommitted working tree on
`550e5f2` (the merge base with `develop`; the branch has no commits of its
own yet). The code under review is `git diff develop -- Sources Tests`,
SHA-256 `fb402fbc…d5716a3`, the same at the start and the end of this pass
(the designer's `review.md` and `ui-redesign/design.md` §10 landed while it
ran; no source moved). Spec: the **Bug** section of `status.md`, issue #56.
Build and tests: `swift build` clean, and a from-scratch build in a separate
build folder gave no warnings; `swift test` 693 tests in 116 suites passed,
1 known issue (`LiveSessionTests.swift:258`, not this branch). The app was
not launched (qa-tester's job).

## Verdict

Ready for qa-tester. No blocker and nothing the engineer must change: the fix
removes the cause the Bug section names, the rule sits in PhotoCore with
tests that fail under the old behavior, and no `CLAUDE.md` rule is touched.
One nit in the debug script, and one question (Q1) that QA should settle by
script before sign-off, because its answer decides whether a new failure
mode exists.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Nit | `Sources/PhotoApp/Model/DebugScript.swift:161` (used at 545, 552, 1056) | `popoverWindow` is the first visible window whose class name contains "Popover", not the Activity item's popover. The library window has a second popover, keyword entry (`MainView.swift:90`, opened by `keyentry` or ⌘K) | `keyentry; print activity` prints `popover false on screen true` with no Activity popover up, and `activity snapshot` / `activity click` then act on the keyword panel. `on screen` is the value QA reads to tell the model's state from what AppKit shows (Q1), so a script that has keyword entry open reads it wrong. Either tell the two apart, or say in the command's comment that `on screen` means any popover | Correctness (debug tool only) |

## Questions

- **Q1 (qa-tester to settle by script; the engineer if any probe fails).
  Can the popover leave the screen without SwiftUI calling the binding's
  setter?** Before this change the popover's state was view-local `@State`
  and nothing depended on it. Now `ActivityLog.isPopoverShown` decides
  whether the item shows and when messages are read, and it is a second
  record of something AppKit owns. If it is ever `true` with no popover on
  screen, the item cannot recover: the click calls `setPopoverShown(true)`,
  the guard at `ActivityLog.swift:47` returns because the value is already
  `true`, nothing changes, so SwiftUI has nothing to present; the item stays
  in the toolbar, its messages stay unread, and clicking it does nothing
  until quit. That is worse than issue #56, but I could not show a way into
  that state from the code alone, and the engineer saw SwiftUI set the state
  back in the one case tried (the item hidden). The designer lists the same
  risk as R8 with manual checks M5–M7; three of them can be scripted, since
  `print activity` prints both values. Launched with `open -W -n … --args
  --library-root …` so `menupress` has a key window, after an idle unread
  message:
  - `activity open; menupress Hide Toolbar; wait 1; print activity; menupress Show Toolbar; wait 1; print activity`
  - `selectall; activity open; export window; wait 1; print activity; export close; wait 1; print activity`
  - `activity open; review on; print activity; review off; print activity` (takes over the display)
  - by hand: the overflow menu of a narrow window (M7), and closing the
    library window with the Import window open, then Window ▸ Library.

  Pass: every line shows `popover` and `on screen` equal, and after the
  popover is gone `visible false … unseen 0`. Any line with `popover true on
  screen false` is a Blocker for the engineer (the state then needs a way
  back that does not depend on SwiftUI reporting the dismissal). Keep C1 in
  mind: no keyword entry open during these.
- **Q2 (qa-tester; not introduced by this diff).** The designer's R6 (a
  second click on the item closes the popover) rests on S2, the idle case,
  where the item goes away on the mouse down. While a job runs the item
  stays, so the mouse up can still run the button's action, which opens.
  The action did the same before the fix, so this is not a regression, but
  it is unchecked: S3's script with a second `click` on the item, then
  `print activity`, shows whether it closes or closes and opens again.

Nothing for the product manager. Nothing new for the designer: DQ1 and DQ2
are ruled (A2 and A1 in `ui-redesign/design.md` §10); `status.md` still
lists them as open.

## Checked and fine

- **Root cause and fix.** The click no longer reads the messages
  (`ActivityToolbarItem.swift:36`); `showsItem` keeps the item while the
  popover is open; reading happens only in `setPopoverShown(false)`, which
  the binding's setter calls on dismissal. `markSeen()` and
  `markActivitySeen()` are gone and nothing else called them (grep over
  `Sources`, `Tests`), so there is one way to read messages.
  `LibraryToolbar` is unchanged and hides through the same `isVisible`.
  This matches issue #56's expected behavior and its suggested direction.
- **The named tests fail without the fix.** Traced against the old rule
  (read on open, visibility ignoring the popover):
  `openingThePopoverLeavesTheItemAndItsMessagesUntilItCloses` fails six
  expectations (lines 188, 190, 191, 195, 198, 200 of
  `BrowserStateTests.swift`) and `theItemStaysWhenItsJobEndsUnderAnOpenPopover`
  one (210): seven, as `status.md` says. They check what the Bug section
  describes. Swift Testing, deterministic, no sleeps; no tolerance or golden
  touched. The view's wiring (the binding, the click) has no unit test
  because `PhotoApp` has no test target; S1 is its check, for `qa.md`.
- **Edge cases in `ActivityLog`.** Closing a popover that is not open reads
  nothing (tested); messages posted while open are read on close (tested);
  the job ending under an open popover keeps the item (tested). `ActivityLog`
  is still `Hashable` and `Sendable`; nothing compares or hashes it.
- **Concurrency.** Everything touched is main-actor UI state or a value
  type; no new task, no decoding or database access. The binding's closures
  build under Swift 6 with no warning.
- **Debug script.** The new `activity` commands change no photos, so they
  need no undo group (`changing`); no new launch option. `activity open`
  refuses while the item is hidden, and the header comment describes the
  commands as built. The sleeps follow the file's other commands.
- **Strings and branding.** No new key: `"Activity"` already has a catalog
  entry (`LocalizationTests` and `BrandingTests` pass). No persisted name,
  migration, catalog write, edit stack, rendering or pipeline version
  touched; no new dependency; nothing from another application.
- **Docs.** `docs/USER_GUIDE.md` line 107 says nothing about when messages
  are read, so it needs no change. `status.md`'s Bug section agrees with the
  issue; its one unexplained part of the report ("shows only after changing
  photos") is stated as such and the fix does not rest on it.
- **Security.** No parser, subprocess or network code. The one new file
  write is `activity snapshot <file.png>`, a debug-script command that
  writes a PNG where the person launching the app says, through the same
  `WindowSnapshot.write` as `snapshot` and `windowshot`.

## Follow-up

None yet. The designer's optional I1 (the idle item's label and tooltip when
nothing is unread), C1, or any fix from Q1 is a source change and takes a
second pass here.
