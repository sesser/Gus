# Import preset packs (.lnpc): design

Owner: apple-ui-designer. Date: 2026-11-17.
Issue: #203. Status: complete (rev 2, 2026-11-17: PRD rev 2 and the owner's RI-1
ruling applied; §2.3 "Names", §6, §8, §10). No open Requirements issue; one
clarification for the product manager in §10 (RI-2, not blocking). Assumptions
in §9.

**Inputs.**

- Requirements: the issue body (PRD, approved 2026-11-17), R1–R12 and AC1–AC12,
  cited as "R‹n›" and "AC‹n›".
- Code read on `feature/luminar-preset-import`:
  `Model/PresetActions.swift` (`chooseAdjustmentPresetImport`,
  `importAdjustmentPresets`, `summary(of:)`, `PresetText`),
  `Views/PresetManagerSheet.swift`, `Views/PresetsSection.swift` (heading
  buttons, empty-state text), `Views/LibraryCommands.swift` (Adjust ▸ Import
  Presets…), `Views/MainView.swift` (the summary alert),
  `Views/LookTableBrowserSheet.swift` (pages with Back),
  `PhotoCore/Presets/PresetImport.swift` and `CameraRawMapping.swift`,
  `Edits/AdjustmentPresets.swift` (the name-clash rule), `Support/Info.plist`,
  `PhotoApp/PhotoApplication.swift` (Finder opens), `docs/USER_GUIDE.md`
  lines 538–562, `docs/UI_REDESIGN.md` §8 (sheets, pages), and
  `docs/features/ui-redesign/design.md` P1–P5.
- HIG pages read 2026-11-17 (markdown versions): Alerts, Sheets, Disclosure
  controls. Lists and tables, Writing and Accessibility are relied on from
  earlier designs in this repository, not re-read today.

**No custom chrome.** The change is one open-panel list, one new page inside
the existing preset manager sheet (a SwiftUI `List` of `Section`s and
`DisclosureGroup`s), and strings. No new window, sheet, control or menu item.

## 1. Where the import starts (R1, AC1, AC10)

The three starting points stay and keep their titles: **Adjust ▸ Import
Presets…**, the Presets heading's **Import…** button, and **Import…** in the
preset manager. All call `chooseAdjustmentPresetImport()`. **No menu item,
shortcut, toolbar item or context-menu change.** The title is already
format-neutral, so it does not need to name packs.

### 1.1 Open panel

- Same `NSOpenPanel`: files and folders, multiple selection (the owner's three
  packs in one go, R1), run through `WindowModal` on the library window (or on
  the sheet when the sheet starts it).
- `allowedContentTypes` is still built from `PresetImport.fileExtensions` with
  `UTType(filenameExtension:)`; adding `lnpc` to that list is the whole change.
  This is the way `.lrtemplate` and `.xmp` already appear, and neither is
  declared in `Info.plist`, so **nothing is declared for `.lnpc` either**: no
  exported or imported type, no document type, no UTI (owner ruling; AC10).
  The panel only needs a type to filter by, and the system makes a dynamic one
  from the extension.
- **Risk to check, not assume:** `compactMap` silently drops a nil. If a system
  returns nil for an undeclared extension, `.lnpc` files would be greyed out
  with no error. The engineer adds a test that the list of types has one entry
  per extension, and manual check M1 looks at the panel on the owner's Mac
  (not on macOS 15 or 26: the owner does not test those; CI and the test cover
  them). If the test fails on any system, return a Design question instead of
  declaring a type.
- Panel `prompt` stays "Import". Panel `message` (and the four other places
  that list the formats, §8) gets the new extension:
  "Choose presets (.guspreset, .lrtemplate, .xmp, .dng or .lnpc), or folders
  of them." The existing string already takes the first extension from
  `PresetFile.fileExtension`; `.lnpc` is a literal, like the other three. It is
  the file's extension, not a brand string, and it names no application, as
  `.lrtemplate` does not.

### 1.2 A folder of packs

A pack names its own collection (R2), so a folder that holds packs does **not**
wrap them in a collection named after the folder, whatever
`PresetImport.scan` does for Lightroom files. Rule: a pack's collection is the
pack's name; the folder name never applies to a pack. (Mixed folders: the
Lightroom files in it keep today's rule.)

### 1.3 Not opened from the Finder (owner ruling)

`AppDelegate.application(_:open:)` filters on `PresetFile.fileExtensions` only
and stays so. Double-clicking a `.lnpc` does not open Gus, and dropping one on
the Dock icon does nothing. Nothing is registered. The user guide says Import
is the way in (§8).

