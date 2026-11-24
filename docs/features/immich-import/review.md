# Import from Immich: design review

Owner: apple-ui-designer. Date: 2026-11-23. Issue #271, branch
`feature/immich-import` at 2552143. Reviewed against [design.md](design.md)
(D1 to D14, §2 to §10, §15), the acceptance criteria as recorded in
[status.md](status.md) (PRD rev4), the HIG and `docs/USER_GUIDE.md`.

**How this was reviewed.** From source only: `Sources/PhotoUI/Import/`
(`ImportWindow`, `ServerSheet`, `ServerSource`, `ServerText`, `ImportCell`,
`ImportGrid`, `ImportCommands`), `Sources/PhotoApp` (`PhotoApplication`,
`DebugServerCommands`, the sheet precedents), the String Catalog entries, the
user guide and `status.md`'s debug-script run. I did not run the app, and I had
no shell, so I did not run `gh issue view 271`: the criteria are read from
`status.md`'s table, which quotes rev4. Nothing below claims a look or a key
press that I did not read in code; those are manual checks.

## Verdict

**Not ready for sign-off: one blocking finding and five should-fix findings, all
in the Server sheet and what follows it.** The rest is built as designed, often
closely (D1 to D14 hold; the strings match §3.4, §4 and §6 word for word; the
security prompts have the wording and button rules the design asked for). The
blocking finding is a dead end in the one place a changed certificate can be
trusted. The should-fix ones are a lost key field, a sheet with no height rule,
a confirmation presented while its sheet closes, keyboard focus that never
reaches the grid after Add, and a VoiceOver grouping that swallows a button.

Three provisional copy items are ruled (DQ-7 confirmed, DQ-8 and DQ-9
rewritten); design.md §3, §6.2, §7, §10 and §15 are updated.

## Findings

### Blocking

**B1. Trust Certificate does nothing on the changed-certificate page when
nothing else was edited.** `ServerSheet.swift:93-97, 99-103, 117-128, 213-219`.
Review Certificate… in the grid's Can't Connect state opens the Edit sheet
directly on page 2 (`ServerSource.swift:415-422`). Trust Certificate then sets
`trusted`, returns to page 1 and calls `submit()`. But `changed` ignores
`trusted`, so `canSubmit` is false for an Edit with no new key, address or name,
and `submit()` returns at its guard: nothing is checked, nothing saved, no
message. Even a name-only edit afterwards takes the "name-only" branch
(`:121-128`), which saves the old record and drops the new pin. The design says
this is "the only place a pinned certificate can be replaced" (§3.5); today it
works only if the person also retypes the key. The debug script missed it
because its `trust` command was only run on the Add path.
Fix: a pending `trusted` counts as a change (`changed`) and as needing a check
(`ServerFormRules.needsCheck` gets a `trustedPending` argument), so the check
runs with the key read from the Keychain and the new pin is saved on a pass.
Put the rule in `ServerFormRules` (PhotoCore) so a Swift Testing test can pin it:
Edit, only `trusted` set, `canSubmit` true and `needsCheck` true. Principle:
Consistency and user control; the requirement is R6.

### Should fix

**S1. The API key field empties when the sheet changes page.**
`ServerSheet.swift:264, 249-256`. The key is `@State` in `ServerFormPage`, which
the `switch` in `ServerSheet.body` destroys when the page becomes Certificate.
Back or Cancel on page 2 (§3.5 promises "the form as it was"), or a failed check
after Trust, returns to a field that shows nothing while the model still holds
the key and `keyEntered` is true, so **Add** is enabled and sends a key the
person cannot see. A masked field that looks empty but is not is the worst way to
fail a credential field. Fix: hold the text in `ServerSheet` (or the model) and
pass a `Binding` down so the field redraws with its dots, or clear the model's key
when the page is left; the first is the one the design describes. The debug
script drives `setKey` on the model and never touches the view, so it cannot
see this; M2 checks it.

