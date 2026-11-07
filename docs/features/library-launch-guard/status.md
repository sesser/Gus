# Library launch guard: implementation status

Owner: swift-macos-engineer. Bug fix (no `prd.md` or `design.md`,
`docs/WORKFLOW.md` "Bug fixes") for the roadmap row library-launch-guard
(`docs/roadmap.md`, Now). Branch `bug/library-launch-guard`, cut from
`develop` at `42a13e0`.

**Status: Done.** Code review (`code-review.md`) and the designer's review
(`review.md`) are in; their findings are fixed (Review findings, below).
Next: their confirmation, then QA.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `42a13e0`). Copy `build/Gus.app`, change its
`CFBundleIdentifier` to `<release id>.debugtest` and re-sign it, as QA does
(`.claude/agents/qa-tester.md`). Start the copy without `--library-root`:
`open <copy>`, a double-click, or its executable with or without
`--debug-script`.

**Expected.** A test copy never opens the owner's library.

**Actual.** It opens the standard library,
`~/Library/Application Support/<app folder>/Library` with previews in
`~/Library/Caches/<release id>/Previews`, creating them if missing, and
takes the library lock. It happened once during QA on 2026-11-06 for about
3 minutes; nothing in the catalog changed
(`docs/features/ui-redesign/qa.md`, "Incident in this QA run"). PR #41 put
the rule in the docs and agent prompts only.

**Root cause.** The bundle identifier separates preferences only. The data
and cache folders come from fixed names in `AppBranding`
(`appSupportDirectoryName`, `cacheDirectoryName`), and `LibraryModel.open`
used them for every launch without `--library-root`. Nothing in the app
knew what a test launch was.

**Owner's rulings (2026-11-07).**
1. A launch is a test launch when (a) the running bundle's identifier is not
   the release identifier (`PRODUCT_BUNDLE_IDENTIFIER`, that is
   `AppBranding.bundleIdentifier`), or (b) `--debug-script` or
   `--benchmark-scroll` is passed. A test launch without `--library-root`
   is refused.
2. Refusing means: a message on standard error, an alert saying
   `--library-root` is required, then quit, before the catalog, preview
   cache, sidecar sync or anything else under the real library is opened or
   created.
3. **No bundle identifier** (`swift run PhotoApp`, a bare executable): refused
   without `--library-root`, like any identifier other than the release one
   ("Yes, refuse it"). This was the engineer's reading of rule (a), which the
   owner confirmed; no code change came of it.
4. **No alert in a scripted launch** (DQ1, option (b)): when a refused launch
   has `--debug-script` or `--benchmark-scroll`, it writes to standard error
   and exits 64 without the alert, so a script ends on its own. A refused
   launch without those flags (a test copy started by a person) still shows
   the alert ("Yes, skip alert").

**Tests that fail without the fix.**
- `LibraryLaunchGuardTests` (Swift Testing, 10 tests) pins every case of
  the rule, including whether a refusal shows the alert; on `develop` the
  rule does not exist.
- End to end, the scripted reproduction below: the `develop` build of a
  `.debugtest` copy, started under a scratch home without `--library-root`,
  creates the standard library there; the branch's build creates nothing.

## The fix

- `Sources/PhotoCore/Launch/LibraryLaunchGuard.swift`: the rule,
  `decide(bundleIdentifier:releaseIdentifier:options:)` →
  `.allowed` / `.refused(.notReleaseBundle(identifier:) | .scriptedLaunch,
  showsAlert:)`, where `showsAlert` is false when `--debug-script` or
  `--benchmark-scroll` was passed (ruling 4), with the release identifier
  defaulting to `AppBranding.bundleIdentifier`,
  and the standard-error text (`diagnostic(for:)`, not localized: it is for
  whoever started the process from a shell).
- `Sources/PhotoCore/Launch/LaunchOptions.swift`: moved from PhotoUI
  unchanged (commit `740d560`) so the rule and its tests can take parsed
  options; doc comment names the guard.
