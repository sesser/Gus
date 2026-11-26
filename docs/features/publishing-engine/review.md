# Publish to Immich: design review

Issue: #28. Reviewer: apple-ui-designer. Date: 2026-11-26. Branch
`feature/publishing-engine`. Sixth pass at 586cfd2 (first at b244b48, second at
a382a7b, third at eb34859, fourth at 41f6d0f, fifth at f5d5f09).

A narrow pass: whether D-17 to D-19 ([`design.md`](design.md) §10.3, §11.1,
§11.2, §17) are built as ruled, the user guide sentences the engineer wrote for
them in the import section, and the QA-round change to the publish sheet's
failed-check text. Method: reading the current sources, the engineer's script
logs A to F with their scripts (`round6`), and one snapshot (`round5/q4-Gus.png`,
looked at). Nothing was built or run, and no diff was run (no shell in this
review). Test results are as [`status.md`](status.md) records them. Round 6 took
no snapshots, so how the windows look under D-18 and D-19 rests on reading.

## Verdict

**D-17 and D-19 are built as ruled. D-18 is too, except in two rename cases
(F30, F31).** The publish sheet's failed-check text passes. Four findings, all
low: two in the UI, two in the user guide. None blocks QA. F30 and F31 change
source, so they take the code reviewer's second pass.

## Findings

**F30 (low, D-18).** A rename saved while the import window is checking that
server is undone in the window.

- `connectServer` reads the row, then runs the network check. A name saved from
  Publish during the check is taken in place (`loadServersAfterPublish`). The
  check then returns the row it read earlier, and `takeSaved(saved)` in the
  `.ready` case puts the old name back (`ServerSource.swift`).
- The person sees the old name in the title, Source pop-up and inspector, and an
  untyped Project name returns to the old prefill, so an import then makes a
  project under the old name. **Edit Server…** opens on the old record. The next
  check puts it right.
- It needs the save to land while a check is out, so a slow server makes it
  likelier; the reconnect after an import counts. By reading; no test or script
  covers it. The Source pop-up's list would show the new name beside the old
  title.
- Fix: take the check's row only if the window's record hasn't changed since the
  check began (compare `browse.service.name` with the captured `service.name`).
  Check by holding the check (`fault slowcheck`), renaming from Publish and
  printing the window afterwards.

**F31 (low, D-18).** After a rename, marked cells already on screen keep the old
name in their tooltip (**Published to “‹name›” from this library**, and the
imported one).

- `ImportGridView` receives only `shots` and `selection`, and `update` reconfigures
  cells only when one of them changes. A rename changes neither. A scroll or a
  selection change corrects them.
- §11.1's list names the title, pop-up, inspector and editor, not tooltips. "The
  window takes the saved name in place" covers them: a tooltip naming a server
  that no longer has that name reads as a second server.
- Fix: give the grid view the server's name, read in the parent's body, and
  refresh the visible cells when it changes. By reading.

**F32 (low, user guide).** "**Save** and **Trust Certificate** with the key field
empty send and save nothing once the other sheet has saved" says more than is
true. If the other save lands while this sheet is already checking, the check
goes on sending, with the key that belongs to its address (log E: two keyed
requests to the old address after the save). D-19 promises no write then, not
silence. "The window shows the server as saved" also leaves out what Publish
does, and a new key alone saved during a check blocks the write too. Suggested:

> If a server's sheet is open in each window and one saves a new address or
> certificate, **Save** or **Trust Certificate** in the other, with its key field
> empty, sends and saves nothing: the sheet closes and the server shows as saved
> (from **Publish…**, the publish sheet comes back with it chosen and checks it
> again). If the other save arrives while this sheet is already checking, the
> check finishes against the address it started with, using the key saved for
> that address, and nothing is saved. A new key saved elsewhere during a check
> also stops this sheet from saving.

**F33 (low, user guide terms).** Same section.

- "saved again from **File ▸ Publish…** (its **Edit Server…**)": the publish
  sheet's menu item reads **Edit “‹name›”…**. **Edit Server…** appears only under
  a failed check, and **Review Certificate…** saves too. Suggested: "saved again
  from **File ▸ Publish…** (**Edit “‹name›”…**, **Edit Server…** or **Review
  Certificate…**)".
