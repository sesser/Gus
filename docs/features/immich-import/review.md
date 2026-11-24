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

Confirmed in the second pass below (2026-11-23, HEAD efb8425). The manual checks
above are superseded by the list at the end of that section.

## Second pass

Owner: apple-ui-designer. Date: 2026-11-23. Branch `feature/immich-import` at
efb8425, after 977427c, 1deda12 and efb8425.

**How this was checked.** From source, as before, with no shell: I could not run
`git diff 2552143..HEAD`, so I read the current files in full instead
(`ServerSheet.swift`, `ServerSource.swift`, `ServerText.swift`,
`ImportWindow.swift`, `ImportGrid.swift`, `RemoteBrowseRules.swift`,
`DebugServerCommands.swift`, `Localizable.xcstrings`, `RemoteReviewFixTests`,
`docs/USER_GUIDE.md` lines 30 to 121) against the first pass's findings. I did not
run the app. "Fixed" below means the code does what the fix said; the looks, keys
and timing are the manual checks at the end.

### Verdict

**The seven findings of the first pass are fixed in code, and the strings match
design.md word for word. Two things remain before sign-off: the certificate page
cannot scroll inside the new fixed sheet height (should fix, N-1), and an alert
sentence of mine sends the person to a dead end (DQ-11, now ruled; one catalog
string).** Neither blocks the owner's checks, but N-1 should be fixed before them,
since M1 is meant to look at exactly that case.

### Confirmation table

