# Edit history: design review

Owner: apple-ui-designer. Date: 2026-11-09. Branch `feature/edit-history`, commit `4db535f`.
Against: [`design.md`](design.md), [`prd.md`](prd.md) acceptance criteria, [`status.md`](status.md), `docs/USER_GUIDE.md`.

Method: read `HistoryPanel.swift`, `HistoryActions.swift`, `HistoryText.swift`, `EditHistoryPanel.swift`, `InspectorView.swift`, the View menu in `LibraryCommands.swift`, the catalog entries and the User Guide text. I did not build or run the app (this review does not build), so everything below that depends on runtime behavior is either a code-reading finding (marked) or a manual check. I did not re-fetch the live HIG; the HIG points rest on the precedent documents design.md cites.

## Verdict

**Changes requested (two fixes, three smaller ones).** Structure, placement, states, copy, menu item, strings and the guide match the design well, and the engineer's two notes are acceptable (see "Responses"). Two defects need fixing before sign-off: a stale keyboard request that can pull the keyboard into the list while the person is working (F1), and a click that does nothing but leaves the keyboard trapped in the list (F2). The row tooltip (F3) is very likely not shown by a view-based table and needs a one-line change. None touches a render or the catalog.

## Findings for the engineer

Most severe first.

**F1 (fail, from code; keyboard).** `historyWantsKeyboard` is set to true by `toggleHistory()` unconditionally, but is cleared only in `onChange(of: state)` (HistoryPanel.swift:44) when the state changes to something other than entries or loading, and in `tookKeyboard` when a table consumes it. If the person presses ⌥⌘3 while the panel's state is already `.empty` or `.unavailable` (a photo with no edits, a video), the state does not change, so the flag stays true. The next time a `HistoryTable` is created for a photo with entries, `updateNSView` takes the keyboard: either right after the first edit on that photo (the list steals focus from the slider) or when the person arrows to the next photo that has history (the next arrow key then moves the list cursor instead of changing photos). That breaks design §9 ("culling keys and the loupe's arrows belong to the loupe") and the engineer's own rule "keyboard taken only when there are entries". Why it matters: Mac users expect focus to stay where they put it; a delayed focus grab is the worst kind of surprise because it is far from its cause. Fix: in `toggleHistory()` set the flag only when `historyPanelState` is `.entries` (or `.loading` with a loaded list for this photo), and also clear it when the focused photo changes and when the panel collapses. Add a unit test for the rule (the panel-state rule is already in PhotoCore, so the "wants keyboard" decision can live there). Separately for code review: `tookKeyboard()` mutates the model inside `updateNSView`, which SwiftUI flags as a state change during a view update; reading it from there is better done through the same task that makes the first responder change.

**F2 (fail, from code; keyboard).** Clicking a row makes the `KeyTableView` first responder (`acceptsFirstResponder` is true). `activate(entryID:)` returns early for the current row (row 0) and while the list is disabled (crop session), so `leaveList()` is not called. The click that "does nothing" (design §6, A5) therefore leaves the keyboard in the list with the row highlighted in the accent color, and the loupe's arrows, culling keys and `\` stop working until Esc. The design says the current-row click does nothing, which I meant as no change to the photo, not no change to focus. Fix: when a click lands on the current or a disabled row, still return the keyboard to the loupe (`leaveList()`), or do not take first responder for mouse clicks at all (clicking a row is a command, not a navigation). Return or Space on the current row from the keyboard may stay as is (the person is browsing the list and nothing moved).

**F3 (likely fail; tooltip).** The tooltip is implemented with `tableView(_:toolTipFor:rect:tableColumn:row:mouseLocation:)`. That delegate method is for cell-based tables; a view-based table (this one, via `viewFor`) does not call it, as far as I know from the AppKit documentation. If so, neither the full label plus seconds (design §5, D3) nor the crop-session hint tooltip appears. I could not run it; the manual check is M2. Fix: set `cell.toolTip` in `HistoryCell.configure` (same text), and drop the delegate method if M2 confirms it is dead.

**F4 (needs manual check, probable gap; motion).** The expand and collapse animation is `.animation(...)` on a SwiftUI `VStack` whose body is inserted and removed with `if model.showsHistory` around an `NSViewRepresentable`. Insertion with the default transition fades the view in; it does not grow the frame upward as design §6 and D7 specify, and the tab content above may jump to its new height at once. If M3 shows a fade or a jump, fix by keeping the body always in the hierarchy with `.frame(height: showsHistory ? bodyHeight : 0)` and `.clipped()` so the frame, not the insertion, animates (Reduce Motion path unchanged).