## 2. The result: one report, as a page of the preset manager (R7, AC6)

### 2.1 Why not the alert

The import today ends in an alert whose text counts, over every preset, how
many left out each kind of setting ("Texture (3), Masks and local adjustments
(1)…"). That does not answer R7. R7 asks per preset: what was mapped,
approximated, left out. A pack has a dozen to several dozen presets and the
owner imports four at once. That is a reading task, and HIG Alerts is plain
about it: an alert is for critical information, "avoid using an alert merely to
provide information", and keep its text as short as possible. A scrolling alert
of 150 lines is the wrong surface.

The surface that fits is the one the new presets live in. UI_REDESIGN §8 already
has the rule: "a step inside a sheet… is a page in the sheet with a Back button,
not a second sheet", and HIG Sheets agrees ("display only one sheet at a time";
Back "lets people navigate to a previous step… or to a parent view in a
hierarchy"; and never Cancel, Done and Back together). The look-up table browser
does exactly this for its Import and Manage pages (`LookTableBrowserSheet`,
`PageHeader`). So:

> **The import report is a page of the preset manager sheet, "Import Report".**

### 2.2 When it appears (P4: report where the task is)

| Import contained | Result shown |
|---|---|
| At least one `.lnpc` (alone or mixed with other formats) | The **Import Report** page. Started from inside the manager: the sheet turns to the page. Started from the menu or the heading: the preset manager sheet opens on the page. No alert. |
| Only existing formats | Exactly as today: the alert from `summary(of:)`, unchanged (R12: nothing that works today changes). |

Opening the manager unasked after a menu import is a small surprise, and it is
the right one: the sheet is where the new collections are listed, Back goes
straight to them, and the alternative is an alert plus a button that opens the
same sheet. When the sheet is already open (Import… in it), the alert would have
been a modal on a modal, which P4 and the sheet rule avoid.

A **mixed** import has one result, not two: the page gets an "Other presets" row
(§2.3) carrying the text the alert would have shown, and failures of every file
go in "Not imported". The alert does not appear in that case.

While the import runs, **Import…** is disabled in the sheet and a small
`ProgressView` with "Importing…" sits beside it. From the menu there is nothing
to show for what should be well under a second; if the engineer measures more
than about one second for the owner's four packs, it goes to Activity as a job
like the other background work, and that is a Design question (§9, A6).
Two imports never run at once: a second waits for the first.

### 2.3 Page layout

The sheet's size does not change (560 × 480; HIG Sheets: people don't expect to
resize sheets). The page fills it, as the look-up table pages do: header on top,
buttons at the bottom.

```
┌──────────────────────────────────────────────────────────┐
│ ‹ Back   Import Report                                   │
│ 3 packs · 47 presets · 52 look-up tables added           │
├──────────────────────────────────────────────────────────┤
│ Not imported                                             │
│  ⚠ Broken.lnpc          The file is damaged or incomplete│
│ American Dream                 12 presets · 12 tables    │
│  ▸ Golden Hour Fade            4 mapped · 1 approx. · 2 …│
│  ▾ Soft Matte                  5 mapped · 1 left out     │
│       ✓ Mapped: Develop, Curves, Color Balance           │
│       ≈ Approximated: Structure (as Clarity)             │
│       – Left out: Accent AI                              │
│  ▸ …                                                     │
│ Camping Trip                   9 presets · 9 tables      │
│  …                                                       │
├──────────────────────────────────────────────────────────┤
│                                                  [ Done ]│
└──────────────────────────────────────────────────────────┘
```

**Header.** `PageHeader` (Back chevron, title "Import Report"), lifted from
`private` in `LookTableBrowserSheet.swift` to internal so both sheets use one
implementation. Under it one line of 11 pt secondary text summarizing the whole
import (§2.4). Back returns to the preset list.

**Body.** One `List` (inset, the manager's own style), sections in this order:

1. **Not imported**, only when something was refused (§3). First because it is
   the only part that asks the person to do something.
2. **One section per pack**, in the order the files were chosen. The header is
   the pack's name (`.headline`, as the manager's collection headers) with a
   trailing 11 pt secondary summary: "12 presets · 12 look-up tables", and "·
   replaced" when the pack was already in the library (§4).
3. **Other presets**, only in a mixed import: one text row, the
   existing aggregate sentence for the non-pack files.

