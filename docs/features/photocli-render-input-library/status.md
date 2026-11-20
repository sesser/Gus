Issue: #222

# photocli render --input opens the default library: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/photocli-render-input-library`, from `develop` at
`d62cd4d`.

**Status: Blocked** on RI-1 below: the fix #222 asks for reverses part of
the owner's ruling on #166 (2026-11-15), so the owner has to choose. The
reproduction is done and committed as a test.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `d62cd4d`; never on the real library, see the test).
1. A library whose catalog is closed (the app has quit), with `catalog.sqlite`,
   `catalog.sqlite-wal` and `catalog.sqlite-shm` in its `Library` folder, at
   the standard location.
2. `photocli render <any image file> --out <new file>.png` with no `--library-root`.

**Expected** (#222). A render of a file by path never opens a library, or it
is refused without `--library-root`, as a test launch of the app is
(`LibraryLaunchGuard`). Which of the two is RI-1.

**Actual.** The render succeeds, and the standard library's
`catalog.sqlite-shm` gets a new modification time (`catalog.sqlite` and the
WAL keep theirs). Found by the QA of #218 (`docs/features/bw-module/qa.md`,
Q2), and seen in earlier QA runs too (`dehaze-above-white`,
`full-render-main-thread-stall`, `libraw-o3`).

**Root cause.** Not an accident: it is how #166 was fixed, per the owner's
ruling of 2026-11-15 (`docs/features/render-out-overwrites-master/status.md`,
"Owner's ruling"): `--out` always consults a library's catalog, and for a
file rendered without `--library-root` that is the standard library, opened
read-only. `RenderCommands.refuseOriginal` calls
`CommandEnvironment.openLibraryForReading`, which falls back on
`LibraryLocations.standard()` (`CommandEnvironment.libraryLocations`) and
opens it with `Catalog.openForReading` (a read-only GRDB `DatabaseQueue`).
"Read-only" protects the database, not the folder: in WAL mode every SQLite
reader maps the `-shm` file (the WAL index) and writes to it (its read mark,
and the index itself when it rebuilds it after the last connection closed),
and it creates `-wal` and `-shm` if they are missing. The #166 comments and
its test said as much (`catalogBytes` compares the database and the WAL, not
`-shm`); #222 is the owner deciding that even this is too much for a command
that only renders a file.

**Test that fails without the fix.** `RenderInputLibraryTests.fileRenderLeavesTheStandardLibraryAlone`
(`Tests/PhotoCoreTests/RenderInputLibraryTests.swift`, Swift Testing). It
makes a library in a temporary folder, imports one photo, closes the catalog
(its `-wal` and `-shm` stay, as in the owner's library), injects that folder
as the environment's standard library (`CommandEnvironment.hermetic(standardLibrary:)`,
so the real one is never reached), renders another file with no
`--library-root`, and compares every file in the library folder (bytes and
modification time) before and after. Today it fails exactly as reported:
`catalog.sqlite-shm` 32768 bytes, modification time moved; the database and
the WAL unchanged. It is committed inside `withKnownIssue` so the suite
stays green until the fix; the fix removes the wrapper (Swift Testing fails
a `withKnownIssue` whose issue no longer occurs, so the wrapper can't be
left behind). The test holds for every option in RI-1 (it renders to a new
file, so it says nothing about what is refused).

A side finding from writing it: in that fixture the import's rows sit in
the WAL (692 KB) and the database file is 4 KB, which rules out reading the
catalog with SQLite's `immutable=1` (it ignores the WAL; option C in RI-1).

## Other photocli commands (same fallback)

