Issue: #179

# About window with a dedication: status

Owner: swift-macos-engineer. Branch: `feature/about-gus`. State: **Done** (2026-11-13).
Every acceptance criterion that can be met before #172 is built and tested; AC7's and AC13's
full-text halves are built and checked against a bundle with the files copied in by hand, and
turn on by themselves when #172 puts the files in the bundles. Nothing is blocked. The findings
of the code review (C1–C7, Q3) and the design review (F1–F4) are fixed (**Review findings**).

Spec: the PRD (issue #179's body, R1–R11, AC1–AC13) and [`design.md`](design.md) (§1–§13,
rulings D-A1 to D-A8).
Next: code-reviewer and the designer confirm C6, C7 and F4, then qa-tester.

## Results

| | Baseline (`3b8819e`) | Now |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 906 tests in 133 suites passed, 1 known issue | 952 tests in 138 suites passed, the same 1 known issue |
| `Scripts/build-app.sh all` | not run | both bundles built |

`swift build --build-tests` prints two warnings that were there before and are not touched
(`SmartAlbumTests.swift:165`, `VirtualCopiesTests.swift:170`).

No migration, no rendering change, no pipeline bump, no new dependency. `Scripts/build-app.sh`
is not changed: putting the license files in the bundles is #172's.

## Tests

`swift test`: 952 tests in 138 suites passed, with the 1 known issue the baseline has (43 new tests
in 5 new suites, and three more in `QuitConfirmationTests`). Before the review fixes: 945; after
the first pass: 949. The last run took 299 s instead of about 50: see **Seen while testing**.

New suites (all in `Tests/PhotoCoreTests`):

| Suite | File | What it holds |
|---|---|---|
| About window | `AboutTests.swift` | The record (five projects, order, relationships, licenses, pages), the version line's rules, the notices file's sections by byte range, what a bundle can show case by case (design §5) |
| Acknowledgements agree with the notices, the README and the package | `AcknowledgementConsistencyTests.swift` | R9 on the real files, and each way of drifting apart, with the project named in the failure; the copyright line and the free-software statement against the README |
| No license text in Swift sources or the String Catalog | `AcknowledgementConsistencyTests.swift` | AC13's "never typed in" |
| About wording | `AboutWiringTests.swift` | The five sentences and four license names are the approved ones and are in the catalog; AC4's wording by relationship |
| About menu wiring | `AboutWiringTests.swift` | Both apps add the commands and scenes under their own names; the item replaces `.appInfo` and `.help`; nothing uses the system panel |

`LocalizationTests` and `BrandingTests` pass with the 19 new catalog keys and the new sources.

## Acceptance criteria

"Script" is a debug-script check I ran on this Mac (macOS 27.2, built with the macOS 27.2 SDK)
against copies of both bundles with their own bundle identifiers and a scratch `--library-root`.
The commands are under **Debug script**.