- Earlier in the section, "the app contacts a server only when you choose it, or
  press **Add**, **Save**, **Try Again** or **Rescan**" is no longer true of the
  app, which also contacts one for publishing. Suggested: "The import window
  contacts a server only when you choose it, press **Add**, **Save**, **Try
  Again** or **Rescan**, save it from **File ▸ Publish…**, or finish an import
  from it."

The rest of the new sentences match the build: the window follows whether in
front, behind or closed; a rename shows in place; what goes with a new address or
certificate; a saved key never reaching the old address; and the running import.

## D-17: Retry Failed called off as its check starts

| Ruled (§10.3) | Result |
|---|---|
| A changed or removed server, or an unreadable catalog: nothing sent, the run as it was | **Pass** by reading (`PublishRetry.perform`: `.changed`, `.unreadable` give `calledOff`) |
| The job leaves Activity with no message, announcement or sheet | **Pass** by reading (`release`, not `finish`) |
| Reopened: removal or address change shows the refusal with **Retry Failed** off; a certificate change alone is no refusal | **Pass** by reading (`retryRefusal`, servers reread on appearing) |

## D-18: the saved server changes while it is the Import window's source

| Ruled (§11.1) | Result |
|---|---|
| Every check reads the key with its row; only the held address and certificate are contacted | **Pass** by reading (`connectServer` has one path, `RemoteImportConnection.connect`) |
| Keychain refusal as today; unreadable catalog as the Keychain result under **Can't Connect to ‹name›** | **Pass** by reading (F: refusal) |
| Follows as soon as the publish save is read, wherever the window is; one check per save | **Pass** (A); closed and minimized by reading, M8 |
| Window not brought forward, keyboard not moved | **Pass** by reading; M8 |
| New address: connects again; selection, pages, All Photos, no range, prefilled name; no request to the old address | **Pass** (A) |
| Date Range popover closes, marks reread, old requests cancelled, earlier **Imported ‹n› photos** goes; destination, templates, Add to, job code, preset stay | **Pass** by reading |
| Certificate change alone treated the same; removed as after Remove Server… | **Pass** by reading |
| Name only: in place, nothing contacted, selection, pages, album, range kept | **Pass** (B, B2: no window request); **F30**, **F31** |
| Project name follows only if not typed | **Pass** (B, B2); **F30** |
| Title, Source pop-up, inspector, **Edit Server…** take the name | **Pass** by reading; **F30** |
| Key only: nothing reloads, next check reads it | **Pass** by reading |
| Import running: nothing changes; originals from the old address | **Pass** (C). Source pop-up is dimmed, label unchanged (by reading) |
| A check during the run that finds the change sends nothing and leaves grid, state and selection | **Pass** by reading |
| After the run: follows, ending subtitle kept; a rename taken then too | **Pass** (C: new address, **Imported 6 photos**); rename by reading |
| Run's alert unchanged; publish **Edit Server…** not dimmed for an import | **Pass** by reading (C: saved during the run) |

## D-19: a Server sheet behind the saved server

