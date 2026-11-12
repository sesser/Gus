Issue: #62

# Virtual copies: design review

Owner: apple-ui-designer. Date: 2026-11-11. Branch: `feature/virtual-copies`
at `c82e88f`, read against `develop`. I read the code and didn't build it.
The engineer's debug-script results in `status.md` are taken as reported.

## Verdict

**Pass with two fixes.** What's built matches `design.md` §1–§11 closely:
placement, key, enablement, naming, marks, caption badge, undo, feedback and
removal text all match. One gap comes from ruling D-V1: a copy still shows its
original's sidecar change in the Changed on Disk source and in the inspector.
The user guide also needs two small wording fixes. Neither fix changes the
design's structure.

## Rulings on the design questions

They are recorded in `design.md` §15. §5.2 is corrected for D-V2.

| DQ | Ruling | Engineer must change |
|---|---|---|
| DQ-V1 | **D-V1: option (b), and the same rule in the inspector.** The Changed on Disk source lists default versions only. The inspector's Changed on Disk section is computed from the default versions among the targets only | Yes, see F1 |
| DQ-V2 | **D-V2: as built.** An original keeps `Remove “IMG_0412.RW2” …` (library-ops), and a copy uses its name without an extension. Design §5.2 was wrong and is corrected | No |
| DQ-V3 | **D-V3: as built.** The grid's marks follow the layout direction. The film strip keeps fixed corners | No |
| DQ-V4 | **D-V4: as built.** Order is pair, then copies, then standard. The singular "1 copy of these photos is removed with them." and the separate "Its copy is removed with it." key are both right | No |
| DQ-V5 | **D-V5: as built.** The first new copy takes the focus | No |
| DQ-V6 | **D-V6: as built.** Undo and Redo don't switch sources | No |

## Design requirements

| # | Requirement | Result | Notes |
|---|---|---|---|
| V1 | File ▸ Duplicate ⌘D, first of the photo-file group, no ellipsis, `canByKey` + photo targets + not cropping | Pass (code); menu-bar enablement **needs manual check** (M1) | `LibraryCommands.swift` order is Duplicate, Show in Finder, Export…, Remove from Library…, matching §2.1. `canDuplicateTargets` also excludes a running removal and a running Duplicate, which is right |
| V2 | Context menus: grid and loupe, Duplicate first in the Export group; left out (not dimmed) for videos; none on the strip or sidebar | Pass | The video loupe shares `addPhotoItems`, and `canDuplicate` is false for a video target, so the item is left out. During a crop it is left out too |
| V3 | Placement after the master's items, selection and focus, loupe follows, one undo step "Duplicate", undo and redo restore selection | Pass; "nothing jumps" **needs manual check** (M4) | `DuplicatePlacement` inserts in place rather than reloading, which keeps the stays-visible-until-the-filter-changes rule. The undo step is registered only after the write, so a failure leaves no step |
| V4 | Display name from one function, used everywhere a photo is named | Pass | `PhotoName.display` / `inFull` serve the grid name row, VoiceOver labels, film strip tooltip, window title, removal title and Activity rows (`AdjustmentActions`, export `reportName`). The Info tab still shows the master's file name (§5.2) |
| V5 | Export names: Original Name and `{name}` give "‹name› copy", other tokens unchanged, import templates untouched | Pass | `TemplateContext.displayName`, with `copyNaming` taken from `PhotoName.naming` so the suffix is localized |
| V6 | Grid mark: `square.on.square`, white on the offline backing, top-trailing, every size, full opacity on rejects. Strip mark at top-trailing of the fitted picture | Pass (code, snapshot); legibility **needs manual check** (M2) | Reuses `markBacking`, `markCornerRadius`, `markSize` and `filmStripMarkBacking`, so no new palette role |
| V7 | Caption badge "Copy" after the ML badge and before Offline, with the master's file name in the tooltip; window title is the display name | Pass; tooltip on screen **needs manual check** (M3) | `LoupeView.swift` ~1399. It shows in review too |
| V8 | Activity: skipped videos (information), long batch (no Stop), failure (warning), with VoiceOver announcements | Pass | Plural variations exist for every counted string. The unreadable-stack fallback isn't needed (the stack is copied unchanged), and its string is rightly absent |
| V9 | Removal text for one copy, several copies, an original with extra copies, several originals, mixed, and a copy of a pair's RAW | Pass | `RemovalConfirmation.photos` follows §7. The pair sentence counts originals' files only |
| V10 | "Photo is a copy / is not a copy", flag kind, listed last | Pass | It reuses the "Photo" key, with a comment covering both the menu and the rule field. Acceptable |
| V11 | `docs/USER_GUIDE.md` terms (§11) | **Fail (minor)**, see F2 | The Copies section, ⌘D row, export sentence, removal, History wording and the Importing rewording are all present. "Virtual copy" never appears, and "version" appears only in its pre-existing meanings (app version, decoder version, `photocli`) |
| §4.4 | Unreadable stack copied unchanged, copy as uneditable as its original | Pass | Matches the design's preferred branch |
| §6.3 | History panel: a new copy shows the empty state | Pass | As reported in `status.md` |
| D-V1 | Changed on Disk excludes copies (source and inspector) | **Fail**, see F1 | New ruling at this review |