| AC | State | Test or check |
|---|---|---|
| AC1 Help lists About ‹name›; one window; a second use doesn't open another | Done | Script: `about menus` (Help has "About Gus", enabled, no key equivalent), `about open help` then `about open app` then `about windows` → 1 window, title "About Gus". `AboutWiringTests` (a `Window` scene, both items open it by id) |
| AC2 The name comes from `AppBranding` only | Done | `BrandingTests` (no literal in Swift or the catalog), `AboutWordingTests.namesAreArguments`. Changing `displayName` itself was not tried |
| AC3 The dedication and exactly the five entries | Done | `AboutTests.recordListsTheFiveProjects`, `AboutWordingTests`; script: `about print` lists the five with sentence, license, address |
| AC4 Wording by relationship | Done | `AboutWordingTests.wordingFollowsTheRelationship` and `sentencesAreTheApprovedOnes` |
| AC5 Version line from the bundle; absent with no bundle | Done | `AboutTests` (version rules, the plist templates); script: bundle → "Version 0.1.0 (build 1)"; `.build/debug/PhotoApp` (no bundle) → `version none`, and the window's maximum height is 21 pt less (no gap kept) |
| AC6 A link opens the project's page; the window needs no network | Done | Script: `about link <project>` and `about click` on the real link both print `about link would open https://www.libraw.org` (the window's own open-URL action; under a script it reports instead of opening). The app has no network code in this feature; a run with the network off was **not** made (manual check M3) |
| AC7 License text of LibRaw, LightCraft and GRDB, byte for byte; none before #172 | Done for what this feature owns | `AboutTests.repositoryFilesAreShownByteForByte`, `noFilesNoControls`; script, bundle as built today: every entry `View License none`; bundle with the two files copied in: three buttons, and each license window's text has the SHA-256 of its section of the file (computed separately with Python). That #172's build puts the files there is #172's test |
| AC8 The importer has the same item and window | Done | Script on the importer copy: `about menus`, `about open help`, `about print` (header "Gus Importer", same five entries, dedication and statement with the project's name) |
| AC9 Both items open the one window; no system panel | Done | Script, both apps: `about open help; about open app; about windows` → 1; `about menus` → "an item opens the system About panel false". `AboutWiringTests.systemPanelIsNotUsed` |
| AC10 Each kind of drift fails with the project's name | Done | `AcknowledgementConsistencyTests`: an entry removed (each of the five), a package added, vendored source added, a project added to the notices or the Credits, one dropped from either |
| AC11 `swift test` passes with the real files | Done, with a fix to the files | `repositoryIsConsistent`. It failed on the files as #169 left them (GRDB and ExifTool had no notices section, ExifTool no Credits line); see **Changes to the notices and the README** |
| AC12 Keyboard: every control reachable; ⌘W closes | Done; Tab order is a person's check | Script (app active, keys through the event queue): ⌘W closes About and a license window; Esc closes About and not a license window; ⌘F shows a license window's find bar and Esc closes the bar. Tab with Keyboard Navigation on: manual check M2 |
| AC13 Copyright and GPL statement; full text from the bundle's `LICENSE`; none typed in | Done for what this feature owns | `copyrightMatchesTheReadme`, `statementMatchesTheReadme`, `LicenseTextTests`; script: the footer line and statement, `View License none` before the files are there; with them, the app's license window shows 35149 bytes with the SHA-256 of the repository's `LICENSE`. That the bundle's file is the repository's is #172's test |

### For a person (I can't see the UI)

- **M1 Look.** The About window in light, dark and Increase Contrast (this Mac is in dark;
  light was not seen): header centered and clear of the window buttons, the divider under it,
  entries leading-aligned with the address at the trailing edge, the footer in secondary
  text, small bordered **View License** buttons. License windows: monospaced text, 16 pt
  inset, the title shown.
- **M2 Keyboard Navigation.** With it on in System Settings, Tab goes link, then View License,
  entry by entry, then the footer's button; Space activates. Nothing has a focus ring when
  the window opens; Return does nothing.
- **M3 No network.** With the network off, the window opens and shows everything.
- **M4 A real click on a link** opens the default browser at the project's page (scripts
  never start a browser).
- **M5 Resizing.** The window drags taller up to its content and no wider; the zoom button
  is dimmed; dragging the window by its background moves it.
- **M6 The app menu and Help in the menu bar** by eye: About first and alone above a
  separator in the app menu; the search field above About in Help.
- **M7 VoiceOver, Voice Control**, macOS 15 and macOS 26 are not checked by anyone (the README
  says so).
- **M8 Quit while a job runs, from the About window.** Start an export (or an import), open
  About so it is key, press ⌘Q: the library window comes in front of About and the question
  is a sheet on it; Return and Esc keep the job going. Again with a sheet already up on the
  library window (the look-up table browser): the question is on that sheet, at once. Not
  checked by anyone: the library window on another Space or in full screen.
- **M9 ⌘F on a non-Latin layout.** With a Russian or Greek input source, ⌘F in a license window
  opens its find bar.

## Debug script

`about …` in both apps' debug scripts (`Sources/PhotoUI/About/AboutDebugCommands.swift`); none
needs a key window except `click` and `escape posted` (`quithost` says more with the app active):

```
about open [app|help]     about close     about escape [posted]     about menus
about print               about windows   about link <project>      about snapshot <file.png>
about license <project>|app [print|close|find|snapshot <file.png>]
about click <x> <y>       about height <points>|max        about closeothers
about quithost            about quitask [keep]
```

