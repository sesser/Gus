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

None yet.
