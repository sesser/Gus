# Publish to Immich: design review

Issue: #28. Reviewer: apple-ui-designer. Date: 2026-11-26. Branch
`feature/publishing-engine`. Fifth pass at f5d5f09 (first at b244b48, second at
a382a7b, third at eb34859, fourth at 41f6d0f).

A narrow pass: whether D-15 and D-16 ([`design.md`](design.md) §3.3, §4, §8,
§17) are built as ruled, the user guide lines changed for them, and the two
follow-ups from the fourth round in [`status.md`](status.md). Method: reading the
current sources and the engineer's snapshots 30 to 32 (`round4/shots`, each
looked at). Nothing was built or run, and no diff against 41f6d0f was run (no
shell in this review). Scripted results not shown by a snapshot (`s33`, `s34`)
and test results are as `status.md` records them.

## Verdict

**Approved, with one small user guide fix (F29).** D-15 and D-16 are built as
ruled. No finding against the UI is open. F29 is one phrase in the user guide.
What else is left is the manual checks and the two follow-ups below.

## D-15: address or certificate changed during Publish

| Ruled (§3.3, §8) | Result |
|---|---|
| A Publish being confirmed is cancelled; **Checking…** goes and the form is enabled | **Pass** (31; by reading) |
| The Skip or New Copy alert closes unanswered | **Pass** by reading and the script's print; the alert itself by eye, M5 |
| Nothing that writes is sent; no run, job or record; nothing remembered | **Pass** by reading: `start` is the one path to each, and it isn't reached |
| Stays on the main page; checks the server as saved now, keeping choices and description | **Pass** (30, 31 show the new address, checked; kept by reading) |
| The line under Server, below the address and **Not encrypted**; exact words | **Pass** (30, 31) |
| Announced, and the Server pop-up's hint | **Pass** by reading |
| Only when a confirmation or an alert was given up | **Pass** by reading |
| Doesn't dim **Publish** | **Pass** (30, 31) |
| Goes on Publish, a server chosen, added or saved from the sheet, removal (D-13's line instead), next opening | **Pass** by reading |
| A run never starts with other than the saved address and certificate, from either route | **Pass** by reading: both read the saved record just before `start` |
| A rename or a new key alone gives nothing up | **Pass** by reading |

**`answer(skip:)` counting as a confirming Publish: accepted.** Answering the
alert is still pressing Publish (§3.8), so while the saved server is read the
same state is right: **Publish** can't be pressed twice, **Cancel** and Esc still
send nothing that writes, and a change or removal arriving then gives the answer
up as D-15 and D-13 require. **Checking…** and the dimmed form may show for the
few milliseconds of one catalog read. That is accurate and needs no delay or
special case.

## D-16: Save never recreates a removed server

| Ruled (§4) | Result |
|---|---|
| Name-only Save, checked Save and Trust Certificate insert no row and leave no key | **Pass** by reading; Trust Certificate goes through the same Save |
| Removed before the press: nothing read from the Keychain, sent or written | **Pass** by reading (`s33`: no request) |
| Removed during a check that passes: nothing written | **Pass** by reading |
| The Server sheet closes, no alert, no new string | **Pass** by reading |
| From Publish: **Server** None with **This server was removed.**, no other server chosen | **Pass** (32) |
| From Publish, last server: **No saved server**, no removal line | **Pass** by reading (`s33`) |
| From Import: servers read again, a removed source left as after Remove Server… | **Pass** by reading (`s34`) |
| The sheet isn't closed at the moment of removal; Add unaffected | **Pass** by reading |
| A name-only Save changes only the name of the server as saved now | **Pass** by reading |

## Findings

**F29 (low, user guide).** In the publish section, "that Publish is given up:
nothing is sent" says more than is true. While Publish is confirming, the check
has already sent requests, with the key, to the earlier address. D-15 rules that
nothing **that writes** is sent. Someone who moved the server because the old
address was wrong shouldn't be told otherwise.

Fix: replace **nothing is sent** with **nothing is uploaded or changed on the
server**.

The other changed lines are right: the quoted line is the UI's, the cases that
remove it match §3.3, a name or key alone gives nothing up, and both D-16
passages (the import section and the removed server under **Server**) match the
build.

## Follow-ups

Both items proposed in `status.md` are follow-ups; neither holds this branch.
The first replaces the fourth pass's proposed follow-up. Suggested bodies, with
what each should add:

1. **Publish sheet keeps an old check after its own Server sheet is cancelled**
   (bug; what is left of D-14). Agreed. Add: by reading, **Check Originals** in
   that state also still asks the earlier address, with the key it was checked
   with, while matching records by the new one. It isn't only a stale check and
   album list. Nothing is written, and **Publish** connects afresh. Expected:
   when the publish sheet comes back and the saved address or certificate
   differs from the one checked, it checks again, keeping every choice. D-15's
   line isn't needed, since nothing was given up.
2. **A name-only Save whose catalog write fails says nothing** (bug, #271's
   code). Agreed. Change the expectation: "the same message" as a checked Save
   would copy a wrong one. By reading, a checked Save's catalog failure, D-16's
   new read before the check included, is headed **The key couldn't be saved**
   with **The Keychain returned an error: …**. Expected: both say the library
   couldn't be read or written, in wording the designer rules on then.

## Design requirements

| Design | Requirement | Result |
|---|---|---|
| P1, §2.1 | File menu items, order, ⌥⌘E, Stop title, enabling | Pass by reading; M3 |
| §2.2, §2.3 | Toolbar item; context menu | Pass by reading; M3 |
| P2, §3.1, §3.2 | Sheet, header, sections | Pass; smallest window M1 |
| §3.3 | Server section, removed server (D-13) and changed destination (D-15) included | Pass (26, 26c, 26e, 28, 30, 31); M5 |
| §3.4 | Album, Archive captions | Pass; M4 |
| §3.5 | Stacking | Pass |
| P3, §3.6 | Shared form, presets, description | Pass (29a, 29b); M4 |
| §3.8 | Publish enabling; Cancel sends nothing that writes | Pass |
| P4, P13, P14, §4 | Server sheet by host, wording, address warning, D-16 | Pass (32); M4, M5 |
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

## Earlier passes

F1 to F28 were closed by the fourth pass, with D-12, D-13 and the Failed list's
repeated row confirmed at 41f6d0f. D-14's accepted cases still standing: a
key-only change isn't noticed by an open sheet; the publish sheet's own Server
sheet stays up when its server is removed (a Save now ends as D-16 says); and
follow-up 1.

## Requirements and design issues

None for the product manager.

## Manual checks (a person, bundled app, scratch library and a test server)

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
  returns. With the alert up, removing the server in the import window closes it.
  Again with the alert up, change the server's address in the import window: the
  alert closes, **This server's address or certificate changed. Nothing was
  published.** shows under Server, the new address is checked and no run appears
  in Activity. Open **Edit “‹name›”…** from Publish, remove that server in the
  import window, change the name and **Save**: the sheet closes once and the
  publish sheet comes back with **This server was removed.** (the end state is
  scripted; look at the change of sheets). Results: Return and Esc close; the Run
  pop-up; selecting a reason.
- **M6.** A real run: **Stop** while a large photo renders and while it uploads;
  **Stop** while a retry checks a slow server; **Show Results…**; Quit during a
  run and while it is ending; the import window marks new uploads In Library, with
  Edit and Remove Server dimmed.
- **M7.** The owner's server (AC17): an https server shows no **Not encrypted**
  line; if its certificate isn't trusted, read the publish sheet's wording.

## Follow-up

F1 to F28 are closed. Open: F29, M1 to M7, and the two follow-ups above.
