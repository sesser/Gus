# Publish to Immich: design review

Issue: #28. Reviewer: apple-ui-designer. Date: 2026-11-26. Branch
`feature/publishing-engine`. Third pass at eb34859 (first at b244b48, second at
a382a7b).

Compared with [`design.md`](design.md) (rulings in its §16 and §17), the PRD
(revision 7) and the HIG. Method: reading the current sources that
[`status.md`](status.md) names for the second round, the catalog entries it
changed, the user guide, and the engineer's 22 retaken snapshots (`round2/shots`).
Nothing was built or run, and the diff against a382a7b was not run (no shell in
this review). The snapshots draw the default button as in an inactive window, and
the Activity popover's glass comes out colored; neither is a finding.

## Verdict

**Changes needed, all small; no blocker.** F19 to F23 are fixed, and D-10 and
D-11 are built as ruled. Three faults are open (F24 to F26): the two the
engineer asked about as DQ-R2-1 and DQ-R2-2, now ruled (D-12, D-13), and one in
the Check Originals list that earlier passes missed. F27 and F28 are minor and
optional.

## Open findings

### Must fix

**F24. Retry Failed is offered when it has nothing to send** (DQ-R2-1, ruling
D-12). After a later publish has sent a run's remaining photos, the older run
still shows the button. Pressing it sends nothing and ends the run again as
completed, so the results then read **Failed 1**, **Not published 1**, no stop
line, and the button again (`23-results-newest-after-retry.png` shows exactly
this). The Activity message says "not published because publishing stopped" for a
run that now reads as completed. Publishing again after fixing a key is an
ordinary way to get here. Why it matters: a button that is on and does nothing,
as often as it is pressed (HIG Buttons, Feedback).
Fix (design §10.3): no button when every photo it would cover is left out because
a later run published it; in its place, the caption **A later publish already
sent the photos left to retry.** Counts, lists and messages are unchanged.

**F25. The sheet keeps a removed server's state** (DQ-R2-2, ruling D-13). C10
dims Publish and Check Originals, but the model still holds the removed server's
check, albums and folder map. Seen in `26-publish-chosen-server-removed.png`:
**Edit Folder Map…** is on, the "no original can be found yet … this server" line
stands, and nothing says why Publish is off. By reading: the **Album** pop-up is
still on with the removed server's albums; if its check had failed or lacked a
permission, **Try Again** and **Check Again** do nothing and **Edit Server…**
opens Add Server; the folder map page is titled **Folder Map for “”**.
Fix: design §3.3, "The chosen server is removed".

**F26. Check Originals' photo lines are centered on each other.** `ReasonGroup`
(`PublishSheet.swift`) puts its `Text`s straight into the `DisclosureGroup`,
whose stack centers them. In `06-check-originals-result.png` the first line starts
3 pixels right of the other two, only because its digits are narrower; with
file names or paths of different lengths, and in the "And ‹n› more." line, the
left edges stagger visibly. Why it matters: a list is read down its leading edge
(HIG Layout, alignment). Design §7.
Fix: wrap the content in `VStack(alignment: .leading, spacing: 4)` with
`.frame(maxWidth: .infinity, alignment: .leading)`.

### Minor (optional)

**F27. On File Settings, a bad watermark pick is hidden while the image is
missing.** The page passes `publish.settingsIssue` to `ExportSettingsSections`,
which shows it in preference to `editor.watermarkIssue`. Choosing a non-PNG then
changes nothing on screen. Fix: pass
`publish.editor.watermarkIssue ?? publish.settingsIssue`. Export is not affected.

**F28. An address changed in the import window leaves the old check up** (by
reading). `serversChanged` only reloads the records, so the open sheet shows the
new address over the old address's check, albums and Check Originals client until
**Check Again** or another choice. **Publish** connects afresh, so this is about
what is shown. Fix: when the chosen record's address or trusted certificate
differs after a reload, run `choose(_:keepingChoices: true)`.

## Second-pass findings, confirmed against eb34859

| # | Finding | Result |
|---|---|---|
| F19 | Publish stayed dimmed | **Fixed.** `client` and `session` are observed; `01` shows **Publish 3 Photos** on with nothing pressed, and the A/B copy (`01b`) shows it off. Return publishing: M2. F9 is closed with it |
| F20 | "1 of 1 photos." | **Fixed.** Both keys replaced, old entries gone (`25`, `10`) |
| F21 | "them" about one photo | **Fixed** by reading (code and catalog; "The other ‹n› photos" inflects). The alert is unseen: M6 |
| F22 | "Rendering 0 of 2" on a steps-only retry | **Fixed** by reading (first report and `steps` both report Uploading) and the engineer's test; unseen |
| F23 | Newest run | **Fixed.** `PublishRun.byEnding`; the retried run opens by default (`23`). Pop-up order by reading |

## D-10 and D-11 as built

| Ruling | Result |
|---|---|
| D-10: a Stop during the check is not an ending | **Pass** by reading: `PublishRetry.perform` and `ended(stopAsked:)`, then `release` with no `finish`, so no message, announcement or sheet. Run unchanged on screen (`19`, `21`) and the next retry covers it (`22`) |
| D-10: **Stopping…**, Stop dimmed, until the check returns | **Pass** by reading; the moment was too short to capture: M7 |
| D-10: an open results sheet stays on its run | **Pass** by reading (`resultsRunID` untouched; the retried run is left out until released): M7 |
| D-11: **Show Results…** dimmed during the retry | **Pass** (`16` dimmed, `19` on again); `showResults` opens no other run |

