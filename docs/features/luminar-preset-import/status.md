Issue: #203

# Import preset packs (.lnpc): status

Owner: swift-macos-engineer. State: **Done** (2026-11-17). Commits 065dcb6
(PhotoCore and its tests), b57a25a (the page, strings, user guide, AC10 test),
the DQ-1 change after the owner's rulings (concurrent table check), and the
review fixes (see Review findings).
Spec: the PRD (issue #203 body, rev 3, approved) and `design.md` rev 2.
Reference for the mapping and scales: the owner's prototype `lnp2gus`
(outside this repository; read only, nothing copied).

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (branch at 00a016f) | clean | 1072 tests in 161 suites, all pass |
| After b57a25a | clean, no new warnings | 1127 tests in 169 suites, all pass; no golden changed |
| After the DQ-1 change | clean, no new warnings | 1128 tests in 169 suites, all pass; no golden changed |
| After the first review fixes | clean, no new warnings | 1134 tests in 169 suites, all pass; no golden changed |
| After the second-pass fixes (C7, C8) | clean, no new warnings | 1135 tests in 169 suites, all pass; no golden changed |
| After the third-pass fixes (C9, C10) | clean, no new warnings | 1136 tests in 170 suites, all pass; no golden changed |
| Latest (design §13, a table under both statuses) | clean, no new warnings | 1137 tests in 170 suites, all pass; no golden changed; opt-in four-pack suite passes, 40 presets equal to the prototype's |

## What was built

PhotoCore (no AppKit or SwiftUI):

- `Support/ZipArchive.swift`: our own in-memory zip reader (central
  directory; stored and deflate members, deflate through Apple's Compression
  framework, `COMPRESSION_ZLIB`, which is raw deflate; CRC-32 checked; one
  disk, no ZIP64, no encryption; 64 MiB per member, 10,000 members). **No new
  package.**
- `Presets/Luminar/LuminarPack.swift`: reads a pack from memory (a regular
  file only, symbolic links followed, read through a handle capped at
  256 MiB; at most 512 MiB decompressed; members parsed as text, that is
  configurations, templates and `.strings`, at most 4 MiB each, refused from
  the declared size before decompressing; at most 1,000 presets listed or
  found, counted before any row is made), typed
  refusals (`LuminarPack.Failure`), names in the system language when the pack
  has it, English otherwise, presets in the pack's order, a preset that can't
  be read kept in its place as unreadable. `.strings` files are read with
  Foundation's property list parser (`StringsTable`; BOM-less UTF-16 is
  decoded first).
- `LuminarTemplate.swift` (the template model), `LuminarCurves.swift` (point
  lists, Supercontrast and Matte curves, composition sampled at 17 points with
  the app's `MonotoneSpline`), `LuminarMapping.swift` (the converter and the
  named scales), `LuminarTool.swift` (the one identifier table, the report
  types, `PresetControl`).
- `PresetImport`: `.lnpc` in `fileExtensions`; `scan` reads packs into items
  (collection = pack name, never a folder's) and `PackReport`s; `run` counts
  replaced and added presets and tables added per pack, and leaves out a
  table that is not a readable cube (the report says so).

PhotoApp:

- `PresetActions.swift`: pack imports open the preset manager on its Import
  Report page (announced to VoiceOver at medium priority); other imports keep
  the alert; imports run one after another (`presetImportChain`); the panel
  message names `.lnpc`. `PresetText.title(_: LuminarTool)` and
  `title(_: PresetControl)`.
- `PresetReportText.swift`: the page's words; `PresetImportReportPage.swift`:
  the page; `PresetManagerSheet.swift`: pages, **Import Report** button,
  Importing… indicator; `PageHeader` lifted from `private`.
- `DebugScript.swift`: `preset import` prints the report's text for pack
  imports; new `preset report` and `preset reportpage`.
- String Catalog: 30 new report entries, 36 tool names, three format-list
  entries renamed to add `.lnpc`.

No migration, no pipeline bump, no `Info.plist` or file-type change.

## Decisions (engineer's, within the spec)

- **Zip reading:** our own reader plus Apple's Compression framework (PRD
  Dependencies, open question). Nothing added to `Package.swift`.