**F5 (gap against design §9; keyboard).** Design lists Home / End and Page Up / Down as moving the row cursor to the first / last row and by a page. `KeyTableView` forwards them to `super.keyDown`, and `NSTableView` scrolls on those keys but, as far as I know, does not move the selection. If M4 confirms the cursor stays put, handle Home / End (and Page Up / Down) in `keyDown` by selecting the target row and scrolling it into view. Low severity: with at most 100 rows, but it is how Mac lists behave and Full Keyboard Access users rely on it.

**F6 (User Guide, terms; minor).** The History paragraph says "it begins with the first change made after this feature was added". "This feature" is team language; a reader does not know what was added when. Write "after History was introduced" or, better, drop the date reference: "there is no entry for the photo as it was before its first recorded change". Everything else in the paragraph checks out against the UI: panel and heading name "History", **View ▸ Show History** and ⌥⌘3, the shortcut table row, "Reset All Adjustments" (a real item in the Photo menu and the ⋯ menu), the **Original** toggle, **Edit ▸ Undo** wording and "Revert to “…”", Esc, dimmed rows. One small improvement: the shortcut row shows "show / hide the History panel (**View ▸ Show History**)"; fine as is, since the menu title flips to Hide History.

## Improvements (judgment, not violations)

- **I1. Selection highlight and the pane corners.** `table.style = .plain` draws a square, edge-to-edge highlight. On macOS 26 the pane has rounded corners and controls are rounded (Harmony: concentric shapes), so a square cursor bar sits against rounded geometry. `.inset` gives the system's rounded, inset highlight on 26 (and a slight inset on 15). It changes the cell's 12 pt leading padding, so reduce the cell's own padding by the table's inset. Check on both designs (M6) before deciding; this is the one place the panel may look un-native.
- **I2. VoiceOver "selected".** Design §10 says the row is not selected for VoiceOver. The table's selection is the cursor, and `NSTableView` exposes `AXSelectedRows`, so VoiceOver will say "selected" on the cursor row. That cannot be avoided without replacing the table's selection model, and it is accurate enough (the cursor is there). I accept it; M5 listens for it. If it confuses, the row's value already says "current state" on the real current row.
- **I3. Row cell as one accessibility element.** `HistoryCell` is an accessibility element with a label and value, but its subviews (the two text fields and the image) are still children unless told otherwise, and VoiceOver can read the label twice. Add `setAccessibilityChildren([])` to guarantee one element per row. The engineer's `accessibility` dump showed the label and value; confirm no duplicate children in M5.
- **I4. Count flicker while browsing.** Moving between photos goes through `.loading` (design: no count while loading), so the count at the right of the header blinks off and on as the person presses the arrow keys. Design §6 specified it; if M1 shows it is distracting, keep the previous photo's count until the next list arrives (judgment, a one-line change to when `entryCount` becomes nil).
- **I5. Header has two Tab stops** (the triangle and the title button), the triangle being hidden from VoiceOver. Same as the inspector's other section headers, so consistent; noted only so a person who tabs through knows it is not new.

## Responses to the engineer's notes

1. **Date format ("Nov 2 at 4:10 PM" against "Nov 2, 4:10 PM" in §5).** Acceptable. §5 asked for the system formatter's output with the user's locale and 12/24-hour setting; the example string was illustrative, and imitating it with a literal pattern would defeat localization. The structure (short time today, relative "Yesterday, 4:10 PM", month and day this year, year otherwise) is what I specified, and `EditHistoryTime` implements exactly that. I will treat §5's examples as illustrations in future. No change needed. One thing to verify by hand: 24-hour setting shows "16:10" (M8).
2. **Palette-only toolbar item not built.** Accepted; §8 marked it optional, and the menu item plus the panel header meet R4 and discoverability. History is a companion to the Adjust tab, which is the one place the person is while editing, so a toolbar button adds little. If the owner wants it later it is a separate change; not a finding.