| Finding | Result | What I checked in code | Left for a person |
|---|---|---|---|
| **B1** Trust Certificate does nothing in Edit | **Fixed** | `ServerFormRules.canSubmit` returns `changed \|\| trustedPending` for an Edit (`RemoteBrowseRules.swift:101-110`); `needsCheck` is `!isEdit \|\| addressChanged \|\| keyEntered \|\| trustedPending` (`:116-118`). The model passes `trustedPending` to both (`ServerSheet.swift:104-108, 126-127`), so after `trustCertificate()` sets `trusted`, `submit()` passes its guard, skips the name-only branch, reads the stored key from the Keychain off the main thread, checks with the new pin (`:137`) and saves `certificateFingerprint` and `certificateTrustedAt` (`:176-177`). **A plain Add cannot skip the check:** for Add `canSubmit` still requires `keyEntered` and `needsCheck` is true because `!isEdit`; `trustedPending` is only ever set by `trustCertificate()`, which exists only on the certificate page, which only a check or Review Certificate… opens. `trustedPendingIsAChange` (`RemoteReviewFixTests.swift:180`) pins the Edit rule. It does not assert Add; I read that rule by hand and it holds | M2: a real changed certificate (the fake has no TLS) |
| **S1** key field empties | **Fixed** | The key is `public private(set) var key` on the `@Observable` `ServerSheetModel` (`:33`); the field is `SecureField` bound with `Binding(get: { sheet.key }, set: { sheet.setKey($0) })` (`:321-322`), so a page change redraws it with its dots and Add agrees with it (`keyEntered` is set in the same `setKey`). It is never shown: `SecureField`, no `Text(sheet.key)`, no `Mirror`, no log; the debug `sheet print` writes "key entered", never the text (`DebugServerCommands.swift:262`); the field's accessibility hint is the check result, never the value (`:326`). Memory only. **Cleared by release, not by wiping:** Cancel on the form and a successful save both set `model.serverSheet = nil`, which frees the sheet model and its string; Remove from the sheet does the same (`:241-245`); Back and Cancel on the certificate page keep it on purpose (the form as it was). A cancelled check's task holds the model until it ends, which is the request's cancellation. A Swift `String` can't be reliably zeroed, so I do not ask for it; clearing `key` in `cancel()` and after a save would be harmless hygiene (nit, N-3) | M2: dots after Back; VoiceOver is not asked of the owner |
| **S2** height rule | **Fixed for the form; partly fixed for the certificate page** | The numbers: form 380, notice +90, result +60, certificate 470, changed 540, clamped to `window - 40`, never under 300 (`RemoteBrowseRules.swift:126-141`). `.presentationSizing(.fitted)` is gone from `ServerSheet` (the other three sheets keep it: `ExportSheet.swift:30`, `MergeSheet.swift:32`, `CopyAdjustmentsSheet.swift:46`; the Server sheet is the one whose height changes after it opens, so the difference is right). The frame is `.frame(width: 460).frame(height: sheet.idealHeight)` (`:279-282`); `idealHeight` reads `page`, `result` and `address` (observed), so it follows the notice, a result and the page. The status file's scripted sizes (460 x 380, 470, 530) are the real sheet window's frame (`sheet print` reads `attachedSheet.frame`). **Clamped to small windows:** the import window's minimum is 480 pt (`ImportWindow.swift:18`), so the sheet is at most 440 pt there. **Larger text and Increase Contrast:** macOS has no Dynamic Type; Increase Contrast changes colors and borders, not metrics. The form is a `Form` (scroll-backed) between a fixed title and a fixed button bar, so if its content is taller than the budget it scrolls and **Add never leaves the sheet**: that case is safe. **The certificate page is not scroll-backed** (`CertificatePage`: a plain `VStack` with `fixedSize` texts and fingerprints), so at 440 pt it can overflow its fixed frame: my estimate of the changed page's content is 460 to 500 pt (header, a four-line paragraph, three rows, two two-line fingerprints, a three-line footer, button bar), against 440 in the smallest window. An overflow clips both ends of a centered stack, that is the title and Back at the top and Cancel and Trust Certificate at the bottom. I can't measure this from source: it is **N-1** and M1 | M1: the sheet in the smallest window, both pages |
| **S3** confirmation while the sheet closes | **Fixed** | `remove()` stores the server in `removalAfterSheet` and sets `serverSheet = nil` (`ServerSheet.swift:241-245`); the window asks from `.sheet(item:onDismiss:)` (`ImportWindow.swift:67`) through `serverSheetDidDismiss()` (`ServerSource.swift:466-470`), so `confirmationDialog` is requested after the sheet has gone. The other dismissals (Cancel, save) leave `removalAfterSheet` nil, so `onDismiss` does nothing for them. The dialog is as before: destructive Remove, `.cancel` Cancel, no default (`ImportWindow.swift:72-81`) | M3: Return does nothing on the dialog; it appears each time |
| **S4** focus after Add | **Fixed** | `serverSaved` sets `focusesGridWhenShown` after `chooseServer` (`ServerSource.swift:456-463`); `chooseServer` tears the old grid down (`closeServer` sets `browse = nil`) and the new `ImportGridView` is created only when `gridState` becomes `.photos`, so `viewDidMoveToWindow` calls `windowDidChange` with the window, which clears the flag and makes the collection view first responder on the next run-loop turn (`ImportGrid.swift:228-235, 302-304`). Cancel and Esc never touch the first responder. The status file's scripted `import grid` "first responder true" matches. One nit, N-4 | M5 with a real keyboard |
| **S5** `.combine` hides the button | **Fixed** | `.accessibilityElement(children: .contain)` on the result block (`ServerSheet.swift:399-400`), with the comment; **Review Certificate…** is a child control. The title, detail and button are separate children, which reads title, detail, button in order | Not asked of the owner (VoiceOver policy) |
| **S6** unbounded titles | **Fixed in code** | Album and Date Range titles: `lineLimit(1)`, `truncationMode(.middle)`, `frame(maxWidth: ServerToolbarMetrics.titleWidth)`, 180 pt (`ImportWindow.swift:752-760, 779-787, 884-887`). Whether a `Text` inside a toolbar `Menu` label honors the line limit and width as written is toolbar rendering I can't read from source | M6 |
| **N1** result as field hint | **Fixed** | Address and key fields carry `accessibilityHint(resultHint(...))`, which is the result's title and detail, empty when the result belongs to the other field (`ServerSheet.swift:311, 326, 404-410`); no key text | none |
| **N3** subtitle slice | **Fixed** | `ServerText.notEncrypted` ("Not encrypted") for the empty case and `notEncryptedSuffix` (" · Not encrypted") for the rest, each its own catalog entry (`ServerText.swift:113-119`, `ImportWindow.swift:104-106`); no character slicing. Two entries rather than one built from the other: acceptable, and a translator can move the separator | none |
| **N4** "Imported 0 photos" | **Fixed** | `alert(...)` uses "No photos were imported. ‹n› could not be imported." when `done == 0` (`ServerText.swift:229-233`); both plural variants of the catalog entry read the same, which is right (the number is only the failure count and "1 could not be imported" is grammatical) | none |
| **N5** "From" and "To" twice | **Partly fixed, accepted** | The pickers are named "From date" and "To date" (`ImportWindow.swift:846, 854`), so the check boxes keep "From" and "To" and nothing is said twice. The reversed-range line is still not announced; the engineer left it and I accept it: it sits beside the picker that caused it and Apply is dimmed | none |
| **N6** long name | **Fixed** | Name row `lineLimit(2)` with `.help` (`ImportWindow.swift:626-630`) | M7 |

### DQ-8 and DQ-9: strings as worded

Both match design.md §10 exactly, in `ServerText.swift` and the catalog.
DQ-8 (`ServerText.swift:159`, `Localizable.xcstrings:445-467`): the `one` form is
"%lld imported photo was checked by size only, not against the server's checksum,
because it is in an Immich external library." and `other` the plural form, both
word for word, with the old key gone (a grep for the old sentence finds nothing).
DQ-9 (`ServerText.swift:183`, `Localizable.xcstrings:367-373`): "%@: the server did
not say how large the file is, so the download could not be checked and was
discarded." Correct, no stale key.

### DQ-10: the new failure sentence (ruled)

**Confirmed as built; no catalog change.** "‹name›: its name on the server would
have placed it outside the destination folder, so it was not imported." Recorded
as design.md §15 **DQ-10** (2026-11-23), with the table row in §6.2 and the string
in §10. Why: it has the shape of its neighbors, uses the inspector's own words
("destination folder", from Destination ▸ **Folder**), places the fault with the
server's file name rather than the person's template, and offers no action
because there is none (a name that could do this is not listed in the first place;
this is the backstop). The catalog entry is the one at `Localizable.xcstrings:312`.

