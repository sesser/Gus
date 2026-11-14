# About window with a dedication: QA

Owner: qa-tester. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md`. Issue: #179.
Tested: `feature/about-gus` at `a702501` (merge base with `develop`: `e990152`, PR #169 merged),
on a Mac16,8, macOS 27.2.1 (26B131), macOS 27.2 SDK (bundles record `sdk 27.2`, `minos 15.0`).

## Verdict

**Passes.** Every acceptance criterion that can be checked before #172 passes by test or by
script, on both apps, with and without the license files in the bundle. What stays open is a
person's eye and keys (P1–P9) and the packaging halves of AC7 and AC13, which only #172 can
make true. No finding blocks this feature; Q1 and Q2 are about code this branch did not
break (both reproduce on `develop`).

## Acceptance criteria

`swift test`: 952 tests in 138 suites passed, 1 known issue (`LiveSessionTests.swift:258`, the
baseline's), 50 s. `Scripts/build-app.sh all`: both bundles built, exit 0. Scripts S1–S9 are
below.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 Help lists About ‹name›; one window; a second use opens no second window | Test, Script | `AboutWiringTests.commandsReplaceBothItems` (a `Window` scene, both items open it by id); S1: Help has “About Gus”, enabled; Help then app menu → `1 titled “About Gus”` | Pass |
| AC2 The name comes only from `AppBranding.displayName` | Test, Script | `BrandingTests`, `AboutWordingTests.namesAreArguments`; S8: a scratch copy of the branch with `displayName = "Zephyr"` shows “About Zephyr” in both menus, the window title, header, dedication, statement and “Zephyr License” | Pass |
| AC3 Dedication and exactly the five entries, each with a line and a license | Test, Script | `AboutTests.recordListsTheFiveProjects`, `AboutWordingTests.sentencesAreTheApprovedOnes`, `licenseNamesAreTheApprovedOnes`; S1 `about print`; snapshot looked at | Pass |
| AC4 Wording by relationship | Test | `AboutWordingTests.wordingFollowsTheRelationship` (no “built on”, “includes”, “is included”, “contains” for studied, reimplemented or optional projects; darktable and ExifTool phrases present) | Pass |
| AC5 Version line from the bundle; absent with no bundle | Test, Script | `AboutTests` R4/AC5 tests (values missing, empty, not text; the plist templates); S1: “Version 0.1.0 (build 1)”, the bundle's `CFBundleShortVersionString` 0.1.0 and `CFBundleVersion` 1; S7: `.build/debug/PhotoApp` → `version none`, max height 21 pt less (670 against 691) | Pass |
| AC6 A link opens the project's page; works with no network | Script, Person | S3: all five links report the page they would open (libraw.org, darktable.org, github.com/storytold/lightcraft, github.com/groue/GRDB.swift, exiftool.org); S6: a posted click on `libraw.org` runs the link. No network API in `Sources/PhotoUI/About` or `Sources/PhotoCore/About`. Real browser: P4. Network off: P3 | Pass (script); P3, P4 open |
| AC7 License text of LibRaw, LightCraft, GRDB byte-identical to the notices' sections; none before #172 | Test, Script | `AboutTests.repositoryFilesAreShownByteForByte`, `noFilesNoControls` and the design §5 cases; S1: bundle as built, every entry `View License none`; S2: files copied in, three buttons (none on darktable, ExifTool), and the text read back from each license window has the SHA-256 of its section, computed separately (table under S2). **Packaging half** (the build puts `THIRD_PARTY_NOTICES.md` in both bundles): unverifiable until #172 | Pass for this feature; packaging open (#172) |
| AC8 The importer has the same item and window content | Script | S5: both menus “About Gus Importer”; header “Gus Importer”; same five entries, dedication and statement naming the project (RI-A1); license windows as in the library app | Pass |
| AC9 Both items open the one window; no system panel | Test, Script | `AboutWiringTests.systemPanelIsNotUsed`; S1 and S5: Help then app menu → one window; `an item opens the system About panel false`, both apps | Pass |
| AC10 Each kind of drift fails naming the project | Test | `AcknowledgementConsistencyTests`: removal of each of the five, package added (seven forms, comments ignored), vendored folder added, project added to or dropped from the notices or Credits, unbolded Credits line, stable anchors | Pass |
| AC11 `swift test` passes with the real notices and README after #169 | Test | `repositoryIsConsistent` on the files as merged with #169 (`e990152`) | Pass |
| AC12 Every control reachable by keyboard; ⌘W closes | Script, Person | S6: Esc posted through the event queue closed About. ⌘W, ⌘F and Tab not seen: macOS would not make the test copy the active app in my runs (`app active false`, also after bringing it forward by process ID), so posted ⌘W did nothing. P2, P7 | Open (P2, P7) |
| AC13 Copyright and GPL statement; full text from the bundle's `LICENSE`; none typed in | Test, Script | `copyrightMatchesTheReadme`, `statementMatchesTheReadme`, `copyrightLineMatchesTheReadme`, `LicenseTextTests`; S1: footer line and statement, no control without the file; S2: the app's license window shows 35149 bytes with the SHA-256 of the repository's `LICENSE` (`3972dc97…`). **Packaging half** (the bundle's `LICENSE` is the repository's, put there by the build): unverifiable until #172 | Pass for this feature; packaging open (#172) |

Design requirements checked by script on the way (design §2.2, §3.1, §5, §6.1): About opens
from both menus with the library or import window closed and only a license window open (S4,
both apps) and with a sheet up (S6); window 520×640, min 400, max 691 (734 with the buttons,
706 notices only, 719 `LICENSE` only), minimize and zoom off, no full screen, not restorable,
not in the Window menu, nothing focused; license windows 640×720, min 420×320, not restorable,
monospaced 12 pt, read-only, selectable, one per license; files removed while About is open
give the “Can't Show the License” state with no alert, and reopening About shows no buttons
(S9). The quit question's host: S6, under **Scripts**.

## Findings

No finding against #179's acceptance criteria. Two for the engineer, neither a regression.

**Q1. A quit with a sheet up on the library window shows no question, on the branch and on
`develop` (look into it; not blocking #179 unless P8 shows it with a real ⌘Q).**
Steps: start an export of 40 photos, close the export sheet, open the look-up table browser
(a sheet), optionally open About, then run App ▸ Quit Gus (`menupress Quit Gus`), wait, close
the sheet.
Expected (status.md C6, M8): “Quit While Exporting?” on the browser sheet at once.
Actual: no alert window appears (on-screen window list taken from outside the app: the same
windows before and after), nothing is queued (after the sheet is closed, `alert` → none), the
app does not quit, and the export runs to its end. With About in front, the library window does
come in front of About and the sheet becomes key. Without a sheet (S6, R1 and R7) the question
appears on the library window and the library window comes in front of About, as designed.
The same steps on a scratch build of `develop` (`e990152`) give the same result, so this is not
from this branch. `about quitask`, which calls `QuitGuard.ask` directly, does show the question
on the sheet (S6, R5), so the C6 code works when it is reached; what I can't tell from the
script is whether AppKit's `terminate:` reaches `applicationShouldTerminate` while a sheet is
up. A real ⌘Q in P8 decides; if it reproduces there it is a follow-up issue (proposed below),
not a fix on this branch.

**Q2. Launch crash from a saved toolbar configuration (pre-existing; follow-up issue, not
#179).** The test preference domain `me.sesser.gus.debugtest` (used by earlier test runs on
this Mac) now holds an `NSToolbar Configuration library` whose item list has `crop`,
`compare` and `original` and the split-view separator last. Every launch with it stops in
SwiftUI, `AppKitToolbarStrategy.applyItemCustomizations` (`EXC_BREAKPOINT`, exit 133), with any
library. A `develop` build given the same domain crashes the same way; removing only that key
makes it launch. Which run wrote that list is not known. A copy of the domain is at
`/private/tmp/claude-501/-Users-randy-Projects-Gus/681f34a7-d69a-4872-8e68-6c916dfa14fe/scratchpad/debugtest-prefs-crash-export.plist`
(scratch, may be cleared). The domain itself is left as found; later scripted runs on this Mac
need another identifier or that key removed.

Proposed follow-up issues (for the main session to file):

- **bug: “Quit while a sheet is up on the library window shows no question”** (if P8 reproduces
  Q1 with a real ⌘Q). Body: Q1's steps, expected, actual; seen on `develop` `e990152` and
  `feature/about-gus` `a702501`, macOS 27.2.1.
- **bug: “Launch crash restoring a customized library toolbar”**. Body: Q2; the toolbar item
  list above; `AppKitToolbarStrategy.applyItemCustomizations` traps; `develop` `e990152`,
  macOS 27.2.1; the owner's own toolbar customization could hit it.

Noted, not findings: the requirements issues RI-E1 (LibRaw's View License shows a pointer to
`Sources/CLibRaw/LICENSE.LGPL`, which is not in the bundle), RI-E2 (GRDB's Apache-derived files)
and RI-E3 (file names and place, the contract with #172) stay with the product manager and #172.
In the importer, closing the import window while About or a license window is open leaves the
app running with those; it quits when the last of them closes (S5).

## Scripts

Copies: `build/Gus.app` and `build/Gus Importer.app` copied to the scratch folder, identifiers
`me.sesser.gus.debugtest` and `me.sesser.gus.importer.debugtest` (Q2's crash later moved the
library runs to `me.sesser.gus.debugtest2`), signed again ad hoc. “plain” is the bundle as
built; “files” has `THIRD_PARTY_NOTICES.md` and `LICENSE` copied into `Contents/Resources`
(copies only; `build-app.sh` unchanged). Library: `photobench generate --jpeg 40 --jpeg-size
4000x3000`, then `photobench import --library-root <scratch>/lib`. Every launch:
`<copy>/Contents/MacOS/<name> --library-root <scratch>/lib --debug-script "…"`.

**S1, library, plain.**
```
wait 2; about menus; about print; about windows; about open help; about windows; about open app; about windows; about print; about license libraw; about license app; quit
```
App menu: “About Gus” at 0 of 11, followed by a separator, enabled, no key equivalent; Help:
“About Gus”, the only item; `⌘W item “Close”`; system panel false. No window at first; one after
Help, still one after the app menu. Window 520×640, min 520×400, max 520×691, zoom and minimize
off, not restorable, not in the Window menu. Header “Gus”, “Version 0.1.0 (build 1)”, the
dedication, the five entries with the approved sentences, licenses and addresses, every
`View License none`; footer “Copyright © 2026 Randy Sesser” and the statement, `View License
none`. `about license libraw` / `app`: “the window has no View License”.

**S2, library, files.**
```
wait 2; helpmenu; about open app; about print; about license libraw; about license lightcraft; about license grdb; about license app; about license darktable; about license exiftool; about license libraw; about windows; about license libraw find; about license libraw print; about snapshot <a.png>; about height max; about snapshot <b.png>; about license app snapshot <c.png>; about close; about windows; about print; quit
```
`helpmenu`: the Help menu is the menu bar's help menu, items [About Gus]. View License on
LibRaw, LightCraft, GRDB and the footer (“View Gus License”), none on darktable and ExifTool;
max height 734. darktable and ExifTool: no View License. LibRaw asked twice: one window. Find
bar shown. Closing About leaves the four license windows. Snapshots looked at: all four
buttons alike; the GPL text monospaced in “Gus License”.

| License window | Bytes shown | SHA-256 of the text shown | SHA-256 computed separately (Python, section from its `## ` heading to the next, fenced blocks skipped; `LICENSE` whole) |
|---|---|---|---|
| LibRaw (`## LibRaw 0.22.3`) | 2408 | `a3091a2f…98e8a` | `a3091a2f…98e8a` |
| LightCraft | 1981 | `830db8cd…c37` | `830db8cd…c37` |
| GRDB | 3283 | `037586fb…1fd36` | `037586fb…1fd36` |
| Gus (`LICENSE`) | 35149 | `3972dc97…86986` | `3972dc97…86986` (`shasum -a 256 LICENSE`) |