Acceptance criteria AC1–AC9 are mapped to tests in `status.md`. As far as
the UI goes, I find nothing that contradicts them. AC5's "copy marked" is
V6/V7, and its counts wording is the subtitle and sidebar (RI-V3).

## Fixes for the engineer

- **F1 (D-V1).** Copies don't take part in sidecar review.
  - `LibraryQuery` `.changedOnDisk`: add `version.isDefault` to the clause,
    so the source lists originals (and their pair partners' default
    versions) only.
  - `Catalog.diskChanges(forVersions:)` (`SidecarState.swift`): map only
    default versions to images, so selecting a copy alone shows no Changed
    on Disk section in the inspector. If the selection includes the original,
    the section still shows.
  - Add a test for each: a master with a changed sidecar and one copy, where
    the source lists one item and `diskChanges(forVersions: [copy])` is
    empty.
- **F2 (user guide).**
  - Film strip paragraph: "a mark for videos and offline photos" becomes "a
    mark for videos, offline photos and copies".
  - Copies section: "two overlapping squares at the top corner of its
    picture" becomes "…at the top-right corner of its picture". "Top
    corner" doesn't say which; the offline mark sits at the other one.

When F1 is done, `status.md` should say so. I'll confirm both fixes here.

## Manual checks (for a person at the bundled app)

- **M1.** With the library window key: File ▸ Duplicate is enabled with a
  photo selected in the grid, and in the loupe. It is dimmed with only a
  video selected, with the sidebar focused, with the search field focused,
  and while a crop is being edited. ⌘D from the keyboard makes the copy.
- **M2.** The copy mark by eye, in the grid at the smallest and largest
  thumbnail sizes and in the film strip at its smallest size. Check it on a
  mostly white photo and on a rejected (dimmed) photo, with Increase
  Contrast on and off. The mark must read as a mark and not be lost against
  the picture. The offline mark at the opposite corner (an offline copy)
  must not crowd it.
- **M3.** In the loupe on a copy, hovering the **Copy** caption badge shows
  "A copy of “‹file name›”. Its adjustments, rating, flag, label, keywords
  and albums are its own." It stays clear of the HDR, Offline and film strip
  controls at a narrow window width.
- **M4.** Duplicate a photo in the middle of a long, scrolled grid, then
  undo and redo. The copy appears right after its original, selected and
  scrolled into view, and nothing else in the grid jumps. Undo and redo put
  the selection back without a visible reload flash.
- **M5.** Right-click a photo in the grid and in the loupe: Duplicate is the
  first item of the Export… / Show in Finder group. Right-click a video in
  the video loupe: there is no Duplicate.
- **M6.** After F1: select a copy of a photo whose sidecar another app
  changed. The inspector shows no Changed on Disk section, and the Changed
  on Disk source lists only the original.

## What's working

- The vocabulary is held everywhere: **Duplicate** for the command and
  **copy** for the result, and "virtual copy" appears nowhere in the UI,
  strings or guide.
- Names come from one function (`PhotoName`), with localized suffixes shared
  by the UI and export. Keep it that way; R10's typed names plug in there.
- The undo design is careful: the step is registered after the write, Redo
  keeps the same version ids (so later undo steps still find the copy), and
  a failed Duplicate leaves nothing behind.
- Placement inserts in place rather than reloading, which keeps the culling
  rule that photos stay visible until the filter changes.
- The grid's marks now mirror for right to left, which also fixes the
  offline mark.