**Preset rows** are `DisclosureGroup`s, collapsed. Collapsed shows the preset
name (primary) and one count line in `.caption` secondary: "4 mapped, 1
approximated, 2 left out", leaving out any zero part; "Nothing carried over" when
all are zero (§9, A3). HIG Disclosure controls: "hide details until they're
relevant", with the most useful information visible by default. The counts are
that information; the tool names are the detail. Collapsed by default because a
pack is long and the person is usually hunting for what was left out.

**Expanded** a preset shows up to four lines, one per status, each a leading
SF Symbol and then words, omitting a status with no tools:

| Status | Symbol | Line |
|---|---|---|
| Mapped | `checkmark.circle` | "Mapped: ‹tools›" |
| Approximated | `plusminus.circle` | "Approximated: ‹tool› (as ‹Gus control›), …" |
| Left out | `minus.circle` | "Left out: ‹tools›" |
| Not recognized | `questionmark.circle` | "Not recognized: ‹identifiers›" (§2.3 "Names") |

The tools are joined with `formatted(.list(type: .and))`, wrapping to several
lines. The word and the symbol both carry the status, so color and shape are
never the only signal (Foundations: color). Symbols are in the label's
secondary color; nothing is red or green. A left-out tool is not an error, and a
sea of red across a pack would make an expected result look like a failure.
Symbols are `.accessibilityHidden(true)`; the words say it.

**Names, by where they come from** (PRD rev 2, R11):

| Kind | Source | In the String Catalog? | Shown as |
|---|---|---|---|
| Gus control names ("Clarity", "Tone Curve") | `AdjustText` where one exists | yes | normal text |
| A Luminar tool the mapping knows (mapped, approximated, or one of R6's left-out tools) | the one name table, display name written by us | **yes** | normal text |
| A Luminar tool the table does not know | the identifier exactly as the pack gives it | **no**, never | monospaced, its own line |
| Pack names and preset names | read from the pack | no | verbatim, normal text (`Text(verbatim:)`) |

*Known tools go through the catalog.* The display names are our wording (plain
words for what the tool is called, never Skylum's text), so they follow the
app's string rules like every other word on screen: a catalog entry per name,
added by hand, found by `LocalizationTests`, and translatable. They are title-style
like Gus's control names ("Sky Enhancer"). Each entry carries a translator
comment, "Name of a tool in an imported preset pack. A proper name: leave it as
is if there is no usual translation." so a translator does not invent one. The
precedent is `CameraRawFeature` (PhotoCore enum) with `PresetText.title`
(PhotoApp, catalog strings); the same split here keeps PhotoCore free of display
text: a PhotoCore `LuminarTool` enum whose raw value is the pack's identifier
and whose cases are exactly the tools the mapping handles or R6 names, plus an
`unknown(identifier)` case for everything else, and a `PresetText` switch giving
each known case its catalog string. The engineer may structure it differently,
but the display wording must reach the screen through the catalog, not a
Swift dictionary of literals (a literal outside `String(localized:)` is exactly
what `LocalizationTests` catches).

*Unknown identifiers.* A tool the table does not know is by definition left out
(the mapping has no equivalent and never invents one), so it counts in the
preset's "left out" total, but it is listed on its own line, **"Not
recognized: ‹identifiers›"**, never mixed into the "Left out" line. The reasons:
a name we wrote and an identifier a pack gave must not look alike, since the
first says "this tool has no equivalent here" and the second says only "this app
has no word for it". The identifiers are in a **monospaced** system font at the
line's size (`.system(.body, design: .monospaced)` at 13 pt; `.caption` size is
not used, the line is content), in the label's primary color, with the words
"Not recognized:" in the normal font. Monospace is the system convention for
identifiers and code, needs no color, and survives Increase Contrast and
Reduce Transparency. Several identifiers are separated by a comma and a space
(not the localized "and": an identifier list is data), wrapping at the commas;
an identifier is never truncated or altered, including its case. The text view
selects as a whole, so the owner can copy an identifier into an issue. The
construction (one `Text` with the identifier run styled, or an interpolated
`Text`) is the engineer's; the look is the contract.

If the pack's identifier is empty or whitespace, the row shows "Not recognized: (no
name)"; the engineer's decision on the exact string (a catalog entry).