Other engineer decisions I read and accept: same-content comparison for "unchanged" (R10), revert to a state the photo already has does nothing (extends A5 sensibly), entry text stored as written (RI-3 is the product manager's), the video loupe deciding "video" from the focused item, unavailable text sentences exactly as designed.

## Design requirement table

| # | Requirement | Result | Note |
|---|---|---|---|
| D1 | Panel at the inspector's bottom, collapsed by default, loupe only, none in grid or review | Pass (code) | `HistoryPanel` below the tab content in `InspectorView`; `showsHistory` default false; `.absent` outside the loupe and in review. M1 to see it |
| D2 | Newest on top; check mark and semibold on row 1 | Pass | `isCurrent: row == 0`; semibold; `checkmark` shape, not color |
| D3 | Row: label, time rules, tooltip with seconds | Fail (likely) | Label and time correct; tooltip see F3 |
| D4 | Click reverts, current row does nothing, focus returns, Show Original off | Fail | Revert path and Show Original off correct (`showsOriginal = false`); focus after a no-op click F2 |
| D5 | Crop session dims rows | Pass (code), M7 | `isEnabled` false: alpha 0.5, no revert, hint and AX disabled. Whole table at 0.5 alpha is acceptable for a disabled control |
| D6 | States and their text | Pass | Strings match §6 exactly; empty is a text pair; loading draws nothing |
| D7 | 0.25 / 0.2 s, none with Reduce Motion | Needs manual check | Timing and Reduce Motion are coded; whether the frame grows upward is F4 (M3) |
| D8 | View ▸ Show / Hide History ⌥⌘3, dimmed in grid and review, shows inspector | Needs manual check | Item, key, title flip and `canShowHistory` read correctly, placed after Adjust; the engineer could not drive the menu (no key window): M9 |
| D9 | Keyboard: arrows move cursor only; Return / Space revert; Esc returns | Fail (partial) | Arrows, Return, Space, Esc, type-to-select off are right; stale grab F1, trap F2, Home / End F5 |
| D10 | VoiceOver: header, "Edit History", row label and value, announcement | Needs manual check | Header value and hint, table label, row label, value with ", current state", press action, custom action, "Reverted to %@" announcement are all in the code; reading order and duplicates M5 (I2, I3) |
| D11 | Strings in the catalog, no brand | Pass | All 19 keys present with comments; plural for entries; whole-string `Undo %@`, `Redo %@`, `Revert to “%@”` (not concatenated, as required) |
| D12 | No SwiftUI `ScrollView` or `List`; header is an `AppKitButton` | Pass | `NSTableView` in `NSScrollView`; `AppKitButton` and the existing `AppKitDisclosure`. The panel's empty and unavailable text are plain SwiftUI `Text`, which is fine (no scrolling) |
| D13 | Contrast, Increase Contrast, no glass | Needs manual check | Semantic colors only, no material (code). M6 |
| D14 | Terms in `USER_GUIDE.md` | Pass with F6 | Terms match the UI; one phrase to reword |

Acceptance criteria within my scope: AC3 (scroll) needs M4; AC4 passes by code; AC12 passes for the UI (no panel in grid or review; the three unavailable lines are as designed); AC14 needs M5 and depends on F2, F5 and I3. The data criteria (AC1, 2, 5 to 11, 13, 15, 16) are code-reviewer's and QA's; I saw nothing in the UI code that contradicts them.

## What is working

Placement and structure follow the owner's ruling; a bottom-docked panel with a 1 pt divider, 28 pt header, 24 pt rows, 96 to 192 pt body and 12 pt bottom inset. No custom surface, no glass. The label, the check-mark slot and the time are laid out as designed, the time never truncates (the label gives way). The menu title follows state, ⌥⌘3 does not collide, and the entry labels are one function with the undo names so they cannot drift. All copy is sentence-style or title-style per the design, with verbs where there are actions. Do not change any of that.

## Manual checks (people only), M1 to M9

Run the bundle with `--library-root` on a scratch library (WORKFLOW step 5). The panel sits in a glass pane, so `snapshot` will not show it.

- **M1.** In the loupe, the History panel is at the inspector's foot in both tabs, collapsed on first launch. Header: title, disclosure triangle, count at right (none while loading, none in empty and unavailable states). Arrow through several photos: does the count blink (I4)? Grid and review: no panel.
- **M2.** Hover a row for about a second: tooltip shows the label and the full date with seconds. Hover a dimmed row in a crop session: it adds the "Finish cropping" line (F3).
- **M3.** Expand and collapse by clicking the title, the triangle and ⌥⌘3. The body should grow upward over about a quarter second while the tab content above shortens, with no fade-in or jump (F4). With System Settings ▸ Accessibility ▸ Display ▸ Reduce motion on, it happens at once, and new rows and the scroll to the top are immediate. Click during the animation: it should retarget.
- **M4.** With more than eight entries: the list scrolls with the overlay scroller; the last row clears the pane's rounded bottom corner on macOS 26. In the list, Up and Down move the cursor without changing the photo; Home, End, Page Up and Page Down move the cursor (F5).
- **M5.** VoiceOver: Tab to the header (reads "History, button, collapsed or expanded", the "12 entries" hint); to the list ("Edit History"); rows read the label once, then "Today at ..." and ", current state" on the top row; check for duplicate reading (I3) and whether "selected" is spoken on the cursor row (I2); VO-Space on an earlier row reverts and says "Reverted to ..."; the current row offers no action. Full Keyboard Access reaches the header and every row.
- **M6.** Light, Dark (the library window is dark) and Increase Contrast: label and time stay readable, including the time on the highlighted row, key window and not. Look at the selection bar's shape against the rounded pane (I1), on macOS 26 and with a build linked against the older SDK if available.
- **M7.** Start a crop: rows dim and do nothing; the tooltip explains. Cancel the crop: rows work. Click the current row and a dimmed row, then press an arrow key: the photo should change (F2). Press ⌥⌘3 on a photo with no edits, make one edit, then arrow to another photo with history: the keyboard must stay in the loupe (F1).
- **M8.** Time text: today short; an entry from yesterday reads "Yesterday, ..."; an older one reads month and day, with the year if not this year. Switch the Mac to 24-hour time: rows follow. The row's exact time in the tooltip includes seconds.
- **M9.** View menu: "Show History" and "Hide History" follow the panel; ⌥⌘3 works from the grid? (it must be dimmed there and in review, and in the loupe with a sheet open); with the inspector hidden (⌥⌘I) it brings the inspector back, expands the panel and puts the cursor on the top row; Hide History returns the keyboard to the loupe. Edit ▸ Undo after a revert reads "Undo Revert to “...”"; ⇧⌘Z redoes; ⌘Y does nothing.

## Design questions and requirements issues

None new. design.md needs no change except the note in "Responses" item 1 (§5's time examples are illustrations); I will fold that into design.md if the owner wants it written down. The engineer's RI-3 (stored label language) and RI-4 (AC15 measure) belong to the product manager; from a design view RI-3 is acceptable while the app is English only.

## Follow-up

The engineer fixes F1 to F6 and updates `status.md`; I will confirm each fix here after the second pass. F4 and F5 can be downgraded to "no change" if M3 and M4 show the system behavior already matches the design.

## Second pass (2026-11-10, commit `e54ceeb`)

Method: read `HistoryPanel.swift`, `HistoryActions.swift`, the revert path in `AdjustmentEditor.swift`, the catalog entries for the two new strings, the History paragraph and shortcut row in `USER_GUIDE.md`, and the `status.md` table. I did not build, run or diff the commit (no shell in this review), so "confirmed" means confirmed by reading the code as it stands in the working tree; nothing runtime is claimed.

### Verdict

**Approved for sign-off, with two small copy fixes (F7, F8) that do not block the manual checks.** All six findings are fixed in code. What is left is runtime behavior that only a person can see (M2, M3, M4, M7, plus M5, M6, M9).

### Finding by finding

| # | Result | Evidence |
|---|---|---|
| F1 stale keyboard request | Confirmed fixed (code) | `toggleHistory` sets the request from `historyPanelState.canTakeKeyboard`, so empty, unavailable, loading and absent states never set it; collapse clears it; `onChange(of: focusedItem?.versionID)` and `onChange(of: state)` clear it; `tookKeyboard()` runs inside a `Task`, not in the view update. The grab happens only when `!isCollapsed`. Runtime sequence still M7 |
| F2 click leaves the keyboard in the list | Confirmed fixed (code) | `clicked()` calls `leaveList()` whenever `activate(row:)` returns false (current row, dimmed rows, disabled list). Return or Space on the current row from the keyboard stays in the list, as I allowed. Note, not a finding: a click on empty space below the last row (`clickedRow < 0`) returns early and keeps the keyboard; harmless, since there is no row to highlight |
| F3 tooltip | Confirmed fixed (code), M2 | `HistoryCell.configure` sets `toolTip` (label, exact time, crop hint when dimmed); the delegate method is gone. Whether the tooltip shows on a row of a view-based table is runtime: M2 |
| F4 expand and collapse | Fixed in code, M3 | Body is always in the hierarchy with `.frame(height: showsHistory ? bodyHeight : 0)`, `.clipped()`, hit testing and VoiceOver off when collapsed, `.animation` nil under Reduce Motion, 0.25 s ease-out in, 0.2 s ease-in out. That is the structure I asked for; the visual result (growth upward, tab content above following without a jump, an `NSViewRepresentable` resizing smoothly) cannot be read from code |
| F5 Home, End, Page keys | Confirmed fixed (code), M4 | Key codes 115, 119, 116, 121 move the cursor with clamping and `scrollRowToVisible`; page size is visible rows minus one. M4 confirms the feel and that arrows still move only the cursor |
| F6 guide wording | Confirmed fixed | "it begins with the first recorded change: there is no entry for the photo as it was before that change", then Reset All Adjustments, Undo, Original. No team language left. The new sentences (size limit, copied version starts empty) read plainly. One nit, no action needed: that paragraph has an over-long line from the edit; reflow it when next touched |
| I3 one element per row | Confirmed (code), M5 | `setAccessibilityChildren([])` with `setAccessibilityElement(true)` and role `.cell`. Duplicate reading is checked in M5 |
| I4 count flicker | Confirmed (code), M1 | While `.loading`, the header shows the previous list's count (`history.entries.count`, nil if that list was empty). One side effect: the VoiceOver hint ("12 entries") is also the previous photo's for that moment; negligible, no change asked |
| I1 selection shape | Stays a manual check, M6 | See below |

### I1 decision: keep as M6, not a finding

`table.style = .plain` gives a square, full-width cursor bar. That is a judgment call about Harmony, not a rule violation, and the engineer cannot see the result either. Keep it in M6 as an observation: look at the selection bar against the pane's rounded corners on macOS 26. Only if it looks wrong to the owner does it become a follow-up (`.inset` plus reducing the cell's 12 pt padding by the inset). It is not a condition of sign-off. Note the cursor bar is transient: it shows only while the list holds the keyboard, and a click or Esc clears it, so the exposure is small.

### The two new strings

1. **"“%@” can't be restored: its saved state can't be read."** (Activity warning, `AdjustmentEditor.revert`). Works as a sentence but has two problems.
   - **F7 (term, minor).** Every other surface says revert (View menu, "Revert to “…”", "Reverted to …", "Revert to This State", the guide). "Restored" introduces a second verb for the same action. Also "can't" twice in one sentence reads like a stutter, and it does not say what happened to the photo.
   - Fix: title (the `action:` argument is the Activity row title, not a button, so the bare "Revert" title is thin) = the existing `Revert to “%@”` string via `HistoryText.revert(toLabel:)`; message = "Its saved state can't be read. The photo is unchanged." This reuses a catalog string, puts the verb in the title, names the outcome, and avoids interpolating the label into a sentence (labels can be long, and the title truncates more gracefully than a sentence). If the owner prefers a single line: "Can't revert to “%@”. Its saved state can't be read." Either way update the translator comment; the VoiceOver announcement is the message text, so keep it to the shorter form.
   - Straight apostrophe matches the other strings in this feature ("can't"), so no change there.
2. **"History is unavailable. It could not be read from the library."** (`.failed` state). Terms are right ("History", "library" both match the UI and guide) and it is sentence-case with a period like its siblings.
   - **F8 (consistency, minor).** The siblings say "This version can't read…"; this one says "could not". Use "It can't be read from the library." so the three "History is unavailable." lines share a voice. Optional: it gives no next step, which is acceptable for a rare error; do not add "try again" unless reopening the photo actually retries (it does, since the task reloads on photo change and on history revision, but that is not worth promising in copy).
   - Also confirm the row is not shown in the guide's list of unavailable cases: the guide names video, offline and unreadable stack only. Add "or the list could not be read" for completeness (guide terms check; the engineer owns the file).

### What is confirmed from code and what needs a person

- **Confirmed from code:** F1, F2, F3 (structure), F5, F6, I3, I4, the two strings' terms and catalog entries, the guide's terms and the shortcut row.
- **Still needs a person (the owner, at the bundle):**
  - **M2** tooltip on a live row and on a dimmed row.
  - **M3** expand and collapse motion, retargeting, Reduce Motion.
  - **M4** more than eight rows scroll; Up and Down, Home, End, Page keys move only the cursor; last row clear of the rounded corner.
  - **M7** crop session dims and ignores rows; click the current row and a dimmed row then press an arrow key (the photo must change); press ⌥⌘3 on a photo with no edits, make an edit, arrow to another photo with history (the keyboard must stay in the loupe).
  - Unchanged from the first pass and still open: M1, M5, M6 (including I1), M8, M9.

### Open items

F7 and F8 (copy) to the engineer, with the guide addition. Neither changes behavior or needs a new manual check beyond reading the Activity row once during M7 (force it by damaging a snapshot only if convenient; otherwise accept it on the unit test). No design questions or requirements issues. I will mark F7 and F8 confirmed when the strings change; if the owner prefers to ship the current copy, I accept that, since neither is a defect.