| Ruled (§11.2) | Result |
|---|---|
| At the press: D-16 first, then key with row; behind, nothing sent or written | **Pass** (D); order by reading |
| At the save: row written only with the same address, certificate and checked key, as one step | **Pass** (E: no write) and by reading (under the account's gate) |
| A failed check shows its result as usual | **Pass** by reading |
| The sheet closes, no alert, no new string | **Pass** (D, E) |
| From Import: servers reread, server chosen as saved, grid takes the keyboard, publish side told | **Pass** (D, E); keyboard by reading, M8 |
| From Publish: sheet returns, server chosen and rechecked, choices and description kept, no D-15 line, nothing remembered or published | **Pass** by reading only: D and E use the import window's sheet as the stale one. M8 |
| Typed key, name-only Save and Add unaffected | **Pass** by reading |

## Publish sheet: failed-check text (QA Q4)

**Pass.** The sheet's title and detail, the Server pop-up's hint and the
announcement all come from `PublishText.checkTitle` and `checkDetail`, and the
words match §3.3: `ServerText`'s for ordinary failures, D-3's for an untrusted
certificate, **The key couldn't be read** with the system's text for the
Keychain. Buttons are unchanged. The snapshot shows the Keychain case under the
address and **Not encrypted** line, with **Try Again**, **Edit Server…** and a
dimmed **Publish 1 Photo**.

## Follow-ups

Both stand from the fifth pass; neither holds this branch.

1. **Publish sheet keeps an old check after its own Server sheet is cancelled**
   (bug; what is left of D-14). By reading, **Check Originals** in that state also
   still asks the earlier address, with the key it was checked with, while
   matching records by the new one. Nothing is written, and **Publish** connects
   afresh. Expected: when the publish sheet comes back and the saved address or
   certificate differs from the one checked, it checks again, keeping every
   choice. No D-15 line, since nothing was given up.
2. **A name-only Save whose catalog write fails says nothing** (bug, #271's
   code). A checked Save's catalog failure is headed **The key couldn't be
   saved** with **The Keychain returned an error: …**, so don't copy it. Expected:
   both say the library couldn't be read or written, in wording the designer rules
   on then. Add: the import window's grid also heads a Keychain **read** refusal,
   and under D-18 an unreadable catalog, **The key couldn't be saved** (log F).
   That is as D-18 ruled ("as today"), so not a finding here, but it belongs in
   the same fix.

## Design requirements

| Design | Requirement | Result |
|---|---|---|
| P1, §2.1 | File menu items, order, ⌥⌘E, Stop title, enabling | Pass by reading; M3 |
| §2.2, §2.3 | Toolbar item; context menu | Pass by reading; M3 |
| P2, §3.1, §3.2 | Sheet, header, sections | Pass; smallest window M1 |
| §3.3 | Server section, failed states, D-13 and D-15 | Pass; M5 |
| §3.4 | Album, Archive captions | Pass; M4 |
| §3.5 | Stacking | Pass |
| P3, §3.6 | Shared form, presets, description | Pass; M4 |
| §3.8 | Publish enabling; Cancel sends nothing that writes | Pass |
| P4, P13, P14, §4 | Server sheet by host, wording, address warning, D-16 | Pass; M4, M5 |
| P5, §5 | Missing permissions | Pass |
| P6, §6 | Folder map | Pass; M2 |
| P7, §7 | Check Originals | Pass |
| P8, §8 | Skip / New Copy | Pass by reading; M5 |
| P9, §9 | Activity, Stop, ending, quit | Pass; M6 |
| P10, §10 | Activity row, results, Retry Failed | Pass |
| §10.3, D-17 | Retry called off silently | Pass by reading |
| P11, §11 | Import window marks | Pass by reading; M6 |
| §11.1, D-18 | The window follows the saved server | **F30**, **F31**; otherwise pass; M8 |
| §11.2, D-19 | A Server sheet behind the saved server | Pass; M8 |
| P12, P15, P16 | Nothing elsewhere; Archive warns; Already There | Pass |
| §13 | Keyboard, announcements, plurals | Pass by reading; M2 |

Rows not about D-17 to D-19 or the failed-check text rest on the earlier passes.

## Earlier passes

F1 to F28 were closed by the fourth pass, with D-12, D-13 and the Failed list's
repeated row confirmed at 41f6d0f. The fifth pass approved D-15 and D-16 as built
(including `answer(skip:)` counting as a confirming Publish) with one user guide
fix, F29, which now reads as asked ("nothing is uploaded or changed on the
server"): **closed**. D-14's accepted cases still standing: a key-only change
isn't noticed by an open sheet; the publish sheet's own Server sheet stays up
when its server is removed (a Save ends as D-16 says); and follow-up 1.

## Requirements and design issues

None for the product manager. No new design ruling.

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
- **M8.** The same server in both windows (it needs two addresses, such as its
  name and its IP). With the import window behind the library window, then
  minimized, then closed, save the other address from Publish's **Edit
  “‹name›”…**: the import window doesn't come forward, the library window keeps
  the keyboard, and the import window shows the new address when brought back.
  Save only a new name and hover an **In Library** photo that was already on
  screen (after F31). Then open Edit Server in both windows, key field empty, save
  a new address in one and press **Save** in the other, once each way round: the
  second closes with no alert. From Publish, the publish sheet comes back with the
  server chosen, choices and description kept and no line under Server; from
  Import, the grid takes the keyboard.

## Follow-up

F1 to F29 are closed. Open: F30 to F33 (low), M1 to M8, and the two follow-ups
above.