*Raw identifier reading (VoiceOver).* An identifier such as a run-together
camel-case word reads badly as a spoken word, and spelling every one letter by
letter is slower than useful. The status line is one accessibility element,
label "Not recognized: ‹identifier›, ‹identifier›", read in the default way; the
line is not set to spell out. Someone who needs the letters can move through it
by character with the VoiceOver cursor, which works because the identifier is
ordinary text (not an image or a custom drawing). This is judgment, not a stated
Apple rule; a 20-character name read as one word is accepted over a long spelled
one. The word "Not recognized" tells a listener at once that it is not a
description. Manual: M7, by the owner's judgment and QA's accessibility
checks, not by asking the owner to run VoiceOver.

**Long names.** Tool lines wrap (they are the content). Pack and preset names
truncate at the tail on one line, with the full name as `.help`, as the
manager's rows do.

**Footer.** One **Done** button, trailing, the default action (Return), closing
the sheet, as the manager's own Done. Back is the page's cancellation: Esc goes
Back, as on the look-up table pages (the engineer copies
`LookTableImportPage`'s key handling; if it differs, Design question). Two
buttons, not three (HIG Sheets: avoid Cancel, Done and Back together).

### 2.4 Header summary line

Counts only, plural-aware, the numbers the owner wants at a glance:
"3 packs · 47 presets · 52 look-up tables added". Parts that are zero are left
out; "look-up tables added" counts what `addedTables` counts, so a re-import says
nothing about tables (none were added). With only refusals: "Nothing was
imported."

### 2.5 Reaching it again (judgment, label: not HIG policy)

Nothing else would let someone who pressed Back, or closed the sheet, read it
again, and the point of per-preset detail is looking things up while trying the
presets. So the manager's bottom row gets one more button: **Import Report**,
after **Export All…**. It is dimmed until an import this session has produced a
report and opens the page. The report is held in memory in the model, replaced by
the next pack import, and **never stored** (no migration, R12). Dimmed rather
than hidden is P1's rule. If the owner would rather not have the button, it can
go without changing anything else; the page is built to be reached either way.

## 3. Refused files and presets (R9, AC8)

A refused file shows in **Not imported**, one row each: `exclamationmark.triangle`
(the page's only caution symbol, used because the person may need to act: HIG
Alerts says to use it sparingly), the file name on one line, and the reason in
`.caption` secondary under it. The other files in the selection import as
normal: the report always renders, and the title line says what did import.

PhotoCore returns a typed reason, not a string (the existing
`PresetImport.describe` returns untranslated English fragments, and these are
shown in the new page); the view maps each case to a catalog string.

| Case | Shown as | Notes |
|---|---|---|
| not a zip archive, or a zip with no `Config/config.json` | "Not a preset pack." | One wording; the test keeps the two cases distinct. |
| truncated or corrupt archive | "The file is damaged or incomplete." | |
| config present but unreadable | "The pack's settings can't be read." | |
| a pack with no presets | "The pack has no presets." | Imports nothing, so it is refused, not an empty collection. |
| over the engineer's size or count limits (R9: memory only) | "Too large to read." | The limits are the engineer's; the wording stays. |
| the file can't be opened | the system's reason, as `describe` does today | |

A **single preset** in an otherwise good pack that can't be read is skipped and
shown as a row in its pack's section with the symbol, its position or name if
known, and "Its settings can't be read." The rest of the pack imports (§9, A4).

No message names a brand or a reasoning the person can't use: "damaged or
incomplete" beats "central directory not found".

## 4. Importing again (R8, AC7)

Existing rule (read from `saveAdjustmentPresets`): a preset with the same name in
the same collection is **replaced in place**, keeping its id and uuid; anything
else is added. A pack imported twice therefore gives the same collection and the
same presets (and the look-up tables are recognized by content, `installTables`).

The UI says so rather than doing it silently, because replacing discards what the
person changed in the manager since (a preset's groups, which are edited from
the Include menu):

- The pack's section summary adds "· replaced" when every preset was already
  there, or "· 4 replaced, 8 added" when some were.
- The header line is unchanged except that "added" counts are for what is new.
- No confirmation before it: the person chose to import the pack again, and
  re-importing is the way to get the pack's own values back. The cost (changes
  made in the manager are replaced) is stated in the report and the user guide
  (§8). Nothing here can be undone with Undo, as with every other preset import.

If the person renamed an imported collection, a re-import cannot tell and makes a
second collection under the pack's name. That follows from recognition by name
(PRD assumption); if the engineer recognizes packs by an identity stored with the
presets that would need a migration, which the PRD expects not to happen.
Either way the report must read correctly: it states what it did.

## 5. Names and collections (R2, R3)

