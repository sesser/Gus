# About window with a dedication: design

Owner: apple-ui-designer. Date: 2026-11-13.
Issue: #179. Status: complete. One requirements issue (RI-A1, not
blocking: the design proceeds on its stated assumption); assumptions in §11.

**Inputs.**

- Requirements: the PRD (issue #179's body, approved 2026-11-13), R1–R11
  and AC1–AC13, cited as "R‹n›" and "AC‹n›".
- Conventions: [`../ui-redesign/design.md`](../ui-redesign/design.md) (P1,
  N13 and E28: the Help menu keeps its search field and has no dead item),
  [`../../UI_REDESIGN.md`](../../UI_REDESIGN.md) §8 Appearance (only the
  library window is forced dark; Import and Settings follow the system), §9
  (title-style empty-state titles, sentences in the description), §10
  (accessibility, no tertiary text for labels).
- Code read on `feature/about-gus` at `d978648`:
  `Sources/PhotoApp/PhotoApplication.swift`,
  `Sources/PhotoImporter/ImporterApplication.swift` (both replace `.help`
  with nothing), `Sources/PhotoUI/HelpMenuProbe.swift`,
  `Sources/PhotoCore/Branding/AppBranding.swift` (`displayName`,
  `importerDisplayName`), `Support/Info.plist`, `Support/Importer-Info.plist`
  and `Support/Version.xcconfig` (both plists carry
  `CFBundleShortVersionString` and `CFBundleVersion`, today 0.1.0 and 1),
  `THIRD_PARTY_NOTICES.md` (LightCraft only on `develop`), README "License",
  and the string style of `Localizable.xcstrings` (English text as keys,
  straight apostrophes in most keys, curly quotes around names, positional
  `%1$@` where two arguments differ in kind).
- HIG read on 2026-11-13: The menu bar (app menu table: "About
  *YourAppName* — Displays the About window for your app, which includes
  copyright and version information… Don't include a version number";
  "Display the About menu item first… by itself in a group"; Help menu:
  additional items after a separator, keep the menu small). Apple's own
  pattern for a SwiftUI About window is WWDC24 session 10148, "Tailor macOS
  windows with SwiftUI" (a `Window` scene, minimize disabled, restoration
  disabled, title hidden, background drag enabled).
- APIs checked against Apple's documentation: `restorationBehavior(_:)`
  and `defaultLaunchBehavior(_:)` (Scene, macOS 15), `windowMinimizeBehavior(_:)`
  (View, macOS 15). The others named below are macOS 13–15 APIs the engineer
  confirms at build time (§10, Q-E1).

**Custom chrome: none.** Every surface is a system component: a SwiftUI
`Window` scene, `Text`, `Link`, small bordered `Button`s, `Divider`, a
scroll view, and `ContentUnavailableView`. One AppKit view is used, an
`NSTextView` for licence text (§6.2, justified there). No glass, no custom
backgrounds, no `Palette` colors: the window uses semantic system colors only.

---

## 1. Principle

The About window answers two questions a person may have about the app they
are running: *which version is this*, and *whose work is in it*. Both are
information, not a task, so the window behaves like the system's About
panel (small, fixed width, closes with Esc or ⌘W, no state of its own) and
reads top to bottom in that order: who the app is, who it thanks, and the
legal footing.

Why not the system panel with credits (`orderFrontStandardAboutPanel(options:)`
and an attributed credits string)? It would be the least code, but:

1. The owner ruled that this window replaces the system panel (Owner ruling 1,
   R8).
2. The panel can't hold a control that opens a licence (R6, R11); a link to a
   file inside the bundle would hand the text to whatever app opens `.md`
   files, leaving the app.
3. Its version line is fixed by AppKit ("Version X (Y)"), not R4's wording,
   and the debug script can't see or drive its credits (AC6 needs the URL a
   link would open).

So it is a SwiftUI `Window` scene of our own, built the way Apple's WWDC24
session builds one, shared by both apps from `PhotoUI` (R7).

## 2. Menus (R1, R7, R8; AC1, AC8, AC9)

### 2.1 Where the item lives

