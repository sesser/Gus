# Library launch guard: code review

Owner: code-reviewer. Date: 2026-11-07. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/library-launch-guard`, 42a13e0..09ad984 (740d560 the move of
`LaunchOptions`, f02f986 the rule, b5da746 the launcher, 09ad984 no alert in
scripted launches; 0d85dfd and 913d798 are docs). Build and tests:
`swift build` clean; `swift test` 572 tests in 99 suites passed, 1 known
issue (the pre-existing `LiveSessionTests` `withKnownIssue`).

Spec: no `prd.md` or `design.md` (bug fix); the **Bug** section of
`status.md` with the owner's rulings of 2026-11-07, and the
library-launch-guard row in `docs/roadmap.md`.

## Verdict

Ready to merge. The guard runs before anything can resolve, migrate or
create the standard data and cache folders, applies exactly the owner's four
rulings, and `LibraryModel.open` backs it up as its first statement. Two
nits, both comments or whitespace; nothing blocks.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Nit | `Package.swift:25-26` | The PhotoUI target's comment still lists "launch options" among what it holds; 740d560 moved `LaunchOptions` to `Sources/PhotoCore/Launch/`. | Someone looking for the launch options, or deciding where the importer gets them, goes to PhotoUI and finds nothing. (`CLAUDE.md`'s Layout paragraph for PhotoUI, line 195, has the same stale mention; that paragraph is the owner's, see Follow-up for the main session.) | Layout kept true |
| C2 | Nit | `Sources/PhotoCore/Launch/LibraryLaunchGuard.swift:73` | The file ends with a blank line after the closing brace (`}\n\n`); the other files in `PhotoCore` end with a single newline. | None at run time; a stray line in the next diff that touches the file's end. | Surrounding style |

## Questions

None for the designer or the product manager from this review. The alert's
copy (DQ2) is the designer's and is ruled in `review.md` (F1).

## Checked and fine

- **Nothing reaches the standard library before the guard.** The standard
  folders are resolved only by `DataDirectoryMigrator.migrateStandardLocations`
  and `LibraryLocations.standard`; in the app the only caller of either is
  `LibraryModel.open`, whose only caller is `LibraryLoader.init`, built as
  `PhotoApplication`'s `@State` inside `PhotoApplication.main()`, which
  `AppLauncher.main()` calls only after `.allowed`. `photocli` reaches
  `LibraryLocations.standard` through `CommandRegistry` in its own process
  (unchanged, out of the ruling's scope, noted in status.md). Swift globals
  and statics outside `main.swift` are lazy (`LaunchOptions.current`,
  `AppDelegate.library`, `AppBranding`); there are no C targets,
  constructors or `+load` methods; `@NSApplicationDelegateAdaptor` and
  `NSApplicationMain`'s work happen inside `PhotoApplication.main()`. The
  refused path touches only `Bundle.main`, `CommandLine.arguments`, standard
  error and, for the alert, `NSApplication.shared`, which reads the copy's
  own preferences domain, never a library path.
- **Defense in depth.** The `preconditionFailure` in `LibraryModel.open` is
  its first statement, before the migrator or `createDirectories`. It uses the
  same inputs as the launcher (`Bundle.main`, the same `LaunchOptions.current`
  static), so it cannot fire on a launch the launcher allowed. `LibraryModel`
  lives in the `PhotoApp` executable target; `photocli`, `photobench` and
  `PhotoCoreTests` cannot link it, so no legitimate caller exists outside
  `LibraryLoader`. Mutation check by reading: with the launcher's check
  removed, a refused launch would trap in `open` before creating anything.
- **The rule** (`LibraryLaunchGuard.decide`) matches rulings 1, 3 and 4:
  `--library-root` with a value always allows; an identifier other than the
  release one, nil included, refuses with the alert unless scripted; the
  release identifier refuses only when scripted, never with the alert.
  `AppBranding.bundleIdentifier` equals `Branding.xcconfig`'s
  `PRODUCT_BUNDLE_IDENTIFIER` (enforced by `BrandingTests`), so the release
  bundle is never refused by mistake. Edge cases traced through the parser:
  a trailing `--library-root` with no value names no folder and refuses
  (tested); a trailing `--debug-script` with no value on the release bundle
  is allowed, but no script runs then, so it is an ordinary launch; a
  `--library-root` whose value is another switch roots the library at that
  odd relative path, never the standard one.
- **The `@main` move.** `PhotoApplication.main()` is the `App` protocol's
  public entry point and may be called from another `@main` type. Nothing
  else relied on `PhotoApplication` being `@main`: `Support/Info.plist` names
  `NSApplication` as principal class and no nib; `build-app.sh` copies the
  `PhotoApp` product by name; the target has no `main.swift`, so SwiftPM
  parses it as a library and accepts `@main` in `AppLauncher.swift`.
- **Swift 6 concurrency.** `AppLauncher.main()` and `refuse` are
  `@MainActor`, as `App.main()` and AppKit require; `Decision`, `Reason` and
  `LaunchOptions` are `Sendable`; no `@unchecked` or `nonisolated(unsafe)`.
  Builds clean under strict concurrency.
- **The move of `LaunchOptions`** (740d560) is a pure rename; the importer
  (`ImporterApplication.swift`), `DebugScript` and `ScrollBenchmark` already
  import PhotoCore. The standalone importer resolves no library or cache
  path, so leaving it unguarded is right.
- **Localization and branding.** Both new keys are in the catalog and match
  what `String(localized:)` generates (the interpolation becomes `%@`, filled
  from `AppBranding.displayName`); the title reuses the existing key. The
  standard-error line is not UI and is rightly not localized; it names the
  release identifier through `AppBranding`, not a literal. `BrandingTests` and
  `LocalizationTests` pass.
- **Tests.** `LibraryLaunchGuardTests` is Swift Testing, deterministic, touches
  no file system, and injects the release identifier; it does not compile on
  `develop` (the rule does not exist there) and would fail on a wrong rule
  (nil identifier, `showsAlert`, argument order, a valueless
  `--library-root`). The launcher's wiring is an executable target with no
  test target; status.md's D1 to D5 cover it end to end under a scratch home,
  and QA reruns them.
- **No goldens, migrations, edit stacks, sidecars, undo, pairs or
  dependencies** are touched.
- **Side effects worth knowing, all consistent with the rulings:** a test
  copy that macOS relaunches at login (it was running at log-out) now
  refuses instead of opening the library; a test copy that LaunchServices
  picks to open a preset file from the Finder shows the alert instead of
  importing.
- **Security.** No parser of outside files, no subprocess, no file writing
  and no network code is added or changed (argv parsing only moved).
  `/security-review` is not needed.

## Follow-up

For the main session to relay: `CLAUDE.md`'s Layout paragraph for
`Sources/PhotoUI` (line 195) still lists `LaunchOptions`; it now lives in
`Sources/PhotoCore/Launch/` beside `LibraryLaunchGuard`. That paragraph is
the owner's.

### Second pass, 2026-11-07: dc70f0b..fa7a67a

Reviewed `fa7a67a` only (the other commits in that range are docs).
`swift build` clean, no warnings; `swift test` 572 tests in 99 suites
passed, 1 known issue (the same `LiveSessionTests` one); `Localization`,
`Branding` and `Library launch guard` suites pass.

| # | Result | Commit |
|---|---|---|
| C1 | Fixed: the PhotoUI comment in `Package.swift` no longer lists launch options. (`CLAUDE.md` line 195 is still the owner's to change.) | fa7a67a |
| C2 | Fixed: `LibraryLaunchGuard.swift` ends with a single newline. | fa7a67a |

Also checked in `fa7a67a` (the designer's F1):
- `LibraryErrorView`: `Label { Text("Can't Open the Library", comment:) }
  icon: { Image(systemName: "exclamationmark.triangle") }` is what
  `Label(_:systemImage:)` expands to: the same localized key, looked up
  in the same table and bundle, and the same symbol. The title and icon
  render the same; the only change is the comment, which has no effect at
  run time.
- The alert's new message key, `Test copies of %@ must be started with
  --library-root <folder>. Your library wasn't opened.`, matches the
  catalog byte for byte (straight apostrophe in both). The old key is
  removed, not left behind. `%@` is still filled from
  `AppBranding.displayName`. The catalog comments for both keys match the
  comments in the code.
- `LocalizationTests` coverage: `Text("Can't Open the Library"` is on a
  single line, so the test still checks the title key. The alert's
  `String(` call, with `localized:` on the next line, was already outside
  what the line scanner reads before this commit (the same pattern appears
  in `MetadataActions.swift` and `MachineLearningText.swift`). The key is in
  the catalog anyway. This is a gap in the test that predates the branch,
  not a finding against it.
- The standard-error line still ends "Nothing was opened; quitting.". It is
  not UI, it is true there, and F1 was about the alert only. Fine.

No new findings. Every code-review finding is closed.
