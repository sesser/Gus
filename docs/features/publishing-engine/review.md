# Publish to Immich: design review

Issue: #28. Reviewer: apple-ui-designer. Date: 2026-11-26. Branch
`feature/publishing-engine`. Second pass at a382a7b (first pass at b244b48).

Compared with [`design.md`](design.md) (rulings in its §16 and §17), the PRD
(revision 6) and the HIG. Method: reading the sources, the String Catalog entries
of the changed publishing strings, the user guide, [`status.md`](status.md), and
the engineer's 20 snapshot files (01 to 18, with 05 twice and 06 twice) of the
running app. Nothing was built or run by this review. The snapshots draw the
default button as in an inactive window, and the Activity popover's glass comes
out colored; neither is a finding.

## Verdict

**Changes needed.** F1 to F8 and F10 to F18 are fixed. The fix for F9 brought in
a blocker: **Publish N Photos stays dimmed after the server check passes**
(F19). Three smaller faults (F20 to F22) and one minor one (F23) are also open.

## Open findings

### Must fix

**F19. Publish stays dimmed after a passing check.** `PublishModel.canPublish`
(line 380) tests `client != nil` before `serverInfo`, and `client` is
`@ObservationIgnored` (line 81). While the check runs `client` is nil, so the
guard stops there and SwiftUI registers no dependency on `check`. When the check
passes, nothing the button's view (`PublishMainPage`) reads changes, so it is
not drawn again. Snapshot `01-publish-main.png` shows it: the check has passed
(no spinner, Album enabled), no issue is shown, and **Publish 3 Photos** is
disabled. In `06-check-originals-result.png` it is enabled, after a visit to
another page redrew it. The scripted checks missed it because `publish start`
calls `confirm()` and `publish print` computes `canPublish` afresh.
Why it matters: the sheet's one purpose can't be carried out by the ordinary
route (open, press Return), and no reason is given (design §3.8; HIG Buttons,
Feedback).
Fix: remove `@ObservationIgnored` from `client`, so every input of `canPublish`
is observed. Check it on screen: open the sheet, wait for the check, snapshot
without visiting a page or pressing anything.

### Should fix

**F20. One photo reads "1 of 1 photos."** Both catalog variations of **Originals
found for %lld of %lld photos.** and of **Publishing stopped after %lld of %lld
photos.** are plural, and the catalog compiler can inflect only a first number.
Publishing the loupe's one photo is a common case, so fix on this branch (ruling
D-6), replacing the two keys, with no plural variation:
**Originals found: %1$lld of %2$lld.** and **Publishing stopped. Photos on the
server: %1$lld of %2$lld.** This was the engineer's proposed follow-up; it is
not needed after this.

**F21. Skip or New Copy says "them" about one photo.** `PublishText
.questionMessage` has one first part for every count, under a title reading **1
photo was already published to…** (design §8 asks for singular and plural; missed
in the first pass). With one published photo use (ruling D-7): **Skip leaves it
as it is on the server. New Copy publishes it again; no photo on the server is
replaced, and a file that hasn't changed may be reported as already there.** The
last sentence is unchanged.

**F22. A retry that only finishes steps reads "Rendering 0 of 2".**
`ItemContext.steps` calls `counter.step` only from the upload path, so for photos
already accepted the job keeps its starting phase and a current of 0 for the
whole retry (design §9: those steps run under Uploading; ruling D-8).
Fix: report `.uploading` with the photo's sequence when its upload is already
done.

### Minor

**F23. After a retry, "newest" is not the newest.** `endedRuns` is in start
order, but the Run pop-up shows end times. Retrying an older run leaves the list
out of time order, and **File ▸ Publish Results…** opens a different run from the
one just retried (design §10.2; ruling D-9). Fix: order `endedRuns` by
`endedAt`; or say in `status.md` why not.

## First-pass findings, confirmed against a382a7b

"Reading" means the code was read; a snapshot number means it was also seen.

