# About window with a dedication: code review

Owner: code-reviewer. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/about-gus`, e990152..47171a9 (five commits, #179; the merge of `develop`
and the roadmap commit before them were not re-reviewed). Build and tests: `swift build`
complete (incremental, so warnings were not listed again); `swift test` 945 tests in 138
suites passed with 1 known issue, the same count `status.md` gives. The app was not launched.

## Verdict

Ready for qa-tester once C1 to C3 are answered. Nothing is a blocker: the window, the menu
wiring, the record and the bundle reading are correct as far as the code and the tests can
say. The three Should-fix findings are two ways the R9 test can be passed while the lists
have drifted, and one notice missing from the GRDB section added on this branch.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Tests/PhotoCoreTests/AcknowledgementConsistencyTests.swift:54-63` | `packageLocations` only sees `.package(url:)` and `.package(path:)`. A registry package (`.package(id: "scope.name", from: …)`) and a `.binaryTarget(name:url:checksum:)` or `.binaryTarget(name:path:)` are external dependencies it does not see. | Add `.package(id: "groue.GRDB-extras", from: "1.0.0")` to `dependencies`, or a `.binaryTarget(…)` to `targets`: the regex requires `url:` or `path:` right after `.package(` (and an optional `name:`), so `problems()` is empty and `repositoryIsConsistent` passes with a dependency the record lacks. `addingAPackageIsNamed` tests the `url:` and `path:` forms only. | R9 (c), AC10 |
| C2 | Should fix | `Tests/PhotoCoreTests/AcknowledgementConsistencyTests.swift:45-51`, `:111` | A credit in the README counts only when its name is in bold. A Credits line with no bold is not read as a credit. | Append `- OpenColorIO for the color transforms.` to the Credits section: `creditedNames` returns the same five names, `problems()` is empty, the test passes. AC10's "adding a project to the README Credits without the record fails" holds only for a bolded name (`addingToTheNoticesOrCreditsIsNamed` adds `**OpenColorIO**`). A check that every list item of the section starts with a bold name would close it. | R9 (b), AC10 |
| C3 | Should fix | `THIRD_PARTY_NOTICES.md:118-136` (added by 64ec379) | The GRDB section's license text is right: it is byte-identical to `LICENSE` of the pinned checkout (`.build/checkouts/GRDB.swift`, v7.11.1, b83108d; compared with `cmp`). But the section says nothing of the notices GRDB carries inside its source, and one has the same condition as GRDB's own. | `GRDB/Utils/Inflections+English.swift` (compiled into the `GRDB` target the apps link) carries a second MIT notice, "Copyright (c) 2005-2019 David Heinemeier Hansson", with "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software." The apps' notices reproduce only Gwendal Roué's. (`Core/Cursor.swift`, `Record/EncodableRecord.swift` and `Record/FetchableRecord.swift` say parts derive from Swift.org code under Apache 2.0 with the Runtime Library Exception; the section's "used under the MIT License" does not mention that either.) Whether to add them is the product manager's and #172's call: decide it with RI-E2, not by guessing. | #172's notices; R9's "truthfully" (R3) |
| C4 | Nit | `Sources/PhotoUI/About/LicenseView.swift:109` | ⌘F, ⌘G and ⇧⌘G are matched on `charactersIgnoringModifiers`, which is the layout's own letter. | With a non-Latin input source (Russian: the F key gives "а"), ⌘F in a license window falls through to `super` and no find bar opens; a menu item's key equivalent would have matched. Not run here (it needs the input source switched); it follows from what `charactersIgnoringModifiers` returns. `event.characters` (the letter with Command applied) is what menu matching uses. Find is a Should in design §6.2. | design §6.2 |
| C5 | Nit | `Tests/PhotoCoreTests/AcknowledgementConsistencyTests.swift:277-283` | `statementMatchesTheReadme` compares the README with a copy of the sentence typed into the test, not with the literal `AboutText.freeSoftwareStatement` uses. | Reword the statement in `AboutText.swift`, add the new key to the catalog and leave the old key in it: the window and the README now differ and the test passes (no test fails on an unused catalog key). The project sentences are read from the source by `AboutWordingTests.literal(forCase:)`; the statement could be read the same way. | R11, Q-E2 |

## Questions

- **For the owner (a `CLAUDE.md` rule), Q1.** "No SwiftUI `ScrollView` under the toolbar" is
  written without exceptions. The About window's body is a SwiftUI `ScrollView`
  (`AboutView.swift:104`) in a window whose title bar is kept and whose toolbar title is
  removed. The design (Q-E6) and the design review accept it because the window has no
  toolbar and the fault was seen in the earlier design on macOS 26+; clicks were checked on
  macOS 27.2 only, and macOS 15 (which still gets the earlier design) by nobody. I can't show
  a failure, so this is not a finding. Does the owner read the rule as covering this window?
  If yes, `AppKitScrollView` (now in `Sources/PhotoApp/Views/`) moves to PhotoUI.
- **For qa-tester, Q2.** Design §2.2's first case, "the library window closed while a licence
  window is open", is not in the engineer's table of checks (no key window and a sheet up
  are). Check that About ‹name› still opens the window from both menus then.