**S2. The sheet has no height rule.** `ServerSheet.swift:257-258`. Export,
Merge and Copy Adjustments each give a grouped `Form` in a `.fitted` sheet
`.frame(minHeight:, idealHeight:)` (`ExportSheet.swift:29`, `MergeSheet.swift:31`,
`CopyAdjustmentsSheet.swift:43`); the Server sheet gives none, and §3.1 asks
for "about 360 pt for Add, +90 when the notice shows, never taller than the
window minus 40 pt". A scroll-backed `Form` has no content-sized ideal height,
so the form may collapse or clip, and the notice appearing may jump the sheet
(I can't see which from source; M1 does). The debug `sheet print` also lacks the
size-against-ideal line §11 asked for. Fix: the CA pattern
(`CopySheetMetrics.idealHeight`: content height, clamped to the window, never
under a minimum) with the notice's 90 pt as an input, and add size and ideal to
`sheet print`.

**S3. Remove Server… from the sheet presents its confirmation while the sheet
is closing.** `ServerSheet.swift:228-232`, `ServerSource.swift:424-427`.
`remove()` sets `serverSheet = nil` and, in the same turn, `removingServer`, so
the confirmation dialog is requested on a window whose sheet is still on screen.
SwiftUI can drop a presentation requested during another's dismissal. The path
the debug script exercised calls `askToRemoveServer` directly, never through the
sheet. Fix: set `removingServer` from `.sheet(item:onDismiss:)` (keep the pending
service in the model until then). M3 checks it.

**S4. After Add or Save the keyboard is not on the grid.**
`ServerSource.swift:451-457`, `ImportGrid.swift:238-244`. §7 promises "Space,
arrows and ⌘A work at once". `serverSaved` calls `chooseServer` (which replaces
the grid with the Connecting state) and then
`ImportCollectionView.focus(in:)`, which only finds a grid that is already in the
window: at that instant it is not, or it is the old one about to go. Fix: request
focus when the first page lands (when `gridState` becomes `.photos` after a
sheet-initiated choice), once. Cancel/Esc needs nothing (the window's first
responder was never changed).

**S5. The result block hides its own button from VoiceOver.**
`ServerSheet.swift:374`. `.accessibilityElement(children: .combine)` wraps the
title, detail and, for a changed certificate, the **Review Certificate…**
button; a combined element is one element, so the button is no longer a control
of its own. Fix: `.accessibilityElement(children: .contain)` on the block, or
combine only the two texts. Owner checks of VoiceOver are not asked for (CI
policy); this is a code finding.

