# Activity popover: design review

Owner: apple-ui-designer. Date: 2026-11-10. Bug fix for issue #56, branch
`bug/activity-popover-anchor` (uncommitted working tree on `550e5f2`).

**Reviewed against.** The **Bug** section of `status.md`; `docs/UI_REDESIGN.md`
§1 (Activity, historical); `docs/features/ui-redesign/design.md` (now §10,
rulings A1 and A2 below); HIG Popovers (read 2026-11-10, markdown version).
Code read: `Sources/PhotoApp/Views/ActivityToolbarItem.swift`,
`Sources/PhotoCore/Browser/ActivityLog.swift`,
`Sources/PhotoApp/Model/LibraryModel.swift` (`setActivityPopoverShown`),
`Sources/PhotoApp/Views/LibraryToolbar.swift` (unchanged; hides the item
through `isVisible`), the `activity` commands in `DebugScript.swift`, and
`ActivityLogTests` in `Tests/PhotoCoreTests/BrowserStateTests.swift`. Not
built or run here: the results below rest on the code and the engineer's
scripts R1 and S1–S6.

## Verdict

**Pass, pending manual checks M1–M8.** The fix is the right one: the
popover's anchor is kept for as long as the popover is open, which is what
HIG Popovers requires, and the rule lives in one tested place
(`ActivityLog.showsItem`) instead of being split between a view's `@State`
and the toolbar. Reading on close is the better rule, and it is now the
recorded one (A1). No violations; one small improvement (I1), not blocking.

## Rulings on the engineer's questions

Recorded in `docs/features/ui-redesign/design.md` §10, which the engineer
can cite.

- **DQ1 → A2. Ruled: as built.** When the last job ends under an open
  popover and posts nothing, the item shows `info.circle` until the popover
  closes, then goes. Closing the popover under the person, an empty capsule,
  or a frozen finished job are all worse (reasons in A2).
- **DQ2 → A1. Ruled: read on close.** This overrides UIR §1's "opening its
  popover marks them read". UIR §1 stays as it is (historical); A1 is the
  current rule. Every message the popover listed, including those posted
  while it was open, is read when it closes, however it closes.

## Requirements

| # | Requirement (source) | Result | Evidence |
|---|---|---|---|
| R1 | Clicking the idle item opens a popover under it (Bug, Expected) | Pass in code, needs manual check | Click only opens (`setActivityPopoverShown(true)`); nothing read on open, so `showsItem` stays true. S1: `popover true on screen true`, button still in place. The look: M1 |
| R2 | The popover's arrow points at the item (HIG Popovers, "Position popovers appropriately") | Needs manual check | `.popover(…, arrowEdge: .bottom)` on the item's button. M1, and M3 for an item that shrinks under the popover |
| R3 | The item goes only after the popover closes (Bug, Expected) | Pass | `showsItem` is `jobsRunning || unseenCount > 0 || isPopoverShown`; tests `openingThePopover…UntilItCloses`, `theItemStaysWhenItsJobEndsUnderAnOpenPopover`; S1, S2, S6 |
| R4 | Messages are read on close, those posted while open included (A1) | Pass | `setPopoverShown(false)` clears `unseenCount` and `unseenHasWarning`; closing one that isn't open reads nothing (test). `markSeen()` removed, so there is one way to read |
| R5 | The idle symbol under an open popover: triangle for an unread warning, else `info.circle` (UIR §1, A2) | Pass in code, needs manual check | Label branch `showsItem(jobsRunning: false)`; S6 for information. Warning: M2 |
| R6 | The item's click toggles: a second click closes the popover (macOS convention for a control that reveals a popover) | Pass | S2: second click closes it and the item goes |
| R7 | Escape and a click outside close the popover and read the messages (HIG Popovers: closes on a click outside) | Pass for click outside; Escape needs manual check | S1 (click in the grid). Escape: M4 |
| R8 | Nothing is left behind when the window changes under an open popover: review mode, full screen, a sheet, a narrow window (no orphaned item, messages not stuck unread) | Needs manual check | The popover state now lives on the model, so a dismissal SwiftUI does not report would leave the item up for good. S5 (grid/loupe switch) passes; M5, M6, M7 |
| R9 | Stop in the popover still works, and the popover stays open over the finished job (UIR §1) | Pass | S3 |
| R10 | VoiceOver: the item and the popover's rows read as before (UIR §1) | Needs manual check | No accessibility code changed; the item now stays under the popover. M8 |
| R11 | User guide terms | Pass | `docs/USER_GUIDE.md` line 107 says "Activity item … with Stop, and the latest messages": matches the UI and says nothing about when messages are read, so it needs no change |
| R12 | No new strings, symbols or chrome | Pass | Same symbols and strings as before; no catalog change |