- **Re-import:** recognized by name, the existing rule of
  `saveAdjustmentPresets`: a preset with the same name in the same collection
  (the pack's name) is replaced in place, keeping its id; anything else is
  added. Tables are recognized by content (SHA-256) and listed once. A
  renamed collection is not recognized (design §4).
- **Tool names through the catalog:** each display name has its own keyed
  entry, `String(localized: "presetPackTool.<case>", defaultValue: …)`, with
  the design's translator comment. Several names would otherwise share an
  entry with the app's own control names ("Color", "Grain", "Vignette",
  "Texture", "Sharpening", "Noise Reduction", "Masks"), and one entry can't
  carry two comments; keyed entries also let the AC10 test match the
  catalog's tool names to the table exactly. What reaches the screen is the
  same.
- **What the table holds** (36 cases): every tool, effect or setting the
  mapping maps, approximates or leaves out by name. Besides R6's list that
  includes settings the prototype reports by name with no control here
  (Smart Tone, Texture, Develop noise reduction, AI noise reduction, Lens
  Correction) and "Layers" (layer opacity, blend modes, several layers: the
  prototype's approximation). See Requirements issue RI-E1.
- **Report granularity:** a tool approximated anywhere in a preset is not also
  listed as mapped, except the look-up table tool (design §13, ruling on QA's
  Q1): its table is carried exactly and its contrast and saturation are
  approximated in other controls, so it is listed, and counted, under both
  (`LuminarMapping.exactAndApproximated`, which holds only it; no other tool
  has an exact part beside an approximated one: Vignette's style stays in its
  own control, Matte, Dramatic and Black and White are approximated
  throughout, Details Enhancer's sharpening is its own Sharpening entry). The
  rest of this point is unchanged: listed as mapped; the same tool can be both mapped and left out (a second
  look-up table). Settings the prototype reports separately inside an
  approximated tool (the Matte look's toning, color a black and white
  conversion keeps, the vignette's feather) are part of that tool's
  approximation, not separate rows. Warmth, Color Balance and Color Toning
  before a black and white conversion are dropped (they would turn gray
  there too) and not reported; the prototype drops the first two the same
  way.
- **A3/A4 as designed:** a preset with nothing carried over imports with no
  groups ("Nothing carried over"); one unreadable preset does not refuse its
  pack. A pack where no preset can be read is refused ("The pack's settings
  can't be read.").
- **Language:** the first of the system's preferred languages, as a language
  code; the pack's `<code>.strings` over its `en.strings`.

## Assumed scales (R10)

Named constants in `LuminarMapping` (and `LuminarCurves.sampleCount`), the
prototype's values; `PresetPackMappingTests.assumedScalesAreTheRecordedOnes`
fails if one changes without the test.

| Constant | Value | Meaning |
|---|---|---|
| `exposureRangeEV` | 2.0 | Exposure ±100 = ±2 EV |
| `colorBalanceFullScale` | 0.2 | Color Balance ±100 = ±0.2 channel offset |
| `warmthFullScale` | 0.1 | Warmth ±100 = red ±0.1, blue ∓0.1 |
| `warmthRangeWeights` | shadows 0.5, midtones 1, highlights 1 | how much of Warmth each range gets |
| `structureToClarity` | 0.75 | Clarity per point of Structure |
| `detailsToClarity` | 1.0 | Clarity per point of mean detail |
| `splitWarmthToSaturation` | 1.0 | Color Mixer saturation per point of warm or cool colors |
| `supercontrastGain` | 0.5 | slope added at a region's pivot at amount 100 |
| `supercontrastPivotTravel` | 0.8 | pivot travel at balance ±100, in half-widths |
| `LuminarCurves.sampleCount` | 17 | points a composed curve is sampled at |

## Acceptance criteria

| AC | Check | State |
|---|---|---|
| AC1 | `PresetPackImportTests.importsPacksBesideOtherFormats` (two packs and a preset file in one import); `PresetImport.fileExtensions` has `lnpc`; `PresetPackTableTests.everyImportExtensionHasAType` (each extension gives a `UTType`, design §1.1, review F1; passes here, no type declared); manual M1 (panel) | Done |
| AC2 | `importsPacksBesideOtherFormats` (order), `namesInTheSystemLanguage` (German), `PresetPackReadingTests.namesFollowTheLanguageWhenThePackHasIt` (French falls back to English) | Done |
| AC3 | `importsPacksBesideOtherFormats`: table installed, listed in the pack-named collection, the applied preset's effective look-up table at intensity 80 | Done |
| AC4 | `PresetPackMappingTests`: every mapped tool, expected values from the prototype run on the same made-up templates; curves at 17 points; two Develops add up; RAW Develop used only alone | Done |
| AC5 | `applyingChangesOnlyTheGroupsItSets` | Done |
| AC6 | `accentAIAndAMaskAreLeftOutAndSetNothing` (statuses, and values equal without those tools); report lines in `PresetPackReportLineTests` | Done |
| AC7 | `importingAgainDuplicatesNothing` (presets, ids, collections, table entries and files) | Done |
| AC8 | `badFilesAreRefusedAndTheRestImport` (truncated → damaged, no config, text file), `refusesWhatIsNotAReadablePack`; no temp files: `packCodeWritesNoFiles` (no write API in the pack and zip code; reading takes `Data`) | Done |
| AC9 | `assumedScalesAreTheRecordedOnes` | Done |
| AC10 | `PresetPackTableTests`: every table case reported by the mapping from a template; R6's tools left out; unknown identifiers verbatim; the catalog's `presetPackTool.` entries are exactly the table's and nothing else has the tool-name comment; no `lnpc` or the format's name in either `Info.plist`; Finder open path takes `PresetFile.fileExtensions` only; no catalog string names the format's application or maker; `LocalizationTests` and `BrandingTests` pass; manual M6 | Done |
| AC11 | full `swift test`: 1137 tests pass, goldens untouched; no migration, no pipeline bump | Done |
| AC12 | the owner, by eye (manual). Opt-in `PresetPackSampleTests.conversionsMatchThePrototype` compares all 40 presets of the four packs with the prototype's own output: all match within rounding | Manual |

Opt-in suite (real packs, never committed):
`LUMINAR_PACKS=<folder> LUMINAR_PROTOTYPE_OUTPUT=<folder of the prototype's preset files> swift test --filter PresetPackSampleTests`.

## Debug-script checks (bundle copy, scratch library)

Bundle from `Scripts/build-app.sh`, copied with `CFBundleIdentifier`
`me.sesser.gus.debugtest`, ad hoc signed; scratch library from
`photobench generate --jpeg 4` and `photobench import`; every launch with
`--library-root`. Pack files: a made-up pack (an unknown tool and an unknown
effect, a mask, Accent AI, Smart Tone, Structure, a table, an unreadable third
preset), a truncated copy of it, a text file named `.lnpc`, and copies of the
owner's four packs (read from copies only).

| Script | Result |
|---|---|
| `preset import MadeUp.lnpc Damaged.lnpc NotAPack.lnpc; preset report` | "1 pack · 2 presets · 1 look-up table added"; Not imported: Damaged ("The file is damaged or incomplete."), NotAPack ("Not a preset pack."); the long preset "2 mapped, 1 approximated, 5 left out" with Mapped: LUT Mapping and Develop; Approximated: Structure (as Clarity); Left out: Smart Tone, Accent AI, and Masks; Not recognized: SomeFutureToolAdjustmentLayer, MIPLAnotherUnknownEffect; "Preset 3: Its settings can't be read." |
| `preset reportpage; preset windowshot` | the page as in design §2.3: Back and title, summary line, Not imported first, pack header with its trailing summary, collapsed rows with count lines, Done at the bottom |
| `preset import MadeUp.lnpc` again | "1 pack · 2 presets" (no tables added), pack "2 presets · 1 look-up table · replaced" |
| the owner's four packs | "4 packs · 40 presets · 36 look-up tables added"; nothing refused, nothing not recognized; the tools per preset read as expected (e.g. Americana: LUT Mapping, Develop, Color, and Grain mapped) |
| the owner's four packs, after design §13 (opt-in suite's totals) | American Dream 27 mapped, 28 approximated, 7 left out; Camping Trip 21, 21, 13; Land of the Rising Sun 21, 17, 6; Wonderful Scandinavia 35, 52, 13. A preset whose table tool sets contrast or saturation now reads one more mapped (Heritage Hues: "3 mapped, 5 approximated", was "2 mapped") |
| `plutil -p` on the bundle's `Info.plist` | no `lnpc` entry; the only type declared is the app's own preset type |

Expanding a row needs a click; the debug script has no command for it
(manual M2, M7).

## Manual checks (for qa.md's "For a person")

From design §11: M1 (the open panel lets `.lnpc` be chosen with no file type
declared), M2 (the page with the four packs: look, truncation, expanding,
Back, Done, Esc, Light, Dark, Increase Contrast), M3 (Import from Adjust ▸
Import Presets… and from the heading opens the manager on the report; Back
shows the collections), M4 (import again: "replaced", nothing doubled), M5 (a
good pack with a damaged file), M6 (double-clicking a `.lnpc` in the Finder
doesn't open the app), M7 (the "Not recognized" line: monospace, unaltered,
wraps at commas, can be selected and copied). AC12: the owner compares
presets with the prototype's output on the same photos (the opt-in suite
already finds every value equal within rounding).

## Known limits

- Two presets with the same name in one pack collapse to one (RI-E3, kept by
  the owner; no suffix). Corrected record (code review C4): the import's
  deduplication (`PresetImport.deduplicated`) keeps the **first** of them, not
  the later, and it compares names **without regard to case** ("Sunset" and
  "sunset" collapse too), while the catalog's own name rule
  (`saveAdjustmentPresets`) is case-sensitive. The pack's report still lists
  both and counts both as imported, so its "N presets" can be one more than
  the presets saved. None in the owner's packs.
- A table two packs share, or one already listed in another look-up table
  collection, is listed once, in the first collection (the existing rule of
  `PresetImport.listNewTables`).
- Two packs with the same name go into one collection; a renamed collection
  is not recognized on re-import.
- ZIP64 and encrypted archives are refused ("Too large to read.", "The file
  is damaged or incomplete.").
- Settings inside an approximated tool that have no equivalent (the Matte
  look's toning, color a black and white conversion keeps, a vignette's
  feather, inner light or offset) are part of that tool's "approximated", not
  named on their own.
- C11 (fourth review, accepted by the coordinator): Remove from Library's
  confirmation goes up only after a catalog read (`askToRemove`), so if ⌘⌫ is
  pressed while a pack import is ending, the import can end inside that read,
  find no modal up and open the preset manager; the removal confirmation then
  comes after it. Rare: the window is one catalog read wide.
- C12 (fourth review, accepted): `LibraryModalTests` is a tripwire on
  `MainView.swift` and `SidebarView.swift` only, and counts `.sheet(`,
  `.confirmationDialog(`, `.alert(` and `.fullScreenCover(`, not
  `.fileImporter`, `.fileExporter` or `.fileMover` (none used on the window
  today). A presenter added elsewhere on the window is not caught.
- Develop's Brightness, which the prototype reports as "other", shows as
  "Not recognized: Brightness".
- Type-check times of the new code (local compiler): no PhotoCore expression
  over 60 ms; SwiftUI bodies 250 to 290 ms, like the existing views.

## Measurements

Owner's four packs (40 presets, 36 tables), release build,
`LUMINAR_PACKS=… swift test -c release --filter PresetPackSampleTests`:

| | Reading and converting | Saving | of which checking and installing the tables |
|---|---|---|---|
| Before (tables checked one at a time) | 0.13 s | 1.89 s | 1.84 s |
| After DQ-1 (b), three runs | 0.13 to 0.14 s | 0.53 to 0.56 s | 0.50 to 0.51 s |

The whole import is now about 0.7 s, under the design's one second (A6), so
it stays in the sheet with Importing… and does not become an Activity job.
Debug builds are slower (before the change: 0.75 s and 5.2 s).

**DQ-1 change.** `PresetFile.installTables` checks the tables (parses each
cube) with `DispatchQueue.concurrentPerform`, each result in its table's
place (`Mutex<[Bool]>`); the tables are then installed one after another in
the file's order, as before. The identifier map, the files written, and
unreadable tables being left out are unchanged, so `.guspreset` imports
behave exactly as before, only faster. The call was never cancellable and
still isn't. Test: `PresetFileTests.installsTablesAsOneAtATimeWould` (16
tables, readable, unreadable and repeated; the same map and files as a
one-at-a-time check, five runs); `embedsTablesAndInstallsThemElsewhere` and
the pack import tests unchanged and passing.

## Review findings (code-review.md, review.md)

| # | Finding | Fix | State |
|---|---|---|---|
| C1 | No limit on how many presets a pack's config lists; quadratic `unlisted` filter; paths sorted per preset | `LuminarPack.maximumPresetCount` (1,000): template folders and listed entries counted before any row is made, refused as "Too large to read."; listed entries looked up in a `Set`, template folders grouped by parent once, paths sorted once, each preset's resources indexed once. Test `refusesAPackListingTooManyPresets` | Fixed |
| C2 | The size check read a symbolic link's own size; a link to a large file or a device was read whole | `LuminarPack.contents(of:limit:)`: the link resolved, a regular file required ("Not a preset pack." otherwise), the size checked, then read through a `FileHandle` capped at the limit + 1. Folder imports (`PresetImport.files(in:)`) list a file only when it, or what its link leads to, is a regular file. Test `readsOnlyRegularFilesWithinTheLimit` (a file over a small limit, a link to it, a folder, a link to a folder, a link to `/dev/zero`, the folder listing) | Fixed |
| C3 | The zip and pack limits had no tests | `refusesWhatIsOverItsLimitsOrUnsupported` (member size, entry count, encryption flag, an unsupported method, by patching the central directory and end record), `refusesAPackOverItsReadBudget` (an internal `readBudget`), the file limit in C2's test. Checked: deleting the member-size guard or the read-budget guard now fails these tests | Fixed |
| C4 | `status.md` said the later duplicate wins; the first does, compared without regard to case | Record corrected (Known limits); the owner's RI-E3 ruling stands, no code change | Fixed (record) |
| C5 | A test used a real pack's name | Renamed to a made-up name ("Valley of Quiet Lakes") | Fixed |
| C6 | An uninstalled table dropped the table tool's approximated row while its contrast and saturation stayed; the pack counted the table | Only the mapped row becomes "left out"; the approximated row stays while its values apply; a pack counts only tables that installed. Test `anUnreadableTableKeepsItsApproximatedValues` | Fixed |
| F1 | No test that every import extension gives a `UTType` | `everyImportExtensionHasAType`; passes on macOS 27.2 here, so no Design question (CI runs it on 26 and 15) | Fixed |
| F2 | The manager could open over another sheet at the end of a pack import | `openPresetSheetWhenFree`: with Export or the look-up table sheet up, the report waits (`presetSheetWaits`) and the manager opens on it from that sheet's `onDismiss`, after it has closed. Debug script `preset sheets` (below) | Fixed |
| Nits | `PageHeader`'s stale comment; no `.help` on an unreadable preset's truncated name | Comment corrected; `.help` added | Fixed |
| C7 (second pass) | F2's guard missed the sidebar's sheet (New Album…, New Smart Album…, Edit Smart Album…, a keyword's Rename…) and its delete confirmation | One rule, `otherSheetIsUp` (Export, look-up tables, `sidebarSheet`, `sidebarDeletion`), used by `openPresetSheetWhenFree` and `sheetDidDismiss`; the sidebar's `.sheet(item:)` has an `onDismiss`, and the delete confirmation (a `confirmationDialog`, which has none) calls `sheetDidDismiss` when it closes (`onChange`). Every `onDismiss` is a closure, `{ model.sheetDidDismiss() }`, not a method reference. Debug-script checks below; the rule lives in PhotoApp, which has no test target, so there is no unit test | Fixed |
| C9, C10 (third pass) | The Remove from Library / Remove Project from Library confirmation (`pendingRemoval`) and the summary alert of imports without a pack (`presetImportSummary`) were outside the guard | Replaced the patched guard with one list: `LibraryModal` (`Model/LibraryModal.swift`) names every sheet, dialog and alert SwiftUI presents on the library window other than the preset manager (Export, look-up tables, the sidebar's sheet, the sidebar's delete confirmation, the removal confirmation, the summary alert), with `LibraryModel.isUp(_:)`, `otherModalIsUp`, `openPresetSheetWhenFree()` and one close hook, `modalDidClose()`. Sheets call it from `onDismiss`; dialogs and alerts through one `onChange(of: model.dialogIsUp)` in `MainView` (the sidebar's own `onChange` is gone). Its comment says a new sheet, dialog or alert on the window goes there; `LibraryModalTests` reads `MainView` and `SidebarView` and fails when they present more than the list holds (plus the preset manager), or when a listed sheet doesn't close through `modalDidClose()`. Not covered: panels and alerts run through `WindowModal` (AppKit), as the reviews note | Fixed |
| C8 (second pass) | Text members capped only by the 64 MiB member limit | `LuminarPack.maximumTextSize` (4 MiB) for configurations, templates and `.strings`, checked from the archive's declared size before reading; tables keep the member limit. Test `refusesTextMembersOverTheTextLimit` (each kind one byte over an internal limit; a table larger than it still reads) | Fixed |

F2 checks (bundle copy, scratch library, `--library-root`):
`selectall; export window; preset summary MadeUp.lnpc; preset sheets` gives
"export true … presets false page report waits true attached 1"; after
`export close`, "export false … presets true page report waits false attached
1", and the snapshot is the Import Report page. The same with `lutwindow
open` / `lutwindow close`. With no other sheet up, the manager opens at once
on the report. Only one sheet is attached at any point. Manual M9 (a real
⇧⌘E in the second after the panel closes) stays for a person.

Every source, the same way (`preset sheets` now prints each `LibraryModal`;
new `preset close removal|summary`): open the source, `preset summary
MadeUp.lnpc`, `preset sheets`, close it, `preset sheets`. For each of Remove
from Library (`project 0; focus 0; removephotos`), Remove Project from Library
(`removeproject`), New Smart Album… (`sheet smart`), New Album… (`sheet
album`), the sidebar's delete confirmation (`smartalbum Stars; sheet
deletesmart`), Export (`selectall; export window`), look-up tables
(`lutwindow open`) and the summary alert (`preset summary Plain.guspreset`,
a plain preset file): while it is up, only it is true, "presets false page
report waits true attached 1"; after it closes, "presets true page report
waits false attached 1". With none up, the manager opens at once. After the
removal confirmation's Cancel the four photos are all still there and the
snapshot is the Import Report page.

## Rulings (owner, 2026-11-17)

- **QA's Q1 (designer, design §13):** a look-up table tool that also sets
  contrast or saturation is listed as Mapped and as Approximated (as Contrast
  and Saturation), counted once under each. Done; C6's unreadable table
  unchanged (its Mapped entry becomes Left out, the Approximated one stays).
  Tests: `lookUpTableContrastAndSaturationAreApproximated` (now
  `["lookUpTable:mapped", "lookUpTable:approximated", "develop:mapped"]`),
  `aTableWithContrastCountsUnderBothStatuses`. No stored value or rendering
  changed.

- **DQ-1:** option (b), check the cubes concurrently in
  `PresetFile.installTables`. Done; see Measurements.
- **DQ-2:** yes to both: tool names as their own keyed catalog entries
  (`presetPackTool.<case>`), and a vignette approximated in its own control
  shown as plain "Vignette".
- **RI-E1:** all 36 table entries are within option (b) of RI-1.
- **RI-E2:** the format's structure keys the mapping reads are fine (never
  shown); AC10 means display-name data.
- **RI-E3:** keep the existing name rule; same names in one pack collapse to
  one (Known limits). No suffix.

No open questions. The proposed follow-up issues (a faster table check,
duplicate names in a pack) are not filed: the first is done here, the second
was ruled out.

## README

- Import Presets… reads `.lnpc` preset packs (requirements).
- New opt-in test environment variables: `LUMINAR_PACKS`,
  `LUMINAR_PROTOTYPE_OUTPUT` (`PresetPackSampleTests`).