Every command that takes `--library-root` falls back on the standard library
through the same `CommandEnvironment.libraryLocations` when it is left out.
For all but a file render this is the documented contract (they act on a
library: USER_GUIDE "Pass `--library-root` as for the app; without it the
standard library is used"), so they are not this bug and are not changed
here. Listed for the follow-up (proposed issue F1):

| Command | Without `--library-root` | What it does to the standard library |
| --- | --- | --- |
| `render <file>` | the #166 check | read-only open (`Catalog.openForReading`): `-shm` written, `-wal`/`-shm` created if missing. **This bug.** |
| `render <file> --library-root X` | — | `Catalog.open` on X (a writer: migrates X if it is older) |
| `render --version N` | standard library | `Catalog.open` (only when the catalog file exists): runs migrations, writer connection |
| `query projects`, `query images`, `mask list` (reads) | standard library | `Catalog.open`, as above: a read command can migrate the catalog |
| `develop`, `rate`, `flag`, `label`, `export`, `mask add`/`set`/`remove` (writes; `--dry-run` reads) | standard library | `LibraryLock` (`library.lock`) then `Catalog.open`, and the change |
| `adjustments`, `help` | — | nothing |

No one-line change covers the others without changing their contract, so
only `render <file>` is in scope (per the task).

## Requirements issue RI-1 (for the owner, via the main session)

#222 says "never opens a library, or refuses without `--library-root`". The
owner's #166 ruling says a file render without `--library-root` must check
the standard library. Both can't hold. Options:

- **A. A file render opens a library only when `--library-root` names one.**
  Without it no library is read; the file being rendered is still refused
  (by place and identity, as now); any other existing file at `--out` is
  replaced. `render --version N` and any render with `--library-root` keep
  the full #166 check. Cost: small (drop the standard-library branch of
  `refuseOriginal`; rewrite `standardLibraryAskedForAFileRender` and
  `unreadableStandardLibraryRefuses` to the new rule; `--out` help text and
  USER_GUIDE). Gives up one #166 protection: `photocli render a.jpg --out
  <a master in the standard library>` writes over that master.
- **B. A file render without `--library-root` is refused** (usage error,
  exit 2, nothing read), as the app's guard refuses a test launch. Keeps all
  of #166. Cost: small in code, but every existing `render <file>` call
  without the option breaks (QA recipes in `docs/features/*/qa.md`, scripts),
  and a Mac with no library has no way to render a file (`--library-root`
  must name an existing library; `photocli` can't create one). So B needs an
  explicit way out, for example a new `--no-library` flag ("check no
  library; only the file being rendered is refused"): new command-line
  surface, the owner's to approve.
- **C. Keep asking the standard library without touching its files.** Not
  feasible cheaply: `immutable=1` ignores the WAL (a running or recently quit
  app's latest masters live there), and copying the catalog and WAL to a
  temporary folder for each render costs a full copy and races a running
  app. Not recommended.
- **D. Ask a library only when `--out` already exists** (a file that isn't
  there can't be overwritten). Combines with A or B; it would have avoided
  every QA case seen so far, but it still opens the standard library when
  `--out` exists, so on its own it doesn't meet #222.

Recommendation: **A**. It is #222's first expectation and the least
surprise for "render this file": nothing reaches the standard library unless
named, the same principle as the app's launch guard. The #166 repro
(`--version` onto its own master) and every render with `--library-root`
stay protected. It needs the owner's explicit OK because it narrows the
2026-11-15 ruling. If the owner wants that protection kept, B with
`--no-library`.

## Results

| Check | Result |
| --- | --- |
| Baseline `swift build` at `d62cd4d` | Clean |
| Baseline `swift test` at `d62cd4d` | 1240 tests in 176 suites, 1 issue: `DeferredRenderTests` "Core Animation renders an unread deferred image…" (the known flaky #229) |
| `swift test --filter RenderInputLibraryTests` (unfixed, without the wrapper) | Fails: `catalog.sqlite-shm` modification time moved |
| `swift test --filter "HermeticCommandTests\|RenderOutputProtectionTests\|RenderInputLibraryTests"` (with the wrapper) | 11 tests in 3 suites passed, 1 known issue (this one) |

No `photocli` was run against any library for this work: the reproduction is
the test, with an injected library location.

## Bug section mapped to checks

| Item | Check |
| --- | --- |
| A file render without `--library-root` leaves the standard library's folder byte for byte and time for time unchanged | `RenderInputLibraryTests.fileRenderLeavesTheStandardLibraryAlone` (known issue until the fix) |
| What is refused without a library | Waits on RI-1 |

## Open questions

- RI-1 (blocking).

## README

Nothing yet. Under A or B, `photocli render`'s contract changes (USER_GUIDE
Scripting, and the README if it describes `render`'s library use); recorded
here when built.