### New finding ruled: DQ-11 (the certificate-changed alert)

`ServerText.swift:226` says "Choose Edit Server…, then Review Certificate…, to see
the new one." That was my wording (design §6.3), and it is wrong: Edit Server…
opens the form with no check result and Save dimmed (`showEditServer()` with
`reviewingCertificate: false`, `ServerSource.swift:420-427`, nothing seeds
`result`), and Review Certificate… appears in the sheet only under a "certificate
has changed" result. The way in is the grid's **Review Certificate…** button, which
the window shows after any stop (§6.3's bullet). Ruled in §15 as **DQ-11**; the
engineer changes exactly one catalog string (below). **Engineer, DQ-11:** replace
the key `%lld photos were imported before the import stopped. Nothing more was
downloaded. Choose Edit Server…, then Review Certificate…, to see the new one.`
(`ServerText.swift:226`, `Localizable.xcstrings:1120-1135`) with `%lld photos were
imported before the import stopped. Nothing more was downloaded. Choose Review
Certificate… in the window to see the new one.`, keeping both plural forms.

### User guide: the new sentences

Lines 53 to 60 (plain http judges the name you typed), 40 to 44 (five permissions)
and 99 to 102 (size-only checking), read against the UI and the strings.

- **Terms** match the UI: **Send my key and photos without encryption**, **Not
  encrypted**, **Will connect to**, **Trust Certificate**, **Review Certificate…**,
  **Back**, **Edit Server…**; the five permission names are the caption's, in the
  caption's order. No product name appears.
- **Tone:** direct and in the second person, like its neighbors. "The app judges
  the name you typed, not where it leads: a name without dots counts as local even
  if your network's settings send it elsewhere, so use `http://` only for a server
  you know is on your own network" says the limit and the consequence once, without
  alarm. The user.read parenthesis and the size-only sentence ("since Immich's
  checksum for it can be of its path rather than its content") explain the reason,
  as the design asks.
- **Consistent with DQ-8 and DQ-9:** "Activity says how many were" and "one whose
  size the server doesn't give is not imported" still hold. No guide sentence for
  DQ-10 is needed.
- **One formatting nit:** line 60 runs on past the file's wrap (the sentence that
  starts "Such a server stays marked **Not encrypted**" was joined onto the line
  before it). Re-wrap it.
- **The Review Certificate… route is not described** in the guide (it says
  connecting fails and **Review Certificate…** shows the fingerprints), which is
  why DQ-11 needs no guide change.

### New findings

**Blocking: none.**

**Should fix**

- **N-1. The certificate page has no scroll rule inside its fixed height.**
  `ServerSheet.swift:437-496` (`CertificatePage`), with `:279-282` and
  `RemoteBrowseRules.swift:126-141`. The sheet height is now fixed at 470 pt (540
  for a changed certificate) and clamped to the window less 40 pt; the smallest
  import window (480 pt) gives 440 pt, the form page scrolls inside it but this
  page is a plain `VStack` with `fixedSize` content, so anything over the height
  is cut at both ends, which includes the Cancel and **Trust Certificate** buttons
  and the Back button. On a page whose job is to let a person read a fingerprint
  before deciding, losing the buttons is the worst failure available. Fix: keep the
  header and the button bar outside, and put the body (paragraph, rows,
  fingerprints, footer) in a `ScrollView` between the two dividers, as the form's
  `Form` does; the sheet's frame stays. Principle: Layout, "adapt to window size";
  the form page already does it. M1 checks the smallest window.
- **N-2. The certificate-changed alert names a route that ends at a dimmed
  button.** `ServerText.swift:226` and the catalog entry, ruled as DQ-11 (a string
  change, above).

**Nits**

- **N-3.** `trusted` is not cleared when the address changes
  (`ServerSheet.swift:71-75`). In Add: type address A, reach the certificate page,
  Trust, the check then fails on the key; fix the address to B and Add: the pin
  from A is applied to B, and a different certificate reads "The server's
  certificate has changed" for a server never saved. Safe (nothing is trusted that
  wasn't looked at) but a wrong message. Clear `trusted` in `addressEdited()`; also
  clearing `key` when the sheet closes is harmless hygiene (S1).
- **N-4.** `focusesGridWhenShown` stays set when the server's first check fails
  (`ServerSource.swift:462`, `CardImportModel.swift:101`): the next grid to enter the
  window, whatever its source, takes the keyboard once. Harmless; clear the flag in
  `closeServer()` or when the state lands on a failure.
- **N-5.** `ServerSheetModel.key`'s comment says "the key itself is not observed"
  (`ServerSheet.swift:34`, on `keyEntered`) while `key` is an `@Observable` stored
  property that the field reads. The behavior is right (the field must redraw); the
  comment on `keyEntered` is about the Bool, so nothing misleads, but the one on
  `key` ("Memory only") could add "observed, so the field redraws".

### What's working

The B1 rule is in PhotoCore with a test, and the Add path is untouched by it. The
key lives in one model and one field and nowhere else. The removal confirmation now
waits for the sheet's dismissal through the system's own callback rather than a
timer. The strings follow design.md and carry plurals on the first number.

### Manual checks for a person (final list, in order)

For the owner at the bundled app, on a scratch library, with a real self-signed
server for M2 and M11. Nothing here asks for VoiceOver, macOS 15 or macOS 26. The
first three decide the open findings.

- **M1. The sheet's size and look (S2, N-1).** Add Server… with the import window
  at its smallest height (480 pt), then taller. Both pages: after typing
  `http://192.168.1.5` (the notice appears) and pressing Add with a wrong key
  (a result appears), the sheet grows without jumping and **Add** stays on screen;
  the form scrolls between the title and the buttons when the window is short. On
  the certificate page, in the smallest window, **the title, Back, Cancel and Trust
  Certificate are all visible**, for the first-time page and the changed one (M2
  gets you there). In Light, Dark and Increase Contrast: row pitch, captions'
  legibility, the warning icon and text under a field.
- **M2. The certificate page, with a real self-signed server (B1, S1, DQ-11; PRD
  P1).** Add: name, address, key; the certificate page opens. Back: **the API key
  field shows its dots again** and Add is enabled. Return on the page does nothing;
  Esc returns to the form. Trust Certificate: the sheet checks again and closes.
  Then renew that server's certificate and choose the server: the grid says the
  certificate changed; **Review Certificate…** opens the Edit sheet on the page
  naming "Trusted before" and "Now"; **Trust Certificate must save with nothing
  else edited** (the server opens afterwards with no further prompt, and a second
  trust of the same certificate does not ask again). Make the certificate change
  mid-import: the alert's last sentence names **Review Certificate…**, and that
  button is in the window once it has checked the server. Read the page aloud: does
  anything nudge you to trust it?
- **M3. Remove Server… three ways (S3, D4).** From the sheet's button, the Source
  pop-up and File ▸ Remove Server…. The confirmation appears each time (from the
  sheet, after it has closed). Return does nothing; Esc cancels; Remove removes.
  Then make the Keychain refuse (lock the login keychain, or deny) and check the
  "wasn't removed" alert.
- **M4. Alert keys (DQ-5).** On "The server … wasn't removed" and on each stop
  alert (revoke the key mid-import, pull the network, PRD P3, P4): Return and Esc
  both dismiss. `serverAlert`'s **OK** has no `.cancel` role
  (`ImportWindow.swift:63`); if Esc does not dismiss, give it `role: .cancel` and
  check that Return still does.
- **M5. Keyboard, Full Keyboard Access on (S4; PRD P1).** Source pop-up to Add
  Server…, Tab through the sheet (Name, address, the check box when shown, API key,
  Cancel, Add), Space on the check box, Return with the notice unticked does
  nothing. After Add: without clicking, ⌘A, Space, arrows, End (a second page
  loads), Return imports. Also after **Save** on an edited server.
- **M6. The toolbar at 900 pt (S6).** A server with a long album name and a date
  range set: the titles truncate in the middle at about 180 pt, Import and Stop stay
  reachable; View ▸ Date Range… still opens its popover when the item is in the
  overflow menu.
- **M7. The narrowest inspector (N6).** Drag it to its minimum with a long server
  name (two lines then cut, tooltip on hover), "Encrypted, certificate trusted by
  you" and a long project name: nothing clipped or overlapping; `print
  inspectorwidth` in the debug script reports `fits`.
- **M8. The grid (PRD P2).** An album of a few hundred photos: thumbnails arrive, no
  hitch, the scroll position holds when a page appends. An **Edited** photo that is
  also **In Library** at the smallest tile size in Light and Dark: both badges fit
  and read; the tooltips say what the design lists.
- **M9. Menus and the empty state.** File and View in the Import window and in the
  library window (the dimmed Server, **Album** and **Date Range…** items): does a
  dimmed **Album** submenu in the library's View menu read as the library's own
  albums? If yes, rename it **Server Album**. The empty state's **Open Server**
  menu button beside **Choose Folder…**: does it look like the other action buttons?
- **M10. Wording of the Activity lines.** Import from a server with an external
  library and read the row against DQ-8; with a photo the server gives no size for,
  DQ-9. DQ-10's sentence can't be produced from the app (a name that triggers it
  is not listed), so it is covered by `RemoteSecurityTests` and the string's
  catalog entry, not by a person.
- **M11. macOS's local network prompt (PRD P7)** on first connecting to a
  `192.168.x.x` server, and the unreachable result's System Settings sentence.

M1 and M2 grew (the certificate page in the smallest window; the trust-only save;
the mid-import alert route), M5 gained Save, M6 and M7 name what S6 and N6 changed,
and M10 gained DQ-10's note. No check was added that needs VoiceOver.

### Held for the owner, not decided here

The Tailscale address range, the fake server linked into the app (C10), and the
Info.plist permission text are the owner's; nothing in this pass changes them.

### Requirements issues

None.

## Third pass

Owner: apple-ui-designer. Date: 2026-11-23. Branch `feature/immich-import` at
22103c2 (the fixes of the second pass). Checked from source with no shell and no
run of the app: `ServerSheet.swift` in full, `RemoteBrowseRules.swift` 90 to 175,
`ServerSource.swift` (the sheet, focus and finish paths), `ServerText.swift`
200 to 240, `ImportWindow.swift` 670 to 700, `Localizable.xcstrings` (the DQ-11
entry), `docs/USER_GUIDE.md` 36 to 90, the tests named in `status.md`'s "Review
findings (second round)" and design.md §10 and §15.

### Verdict

**Ready for the owner's sign-off checks. All six items I raised in the second
pass are fixed as asked; nothing blocking and nothing that should be fixed
first.** Two nits are new (N-6, N-7), neither needs a change to pass.

### Confirmations

| Item | Result | From the source |
|---|---|---|
| **N-1** certificate page clipped its buttons | **Fixed** | `CertificatePage` (`ServerSheet.swift:443-509`) is a `VStack` of a fixed header (title and **Back**), a `ScrollView` holding the paragraph, the three rows, the fingerprints and the footer, then a `Divider` and the fixed button bar. Only the body scrolls, so Back, Cancel and **Trust Certificate** cannot be pushed out by content at any height. A `ScrollView` is not the CLAUDE.md hazard here: that rule is about the inspector's scroll view under the window's toolbar, and this one is inside a sheet window with no toolbar (the buttons, which a click must reach, are outside it anyway). The body keeps `fixedSize(horizontal: false, vertical: true)` inside the scroll view, so text wraps to the 460 pt width and the scroll view measures it correctly |
| Trust Certificate reachable, not the default | **Pass** | The button has no `keyboardShortcut` and no `.borderedProminent`, so it is not the default and Return does nothing on the page. **Cancel** has `role: .cancel` and `.cancelAction`, and calls `back()`; **Back** has ⌘[. Trust is a plain push button in the bar. D4 holds. The user guide says the same ("neither button is the default, so Return does nothing; Esc or **Back** returns to the form") |
| Back and Cancel at the smallest window | **Pass in the arithmetic, look is M1** | The import window's minimum is 480 pt (`ImportWindow.swift:18`); `ServerSheetHeight.ideal` gives `max(300, min(470 or 540, 480 - 40))` = 440 pt there. Of that, the header and the bar with its divider take roughly 100 pt (my estimate), leaving about 340 pt for the scrolling body. The three controls are in the fixed parts, so they are on screen whatever the body needs |
| Layout when the height is clamped | **Pass** | Form page: title fixed, `Form` scrolls, button bar fixed (`ServerSheet.swift:299-364`), so **Add**, **Save**, Remove Server… and Cancel stay visible; the notice (+90) and a result (+60) raise the ideal but are cut at `window - 40`, and the form scrolls instead. Certificate page: as above. The 300 pt floor never applies in a real window (440 at the smallest) and only guards a window whose height is not known yet (`windowHeight` nil gives the content height). The frame is set on the sheet's root, so no page can be taller than it is told |
| **N-3** `trusted` cleared on address change | **Fixed, with a test** | `addressEdited()` sets `trusted = nil`, clears the unencrypted confirmation and the result (`:73-79`), and the property observer on `address` runs only when the value differs from the old one. `ServerFormRules.pin` gives a trusted certificate only for the address it was trusted for, else the saved pin while the saved address is unchanged, else none (`RemoteBrowseRules.swift:129-136`); `pinFollowsAddress` pins all four cases. The B1 rule is unaffected: `trustedPending` is `trusted != nil`, and Trust sets it after the address is already typed |
| User-facing consequence of that | **Acceptable; wording nit N-7** | What the person sees after changing the address of a trusted server: the form shows no result; Save checks again and, because the old pin is dropped for a new address, the certificate page appears as a first-time page ("Trust this certificate?", not "Trust the new certificate?", one fingerprint). That is the right outcome: a pin is for one address, and nothing is trusted that was not looked at. The page footer's promise ("accept only this exact certificate for “‹name›”") names the connection, not the address, which is slightly looser than the rule (N-7) |
| **N-4** focus flag | **Fixed** | Cleared in the failed branch of the first check (`ServerSource.swift:144`), so a later grid cannot take the keyboard unasked. `serverSaved` sets it after `chooseServer` and `ImportGrid.windowDidChange` consumes it once (`:231-233`) |
| **N-5** comment on `key` | **Fixed** | The comment says the key is held and observed so the field redraws (`ServerSheet.swift:31-34`) |
| **DQ-11** alert string | **Fixed, word for word** | `ServerText.swift:226` and the catalog entry at `Localizable.xcstrings:1120-1135` read "‹n› photos were imported before the import stopped. Nothing more was downloaded. Choose Review Certificate… in the window to see the new one." with the `one` form "1 photo was imported…" and the `other` form; the old "Edit Server…, then Review Certificate…" key is gone (a search of Sources and the guide finds none). It matches design.md §10 (lines 743, 940, 1375-1387). **The route it names exists:** `finishServerImport` always calls `connectServer` after the alert is queued, so the grid re-reads the server, lands on the Can't Connect state with `browse.failure == .certificateChanged`, and that state shows **Review Certificate…** (`ImportWindow.swift:686-687`), which opens the Edit sheet on the changed-certificate page (`showEditServer(reviewingCertificate: true)`). The button appears a moment after the alert, once that check ends |
| User guide wrap | **Fixed** | Lines 53 to 67 wrap at the file's width; "Such a server stays marked **Not encrypted**…" starts its own line. Terms unchanged and still match the UI. The guide describes the route to review a certificate only as "**Review Certificate…** shows the old and new fingerprints" (line 69), which stays true |

### New findings

**Blocking: none. Should fix: none.**

**Nits (no change needed to pass)**

- **N-6. Nothing says the certificate page scrolls.** In the smallest window the
  body is about 340 pt against a content height of roughly 360 pt for a first-time
  page and 420 pt or more for a changed one (estimates). On macOS overlay
  scrollers show only while scrolling (or if the person set "Always"), so the
  footer, and on a changed certificate possibly the **Now** fingerprint, can sit
  below the fold with no sign. The buttons stay reachable, so a person can press
  **Trust Certificate** without having seen the second fingerprint. That is
  the very behaviour the page exists to prevent. Judgment, not HIG text: the
  smallest window is an edge case and a person who resizes the window sees all of
  it. If M1 shows it is easy to miss, add `.scrollIndicators(.visible)` to that
  `ScrollView` (I have not verified that this forces the indicator under an
  overlay scroller setting) or raise the import window's minimum height. No change
  asked now.
- **N-7. The footer promises trust "for ‹name›"; the pin is for the address.**
  `ServerSheet.swift:490`. After the fix a person who edits a trusted server's
  address meets the page again, as the rule intends, but the sentence let them
  expect the trust to follow the name. Suggested wording if the engineer touches
  it: "…this Mac will accept only this exact certificate for “‹name›” at this
  address." Optional; the user guide's "for this server" has the same slack.

### What's working

The fixed header and bar with a scrolling middle is the same shape as the form
page, so both pages behave alike at every size. The trust rules live in
PhotoCore with tests, and every fix of the second pass has either a test or a
named manual check. The DQ-11 route now exists from the first window the person
sees after the alert.

### Manual checks for a person: the final list

For the owner at the bundled app, on a scratch library (`Scripts/build-app.sh`,
then the bundle with `--library-root`). None asks for VoiceOver, macOS 15 or
macOS 26. M2 and the second half of M1 need a real self-signed `https://` Immich
server (the fake server has no TLS). **Required before sign-off, because they
decide a finding: M1 to M6. Optional, to look at when convenient: M7 to M11.**

Required:

1. **M1. Sheet size and the certificate page (S2, N-1, N-6).** Add Server… with
   the import window at its smallest height (480 pt) and taller. Look at: the form
   scrolls between title and buttons and **Add** never leaves; typing
   `http://192.168.1.5` or getting a result grows the sheet without a jump; on the
   certificate page, first-time and changed, **title, Back, Cancel and Trust
   Certificate are all visible**, and whether it is obvious that the body scrolls
   (N-6). Light, Dark, Increase Contrast.
2. **M2. Trusting a certificate, end to end (B1, S1, N-3, DQ-11).** Add with a
   self-signed server: certificate page; **Back** brings the API key's dots back
   and Add is enabled; Return does nothing, Esc goes back; Trust Certificate
   checks and closes. Renew the certificate and choose the server:
   **Review Certificate…** opens the "Trusted before / Now" page and **Trust
   Certificate saves with nothing else edited**, with no prompt afterwards. Change
   a trusted server's address in Edit and Save: a first-time page appears, not the
   changed one. Make the certificate change mid-import: the alert's last sentence
   names **Review Certificate…** and the button is in the window a moment later.
   Does anything on the page nudge you to trust?
3. **M3. Remove Server… three ways (S3, D4).** From the sheet, the Source pop-up
   and File ▸ Remove Server…: the confirmation appears each time (from the sheet,
   after it closes); Return does nothing, Esc cancels, Remove removes. Then
   make the Keychain refuse and read the "wasn't removed" alert.
4. **M4. Alert keys (DQ-5).** On the "wasn't removed" alert and each stop alert
   (revoke the key mid-import, drop the network): do Return and Esc both dismiss?
   If Esc does not, the engineer adds `role: .cancel` to OK.
5. **M5. Keyboard (S4).** Full Keyboard Access on: Source pop-up to Add Server…, Tab
   through the sheet in order, Space on the notice's check box, Return with it
   unticked does nothing. After **Add** and after **Save**, with no click: ⌘A,
   Space, arrows, End (next page), Return.
6. **M6. Toolbar at 900 pt (S6).** A long album name and a date range set: titles
   cut in the middle near 180 pt, Import and Stop still reachable, View ▸ Date
   Range… still opens its popover from the overflow menu.

Optional:

7. **M7. Narrowest inspector (N6).** Long server and project names, "Encrypted,
   certificate trusted by you": nothing clipped; `print inspectorwidth` says `fits`.
8. **M8. The grid (PRD P2).** A few hundred photos: thumbnails arrive, no hitch,
   scroll position holds as a page appends; an **Edited** and **In Library** photo
   at the smallest tile size, both badges legible in Light and Dark.
9. **M9. Menus and empty state.** The dimmed Server, **Album** and **Date Range…**
   items in the library window's menus (does a dimmed **Album** read as the
   library's own albums? If so, **Server Album**); **Open Server** beside
   **Choose Folder…** looks like the other action buttons.
10. **M10. Wording of the Activity lines.** Read the external-library line (DQ-8)
    and, with a photo the server gives no size for, DQ-9.
11. **M11. The local network prompt (PRD P7)** on first connecting to a
    `192.168.x.x` server, and the unreachable result's System Settings sentence.

### Held for the owner, not decided here

The Tailscale address range, the fake server linked into the app (C10) and the
Info.plist permission text. Unchanged by this pass.

### Requirements issues

None.

## Fourth pass

Owner: apple-ui-designer. Date: 2026-11-24. Branch `feature/immich-import` at
54760d1. Scope: DQ-13 and DQ-14 only (f334d9d, 54760d1). Checked from source
with no shell and no run of the app (the inspector is a glass pane, so there is
no screenshot either): `ImportWindow.swift` 379 to 531, `ServerSource.swift`
211 to 262, `ServerText.swift` 93 to 100, `RemoteBrowseRules.swift` 169 to 197,
`Localizable.xcstrings` (the new entry), `RemoteProjectReuseTests.reuseNote`,
`docs/USER_GUIDE.md` 93 to 129, design.md §5.3 and §15 DQ-12 to DQ-14, and
`status.md` "DQ-13 and DQ-14 built". I did not re-run the engineer's scripted
checks; they are read as reported.

### Verdict

**Ready for the owner's sign-off checks. DQ-13 and DQ-14 are built as ruled; no
blocking finding and nothing that should be fixed first.** Two nits (N-8, N-9),
neither needs a change to pass. DQ-12's rule is described the same way in
design.md, `status.md` and the user guide.

### Confirmations

| Requirement | Result | From the source |
|---|---|---|
| DQ-13 string, exact | **Pass** | `ServerText.addsToExistingProject` and the catalog key are "Adds to the existing project with this name." (period, sentence case); one `en` entry, state `translated`, comment word for word as ruled (`Localizable.xcstrings:2369-2379`); sorted between "Address" and "Adjust" as the catalog is. The key is the English text and the call is `String(localized:comment:)`, like its neighbours |
| Caption style, one line vs wrapping | **Pass** | The file's own `Caption` (11 pt, `.secondary`, `fixedSize(horizontal: false, vertical: true)`), the one under Preset and Server, so it wraps and never truncates. No icon, colour, button or confirmation |
| Placement | **Pass** | Inside the field's `VStack(alignment: .leading, spacing: 6)`, directly under the field, 6 pt below it (`ImportWindow.swift:419-433`) |
| Shown when | **Pass** | `CardImportModel.addsToExistingProject` is false without a server source or a library (standalone importer, card, folder), false when `existingProjectID != nil` (the field is absent then anyway), false while `library.projects` is empty; otherwise `RemoteProjectName.cleaned(typed, address:) == any project name`. That is the very call and the very address (`address.normalized`) `RemoteImporter.makeTarget` and `Catalog.projectForImport` use (`RemoteImporter.swift:408`, `ServerSource.swift:393`), so the note and the import cannot disagree, an empty field included |
| Computed, not stored; follows typing, prefill, Add to, project list | **Pass** | A computed property read in the view body, so it follows `browse.projectName` and `library.projects`; nothing is cached. `reuseNote` covers match, match after cleaning, case, NFD against NFC, empty field as the address, no match, no projects, Add to set |
| Announcement: once, only when it appears because the name changed | **Pass** | `setServerProjectName` and `chooseAlbum`'s prefill take the state before, change the name, and call `announceProjectNote(wasShown:)`, which speaks only for `!wasShown && shown`, medium priority. Never on window open, source change, Add to change or a change of the project list (none of those call it), never when the note goes. Typing past a match and back (delete a letter, retype it) announces again: the note did appear again because of the name, as DQ-13 says |
| VoiceOver: hint plus a single announcement, visible label hidden | **Pass** | The field has `.accessibilityHint` of the sentence while the note shows and an empty text otherwise; the `Caption` is `.accessibilityHidden(true)`, so the sentence is not read twice; the visible `Text("Project name")` is `.accessibilityHidden(true)` and the field keeps its title "Project name" through `labelsHidden()` (which hides the label visually and keeps it for assistive technology). `Text(String)` for the hint is verbatim, not looked up again. Not tested with VoiceOver (owner's standing ruling) |
| DQ-14 layout | **Pass** | `VStack(alignment: .leading, spacing: 6)`: plain `Text("Project name")`, `TextField` with `.textFieldStyle(.roundedBorder)`, `.labelsHidden()`, `.multilineTextAlignment(.leading)`, `.frame(maxWidth: .infinity)`: the shape `TemplateField` has (`TemplateField.swift:45-70`), system field, no custom control. No new string; Job code, the two pop-ups and the card's template Project name are untouched, as ruled |
| No fixed widths at 300 pt | **Pass** | None in the stack: the field takes the column (`maxWidth: .infinity`), the caption has no horizontal size constraint of its own. The inspector is `inspectorColumnWidth(min: 300, ideal: 320, max: 400)` (`ImportWindow.swift:21`). Nothing in the new rows can widen the column or be cut at its trailing edge (the `print inspectorwidth` verdict is not available in this window and was not asked to be added) |
| Increase Contrast, Light, Dark | **Pass in code, look is M12** | Only system pieces: rounded-border field (the system strengthens its border), primary label, `.secondary` caption. No hard-coded colour or border |
| User guide terms | **Pass, with N-9** | **Project name**'s sentence and the quoted caption match the string character for character; **Import N Photos**, **Edit Server…** and **New Project** match the UI |
| DQ-12 consistent in the three places | **Pass** | design.md §5.3 (lines 644-648), DQ-12 (1396-1408), `status.md` O1 and the guide (lines 95-103) all say: exact name after the field's cleaning, case counts, spaces collapsed, the **oldest** when several, a reused project keeps its folder, card and folder imports unchanged. design.md has no other sentence that says one project per run or a new project for a server (`grep` of "project" in the file: lines 57, 421, 608, 951 and 1070 are all still true; line 1070 is RI-3's history). The guide adds the empty-field fallback nowhere; DQ-12 has it (see N-9) |

### New findings

**Blocking: none. Should fix: none.**

**Nits (no change needed to pass)**

- **N-8. My "two lines at the narrowest" in DQ-13 is an estimate and is probably
  wrong.** The sentence is 44 characters; at 11 pt SF Pro that is roughly 230 to
  245 pt, and the grouped form's column at the 300 pt minimum is roughly 250 to
  260 pt (my estimate: the form's insets are not in the code). It may fit on one
  line at every width, or wrap only at 300 pt. Either is right; the rule is that
  it wraps and never truncates, and the code does that. No change to code or
  design.md; M12 asks the owner to report which, so the number can be corrected
  if anyone cares. (design.md is read-only for this pass; I will correct the
  sentence at the next edit of §15.)
- **N-9. The user guide never says the reuse rule belongs to Add to = New
  Project, and never names the pop-up.** It says a card or folder import "set to
  **New Project**" makes a new project, which reads as if **Add to** had been
  introduced; it is not in the guide for any source. Someone who picks an
  existing project in **Add to** has no field and no note and no sentence about
  it. Optional wording for the server paragraph, if the engineer touches it:
  "With **Add to** set to **New Project**, a project that already has that
  name..." and "Choosing a project in **Add to** puts the photos in it, and the
  field is hidden." The empty-field fallback (the name becomes the server's
  address) is also unsaid; it is a corner and can stay out.
- **Two things to know, not findings.** (1) The Project section now mixes three
  row shapes: the **Add to** pop-up (label left, value right), the stacked
  **Project name**, and **Job code** (label left, field right). DQ-14 ruled this
  deliberately and named the follow-up (a stacked Job code, the owner's to file);
  M12 asks the owner to look at whether it reads as untidy. (2) `status.md`'s
  "For a person, M1" is the DQ-14 look and collides with this file's M1 (the
  certificate page); the engineer's file can keep its name, but the owner should
  use this file's numbers: the combined check is **M12**.

### What's working

The note is a pure function of the same inputs the importer uses, so it is
accurate by construction and cheap; the announcement rule is one `wasShown`
comparison in the two places the name changes; the caption doubles as the hint
without being read twice; and the stacked field is the `TemplateField` shape with
the system field, so it needed no custom layout.

### Manual checks for a person

For the owner at the bundled app, on a scratch library (`Scripts/build-app.sh`,
then the bundle with `--library-root`, a fake server with at least one photo
imported so a project named "Home - All Photos" exists). No VoiceOver, macOS 15
or macOS 26. **Optional but recommended before sign-off: the look is the only
thing this pass could not see.**

12. **M12. The server Project name field and its note (DQ-13, DQ-14).** Open the
    fake server in the Import window with **Add to** set to **New Project**.
    - **Short name.** The field is "Home - All Photos": label **Project name**
      above, the field across the column, the text starting at its left edge
      (not flush right), and the line **Adds to the existing project with this
      name.** under it in small grey type. Type "Trip": the line disappears and
      the form below moves up by its height, with nothing else jumping. Type
      "Home - All Photos" again: it returns.
    - **Long name.** Paste a 60-character name that does not match: the field
      shows its start while at rest, scrolls to the caret while typing, and
      nothing is cut at the trailing edge of the inspector. Paste a long name that
      matches (rename a project to it first): the note shows.
    - **Narrowest width.** Drag the inspector to its minimum (300 pt) and to its
      maximum (400): the label, field and note stay on one left edge; the note is
      one or two lines (say which at 300 pt, N-8) and never cut with "…"; the
      field is not wider than the section's other rows.
    - **Add to a project.** Choose an existing project in **Add to**: the field
      and the note both go; back to **New Project**: both return.
    - **Appearance.** Light, Dark and System Settings ▸ Accessibility ▸ Display ▸
      Increase Contrast: the field's border is the stronger one, the label is
      black or white text and the note stays legible (not fainter than the
      captions under **Server** and **Preset**).
    - **Neighbours.** Does the Project section read tidily with a pop-up row, a
      stacked field and the Job code row together? A "no" is a follow-up to
      stack Job code, not a fault of this branch.

### Held for the owner, not decided here

Nothing new. The follow-up for a stacked Job code (DQ-14) remains the owner's to
file.

### Requirements issues

None.
