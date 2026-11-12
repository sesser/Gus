Issue: #62

# Virtual copies: status

Owner: swift-macos-engineer. Branch: `feature/virtual-copies`. State: **Done** (2026-11-11).
Every acceptance criterion (AC1–AC9) is built and tested, and nothing is blocked. R11 (Could)
is built. R10 is deferred at design (D9) and not built. Next: code-reviewer and the designer's
review, then qa-tester.

Spec: [`prd.md`](prd.md) (R1–R11, AC1–AC9, D1–D9, P1), [`design.md`](design.md) (§12, V1–V11).
In the UI and the user guide the command is **Duplicate** and its result a **copy**; "version"
is the catalog's word and appears only in code.

## Results

| | Baseline (`479940f`) | Now |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 724 tests in 118 suites passed, 1 known issue | 753 tests in 119 suites passed, the same 1 known issue |
| `Scripts/build-app.sh all` | not run | both bundles built |

The one warning `swift build --build-tests` prints (`SmartAlbumTests.swift:165`, an unused
result) was there before and is not touched.

New suite: `VirtualCopiesTests` (29 tests, the sort test run for six sorts). One existing test
changed: `LibraryRemovalTests` "R6: removing a photo removes its master and every version of
it" removed the master through its copy; it now removes it through the original, since a copy
removed alone leaves its original (this feature's R6).

No migration. No rendering changed, no cache key changed, and
`PreviewCacheKey.currentPipelineVersion` is not bumped: a copy has the same content hash and,
until it is edited, the same render hash as its original, so it shows the original's cached
preview; once edited it has a key of its own (tested).

## Answers to the PRD's engineer questions

1. **Does the grid query list non-default versions today?** Yes. `libraryItems(matching:)`
   and `itemCount` select from `version` with no `isDefault` filter; `isDefault` was read only
   to find each pair's two halves. Sidebar counts (`projectSummaries`, `versionCount`,
   `albumSummaries`, `keywordSummaries`, `captureMonths`) count versions too. So copies were
   already listed and counted; what was missing was telling them apart. `CatalogItem` now
   carries `versionNumber` and `isCopy` (a version that is not its master's default), read by
   both item queries.
2. **How does Remove from Library find a copy's pair partner?** It did not need to: it took
   the master of any chosen version, and the partner's master through `imagePair`, so
   removing a copy removed the original, the file's pair partner and everything else. That is
   changed. `Catalog.removalPlan` sorts the chosen versions: an original takes its master
   (every version of it, so its copies) and the pair partner's master, as before; a copy
   whose original is not going is deleted alone (`deleteCopies`, never a default version).
   A copy has no pair partner: `ImagePairing.partnerVersionIDs` and the grid's pair
   resolution work on default versions only, which was already so.
3. **An unreadable stack: copied unchanged.** `duplicateVersions` copies the stored
   `editStack` text and its hash without decoding them, so nothing is written over and
   nothing can be lost. The copy is then as uneditable as its original: `setEditStacks`
   refuses to write over a stored stack it cannot read, for the copy as for the original, and
   the Adjust tab shows the same state. Tested with a newer schema and with damaged JSON.
   **The fallback was not needed and is not built**: no photo is skipped for this reason, and
   the string "%lld photos weren't duplicated because their adjustments can't be read." is
   not in the catalog.
4. **Offline photos can be duplicated.** Duplicate reads and writes the catalog only; no
   file is opened. Tested on a catalog whose volume is not mounted.

## What was built

- **PhotoCore** (no AppKit or SwiftUI, all tested):
  - `Catalog/Copies.swift` (new): `duplicateVersions(ids:)` (one transaction: the row with
    its stack and culling values, keyword links and album memberships; no history, no stack
    membership; the next version number of its master), `duplicateVersion(id:)` (moved here
    from `Catalog.swift`; it now copies keywords and albums too), `removeCopies` and
    `restoreCopies` (Undo and Redo: the same version ids and numbers, with keywords, albums
    and edit history), `deleteCopies`. `CopyNaming` is the one place a copy's name is made
    (the words are the caller's; `.plain` is English for `photocli`). `DuplicateTargets`
    (photos only; **`includesVideos` is the one switch for P1**). `DuplicatePlacement` (where
    a new copy goes in the list on screen).
  - `Catalog/LibraryQuery.swift`: `CatalogItem.versionNumber`, `isCopy`, `copyNumber`.
  - `Catalog/LibraryRemoval.swift`: `PhotoRemovalPlan` gains `copyVersionIDs`,
    `originalCount`, `extraCopyCount`; `RemovalResult` gains `copyVersionIDs`.
  - `Browser/RemovalConfirmation.swift`: the sentences for copies (design §7).
  - `Export/`: `TemplateContext.displayName`, which `{name}` and Original Name use;
    `ExportItem.copyName` and `reportName`; `ExportJob.copyNaming`.
  - `Catalog/SmartAlbumRules.swift`: the field `isCopy` (R11).
- **PhotoApp**: `Model/DuplicateActions.swift` (the command, its undo step, its words),
  `Model/PhotoName.swift` (the localized name, used by the grid, VoiceOver labels, the film
  strip's tooltip, the window title, the removal title and Activity rows),
  `LibraryModel.replaceItems` (puts a changed list in place without reading the catalog),
  `LibraryMenuState.canDuplicate`, File ▸ Duplicate (⌘D) in `LibraryCommands`, the context
  menus, the Activity job, the copy mark in `PhotoCell` and `FilmStripCell`, the caption's
  Copy badge, the removal texts, the smart-album rule's titles.
- **Strings**: 17 new keys in `Localizable.xcstrings`, added by hand, each with a comment.
- **Debug script**: `duplicate`, `duplicate fail on|off`, `print copies`
  (`Model/DebugCopyCommands.swift`); `focus <name>` takes a copy's name; `print menustate`
  shows `canDuplicate`.
- **`docs/USER_GUIDE.md`**: a Copies section, ⌘D in the key table, export names, removal,
  History's wording, the smart-album rule, and the Importing paragraph's "Duplicates … are
  skipped" reworded to "Files already in the library … are skipped" (design §11).

### How it works, where the design left it to engineering

- **A copy is a version that is not its master's default version.** Whether a version is a
  copy comes from `isDefault`; which copy it is ("copy 2") from `versionNumber`. The two
  agree as long as nothing makes a copy the default (R10, deferred).
- **Placement is in place, not a reload.** After the write the new items are inserted into
  the list on screen at the index `DuplicatePlacement` gives, which is the index the
  catalog's order gives (tested against `libraryItems(matching:)` for all three sort keys,
  both directions, second copies and a copy of a copy). A reload would drop photos that no
  longer match the filter but stay on screen until it changes, and with them the photo just
  duplicated; design §4.2 relies on that rule. Undo and Redo change the list the same way.
- **The write is on the model's write chain**, after every change made before it. Nothing
  changes on screen until it has landed, and a failure changes nothing.
- **The undo step is registered once the copies are written**, not when ⌘D is pressed, as a
  paste that measures first registers its own. A failed Duplicate therefore leaves no undo
  step. Undo removes the copies and keeps what the catalog held for them; Redo puts the same
  rows back with the same ids, because later undo steps (an edit to the copy) name the copy
  by its version id.
- **Sidecars.** No schema change was needed: the v5 triggers queue only for default
  versions. Inserting a copy, its keyword links, culling it, renaming its keyword and
  deleting it queue nothing (tested).
- **Undo or Redo while another source is on screen** changes the catalog and the sidebar's
  counts, and leaves that source's list and selection alone.

## Acceptance criteria

All tests are in `Tests/PhotoCoreTests/VirtualCopiesTests.swift` unless another file is named.

| | Criterion | Test | Debug-script check |
|---|---|---|---|
| AC1 | One more version with an equal stack; undo removes it, redo restores it | `duplicateAddsAVersionWithAnEqualStack`, `undoRemovesAndRedoRestoresTheSameCopy`, `removeCopiesLeavesOriginals`, `aBatchIsAllOrNothing` | `duplicate`, `print undo` ("Duplicate"), `undo`, `redo`: the copy goes and the same copy returns, selection and focus restored |
| AC2 | Editing the copy leaves the original's stack, render hash and history byte-identical | `editingTheCopyLeavesTheOriginal` (and the reverse), `previewKeysFollowEachStack` | Edit the copy in the loupe: its History has the entry, the original's is empty and its stack the identity |
| AC3 | Rating the copy leaves the original's, and the reverse | `cullingIsPerCopy` | `key 5` on a copy: only the copy's rating changes |
| AC4 | The copy has the original's keywords and albums; then each changes alone | `keywordsAndAlbumsAreSeededThenIndependent`, `copiesAreStackless` | |
| AC5 | Two items for the master, the copy marked; counts include copies; the copy sits next to its original | `theCopyIsAnItemAndIsCounted`, `theCopyIsPlacedAfterItsOriginal` (six sorts), `aCopySortsByItsOwnRating`, `placementEdges` | `print copies`: order, `*`, the subtitle and library count; the grid's and the strip's marks; `snapshot` of the grid |
| AC6 | Removing a copy leaves the original; removing the original takes its copies, and the confirmation names their number | `removingACopyLeavesTheOriginal`, `removingTheOriginalTakesItsCopies`, `removalConfirmationForCopies`, `removingACopyOfAPairsRAW`; `LibraryRemovalTests.everyVersionOfTheMasterGoes` | `removephotos` then `alert`: both texts, read below |
| AC7 | Nothing queued, no `.xmp` written or flagged | `copiesNeverReachASidecar` (real files, a real sidecar, the queue run and the disk check), `renamingACopysKeywordQueuesNothing` | |
| AC8 | Original and copy exported together: two files, each with its own edits | `exportNamesForCopies`, `exportingOriginalAndCopyTogether` (real export, pixels compared), `importTemplatesAreUnchanged` | |
| AC9 | A pair's RAW duplicated: the JPEG untouched, the copy unpaired, ratings not shared | `aPairsCopyIsUnpaired` | Duplicate on a grouped pair: the copy has no `:pair`, and `key 5` on it changes it alone; `pairs separate` lists RAW, copy, JPEG |

Also tested: names (`copyNames`, `namingWordsAreInjected`; V4), videos (`videosAreLeftOut`;
P1), offline (`offlinePhotosCanBeDuplicated`), unreadable stacks
(`anUnreadableStackIsCopiedUnchanged`), the smart-album rule (`smartAlbumRuleForCopies`; V10).
`LocalizationTests` covers the new strings.

Strings composed in the app target (the Activity rows, the announcements, the removal
sentences as words) have no unit test: the test target links PhotoCore only. Their structure
is tested in PhotoCore (`RemovalConfirmation`, `DuplicateTargets`) and their words were read
in the debug-script runs below.

## Debug-script results

Run on a copy of the bundle with the identifier `me.sesser.gus.debugtest`, ad hoc signed, with
`--library-root` on a scratch library from `photobench generate` and `import` (114 files: JPEG,
DNG, HEIC, two RAW+JPEG pairs, one video). Every launch passed `--library-root`.

| Design | Check | Result |
|---|---|---|
| V1 | `menuitems Duplicate` | `File/Duplicate key cmd+"d"`, after a separator, before Show in Finder. Enablement in the menu bar needs a key window (see **For a person**); `print menustate` gives `canDuplicate true` with a photo, `false` with only a video and during a crop |
| V2 | `contextmenu cell 1`, `contextmenu loupe` | Duplicate, Export…, Show in Finder, in that order, after a separator. During a crop Duplicate is left out and Export… stays |
| V3 | `duplicate`, `print copies`, `undo`, `redo` | `IMG_00002`, then `IMG_00002 copy`, selected and focused; undo `Duplicate`; after undo the original is focused and redo is `Duplicate`; after redo the same copy is back and focused. In the loupe the title becomes `IMG_00003 copy`, and undo returns to `IMG_00003.JPG` |
| V4 | `print copies` | Names as designed; the strip's tooltip is `IMG_00002 copy, JPEG` |
| V6 | `snapshot`, `print copies` | The glyph on its dark backing at the copy's top-trailing corner in the grid (22 × 18 pt) and at the picture's top-trailing corner in the strip; no other cell has it |
| V7 | `print copies` in the loupe | Title `IMG_00002 copy`; badge `Copy`; help `A copy of “IMG_00002.JPG”. Its adjustments, rating, flag, label, keywords and albums are its own.` |
| V8 | `selectall`, `duplicate`, `print messages`, `print announcement` | 113 copies of 114 targets; one information row `[Duplicate] 1 video wasn't duplicated.`; `Made 113 copies.`; for one photo `Made a copy of “IMG_00003”.` |
| V8 | `duplicate fail on`, `duplicate` | A warning `The photos couldn't be duplicated. The library is unchanged.` with the error under it; the count is unchanged and no `Duplicate` undo step is left |
| V8 | 20,000 photos (`photobench synthesize`), `selectall`, `duplicate` | 19,999 copies in 2.0 s; Activity showed `Duplicate`, `Duplicating 19,999 photos…`; undo took them all back |
| V9 | `removephotos`, `alert` on a copy | `Remove “IMG_00002 copy” from the library?` / `The original and its file are not affected. The copy's edits are lost, along with its rating, keywords and albums. You can't undo this action.` |
| V9 | the same on its original | `Remove “IMG_00002.JPG” from the library?` / `Its copy is removed with it. The files and their sidecar files stay on disk, …` |
| §4.2 | Filter Unrated, rate a photo 3 (it stays), `duplicate` | The copy appears beside it, rated 3; nothing else leaves the grid |
| §6.3 | `history` on a new copy | Empty state; after an edit one entry; after undo and redo of the Duplicate the copy has its entries again |

In a script, a `duplicate` that fails leaves an undo step with an empty name. That is the
script's own undo group, which it opens around every command that can change photos; the app
registers nothing on a failure.

## For a person (cannot be scripted here)

- File ▸ Duplicate with a real key window: enabled in the grid with a photo selected; dimmed
  with only a video selected, with the sidebar or the search field focused, and during a
  crop; ⌘D from the keyboard. A scripted launch has no key window, so the menu bar's own
  enablement was read from `menustate` only.
- The marks by eye: the grid's and the strip's at small sizes, on a white picture, with
  Increase Contrast, in light and dark; the Copy badge's tooltip.
- The grid when copies are inserted and taken back (it reloads in place and scrolls to the
  focus): that nothing jumps.

## Design questions

Each is built one way so the feature is whole; a different ruling is a small change.

- **DQ-V1. The Changed on Disk source lists copies.** Its scope is by master, so a copy of
  a photo whose sidecar another app changed appears there too, and resolving the change
  does nothing to the copy (D3). Options: (a) leave it, copies count wherever photos do (D6);
  (b) list originals only there (one condition in `whereClause`, and the source's count then
  matches the sidebar badge, which counts masters). Recommendation: (b). Built: (a), unchanged.
- **DQ-V2. The removal title for an original.** §5.2 shows `Remove “IMG_0412” from the
  library?`; the app has shown the file name with its extension since library-ops
  (`Remove “IMG_0412.RW2” …`). Built: originals unchanged, copies by their name without an
  extension. Changing originals is a one-line change but alters library-ops' text.
- **DQ-V3. Right to left.** §6.1 says the grid's corner mirrors "as the offline mark
  should"; the offline mark did not mirror. Built: in the grid both marks follow the layout
  direction (otherwise they would overlap). The film strip's marks are placed by fixed
  corners, as before, and the copy mark there stays at the right. Mirror the strip too?
- **DQ-V4. Sentence order and the singular.** With a pair and copies the message reads pair
  sentence, copies sentence, standard sentence. Several targets with one extra copy read
  "1 copy of these photos is removed with them." (§7 gives only the plural). "Its copy is
  removed with it." is a key of its own, because the catalog's check wants a plural's forms
  to take the same arguments.
- **DQ-V5. Focus when the focused target is a video.** The video is skipped, so there is no
  "copy of the focused photo"; the first new copy takes the focus.
- **DQ-V6. An Undo or Redo of Duplicate from another source** leaves that source's list
  and selection alone (§4.3 assumes the copies are on screen).

## Requirements issues

- **RI-E1. P1 (videos) is still pending the owner.** Built as proposed. Changing the answer
  is `DuplicateTargets.includesVideos`, the `videosAreLeftOut` test and the user guide's
  sentence; the menus, the context menus and the Activity row follow the switch.
- **RI-E2. library-ops R6 is narrowed.** "Removing a photo takes everything the catalog
  holds for it" held for any version of a master; a copy removed alone now leaves its master.
  The library-ops PRD and inventory may want a line.
- **RI-E3. `photocli` and `photobench` (Could).** No `duplicate` command was added to the
  registry, and `photobench` does not make copies. `photocli export` names a copy's file in
  plain English (`IMG_0412 copy.jpg`), having no String Catalog; `query` already printed
  `versionNumber`.
- **RI-E4. R11's rule and stickiness.** In a smart album "Photo is not a copy", a copy made
  there stays on screen until the list is read again, like a photo culled out of a filter.

## README

Nothing changes in requirements, build commands or the repository layout. The README's feature
list and `CLAUDE.md`'s "Scope so far" should gain copies (File ▸ Duplicate), and `CLAUDE.md`'s
debug-script paragraph could name `duplicate` and `print copies` (the owner's section; proposed
only).

## Not done, on purpose

- R10 (name a copy, make a copy the original): deferred at design (D9).
- The unreadable-stack fallback (design §4.4): not needed, see the answers above.
- A `photocli` duplicate command and `photobench` copies (Could).
- No toolbar item, no VoiceOver custom action (design §2.3).

## Proposed issues

- **Name a copy, and make a copy the original** (`enhancement`, slug `copy-name-and-default`):
  the designer's text in design §13.
- **`photocli duplicate`** (`enhancement`): "A registry command that makes a copy of a
  version (`Catalog.duplicateVersions`), refused while the app has the library open, as the
  other write commands are. From virtual-copies (#62), where it was a Could."