## Export

The change in this round (`ExportSettingsEditor.useWatermark` loads the image
after setting it) keeps Export acceptable. Choosing the same image again after
its file had gone now clears the warning and draws the mark (`17`, `18`); a
non-PNG says so and keeps the earlier choice (`17b`). A pick of a different image
loads it twice, which shows nothing. F7 is now seen as well as read.

## Snapshots

| Files | What is on screen |
|---|---|
| 01, 02, 03 | As designed: enabled Publish; New Album with its note and button; Archive warning wraps |
| 06, 06 dimmed, 06 result, 25 | As designed apart from F26 |
| 09, 10, 13, 21, 22 | Results as designed; 13 now has its stop line |
| 15, 16, 19 | Activity as designed |
| 23 | Order right; **F24** |
| 24 | Sheet behind the one-photo question |
| 26 | **F25** |
| 17, 17b, 18 | Export, as above |

Nothing is clipped or overlapping.

## Design requirements

| Design | Requirement | Result |
|---|---|---|
| P1, §2.1 | File menu items, order, ⌥⌘E, Stop title, enabling | Pass by reading; M3 |
| §2.2, §2.3 | Toolbar item; context menu | Pass by reading; M3 |
| P2, §3.1, §3.2 | Sheet, header, sections | Pass (01, 25); smallest window M1 |
| §3.3 | Server section | Pass (01); **fail** on a removed server (F25) |
| §3.4 | Album, Archive captions | Pass (02, 03); M4 |
| §3.5 | Stacking | Pass (06) |
| P3, §3.6 | Shared form, presets, description | Pass; F27 optional; M8 |
| §3.8 | Publish enabling; Cancel sends nothing | Pass (01) |
| P4, P13, P14, §4 | Server sheet by host, wording, address warning | Pass by the second pass (no change); M5 |
| P5, §5 | Missing permissions | Pass (06 dimmed) |
| P6, §6 | Folder map | Pass by the second pass; M2 |
| P7, §7 | Check Originals | Wording passes; **fail** alignment (F26) |
| P8, §8 | Skip / New Copy | Pass by reading; M6 |
| P9, §9 | Activity, Stop, ending, quit | Pass (15, 16); M7 |
| P10, §10 | Activity row, results, Retry Failed | **Fail** offering an empty retry (F24); rest pass |
| P11, §11 | Import window marks | Pass by reading; M9 |
| P12, P15, P16 | Nothing elsewhere; Archive warns; Already There | Pass |
| §13 | Keyboard, announcements, plurals | Pass by reading; M2 |

## User guide

Matches the UI and PRD revision 7, the retry's Stop and the dimmed **Show
Results…** included. With F24 it needs a few words where it says when Retry Failed
is offered (not when a later publish already sent what was left).

## Rulings

D-12 (DQ-R2-1) and D-13 (DQ-R2-2) are recorded in [`design.md`](design.md) §17
and the sections it names. Neither changes a requirement.

## Requirements and design issues

None for the product manager.

## Manual checks (a person, bundled app, scratch library and a test server)

After F24 to F26 are fixed.

- **M1.** Publish sheet, both pages and results at the smallest window, also with
  Increase Contrast; long addresses.
- **M2.** Keyboard only: ⌥⌘E, every control, **Return** publishes straight after
  the check with no click first; note what Return and Option-Return do in
  Description; focus returns to the grid or loupe. In the folder map type
  `/mnt/media/photos` by hand, paste a trailing slash, and check focus after
  **Add Folder…** through the real panel.
- **M3.** File menu, context menu and toolbar by eye: order, dimming, the
  `paperplane` item in the default set, Customize and overflow.
- **M4.** Album pop-up with the mouse: the tick; with a key lacking `album.read`,
  the dimmed **New Album…** and its line.
- **M5.** Add, Edit, Cancel and Review Certificate from Publish: sheets swap
  cleanly, choices and description kept, Publish enabled after the return. With
  the sheet open, remove its server in the import window.
- **M6.** Skip or New Copy, for one published photo and for several: wording,
  Return is Skip, Esc returns. Results: Return and Esc close; the Run pop-up;
  selecting a reason.
- **M7.** A real run: **Stop** while a large photo renders (**Stopping…**) and
  while it uploads (never back to Uploading); **Stop** while a retry checks a slow
  server, with another run's results open (nothing changes); **Show Results…**;
  Quit during a run, and again while it is ending (no question).
- **M8.** Watermark file missing, in Export and in Publish ▸ File Settings: the
  warning shows; choosing the same image again clears it (in Publish this is
  unverified); a non-PNG says so.
- **M9.** Import window during a publish: new uploads become In Library; Edit and
  Remove Server dimmed.
- **M10.** The owner's server (AC17): an https server shows no **Not encrypted**
  line; if its certificate isn't trusted, the publish sheet's wording.

## Follow-up

Open: F24 to F26 (F27 and F28 optional). I confirm the fixes here. F1 to F23 are
closed.
