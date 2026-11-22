# Copy Adjustments: choose what to copy: design review

Reviewer: apple-ui-designer. Date: 2026-11-22. Issue #243.
Reviewed: branch `feature/copy-adjustments-selective` at 890588c, against
[design.md](design.md) (with the rulings of §15 added in this review), the PRD
(issue #243, R1 to R14, AC1 to AC12) and `docs/USER_GUIDE.md`.

How: read the code and the String Catalog; nothing was built or run here (no
shell). Where a row says Pass it is from the source and from the engineer's
scripted checks in `status.md`, which I did not repeat. "Needs manual check"
means the source cannot show it.

## Verdict

**Pass, with three small findings (F1 to F3) and the two design rulings
applied.** The sheet is built the way the design describes: system parts only
(a SwiftUI sheet, system check boxes through `AppKitCheckbox`, standard
buttons), one data-driven row list shared by the sheet, the clipboard and the
tests, one command with the same behavior at every entry point, and the
defaults, mixed state, trailing text, footer and button bar as specified. No
violation of the HIG or of an accessibility requirement was found in what can
be read. F1 (a wording change) and F2 (the Paste tooltip) come from the
rulings; F3 is a VoiceOver verbosity nit. Nothing blocks QA.

## Design requirements

| # | Requirement (design section) | Result | Note |
|---|---|---|---|
| 1 | One command, **Copy Adjustments…**, opens the sheet for the focused photo, at every entry point (§2) | Pass | Adjust menu (first item, ⇧⌘C, `canCopyAdjustments`), grid/loupe/video-loupe context menu, the tab's ⋯ menu, palette-only toolbar item without the ellipsis. Paste Adjustments stays under it, ⇧⌘V |
| 2 | Toolbar tooltip "Choose which adjustments to copy" (§2) | Pass | `.help(CopyAdjustmentsText.toolbarHelp)` |
| 3 | Video never opens the sheet; unreadable edits post the existing warning and open nothing; second ⇧⌘C while the read is pending does nothing (§2) | Pass | `canCopyAdjustments` excludes videos; `copySource` posts `unreadableMessage`; `copySheetRead` guards. Scripted per status |
| 4 | Editor's *saved* values in the loupe, the catalog's after pending saves elsewhere; frozen at open (§3, §2) | Pass | `editorCopySource` uses `savedAdjustments`; `CopySheetState.source` is a `let` |
| 5 | Sheet is a `LibraryModal` of kind sheet; one sheet at a time; `onDismiss: modalDidClose` (§7) | Pass | `.copyAdjustments`, `showsCopySheet`, `MainView` presenter; `LibraryModalTests` updated; `presentCopySheet` re-checks `otherModalIsUp` after the read |
| 6 | Header: 44 pt thumbnail with placeholder, hidden from VoiceOver; title as header; "From ‹name›" via `PhotoName.display`; Check All / Uncheck All bottom-aligned (§3.1) | Pass | `CopySheetHeader`; `.lastTextBaseline` alignment |
| 7 | No-changes note under the subtitle with `info.circle` (§3.1) | Pass | `sourceHasNoChanges`; the ideal height grows 20 pt for it |
| 8 | Rows: Crop & Straighten, then the tab's order and names; a one-group heading is one row; Presets and Masks absent; never collapsed (§3.2) | Pass | `CopyRow.all`; names through `AdjustText` (Light: White Balance, Tone, Presence). `rowsFollowTheTab` pins it |
| 9 | Typography and spacing: headings and single rows 13 semibold, children 13 regular and indented, 20 pt pitch, 4 pt block gap, tail truncation with tooltip, trailing text never truncates (§3.2) | Pass | `CopySheetMetrics`, `CopySheetRow`. The indent is 22 pt (box 16 + 6) as designed. Look itself: M1 |
| 10 | Whole row is the hit target, box included (§3.2, §3.4) | Pass | `contentShape` + `onTapGesture`; engineer posted real mouse events on box and label (one toggle each). A real mouse: M4 |
| 11 | Default state: Crop, Spots and Lens groups never; other groups when `isModified`, off-with-values counts (§3.3, §4) | Pass | `CopyItem.isUncheckedByDefault`, `defaults(for:)`; tests |
| 12 | Heading box derived, never stored; click rule: checked unchecks all, unchecked or mixed checks all (§3.3, §3.4) | Pass | `state(of:)`, `click(_:)`; `AppKitCheckbox.updateNSView` re-applies the model's state after AppKit's own on/mixed/off cycle |
| 13 | Trailing text rules and strings: No changes, Resets on paste, Turned off, "‹n› spots", "‹n› spots, turned off"; box never dimmed (§3.3) | Pass | `note(for:)`; plural forms in the catalog |
| 14 | Footer: masks note verbatim, fixed under the list (§3.5) | Pass | Same key as the Masks heading's |
| 15 | Button bar: Cancel (Esc), Copy (Return, default), Copy disabled with "Check something to copy." at the leading edge and as hint (§3.6) | Pass | Text hidden from VoiceOver, hint on the button |
| 16 | Copy replaces the clipboard, closes, posts no Activity row, announces "Copied ‹list›." at medium priority, more than five entries read "‹n› items" (§3.6) | Pass | `confirmCopySheet`, `announcement` |
| 17 | Cancel changes neither clipboard nor photos (§3.6, AC1) | Pass | `cancelCopySheet` only closes |
| 18 | Paste applies exactly the copied items, values and on/off; defaults reset; the rest, masks, decode and unknown operations untouched (§3.7) | Pass | `CopiedAdjustments.pasted`; tests for AC5, AC6, masks/decode/unknown |
| 19 | Size: 420 wide, ideal = measured content (660, 680 with the note, within the 680 cap), min 380, clamped to a short window, only the list scrolls; no grouped `Form` (§3.8) | Pass | `CopySheetMetrics.idealHeight`; engineer measured 520 + 140 and the 760 x 480 case. By eye: M3 |
| 20 | Spots paste only on the same frame size; one warning with a count after the change landed; none when all matched or Spots not copied; assumption for a source with no spots (§5.1) | Pass, with F1 | See DQ-1: the unreadable-size case needed a second string, ruled below |
| 21 | Lens frame alert unchanged; asked before the spots sentence; none for a paste without a Lens group (§5.2) | Pass | `confirmingLensFrameChange` wraps the transform. The sheet is closed before it, so they never meet |
| 22 | Spots hint rewritten, old key removed, Masks hint unchanged (§6) | Pass | `SpotsSection`; no `leave spots out` of the old wording anywhere in `Sources/` or the catalog |
| 23 | Keyboard: Return/Esc, every box a system check box and a Tab stop with Full Keyboard Access, Space toggles, no initial focus set by code, keyboard returns to the grid or loupe after the sheet (§8) | Pass; Tab order by hand | System `NSButton` check boxes; engineer saw first responder return to `PhotoCollectionView` / `LoupeHostView`. Real Tab walk: M2. Check All / Uncheck All come before the list: accepted, DQ-3 |
| 24 | VoiceOver: list container "Adjustments to copy", heading containers, row label includes the trailing text read once, captions as hints, Copy hint (§8) | Pass, with F3 | Not testable here; CI only per project rule |
| 25 | Color and contrast: system check box, `.secondary` text, no custom color or glass; no motion (§8) | Pass | Increase Contrast look: M1 |
| 26 | Strings: all of §10 present with comments, the removed key gone, extended comments on reused keys (§10) | Pass, with F1 | 18 added keys; DQ-1 changes one key, DQ-2 adds one |
| 27 | Debug script: `copyadjust` (defaults, no sheet), `all`, `<name>…`, `sheet [...]`, `print copysheet`, `print clipboard` (§11) | Pass | Per status and source; extras (`click`, `mouse`) are additions, harmless |
| 28 | User guide terms (§12) | Pass, with F4 | See below |
| 29 | R14 Paste tooltip (PRD, design §14 "not designed") | Not built | Specified in §15 DQ-2: F2 |

## Acceptance criteria (design view)

| AC | Result | Note |
|---|---|---|
| AC1 | Pass | Dialog, Cancel, Copy then Paste; tests and scripted |
| AC2 | Pass | Order and names as the revised PRD; mixed heading |
| AC3 | Pass | Scripted on a photo with Exposure, Contrast, crop |
| AC4 | Pass | Copy off, with the reason shown |
| AC5, AC6, AC7 | Pass | Tests compare stored stacks and History |
| AC8 | Pass | Rides on the unchanged lens paths; engineer used no real table files. Lens work was checked by the owner in #87 |
| AC9 | Pass, with F1 | Same size, other size, turned-off Spots, no-spots source; the unreadable case gets its sentence from DQ-1 |
| AC10 | Pass | Crop pastes as stored, untouched when unchecked |
| AC11 | Pass | Copy dimmed for a video, Paste dimmed until a copy exists and while comparing. The ⋯ menu's Paste is enabled by the clipboard alone, as before this branch; the Adjust tab is not shown while comparing, so it can't be reached |
| AC12 | Pass for what the keyboard can reach by script; Tab walk is M2 | |

## User guide terms

Checked `docs/USER_GUIDE.md` against the UI: **Copy Adjustments…** (with the
ellipsis everywhere the command is a menu item), **Paste Adjustments**, **Crop &
Straighten**, **Spots**, **Lens**, **No changes**, **Resets on paste**, **Turned
off**, **Check All**, **Uncheck All**, **Copy**, **Cancel**, the heading and group
names, ⇧⌘C and ⇧⌘V all match the labels in code and the catalog. The old
statements (spots left out of Copy and Paste; the crop always pasted; masks
"into Copy and Paste") read correctly now at 416, 460, 520, 643, 690 and 764,
and the new paragraph at 858 describes the sheet and Paste. Two gaps, both small (F4): the "could not be read" case
once DQ-1 is built, and the note a photo with no adjustments shows.

## Findings for the engineer

1. **F1 (DQ-1 applied).** Change the second spots warning's text to `Spots were
   not pasted onto %lld photos: their size, or the size of the photo they were
   copied from, could not be read.` (1 form: `…onto %lld photo: its size, or the
   size of the photo they were copied from, could not be read.`), rename the
   catalog key and the comment, keep the order (size differs first, then
   unreadable) and the at-most-two-rows rule. Update the test that pins the
   wording, if any. See design §15 DQ-1.
2. **F2 (DQ-2 applied).** Build the toolbar Paste item's tooltip as specified in
   design §15 DQ-2: `.help` on the `pasteAdjustments` item, text `Paste
   Adjustments: ‹list›` from the same list function as the announcement
   (refactor it out of `CopyAdjustmentsText.announcement`: five names or fewer joined
   with ", ", else `%lld items`), plain `Paste Adjustments` with nothing copied,
   no period. It must update when the clipboard changes (read the summary from
   the state that already enables the item). Add the catalog key with a comment.
3. **F3 (nit, VoiceOver). The check boxes' help repeats their name.**
   `CopySheetRow` passes `help: caption ?? title`, and `AppKitCheckbox` uses
   `help` for both the tooltip and `setAccessibilityHelp`, so for every row
   without a caption VoiceOver reads "Tone, checkbox, checked, Tone". Design
   §8 wants the hint only on Crop and Spots (their captions). Give
   `AppKitCheckbox` an optional separate accessibility help (defaulting to
   `help`, so the inspector's uses do not change) and pass the caption or nil.
   Keep the tooltip as the full name for truncation (§3.2).
4. **F4 (docs). User guide.** After F1, add to the Spots passage (line 465) that
   a photo whose size can't be read (an offline original, or the one the spots
   came from) also keeps its spots and Activity says so. Optionally add one
   sentence that a photo with no adjustments says so under the sheet's title and
   that Copy announces what was copied for VoiceOver.

## Manual checks (for QA to script, or for a person)

None needs VoiceOver or macOS 15 and 26 (CI only). The design's M1 to M6 stand
(`design.md` §13); `status.md` already lists them for a person. Added or
sharpened:

- **M1** The sheet's look beside Export's with Increase Contrast on: pitch, the
  indent, the trailing text's contrast, the header, the footer, no clipped label;
  the Spots and Crop captions line up with the label, not the box.
- **M2** Full Keyboard Access: Tab through every box (and Check All, Uncheck All
  first, per DQ-3), Space toggles, Return copies, Esc cancels, Return does
  nothing with nothing checked, a box focused out of view scrolls in.
- **M3** 760 x 480 window: the list scrolls, header, footer and buttons stay;
  at the default window nothing scrolls.
- **M4** A real mouse on a mixed Light heading, on a row's label and on the
  trailing text: one toggle each, the text changes with the box.
- **M5** The real flow with keys: ⇧⌘C, Space, Return, ⇧⌘V on a series, ⌘Z once.
- **M6** A preset pack import that ends while the sheet is up: the report waits.
- **M7** (QA can script) DQ-1's unreadable case: copy Spots from a photo, make
  the source's master unreadable (rename its file in the scratch library), then
  paste onto photos of the same size: expect only the "could not be read"
  warning, counting every target. Then a paste where some targets differ in size
  and one target's master is missing: two rows, the differing count first.
- **M8** After F2, the toolbar Paste item's tooltip (the item is palette-only;
  `customize toolbar` to add it): hover shows `Paste Adjustments: Tone, Color
  Grading` after such a copy and updates after another Copy. QA can read the
  item's help through the debug script's `buttons`/`print` if it prints help.

## Requirements issues

None. Design questions are answered in design.md §15. One consequence the
product manager may want to know: R14's tooltip is built after all, so the
"order of removal" list in R14 gains nothing and loses nothing.

## What's working, and should not change by accident

- One `CopyRow.all` list drives the sheet, the debug script, the clipboard and
  the tests; #92's Masks row is one more case and the footer then goes.
- The click rule for a mixed heading matches the Adjust tab's own heading boxes.
- Defaults are worked out from the frozen source every time and nothing is
  remembered.
- The sheet freezes the editor's *saved* values, so a slider mid-drag or a hover
  preview never leaks into a copy.
- Spots are compared by header-read frame size with no remapping, and an
  unreadable size is a distinct outcome, not folded into "differs" without a
  sentence of its own.

## Second pass (2026-11-22)

Reviewed: branch `feature/copy-adjustments-selective` at a883a3b (fixes in
05b0e8b, b034487, a883a3b), against the first pass above, `design.md` §15 and
`status.md`'s **Review findings**. Source read only (no shell); the engineer's
scripted results are taken from `status.md`, not repeated.

### Verdict

**Pass. F1 to F4 are confirmed fixed; no new findings that block QA.** One
documentation nit (N1) the engineer may take or leave.

### Fixes

| # | Result | Evidence |
|---|---|---|
| F1 | Confirmed | `CopyAdjustmentsText.spotsUnknownSize` and the catalog key read `Spots were not pasted onto %lld photos: their size, or the size of the photo they were copied from, could not be read.`, with the singular `…photo: its size, or the size…` exactly as ruled. The old key is gone from the catalog. `reportSpotsLeftOut` posts "differs" first, then "unreadable", each only when its count is above 0, so two rows at most. The comment explains the two causes. |
| F2 | Confirmed | `.help(CopyAdjustmentsText.pasteHelp(state.copiedSummary))` is on the `pasteAdjustments` toolbar item only. `list(_:)` is the one list function for `announcement` and `pasteHelp` (five names or fewer joined with ", ", else `%lld items`, with a catalog comment naming both uses). `pasteHelp(nil)` is plain "Paste Adjustments", no period. `LibraryMenuState.copiedSummary` is what enables the item and is set from `model.copiedAdjustments?.summary`, so the tooltip follows the clipboard. Key `Paste Adjustments: %@` is in the catalog with a comment. Hover on the real item stays M8. |
| F3 | Confirmed | `AppKitCheckbox.accessibilityHelp: String??` defaults to `.none`, so `setAccessibilityHelp(accessibilityHelp ?? help)` leaves every inspector box as before; the sheet passes `.some(caption)`, which gives VoiceOver the caption on Crop & Straighten and Spots only and nothing elsewhere, while the tooltip stays `caption ?? title` (the full name for a truncated label). `print copysheet` prints the pair, so QA can read it. `String??` is slightly clumsy but is documented in the property's comment and does the job; not worth a change. |
| F4 | Confirmed | `USER_GUIDE.md` 466 to 474 (unreadable size, its own Activity line after the size one, many-photo versus one-photo measuring, the ⌘Z limit, Stop), 881 to 884 (announcement, tooltip, the no-adjustments note) and 762 to 764 (the frame question counts only what a photo already has). |
| C1 (code review, design effect) | Confirmed, no UI change | The lens alert's wording and buttons are untouched; only which photos count changed. The guide says so at 762. The "1 of the 5 photos has masks or spots" check in `status.md` is the user-visible result. |

### User guide terms

Checked the new text against the UI: **Copy Adjustments…**, **Paste Adjustments**,
**Spots**, **Lens**, **Crop & Straighten**, **Stop**, **Activity**, **Copy**,
**Cancel**, **Check All**, **Uncheck All** and the toolbar item's tooltip name
match the labels in code and the catalog. "Turned off", "No changes" and
"Resets on paste" are unchanged and correct. The guide says "⋯ menu" and
"toolbar item" for entry points that match the code.

- **N1 (nit, wording, not blocking).** Line 763 says spots a paste brings "come
  with the Distortion of the photo they were copied from". That is only so when
  the Lens group was also copied; otherwise the spots arrive on a photo whose own
  Distortion stays, and a later Distortion change then asks. Suggest: "spots that
  Copy Adjustments… brings are not asked about; they are placed in the frame they
  had on the photo they were copied from, and a later Distortion change asks as
  usual." The code and rule are right; only the sentence overstates.

### Remaining findings

None blocking. N1 is optional.

### Final manual checks (for QA, then a person)

None needs VoiceOver or macOS 15 and 26 (CI only, per project rule). M1 to M8
are as listed above; the status after this pass:

- **M1** Look beside Export's with Increase Contrast (a person).
- **M2** Full Keyboard Access Tab walk, Space, Return, Esc (a person; QA can only
  script the order).
- **M3** 760 x 480 window: the list scrolls, header, footer and buttons stay (QA
  can script by window size; a person by eye).
- **M4** A real mouse on a mixed heading, a label and the trailing text (a person).
- **M5** ⇧⌘C, Space, Return, ⇧⌘V on a series, ⌘Z once (a person; QA scripts the
  menu keys).
- **M6** A preset pack import that ends while the sheet is up: the report waits
  (a person).
- **M7** (QA can script) the unreadable-size paste: only the "could not be read"
  row with every target counted; then mixed sizes with one missing master: two
  rows, "differs" first. `status.md` reports both scripted; QA repeats them on its
  own copy.
- **M8** The toolbar Paste item's tooltip by hover (the item is palette-only):
  `Paste Adjustments: Tone, Color Grading` after a copy, updating after another
  Copy, plain `Paste Adjustments` with nothing copied (a person; QA reads
  `print clipboard`).
- **M9 (new, from C4)** A Spots paste onto one photo, then ⌘Z at once: the paste
  is undone, not the step before it. A person with a real keyboard; QA's script
  waits after each paste and cannot race it. Onto many photos, ⌘Z while Activity
  shows the measuring is the documented limit, not a defect.
- **M10 (new, from C1)** Paste Spots and Distortion in the loupe onto a photo
  with no spots or masks: no frame question; onto one with a spot of its own: the
  question, "1 of 1" (a person, or QA's script as the engineer ran it).
