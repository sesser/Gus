# Activity popover: QA

Owner: qa-tester. Date: 2026-11-10. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/activity-popover-anchor`, the uncommitted working tree on
`550e5f2` (`git diff develop -- Sources Tests` SHA-256 `fb402fbc…d5716a3`,
the same diff code review read), on a Mac16,8, macOS 27.2 (26B123), SDK 27.2
(`vtool -show-build`: minos 15.0, sdk 27.2, for both bundles below).
Spec: the **Bug** section of `status.md` (issue #56); `code-review.md` Q1
and Q2; `review.md` R1–R12 and M1–M8.

## Verdict

Passes. The bug shows on `develop` and is gone on the branch; the named
tests fail with the old rule put back; every Q1 probe printed `popover` and
`on screen` equal (no `popover true on screen false` anywhere), and the
second click on the item while a job runs closes the popover and leaves it
closed. What remains is for a person: the look, the warning case, VoiceOver,
the overflow menu and macOS 15/26 (P1–P10).

## Acceptance criteria

| # | Criterion (source) | How | Evidence | Result |
|---|---|---|---|---|
| B1 | The bug exists before the fix: clicking the idle item shows no popover, the item vanishes and the messages count as read (Bug, Actual) | Script | R1 on a `develop` build | Pass (bug shown) |
| B2 | Clicking the idle item opens a popover under it listing the recent messages (Bug, Expected; R1) | Script, Person for the look | S1 and its `activity snapshot`; P1 | Pass; look Open |
| B3 | The item goes only after the popover closes (Bug, Expected; R3) | Test, Script | `ActivityLogTests.openingThePopoverLeavesTheItemAndItsMessagesUntilItCloses`; S1, S2 | Pass |
| B4 | Messages are read on close, not on open, those posted while it was open included (A1, R4) | Test, Script | `ActivityLogTests.openingThePopover…UntilItCloses`, `closingAPopoverThatIsNotOpenReadsNothing`; S6, Q1-A…D | Pass |
| B5 | The item stays when its job ends under the open popover (A2) | Test, Script | `ActivityLogTests.theItemStaysWhenItsJobEndsUnderAnOpenPopover`; S6 (import ends), S3 (export stopped) | Pass |
| B6 | The tests fail without the fix (Bug, "Tests that fail") | Test | Trial revert in a scratch copy (below): 2 tests, 7 issues | Pass |
| B7 | A second click on the item closes the popover: idle (R6) and while a job runs (code review Q2) | Script, Person for a real mouse | S2 (idle), Q2 (export running, shell launch and activated launch); P9 | Pass; real mouse Open |
| B8 | Code review Q1: the model's popover state never disagrees with the screen when the window changes under the popover (R8) | Script | Q1-A (Hide/Show Toolbar), Q1-B (Export sheet, both `export window` and File ▸ Export…), Q1-C (review on/off, leaving full screen), Q1-D (sheet over a running job) | Pass |
| B9 | Stop in the popover stops the job; the popover stays over the finished job (R9) | Script | Q1-D (`activity click 292 39`) | Pass |
| B10 | Escape closes the popover and, with nothing running, the item goes (R7, M4) | Script, Person for a real key | Q1-D (`menukey escape`, activated app, over a job and idle); P4 | Pass; real key Open |
| B11 | Look, warning symbol, VoiceOver, overflow menu, other window paths, macOS 15 and 26 (R2, R5, R10, M1–M8) | Person | P1–P10 | Open |

Full `swift test` on the branch: 693 tests in 116 suites passed, 1 known
issue (`LiveSessionTests.swift:258`, not this branch). `Scripts/build-app.sh`
builds.

**B6 in detail.** On `develop` the new tests don't compile (no
`setPopoverShown`, `showsItem`), so in a scratch clone of `develop` outside
the checkout I applied the branch's whole diff, then put the old rule back
in `ActivityLog.swift` only (`setPopoverShown(true)` reads the messages;
`showsItem` ignores `isPopoverShown`) and ran
`swift test --filter ActivityLogTests`: 7 tests, 2 failed with 7 issues:
`openingThePopover…UntilItCloses` at `BrowserStateTests.swift` lines 188,
190, 191, 195, 198, 200, and `theItemStaysWhenItsJobEndsUnderAnOpenPopover`
at 210. The same seven the engineer and code review named.

## Findings

None for the engineer.

Observed, already raised: code review's C1 (Nit) holds. With keyword entry
open, `print activity` reads `popover false on screen true` (last line of
Q2's run below), because `on screen` means any popover window. No Q1 probe
had keyword entry open, so it does not affect the results here.

The view's wiring (the binding's setter, the click) has no unit test, since
`PhotoApp` has no test target; the scripts above are its check.

## Scripts

Setup. Both bundles (`develop` at `550e5f2`, built in a scratch clone, and
the branch) copied to a scratch folder, identifier set to
`me.sesser.gus.debugtest`, re-signed ad hoc. Scratch photos from
`photobench generate --output <dir> --jpeg N --dng 0 --heic 0` (`$P`: 4
photos, `$M`: 1,500); every launch with `--library-root` on a new scratch
library (`big` holds `$M` imported, copied for each export run). `$O` is an
empty export folder. Shell launch:
`<copy>/Contents/MacOS/Gus --library-root <lib> --debug-script "…"`.
Activated launch (for menus and keys): `open -W -n --stdout <log> --stderr
<log> <copy> --args --library-root <lib> --debug-script "…"`, then the
process brought forward by its ID (`pgrep -n -x Gus`, checked to be the
scratch copy, then System Events `set frontmost of (first process whose unix
id is <pid>) to true`). `print responder` in each activated run says whether
it took. The idle item was at 912,26 (31 pt wide; 212 pt while exporting),
as in `status.md`.

After all runs: no `Gus` process left, and no file in
`~/Library/Application Support/Gus/Library` newer than the start of this
pass.

**R1, `develop` build, shell launch.**
`wait 1; addfolder $P; waitimport; wait 4; print activity; click 912 26; wait 1; print activity; buttons; addfolder $P; waitimport; wait 1; print activity; quit`
Before the click `visible true jobs [] unseen 1`. After it `visible false
… unseen 0` and `buttons` lists nothing at 912,26: no popover, item gone,
message read. The bug. After the second import the item is back with
`unseen 1`.

**S1, branch, shell launch.**
`wait 1; addfolder $P; waitimport; wait 4; print activity; click 912 26; wait 1; print activity; buttons; activity snapshot <png>; click 700 500; wait 1; print activity; buttons; quit`
After the click `visible true … unseen 1 … popover true on screen true`,
button still at 912,26. Snapshot: one row, info symbol, "Add Folder “p4”",
"Imported: 4. Already in the library: 0.", "5 sec", arrow at the top edge
(glass in false colors, as expected). After the click in the grid
`visible false … unseen 0 … popover false on screen false`.

**S2, second click, idle, shell launch.**
`wait 1; addfolder $P; waitimport; wait 4; click 912 26; wait 1; print activity; click 912 26; wait 1; print activity; activity open; print activity; quit`
`popover true on screen true`, then `visible false unseen 0 popover false
on screen false`; `activity open` then prints `the Activity item is not
shown`.

**S6, job ends under the popover, shell launch.**
`wait 1; addfolder $M; wait 0.4; print activity; activity open; print activity; waitimport; print activity; activity close; print activity; quit`
Open over `Add Folder | 1,280 of 1,500` (`popover true on screen true`);
after the import `jobs [] unseen 1 … popover true on screen true`; closed:
`visible false unseen 0 popover false on screen false`.

**Q2, second click while an export runs, shell launch.**
`wait 2; selectall; export set dest=$O reveal=off; export run nowait; export close; wait 1; print activity; buttons; click 912 26; wait 0.5; print activity; click 912 26; wait 1; print activity; wait 1; print activity; click 912 26; wait 1; print activity; activity snapshot <png>; stop; wait 1; print activity; click 700 500; wait 1; print activity; quit`
First click opens (`61 of 1,500 … popover true on screen true`). Second
click closes, and it stays closed a second later (`97`, then `124 of 1,500
… popover false on screen false`): it does not reopen. A third click opens
it again (snapshot: "Export to “out”", Stop, "159 of 1,500", bar). File ▸
Stop: `jobs [] unseen 1 … popover true on screen true`; click outside:
`visible false unseen 0 popover false on screen false`.
Repeated in an activated launch (`print responder`: `key AppKitWindow`):
`…; export close; wait 1; click 912 26; wait 1; print activity; click 912 26; wait 1; print activity; wait 1; print activity; stop; wait 1; print activity; keyentry; wait 1; print activity; quit`
Same: open at `76`, closed at `112` and `139`. The last line,
after `keyentry`, is C1: `popover false on screen true`.

**Q1-A, Hide Toolbar, activated launch** (`key AppKitWindow`).
`wait 1; addfolder $P; waitimport; wait 8; print responder; print activity; click 912 26; wait 1; print activity; menuitems Toolbar; menupress Hide Toolbar; wait 1; print activity; menuitems Toolbar; menupress Show Toolbar; wait 1; print activity; buttons; click 912 26; wait 1; print activity; click 700 500; wait 1; print activity; quit`
Open: `popover true on screen true`. After Hide Toolbar: `visible false
unseen 0 popover false on screen false`. After Show Toolbar the same, and
the item is gone (912,26 hits the toolbar's title view). Every line agrees.
(A first try of this without activation had View ▸ Hide Toolbar disabled;
the popover stayed open and agreed.)

**Q1-B and Q1-C, Export sheet and review mode, activated launch**
(`key AppKitWindow`).
`wait 1; addfolder $P; waitimport; wait 12; print responder; selectall; click 912 26; wait 1; print activity; menuitems Export; menupress Export…; wait 1; print activity; export close; wait 1; print activity; buttons; addfolder $P; waitimport; wait 2; print activity; click 912 26; wait 1; print activity; review on; print activity; print review; review off; print activity; print review; addfolder $P; waitimport; wait 2; click 912 26; wait 1; print activity; review on; review leavefullscreen; print review; print activity; review off; print review; print activity; quit`
File ▸ Export… (enabled, ⇧⌘E) under the open popover: `popover false on
screen false`, `unseen 0`, item gone after the sheet closes. Review on
(`review true … fullscreen true`): `popover false on screen false`; review
off: the same, item gone. Review on then leaving full screen: the same.
An earlier `open` launch where activation did not take (`key nil`) ran the
debug script's own `export window` under the popover: `popover false on
screen false`, `unseen 0`, also agreeing (File ▸ Export… was disabled
there, so the popover stayed open, and agreed).

**Q1-D, a sheet, Escape and Stop over a running export, activated launch**
(`key AppKitWindow`).
`wait 12; print responder; selectall; export set dest=$O reveal=off; export run nowait; export close; wait 1; print activity; click 912 26; wait 1; print activity; menukey escape; wait 1; print activity; click 912 26; wait 1; print activity; export window; wait 1; print activity; export close; wait 1; print activity; click 912 26; wait 1; print activity; activity click 292 39; wait 1; print activity; buttons; menukey escape; wait 1; print activity; quit`
Open over the export (`popover true on screen true`); Escape closes it
(`popover false on screen false`, job still running, item stays); reopened;
Export sheet closes it (`false false`); reopened; Stop in the popover:
`jobs [] unseen 1 … popover true on screen true`, item now 31 pt; Escape:
`visible false unseen 0 popover false on screen false`.

No line in any run showed `popover true on screen false`.

## For a person

Build and run as `docs/WORKFLOW.md` step 5 says (a bundle copy, always with
`--library-root` on a scratch library). Add a small folder (File ▸ Add
Folder Without Copying…) to get an idle unread message.

- **P1 (M1). Anchor and look.** Click the idle `info.circle` item. The
  popover opens under it, its arrow on the item; the item does not jump,
  flicker or change symbol. Click outside: the popover closes, then the item
  goes, with no empty capsule left for a frame.
- **P2 (M2). Warning.** The same with an unread warning (for example, revert
  to a History entry that can't be applied): the triangle stays under the
  open popover and goes with the item on close. Not scripted (no scripted
  way to post a warning).
- **P3 (M3). Job ends under the popover.** Export many photos, open the
  popover, let it finish or press Stop: the item shrinks to an idle symbol,
  the arrow follows it, and the height change animates. Then with only
  Rendering previews running (a large folder, after its import): when they
  finish, the item shows `info.circle` until the popover closes, then goes.
  The states are scripted (S6, Q1-D); the motion is not.
- **P4 (M4). Escape on a real keyboard** closes the popover and, with
  nothing running, the item goes. Scripted with a posted key (Q1-D); this
  confirms it with focus where a person leaves it.
- **P5 (M5). Full screen without review.** With the popover open, ⌃⌘F:
  the popover closes; back out, the item is gone if nothing is running or
  unread, and opens again on a click. Review mode (F) is scripted (Q1-C);
  plain full screen is not.
- **P6 (M6). A menu opened with the mouse.** With the popover open, open a
  menu-bar menu with the mouse, then close it: either the popover is still
  open and works, or it is closed with the item gone. Never an item that
  stays with no popover. (Hide Toolbar and Export… from the menu are
  scripted, Q1-A and Q1-B.)
- **P7 (M7, code review Q1 by hand). Overflow and window close.** Narrow the
  window until Activity moves into the » menu, with an unread message;
  choose it there: a popover opens anchored sensibly, or nothing happens and
  the item keeps its message. Then, with the popover open, close the library
  window with the Import window open and reopen it (Window ▸ Library): the
  item is not stuck, and a click on it opens the popover.
- **P8 (M8). VoiceOver.** Focus the idle item: it reads the message.
  Activate it: focus moves into the popover; rows read title, text and time.
  Escape returns focus and the item goes. Note what the item reads in P3's
  previews case (the designer's I1).
- **P9 (code review Q2). Second click with a real mouse while a job runs.**
  Open the popover over an export and click the item again: it closes and
  does not reopen. The script posts the mouse down and up together; a person
  pressing and releasing is the real case.
- **P10. macOS 15 and macOS 26.** P1, P3 and P4 on each (CI builds and
  tests both; the popover has only been run on 27.2). Owner's choice.

## Follow-up

**Sign-off, 2026-11-10.** The owner signed off on `d8d05ba`
(`bug/activity-popover-anchor`, issue #56). P1–P6 checked by the owner and
verified. Left open: P7 and P8, unverified, by the owner's explicit word; P9
and P10, which the owner did not report either way.
