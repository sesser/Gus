# Library launch guard: QA

Owner: qa-tester. Date: 2026-11-07. Step 4 of `docs/WORKFLOW.md`, last
after code review (`code-review.md`, two passes, closed) and the designer's
review (`review.md`, F1 confirmed, closed).
Tested: `bug/library-launch-guard` at `aae6dac`, on a Mac16,8 (Apple M4
Pro), macOS 27.2 (26B123), Xcode 27.2, macOS SDK 27.2 (the bundle's
executable records `sdk 27.2`, `minos 15.0`).

This is a bug fix, so there is no PRD or design. The criteria are the
**Bug** section of [`status.md`](status.md), with the owner's rulings 1–4
of 2026-11-07, and the library-launch-guard row in `docs/roadmap.md` ("The
workflow forbids it, but nothing in the app prevents it").

## Verdict

**Passes.** On `develop` a `.debugtest` copy started without
`--library-root` creates and opens the standard library (D5). On the branch
every such launch I could script is refused before anything is created.
Scripted launches exit 64 at once with no alert. The person-started launch
waits at an alert, and launches with `--library-root` work as before. The
owner's library was untouched throughout. No findings. Four checks are left
for a person (P1–P4), all about the alert on screen or the release
identifier.

## Acceptance criteria

| AC | Criterion | How | Evidence | Result |
|---|---|---|---|---|
| B1 | Expected: a test copy never opens the owner's library. Executable started directly, with or without `--debug-script` | Script | D2, D3, D4, E1: refused, scratch home left empty; compare D5 on `develop` | Pass |
| B1′ | The same for a copy started by `open <copy>` or a double-click (LaunchServices) | Person | P1 | Open |
| R1a | Ruling 1(a): an identifier other than the release one makes a test launch, refused without `--library-root` | Test, Script | `LibraryLaunchGuardTests.otherBundleWithoutLibraryRootIsRefused`, `otherBundleWithLibraryRootIsAllowed`, `defaultReleaseIdentifierIsTheBrandedOne`, `libraryRootWithoutAValueDoesNotCount`; D2–D4, E1 | Pass |
| R1b | Ruling 1(b): `--debug-script` or `--benchmark-scroll` makes a test launch even with the release identifier | Test | `LibraryLaunchGuardTests.releaseBundleWithScriptNeedsLibraryRoot` (2 cases), `releaseBundleWithoutFlagsOpensTheStandardLibrary`, `releaseBundleWithLibraryRootIsAllowed`. Not run as a launch: that needs the release identifier (P4, optional) | Pass |
| R2a | Ruling 2: a message on standard error | Script | D2, D3, D4, E1, E2: the line below, nothing on standard output | Pass |
| R2b | Ruling 2: an alert saying `--library-root` is required | Script, Person | D2: the refused process shows one 410 × 384 window and no other (an alert, no library window), and waits there. The bundle's `en.lproj/Localizable.strings` has the title, message and Quit. How it looks and reads: P1, P2 | Pass (shown, strings), Open (look) |
| R2c | Ruling 2: then quit | Script, Person | Scripted refusals exit 64 (D3, D4, E1, E2). Exit after answering the alert with Return or a click: P1, P3 | Pass (scripted), Open (after the alert) |
| R2d | Ruling 2: before the catalog, preview cache, sidecar sync or anything under the real library is opened or created | Script | D2, D3, D4, E1, E2: the scratch home (where Foundation resolves Application Support and Caches) stays completely empty, not even `Library/`. D5 on `develop` creates the whole library there | Pass |
| R3 | Ruling 3: no bundle identifier (`swift run`, a bare executable) is refused without `--library-root` | Test, Script, Person | `LibraryLaunchGuardTests.noBundleIdentifierIsNotTheReleaseIdentifier`; E2: the bare `.build/release/PhotoApp` with a script exits 64 with the "not running from a bundle" reason, home empty. `swift run PhotoApp` with no arguments, alert and exit after Quit: P3 | Pass (test, scripted), Open (alert) |
| R4 | Ruling 4: a refused scripted launch writes to standard error and exits 64 with no alert; a refused launch without those flags still shows the alert | Test, Script | Tests as R1a, R1b, R3 (each checks `showsAlert`); D3, D4, E1, E2 exit 64 in 0.03 s; D2 waits at the alert until `timeout` (exit 124) | Pass |
| B2 | Root cause and reproduction: `develop` opens the standard library for a test copy | Script | D5 (`develop` at `42a13e0`, `.debugtest` copy, scratch home) | Reproduced |
| B3 | The test fails without the fix | Test | Copied into a scratch clone of `develop`, `LibraryLaunchGuardTests` does not build (`swift test --filter LibraryLaunchGuardTests`: exit 1, 35 errors, `LibraryLaunchGuard` and `LaunchOptions` not in PhotoCore). Five mutants of the rule in a scratch clone of the branch each fail at least one test (Scripts, "Mutants") | Pass |
| B4 | Launches with `--library-root` work as before | Script | D1: `All Photos \| 212 photos`, snapshot shows the scratch library's grid, exit 0, home empty | Pass |
| B5 | Roadmap row: the app itself now prevents a test copy from opening the real library | Script | B1, R2d, R4; S1 | Pass (scripted routes); LaunchServices route P1 |
| B6 | New strings localized and unbranded | Test | `LocalizationTests`, `BrandingTests` pass; both new keys are in the catalog and the built bundle (see Observation O1 for what the scanner can't see) | Pass |
| S1 | The owner's library and caches untouched by this QA run | Script | Before/after listing and marker, below | Pass |

Totals: 16 rows. 3 pass by test only (R1b, B3, B6). 8 pass by script,
alone or with tests (B1, R1a, R2a, R2d, R4, B2 reproduced, B4, S1). 4 pass
in their scripted part and leave a part open for a person (R2b, R2c, R3,
B5). 1 is open for a person only (B1′). None failed.

## Findings

None for the engineer.

Observations (not findings on this branch):

- **O1. `LocalizationTests` can't see multi-line `String(` calls.** The
  scanner matches `String(localized: "` on one line, so a call written as
  `String(` with `localized:` on the next line is never checked against the
  catalog. Code review found this. It predates the branch: 8 calls in 3
  files today (`AppLauncher.swift` 2, `MetadataActions.swift` 1,
  `MachineLearningText.swift` 5). The branch's two are in the catalog and
  the built bundle anyway. A candidate for the qa-test-gaps roadmap row.
- **O2. The launcher's wiring has no automated test.** `AppLauncher.main()`
  (guard before `PhotoApplication.main()`) and the `preconditionFailure` in
  `LibraryModel.open` are in the `PhotoApp` executable target, which has
  no test target. The rule is unit-tested (B3); the wiring is covered only
  by the scripted launches D1–D5, E1, E2, which a later change could break
  unnoticed. Code review accepted this. The `LibraryModel.open` backstop
  can't be reached without changing the launcher, so it was checked by
  reading only (`code-review.md`).

## Scripts

Setup (rerunnable; `$S` is any scratch folder, outside the checkout):

```sh
Scripts/build-app.sh
mkdir -p $S/branch-copy && cp -R build/Gus.app $S/branch-copy/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/branch-copy/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/branch-copy/Gus.app
E=$S/branch-copy/Gus.app/Contents/MacOS/Gus
swift run -c release photobench generate --output $S/masters --jpeg 12
swift run -c release photobench import --library-root $S/lib --source $S/masters
```

`photobench` wrote 212 files (12 JPEG, 100 DNG, 100 HEIC) and imported
212. Every launch below runs the copy's executable directly, never `open`,
with `CFFIXED_USER_HOME` set to its own new, empty folder. No launch used
the release identifier.

**Scratch home check, first.** A three-line Swift program, compiled and run
with `CFFIXED_USER_HOME=$S/homecheck`, printed `NSHomeDirectory()`,
`.applicationSupportDirectory`, `.cachesDirectory` and
`url(for: .applicationSupportDirectory …)`. All four resolved inside
`$S/homecheck` (`…/homecheck/Library/Application Support`,
`…/homecheck/Library/Caches`). So even a broken guard could only have
reached scratch.

The refusal line (D2, D3, D4, E1), on standard error:

```
Refusing to open the standard library: bundle identifier me.sesser.gus.debugtest is not the release identifier me.sesser.gus. Test launches must pass --library-root <folder>. Nothing was opened; quitting.
```

- **D1. With `--library-root`, as before.**
  `CFFIXED_USER_HOME=$S/runs/d1/home timeout 60 $E --library-root $S/lib --debug-script "wait 3; print title; snapshot $S/runs/d1/d1.png; quit"`
  Printed `debug-script: title All Photos | 212 photos | rating any flag
  any search '' sort fileName asc` and wrote the snapshot. Exit 0 after
  7 s. Nothing on standard error, home empty. I looked at the snapshot: the
  scratch library's grid (IMG_00001…, JPEG badges, the first selected),
  title "All Photos, 212 photos", and the sidebar blank as `CLAUDE.md`
  says a glass pane will be.
- **D2. No arguments (a person's launch).**
  `CFFIXED_USER_HOME=$S/runs/d2/home timeout 10 $E &`, then after 4 s
  `pgrep -n -x Gus` (a new PID, not the owner's) and a CGWindowList listing
  of that PID's on-screen windows: one window, layer 0, 410 × 384, owner
  Gus, and nothing else (no library window). Exit 124 when `timeout` ended
  it after 10 s, i.e. it was waiting at the alert. The refusal line on
  standard error, nothing on standard output, home empty.
- **D3. `--debug-script` without `--library-root`.**
  `CFFIXED_USER_HOME=$S/runs/d3/home timeout 20 $E --debug-script "wait 2; quit"`
  Exit 64 in 0.03 s, with no alert, the refusal line, nothing on standard
  output, and an empty home.
- **D4. `--benchmark-scroll` without `--library-root`.**
  `CFFIXED_USER_HOME=$S/runs/d4/home timeout 20 $E --benchmark-scroll $S/runs/d4/report.json`
  Exit 64 in 0.03 s, with no alert and the refusal line. No `report.json`
  was written and the home is empty.
- **E1. `--library-root` with no value (trailing).**
  `CFFIXED_USER_HOME=$S/runs/e1/home timeout 20 $E --debug-script "wait 2; print title; quit" --library-root`
  Exit 64, the refusal line, nothing on standard output, home empty: a
  valueless `--library-root` names no library.
- **E2. No bundle identifier (ruling 3), scripted.**
  `CFFIXED_USER_HOME=$S/runs/e2/home timeout 20 .build/release/PhotoApp --debug-script "wait 2; print title; quit"`
  Exit 64, nothing on standard output, home empty. Standard error:
  `Refusing to open the standard library: not running from a bundle with
  the release identifier me.sesser.gus. Test launches must pass
  --library-root <folder>. Nothing was opened; quitting.`
- **D5. `develop` reproduces the bug.** A clone of `develop` at `42a13e0`
  in scratch, `Scripts/build-app.sh` there, a `.debugtest` copy made the
  same way (`$D`), then
  `CFFIXED_USER_HOME=$S/runs/d5/home timeout 40 $D --debug-script "wait 3; print title; quit"`.
  Printed `All Photos | 0 photos`, exit 0. It created
  `Library/Application Support/Gus/Library/{catalog.sqlite, -wal, -shm,
  library.lock, LUTs/ (8 .cube)}` and `Library/Caches/me.sesser.gus/Previews`
  in its scratch home. That is the incident, reproduced safely.

**Test on `develop`.** `LibraryLaunchGuardTests.swift` copied into the
scratch `develop` clone, then `swift test --filter LibraryLaunchGuardTests`.
It doesn't build: exit 1, 35 errors (`cannot find 'LibraryLaunchGuard' in
scope`, `cannot find type 'LaunchOptions' in scope`).

**Mutants.** In a scratch clone of the branch, one change at a time to
`LibraryLaunchGuard.decide`, then
`swift test --filter LibraryLaunchGuardTests`:

| Mutant | Tests that fail |
|---|---|
| alert always shown (`showsAlert: true`) | `otherBundleWithoutLibraryRootIsRefused`, `noBundleIdentifierIsNotTheReleaseIdentifier` |
| nil identifier treated as the release one | `noBundleIdentifierIsNotTheReleaseIdentifier` |
| release identifier with a script allowed | `releaseBundleWithScriptNeedsLibraryRoot` |
| `--library-root` ignored | `otherBundleWithLibraryRootIsAllowed`, `releaseBundleWithScriptNeedsLibraryRoot`, `noBundleIdentifierIsNotTheReleaseIdentifier` |
| scripted release launch shows the alert | `releaseBundleWithScriptNeedsLibraryRoot` |

The source restored: 10 tests pass.

**Suite.** `swift test` at `aae6dac`: 572 tests in 99 suites passed, 1
known issue (the existing `LiveSessionTests` "Values above white survive
the cached stages"). The suites "Library launch guard" (10 tests),
"Localization" and "Branding" pass. `Scripts/build-app.sh`: exit 0.

**S1. The owner's library.** Before the first launch: a marker file was
touched, and `stat` (mtime, size) was recorded for everything to depth 2
under `~/Library/Application Support/Gus` and
`~/Library/Caches/me.sesser.gus` (12 entries). The owner's release app
(PID 36237) was running on that library throughout. After the last launch
the listing was identical, and `find … -newer <marker>` found nothing under
either folder. No scratch copy and no `PhotoApp` was left running; the only
`Gus` process was the owner's.

## For a person

Each check starts a launch the guard refuses. Before it, in Terminal,
`touch /tmp/qa-marker`. After it, the following should print nothing:
`find ~/Library/Application\ Support/Gus ~/Library/Caches/me.sesser.gus -newer /tmp/qa-marker`
(with the release app quit first, since it writes there itself). For P1
and P2, make a copy first:
`Scripts/build-app.sh && cp -R build/Gus.app /tmp/GusTest.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest /tmp/GusTest.app/Contents/Info.plist && codesign --force --deep --sign - /tmp/GusTest.app`

- **P1. The alert on screen** (status.md M1; `review.md` M1; covers B1′,
  R2b, R2c). Run `open -n /tmp/GusTest.app`, or double-click it in Finder.
  Look for:
  - the alert in front of other windows, with the app icon (no caution
    badge);
  - the title "Can't Open the Library";
  - the message "Test copies of Gus must be started with --library-root
    \<folder\>. Your library wasn't opened." on two or three lines, not
    cut off;
  - one accent-colored Quit button.
  Return quits. Repeat and click Quit, which also quits. No library window
  and no app menus appear, and the Dock icon goes away after Quit.
- **P2. VoiceOver** (status.md M3; `review.md` M2). Turn VoiceOver on
  (⌘F5) and repeat P1. VoiceOver reads the title, then the message, and
  lands on Quit. Turn it off after.
- **P3. `swift run` with no arguments** (status.md M4; `review.md` M3;
  covers R3's alert path, R2c). From Terminal in the checkout:
  `swift run PhotoApp; echo $?`. Standard error shows "Refusing to open the
  standard library: not running from a bundle with the release identifier
  …". The alert is in front, or reachable from its Dock icon if macOS
  doesn't activate a process started from a shell. After Quit it prints
  `64`. (E2 already showed the scripted form of this exits 64 with nothing
  created.)
- **P4. Optional: the release identifier with a script** (status.md M2;
  covers R1b as a launch). Quit the release app first. Run
  `build/Gus.app/Contents/MacOS/Gus --debug-script "quit"; echo $?`. Standard
  error says "--debug-script or --benchmark-scroll was passed", no alert,
  `64` at once. I didn't run this: it uses the release identifier and its
  preferences, and the owner's copy was running. The unit tests cover this
  branch of the rule, and the launch path is the one D3 and D4 ran.

## Follow-up

None yet. Record here each P item when the owner reports it done.