| App | App menu | Help menu |
| --- | --- | --- |
| Library app | **About ‹displayName›**, first, alone above a separator (replaces SwiftUI's system item: `CommandGroup(replacing: .appInfo)`) | Search field (system), then **About ‹displayName›** |
| Standalone importer | **About ‹importerDisplayName›**, same place | Search field (system), then **About ‹importerDisplayName›** |

- **Same title in both menus**, from the String Catalog key `About %@`
  filled with the running app's name (§2.3). No version number in the title
  (HIG The menu bar).
- **No keyboard shortcut.** The system About item has none, and nothing
  justifies spending one.
- **Help ▸ About is not a HIG-listed item.** The HIG puts About in the app
  menu only; the Help menu allows "additional items". The owner ruled for both
  (Owner ruling 1), and it does no harm as long as it is the same item doing
  the same thing. When `in-app-help` (#107) adds "‹name› Help", that item goes
  first and a separator goes between it and About (HIG Help menu: primary help
  first, additional items after a separator). Until then About is the Help
  menu's only item, with no separator.
- **Help ▸ Search stays** (UI redesign N13, E28): the Help menu is still the
  one AppKit treats as the help menu, so the search field stays at its top.
  `helpmenu` in both debug scripts must list `About ‹name›` and report the
  menu as the help menu.

### 2.2 Enablement and window state

The item is always enabled and needs no window: it reads **no focused value**
and no model. It opens a scene, so it is a `Commands` struct in `PhotoUI`
(working name `AboutCommands(appName:)`) that calls
`@Environment(\.openWindow)` with the About window's id. This is the
exception CLAUDE.md's menu rule allows by its own reasoning: the rule exists
because SwiftUI does not refresh a model passed into `Commands`; About has no
model and no state to refresh. It must work:

- with no key window (every window closed but the app still running, for
  instance the library window closed while a licence window is open);
- with a sheet up on the library or Import window;
- in the importer, which has no library model.

### 2.3 Which name

- **Menu items, window title, window header:** the running app's own name:
  `AppBranding.displayName` in the library app,
  `AppBranding.importerDisplayName` in the importer. This is the name in the
  app menu's title and in Hide and Quit, and the HIG asks for the same short
  name in all of them.
- **Dedication and the free-software statement:** `AppBranding.displayName`
  in both apps. These speak about the project, and the importer is part of
  it; "Gus stands on other people's work" is true of both binaries, and the
  GPL statement covers the project. (Assumption A-1; RI-A1 asks the product
  manager to confirm.)

Every occurrence comes from `AppBranding` through a `%@` argument; no
literal name appears in Swift or in the catalog (R1, AC2, R10).

## 3. The About window (R1–R5, R11)

### 3.1 Scene

One `Window` scene, id `about`, declared in `PhotoUI` and added by both apps
**after** their main window scene (a `Window` that comes first is the one
presented at launch).

| Property | Value | Why |
| --- | --- | --- |
| Instances | One. A `Window` scene is single by construction; `openWindow(id: "about")` on an open window brings it forward and makes it key (R1, AC1) | R1 |
| Title | `About %@` with the running app's name. The title text is not drawn (`toolbar(removing: .title)`, toolbar background hidden), because the header shows the app's name; the window still carries the title, so VoiceOver, Mission Control and `print` read it (AC1) | Matches the system About panel; Apple's WWDC24 pattern |
| Size | Width fixed at **520 pt**. Height ideal **640 pt**, minimum **400 pt**, maximum the content's full height. Resizes vertically only (`windowResizability(.contentSize)` with a fixed-width, flexible-height root frame) | §3.6 |
| Position | Centered on the active screen when opened (`defaultPosition(.center)`) | System panel behavior |
| Launch and restore | Never opens at launch (`defaultLaunchBehavior(.suppressed)`), never restored (`restorationBehavior(.disabled)`) | Information window, no state worth restoring |
| Minimize, full screen | Minimize off (`windowMinimizeBehavior(.disabled)`); zoom and full screen off (fixed width with content-size resizability disables full screen; if it doesn't, `windowFullScreenBehavior(.disabled)`) | It's always one menu choice away (WWDC24 10148) |
| Window menu | No "About ‹name›" item added to the Window menu (`commandsRemoved()`); the open window should also be left out of the Window menu's list, as the system panel is (Should; see Q-E4) | It is reached from the app and Help menus |
| Background drag | Enabled (`windowBackgroundDragBehavior(.enabled)`), since the title bar has no visible title to grab | WWDC24 10148 |
| Appearance | Follows the system (light, dark, Increase Contrast) like Import and Settings. Not forced dark: only the library window is (UI_REDESIGN §8) | HIG Dark Mode |
| Material | The standard window background. No glass, no `containerBackground` material: body text stays on a solid surface | Liquid Glass is for controls, not content |

### 3.2 Anatomy

```
┌──────────────────────────────────────────────┐
│ ● ● ●                                        │  title bar, title hidden
│                  [app icon]                  │  64 pt
│                     Gus                      │  .title2, semibold
│            Version 0.1.0 (build 1)           │  .callout, secondary, selectable
├──────────────────────────────────────────────┤  Divider
│ Gus stands on other people's work. Thank     │  .body          ┐
│ you to:                                      │                 │
│                                              │                 │
│ LibRaw                          libraw.org   │  headline · link│
│ Reads raw files macOS can't.                 │  .body          │
│ LGPL 2.1                     [View License]  │  callout · btn  │
│                                              │                 │  one scroll
│ darktable                    darktable.org   │                 │  region
│ Showed how to apply the lens corrections     │                 │
│ Fujifilm stores in its raw files. This app's │                 │
│ version was written after reading how        │                 │
│ darktable does it; no code was copied.       │                 │
│ GPL 3 or later                               │                 │
│ …LightCraft, GRDB, ExifTool…                 │                 │
│ ──────────────────────────────────────────── │  Divider        │
│ Copyright © 2026 Randy Sesser                │  .callout, sec. │
│ Gus is free software: you can redistribute   │  .callout, sec. │
│ it and/or modify it under the terms of …     │                 │
│ [View License]                               │                 ┘
└──────────────────────────────────────────────┘
```

Two parts:

- **Header (fixed, does not scroll).** Centered: app icon, name, version
  line. Top padding clears the title bar (about 28 pt; the icon is centered,
  so it never meets the window controls), 8 pt between icon and name, 2 pt
  between name and version, 16 pt below. The header is the window's
  identity; it stays visible however short the window is made.
- **Body (one vertical scroll region).** Leading-aligned, 20 pt side
  padding, 16 pt top and bottom: the dedication, the five entries, a
  divider, then the copyright and licence footer. Leading alignment because
  entries of two to four lines read badly centered; the header stays
  centered because it is a single short stack, as in the system panel.

The scroll region shows its scroller only when the content is taller than
the window (system overlay scrollers). In English at the ideal height the
dedication and the five entries are visible and the footer is one short
scroll away; at the content's full height nothing scrolls. That is a
deliberate tradeoff: the legal footer is in the window (R11) but the thanks
come first, which is the window's purpose (PRD Goal).

### 3.3 Header

| Element | Content | Style | Notes |
| --- | --- | --- | --- |
| Icon | `NSApp.applicationIconImage` at 64 × 64 pt | — | Decorative: hidden from VoiceOver. Under `swift run` it is the generic app icon; that is fine |
| Name | The running app's name (§2.3) | `.title2`, `.semibold`, primary | Accessibility header trait |
| Version | `Version %1$@ (build %2$@)` from `CFBundleShortVersionString` and `CFBundleVersion` (R4) | `.callout`, `.secondary` | Selectable (`textSelection(.enabled)`) so people can copy it into a report. **Left out entirely**, with no gap kept for it, when there is no bundle or either value is missing or empty (R4, AC5) |

### 3.4 Dedication and entries (R2, R3, R5, R6)

**Dedication.** `%@ stands on other people's work. Thank you to:` filled
with `AppBranding.displayName`; `.body`, primary, accessibility header
trait (it introduces the list). 12 pt below it, then the entries, 14 pt
apart.

**Entry.** Three lines, in this order, for each project in the record, in
the record's order (LibRaw, darktable, LightCraft, GRDB, ExifTool):

| Line | Leading | Trailing |
| --- | --- | --- |
| 1 | Project name: `.headline`, primary. From the record, not translated (`Text(verbatim:)`): proper names, and the R9 test matches them against the notices file and the README | The project's page as a SwiftUI `Link`, whose visible text is the URL without scheme or trailing slash (`libraw.org`, `darktable.org`, `exiftool.org`, `github.com/storytold/lightcraft`, `github.com/groue/GRDB.swift`); `.callout`; tooltip (`.help`) the full URL |
| 2 | One-line description (it may wrap): `.body`, primary | — |
| 3 | Licence name: `.callout`, `.secondary` | **View License**: small bordered push button (`.controlSize(.small)`), only for an entry whose licence requires a notice (LibRaw, LightCraft, GRDB) **and** whose text was found in the bundle (§5) |

Why these choices:

- **The link shows where it goes.** The app makes no network calls (R5);
  showing the address before someone clicks it is honest and needs no
  explanation. The visible text is the link's accessible name, so a Voice
  Control user can say what they see. Activating it opens the default
  browser through the system (`openURL`); the app fetches nothing, and the
  window renders the same with no network (AC6).
- **View License is a button, not a link.** It opens a window in the app;
  link styling is kept for things that leave the app. No ellipsis: it shows
  information and asks for nothing more (HIG Menus and Buttons, ellipsis
  only when more input follows).
- **The licence slot is always "the project's licence".** The descriptions
  carry the relationship (R3): included code, studied, reimplemented, an
  outside tool. darktable's and ExifTool's licence lines therefore read as
  the project's own licence, not as terms Gus uses them under; their
  descriptions say no code was copied and that ExifTool is not included
  (AC4). The PRD drafted those two licences in parentheses inside the
  sentence; moving them to the licence slot is a layout change, not a
  rewording.
- **No entry ever says "built on" or "includes"** for darktable, LightCraft
  or ExifTool (AC4). The strings in §8 are the PRD's approved wording.

Each entry is one accessibility container (`accessibilityElement(children:
.contain)`) labelled with the project name, so VoiceOver users move entry by
entry and hear the project before its link and button.

### 3.5 Copyright and licence footer (R11, AC13)

After the last entry: 20 pt, a `Divider`, 16 pt, then:

1. `Copyright © %1$@ %2$@` (year, holder): `.callout`, `.secondary`,
   selectable. The values come from one place the engineer chooses so the
   window and README can't drift (PRD engineer question; Q-E2).
2. 4 pt, then the free-software statement (§8 key S-GPL) filled with
   `AppBranding.displayName`: `.callout`, `.secondary`, wraps. Its wording is
   the README's "License" paragraph, so the app and the repository say the
   same thing.
3. 8 pt, then **View License** (same small bordered button), only when the
   bundle's `LICENSE` is found (§5). Before #172 lands, there is no button
   and the statement still shows (AC13).

The statement is the GPL's short notice, not licence text; the AC13 test
that keeps GPL text out of Swift and the catalog must look for the licence
itself (its preamble or "TERMS AND CONDITIONS"), not the phrase "GNU General
Public License", or it would fail on this string.

### 3.6 Size, resizing, localization

- **Fixed width, 520 pt.** Wide enough that each entry's first line holds a
  name and its address (the longest, `github.com/groue/GRDB.swift`, is about
  170 pt in `.callout`), narrow enough to read as an informational window.
  Width doesn't change with content; text wraps.
- **Height between 400 and the content's full height, ideal 640.** English
  needs about 750 pt for everything at once; German or French needs more.
  Rather than a window taller than a 13-inch display allows, the body
  scrolls and the person may stretch the window down to show it all. Not
  remembered between openings (restoration off).
- **No truncation anywhere.** Every text wraps (`fixedSize(horizontal: false,
  vertical: true)`); nothing is clipped to one line. A long translated
  address line wraps under the name rather than truncating.

## 4. Keyboard (R10, AC12)

| Key | Action |
| --- | --- |
| ⌘W (File ▸ Close) | Closes the About window (and, in a licence window, that window) |
| Esc | Closes the About window, as it closes the system About panel. Must work with nothing focused (on open, nothing is) — see Q-E3. Licence windows don't close on Esc: they are ordinary reading windows, and in a text view Esc belongs to the text system |
| Tab / ⇧Tab | With Keyboard Navigation on (System Settings), moves through the controls in reading order: each entry's link then its View License button, top to bottom, then the footer's View License. With it off, Tab does what it does in every Mac app (no controls to reach): that is "the usual way for system controls" (R10) |
| Space | Activates the focused link or button |
| Return | Nothing. There is no default button: nothing here is a confirmation |
| ⌘C, ⌘A | Copy and select in the selectable texts (version, copyright) and in licence windows |

No initial focus ring: the window opens with nothing focused, so it doesn't
look like a dialog waiting for an answer.

No Settings-like state: nothing in the window changes anything, nothing is
saved, and closing it loses nothing.

## 5. When a bundle file is missing (R4, R6, R11)

One rule, no feature flag: **a control is shown only when what it would show
is there.** The state before #172 lands is just "the files aren't in the
bundle", so the same code serves both, and when #172 lands the buttons
appear without a change here.

The About window decides each time it opens (reading the bundle is local and
cheap; nothing is cached across openings):

| Situation | Version line | Entry licence buttons | Footer View License |
| --- | --- | --- | --- |
| Built bundle, #172 landed, files intact | Shown | LibRaw, LightCraft, GRDB | Shown |
| Built bundle before #172 | Shown | None (names only) | None (statement only) |
| No bundle (`swift run`) | Absent | None | None |
| `CFBundleShortVersionString` or `CFBundleVersion` missing or empty | Absent | as the files allow | as the files allow |
| `THIRD_PARTY_NOTICES.md` missing or unreadable | as the plist allows | None | as the files allow |
| Notices present, one project's section not found | — | None for that entry; the others as found | — |
| `LICENSE` missing or unreadable | — | — | None |

- **Never an alert, never an error line in the About window.** The window is
  information; a missing file in a damaged bundle is not the reader's
  problem to solve, and the licence names and statement still say what
  applies. The packaging tests (AC7, AC13) are what catch a bundle shipped
  without the files.
- **darktable and ExifTool never get a View License button**, even if their
  sections exist in the notices file: their licences don't require Gus to
  carry a notice (R6, PRD A3).
- **A file that disappears after the About window checked** (between the
  window opening and the button being clicked): the licence window opens and
  shows a `ContentUnavailableView` titled "Can't Show the License" with the
  description "The license text is missing from this copy of %@." (§8). No
  alert.

## 6. Licence windows (R6, R11; AC7, AC13)

### 6.1 Form

Each **View License** opens a window for that one licence: "LibRaw
License", "LightCraft License", "GRDB License", and "‹displayName›
License" for the footer's (`%@ License`).

- **One window per licence, single instance per licence.** A
  `WindowGroup(id: "license", for: ‹licence id›)`: choosing View License
  again for the same project brings its window forward; choosing another
  project's opens a second window beside it, so someone comparing two
  licences can.
- **Why a window, not a sheet or an inline disclosure.** Licence texts are
  long (the GPL is about 35 KB, LGPL 2.1 about 26 KB) and are read, searched
  and copied: that wants a resizable window. A sheet would be modal for no
  reason (reading a licence isn't a task to finish) and couldn't be larger
  than the 520 pt About window without looking wrong. An inline disclosure
  would make the About window's scroll region tens of thousands of points
  tall and bury the other entries.
- Titled standard window (title shown), default **640 × 720 pt**, minimum
  **420 × 320 pt**, freely resizable, minimize allowed, full screen not
  needed (leave the system default), centered on first open, never restored
  (`restorationBehavior(.disabled)`), never presented at launch, no "New …
  Window" item in the File menu and no item added to the Window menu by the
  scene (`commandsRemoved()`). The open window is listed in the Window menu
  like any window, since people may leave it open while working.
- Independent of the About window: closing About leaves licence windows
  open.
- Appearance follows the system.

### 6.2 Content

- The text exactly as stored in the bundle, with no rendering, editing or
  reflow of its own lines: for a project, its section of the bundled
  `THIRD_PARTY_NOTICES.md` (byte-identical, AC7; the section's Markdown is
  shown as the characters it is, since legal text is shown verbatim); for
  the app, the bundled `LICENSE` (AC13).
- In an **`NSTextView`** (non-editable, selectable) in its scroll view,
  filling the window; text inset about 16 pt; font
  `NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)`; colors
  `textColor` on `textBackgroundColor`, so light, dark and Increase Contrast
  are the system's; lines wrap to the window width when it is narrower than
  the text. Monospaced because licence files are hand-wrapped plain text
  laid out in columns and indents; 80 columns at 12 pt fit the default
  width.
- **Why AppKit here.** SwiftUI has no read-only, selectable text view that
  handles 35 KB of text well: `Text` with `textSelection` lays out the whole
  string on the main thread and supports neither Find nor partial
  selection well, and `TextEditor` can't be made read-only without dimming
  it. `NSTextView` lays out lazily, selects and copies normally, and can use
  the find bar.
- **Find (Should).** ⌘F shows the text view's find bar (`usesFindBar`) if
  the app's Edit menu has, or gains, a Find item that reaches it. If that
  would collide with the library window's own ⌘F handling, leave Find out
  and record why (Q-E5); selection and copy are the Must.
- VoiceOver reads it as a text area with the window's title as context.

## 7. VoiceOver summary (R10)

| Element | Role | Label / value |
| --- | --- | --- |
| About window | window | Title "About ‹name›" |
| Icon | hidden | — |
| App name | static text, header | "‹name›" |
| Version line | static text | "Version 0.1.0 (build 1)" |
| Dedication | static text, header | the sentence |
| Entry | group (container) | label: project name |
| Entry link | link | its visible address; hint is the system's |
| Entry View License | button | label "View ‹project› License" (§8 key), so the three are told apart in the rotor; the visible title stays "View License" |
| Copyright, statement | static text | as shown |
| Footer View License | button | label "View ‹displayName› License" |
| Licence window | window, text area | title "‹project› License"; the text |

## 8. Strings (String Catalog keys, English values)

All in `Sources/PhotoUI/Resources/Localizable.xcstrings`, added by hand.
Key = English value. Each needs the comment given (the catalog's comments
are what a translator sees). `%@` arguments are filled from `AppBranding`
or the bundle, never from a literal.

| Id | Key (= English) | Argument(s) | Comment |
| --- | --- | --- | --- |
| S-ABOUT | `About %@` | running app's name | App menu and Help menu item, and the About window's title; the argument is the app's name |
| S-VERSION | `Version %1$@ (build %2$@)` | short version, build | About window: the version line, from the bundle; left out when either is missing |
| S-DEDICATION | `%@ stands on other people's work. Thank you to:` | `AppBranding.displayName` | About window: the dedication above the list of projects; the argument is the app's name |
| S-LIBRAW | `Reads raw files macOS can't.` | — | About window: what LibRaw (a library included in the app) does for it |
| S-DARKTABLE | `Showed how to apply the lens corrections Fujifilm stores in its raw files. This app's version was written after reading how darktable does it; no code was copied.` | — | About window: what darktable gave the app. Its approach was studied; none of its code is in the app. Keep that distinction in translation |
| S-LIGHTCRAFT | `The formulas behind brush and color range masks, reimplemented in Swift.` | — | About window: what LightCraft gave the app. Formulas were reimplemented, not code copied |
| S-GRDB | `The database toolkit under the catalog.` | — | About window: what GRDB (a library included in the app) does for it |
| S-EXIFTOOL | `Reads metadata when it is installed; not part of the app.` | — | About window: ExifTool is an optional separate program the app uses when present; it is not included |
| S-LIC-LGPL | `LGPL 2.1` | — | About window: LibRaw's license, as a short name |
| S-LIC-GPL3 | `GPL 3 or later` | — | About window: darktable's license, as a short name |
| S-LIC-MIT | `MIT` | — | About window: the MIT License, as a short name (LightCraft, GRDB) |
| S-LIC-EXIFTOOL | `Artistic License / GPL, as ExifTool states` | — | About window: ExifTool's license as ExifTool describes it |
| S-VIEW | `View License` | — | About window: button that opens a project's or the app's full license text in its own window |
| S-VIEW-AX | `View %@ License` | project name, or `AppBranding.displayName` | About window: VoiceOver label of the View License button; the argument says whose license |
| S-LIC-TITLE | `%@ License` | project name, or `AppBranding.displayName` | Title of the window showing a license text, e.g. “LibRaw License” |
| S-COPYRIGHT | `Copyright © %1$@ %2$@` | year, holder | About window: the app's copyright line; the arguments are the year and the copyright holder |
| S-GPL | `%@ is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It is distributed in the hope that it will be useful, but without any warranty; see the license for details.` | `AppBranding.displayName` | About window: the app's free-software statement (the GPL's short notice, as in the README). Not the license text itself |
| S-MISSING-T | `Can't Show the License` | — | License window: title when the license file is missing from the app |
| S-MISSING-D | `The license text is missing from this copy of %@.` | running app's name | License window: description when the license file is missing; the argument is the app's name |

Not in the catalog, on purpose: project names and link addresses (data from
the record, shown verbatim; R9 compares the names with the notices file and
the README), the licence texts themselves (read from the bundle, never typed:
R11, AC13), and the holder's name if the engineer keeps it beside the README
value (Q-E2).

## 9. Checks the review will need

For the design review (step 4) and QA, the debug scripts of **both** apps
need, at least (names are the engineer's):

- open and close the About window through each menu item (`menupress` already
  covers the items; `helpmenu` lists the Help menu);
- print the About window: title, frame size, whether it resizes and in which
  axis, the version line or its absence, each entry's name, description,
  licence and address, and which View License buttons exist;
- activate an entry's link and print the URL it would open **without**
  opening a browser (AC6);
- open a licence window and print its title and the SHA-256 or byte count of
  the text it shows (AC7, AC13);
- count windows after opening About twice (AC1, AC9: one window).

Things only a person can judge (to become M-checks in `review.md`): the
window's look in light, dark and Increase Contrast; the header clearing the
window controls; Esc and ⌘W; Tab order with Keyboard Navigation on; that
the system panel never appears from either menu in either app.

## 10. Questions for the engineer

Answer in `status.md`; come back to me only if an answer changes something
above.

- **Q-E1 (APIs).** Confirm at build time, against the macOS 15 minimum:
  `toolbar(removing: .title)`, `toolbarBackground(.hidden, for:
  .windowToolbar)`, `windowBackgroundDragBehavior(_:)`,
  `windowFullScreenBehavior(_:)`, `commandsRemoved()`, `defaultPosition(_:)`,
  `WindowGroup(id:for:)` bringing an existing window for the same value
  forward. If one is missing on 15, say which and what you used instead.
- **Q-E2 (one source for the copyright).** Where the year and holder live so
  the window and README can't drift (PRD's engineer question). The design
  only needs two values for S-COPYRIGHT.
- **Q-E3 (Esc).** How Esc closes the About window with nothing focused.
  Prefer a mechanism that doesn't add an invisible control to the
  accessibility tree.
- **Q-E4 (Window menu list).** Whether the open About window can be left out
  of the Window menu's window list (as the system panel is). Should, not
  Must: say if it can't.
- **Q-E5 (Find in licence windows).** Whether ⌘F can reach the text view's
  find bar without disturbing the library window's ⌘F. If not, leave it out
  and say why.
- **Q-E6 (scroll view).** The About window has no toolbar, so CLAUDE.md's "no
  SwiftUI `ScrollView` under the toolbar" rule doesn't strictly apply; check
  clicks on links and buttons inside it on macOS 26, and use
  `AppKitScrollView` (moved to `PhotoUI`) if they misbehave.

## 11. Assumptions

- **A-1** (RI-A1). Menu items, window title and header use the running app's
  name; the dedication and the free-software statement use
  `AppBranding.displayName` in both apps (§2.3).
- **A-2.** Both apps show the same five entries with the same wording,
  including the importer, which doesn't use masks or lens corrections: the
  entries describe what each project gave the Gus project, and the code is in
  both binaries (R7, AC8).
- **A-3.** The licence names in §8 are the PRD's draft moved out of
  parentheses into the licence slot (§3.4); no wording changed.
- **A-4.** The free-software statement keeps "see the license for details"
  before #172 lands, as in the README, even though the window then has no
  button for it: the licence still exists in the repository, and one wording
  that doesn't change when #172 lands is better than two.

## 12. Requirements issues (for the product manager)

- **RI-A1 (not blocking).** In the standalone importer, should the dedication
  and the GPL statement name the project ("Gus stands on…", "Gus is free
  software…") or the importer ("Gus Importer stands on…")? The HIG decides
  the menu items and title (the app's own short name); the body text is a
  product call. The design proceeds on A-1 (the project's name); a ruling the
  other way changes only which `AppBranding` value two `%@` arguments take.

## 13. Rulings

Rulings on the engineer's readings in `status.md` ("Where I read the design
one way", D-1 to D-6), made at design review on 2026-11-13. Each is cited as
D-A‹n›.

### D-A1 Heights are the window's (status D-1): accepted

400 pt minimum and 640 pt ideal are the window's outer heights, title bar
included; the view's own limits subtract the title bar. The maximum is the
content's height (691 pt in English without licence buttons, 734 with them),
as §3.6 intends. No change.

### D-A2 Lines within an entry are 3 pt apart (status D-2): accepted

§3.4 gave only the space between entries (14 pt). 3 pt between an entry's
lines keeps each entry reading as one block against the 14 pt between
entries. No change.

### D-A3 Header top (status D-3): accepted

4 pt under the title bar (the icon's canvas about 36 pt from the window's
top on macOS 27.2) replaces "about 28 pt". The icon is centered, so it never
meets the window controls; the larger figure only follows from the title
bar's real height. No change.

### D-A4 "Can't Show the License" has no symbol (status D-4): accepted

A `ContentUnavailableView` with a title and description and no image is
right for a state that should never be seen in a healthy bundle. A symbol
would add weight to a rare, non-actionable state. No change.

### D-A5 Catalog keys with plain `%@` (status D-5): accepted; §8 amended

`String(localized:)` builds the key from the interpolation with plain `%@`,
so the keys are `Version %@ (build %@)` and `Copyright © %@ %@`, and the
English values carry the positional `%1$@ … %2$@` so a translator can
reorder. This is how the catalog's other two-argument strings work. Read
§8's S-VERSION and S-COPYRIGHT key column as those plain-`%@` keys; the
English text is unchanged.

### D-A6 The app's licence window title in the importer (status D-6): accepted

"Gus License" (the project's name, `AppBranding.displayName`) in both apps:
the licence belongs to the project, which the importer is part of (RI-A1's
ruling). The missing-file description names the running app ("this copy of
‹importerDisplayName›") because it is that copy that is damaged. Both as §6.1
and §8 say.

### D-A7 Voice Control names for View License (amends §7)

§7 gave the entry buttons the accessibility label "View ‹project› License"
while the visible title stays "View License". That label doesn't contain the
visible words in order, so a Voice Control user saying what they see ("click
View License") isn't matched by name. Keep the label for VoiceOver, and add
`accessibilityInputLabels` with the visible title first and the long form
second (`["View License", "View ‹project› License"]`; for the footer,
`["View License", "View ‹displayName› License"]`). Both strings are already
in the catalog (S-VIEW, S-VIEW-AX).

### D-A8 Catalog comments name the right argument (amends §8)

S-DEDICATION's and S-GPL's arguments are the project's name
(`AppBranding.displayName`) in both apps, not the running app's (RI-A1's
ruling). Their translator comments say "the argument is the project's name",
so a translator doesn't assume "Gus Importer" could appear there.
