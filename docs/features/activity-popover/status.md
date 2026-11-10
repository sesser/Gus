# Activity popover: implementation status

Owner: swift-macos-engineer. Bug fix (no `prd.md` or `design.md`,
`docs/WORKFLOW.md` "Bug fixes") for issue #56 and the follow-up
`bug/activity-popover` named in the roadmap's edit-history row. Branch
`bug/activity-popover-anchor`, cut from `develop` at `550e5f2` (the branch
name `bug/activity-popover` belongs to an older worktree, left alone).
Nothing is committed yet.

**Status: Done.** Next: code-reviewer, then the designer (the fix changes
when the toolbar item shows; DQ1 and DQ2 below are for them), then
qa-tester.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `550e5f2`).
1. Get an unread Activity message with nothing running: add a small folder
   (File ▸ Add Folder Without Copying…) and wait until the toolbar's
   Activity item shows only its info circle. A warning (a history entry that
   can't be applied, say) does the same with the triangle.
2. Click the item.

**Expected.** A popover opens under the item and lists the recent messages.
The item goes away only after the popover closes.

**Actual.** No popover. The item vanishes and the messages count as read.

**Root cause** (confirmed, script R1 below). The item's click ran
`showsPopover = true` and then `model.markActivitySeen()`
(`Sources/PhotoApp/Views/ActivityToolbarItem.swift`). Marking the messages
read set `activity.unseenCount` to 0, so with no job running
`ActivityToolbarItem.isVisible(model)` became false in the same update, and
`LibraryToolbar` hid the toolbar item (`.hidden(!isVisible)`). The hidden
item is the popover's anchor, so SwiftUI had nothing to present from.
`showsPopover` was `@State` inside the item, where `LibraryToolbar` could
not read it to keep the item. While a job runs the item stays for the job,
which is why the popover always worked then.

Not explained: the report's "the message shows only after changing photos".
In the unfixed build the lost click leaves nothing behind: when the next
message brings the item back, no popover opens by itself (R1, second half).
What the owner saw after changing photos was most likely the item coming
back for a later message or job. The fix does not depend on it.

**Tests that fail without the fix.** `ActivityLogTests` in
`Tests/PhotoCoreTests/BrowserStateTests.swift` (Swift Testing):
- `openingThePopoverLeavesTheItemAndItsMessagesUntilItCloses`
- `theItemStaysWhenItsJobEndsUnderAnOpenPopover`

On `develop` they don't compile: the rule for showing the item lived in the
app target, which has no tests. With the old behavior put back behind the
new interface (read on open, visibility ignoring the popover; a trial
revert, since restored) both fail, with 7 expectations. End to end, script
R1 shows the bug in a `develop` build and S1 shows it gone.

## The fix

One rule, in PhotoCore so that it is tested: the item shows while a job
runs, while messages are unread, **and while its popover is open**; messages
are read when the popover closes, not when it opens.

- `Sources/PhotoCore/Browser/ActivityLog.swift`: `isPopoverShown`,
  `setPopoverShown(_:)` (closing marks every message read, those posted
  while it was open included; closing a popover that isn't open does
  nothing) and `showsItem(jobsRunning:)`. `markSeen()` is gone: its only
  caller was the click, and a second way to read messages is how this bug
  comes back.
- `Sources/PhotoApp/Model/LibraryModel.swift`: `markActivitySeen()` became
  `setActivityPopoverShown(_:)`. Nothing else called it.
- `Sources/PhotoApp/Views/ActivityToolbarItem.swift`: no `@State`. The
  popover is bound to `model.activity.isPopoverShown`, `isVisible` asks
  `showsItem`, and the click only opens. The idle label (info circle or
  warning triangle) stays under the open popover because the messages are
  still unread; it also covers the one new state, the popover still open
  after its job ended with nothing unread (DQ1).
- `Sources/PhotoApp/Views/LibraryToolbar.swift`: unchanged; it still hides
  the item through `isVisible`.
- `Sources/PhotoApp/Model/DebugScript.swift`: `activity open|close|snapshot
  <file.png>|click <x> <y>`, and `print activity` also prints `popover`
  (what the model holds) and `on screen` (AppKit has a popover window up).
  `activity open` refuses while the item is hidden: asked for then, the
  popover never opens and SwiftUI sets the state back.

No rendering, catalog or string changed. `docs/USER_GUIDE.md` is unchanged:
its one sentence on the Activity item says nothing about when messages are
read.

## Build and tests

On macOS 27.2, SDK 27.2 (`vtool -show-build`: minos 15.0, sdk 27.2).

| | Baseline (`550e5f2`) | With the fix |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 690 tests in 116 suites passed, 1 known issue | 693 tests in 116 suites passed, 1 known issue |
| `Scripts/build-app.sh` | builds | builds |

The three new tests are the two above and
`closingAPopoverThatIsNotOpenReadsNothing`. Two existing tests now read
messages by opening and closing the popover instead of `markSeen()`.

## Debug-script checks

Run against copies of the bundle with the identifier `<release id>.debugtest`,
each with `--library-root` on a scratch library (4 or 1,500 JPEGs from
`photobench generate --jpeg N --dng 0 --heic 0`), started from a shell
(`<copy>/Contents/MacOS/<executable> --library-root <lib> --debug-script "…"`).
`$P` is the folder of 4 photos, `$M` the folder of 1,500, `$O` an empty
export folder. The coordinates are those of these runs' window (the test
copy's saved frame): the idle item was at 912,26, and Stop at 292,39 in the
popover. In another window find the item with `buttons` (a
`SwiftUIAppKitButton` in the toolbar row, 31 pt wide when idle, 212 pt
during an export) and Stop with `activity snapshot` (the picture is at 2×).
`click` reached the toolbar and the popover without the app being active.

| | Script | Result |
|---|---|---|
| R1, `develop` build | `wait 1; addfolder $P; waitimport; wait 4; print activity; print appearance; click 912 26; wait 1; print activity; print appearance; buttons; addfolder $P; waitimport; wait 1; print activity; print appearance; quit` | Before the click `visible true … unseen 1`. After it `visible false … unseen 0`, no button at 912,26, and the library window is the only window: the bug. After the second import the item is back (`unseen 1`) and still no popover window |
| S1, idle click | `wait 1; addfolder $P; waitimport; wait 4; print activity; buttons; click 912 26; wait 1; print activity; buttons; click 700 500; wait 1; print activity; buttons; quit` | After the click `visible true … unseen 1 … popover true on screen true`, the button still at 912,26. After the click in the grid `visible false … unseen 0 … popover false on screen false`, button gone |
| S2, second click on the item | `…; click 912 26; wait 1; print activity; click 912 26; wait 1; print activity; activity open; quit` | The second click closes the popover and the item goes (`visible false … popover false`). `activity open` then prints `the Activity item is not shown` |
| S3, export running, Stop in the popover | `wait 2; selectall; export set dest=$O reveal=off; export run nowait; export close; wait 1; click 912 26; wait 0.5; print activity; activity click 292 39; wait 1; print activity; buttons; click 700 500; wait 1; print activity; quit` | The click opens the popover over the running job (`jobs [Export to “out” … 62 of 1,500] … popover true on screen true`). Stop in the popover stops it (`Export stopped after 64 photos.`, `unseen 1`); the popover and the item (now 31 pt, idle) stay. The click outside closes it and the item goes. `export close` is needed: the script's `export run` leaves the Export sheet up, which blocks clicks on the toolbar in the `develop` build as well |
| S5, changing mode under the popover | `…; activity open; print activity; loupe; wait 1; print activity; key right; wait 1; print activity; grid; wait 1; print activity; activity close; print activity; quit` | `popover true on screen true` after each step, then closed and read |
| S6, the job ends under the popover | `wait 1; addfolder $M; wait 0.4; print activity; activity open; print activity; waitimport; print activity; buttons; activity close; print activity; quit` | Open over `Add Folder … 1,280 of 1,500`; when the import ends the popover stays with the result unread (`unseen 1 … popover true on screen true`), the item idle at 912,26; closing reads it and the item goes |
| `activity snapshot` | after `activity open` in S1 and S3 | The popover's rows: the message with its title and time; the job with its title, count, bar and Stop. Its glass background comes out as false colors, as `CLAUDE.md` says of snapshots |

The owner's library was not opened: its files carry the time the owner's
own copy of the app started (08:04, hours before these runs).

## Open questions

Neither blocks the fix; both are as built until ruled.

- **DQ1 (designer).** The popover is open and its job ends with nothing
  unread (Rendering previews and Suggesting keywords post no message). The
  item now has to stay, as the anchor, with nothing to show. Built: the info
  circle, as for an unread message, until the popover closes. Before the
  fix the item was hidden at that moment, under an open popover.
- **DQ2 (designer).** `docs/UI_REDESIGN.md` §1 (historical) says "opening
  its popover marks them read". The issue asks for reading on close, and
  that is what is built: a message posted while the popover is open is read
  when it closes, and the idle symbol stays under the open popover. If
  `ui-redesign/design.md` should say so, that is the designer's file.

## For a person

What the script can't show (for `qa.md`):

1. The look: the popover's arrow points at the item, and the item doesn't
   jump or flicker when the popover opens. When the popover closes, the
   item goes without a visible glitch.
2. Escape closes the popover, and the item then goes (scripted keys go to
   the library window, not the popover).
3. With an idle unread warning (the triangle): the same as the info circle.
   Only the information case was scripted.
4. Review mode (F) or full screen while the popover is open: the popover
   closes and nothing is left behind (an item with no popover). Not
   scripted, since it takes over the display.
5. VoiceOver on the item and in the popover: unchanged, but the item now
   stays under the popover.
6. macOS 15 and 26 (CI builds them; the popover was only run on 27.2).

## README

Nothing: no requirement, build command or layout changed.