| # | Finding | Result |
|---|---|---|
| F1 | Cancel during Checking still published | **Fixed.** Session-guarded confirm task, cancelled on dismissal; question carries its server and client; form dimmed, Cancel on (08) |
| F2 | An ending run showed as running | **Fixed** by reading: slot holds stopping; counter and `followed(by:)` keep ending; D-1 details. Ending state not in any snapshot (15 shows the ended run) |
| F3 | Retry invisible and repeatable | **Fixed.** Slot claimed before the check, check inside the task, `endedAt` set on every ending (12, 16) |
| F4 | Retry unaware of removed or moved server | **Fixed** (14) |
| F5 | Edit Server threw choices away | **Fixed** by reading (`keepingChoices`) |
| F6 | Server path rewritten while typed | **Closed.** Not reproduced by the engineer; the text is now kept as typed and the slash dropped in matching and on Done (05) |
| F7 | Export watermark warning stayed | **Fixed** by reading (`onWatermarkPicked`). 17 and 18 are identical and show only the top of the sheet, so the warning has not been seen |
| F8 | Results showed the running run | **Fixed** by reading (`endedRuns`) |
| F9 | Reopened sheet publishable before loading | Asked changes are in; **superseded by F19**, a fault the fix introduced |
| F10 | Untrusted certificate unexplained | **Fixed** by reading (D-3) |
| F11 | Stale originals check came back | **Fixed** by reading (`resetOriginals`; album no longer clears) |
| F12 | Album pop-up tick and permission line | **Fixed** by reading; needs a person (M4) |
| F13, G-2 | Issues not announced | **Fixed** by reading (`AnnouncedIssue`, hints) |
| F14 | Import marks late; actions not dimmed | **Fixed** by reading |
| F15 | No popover spinner; Waiting stuck | **Fixed** (16) |
| F16 | Result wording | **Fixed** (10, 11; D-5 line by reading only, see below) |
| F17 | Add Folder focus | **Fixed** (05, added: the server field has the selection) |
| F18 | Retry overwrote remembered choices | **Fixed** by reading |

RI-E1 is ruled (PRD revision 5); `design.md` §4.1 and §15 now agree with it.

## Snapshots

| File | What it shows |
|---|---|
| 01 | Main page. **Publish dimmed with a passing check (F19)** |
| 02, 03, 06 (check originals) | The same view three times: top of the sheet, missing `asset.upload`, Album **None**, **Timeline**. Section and issue are right. They do **not** show what `status.md` says: no New Album name or note, no Archive warning, no dimmed Check Originals. Retake after the change has drawn and scrolled into view, or those stay unseen. If the controls don't redraw after the script's command, that is a further fault to report |
| 04 | File Settings: as designed |
| 05, 05 added | Folder map: typed text kept, example correct, field focused |
| 06 result | Folder map saved, **1 folder**, Check Originals; the result itself is below the fold and unseen |
| 07 | Server sheet from Publish: host captions and unencrypted notice as designed |
| 08 | Confirming: form dimmed, Cancel on, **Checking…** |
| 09 to 12, 14 | Results: counts, sections, reasons, Run pop-up, Retry Failed and its refusals as designed |
| 13 | Named "retry check failed", but the header has no **Publishing stopped: …** line and Retry is enabled. By code a run stopped by its check shows that line, so this is probably another run (F23) or was taken before the retry ended. Retake with the fixes |
| 15 | Popover with the ended, stopped run; not the ending state |
| 16 | Retry's check: title, **Stop**, detail, spinner: as designed |
| 17, 18 | Export top of sheet; the watermark section is not in view |

Nothing is clipped or overlapping in the views shown.

## Design requirements