- Preset and pack names follow R2: the system language if the pack has it,
  English otherwise. Nothing in the UI shows that choice, so nothing about it is
  designed here beyond: the report uses the same names the list does.
- The pack's name is the collection name and the look-up table collection name
  (R3), through the same `listNewTables` path as now. A collection the person
  already has by that name is merged into, as Lightroom imports are today.
- A pack name that is empty or only whitespace falls back to the file name
  without extension (`LookTableNaming.cleanedFileName`, as other imports).

## 6. Accessibility

- **Keyboard.** Everything on the page is reachable with Full Keyboard Access:
  Back, the list (arrow keys), each disclosure group (Right and Left arrow expand
  and collapse in a `List` row, Space toggles), Done. Return is Done, Esc is
  Back. No hover-only information: every `.help` repeats text already on
  screen.
- **VoiceOver.** The section header is a heading. A preset row reads as the name,
  its count line as the value, and its state "collapsed" or "expanded" from
  `DisclosureGroup`. Each status line is one element read as its text ("Left
  out: Accent AI, Sky Enhancer"); the symbols are hidden. The "Not recognized"
  line is read as "Not recognized: ‹identifiers›" with the identifiers as plain
  text (§2.3 "Names": not spelled out, navigable by character). The refused-file row
  reads as one element: file name, then reason. When the import finishes,
  `AccessibilityText.announce` (medium priority) says the header summary, so
  someone who cannot see the sheet appear still hears the outcome. This
  replaces the Activity message the other imports don't post either.
  VoiceOver itself is not checked by the owner (project memory: no VoiceOver
  checks asked of the owner); the accessibility labels and the debug script's
  checks are the engineer's and QA's.
- **Contrast and appearance.** Semantic colors only (`.primary`, `.secondary`),
  `List` and sheet backgrounds from the system; they follow Light, Dark and
  Increase Contrast with no custom palette.
- **Reduce Motion.** The only motion is the system disclosure animation, which
  the system reduces itself.
- **Reduce Transparency.** Nothing here uses glass. The sheet is a system sheet.
- **Text.** 13 pt body for names, 11 pt (`.caption`) secondary for counts and
  reasons, as in the manager; nothing below 11 pt.

## 7. Menu bar, toolbar, shortcuts, Liquid Glass

- Menu bar: **no change.** Adjust ▸ Import Presets… already exists and keeps its
  title and place. There is no new command, so no new key.
- Toolbar: no change. Context menus: no change.
- The page adds no glass, tint or custom background. The sheet inherits the
  window's appearance (UI_REDESIGN §8); the content is a standard list on the
  content layer (Hierarchy: content leads, controls recede).
- Concentricity: nothing custom with corners.

## 8. Strings, user guide, copy rules

All of it goes through `Localizable.xcstrings`, added by hand (nothing extracts
automatically), with the product name in no string (BrandingTests). Counts use
plural variations in the catalog (`StringCatalogCompiler` emits `.stringsdict`;
the existing "Presets imported: \(count)" has no plural form, and the new ones
should not copy that). Sentence-style for sentences and row labels, title-style
for buttons and titles (P5).

New or changed keys (final wording, engineer may adjust punctuation only):

| Where | String |
|---|---|
| Panel message, empty states, heading tooltip | the format list now ends "… .xmp, .dng or .lnpc" (four places in `PresetManagerSheet`, `PresetsSection` ×2, `PresetActions`) |
| Page title | Import Report |
| Manager button | Import Report |
| Importing | Importing… |
| Header line | "‹n› packs", "‹n› presets", "‹n› look-up tables added", joined with " · "; "Nothing was imported." |
| Section headers | Not imported; Other presets |
| Pack summary | "‹n› presets", "‹n› look-up tables", "replaced", "‹n› replaced, ‹m› added" |
| Preset counts | "‹n› mapped", "‹n› approximated", "‹n› left out", "Nothing carried over" |
| Status lines | Mapped: %@, Approximated: %@, Left out: %@, Not recognized: %@ ; "%@ (as %@)" |
| Tool display names | one entry per tool in the name table (title-style, our wording, each with the translator comment of §2.3). The list is the table's, nothing else: the engineer adds no name for a tool the mapping does not know |
| Reasons | the six in §3 |
| VoiceOver | the announcement is the header line |

The Lightroom-era strings stay (the old alert is unchanged for those imports).
The word "Luminar" and its maker's name appear in **no** string of ours: users see
`.lnpc`, "pack" and "preset pack". The only Luminar-derived words in the catalog
are the tool display names above, and they are the name table's localization,
not a second list (RI-2). Pack names, preset names and unknown identifiers are
data a pack carries, not words we ship, and never enter the catalog; the existing
UI likewise never says "Lightroom".

`docs/USER_GUIDE.md` (engineer, same change): in the Presets paragraph, add
`.lnpc` packs to what **Import Presets…** reads; say a pack becomes a collection
(and a look-up table collection) named after it; say the **Import Report** lists
per preset what was mapped, approximated or left out, and that importing a pack
again replaces its presets by name; and correct the last sentence, which says
double-clicking a preset file in the Finder imports it: that is true of this
app's own preset files only, and `.lnpc` packs are imported only from Import.
Terms to keep exactly: **Import Presets…**, **Manage Presets…**, **Import**,
**Done**, **Back**, collection, look-up table.

## 9. Assumptions

- **A1.** Tool statuses reach the UI as structured data, not prose: per preset an
  ordered list of (tool: known case or unknown identifier, mapped | approximated |
  left out, optional Gus control for approximated). An unknown tool is always
  left out. PhotoCore decides the status; the UI never infers it and never
  holds display text (§2.3 "Names"). This keeps AC4/AC6 testable without the
  view.
- **A2.** A "mapped" tool is one whose settings all became Gus values as the
  prototype does; "approximated" is anything the README table marks so (Structure
  and Details as Clarity, Supercontrast, and the like). Left out is exactly
  R6's list.
- **A3.** A preset none of whose tools mapped still imports (R2: one preset per
  Luminar preset), with "Nothing carried over" in the report, rather than being
  skipped; skipping would break the pack's order and counts. If it carries a
  look-up table that is its content, so its row shows "1 mapped" at least.
- **A4.** One unreadable preset does not refuse its pack (R9 speaks of files).
  Reasonable, and the least data loss; the PRD is silent, so the PM can overrule.
- **A5.** Pack names follow the same language rule as preset names; if the pack
  has no name field, the file name without extension.
- **A6.** Import time is small. If the four packs take more than about one second
  the engineer reports it as a Design question; the fallback is an Activity job.
- **A7.** The page is not persisted (§2.5).
- **A8.** Collections already in the library with a pack's name are merged into,
  as for every other import.

## 10. Requirements issues for the product manager

**RI-1: closed.** The owner ruled option (b) on 2026-11-17 and the PRD is rev 2:
one identifier-to-display-name table in code, limited to the tools the mapping
knows; unknown tools show their identifier as the pack gives it. The design
applies it in §2.3 "Names" and §6. (Originally: R11 against R7, whether the
report could name tools at all when packs carry only identifiers.)

**RI-2 (clarification, not blocking).** The PRD's assumption leaves open
whether the table's display names go through the String Catalog, "open,
designer". The design says yes (§2.3): they are our wording on screen, and
`LocalizationTests` requires a catalog entry for every UI string. AC10 says the
only Luminar-named data in the repository or the bundle is the one table; the
catalog entries are that table's localization and so are the same data in a
second file. Please confirm that reading, or word AC10 as "the table and its
catalog entries". The engineer's AC10 test should then check the catalog's
tool-name entries against the table (no entry for a tool the table lacks).

No other requirements issue: the PRD is silent on persistence of the report,
progress and a partly unreadable pack; those are assumptions above.

## 11. Manual checks (for the review)

- **M1.** In the open panel on the owner's Mac, `.lnpc` files can be selected
  (not greyed out) with no file-type registration in the app.
- **M2.** The Import Report page with the owner's four packs: look, truncation
  of long names, expanding several presets, Back, Done, Esc, in Light and Dark and
  with Increase Contrast.
- **M3.** Import started from Adjust ▸ Import Presets… and from the heading's
  Import…: the manager opens on the report; Back shows the new collections.
- **M4.** Import again: the section says it replaced the presets and nothing
  doubles.
- **M5.** A selection of one good pack and one damaged file: the good one imports
  and the damaged one is listed with its reason.
- **M6.** Double-clicking a `.lnpc` in the Finder does not open Gus.
- **M7.** A preset with a tool the table does not know (a fixture, or one in the
  owner's packs): its expanded row has a separate "Not recognized" line with
  the identifier in monospace, unaltered, wrapping at commas, copyable; the
  count line includes it under "left out". QA checks its accessibility label by
  the debug script where it can; the owner is not asked to run VoiceOver.