`about print` gives the window (title, size and limits, buttons, Window menu, first
responder, appearance), then what it shows from the same values the view draws: header,
version line or `none`, dedication, each entry (name, sentence, license, address, page,
View License or `none`), the footer, and every open license window. `about license … print`
reads the text back from the text view on screen: bytes, SHA-256, font, find bar.

What I ran, and what came back:

| Check | Result |
|---|---|
| Library copy as built (no license files) | Version line; five entries; every `View License none`; footer statement, `View License none`; window 520×640, min 520×400, max 520×691; minimize off, zoom off, full screen not allowed, not restorable, not in the Window menu, first responder the window (nothing focused) |
| The same with `THIRD_PARTY_NOTICES.md` and `LICENSE` copied into `Contents/Resources` | View License on LibRaw, LightCraft, GRDB and the footer, none on darktable and ExifTool; max height 734; four license windows with the files' hashes; the same license asked twice → one window; license windows are in the Window menu, About is not; closing About leaves them open |
| Files removed while About is open | View License opens the window in its "Can't Show the License" state, no alert; reopening About shows no buttons (decided at each opening) |
| App active (`open -W -n … --args --library-root …`) | A click on `libraw.org` runs the link (reported, not opened); a click on LibRaw's View License opens "LibRaw License"; a posted Esc closes About; ⌘W closes About and a license window; ⌘F opens the find bar, Esc closes the bar and not the window |
| A sheet up on the library window (`lutwindow open`) | Both About items enabled; About opens |
| `.build/debug/PhotoApp` (no bundle) | `version none`, no buttons, the statement still there |
| Importer copy | Menus, one window, header "Gus Importer", dedication "Gus stands on…", "Gus License" |
| File ▸ New Window | Not added by the license window group (`menuitems New` lists only the album items) |
| The app's own window closed, a license window open (design §2.2; code review Q2), both apps | `about closeothers` leaves only license windows; both About items are enabled; `about open help` opens About (1 window), and after closing it `about open app` opens it again |
| All four View License buttons alike (F1) | `about height max` then `about snapshot`: the footer's button has the entries' font and title color in the picture (dark). By eye in light: M1 |
| The window a quit confirmation goes on (code review Q3), app active | `about quithost`: “All Photos” while the library window is key, while About is key and while a license window is key; none (the alert stands alone) when only license windows are left. Importer: “Gus Importer” with About open. A real ⌘Q during an export with About key was **not** run (M8) |
| The same with a sheet up on the library window (C6) | `lutwindow open; about open app; about quithost` → "a sheet on “All Photos”". `about quitask` (the real `QuitGuard.ask`, nothing running, nothing quitting): "question on screen true, sheets on it 0 → 1", so it is shown on the sheet and not kept waiting behind it; `about quitask keep` answers it |
| The host comes in front of About (F4) | Front to back before `about quitask`: About, All Photos; after: All Photos, About (the question's glass window above both). The same in the importer copy. In these three runs macOS refused to make the test copy the active app, so "the host becomes key" was not seen by the script: M8 |
| ⌘F after C4 | Posted ⌘F in a key license window: find bar shown; Esc: bar closed, window stays. A non-Latin input source was not tried (M9) |

To see the state after #172 before it lands, copy the two files into a test copy of the bundle
and sign it again:

```
cp THIRD_PARTY_NOTICES.md LICENSE "<copy>.app/Contents/Resources/"
```

```
codesign --force --sign - --timestamp=none "<copy>.app"
```

## What was built

- **PhotoCore** (`Sources/PhotoCore/About/`, no AppKit or SwiftUI, all tested):
  - `Acknowledgements.swift`: `Acknowledgements.all`, **the one record** (project, name, page,
    relationship, license, whether its license needs a notice, its package URL or vendored
    folder), and `AppCopyright` (year, holder).
  - `BundledLicenses.swift`: `NoticesFile` (second-level sections as byte ranges, fenced
    blocks skipped, a heading matched by a project's whole name), `BundledLicenses` (reads
    `THIRD_PARTY_NOTICES.md` and `LICENSE` from a folder, every time), `LicenseDocument`.
  - `AboutContent.swift`: `AppVersion` (both plist values or nothing), `AboutContent` (what
    one bundle gives the window: design §5's table).
- **PhotoUI** (`Sources/PhotoUI/About/`):
  - `AboutView.swift`: `AboutScenes` (the `Window` and the license `WindowGroup`),
    `AboutCommands` (`.appInfo` and `.help`), the view.
  - `LicenseView.swift`: the license window; `LicenseTextView` (`NSTextView`, find bar).
  - `AboutText.swift`: the words, one per case of the record's enums (exhaustive switches: a
    project added to the record doesn't compile until it has a sentence).
  - `AboutWindows.swift`: metrics, `AboutWindowRegistry` (which `NSWindow`s these are; Esc;
    Window menu; zoom), `AboutLinks`.
  - `AboutDebugCommands.swift`.
  - `Resources/Localizable.xcstrings`: 19 keys (design §8), added by hand.
- **Both apps**: `AboutCommands(appName:)` in place of the emptied Help group, `AboutScenes(appName:)`
  after the main window; `about` in both debug scripts, whose own window lookups now skip the
  About and license windows.
- `docs/USER_GUIDE.md`: an **About** paragraph.

State: none. The window holds no model; `AboutContent` is a value computed when the window
appears. `AboutWindowRegistry` holds weak references to the windows and is the only shared
mutable state, on the main actor.

## Changes to the notices and the README (a consistency fix, outside this feature's own files)

R9 (a) asks that every project in the record be in `THIRD_PARTY_NOTICES.md` and in the README's
Credits, and AC11 that the test pass on the real files. After #169 they named LibRaw, darktable
and LightCraft (notices) and LibRaw, darktable, LightCraft and GRDB (Credits). Added, in a commit
of its own:

- `THIRD_PARTY_NOTICES.md`: **`## GRDB`** (what it is, how it is used, and upstream's MIT
  `LICENSE` copied byte for byte from the pinned 7.11.1 checkout: PRD A2 confirmed against the
  repository) and **`## ExifTool`** (not included, run when installed, "the same terms as Perl
  itself" as exiftool.org states; no license text, since nothing of it is distributed).
- `README.md` Credits: one line, "**ExifTool** reads metadata when it is installed; it is not
  part of Gus."

After the code review (C3) the GRDB section also carries, in commit "Notices: GRDB's second
MIT notice and its Swift.org-derived files":

- the **second MIT notice** GRDB has in `GRDB/Utils/Inflections+English.swift` ("Copyright (c)
  2005-2019 David Heinemeier Hansson"), copied from that file's header with the comment marks
  taken off;
- a **note naming the three files** whose headers say parts come from the Swift.org project
  under the Apache License v2.0 with Runtime Library Exception (`GRDB/Core/Cursor.swift`, and
  one function each in `GRDB/Record/EncodableRecord.swift` and `FetchableRecord.swift`), with
  the address those headers give. The Apache license's text is **not** reproduced, and the note
  says so.

**Open for Ship (owner, product manager; #172 owns the content), RI-E2:** the wording of the GRDB
and ExifTool sections, and whether naming the Swift.org-derived files with a link is enough or
the Apache 2.0 text should travel with the apps. The code reviewer's second pass notes that
the Runtime Library Exception, as written, is about the Swift runtime embedded by compiling,
not about source copied into GRDB's files, so the question is a real one. I am not a lawyer and did not decide that; I
only made the section say what GRDB's sources say. GRDB's View License window shows the whole
section, so whatever is settled there is what the window shows.

The README is the product manager's and the notices' content is #172's: both should read these
lines and reword them if they want (RI-E2).

## Answers to the design's questions (§10)

- **Q-E1 (APIs).** All exist at the macOS 15 minimum; checked in the macOS 27.2 SDK's SwiftUI
  interface and by building with a 15.0 deployment target. `toolbar(removing:)` 14,
  `windowBackgroundDragBehavior`, `windowMinimizeBehavior`, `windowFullScreenBehavior`,
  `restorationBehavior`, `defaultLaunchBehavior` 15, `commandsRemoved`, `defaultPosition`,
  `windowResizability`, `WindowGroup(id:for:)` 13. `toolbarBackground(.hidden, for:)` is
  soft-deprecated; I used its macOS 15 name, `toolbarBackgroundVisibility(_:for:)`.
  `openWindow(id:value:)` for a value whose window is open brings that window forward
  (checked). Two things SwiftUI has no modifier for are set on the `NSWindow`: the zoom
  button off, and the Window menu (Q-E4).
- **Q-E2 (copyright).** `AppCopyright.year` and `.holder` in
  `Sources/PhotoCore/About/Acknowledgements.swift`. `copyrightMatchesTheReadme` fails when the
  README's License section says otherwise, and `statementMatchesTheReadme` does the same for
  the free-software paragraph. Not `AppBranding`: the holder is a person, not the product
  name, and a rename doesn't change it. The Info.plists still have no
  `NSHumanReadableCopyright` (proposed follow-up).
- **Q-E3 (Esc).** A local key-down monitor, installed the first time the About window appears
  (`AboutWindowRegistry.closesAbout`): an unmodified Esc whose event is for the About window,
  with no sheet on it, runs the window's `performClose`. Nothing is added to the view or the
  accessibility tree, and it doesn't depend on what has the keyboard. Checked with the key
  posted through the event queue.
- **Q-E4 (Window menu).** Yes: `isExcludedFromWindowsMenu`. Checked: About is not listed,
  license windows are.
- **Q-E5 (Find).** Yes. `LicenseTextView` answers ⌘F, ⌘G and ⇧⌘G in `performKeyEquivalent`,
  which the key window's views get before the menu bar, so no Edit ▸ Find item is needed and
  the library window's ⌘F (off while another window is key) is never reached. Checked with
  posted keys. One thing found: the find bar lies over the top of the text in the current
  design, so opening it at the start of the text hid the first line; the view now stays at
  the start.
- **Q-E6 (scroll view).** A SwiftUI `ScrollView` is kept, by the owner's ruling (**Rulings**,
  Q1). On macOS 27.2 clicks posted through the event queue reached the link and the View
  License button inside it. macOS 26 and 15 were not checked.

## Where I read the design one way (all accepted at design review: design.md §13, D-A1 to D-A6)

- **D-1 Heights are the window's.** "Minimum 400, ideal 640" is applied to the window with its
  title bar (the view lies under the title bar, so the view's own limits are 32 pt less on
  this macOS). Maximum: the content's height, 691 pt in English without license buttons, 734
  with them.
- **D-2 Lines of an entry are 3 pt apart** (`AboutMetrics.entryLineSpacing`); the design gives
  the space between entries and around the lists, not within an entry.
- **D-3 Header top.** The header starts 4 pt under the title bar, which puts the icon's
  canvas 36 pt from the window's top on this macOS (the design says "about 28 pt").
- **D-4 "Can't Show the License" has no symbol.** The design names none, so it is a
  title-styled label with no icon above the description.
- **D-5 Catalog keys.** `Version %@ (build %@)` and `Copyright © %@ %@` are the keys, with the
  positional `%1$@ … %2$@` in their English values (as the catalog's other two-argument
  strings are): `String(localized:)` builds its key with plain `%@`, so a key written with
  positions would never be found. The English text is the design's.
- **D-6 The app's license window is titled with the project's name in the importer too**
  ("Gus License"), and its missing-file sentence names the running app, as §6.1 and §8 say.

## Rulings

- **RI-A1 (owner, 2026-11-13, relayed by the main session).** In the standalone importer the
  dedication and the free-software statement name the project (`AppBranding.displayName`),
  as the design assumed (A-1). Menu items, the window's title and the header keep the
  importer's own name. Built so: `AboutScenes(appName:projectName:)`, where `projectName`
  defaults to `AppBranding.displayName` and neither app passes it
  (`AboutWiringTests.projectNameIsTheLibraryApps`). Nothing is pending on it.
- **Q1 of the code review (owner, 2026-11-13, relayed by the main session).** `CLAUDE.md`'s "No
  SwiftUI `ScrollView` under the toolbar" does not cover the About window. Its body stays a
  SwiftUI `ScrollView`; `AppKitScrollView` stays in the library app.
- **Design rulings D-A1 to D-A8** are in [`design.md`](design.md) §13: D-A1 to D-A6 accept the
  six readings below as built; D-A7 (Voice Control names) and D-A8 (catalog comments) are
  findings F2 and F3.

## Review findings

From [`code-review.md`](code-review.md) and [`review.md`](review.md), both of 2026-11-13.

| # | Finding | What was done |
|---|---|---|
| F1 | The footer's View License took the footer's callout font and secondary color | `.font(.callout)` and `.foregroundStyle(.secondary)` are on the two footer texts, not on their stack. The four buttons are now one view, `ViewLicenseButton`, so they can't differ again. Snapshot at full height: alike |
| F2 (D-A7) | Voice Control names | `accessibilityInputLabels` on all four: "View License", then "View ‹owner› License". The VoiceOver label is unchanged. Not checked with Voice Control (M7) |
| F3 (D-A8) | Translator comments named the app, not the project | The dedication's and the statement's comments, in `AboutText.swift` and the catalog, say the argument is the project's name (the library app's name, also in the standalone importer) |
| C1 | The R9 test saw only `.package(url:)` and `.package(path:)` | `AcknowledgementConsistency.dependencies(in:)` reads every `.package(…)` (url, path, registry id, with or without `name:`, wrapped over lines) and every `.binaryTarget(…)`, with comments taken out by a scanner that leaves strings whole; a call it can't read is reported with its own text. `everyFormOfDependencyIsNamed` (seven forms), `commentsAreStripped` |
| C2 | A Credits line with no bold name wasn't read as a credit | Every list item of the Credits section must open with a name in bold, or the test fails quoting the item. Tested with five shapes of such a line |
| C3 | GRDB's section lacked its second MIT notice and said nothing of its Swift.org-derived files | Added (see **Changes to the notices and the README**); wording to confirm at Ship |
| C4 | Find keys matched on `charactersIgnoringModifiers` | `LicenseTextView` matches `event.characters`, as menu key equivalents do. ⌘F and Esc checked again with posted keys; a non-Latin layout not tried (M9) |
| C5 | The statement test compared the README with a copy typed into the test | `statementMatchesTheReadme` reads the literal `AboutText.freeSoftwareStatement` passes to `String(localized:)` from its source and compares that with the README and the catalog; `copyrightLineMatchesTheReadme` does the same for the copyright line |
| Q2 | "The library window closed, a license window open" was not in my checks | Run in both apps (**Debug script**): About opens from both menus |
| Q3 | ⌘Q during a job put the confirmation on the About window when it was key | The library app asks on `QuitGuard.confirmationWindow`: the key window, else the main one, else a visible one, never the About or a license window (`QuitConfirmation.host` in PhotoCore, tested in `QuitConfirmationTests`); with only such windows left the alert stands alone. The importer already asked on its import window (`CardImportModel.window`), so it needed no change. `about quithost` shows the choice; a real quit during a job is M8 |
| C6 (second pass) | With About or a license window key and a sheet already up on the library window, the question was asked on the window and AppKit kept it waiting behind the sheet: ⌘Q seemed to do nothing | The host is the window's front-most sheet when it shows one (`QuitConfirmation.frontSheet`, used by `host`; a sheet on a sheet is followed). `QuitGuard.ask` applies the same to whatever window it is given, so the importer, which asks on its import window, can't queue a question behind a sheet either: that case was there before this feature, and falls to the same line. `QuitConfirmationTests`: `confirmationGoesOnTheSheetOfAWindowThatShowsOne`, `frontSheetFollowsTheChainAndStops`. `about quithost` names a sheet as "a sheet on ‹window›"; `about quitask` shows the real question and says whether it is on screen |
| F4 (second pass) | The host may be behind About, where the sheet comes down | **Kept the explicit call**: `QuitGuard.ask` calls `bringForward` before the sheet, which does `makeKeyAndOrderFront` on the host (for a sheet, on the window it is on) when the host is not the key window, and nothing when it is. It is in `ask`, so the importer gets it too. The code reviewer's probe says AppKit already fronts a sheet's window; the call then changes nothing, and it also makes the host key and covers a system that doesn't. I can't tell the two apart from the script: the order was right after asking (above) |
| C7 (second pass) | The mutation tests leaned on GRDB's exact version line and on Credits being the README's last section | They insert through `addingDependency` (after `dependencies: [`) and `addingCreditsLine` (at the end of the Credits section, wherever it is). `mutationsUseStableAnchors` runs both on a manifest with another version and a README with a section after the Credits |
| Aside in the code review | The notices were read three times when About appears | `BundledLicenses.available` reads each file once |
| I-3 | User guide: "Help ▸ About" without the name | Now "**Help ▸ About** followed by the app's name" |
| I-1, I-2 | Entry heights; ⌘F while Edit ▸ Find… shows disabled | Left, as the review says |

## Requirements issues (for the product manager)

- **RI-E1 What LibRaw's View License shows.** R6 and AC7 say the project's section of the
  notices file, and that is what is shown. LibRaw's section names the LGPL 2.1 and points to
  `Sources/CLibRaw/LICENSE.LGPL`, a path that is not in the bundle: the window shows the
  notice, not the license's text. LightCraft's and GRDB's sections carry their MIT text. If
  the LGPL's text should be readable in the app, #172 has to put it in the bundle (in the
  notices section or as a file) and say which; the reader then needs a small change for a
  second file.
- **RI-E2 Notices and Credits lines added here** (see above): GRDB's and ExifTool's notices
  sections and ExifTool's Credits line were needed for R9 and AC11. Confirm or reword. **Still
  open for Ship:** whether the Apache 2.0 text must ship for GRDB's three Swift.org-derived
  files, or the note and its link are enough.
- **RI-E3 The contract with #172.** This feature looks for `THIRD_PARTY_NOTICES.md` and
  `LICENSE` directly in the bundle's `Contents/Resources`
  (`BundledLicenses.noticesFileName`, `.licenseFileName`). #172 should use those names and
  that place, or say otherwise so the two constants change. AC7's and AC13's packaging halves
  (the files are in both bundles, and the bundle's `LICENSE` is the repository's) need a test
  in #172.

## Open questions

None blocking.

## README

For the product manager at Ship:

- **Credits**: gained the ExifTool line (above).
- **What works today**: an About window (app menu and Help) with the version, the dedication
  and the licenses, in both apps.
- **Repository layout**: `Sources/PhotoUI` now also holds the About window.
- `CLAUDE.md` (the owner's part; proposed, not edited):
  - Layout, `Sources/PhotoUI`: add "`About/` (the About window and its license windows,
    `AboutCommands`, debug-script commands; the record is `Acknowledgements` in PhotoCore's
    `About/`)".
  - The debug paragraph, after the sentence on `menuitems` and `menupress`: "`about open|close|
    escape|menus|print|windows|link|license|snapshot|click|height|closeothers|quithost|quitask` drives the About window and its
    license windows in both apps without a key window (`AboutDebugCommands`); links are
    reported, never opened, under a script. `menukey` posts keys for the library window even
    when another window is key, so use `about escape posted` for Esc in the About window."
  - A rule worth a line under Naming rules or Architecture rules: "A project whose code,
    formulas or approach is used goes in `Acknowledgements.all`, `THIRD_PARTY_NOTICES.md` and
    the README's Credits together; `AcknowledgementConsistencyTests` fails otherwise. License
    text is never typed into Swift or the String Catalog."
- No change to requirements or build commands.

## Seen while testing, not this feature's

- **A sleeping network share stalls `swift test`, and would stall the app the same way.**
  During the last full run the suite stopped for about four and a half minutes at 0% CPU in
  `ExportJobTests`, inside `VolumeAvailability.mountedVolumes()`
  (`Sources/PhotoCore/Import/VolumeResolver.swift`): `FileManager.mountedVolumeURLs(
  includingResourceValuesForKeys:)` was waiting in the SMB client for a mounted share whose
  server was asleep (`ls` on it timed out too). It went on by itself once the server answered,
  and the run passed. That code is not touched by this branch. Proposed as an issue in my
  report: the same call is made on export, import and when the library looks for its volumes.

## Not done, on purpose

- `Scripts/build-app.sh` does not copy the license files: #172.
- No `NSHumanReadableCopyright` in the Info.plists (follow-up).
- The library debug script's `menukey` is not changed (it posts keys for the library window);
  `about escape posted` covers the About window.