**S3, links (library, files).**
```
wait 2; about open help; about link libraw; about link darktable; about link lightcraft; about link grdb; about link exiftool; …
```
Each prints `about link would open <page>` with the five addresses above; nothing opened.

**S4, the library window closed, a license window open (design §2.2, code review Q2).**
```
… about license grdb; about close; about closeothers; about windows; about menus; about open help; about windows; about print; about close; about windows; about open app; about windows; about quithost; quit
```
Only “GRDB License” left; both About items enabled; Help opens About (1 window, full content),
and after closing it the app menu opens it again. `quithost none` (the alert would stand
alone). Importer: the same (S5).

**S5, importer, plain and files.**
```
wait 2; helpmenu; about menus; about open help; about open app; about windows; about print; about license app; about link grdb; about quithost; quit
wait 2; about open app; about print; about license libraw; about license app; about snapshot <i.png>; about close; about closeothers; about windows; about open help; about windows; about close; about open app; about windows; about quithost; quit
```
Help menu [About Gus Importer]; app menu “About Gus Importer” first, then a separator; one
window; header “Gus Importer”, “Version 0.1.0 (build 1)”, dedication and statement “Gus …”,
the same five entries; plain: no buttons; files: the same buttons and hashes as S2 (“Gus
License”). With the import window closed, both items open About. Closing the remaining windows
quits the importer. Snapshot looked at.

