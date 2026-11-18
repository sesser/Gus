# Import preset packs (.lnpc): design review

Reviewer: apple-ui-designer. Date: 2026-11-17. Issue: #203.
Branch `feature/luminar-preset-import` at 923d9fd, against `design.md` rev 2
(with its new §12), `status.md` and the HIG.

**Verdict: pass with two small findings and no blocker.** The page, the manager
changes, the strings and the user guide match the design. The two findings (F1,
F2) are cheap; the rest is manual checks that cannot be scripted.

**What I could not do.** I have no shell, so I did not read the PRD (rev 3) from
the issue: its requirements are taken as the design and `status.md` cite them
(R1 to R12, AC1 to AC12). I did not build or run the app; everything below is
from reading the code, the String Catalog and `docs/USER_GUIDE.md`, plus the HIG
Typography page (checked for the caption size).

## Findings for the engineer

| # | Severity | Finding | Fix |
|---|---|---|---|
| F1 | Medium | Design §1.1 asked for a test that `PresetImport.fileExtensions` gives one `UTType` per extension, because `presetFileTypes` uses `compactMap` and silently drops a nil: `.lnpc` would be greyed out in the open panel with no error. No such test exists (`Tests/` has only `fileExtensions.contains("lnpc")`), and `status.md` AC1 lists only manual M1. | Add the test in `PhotoCoreTests` (`UniformTypeIdentifiers` is available there): `PresetImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }.count == PresetImport.fileExtensions.count`. If it fails on any system, return a Design question; do not declare a type (design §1.1, AC10). |
| F2 | Low | `runPresetImport` sets `showsPresetSheet = true` when a pack import ends. The library window has three independent sheet flags (`MainView`: Export, look-up tables, presets) and the import runs about 0.7 s after the open panel closes, so a person can open Export (⇧⌘E) in that gap. Design §2.2 and UI_REDESIGN §8 say one sheet at a time. I could not tell what SwiftUI does with a second `isPresented` sheet on the same view (it may log and ignore it, or present it after the first closes). | Confirm by trying (manual M9). If it is lost or misbehaves, open the manager only when no other sheet is up and otherwise leave the report to the manager's **Import Report** button, or open it when the other sheet closes. Not a design change: the announcement and the button already exist. |

Nits, no action required: `PageHeader`'s comment says "the sheet closes only from
the tables", which is no longer true (the preset list closes from Done and Esc
too); an unreadable preset's row (`UnreadablePresetRow`) has no `.help` for a
truncated name, unlike readable rows.

## Design requirements

