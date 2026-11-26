# Publish to Immich: design review

Issue: #28. Reviewer: apple-ui-designer. Date: 2026-11-26. Branch
`feature/publishing-engine`. Fourth pass at 41f6d0f (first at b244b48, second at
a382a7b, third at eb34859).

A narrow pass: F24 to F28, the extra fix to the results' Failed list, the user
guide lines that changed, and the two items [`status.md`](status.md) lists as
known and left. Compared with [`design.md`](design.md) (rulings in its §16 and
§17) and the HIG. Method: reading the current sources and the engineer's 14
snapshots (`round3/shots`, each looked at). Nothing was built or run, and the
diff against eb34859 was not run (no shell in this review). The snapshots draw
the default button as in an inactive window; not a finding.

## Verdict

**Approved.** F24 to F28 are fixed, D-12 and D-13 are built as ruled, and the
Failed list's repeated row is fixed. No design finding is open. The two known
items are accepted (D-14), with one follow-up proposed. What is left is the
manual checks below.

## Third-pass findings, confirmed against 41f6d0f

| # | Finding | Result |
|---|---|---|
| F24 (D-12) | Retry Failed offered with nothing to send | **Fixed.** `27`: caption in the button's place, no button, counts and lists unchanged. `23a`: button still offered while two photos are left. One rule for the button and the job (`retryVersionIDs(laterPublished:)`). Read on appear, on a Run change, when a publish ends with the sheet open (by reading) and again on press |
| F25 (D-13) | The sheet kept a removed server's state | **Fixed.** `26`: None, **This server was removed.**, Album None dimmed, no address, folder-map row or "no original" line, Check Originals and Publish dimmed, Show in and stacking kept. `26b`: back from the folder map page. `26c`: line gone on another choice. `26e`: No saved server, no line. A confirmation in progress and the Skip or New Copy alert are given up (by reading: M5) |
| F26 | Check Originals' lines centered | **Fixed.** `06`: ten lines of different widths and **And 2 more.** share one leading edge |
| F27 | A bad watermark pick hidden | **Fixed.** `29a` missing; `29b` the non-PNG sentence over it |
| F28 | Old check after an address change | **Fixed.** `28`: new address checked, **Trip** and **Archive** kept (the description is below the fold; kept by reading). A rename alone checks nothing (by reading and the engineer's script) |

## The Failed list

**Fixed.** `23a` and `27` list `IMG_00001.JPG` and `IMG_00002.JPG`. The section is
now one `ForEach` with an id per photo and failure. Not Finished, Not Stacked and
Already There draw one row per photo from a single `ForEach` and don't share the
fault (by reading).

## Snapshot 23

As intended. The retried run shows **Failed 1** and the D-12 caption together:
the counts record what happened to that photo in that run, the retry never tried
it (a later publish had sent it, R23), and the caption says why nothing is
offered. Removing it from Failed would credit this run with an upload it didn't
make. Its Activity message stays a warning for the same reason.

One wrinkle, accepted: "later" means after the run began. The retried run now
ended last, so it lists above the publish the caption calls later. The sentence
still points at the right fact, and a reword isn't worth another round. Recorded
in design §10.3.

## Known and left, ruled (D-14)

| Item | Ruling | Why |
|---|---|---|
| A key changed in the import window isn't noticed by an open sheet | **Accept**, no follow-up needed beyond the one below | Nothing wrong is sent: **Publish** connects afresh with the saved key. A sheet showing "rejected this API key" has **Try Again**, which reads the new key |
| Removing the server doesn't close the publish sheet's own Server sheet | **Accept** for this feature; **follow-up** | It takes two deliberate actions on one server in two windows, and nothing is sent without a further Save |

A correction to the second item in `status.md`: "on its return the publish sheet
shows the removal" holds for **Cancel**. By reading, not run: a name-only **Save**
calls GRDB's `save`, which inserts when no row matches, so the removed server
comes back (same address and trusted certificate, no key; its folder map and
choices stay deleted). The sheet then reports that the key couldn't be read.
Remove Server… undoes it. A save with a newly typed key brings it back with that
key, which the person did ask to save.

Two related cases, also by reading, go in the same follow-up. An address changed
while that Server sheet is up and then cancelled leaves the old check showing.
An address changed while **Publish** is being confirmed, or while the Skip or New
Copy alert is up, doesn't cancel either, so the run can go to the old address.
Removal does cancel both.

**Update, 2026-11-26 (after the fourth pass).** D-14's second item is **no longer
deferred**: the branch is reopened for code review C11 and security finding L2
(design D-15), and the removed server brought back by Save is fixed with it
(design D-16, which also makes a name-only Save change only the name). Both are
to be built and reviewed; this file's verdict covers 41f6d0f only. Of the
follow-up below, only one case is left: an address or certificate change while
the publish sheet's Server sheet is up and then cancelled isn't rechecked
(**Publish** still connects to the saved address). The removal and confirmation
parts of its body should be dropped if it is filed.

**Proposed follow-up** (bug):

- Title: **Publish sheet misses some server changes made in the import window**
- Body: With the publish sheet's own Server sheet up, removing that server in the
  import window leaves the sheet open, and Save inserts the removed row again (a
  name-only save leaves it with no key). Expected: Save never recreates a removed
  server; the sheet closes, or says the server was removed, and the publish sheet
  returns showing that. Also: an address or certificate change while that sheet is
  up and cancelled isn't rechecked; one made during Publish's confirmation or its
  Skip or New Copy alert should cancel them. Design: D-14, design §3.3. Slug:
  `publishing-engine`.

## Design requirements

| Design | Requirement | Result |
|---|---|---|
| P1, §2.1 | File menu items, order, ⌥⌘E, Stop title, enabling | Pass by reading; M3 |
| §2.2, §2.3 | Toolbar item; context menu | Pass by reading; M3 |
| P2, §3.1, §3.2 | Sheet, header, sections | Pass; smallest window M1 |
| §3.3 | Server section, removed server included | Pass (26, 26c, 26e, 28) |
| §3.4 | Album, Archive captions | Pass; M4 |
| §3.5 | Stacking | Pass |
| P3, §3.6 | Shared form, presets, description | Pass (29a, 29b); M4 |
| §3.8 | Publish enabling; Cancel sends nothing | Pass |
| P4, P13, P14, §4 | Server sheet by host, wording, address warning | Pass by the second pass; M4 |
| P5, §5 | Missing permissions | Pass |
| P6, §6 | Folder map | Pass; M2 |
| P7, §7 | Check Originals | Pass (06) |
| P8, §8 | Skip / New Copy | Pass by reading; M5 |
| P9, §9 | Activity, Stop, ending, quit | Pass; M6 |
| P10, §10 | Activity row, results, Retry Failed | Pass (23, 23a, 23b, 27) |
| P11, §11 | Import window marks | Pass by reading; M6 |
| P12, P15, P16 | Nothing elsewhere; Archive warns; Already There | Pass |
| §13 | Keyboard, announcements, plurals | Pass by reading; M2 |

Rows without a snapshot from this round rest on the earlier passes.

## User guide

The changed lines match the UI and D-12 and D-13: the removed server, the recheck
after an address or certificate change, and when Retry Failed isn't offered. The
quoted strings are the UI's. The narrow cases of D-14 need no words there.

## Requirements and design issues

None for the product manager.

## Manual checks (a person, bundled app, scratch library and a test server)

This list replaces the third pass's M1 to M10.

- **M1.** Publish sheet (all three pages) and results at the smallest window, also
  with Increase Contrast, with a long address.
- **M2.** Keyboard only: ⌥⌘E, every control, **Return** publishes straight after
  the check with no click first; Return and Option-Return in Description; focus
  returns to the grid or loupe. In the folder map type a path, paste a trailing
  slash, and check focus after **Add Folder…** through the real panel.
- **M3.** File menu, context menu and toolbar by eye: order, dimming, the toolbar
  item in the default set, Customize and overflow.
- **M4.** With the mouse: the Album pop-up's tick, and the dimmed **New Album…**
  with a key lacking `album.read`; Add, Edit, Cancel and Review Certificate swap
  sheets and keep choices and description; in File Settings with the watermark
  file missing, choosing the same image again clears the warning.
- **M5.** Skip or New Copy for one photo and several: wording, Return is Skip, Esc
  returns; with the alert up, removing the server in the import window closes it.
  Results: Return and Esc close; the Run pop-up; selecting a reason.
- **M6.** A real run: **Stop** while a large photo renders and while it uploads;
  **Stop** while a retry checks a slow server; **Show Results…**; Quit during a
  run and while it is ending; the import window marks new uploads In Library, with
  Edit and Remove Server dimmed.
- **M7.** The owner's server (AC17): an https server shows no **Not encrypted**
  line; if its certificate isn't trusted, read the publish sheet's wording.

## Follow-up

F1 to F28 are closed. Open: M1 to M7, and the follow-up issue above.