- `Sources/PhotoApp/AppLauncher.swift`: now the `@main` type. `main()` asks
  the rule first. Refused: writes the diagnostic to standard error; then, if
  `showsAlert`, shows a standard `NSAlert` (title "Can't Open the Library",
  reusing the catalog failure view's string; message "Test copies of %@
  must be started with --library-root <folder>. Your library wasn't
  opened."; one button, Quit), then `exit(EX_USAGE)` (64). Allowed:
  `PhotoApplication.main()`.
- `Sources/PhotoApp/PhotoApplication.swift`: `@main` removed. The catalog
  failure view's title now carries the shared comment (F1.3), so its `Label`
  takes a `Text(_:comment:)`; it looks the same.
- `Sources/PhotoApp/Model/LibraryModel.swift`: `open` checks the same rule
  and stops with `preconditionFailure` if refused. The launcher makes this
  unreachable; it only keeps a future caller from reaching the standard
  library.
- `Localizable.xcstrings`: two new keys (the message, with the product name
  as `%@` from `AppBranding.displayName`; "Quit").
- `docs/USER_GUIDE.md`, "Development options": what a test launch is and
  what happens without `--library-root`.

### Ordering: the guard runs before anything touches the library

By reading the code:
- The standard locations are resolved only by
  `DataDirectoryMigrator.migrateStandardLocations` and
  `LibraryLocations.standard` (both `url(for:in:appropriateFor:create: true)`,
  which creates `Application Support` and `Caches` if needed). In the app
  target both are called only from `LibraryModel.open`; `photocli` and
  `photobench` are separate executables.
- `LibraryModel.open` is called only from `LibraryLoader.init`, which runs
  when SwiftUI builds `PhotoApplication` (its `@State`), which happens only
  inside `PhotoApplication.main()`, which `AppLauncher.main()` calls only
  after the rule allows the launch. Swift globals and statics are lazy, so
  nothing runs before `main()`. The catalog, preview service, look-up table
  store, sidecar sync, card import model and library lock are all built
  from `LibraryModel.open`'s locations.

By running it (below): with `CFFIXED_USER_HOME` set to an empty scratch
folder, Foundation resolves `Application Support` and `Caches` inside it
(checked with a three-line script first). A refused launch left that folder
**completely empty**, not even `Library/` was created, so neither the
migrator nor `LibraryLocations.standard` ran. The unfixed build, started
the same way, created the whole library there.

### Standalone importer

Left out. It has no library: `CardImportModel.library` is nil, its presets
live in its own preferences (`DefaultsMetadataPresetStore`), and the only
per-user path it reads is the default destination `~/Pictures`. Nothing in
`Sources/PhotoImporter` or `Sources/PhotoUI` resolves the data or cache
folders.

## Build and test

| | Baseline (`42a13e0`) | Latest (branch) |
|---|---|---|
| `swift build` | clean | clean, no warnings |
| `swift test` | 562 tests, 98 suites, pass (1 known issue) | 572 tests, 99 suites, pass (same 1 known issue) |
| `Scripts/build-app.sh` | | builds; executable SDK 27.2; both new strings in `en.lproj/Localizable.strings` |

`LocalizationTests` and `BrandingTests` pass with the new strings.

## Checks

| Item | How | Result |
|---|---|---|
| Rule: release id, no flags → allowed | `LibraryLaunchGuardTests.releaseBundleWithoutFlagsOpensTheStandardLibrary` | Pass |
| Rule: release id + `--library-root` → allowed | `releaseBundleWithLibraryRootIsAllowed` | Pass |
| Rule: other id, no `--library-root` → refused; alert only without `--debug-script` / `--benchmark-scroll` | `otherBundleWithoutLibraryRootIsRefused` | Pass |
| Rule: other id + `--library-root` → allowed | `otherBundleWithLibraryRootIsAllowed` | Pass |
| Rule: release id + `--debug-script` / `--benchmark-scroll` → refused without the alert; with `--library-root` (either order) → allowed | `releaseBundleWithScriptNeedsLibraryRoot` (2 cases) | Pass |
| Rule: no bundle id → refused (alert only without a script); with `--library-root` → allowed | `noBundleIdentifierIsNotTheReleaseIdentifier` | Pass |
| Rule: `--library-root` with no value names no library | `libraryRootWithoutAValueDoesNotCount` | Pass |
| Rule defaults to `AppBranding.bundleIdentifier` | `defaultReleaseIdentifierIsTheBrandedOne` | Pass |
| Diagnostic names `--library-root` and the identifier | `diagnosticNamesTheMissingOption` | Pass |
| Options parse the three switches | `optionsParseTheSwitchesTheGuardReads` | Pass |
| D1. `.debugtest` copy **with** `--library-root` and a script works as before | debug script, below | Pass |
| D2. `.debugtest` copy, no arguments → refused at the alert, nothing created | below | Pass |
| D3. `.debugtest` copy, `--debug-script` only → refused, exits 64 at once without the alert, nothing created | below (second run) | Pass |
| D4. `.debugtest` copy, `--benchmark-scroll` only → as D3, and no report | below (second run) | Pass |
| D5. Unfixed build (`42a13e0`) reproduces the bug | below | Reproduced |
| D6. Real library unchanged across all of the above | below | Unchanged |
| M1. The alert's look and its Quit button | manual, for QA / the owner (`review.md` M1) | Open |
| M2. Release-identifier launch with `--debug-script` and no `--library-root` is refused at run time | manual, optional | Open |
| M3. VoiceOver reads the alert | manual, for QA / the owner (`review.md` M2) | Open |
| M4. `swift run PhotoApp` with no arguments is refused | manual, for QA / the owner (`review.md` M3) | Open |

### Debug-script results (2026-11-07)

First run, before ruling 4 (DQ1), at `b5da746`. Second run, after it, at
the commit that records this section; same setup with a fresh copy.

Setup: `Scripts/build-app.sh`; a copy with
`CFBundleIdentifier` `me.sesser.gus.debugtest`, re-signed ad hoc; a scratch
library from `photobench generate --jpeg 12` (212 files) and
`photobench import`. Every launch ran the copy's executable directly with
`CFFIXED_USER_HOME=<empty scratch folder>`, so even a wrong guard could only
have opened a library inside the scratch folder. No launch used the release
identifier, so the owner's preferences domain was never involved.

- **D1.** `--library-root <scratch lib> --debug-script "wait 3; print title;
  snapshot …; quit"`: printed `All Photos | 212 photos`, wrote the snapshot
  (grid of the scratch library), exit 0; the scratch home stayed empty.
- **D2–D4.** No arguments; `--debug-script "wait 2; quit"`;
  `--benchmark-scroll <file>`. Each printed on standard error
  `Refusing to open the standard library: bundle identifier
  me.sesser.gus.debugtest is not the release identifier me.sesser.gus. Test
  launches must pass --library-root <folder>. Nothing was opened; quitting.`,
  printed nothing on standard output, waited at the alert until `timeout`
  ended it (exit 124), and left its scratch home empty. No benchmark report
  was written. One of the no-argument runs exited 64 within 12 s: the alert
  had been answered with Quit, most likely by whoever was at the Mac (the
  alert comes to the front); two reruns waited at the alert as expected.
- **Second run (ruling 4).** `--debug-script "wait 2; quit"` and
  `--benchmark-scroll <file>` without `--library-root`: the same standard
  error line, then exit 64 in under a second with no alert; nothing on
  standard output, no report, scratch homes empty. No arguments: the same
  line, then waited at the alert until `timeout` (6 s, exit 124); scratch
  home empty. D1 again: `All Photos | 212 photos`, exit 0, scratch home
  empty. The real folders' listing was identical before and after, and
  nothing in them was newer than a fresh marker.
- **Third run (after the review fixes).** No arguments, the same way: the
  same standard error line, waited at the alert until `timeout` (6 s, exit
  124), nothing on standard output, scratch home empty; the real folders
  unchanged against a fresh marker. The bundle's `Localizable.strings` has
  the new message and no longer the old one.
- **D5.** The `develop` build (`42a13e0`, built in a scratch worktree), as a
  `.debugtest` copy, `--debug-script "wait 3; print title; quit"` without
  `--library-root`: printed `All Photos | 0 photos` and created
  `Library/Application Support/Gus/Library/{catalog.sqlite, -wal, -shm,
  library.lock, LUTs}` and `Library/Caches/me.sesser.gus/Previews` in its
  scratch home: the incident, reproduced safely.
- **D6.** Before the first launch I recorded the real data and cache
  folders (`stat` to depth 2) and touched a marker file. After the last
  launch the listing was identical and `find -newer <marker>` found nothing
  under either folder. (The owner's release app was running on that library
  throughout, so this check alone could not prove much; the scratch-home
  setup is what made the runs safe.)

### Manual checks (for QA or the owner)

Each runs a launch the guard refuses (no `--library-root`). D2 showed such
a launch creates nothing; to be doubly safe, note the modification times of
`~/Library/Application Support/<app folder>/Library` before and after.

- **M1.** (`review.md` M1.) Start a `.debugtest` copy with `open -n <copy>`
  (no `--args`). Expect the alert in front of other windows, with the app's
  icon, the title "Can't Open the Library", the message "Test copies of
  <app name> must be started with --library-root <folder>. Your library
  wasn't opened." on two or three lines without truncation, and one
  accent-colored Quit button. Return quits; clicking Quit quits. No library
  window and no app menus appear; the Dock icon goes away after Quit.
- **M2.** Optional. The release bundle with `--debug-script "quit"` and no
  `--library-root` should print the reason "--debug-script or
  --benchmark-scroll was passed" on standard error and exit 64 at once,
  with no alert. Not run here: a release-identifier launch shares the
  owner's preferences domain, and the owner's copy was running. The unit
  tests cover this branch of the rule and the launch code path is the same
  as D3–D4.
- **M3.** (`review.md` M2.) With VoiceOver on (⌘F5), repeat M1. VoiceOver
  should read the title, then the message, and land on Quit. Turn
  VoiceOver off after.
- **M4.** (`review.md` M3.) From Terminal, `swift run PhotoApp` (no bundle
  identifier) with no arguments. Expect the standard error line in
  Terminal, the alert visible (in front, or reachable from its Dock icon if
  macOS declines to activate a process started from a shell), and exit
  status 64 after Quit (`echo $?`).

## Design questions

- **DQ1. The alert in a scripted launch.** `NSAlert.runModal` waits for a
  click, so a scripted launch from a shell that forgets `--library-root`
  does not end until someone answers the alert or the process is killed
  (D3, D4). The library is safe either way. Options: (a) keep it as built,
  always the alert (cost: none; a script hangs until killed, which is
  visible and makes the mistake obvious); (b) skip the alert when
  `--debug-script` or `--benchmark-scroll` was passed: standard error and
  exit 64 only (cost: one condition; scripts end at once, but the person at
  the Mac sees nothing); (c) show the alert, but close it after a time-out
  in scripted launches (cost: a timer and a choice of delay; more code for
  little gain). Recommendation: (b), since a scripted launch is read from
  its standard error, and the alert is for launches a person started.
  **Resolved: (b), owner, 2026-11-07** ("Yes, skip alert"); ruling 4 in the
  Bug section. Built and checked (second run above).
- **DQ2. Alert copy.** The first message was "Test copies of %@, and
  launches with --debug-script or --benchmark-scroll, must be started with
  --library-root <folder>. Nothing was opened." Since ruling 4, scripted
  launches never see the alert, so the flags clause reached no one who used
  them. **Resolved by the designer's review** (`review.md` F1): the message
  is now "Test copies of %@ must be started with --library-root <folder>.
  Your library wasn't opened."; title and button unchanged.

## Review findings

| Finding | From | What was done |
|---|---|---|
| C1. `Package.swift` PhotoUI target comment still listed launch options | `code-review.md`, nit | Fixed: "launch options" removed from the comment |
| C2. Trailing blank line at the end of `LibraryLaunchGuard.swift` | `code-review.md`, nit | Fixed |
| F1.1 Alert message | `review.md`, low | Fixed: the new message in the catalog and in `AppLauncher.refuse`; the old key removed |
| F1.2 Message comment | `review.md`, low | Fixed: says to keep `--library-root <folder>` as is |
| F1.3 Title comment | `review.md`, low | Fixed: the shared comment in the catalog and at both call sites (`AppLauncher.refuse`, `LibraryErrorView`) |
| F1.4 Status wording | `review.md`, low | Fixed: The fix and M1 quote the new message; the designer's M1–M3 are this file's M1, M3 and M4. `USER_GUIDE.md` quotes no alert text, so it needs no change (`review.md` R12) |
| I1. Escape to answer the alert | `review.md`, improvement | Not taken, on the coordinator's instruction: Return and the Quit button answer it, and the alert is for developers only |

After the fixes: `swift build` clean, `swift test` 572 tests in 99 suites
pass (same 1 known issue; `LocalizationTests` and `BrandingTests` pass),
`Scripts/build-app.sh` builds, and the third run above.

## Requirements issues

None. `photocli` and `photobench` also fall back to the standard library
without `--library-root` (USER_GUIDE "Scripting"); the ruling is about the
app, so they are unchanged. If the owner wants the same guard there, that
is a new roadmap row.

## README

- No change to requirements or build commands.
- Layout: `LaunchOptions` moved from `Sources/PhotoUI` to
  `Sources/PhotoCore/Launch/`, next to the new `LibraryLaunchGuard`.
  `CLAUDE.md`'s Layout paragraph for PhotoUI lists `LaunchOptions`; that
  paragraph is the owner's (proposed change in the report). The README does
  not mention it.