- **Design question, Q3.** `AppDelegate.applicationShouldTerminate` asks in
  `NSApp.keyWindow` first (`PhotoApplication.swift:113`), so ⌘Q during an export or import
  while the About window is key puts the quit confirmation on the 520 pt About window as a
  sheet (the Esc monitor already allows for a sheet there). Acceptable, or should the About
  and license windows be passed over for the library window?

Requirements issues, for the product manager (the engineer's, which I confirm from the code):

- **RI-E1.** LibRaw's View License shows its section of the notices, which names the LGPL 2.1
  and points to `Sources/CLibRaw/LICENSE.LGPL`, a path that is not in the bundle. The button
  says License and the window shows no license text. #172 decides where the LGPL text goes;
  `BundledLicenses` then needs a second file or a longer section.
- **RI-E2.** The GRDB and ExifTool sections and the ExifTool Credits line were written by the
  engineer. The ExifTool wording is accurate ("the same terms as Perl itself", as
  exiftool.org states; the reader's path exists; the darktable section it refers to says the
  same about the tag documentation). C3 belongs with this ruling.
- **RI-E3.** The file names and the place (`Contents/Resources/THIRD_PARTY_NOTICES.md`,
  `LICENSE`) are a contract with #172, and AC7's and AC13's packaging halves have no test
  until #172 adds one.

## Checked and fine

- **Menu wiring.** `AboutCommands` replaces `.appInfo` and `.help`, reads no model and no
  focused value (only `openWindow`), and both apps add it once under their own names; the
  two apps no longer empty the Help group themselves. `AboutScenes` comes after each app's
  first `Window`, with `defaultLaunchBehavior(.suppressed)` and restoration off. No launch
  option was added.
- **One window.** A `Window` scene with id `about`; licenses a `WindowGroup(for:
  LicenseDocument.self)`; both `commandsRemoved()`. Scene ids don't collide with `library`
  and `import`.
- **Window lifecycle.** `AboutWindowRegistry` is main-actor, holds windows weakly, installs
  one Esc monitor for the app's life that answers only for the About window, visible, with
  no sheet, unmodified Esc. Content is decided at `onAppear`; the license window reads
  again when it opens and shows the missing state without an alert.
- **Key equivalents don't leak between windows.** `LicenseTextView.performKeyEquivalent`
  has no key-window check, so I tested AppKit with a scratch program (two windows, ⌘G sent
  to the key one): on macOS 27.2 only the key window's views are offered the key. A license
  window in the background does not take ⌘F or ⌘G from the library or import window.
- **Swift 6 concurrency.** UI types and the registry are main-actor; the license text is
  read in a detached task with `Sendable` values only. The About window reads `LICENSE`
  once and the notices three times (once per project) on the main actor when it appears:
  about 60 KB of local bundle files, not a large read; one read of the notices would do.
- **File reading.** `NoticesFile` splits by byte offsets with every index bounded by the
  data's count; fenced blocks are skipped; a heading matches a project by its whole name;
  missing, empty or non-UTF-8 files give no control. The input is the app's own bundle, not
  an outside file. The test and the window use the same parser, so a heading the window
  can't find fails `repositoryIsConsistent` too.
- **Version line.** Both plist values or nothing; `AboutTests` covers each missing case and
  the plist templates.
- **Branding and strings.** 19 catalog keys, all used, each English value with its
  arguments; the name only through `%@` from `AppBranding`; `BrandingTests` and
  `LocalizationTests` pass. `AppCopyright` holds a person's name, not a brand value, and is
  tied to the README by `copyrightMatchesTheReadme`. No persisted name was added.
- **The record is the one source.** The view lists `AboutContent.entries`
  (`Acknowledgements.all`); the sentences and license names are exhaustive switches over
  the record's enums. The AC10 tests mutate a copy of the real files and each fails with
  the project named; `repositoryIsConsistent` asserts it read the real files (five
  headings, five credits, one package, one vendored folder).
- **No license text in sources.** `LicenseTextTests` searches every `.swift` and
  `.xcstrings` under `Sources` for eleven phrases and every fifth long line of the four
  license files, whitespace-insensitive, and proves itself on pasted and re-wrapped
  passages and on the allowed short notice and names.
- **Pages (PRD A1).** All five addresses answered 200 on 2026-11-13.
- **Project rules.** No dependency, migration, rendering, golden, pipeline version, catalog
  write, sidecar, undo or export code was touched; `Package.swift` and `Scripts/` are
  unchanged; the new debug-script commands change no photos, so they need no undo group.
- **`/security-review`: not needed.** No parser of outside files (the notices parser reads
  the app's own signed bundle), no subprocess, no file writing, no network code; links are
  handed to the system when a person activates them.

## Follow-up

### Second pass (2026-11-13)

Reviewed: `feature/about-gus`, 7138b18..20f18f8 (four commits: cfe18a2 the notices, 8fd9cd2
the source fixes, 86a4f59 the tests, 20f18f8 status and user guide). Build and tests:
`swift build` complete; `swift test` 949 tests in 138 suites passed with 1 known issue (the
same one, `LiveSessionTests.swift:258`), the count `status.md` gives. The app was not
launched. Three scratch programs outside the repository stood in for it: two AppKit probes
(a sheet asked on a window that already has one; a sheet asked on a covered window) and a
read of the key layout tables.

**Verdict.** C1 to C5 are fixed. The Q3 change does what it says, and brings one regression
(C6, Should fix) in a narrow case. One Nit on the new tests (C7). Not ready for qa-tester
until C6 is answered; it is on the same line as the designer's F4, so fix them together.

| # | Result | Commit | What I checked |
|---|---|---|---|
| C1 | Fixed | 86a4f59 | `dependencies(in:)` finds every `.package(` and `.binaryTarget(` outside comments, reads `url:`, `path:`, `id:` (a binary target without either: its `name:`), and lists a call it can't read by its own text, so nothing is passed over silently. My two inputs (`.package(id: "groue.GRDB-extras", …)`, both `.binaryTarget` forms) are cases of `everyFormOfDependencyIsNamed` and fail with the name; a commented-out declaration is not counted (`commentsAreStripped`). The comment scanner keeps strings whole and ends cleanly on an unterminated block comment. Not seen, and not asked for by R9 (c): a `.systemLibrary` target, and `.package (` written with a space |
| C2 | Fixed | 86a4f59 | Every list item of the Credits section must open with a bold name. My input (`- OpenColorIO for the color transforms.`) and four other shapes fail quoting the item. A `**Name** …` paragraph is not mistaken for a `*` list item (the marker needs a space after it) |
| C3 | Fixed; the Apache question stays with RI-E2 | cfe18a2 | The second MIT notice is byte-identical to lines 24 to 43 of `GRDB/Utils/Inflections+English.swift` in the pinned checkout (7.11.1, b83108d) with the comment marks removed (`cmp`, 1073 bytes). GRDB's own license block is still identical to upstream's `LICENSE`. The note on the Swift.org files is accurate: file names, the two function names, the years (2014 - 2018, 2014 - 2020), the license's name and address are what the three headers say. No other file of the `GRDB` target or `Sources/` carries a notice (four files have one; all four are covered). The headings parser is not disturbed: the new block has no `## ` line, and GRDB's license window shows the whole section |
| C4 | Fixed | 8fd9cd2 | Read from the layouts' own tables (`UCKeyTranslate`, key codes 3 and 5): with Command, Russian, Ukrainian, Greek, Hebrew and Arabic give "f" and "g" where the plain key gives "а", "φ", "כ", "ب"; with Command and Shift they give "F"/"G" or "f"/"g", and the code lowercases. Dvorak gives its own letter and Dvorak-QWERTY ⌘ the QWERTY one, as menus do. A real keypress on such a layout is still M9 |
| C5 | Fixed | 86a4f59 | `statementMatchesTheReadme` reads the literal from `AboutText.swift` and compares it with the catalog and the README; `copyrightLineMatchesTheReadme` does the same for the copyright line. Rewording either in the source alone now fails. A reformatted line (the literal moved off its `String(localized:` line) fails with "expected one line with …", not silently |
| Q3 | Changed as described; see C6 | 8fd9cd2 | `QuitConfirmation.host` is the old order (key, main, a visible one) with owned windows passed over; nil when only those are left, and `WindowModal.run` then shows the alert alone. `QuitConfirmationTests` covers each case. With no About or license window key, the result is the same as before the change. The importer's path (`CardImportModel.confirmQuit`, its own `window`) is untouched. Nothing in the tests ties `PhotoApplication` to `confirmationWindow`; M8 is the check |
| Aside (three reads) | Fixed | 8fd9cd2 | `available` reads `LICENSE` once and the notices once; `text(for:)` gives what it gave (`AboutTests` unchanged and passing) |

New findings from the fix commits:

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C6 | Should fix | `Sources/PhotoUI/QuitGuard.swift:42-46`, used at `Sources/PhotoApp/PhotoApplication.swift:114` | When the About or a license window is key and the library window has a sheet up, the host is the library window itself, and `WindowModal.run` asks `beginSheetModal(for:)` on a window that already shows a sheet. AppKit does not show a second sheet: it queues it until the first ends. | An export runs; the look-up table browser (or the preset manager, the Export sheet, a sidebar sheet) is open on the library window; About is opened (`status.md`: it opens with a sheet up) and is key; ⌘Q. No question appears and the quit is cancelled, so ⌘Q seems to do nothing. When the sheet is closed later, "Quit While Exporting?" drops on the library window by itself (and one more for each further ⌘Q, by the same rule). Before 8fd9cd2 the question showed on About; without About the key window is the sheet and the question shows on it, which is `WindowModal`'s stated rule ("the key window, which is the sheet when one is up"). Mechanism checked with a scratch AppKit program on macOS 27.2: with a sheet up, after `alert.beginSheetModal(for: parent)` the alert's window is not visible and `parent.sheets.count` is 2; it appears when the first sheet ends. Not run in the app. `about quithost` prints the library window in this state, so the script does not show it; the host's `attachedSheet` would be the window to name | Correctness; `WindowModal`'s rule |
| C7 | Nit | `Tests/PhotoCoreTests/AcknowledgementConsistencyTests.swift:275-279`, `:304-306`, `:355`, `:361-365` | The mutation tests edit the real files by text, and depend on two facts that are not what they test: the exact line `.package(url: "…GRDB.swift.git", from: "7.9.0"),` (one test before, eight cases now), and Credits being the README's last section (the lines are appended to the file's end; six appends now). | Raise GRDB's minimum to `from: "7.11.0"`: `addingAPackageIsNamed` and all seven cases of `everyFormOfDependencyIsNamed` fail. Add a section after Credits in the README (the product manager edits it at Ship, without building): `addingToTheNoticesOrCreditsIsNamed` fails on `problems.count == 1` with nothing saying why. Both fail loudly, never pass wrongly. Inserting after `dependencies: [` and into the Credits section itself would not depend on either | Tests |

For the designer (F4, through the main session): my second probe asked an alert as a sheet on
a window covered by another window of the same app. On macOS 27.2 the covered window came in
front of the other one when the sheet began (front to back before: about, library; after:
library, about). The probe's app was not active and had no key window, so M8 in the real app
still decides; but F4's premise did not hold there.

For the product manager (RI-E2): the note says the Apache license's text is not reproduced.
The Runtime Library Exception at the address the headers give (read today) waives sections
4(a), 4(b) and 4(d) "if you use this Software to compile your source code and portions of
this Software are embedded into the binary product as a result". GRDB's three files hold
source copied from the Swift project, which is not that case as written. Whether a link is
enough is the owner's and #172's call; I am not deciding it.

For qa-tester, with M8: ⌘Q during an export with About key and (a) a sheet up on the library
window (C6), (b) the library window minimized (by reading: no host, so the alert stands
alone), (c) the library window on another Space or full screen (not checked by anyone).

`/security-review`: still not needed. The fix commits add no parser of outside files (the
manifest scanner is test code reading the repository's own `Package.swift`), no subprocess,
no file writing and no network code.
