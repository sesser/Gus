# Publish to Immich: design review

Issue: #28. Reviewer: apple-ui-designer. Date: 2026-11-26. Branch
`feature/publishing-engine` at b244b48.

Compared with [`design.md`](design.md) (including §14), the PRD (revision 4) and
the HIG. Method: reading the sources, the String Catalog entries sampled for
plurals, `Info.plist`, the user guide and [`status.md`](status.md). Nothing was
run, and no snapshot of this UI exists to look at, so **nothing here was seen on
screen**.

## Verdict

**Changes needed.** The structure, placement and wording follow the design
closely. Seven faults must be fixed first. The worst: Cancel pressed during
**Checking…** doesn't stop the publish; Stop can fall back to a running state
while the run is ending; Retry Failed can start two runs; and the Export sheet,
which was to be unchanged, keeps a stale watermark warning.

## Findings

F1 to F7 break a requirement in a way that can send something the person didn't
ask for, lose their choices or regress Export. F8 to F12 are visible
violations. F13 to F18 are minor; fix each or say in `status.md` why not.

### Must fix

**F1. Cancel during "Checking…" still publishes.** `PublishModel.requestPublish`
(lines 535 to 567); the sheet's buttons (`PublishSheet.swift` 81 to 87).
Cancel only closes the sheet. The task goes on, and after the check and the
record lookup calls `start(...)`. If the sheet has been reopened meanwhile,
`begin()` has replaced `versionIDs`, so the old task works on the new
selection. The form also stays live: choosing another server during the check
leaves `start` pairing the newly chosen server record with the old server's
client, so records can be written under the wrong address.
Why it matters: Cancel is the promise that nothing happens, and the app can't
remove what it uploads (R9; design §3.8; HIG Sheets).
Fix: keep the confirming task and cancel it when the sheet closes by any route;
after every `await`, return unless the same sheet session is still open; disable
the form (not Cancel) while `isConfirming`.