**S6, quit host and keys.** Shell launch, library, files:
```
wait 2; about quithost; about open app; about quithost; about quitask; about quitask keep; lutwindow open; about open help; about windows; about quithost; about quitask; about quitask keep; quit
```
Host “photos” (the library window, named after the scratch project) with and without About in
front; `quitask`: question on screen on it, sheets 0 → 1, and the library window comes in front
of About. With the look-up table sheet up: host “a sheet on …”, question on screen on the
sheet. Active launch (`open -W -n --stdout <log> <copy> --args --library-root … --debug-script
…`, then System Events by process ID): macOS kept `app active false`, so `about click 472 214`
hit the LibRaw link (`SwiftUIAppKitButton`, reported, not opened), `about escape posted` closed
About, and posted ⌘W, ⌘F and Esc reached no window: P2, P7.
Real quit during an export (40 photos to 16-bit TIFF, `export run keepboth nowait`, export
sheet closed, then `menupress Quit Gus`), windows listed from outside the app:
- R1/R7, About in front (in R7 About was key and the app active): a 410×306 alert appears; `alert`
  reads “Quit While Exporting?”, “The rest is not exported.”, “Keep Exporting” (Return), “Stop
  and Quit”; the library window comes in front of About; the key window is the alert. M8's first
  half, by script.