## Violations

None.

## Improvements (judgment, not blocking)

- **I1. The item's VoiceOver label and tooltip when nothing is unread.** In
  the A2 state the idle item's `accessibilityLabel` and `.help` are the
  newest message's text, which is already read and may be minutes old. That
  is useful while the message is unread (the label then says what is new),
  but in the A2 state it names an old event as if it were current. Prefer
  "Activity" (an existing key) for both when `unseenCount == 0`, and the
  newest message's text only while something is unread. Small; fine in this
  branch or a later one, since the state lasts only while the popover is
  open and focus is in the popover.

## What's working

- One rule for showing the item, in PhotoCore with tests, and the toolbar
  still hides the item through `isVisible`; nothing in the toolbar's
  structure changed.
- No `@State` for the popover: the toolbar and the item read the same value,
  so the anchor can't be hidden behind the popover's back again.
- Reading on close keeps the item's symbol steady under the popover; the
  person sees the item they clicked, not a changed one.
- The debug script's `activity open` refuses while the item is hidden, which
  mirrors what a person can do.

## Fixes for the engineer

None required. I1 is optional.

## Manual checks

For a person at the bundled app (`Scripts/build-app.sh`, launched with
`--library-root` on a scratch library). M1–M8 are for `qa.md`'s "For a
person" list; they cover the engineer's items 1–6.

- **M1. Anchor and look.** Add a small folder, wait until the item shows only
  `info.circle`, click it. The popover opens under the item with its arrow
  pointing at it; the item does not jump, flicker or change symbol while the
  popover opens. Click outside: the popover closes, then the item goes, with
  no visible glitch (no empty capsule left for a frame).
- **M2. Warning.** The same with an unread warning (for example, revert to a
  History entry that can't be applied, or a folder whose import fails): the
  triangle stays under the open popover, and goes with the item on close.
- **M3. Job ends under the popover (A2).** Start an export of many photos,
  open the popover, and let the export finish (or press Stop). The item
  shrinks from progress to an idle symbol: the popover's arrow follows it
  and still points at the item, and the popover's change in height is
  animated rather than looking like a new popover (HIG Popovers, "Provide a
  smooth transition when changing the size of a popover"). Repeat with only
  Rendering previews running (add a large folder, wait past the import, open
  the popover while previews render): when they finish, the item shows
  `info.circle` until the popover closes, then goes.
- **M4. Escape.** With the popover open, press Escape: it closes and, with
  nothing running, the item goes.
- **M5. Review mode and full screen.** With the popover open, press F (review)
  and, separately, enter full screen (⌃⌘F). The popover closes; when you come
  back, the item is gone if nothing is running or unread (not left showing
  with no popover). Open it again afterwards: it opens.
- **M6. Sheets and the menu bar.** With the popover open, press ⇧⌘E (Export…)
  and, separately, open a menu in the menu bar. The popover closes and the
  messages count as read; after the sheet closes the item is gone if nothing
  is running. No popover shows over or under the sheet (HIG Popovers, "Don't
  show another view over a popover").
- **M7. Narrow window.** Make the window narrow enough that toolbar items move
  into the overflow (») menu, with an unread message. Choose Activity there,
  if it is listed: either a popover opens anchored sensibly, or nothing
  happens and the item stays with its message unread. It must never end with
  the messages read and nothing shown, or the item stuck.
- **M8. VoiceOver.** With an unread message, focus the item: VoiceOver reads
  the message. Activate it: focus moves into the popover and its rows read as
  title, text and time. Escape returns focus to the window and the item goes.
  Also note what the item reads in the M3 A2 state (I1).
- macOS 15 and 26 (the engineer's item 6): M1, M3 and M4 again on each, or
  leave to CI plus the owner's choice; the popover was only run on 27.2.