**F2. An ending run can show itself as running again.** `PublishModel.cancel`
sets `progress.phase = .ending`, but `ProgressCounter` learns of ending only on
a fault. After the person's Stop, any photo that ends (`defer {
counter.finished() }`, `PublishJob.swift` 471) reports the old phase, and the
callback at `PublishModel.swift` 615 to 620 writes it back. With two photos in
progress the Activity row returns to **Uploading** with a progress bar, Stop and
File ▸ Stop Publishing come back on, and ⌘Q asks again (design §9; AC23).
Also, `cancel()` shows **Waiting for “‹name›” to answer…** even when no file is
awaited (a render in progress, say), which is untrue.
Fix: once stopping, nothing may clear that state (hold it as a model flag or
report it from the job). Show the waiting detail only while a fully sent file is
awaited; otherwise see ruling D-1.

**F3. Retry Failed is invisible, and repeatable, while it connects.**
`PublishModel.retry` (679 to 704) closes the sheet and awaits the server check
before `started` is set. For that time (long when the server is down, which is
when Retry is used) there is no Activity job, no Stop and no quit question, and
Publish and Retry Failed stay enabled, so a second run can start over the
first: `task`, `runningID` and `progress` are overwritten (R21 one publish at a
time; R23; design §10.3). A retry that ends at the check also keeps the old
`endedAt`, so the results show the earlier time.
Fix: mark the run started, with its Activity job and Stop, before the check, and
run the check inside the cancellable task (ruling D-2). Set `endedAt` on every
ending.

**F4. Retry Failed doesn't know the server was removed or moved.**
`retryRefusal` reads `publish.servers`, loaded only when the publish sheet opens,
after a server sheet and inside `retry`. Remove or re-address the server in the
Import window after a run: the button is enabled with no reason, and pressing it
closes the sheet and does nothing (AC21; design §10.3).
Fix: reload the servers when the results sheet appears and whenever the saved
list changes. A refusal found at press time must leave the sheet open with its
reason.

**F5. Coming back from Edit Server throws the choices away.**
`serverSheetSaved` calls `choose(saved)`, which reloads the server's remembered
album, visibility, stacking, preset and settings. A person who sets Archive, hits
a permission issue and takes the offered **Edit Server…** returns to
**Timeline** (R7 remembers only started runs), and could publish there without
noticing. Design §4 requires every choice and the description kept.
Fix: when the saved server is the one already chosen, keep the form as it is and
only reload what depends on the server (folder map, links, names) and run the
check. Load remembered values only when the selection moves to another server,
a newly added one included.

**F6. The server path is rewritten on every keystroke.** `PublishSheet.swift`
499 to 501 passes each edit through `serverPathKept`, which removes a trailing
slash. If the field takes the model's value back while being edited, typing
`/mnt/media` is impossible: the second `/` vanishes as it is typed. The debug
script's `map add` sets the string directly, so no check typed into the field.
I could not run it; the transformation is wrong either way (design §6 drops the
slash from what is kept, not from what is being typed).
Fix: bind the field to the text as typed; apply `serverPathKept` on Done, and
inside the example and issue calculations.

**F7. Export regression: the watermark warning no longer clears.** The shared
form's **Choose Image…** calls `editor.chooseWatermark`, which never reaches
`ExportModel.useWatermark`, the code that cleared `export.issue`
(`ExportSettingsForm.swift` 150; `ExportModel.swift` 149 to 173, now unused by
the button). After **The watermark image is missing. Choose it again.**, choosing
a good image leaves the warning; choosing a non-PNG keeps showing the old text
because `watermarkIssue` wins over the editor's. The scripted check calls
`export.useWatermark` and so can't see it (design §3.6, "Export behaviour does
not change").
Fix: let the host hear the result of the choice (a callback on the editor, or a
closure passed to `ExportSettingsSections`) and route Export through
`ExportModel.useWatermark`; make the script use the same route.

### Should fix

**F8. Publish Results shows the run that is still going.** `start` appends the
run to `runs` before it begins. During the first run **File ▸ Publish Results…**
is enabled and opens a sheet saying every photo is **Not published**; later it
opens the unfinished run in place of the last ended one, and the Run pop-up
lists it (design §2.1: enabled once a run has ended).
Fix: menu state, `resultsRun` and the pop-up use ended runs only.

**F9. The reopened sheet is publishable before it has loaded.** `begin()` leaves
`serviceID`, `check`, `client`, `names` and `sources` from the last time, and
`canPublish` ignores `isLoading`. Until `choose` finishes, **Publish** is the
enabled default over stale settings, so ⌥⌘E, Return can send them. `choose`
has the same window when switching servers. On the first opening, **Add a Server
to Publish To** shows briefly while servers load (`PublishSheet.swift` 53).
Fix: reset the check to checking at the top of `begin` and `choose`; include
`!isLoading` in `canPublish`; show the empty state only after loading.

**F10. An untrusted certificate gives no explanation.** `ServerText.result`
returns nil for `.untrustedCertificate`, so the Server section shows only **Try
Again** and **Review Certificate…** (design §3.3; HIG Feedback). It happens when
a server whose certificate the system trusted starts presenting one it doesn't.
Fix: ruling D-3.

**F11. A stale originals check comes back.** Changing server, stacking or the
folder map sets `originals = .notRun` without cancelling `originalsTask`, whose
next step writes progress and then a result for the old server or map. Reopening
or closing the sheet doesn't cancel it either. An album change also clears the
result, which design §7 doesn't ask for (a running check then reappears).
Fix: one function that cancels and clears, used by every stale trigger, `begin`
and sheet dismissal; none for the album.

**F12. Album pop-up.** (a) Its items are plain buttons, so nothing is check
marked; design §3.4 shows the selection ticked, and a pop-up marks its current
value (HIG Pop-up buttons). Use an inline `Picker` for None, New Album… and the
albums, as the Server menu does. (b) `canList` is false whenever the check
hasn't passed, so after a failed check the open menu says **Albums need
album.read on this key**, which the app doesn't know. Show that line, and dim New
Album…, only when the check passed and the permission is missing; dim the pop-up
unless the check passed.

### Minor

**F13. Announcements and hints** (design §13; ruling G-2). Announced today: the
album, stacking and Archive issues and the check summary. Not announced: the
Server permission issue, a failed server check, **albums couldn't be listed**,
**album is gone**, the settings issue, folder map issues, the start issue and
**The check stopped**. Only the Server menu and Show in carry hints. Use one
modifier for "issue under this control" so they can't differ.

**F14. Import window** (design §11, §4). `publishedRecordsChanged` is called only
when a run ends, so during a long run the app's own uploads are unmarked and can
be imported back; call it as each upload is recorded. The **Can't Import from**
view's **Edit Server…** and **Review Certificate…** stay enabled during a publish
and do nothing; dim them (`serverIsBusyPublishing`).

**F15. Activity** (design §9). The popover draws no progress view when
`progress` is nil, so an ending run has no spinner there; add a small one for
this job. **Waiting for “‹name›”…** is never replaced after a retried request
succeeds (`ProgressCounter` keeps `.waiting` until another photo starts a render
or upload); return to the phase of the step in hand.

**F16. Result wording** (design §10.2, §10.3).
- Server errors read **…the upload. bad request (400).**: the system's phrase is
  lower case and starts a sentence. See ruling D-4.
- A per-photo refusal from add-to-album is given an invented status 400
  (`PublishJob.swift` 378). Show the server's words alone.
- Not Finished sentences say **published, but** for an already-there photo; it
  must read **already on the server, but** there too (`PublishText.notFinished`).
- A retry whose check fails reports a Keychain refusal as **rejected the API
  key**, and a too-old or non-Immich answer as **stopped responding**
  (`PublishText.stop(for:)`). See ruling D-5.

**F17. Folder map focus.** **Add Folder…** must leave the new section's server
field focused (design §6; keyboard use).

**F18. A retry can overwrite newer remembered choices.** `finish` saves the
run's choices whenever its album was made by it, including a retry of an older
run after a newer one (R7). Update only the remembered album, and only if no
later run to that server has started.

## Rulings

On the engineer's known gaps:

- **G-1, Return in Description** (design §13): not a finding, and it stays a
  manual check (M3). As §13 says, Return may press Publish or insert a line.
  Doing neither is also acceptable, since nothing is then published by
  accident.
- **G-2, the Server section's issue is not announced**: not accepted. It is the
  issue that dims Publish whatever the options. Fixed with F13.
- **G-3, permissions changed after the check** hold until Check Again or Publish:
  accepted; that is the design.

New, where the design was silent or wrong (cite as "review D-n"):

- **D-1.** Stopping with no fully sent file awaited: same job, indeterminate,
  Stop dimmed, detail **Stopping…**. The waiting detail only while an answer is
  awaited.
- **D-2.** A retry's server check is part of the run: indeterminate, Stop
  enabled, detail **Checking “‹name›”…**.
- **D-3.** Untrusted certificate in the publish sheet: title **This server's
  certificate isn't trusted**, detail **macOS doesn't trust the certificate this
  server presented. Review it before publishing. Nothing was sent to the
  server.** Actions as designed.
- **D-4.** Upload refused: **not published: the server didn't accept the upload
  (‹status›). “‹message›”**. Other server causes: **The server answered
  ‹status›.** followed by the quoted message.
- **D-5.** A retry stopped by its check names what the check found: **Publishing
  stopped: ‹the check's title›.**, with **The key couldn't be read** for the
  Keychain.
- Correction to design §3.6: Export reports no empty template (it falls back to
  the original name), so the missing watermark is the only settings issue.
  Not a finding.

## Requirements and design issues

None new for the product manager. The engineer's RI-E1 (a trashed stack primary
returns to the stack) is still open; it changes nothing in the design, and the
user guide already states the real behaviour. I recommend its option (a).

## Design requirements

| Design | Requirement | Result |
|---|---|---|
| P1, §2.1 | File menu items, order, ⌥⌘E, Stop title | Pass, except Publish Results enabling (**F8**) |
| §2.2, §2.3 | Toolbar item, tooltip; context menu order | Pass by reading; look M5 |
| P2, §3.1 | Sheet size, header, sections, button bar | Pass by reading; M1 |
| §3.2 | Header and information lines | Pass |
| §3.3 | Server menu, address, Not encrypted, checking, Keychain, no server | Pass; **F9**, **F10**; https absence M13 |
| §3.4 | Album states, gone album, Archive captions | **Fail** (F12); texts and Archive warning pass |
| §3.5 | Stacking controls and captions | Pass |
| P3, §3.6 | Shared settings form, presets, description, captions | Pass in Publish; Export **fail** (F7) |
| §3.6 | Settings page Cancel and Done | Pass |
| §3.7 | What is remembered | Pass; **F18** |
| §3.8 | Publish dimming, Cancel sends nothing | **Fail** (F1, F9) |
| P4, §4 | Server sheet by host, replace and return | **Fail** on return (F5); permissions, captions, no Remove pass |
| §4 | Edit and Remove dimmed while publishing | **Fail** in one view (F14) |
| P13, §4.1 | New wording, `Info.plist`, no "only reads" claim | Pass |
| P14, §4.2 | Address warning | Pass |
| P5, §5 | Missing permissions under options, Check Again | Pass |
| P6, §6 | Folder map page | **Fail** (F6, F17); rest pass |
| P7, §7, §7.1 | Check Originals, groups, reason sentences | Texts pass; staleness **fail** (F11) |
| P8, §8 | Skip / New Copy / Cancel | Pass by reading; keys M8 |
| P9, §9 | Activity job, Stop, ending, one run | **Fail** (F2, F3, F15) |
| §9 | Quit question, quit while ending | Pass in a steady state; affected by F2; M10 |
| P10, §10.1 | Activity row, lines, plurals, Show Results… | Pass |
| §10.2 | Results sheet | Layout and sections pass; **F16**; keys M6 |
| §10.3 | Retry Failed | **Fail** (F3, F4) |
| P11, §11 | Import window marks | Tooltip and marks pass; timing **fail** (F14) |
| P12, §12 | Nothing in Settings, sidebar, importer, `photocli` | Pass |
| P15 | Archive with stacking warns, doesn't block | Pass |
| P16 | Already There, Nothing Else Done | Pass |
| §13 | Keyboard, announcements, plural strings | **Fail** (F13); M2, M3 |
| §14 | Debug script drives the listed checks | Pass; the script sets fields directly, so F6 and F7 slipped past |

Acceptance criteria as seen from the UI: AC21 fails (F4, F3). AC23's engine
behaviour is tested, but what Activity and Stop show fails (F2). AC13's Cancel
passes for the question; Cancel before it fails (F1). AC1, AC4, AC5, AC15, AC18
(http), AC19, AC22 and AC25 pass by reading and the engineer's scripted checks.
Code review and QA judge the rest.

## User guide

Terms match the UI: Publish, Add Server…, Edit “‹name›”…, Album, Show in, Stack
with original, Edit Folder Map…, Check Originals, Edit Settings…, Check Again,
Skip, New Copy, Stop Publishing, Not encrypted (http), Show Results…, Publish
Results…, Run and Retry Failed. The trashed-member, lost-answer and
unfinished-step texts are present (AC22). One correction: "it uploads no photo
twice" needs "except after a lost answer, described above" (R23).

## Improvements (judgment calls)

- Results sheet: names are cut to a 120 pt column; add `.help` with the full
  name.
- A one-photo check reads **Originals found for 1 of 1 photos.**; word the case
  of one photo on its own if the catalog allows it.
- The File Settings page shows no missing-watermark warning although the main
  page does; pass `editor.settingsIssue` to the form there.

## What's working

- One shared settings form and preset row, not a copy.
- The Server sheet's host rules, captions and address warning.
- Permission issues sit under their options and follow them at once.
- Reason, result and plural strings match the design, including "are … them".
- The Archive warning, the Skip default, and an ending run keeping ⌘. on its own
  job (once F2 holds the state).

## Manual checks (a person, bundled app, scratch library and a test server)

- **M1.** Publish sheet, File Settings, folder map and results at the smallest
  window: nothing clipped, buttons visible, long Archive warning and addresses
  wrap or truncate, readable with Increase Contrast.
- **M2.** Keyboard only (with Keyboard Navigation on): ⌥⌘E, every control, both
  pages, Publish; the grid or loupe has the keyboard after each sheet closes.
- **M3.** In Description: what Return and Option-Return do. Note which (ruling
  G-1).
- **M4.** Folder map, typed by hand: `/mnt/media/photos` with every slash, edit
  in the middle, paste with a trailing slash; Add Folder… focus; Choose…;
  **(not connected)** with the volume away.
- **M5.** File menu, context menu and toolbar by eye: order, dimming, the
  `paperplane` item present by default, in Customize and in the overflow menu.
- **M6.** Publish Results: Return and Esc close it with nothing focused; the Run
  pop-up with two runs; selecting and copying a reason.
- **M7.** Add, Edit, Cancel and Review Certificate from Publish: the sheets swap
  cleanly, choices and description are still there.
- **M8.** Skip or New Copy: Return is Skip, Esc returns to the sheet.
- **M9.** Activity during a run: toolbar item and popover, Stop while rendering
  and while uploading a large file (the row never returns to Uploading), **Show
  Results…** from the popover opens the sheet.
- **M10.** Quit during a run (Return and Esc keep publishing; Stop and Quit), and
  ⌘Q while a run is ending (no question, quits within the bound).
- **M11.** Export sheet looks and behaves as before: section order, presets,
  watermark choose, and the missing-image warning clearing.
- **M12.** Import window: published photos marked with their tooltip; Edit and
  Remove Server dimmed during a publish.
- **M13.** AC17 on the owner's server; an https server's sheet shows no Not
  encrypted line.

## Follow-up

Open: F1 to F18. I confirm fixes here.