- R2/R8 (About) and R3/R9 (no About), the look-up table sheet up: no question (Q1).
- R5, the same state with `about quitask`: question on screen on the sheet, key.
- `develop` scratch build, R9's steps: no question (Q1 is not this branch's).

**S7, no bundle.** `.build/debug/PhotoApp --library-root <scratch>/lib2 --debug-script "wait 3;
about menus; about open help; about print; about license app; quit"`: both items “About Gus”;
`version none`; max 520×670; footer statement, no View License.

**S8, AC2.** `git archive HEAD` into the scratch folder, `displayName = "Zephyr"` in that copy's
`AppBranding.swift`, `Scripts/build-app.sh` there, copy with its own identifier and the two
files: `about menus; about open help; about print; about license app; about license libraw;
about snapshot …`. Every About string reads “Zephyr” (menus, title, header, dedication,
statement, “View Zephyr License”, “Zephyr License”). The app menu's own title and Hide/Quit
items stay “Gus”: they come from `CFBundleName` in `Branding.xcconfig`, not this feature.
Snapshot looked at.

**S9, files missing.** Copies with only the notices (buttons on the three entries, none in the
footer, max 706), only `LICENSE` (footer button only, max 719), and both files removed while
About was open:
```
wait 2; about open app; about print; wait 10; about license libraw; about license app; about license libraw snapshot <m.png>; about close; about open help; about print; quit
```
(files removed at 8 s): the two license windows open in their missing state (“Can't Show the
License”, “The license text is missing from this copy of Gus.”, snapshot looked at), no alert;
About reopened shows no View License.

