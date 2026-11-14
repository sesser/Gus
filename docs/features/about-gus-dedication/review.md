# About window with a dedication: design review

Owner: apple-ui-designer. Date: 2026-11-13. Issue: #179.
Branch `feature/about-gus` at `47171a9`, against [`design.md`](design.md)
(§1–§13, rulings D-A1 to D-A8 added at this review), the PRD (issue #179's
body, R1–R11, AC1–AC13) and the HIG (The menu bar, Windows, Buttons,
Accessibility).

Read: `Sources/PhotoUI/About/*.swift`, the 19 keys in
`Sources/PhotoUI/Resources/Localizable.xcstrings`, the wiring in
`Sources/PhotoApp/PhotoApplication.swift` and
`Sources/PhotoImporter/ImporterApplication.swift`, `AppCopyright`,
`AppVersion` and `displayAddress` in `Sources/PhotoCore/About/`,
[`status.md`](status.md), and the About paragraph of `docs/USER_GUIDE.md`.
Seen: the engineer's debug-script snapshots of the library and importer About
windows (before #172 and with the files copied in), the app's licence window
with its find bar, and the missing-file state, all in dark appearance on
macOS 27.2. I have no shell: nothing was run by me.

## Verdict

**Pass with two small fixes.** The window is what the design asked for:
a `Window` scene of system parts, fixed width, the header fixed above one
scroll region, the five entries with the approved wording, the footer with
copyright and the GPL notice, licence windows in an `NSTextView`, About in
the app menu and Help in both apps, the system panel gone. The two fixes are
the footer's View License button inheriting the footer's callout font and
secondary color (F1) and Voice Control names for View License (F2, a design
amendment, D-A7). A catalog comment fix (F3) is trivial.

## Requirements

| # | Requirement (design § / AC) | Result | Evidence |
|---|---|---|---|
| 1 | About ‹name› first in the app menu, replacing the system item (§2.1, AC9) | Pass | `CommandGroup(replacing: .appInfo)` in `AboutCommands`; status: no item opens the system panel. Separator below it: M6 |
| 2 | Help ▸ About ‹name›, search field kept, no dead Help item (§2.1, AC1, AC8) | Pass | `CommandGroup(replacing: .help)`; status `about menus`, `helpmenu` |
| 3 | No shortcut; always enabled; no focused value (§2.1, §2.2) | Pass | `AboutCommands` reads no focused value; status: enabled with a sheet up and in the importer |
| 4 | One window; second use brings it forward (§3.1, AC1, AC9) | Pass | `Window(id: "about")`; status `about windows` → 1 |
| 5 | Running app's name in menus, title and header; project's name in dedication and GPL notice (§2.3, RI-A1 ruling) | Pass | `AboutScenes(appName:projectName:)`; importer snapshot: header "Gus Importer", dedication "Gus stands on…" |
| 6 | Title kept for VoiceOver, not drawn (§3.1) | Pass | `.toolbar(removing: .title)`; snapshots show no title |
| 7 | 520 pt fixed width; 400 min, 640 ideal, max content height; vertical resize only (§3.1, §3.6) | Pass | `AboutMetrics`, root frame; status 520×640, min 400, max 691/734 (D-A1). Dragging by hand: M5 |
| 8 | Centered, never at launch, never restored (§3.1) | Pass | `defaultPosition(.center)`, `defaultLaunchBehavior(.suppressed)`, `restorationBehavior(.disabled)` |
| 9 | Minimize, zoom and full screen off; background drag (§3.1) | Pass | `windowMinimizeBehavior(.disabled)`, `windowFullScreenBehavior(.disabled)`, zoom button disabled on the `NSWindow`, `windowBackgroundDragBehavior(.enabled)`. Look and drag: M5 |
| 10 | Not in the Window menu's list; no Window menu item for the scene (§3.1) | Pass | `isExcludedFromWindowsMenu`, `commandsRemoved()` |
| 11 | Follows system appearance; no glass, no `Palette` (§3.1) | Pass by code | Only semantic styles (`.secondary`, `textColor`, `textBackgroundColor`). Light and Increase Contrast never seen: M1 |
| 12 | Header: 64 pt icon hidden from VoiceOver, name `.title2` semibold header, version `.callout` secondary selectable, absent with no gap (§3.3, AC5) | Pass | `AboutView.header`; status: no-bundle run has no line and 21 pt less height. Top spacing per D-A3 |
| 13 | Dedication, body, header trait (§3.4) | Pass | Snapshot |
| 14 | Entry: name `.headline` verbatim, link with bare address and full-URL tooltip, description, licence `.callout` secondary (§3.4) | Pass | `AboutEntryView`; snapshot. Address wraps under the name when it doesn't fit (`ViewThatFits`), as §3.6 asks |
| 15 | Entry View License: small bordered button, only for LibRaw, LightCraft, GRDB when the text is found (§3.4, §5, AC7) | Pass | `offersLicense`; snapshots before and after the files; never on darktable or ExifTool |
| 16 | Wording by relationship; the approved sentences (§8, AC3, AC4) | Pass | `AboutText.summary`; catalog keys match §8 word for word |
| 17 | Links open through the system; nothing fetched (§3.4, AC6) | Pass by code | `openURL` environment → `.systemAction`; reported under a script. Real browser: M4; network off: M3 |
| 18 | Footer: divider, copyright selectable, GPL notice, View License only when `LICENSE` is found (§3.5, AC13) | **Fail (F1)** for the button's look; rest Pass. Second pass: Pass (F1 fixed) | The button sits inside the footer stack that sets `.font(.callout)` and `.foregroundStyle(.secondary)`, so its title likely differs from the entries' buttons. See F1 |
| 19 | Missing file: no alert, no error line; licence window shows "Can't Show the License" (§5) | Pass | Snapshot `license-missing`; D-A4 |
| 20 | Licence window: one per licence, titled "‹name› License", 640×720, min 420×320, centered, not restored, no New Window item, listed in Window menu, independent of About (§6.1) | Pass | `WindowGroup(id:for:)`, `commandsRemoved()`; status checks |
| 21 | Licence text verbatim, monospaced 12 pt, 16 pt inset, system text colors, selectable, wraps (§6.2, AC7, AC13) | Pass | `LicenseTextArea`; no link or data detection; snapshot. Byte checks are QA's |
| 22 | ⌘F find bar in licence windows (§6.2, Should) | Pass | `LicenseTextView.performKeyEquivalent`; snapshot. See I-2 |
| 23 | Keyboard: ⌘W closes; Esc closes About only; Return does nothing; no initial focus ring (§4, AC12) | Pass by script | Local key-down monitor scoped to the About window, no hidden control (Q-E3). Real keyboard and Tab order: M2, M7 |
| 24 | VoiceOver: entry containers labelled by project, View License labelled by owner (§7) | Pass by code, with F2 | `accessibilityElement(children: .contain)`; labels per §7. Voice Control names: F2 (D-A7) |
| 25 | Strings: 19 keys with comments; no literal brand name (§8, R10) | Pass, with F3 | Keys present; D-A5 accepted. One comment wrong (F3) |
| 26 | `docs/USER_GUIDE.md` terms match the UI | Pass | "About", "View License", "Help ▸ About", Esc and ⌘W, "taller, not wider" match. See I-3 |

## Findings for the engineer

**F1 — Footer View License doesn't match the entries' buttons (should fix).**
In `AboutView.footer`, the `VStack` that holds the copyright, the statement
and the button carries `.font(.callout)` and `.foregroundStyle(.secondary)`.
Both reach the button: on macOS a `Button`'s label takes the environment
font, and the foreground style tints a bordered button's title. So the
footer's View License is drawn in callout size and secondary gray, while the
three entry buttons (whose rows set the font on the licence `Text` only) use
the small control's own font and primary label color. Same control, two
looks, and a gray title reads as disabled (HIG Buttons; Consistency).
Fix: apply `.font(.callout)` and `.foregroundStyle(.secondary)` to the two
`Text`s, not to the stack, so the button gets the same environment as the
entry buttons. Then take `about snapshot` with the files copied in and the
window stretched to its full height so the footer shows, and compare its
button with LibRaw's.

**F2 — Voice Control names for View License (design amendment D-A7).**
Add `.accessibilityInputLabels([Text(verbatim: AboutText.viewLicense),
Text(verbatim: AboutText.viewLicenseLabel(name))])` to each View License
button (entries: the project's name; footer: `projectName`), keeping the
existing `accessibilityLabel`. The label "View LibRaw License" doesn't
contain the visible "View License" in order, so speaking the visible title
doesn't match it by name. No new strings.

**F3 — Translator comments for the project's name (design amendment D-A8).**
`%@ stands on other people's work. Thank you to:` says "the argument is the
app's name"; make it "the argument is the project's name (the library app's
name, also in the standalone importer)". Give the free-software statement's
comment the same note about its argument. Comment text only, in
`AboutText.swift` and the catalog.

## Improvements (judgment, not required)

- **I-1 Entry heights.** Rows with a View License button are a few points
  taller than rows without (the button is taller than the callout line), so
  the gap after LibRaw, LightCraft and GRDB is slightly larger than after
  darktable and ExifTool. Barely visible in the snapshot; leave it unless M1
  finds it distracting.
- **I-2 ⌘F and the Edit menu.** In a licence window ⌘F works, but the library
  app's Edit ▸ Find… (⌘F) shows disabled at the same time, so the menu bar
  says ⌘F does nothing while it does. Accepted for this feature (Q-E5 allowed
  it, and the library's Find must not reach a licence window). If Find… ever
  routes through the responder chain, let it reach the text view's find bar.
- **I-3 User guide wording.** "**Help ▸ About**" names the item without the
  app's name, which the menu shows ("About Gus"). Writing "**Help ▸ About**
  followed by the app's name", as the app-menu sentence does, would match
  exactly. Optional.

## Rulings on the engineer's readings

Recorded in [`design.md`](design.md) §13. Status lists D-1 to D-6; there is
no D-7 in `status.md`, so nothing was ruled under that number.

| Status | Ruling | Result |
|---|---|---|
| D-1 heights are the window's | D-A1 | Accepted |
| D-2 3 pt between an entry's lines | D-A2 | Accepted |
| D-3 header 4 pt under the title bar | D-A3 | Accepted |
| D-4 no symbol in "Can't Show the License" | D-A4 | Accepted |
| D-5 plain `%@` keys, positional values | D-A5 | Accepted; §8 amended |
| D-6 "Gus License" in the importer; missing text names the running app | D-A6 | Accepted |
| (new) Voice Control names | D-A7 | Amends §7; F2 |
| (new) Catalog comments | D-A8 | Amends §8; F3 |

The answers to §10 (Q-E1 to Q-E6) are accepted as written. Q-E6 keeps a
SwiftUI `ScrollView`: the fault CLAUDE.md records was in the earlier design on
macOS 26+, which a bundle from `build-app.sh` no longer runs in; clicks on
macOS 15 itself are unverified (not asked of the owner, see below).

## Manual checks (for a person at the bundled app)

To see the buttons, use a test copy with `THIRD_PARTY_NOTICES.md` and
`LICENSE` copied into `Contents/Resources` and signed again (status.md,
Debug script).

- **M1 Look.** The About window in light and in dark, and with Increase
  Contrast on: header centered and clear of the window controls, divider
  under it, entries leading-aligned with the address at the trailing edge,
  secondary footer text, and all four View License buttons alike (after F1).
  A licence window in light and dark: monospaced text, readable inset, title
  shown.
- **M2 Keyboard Navigation.** With it on in System Settings: Tab goes link,
  then View License, entry by entry, then the footer's button; Space
  activates; nothing has a focus ring when the window opens; Return does
  nothing.
- **M3 No network.** With Wi-Fi off, About opens and shows everything.
- **M4 A real click on a link** opens the default browser at that page.
- **M5 Resizing and moving.** The window drags taller up to its content and
  stops; it never gets wider; the zoom button is dimmed; dragging the
  background moves it.
- **M6 Menus by eye.** App menu: About ‹name› first, alone above a separator.
  Help: the search field, then About ‹name›. Both in the importer too.
- **M7 Esc and ⌘W with a real keyboard.** Esc closes About; Esc in a licence
  window does nothing (or closes its find bar); ⌘W closes either.
- **M8 Quit during a job from About** (second pass, with F4). Start an export,
  make About key, press ⌘Q: the library window comes in front of About and
  the question is a sheet on it; Return and Esc keep exporting.

Not asked of the owner (README disclaims them): VoiceOver and Voice Control,
and macOS 15 and 26 (including Q-E6's scroll view clicks on 15).

## Second pass (2026-11-13)

Branch `feature/about-gus` at `20f18f8`, the fixes since `7138b18`. Read:
`Sources/PhotoUI/About/AboutView.swift`, `AboutText.swift`, the two catalog
entries, `Sources/PhotoCore/Import/QuitConfirmation.swift`,
`Sources/PhotoUI/QuitGuard.swift`, the quit path in
`Sources/PhotoApp/PhotoApplication.swift`, the About paragraph of
`docs/USER_GUIDE.md` and `status.md`'s **Review findings**. Seen: the
engineer's full-height snapshot with the files copied in (dark). No shell:
nothing run by me.

| Finding | Result | Evidence |
|---|---|---|
| F1 Footer View License | **Fixed** | Font and secondary style are on the two footer `Text`s only; all four buttons are one `ViewLicenseButton` (`.controlSize(.small)`), so they can't drift again. Snapshot: the footer button has the entries' size and primary title. Row 18 now Pass; light and Increase Contrast stay M1 |
| F2 Voice Control names (D-A7) | **Fixed** | `accessibilityInputLabels(["View License", "View ‹owner› License"])` on `ViewLicenseButton`, `accessibilityLabel` unchanged, no new strings. Spoken check stays unasked (README) |
| F3 Catalog comments (D-A8) | **Fixed** | Dedication and statement comments say "the project's name (the library app's name, also in the standalone importer)", identical in `AboutText.swift` and the catalog |
| I-3 User guide | **Done** | "**Help ▸ About** followed by the app's name", matching the app-menu sentence |

### Q3: where the quit confirmation goes

**Accepted, with one fix (F4).** Passing over the About and licence windows
is right. The HIG (Alerts; Sheets) asks for a sheet when the alert concerns a
particular window, and app-modal otherwise. The job a quit would stop is an
import or export that belongs to the library window (the importer's to its
import window), not to About, which is an auxiliary panel with no state. A
"Quit While Exporting?" sheet hanging off About would point the person at
the wrong place, and closing About with Esc or ⌘W would have to dismiss the
sheet first. With only About or licence windows left, a free-standing
app-modal alert is the correct fallback: the job has no window to attach to.
The rule is small, in PhotoCore, tested, and the importer already behaved
this way. Moving the sheet to another window does not break the keyboard
model: Return and Esc still keep the job going.

**F4: bring the host window forward before the sheet (should fix).**
When About is key, `confirmationWindow` returns the library window behind
it, and `WindowModal.run` calls `beginSheetModal(for:)` on it as it is. To my
knowledge AppKit does not order a sheet's parent window to the front, and I
couldn't confirm it either way. If it doesn't, About (520 pt wide and
centered on screen) can cover the top-center of the library window, which is
exactly where the sheet drops. In the worst case the library window sits on
another display or behind other apps' windows. Then ⌘Q seems to do nothing:
the app is waiting on a sheet nobody can see. HIG area: Alerts (people must
see a confirmation to answer it) and Feedback. Fix: in the library app's quit
path, when the chosen host isn't `NSApp.keyWindow`, call
`makeKeyAndOrderFront(nil)` on it before `QuitGuard.ask`. That is one line
at the call site, with no change to `QuitConfirmation.host`. The importer
asks on `CardImportModel.window` and gets the same treatment if its About can
cover it. Check it with `about quithost` followed by a print of the window
order or the key window (the host should be key and first), and by eye in M8.

M8 (quit during a job with About key) and M9 (⌘F on a non-Latin layout) in
`status.md` are accepted as manual checks. M8 now also confirms F4: the
sheet appears on the library window, and that window comes in front of
About.

**Second-pass verdict: Pass with one should-fix (F4).** F1–F3 and I-3 are
closed. Nothing else changed in the UI.

## Third pass (2026-11-13)

Branch `feature/about-gus` at `1804e7c`, the commits since `e45906b`. Read:
`Sources/PhotoUI/QuitGuard.swift`, `Sources/PhotoCore/Import/QuitConfirmation.swift`,
the two call sites (`PhotoApplication.applicationShouldTerminate`,
`CardImportModel.confirmQuit`), the `quithost` and `quitask` debug commands,
and `status.md` (**Debug script**, **Review findings** C6 and F4, M8). Checked
against the live HIG pages Sheets and Alerts. No shell: nothing run by me.

| Finding | Result | Evidence |
|---|---|---|
| F4 Host window forward before the sheet | **Fixed** | `QuitGuard.bringForward` runs inside `ask`, before `WindowModal.run`: when the host is not already key it walks `sheetParent` to the root window and calls `makeKeyAndOrderFront`, which brings the root and its sheets forward and makes the front sheet key. Being in `ask` rather than at one call site, the importer gets it too, which is what F4 asked. A no-op when the host is key, so the ordinary case (⌘Q from the library window) is unchanged. Script: front to back About, All Photos before; All Photos, About after, in both apps. "The host becomes key" was not seen (macOS refused to activate the test copy): stays in M8 |

### The stacked-sheet rule (C6): question on the front-most sheet

**Accepted.** The HIG (Sheets) says "Display only one sheet at a time from the
main interface" and, when something done in a sheet calls for another one,
to close the first. That rule is about task sheets chained from one another,
where closing the second leaves people in a sheet they didn't expect. It
doesn't fit here, for three reasons:

- **Closing the first sheet would cost the person their work.** The sheet up
  might be Export with settings half chosen, or the preset manager. Dismissing
  it to ask "Quit While Exporting?" means that Keep Exporting, the default
  answer, returns them to a window whose sheet is gone. The HIG's own reason
  for the rule ("they expect to return to the parent") is met better by
  stacking: Keep, Return or Esc takes them straight back to the sheet they
  were in.
- **A confirmation alert on a sheet is the platform's own pattern.** The
  standard save panel run as a sheet asks "Replace?" as an alert sheet on
  itself. The alert is short, has nothing to fill in, and goes away with one
  key. It is not a second task.
- **The alternatives are worse.** Asking on the window behind the sheet, as
  before C6, gets the alert queued by AppKit and ⌘Q seems to do nothing (no
  feedback). An app-modal alert works, but it loses the tie to the window
  whose job it would stop, and the HIG (Alerts; Modality) prefers a sheet when
  the question concerns one window.

The macOS section of Sheets also says "When a sheet opens, you bring its
parent window to the front", which is exactly what `bringForward` now does.
The 16-step bound on the chain only guards a loop; real chains are one or two
deep. Esc still keeps the job: the monitor ends the alert on its own
`sheetParent`, which is the first sheet when the alert is stacked.

### Improvement (judgment, not required for #179)

- **I-4 Quit while the app is inactive.** `bringForward` orders the host to
  the front of the app's windows but does not activate the app. ⌘Q always
  comes from the active app, but Quit from the Dock menu or a logout does not,
  and then the sheet may come down on a window behind another app's. The
  behavior predates this feature (the import and export questions have always
  been asked this way). If it's worth doing: call `NSApp.activate()` (macOS
  14+) in `ask` when `!NSApp.isActive`, before `bringForward`. Propose as a
  follow-up issue, not a fix on this branch.

**Third-pass verdict: Pass.** F4 is closed; the stacked-sheet rule is right
for the platform. No open design findings. Manual checks stay M1 to M8
(M8 now also covers "with a sheet already up": the question appears on that
sheet at once), plus the engineer's M9.

## Requirements issues (for the product manager)

- **RI-R1 (endorses the engineer's RI-E1; for #172).** LibRaw's View License
  opens its notices section, which names the LGPL 2.1 and points to
  `Sources/CLibRaw/LICENSE.LGPL`, a repository path that isn't in the bundle.
  To a person, a button called View License that opens a pointer to a file
  they can't reach is a dead end. The design treats this as #172's call: put
  the LGPL 2.1 text where the bundle's notices can show it (in LibRaw's
  section, or as a bundled file the window reads). Not blocking this feature;
  the button only appears once #172 lands.
- **RI-R2 (follow-up, proposed issue).** No `NSHumanReadableCopyright` in
  either Info.plist (status, Q-E2): Finder's Get Info shows no copyright.
  Proposed enhancement, "Copyright in the bundles' Info.plist", generated from
  `AppCopyright` or checked against it by a test so the three places can't
  drift.