| Requirement (design.md) | Result | Evidence |
|---|---|---|
| §1 No new menu item, shortcut, toolbar item or context-menu change; three starting points unchanged | Pass | `LibraryCommands` still has Import Presets… and Manage Presets…; `PresetsSection` and the manager keep **Import…** |
| §1.1 `.lnpc` is added to the open panel's list; no type declared; message names `.lnpc` | Pass (panel: needs manual check M1) | `PresetImport.fileExtensions`; no `lnpc` in `Support/*`; panel message and the other three format lists carry `.lnpc` and are in the catalog |
| §1.1 test that every extension yields a `UTType` | **Fail (F1)** | no such test |
| §1.3 Finder does not open `.lnpc` | Pass | `PhotoApplication.swift:93` filters on `PresetFile.fileExtensions` only; `PresetPackTableTests` pins it |
| §2.1 and §2.2 report as a page of the manager sheet, not an alert; alert unchanged for other formats; mixed import has one result | Pass | `PresetManagerSheet` switches on `presetManagerPage`; `runPresetImport` takes the page only when `includesPacks`, otherwise `presetImportSummary` |
| §2.2 sheet opens on the page after a menu or heading import; Import… disabled with "Importing…" while it runs; imports one after another | Pass (sheet over another sheet: F2) | `showsPresetSheet = true`; `isImportingPresets`; `presetImportChain`. Measured 0.7 s, so no Activity job (A6) |
| §2.3 layout: `PageHeader` with Back, summary line, Not imported first, one section per pack in order, Other presets last; 560 × 480; Done trailing | Pass | `PresetImportReportPage`; frame unchanged in `PresetManagerSheet` |
| §2.3 preset rows: collapsed `DisclosureGroup` with name and a count line, zero parts left out, "Nothing carried over" | Pass | `PresetReportRow`, `PresetReportText.counts` (unknown identifiers count as left out: `PackPresetReport.count`) |
| §2.3 status lines: symbol plus words, secondary symbols hidden from VoiceOver, nothing red or green, tools joined with the localized list | Pass | `StatusLine`; `PresetReportText.tools` uses `.formatted(.list(type: .and))` |
| §2.3 "Not recognized" is its own line, identifiers monospaced at 13 pt, primary color, comma-separated, unaltered, "(no name)" for an empty one, selectable | Pass by reading; look needs manual check M7 | `.font(.system(.body, design: .monospaced))`, `.foregroundStyle(.primary)`, `identifiers(_:)` joins with ", ", `.textSelection(.enabled)`. The identifiers are a `Text` interpolated into `Text("Not recognized: \(identifiers)")`: the code builds, but I can't confirm the monospaced style survives the interpolation without seeing it |
| §2.3 names: known tools through the catalog, one keyed entry each with the translator comment; pack, preset and unknown names verbatim | Pass | 36 `presetPackTool.*` entries (count matches the table's 36 cases); `Text(verbatim:)` for pack, preset and identifier text; `PresetText.toolComment` |
| §2.3 long names truncate at the tail with `.help`; tool lines wrap | Pass | `lineLimit(1)`, `.help`, `fixedSize(horizontal: false, vertical: true)` |
| §2.3 footer: one Done (default action), Back is Esc, no Cancel | Pass | `Button("Done").keyboardShortcut(.defaultAction)`; `PageHeader` Back has `.cancelAction` and a hidden ⌘[ twin, as the look-up pages do |
| §2.4 summary line "3 packs · 47 presets · 52 look-up tables added", zero parts left out, "Nothing was imported." | Pass | `PresetReportText.summary(of: result)`; plural variations in the catalog |
| §2.5 manager's **Import Report** button after Export All…, dimmed until a report exists, report in memory only | Pass | `PresetManagerSheet` line 60; `presetImportReport` is a plain property, no migration |
| §3 refused files: warning symbol, file name, typed reason from the six wordings; other files import; the report always renders | Pass | `RefusedFileRow`, `PresetReportText.reason`; all six strings in the catalog. Files that aren't packs show `failure.reason`, an English string from PhotoCore (see "Known" below) |
| §3 an unreadable preset is a row in its pack with "Its settings can't be read." | Pass | `UnreadablePresetRow`; name or "Preset ‹n›" |
| §4 re-import: "replaced" or "‹n› replaced, ‹m› added" on the pack header; no confirmation | Pass | `summary(of: pack)`; debug-script result in `status.md` |
| §6 VoiceOver: headings, one element per status line, preset row as name plus value, summary announced when the import ends | Pass by reading; not scriptable (M10) | `.accessibilityAddTraits(.isHeader)` on section headers and `PackHeader`; `StatusLine` and refused rows combine children; `PresetReportRow` label and value; `AccessibilityText.announce(... priority: .medium)` |
| §6 Increase Contrast, Reduce Transparency, Reduce Motion: semantic colors, no glass, system disclosure animation | Pass by reading; needs manual check M2 | only `.primary` and `.secondary`, no custom background |
| §6 text sizes | Pass, with a design correction | see design.md §12.1: `.caption` is 10 pt on macOS (HIG minimum), the summaries are 11 pt |
| §7 menu bar, toolbar, Liquid Glass | Pass | no change; no glass or tint added |
| §8 strings: all through the catalog, plural forms for counts, no brand word, sentence style | Pass | see "Wording" below |
| §8 user guide | Pass | see "User guide" below |

## Wording against the catalog

Every key the page and `PresetReportText` use has an entry: Import Report,
Importing…, Not imported, Other presets, Mapped / Approximated / Left out / Not
recognized: %@, `%@ (as %@)`, (no name), Nothing carried over, Nothing was
imported., replaced, `%lld replaced, %lld added` (positional `%1$lld`, `%2$lld`),
Preset %lld, Its settings can't be read., and the six reasons. Each has a
translator comment.

**Plural forms.** `%lld packs`, `%lld presets`, `%lld look-up tables` and
`%lld look-up tables added` have one and other forms in English. `%lld mapped`,
`%lld approximated` and `%lld left out` have a single form: correct in English
(the adjective does not change), and the design's "plural-aware" is met where a
noun follows the number. A translator can add forms later.

**Style.** Sentence style for rows and reasons, title style for the page title
and the Import Report button, verbs and plain words, no "Luminar" or maker name
in any string (`PresetPackTableTests` checks it).

## User guide

`docs/USER_GUIDE.md` lines 559 to 582 use the exact terms: **Import Presets…**,
**Manage Presets…**, **Import Report**, **Back**, **Done**, **Import**, "Not
recognized", "replaced", collection, look-up table. They match the menu items,
the button titles and the page.

- The corrected Finder sentence is there twice and right: line 589 says
  double-clicking "one of this app's preset files" in the Finder imports it, and
  line 581 says packs are imported only from **Import** and that the app does
  not open them from the Finder. That matches `PhotoApplication`.
- The guide says the **Import Report** button "shows the last report again until
  the app quits"; it is also replaced by the next pack import. Cosmetic: "the
  last report" already says it.
- The mixed-import "Other presets" row and the **Importing…** indicator are not
  described. Not needed.

## Keyboard

By reading: Esc is Back (`PageHeader`, `.cancelAction`), Return is Done, ⌘[ is
Back, as on the look-up table pages. The preset list keeps Return for Done and
Esc for closing the sheet, as before. No hover-only information.

One real risk, not a finding until checked (M3): the page's `List` has no
selection binding. In a SwiftUI macOS `List` without one, arrow keys may not move
between rows and Right and Left may not expand a `DisclosureGroup` (design §6
promised both, from my own assumption). If so, the fix is `List(selection:)` with
a throwaway selection, or an explicit expansion state with an "Expand All"
command; return it as a Design question and I will rule.

## What is working

- One page inside the existing sheet, no new window or control: native, and it
  follows the look-up table browser's pattern.
- The counts line carrying the hunt-for-what-was-left-out information while the
  tool names stay one click away.
- Words plus symbols for status, no red and green, so an expected result does not
  read as a failure.
- "Not recognized" as its own monospaced line, apart from tools we named.
- The alert untouched for the existing formats (R12).

## Known, accepted

- Failures of files that are not packs (a damaged `.lrtemplate` in a mixed import)
  show `failure.reason`, the English fragment PhotoCore has always produced, in
  an otherwise localized page. Same text as the old alert; design §3 limited the
  typed reasons to packs.
- Light appearance is unreachable (library window and its sheets are dark only):
  design.md §12.2.

## Manual checks (for qa.md's "For a person")

The owner is not asked to check VoiceOver or macOS 15 and 26 (project memory).
The debug script cannot expand a row, click a disclosure, or read the SwiftUI
accessibility tree; `preset report` prints `PresetReportText.lines`, which is the
same text but not the view's labels.

- **M1.** Open panel, owner's Mac: `.lnpc` files can be chosen (not greyed out),
  alone and with other formats, and a folder of packs. (Covered everywhere else
  by F1's test.)
- **M2.** The Import Report page for the four packs: look, truncation of long
  pack and preset names, wrapping of long tool lines at 560 pt, in Dark, with
  Increase Contrast, with Reduce Transparency. `preset import … ; preset
  reportpage; preset windowshot <file>` gives the collapsed page.
- **M3.** Keyboard on the page, Full Keyboard Access on: Tab reaches Back, the
  rows and Done; arrows move between rows; Right, Left or Space expand and
  collapse a preset; Esc goes Back and does not close the sheet; Return is Done;
  ⌘[ is Back. See the risk above.
- **M4.** Import from Adjust ▸ Import Presets… and from the heading's Import…:
  the manager opens on the report; Back shows the new collections; the manager's
  **Import Report** button is dimmed before the first import and opens the page
  after it.
- **M5.** Import the same pack again: the pack's header says "replaced", nothing
  doubles in the list.
- **M6.** One good pack and one damaged file in one selection: the good pack
  imports, the damaged file is under Not imported with its reason, the summary
  line counts only what imported.
- **M7.** Expand a preset with an unknown tool: its own "Not recognized" line,
  identifiers in monospace (confirm the monospace shows: it is a `Text`
  interpolated into a localized `Text`), unaltered, wrapping at the commas,
  selectable and copyable; the count line includes it under "left out".
- **M8.** Double-click a `.lnpc` in the Finder, and drop one on the Dock icon:
  neither opens or imports into the app.
- **M9.** F2: choose packs, and in the second after the panel closes press ⇧⌘E.
  The Export sheet and the report must not fight; nothing is lost.
- **M10.** (QA, not the owner.) Accessibility of the page by reading and by any
  assistive tool QA has: section headings, preset row as name plus count value,
  one element per status line, the "Not recognized" line read as one element
  with its identifiers as plain text, the spoken summary when the import ends.
- **M11.** A mixed import (a pack and an `.lrtemplate`): the **Other presets** row
  reads as the old alert did; no alert appears.
- **M12.** Start Import… from inside the manager with a large selection (or a
  debug build): **Import…** is dimmed and the spinner with "Importing…" shows;
  Done during the import does not leave the sheet stuck.

## Confirmation (2026-11-17)

Reviewer: apple-ui-designer. Against `status.md` and commit 7d784f0 (and the
earlier review-fix commits). Read from code only: I have no shell, so I did not
build, run the tests or run the `preset sheets` command; the results below that
come from a run are `status.md`'s (1134 tests pass, F2 debug-script output).

| # | Result | Evidence |
|---|---|---|
| F1 | Confirmed | `PresetPackTableTests.everyImportExtensionHasAType` loops `PresetImport.fileExtensions`, expects a non-nil `UTType(filenameExtension:)` for each with the extension in the failure message, and repeats my `compactMap` count comparison. `status.md` says it passes on macOS 27.2 and that no type is declared; CI runs it on 26 and 15. If it fails there, it is a Design question, not a declared type. |
| F2 | Confirmed, behavior acceptable (below) | `openPresetSheetWhenFree` sets `presetSheetWaits` when Export or the look-up table sheet is up and otherwise sets `showsPresetSheet`. `MainView` gives both of those sheets `onDismiss: model.sheetDidDismiss`, which re-checks that neither is up again and then sets the report page and opens the manager. `presetManagerPage = .report` is set at import end as well, so a wait leaves the page right. The Import Report button and the spoken summary are unchanged. `status.md`'s `preset sheets` output (export, then lut, up: "waits true attached 1"; after close: manager open on the report, attached 1) shows one sheet attached at every point. |
| Nit 1 (`PageHeader` comment) | Confirmed | The comment now says Esc goes back and "on a page it never closes the sheet", which is true of every user of it. |
| Nit 2 (`.help` on `UnreadablePresetRow`) | Confirmed | `.help(PresetReportText.name(preset))` beside `lineLimit(1)` and tail truncation, as the readable rows have. |

**Is F2's behavior acceptable under the one-sheet rule?** Yes. The rule
(design §2.2, UI_REDESIGN §8) is that a person never sees two sheets at once or
loses one to another. Waiting for the other sheet to finish closing keeps that,
and using `onDismiss` rather than the flag going false avoids presenting during
the close animation, the case where SwiftUI is least predictable. Three details
I checked and accept:

- The report is deferred, never dropped: if the person cancels Export, or closes
  the look-up tables, the manager still opens on the report, and it stays
  available from **Import Report** whatever happens.
- If the person opens the other sheet again in the gap between its close and the
  `onDismiss` call, the guard in `sheetDidDismiss` keeps the wait, and the next
  dismissal opens the report. It cannot open over a sheet.
- The summary is spoken at the import's end, while the other sheet may still be
  up. That is right: it tells VoiceOver users the import finished, and the page
  follows.

One thing I am labelling as judgment, not a defect: a person who is in the
Export sheet when the import ends gets no visible sign until it closes. Export is
a short, modal task, so I would not add one (an Activity message would be a
second place for the same result).

**M9 stays a manual check, narrowed.** The debug script drives the flags
(`showsExportSheet`, `showsLookTableSheet`) and shows one attached sheet, but
not a real ⇧⌘E arriving from the keyboard in the second after the open panel
closes, nor SwiftUI's real `onDismiss` timing under a real close animation (the
script's `export close` sets the flag). Keep M9, as: choose packs, press ⇧⌘E
at once; the Export sheet stays; Cancel it; the manager opens on the report
with nothing doubled; repeat with Browse Look-Up Tables…. It is quick and the
owner can do it on any one pack. The owner's own record says VoiceOver and macOS
15 and 26 are not asked of them, so this stays on macOS 27.

**Result: F1, F2 and both nits are closed. Verdict unchanged: pass.** Open
manual checks are M1 to M12 as listed above, with M9 as just described.

## Second confirmation (2026-11-17)

Reviewer: apple-ui-designer. Against commit 50b582f (design.md §13, my ruling on
QA's Q1). Read from code, `status.md` and `docs/USER_GUIDE.md` only: no shell,
so no diff, build or test run (`status.md`'s totals are the engineer's).

| Item | Result | Evidence |
|---|---|---|
| Table listed as Mapped and as Approximated | Confirmed | `LuminarMapping.lookUpTable` reports `.mapped` once the table is installed, then `.approximated` with `[.contrast, .saturation]` only when Contrast or Saturation changed. `toolReports` drops a mapped entry for an approximated tool except those in `exactAndApproximated`, which holds only `.known(.lookUpTable)`. The Approximated entry names only the approximated part, as §13 says. |
| Counts | Confirmed | The tool is one entry under each status, so Heritage Hues is "3 mapped, 5 approximated" (`status.md`), and the count line still equals the number of entries in the lines below it. The page code is unchanged: the counts and lines come from the report's entries, so no view change was needed. |
| Unreadable table (C6) | Confirmed | The missing-file and second-table paths report only `.leftOut` and never reach the `.approximated` branch's mapped entry, so no "Mapped" line appears for a table that did not install; `anUnreadableTableKeepsItsApproximatedValues` is unchanged and still the pin. |
| Other tools | Accepted | `status.md` records why no other tool has an exact part beside an approximated one (Vignette's style stays in its own control, Matte, Dramatic and Black and White are approximated throughout, the Details Enhancer's sharpening is its own entry). That is the engineer's reading of the mapping; I did not re-derive it. |
| Tests and records | Confirmed | `lookUpTableContrastAndSaturationAreApproximated` expects `mapped, approximated, develop:mapped`; `aTableWithContrastCountsUnderBothStatuses` is added; `status.md` carries the new totals and the ruling. |
| Nothing else on the page changed | Confirmed by reading | The change is in PhotoCore's report building plus tests and docs; the page, the strings and the summary line are as reviewed. |

**Reading the lines.** "Mapped: LUT Mapping, Develop" and "Approximated: LUT
Mapping (as Contrast and Saturation)" read correctly together: the second names
what is approximated and where it went, and the first says the table is in. The
repetition of the tool name is the cost of one status per line, the same shape
as a table both mapped and left out, and is the right trade.

**User guide (nit, no action required).** `docs/USER_GUIDE.md` lines 572 to 574:
"a look-up table whose tool also changes contrast or saturation is listed as
mapped, and again as approximated for those". The terms match the page. "For
those" can be read as "for those presets"; "and again as approximated for its
contrast and saturation" is clearer. The sentence also sits inside a long
parenthesis that wraps awkwardly; consider moving it to its own sentence.

**Result: closed. Verdict unchanged: pass.** M1 to M12 stand as listed; M2 (the
page's look) should include one preset with a table and a contrast setting, such
as Heritage Hues, to see the two lines together.

## Summary for the issue

Design review of #203: pass with two small findings, no blocker. The Import Report page, manager changes, catalog strings (plurals, translator comments, keyed tool names) and user guide match design.md rev 2; the Finder double-click line is corrected. Open: F1 (add the test that every importable extension has a `UTType`, which the design asked for and is missing) and F2 (a pack import ending while Export or look-up sheet is up: confirm the one-sheet rule holds). Two corrections to my own design.md (§12): macOS `.caption` is 10 pt, and Light is unreachable in the dark-only library window. Manual checks M1 to M12 (open panel, Increase Contrast, keyboard in a `List` without selection, "Not recognized" look, Finder, race with another sheet). I had no shell, so the PRD was not re-read. Details: docs/features/luminar-preset-import/review.md