**S6. The Album and Date Range titles are unbounded.**
`ImportWindow.swift:748, 768`. §4.1 says the labels truncate; an album called
"Trip to Lisbon with the whole family, 2019" and a set date range ("Nov 1, 2026
to Nov 30, 2026") make the navigation group wider than the toolbar's budget at
900 pt and send Rescan, then the status, into overflow before they truncate.
Fix: `Text` title with `.lineLimit(1).truncationMode(.middle)` and a maximum
width (about 180 pt) for the Album item, as `ToolbarMetrics.statusLine` does for
the status. Judgment on the width; the requirement is §4.1's.

### Nits (no change needed to pass)

- **N1.** §8 asked for a check's result to also be the field's accessibility hint
  (`ServerSheet.swift:334-338` only announces it). The announcement is the main
  mechanism; add the hint when S5 is touched.
- **N2.** The changed-certificate page shows the old and new fingerprints without
  dates beside each (`ServerSheet.swift:439-441`); §3.5 asked for them. The first
  paragraph already names the date the old one was trusted. Add the new
  certificate's "Valid" row under "Now" if it is cheap; otherwise accepted.
- **N3.** The subtitle for a plain-http server with no photos yet drops the first
  three characters of " · Not encrypted" to make "Not encrypted"
  (`ImportWindow.swift:106`); that assumes the English separator. A catalog entry
  `Not encrypted` and building the suffix from it is safer.
- **N4.** After a Stop-less finish with failures and nothing imported, the alert
  title says "Imported 0 photos. 2 could not be imported." while Activity says "No
  photos were imported." (`ServerText.swift:221`, §6.2). Cosmetic; consider "No
  photos were imported. 2 could not be imported." for the zero case.
- **N5.** The date range popover has two controls named "From" (check box and
  picker) and two named "To" (`ImportWindow.swift:826-835`); VoiceOver says the
  same word twice. Name the pickers "From date" and "To date". The reversed-range
  line is not announced when it appears.
- **N6.** The inspector's Name row has no line limit
  (`ImportWindow.swift:626`); a long name wraps to several lines. Acceptable, but
  `.lineLimit(2)` with a tooltip keeps the section short.

### Deviations from the design that are accepted (design.md updated)

| Where | Built | Why accepted |
|---|---|---|
| §3.4 missing names | Plain text, not monospaced | A localized sentence is a `String`; the names are matched by characters. §3.4 and §15 DQ-7 say so |
| §7 Tab order | Notice before API key | It sits under the address, so order follows layout; §7 corrected |
| §7 "library menus nothing changes" | File ▸ Add / Edit / Remove Server…, View ▸ Album ▸, Date Range… are present but dimmed in the library window | The existing Import items already behave so, and HIG Menus asks to dim, not remove. §7 corrected; M9 looks at the "Album" name |
| §4.3 range text | "Nov 1, 2026 to Nov 30, 2026" (the `%@ to %@` string) | §10 already named that string; wider than §4.3's sketch, which S6 covers |

## Design requirements

| Requirement | Result | Where, or why |
|---|---|---|
| D1 Server is a Source pop-up kind; Add Server… beside Choose Folder…; nothing in sidebar or Settings | Pass | `ImportWindow.swift:186-248` |
| D2 One sheet (two pages) and one removal alert, no Settings tab | Pass | `ServerSheet.swift`, `ImportWindow.swift:67-81` |
| D3 Check only on choosing, Add or Save | Pass | `connectServer`, `submit`; `.onAppear` only reads sources |
| D4 No default on the certificate page and the removal confirmation; nothing pre-checked; no "continue/allow" | Pass in code; needs manual check | Page 2 has only `cancelAction` on Cancel (`ServerSheet.swift:455-457`). The removal dialog is `confirmationDialog` with a destructive Remove and a `.cancel` Cancel, the library-ops pattern, but nothing scripted shows that Return does nothing: M3 |
| D5 Seven named results under their fields | Pass | `ServerText.result` matches §3.4 verbatim; placement by `concernsAddress` |
| D6 Album pop-up (All Photos, then albums with counts); Date Range popover | Pass | `AlbumMenu`, `DateRangePopover`; S6 for widths |
| D7 Nothing checked; Select All takes loaded unmarked | Pass | `reloadPhotos` clears selection; status's AC7 run |
| D8 Marked photos visible; Show Videos / Show Photos Already in Library not applicable | Pass | Selection pull-down omits them (`ImportWindow.swift:142-151`); View items dimmed (`ImportCommands.swift:74-85`) |
| D9 Edited badge top-trailing, tooltip, VoiceOver | Pass | `ImportCell.swift:216-222, 253-260, 276, 373-375`; same backing as In Library |
| D10 Paging within a screen; append without reload | Pass | `ImportGrid.swift:68-95`, `insertItems` with a zero-length animation group |
| D11 Server section first; After Import absent; plain project name | Pass | `ImportWindow.swift:386-388, 414-421, 475-477` |
| D12 No alert for Stop or a clean finish; one alert for failure; per-photo reasons in Activity | Pass | `RemoteImportReport.needsAlert`, `finishServerImport` |
| D13 Nothing in the standalone importer | Pass | `copiesOnly` gates; `ImportCommands(includesLibraryItems: false)` (`ImporterApplication.swift:27`); Importer-Info.plist has no ATS key (test) |
| D14 Owner rulings DQ-1 to DQ-4 | Pass | Import from Card or Folder… unchanged; Select All loaded; nothing checked; pop-up menu |
| DQ-5 Keychain refusal: one-OK alert, nothing removed | Pass | `ServerText.removalRefused`, `serverAlert`; Return and Esc: M4 |
| DQ-6 Album list failure: sentence, one warning | Pass | `ServerSource.swift:198-203` |
| §3.2 Name, address echo, key field, captions, errors under fields with an icon | Pass | S1 and S5 aside |
| §3.3 http notice with check box, Add dimmed until ticked, reset on address change | Pass | `UnencryptedNotice`, `addressEdited` |
| §3.5 Page 2: wording, fingerprint two lines monospaced and selectable, Trust not prominent | Pass | B1 aside; N2 |
| §3.7 Remove confirmation wording | Pass | `ImportWindow.swift:72-81` |
| §4.7 Grid states and actions | Pass | `ServerGridArea` |
| §5 Inspector rows and captions | Pass | `ServerSection`; layout at 256 pt: M7 |
| §6.2 Activity order and zero-line rule | Pass | `RemoteImportReport`; the size-only line changes per DQ-8 |
| §7 Menu bar items and no shortcuts | Pass | `ImportCommands.swift:34-103` |
| §7 Keyboard returns to the grid after the sheet | **Fail** | S4 |
| §8 VoiceOver wording | Pass with S5, N1, N5 | Cells, fingerprint, announcements read in code |
| §8 Appearance: palette, Light/Dark/Increase Contrast, no hard-coded colors beyond the existing badge backing | Pass in code; M1, M8 look | SwiftUI system styles in the sheet; `Palette` in the grid; the 55% black badge backing is the existing one |
| Layout at 256 pt inspector and 900 pt toolbar | Needs manual check | M6, M7 |
| §10 Strings: curly quotes, real ellipsis, sentence case in captions and alerts, title case in menu items and grid-state labels | Pass | Catalog entries match `ServerText`; plurals on the first number; DQ-8 and DQ-9 change two keys |
| §12 User guide terms | Pass | See below |

## Wording check against the String Catalog and the user guide

- Terms in `docs/USER_GUIDE.md` match the UI: **Add Server…**, **Edit Server…**,
  **Remove Server…**, **Album**, **Date Range**, **Server** (inspector section),
  **Edited**, **In Library**, **Trust Certificate**, **Review Certificate…**,
  **Back**, **Not encrypted**, **Checking the server…**, **Connecting to ‹name›…**,
  **Loading more photos…**, **Waiting for “‹name›”…**, **Rescan**, **Select All**.
- The permission list appears once (guide line 41) and is the five names, as the
  caption. DQ-8 and DQ-9 need no guide change: "Activity says how many were" and
  "one whose size the server doesn't give is not imported" still hold.
- No sentence contains the product name; "Immich" appears only where the person
  needs it.
- Alert wording follows HIG Alerts: titles say what happened, messages the
  consequence and the next step, controls named by their exact title without
  quotes ("Choose Edit Server…"), one **OK** where an alert only informs.

## Provisional copy: DQ-7 to DQ-9

Ruled in design.md §15, 2026-11-23, by me.

| | Built | Ruling | Engineer changes |
|---|---|---|---|
| DQ-7 | Caption and detail name five permissions | **Confirmed.** §3.2, §3.4, §10, §12 updated to five; the monospaced requirement for the missing names is dropped | None |
| DQ-8 | "‹n› were checked by size only (photos in an Immich external library)." | **Rewritten:** "‹n› imported photos were checked by size only, not against the server's checksum, because they are in an Immich external library." (one: "1 imported photo was checked by size only, not against the server's checksum, because it is in an Immich external library.") Reason: the built line borrows its subject from the line above (after the Live Photo line it reads as more videos) and gives no reason or consequence | `ServerText.swift:153-155` and the catalog key at `Localizable.xcstrings:1649` and its plural values |
| DQ-9 | "‹name›: the server gave no size to check the download against, so it was discarded." | **Rewritten:** "‹name›: the server did not say how large the file is, so the download could not be checked and was discarded." Reason: no dangling preposition, same shape as "the download was incomplete and was discarded." | `ServerText.swift:174-176` and the catalog key at `Localizable.xcstrings:356-362` |

Exactly two strings change. No test asserts either old sentence.

## Manual checks for a person

For the owner at the bundled app, on a scratch library (nothing here asks for
VoiceOver, macOS 15 or macOS 26). In order; the first four decide the findings.

- **M1. The sheet's size and look (S2).** Add Server… with the window at its
  smallest height, then a taller one. Check: the form is not collapsed or
  clipped, it scrolls between the title and the buttons when the window is
  short, and typing `http://192.168.1.5` (the notice appears) does not make the
  sheet jump or push **Add** off. In Light, Dark and Increase Contrast: row
  pitch, the captions' legibility, the warning icon and text under a field.
- **M2. The certificate page, with a real self-signed server (B1, S1; PRD P1).**
  Add: type a name, address and key; the certificate page opens. Press Back:
  **the API key field must show its dots again** and Add must agree with it. Press
  Return on the page: nothing happens. Esc: back to the form. Trust Certificate:
  the sheet checks again and closes. Then renew that server's certificate,
  choose the server, and use **Review Certificate…** in the grid state: the page
  names "Trusted before" and "Now"; **Trust Certificate must save** (the
  server opens afterwards with no further prompt). Read the page aloud: does
  anything nudge you to trust it?
- **M3. Remove Server… three ways (S3, D4).** From the sheet's button, the Source
  pop-up and File ▸ Remove Server…. The confirmation must appear each time
  (from the sheet, after it closes). Return does nothing; Esc cancels; Remove
  removes. Then make the Keychain refuse (Keychain Access: lock the login
  keychain, or deny) and check the "wasn't removed" alert.
- **M4. Alert keys (DQ-5).** On "The server … wasn't removed" and on each stop
  alert (revoke the key mid-import, pull the network cable, PRD P3, P4): Return
  and Esc both dismiss. If Esc does not dismiss a one-button alert, give OK
  `role: .cancel` and check that Return still dismisses.
- **M5. Keyboard, Full Keyboard Access on (S4; PRD P1).** Source pop-up to Add
  Server…, Tab through the sheet (Name, address, the check box when shown, API key,
  Cancel, Add), Space on the check box, Return with the notice unticked does
  nothing. After Add: without clicking, ⌘A, Space, arrows, End (a second page
  loads), Return imports.
- **M6. The toolbar at 900 pt (S6).** A server with a long album name and a date
  range set: overflow, truncation, Import and Stop still reachable; View ▸ Date
  Range… still opens its popover when the toolbar item is in the overflow menu.
- **M7. The narrowest inspector.** Drag it to its minimum with a long server name,
  "Encrypted, certificate trusted by you", a long project name: nothing clipped
  or overlapping; `print inspectorwidth` in the debug script reports `fits`.
- **M8. The grid (PRD P2).** An album of a few hundred photos: thumbnails
  arrive, no hitch, the scroll position holds when a page appends. An **Edited**
  photo that is also **In Library** at the smallest tile size in Light and Dark:
  both badges fit and read; the tooltips say what the design lists.
- **M9. Menus and the empty state.** File and View in the Import window and in
  the library window (the dimmed Server, **Album** and **Date Range…** items:
  does a dimmed **Album** submenu in the library's View menu read as the
  library's own albums? If yes, rename it **Server Album**). The empty state's
  **Open Server** menu button beside **Choose Folder…**: does it look like the
  other action buttons?
- **M10. Wording of the external-library lines.** Import from a server with an
  external library: read the Activity row against DQ-8 and, with a photo the
  server gives no size for, DQ-9.
- **M11. macOS's local network prompt (PRD P7)** on first connecting to a
  `192.168.x.x` server, and the unreachable result's System Settings sentence.

## Requirements issues

None. Two things the PRD wording may want, neither blocking: R19's size-only line
and R13's no-size failure now have copy (DQ-8, DQ-9), and R3's wording says five
permissions, which the design now matches.

## Confirmation of fixes

Open until the engineer reports on B1 and S1 to S6 and DQ-8 and DQ-9; I confirm
here, in a second pass on `ServerSheet.swift`, `ServerSource.swift`,
`ImportWindow.swift` and `ServerText.swift`.