After every run: no instance left running; nothing under `~/Library/Application Support/Gus`
or `~/Library/Caches/Gus` newer than the start of the session; the owner's preference files
unchanged (last written 18:28 and 08:41, before the session).

## For a person

Use a test copy with `THIRD_PARTY_NOTICES.md` and `LICENSE` copied into
`Contents/Resources` and signed again (status.md, **Debug script**), launched with
`--library-root` on a scratch library. Per the owner's standing rule, VoiceOver, Voice Control
and macOS 15 and 26 are not listed (M7's VoiceOver part is out; its keyboard part is P7).

- **P1 Look (M1).** About in light, dark and with Increase Contrast: header centered and clear
  of the window buttons, divider under it, entries leading-aligned with the address at the
  trailing edge, footer text secondary, the four View License buttons alike. A license window
  in light and dark: monospaced text, inset, title shown. (Dark seen by script in S2; light and
  Increase Contrast never seen.)
- **P2 Keyboard Navigation (M2, AC12).** With Keyboard Navigation on: Tab goes link, then View
  License, entry by entry, then the footer's button; Space activates; no focus ring when the
  window opens; Return does nothing.
- **P3 No network (M3, AC6).** With Wi-Fi off, About opens and shows everything.
- **P4 A real click on a link (M4, AC6)** opens the default browser at that project's page.
- **P5 Resizing and moving (M5).** The window drags taller up to its content and no wider; the
  zoom button is dimmed; dragging the background moves it.
- **P6 Menus by eye (M6).** App menu: About ‹name› first, alone above a separator. Help: the
  search field, then About ‹name›. In both apps.
- **P7 Esc, ⌘W and ⌘F with a real keyboard (M7's keys, AC12).** Esc closes About; Esc in a
  license window does nothing, or closes its find bar; ⌘W closes either; ⌘F in a license
  window opens its find bar.
- **P8 Quit during an export, from About (M8).** (a) Start an export, open About so it is key,
  ⌘Q: the library window comes in front of About and “Quit While Exporting?” is a sheet on it;
  Return and Esc keep exporting. The script saw the placement (S6, R7), not the keys.
  (b) Again with the look-up table browser open on the library window: the question should be on
  that sheet at once. The script saw no question at all here, on `develop` too (Q1): say what
  happens. Not checked by anyone: the library window on another Space or in full screen.
- **P9 ⌘F on a non-Latin layout (M9).** With a Russian or Greek input source, ⌘F in a license
  window opens its find bar.

Open until #172 lands (not a person's check now): AC7's and AC13's packaging halves, that the
build puts `THIRD_PARTY_NOTICES.md` and `LICENSE` in both bundles and that the bundle's
`LICENSE` is the repository's. #172 needs its own test for that (RI-E3).

## Follow-up

(Reruns after fixes, P items as the owner reports them, and the owner's sign-off go here.)