| Design | Requirement | Result |
|---|---|---|
| P1, §2.1 | File menu items, order, ⌥⌘E, Stop title, enabling | Pass by reading; M3 |
| §2.2, §2.3 | Toolbar item; context menu | Pass by reading; M3 |
| P2, §3.1, §3.2 | Sheet, header, sections | Pass (01); smallest window M1 |
| §3.3 | Server section | Pass (01, 02) |
| §3.4 | Album, Archive captions | Pass by reading; unseen, M1, M4 |
| §3.5 | Stacking | Pass (01) |
| P3, §3.6 | Shared form, presets, description | Pass (04); Export M8 |
| §3.8 | Publish enabling; Cancel sends nothing | **Fail (F19)**; Cancel passes (08) |
| P4, P13, P14, §4 | Server sheet by host, wording, address warning | Pass (07); swap M5 |
| P5, §5 | Missing permissions | Pass (02) |
| P6, §6 | Folder map | Pass (05); M2 |
| P7, §7 | Check Originals | **Fail** wording (F20); rest by reading |
| P8, §8 | Skip / New Copy | **Fail** singular (F21); keys M6 |
| P9, §9 | Activity, Stop, ending, quit | **Fail** detail on a steps-only retry (F22); rest pass (16); M7 |
| P10, §10 | Activity row, results, Retry Failed | **Fail** wording (F20), order (F23); rest pass (09 to 14) |
| P11, §11 | Import window marks | Pass by reading; M9 |
| P12, P15, P16 | Nothing elsewhere; Archive warns; Already There | Pass by reading |
| §13 | Keyboard, announcements, plurals | **Fail** plurals (F20, F21); M2 |

## Strings and user guide

The new and changed catalog entries read for D-1, D-3, D-4, the already-there
forms of Not Finished, and the plural entries match the design, apart from F20
and F21. The user guide matches the UI and PRD revision 6 on terms, link order,
the former top photo, **Stopping…**, the retry's check, the dropped slash and
"uploads no photo twice (except after a lost answer…)". It quotes neither string
that F20 changes. No change needed.

## Rulings

D-1 to D-5, the §3.6 correction and the new D-6 to D-9 are recorded in
[`design.md`](design.md) §17 and the sections it names.

## Requirements and design issues

None for the product manager.

## Manual checks (a person, bundled app, scratch library and a test server)

After F19 to F22 are fixed.

- **M1.** Publish sheet, both pages and results at the smallest window, also with
  Increase Contrast: **New Album…** with an existing name (note and button),
  Archive with stacking (warning wraps), Check Originals' result, long addresses.
- **M2.** Keyboard only: ⌥⌘E, every control, **Return** publishes straight after
  the check; note what Return and Option-Return do in Description; focus returns
  to the grid or loupe. In the folder map type `/mnt/media/photos` by hand, paste
  a trailing slash, and check focus after **Add Folder…** through the real panel.
- **M3.** File menu, context menu and toolbar by eye: order, dimming, the
  `paperplane` item in the default set, Customize and overflow.
- **M4.** Album pop-up with the mouse: the tick; with a key lacking `album.read`,
  the dimmed **New Album…** and its line.
- **M5.** Add, Edit, Cancel and Review Certificate from Publish: sheets swap
  cleanly, choices and description kept, Publish enabled after the return.
- **M6.** Skip or New Copy: Return is Skip, Esc returns. Results: Return and Esc
  close; the Run pop-up; selecting a reason.
- **M7.** A real run: **Stop** while a large photo renders (**Stopping…**) and
  while it uploads (never back to Uploading); **Show Results…**; Quit during a
  run, and again while it is ending (no question).
- **M8.** Export: with the watermark file missing, the warning shows; choosing a
  good image clears it; a non-PNG says so.
- **M9.** Import window during a publish: new uploads become In Library; Edit and
  Remove Server dimmed.
- **M10.** The owner's server (AC17): an https server shows no **Not encrypted**
  line; if its certificate isn't trusted, the publish sheet's wording.

## Follow-up

Open: F19 to F23. I confirm the fixes here. F1 to F8 and F10 to F18 are closed;
F9 is closed once F19 is.
