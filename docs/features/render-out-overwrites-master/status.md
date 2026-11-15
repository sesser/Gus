Issue: #166

# photocli render --out overwrites a master: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"), a follow-up from #160's third code review. Branch
`bug/squash-top-10`, from `develop` at `4cf2107`.

**Status: Done.** Next: code-reviewer, then qa-tester. No UI changed, so no
design review. This fix changes file writing outside the library
(`photocli render --out`) and opens the standard library from `photocli`:
code-reviewer to say whether `/security-review` should run.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `4cf2107`, from #166).
1. A library with a JPEG imported in place; note its version id N and its
   master's size.
2. `swift run photocli render --version N --out <that version's master> --long-edge 200 --library-root <library>`

**Expected.** The command refuses, writes nothing, and the master keeps its
bytes. Originals are never written (`CLAUDE.md`, Architecture rules).

**Actual.** Exit 0. The master is replaced by a 200-pixel render (131,530 to
7,558 bytes in the report), with no flag, question or warning. The same
happens for any other master, a master named in another case
(`img_0001.JPG`), a master reached through a linked folder, a copy of a
master elsewhere, a file rendered with no `--library-root` onto a master in
the standard library, and, with no library at all, the input file itself.

**Root cause.** `RenderCommands.write` (`Sources/PhotoCore/Commands/RenderCommands.swift`)
writes a temporary file next to `--out` and moves it into place with
`FileManager.replaceItemAt` when something is already there. Nothing on the
path from `runRender` to `write` asked whether `--out` was an original. #160
added that question to export (`Catalog.masterFiles(mounted:)`, used by
`ExportJob`), but `render` writes on its own path and was not covered. A file
render without `--library-root` opened no library at all, so it had nothing
to ask.

**Tests that fail without the fix.** `RenderOutputProtectionTests`
(`Tests/PhotoCoreTests/RenderOutputProtectionTests.swift`, Swift Testing).
With the call to the check taken out (a trial, since restored), 6 of its 8
tests fail with 34 issues (exit 0, no `outputIsMaster` code, the file at
`--out` rewritten):
- `versionOntoItsOwnMaster`: the #166 repro.
- `anyMasterByPlace`: with `--library-root`, another photo's master, another
  case, a linked folder, and with `--version` onto another photo's master.
- `masterByContent`: a byte copy of a master in another folder.
- `standardLibraryAskedForAFileRender`: no `--library-root`; the standard
  library (the environment's default root) refuses another photo's master
  and a byte copy of one, an ordinary file is still written, and the
  catalog's files (database and WAL) are byte for byte unchanged.
- `unreadableStandardLibraryRefuses`: a standard catalog that exists but is
  not a database: the command fails (`failed`), writes nothing, and leaves
  the catalog file as it was.
- `inputItselfWithoutLibrary`: no catalog at the standard location; the input
  by its path, in another case and through a hard link is refused; another
  file is written; nothing is created at the library location.

These pass before and after the fix:
- `ordinaryFilesStillReplaced`: an ordinary existing file at `--out` is still
  replaced with a library open.
- `catalogOpenForReading`: `Catalog.openForReading` creates nothing for a
  missing catalog, reads masters, and throws on a write.

## Owner's ruling (2026-11-15, relayed by the main session)

Replaces the earlier open question (whether a file render without
`--library-root` should open the standard library to ask). `photocli render`
must check the library: `--out` always consults a library's catalog (the
one the command already opens, or the standard library when none is given,
read-only, no writes, no lock) and refuses an `--out` that is a catalogued
master by place or by content. If no library can be opened, refuse an `--out`
that can't be shown safe, or require a library, whichever fits the command
contract better. The input-itself refusal stays.

How it was applied (my reading of the last point; for code review and the
owner to confirm):
- **No catalog at the standard location** (the file is absent): nothing is
  catalogued, so no `--out` can be a catalogued master. Only the input itself
  is refused and the render goes ahead. Requiring a library was the other
  option; it would break plain file renders on a Mac with no library, which
  the command's contract allows today (`libraryRoot` is optional for a file,
  required only through `--version`), so I did not choose it.
- **A catalog that exists but can't be opened or read** (damaged, a schema
  the query can't read), or **a standard location that can't be found**:
  `--out` can't be shown safe, so the command fails with `failed` and writes
  nothing.
- **An explicitly named library** (`--library-root`) that doesn't exist is
  `libraryNotFound`, as before.

## The fix

`RenderCommands.refuseOriginal(_:source:library:environment:arguments:)`,
called in `runRender` after the source is found and before anything renders
(a refused output costs no render):

- **Always**: `--out` that is the file being rendered is refused, by place
  (`MasterFiles([source]).contains`: same folder resolved through links,
  names folded as APFS compares them) or by identity
  (`fileResourceIdentifier` after following links, so a hard link or a link
  to it counts).
- **Then a catalog is asked**: the library the command opened (`--version`,
  or a file with `--library-root`; opened as before, with `Catalog.open`),
  otherwise the standard one (the environment's `defaultLibraryRoot`, else
  `LibraryLocations.standard()`) through the new
  `CommandEnvironment.openLibraryForReading`, which opens it with the new
  `Catalog.openForReading`: a read-only `DatabaseQueue`, no migration,
  nothing created, no lock. `--out` is refused when
  `masterFiles(mounted: VolumeAvailability.mountedVolumes())` holds it by
  place (`contains`) or by content (`holdsContent(ofFileAt:)`). `mounted:` is
  passed explicitly. If the masters can't be read, the command fails
  (`failed`) and writes nothing.

A refusal is an error, never a numbered name: `--out` names one exact file.
New code `outputIsMaster` (`CommandError.Code`, exit 1, not a usage error),
so scripts can tell it from `writeFailed`. `--out`'s help text says so.

Why a separate read-only open: `Catalog.open` creates the folder and runs
migrations, so on a library made by an older build it writes. The commands
that already open a library keep that contract; the check of a library the
user didn't name must not change it.

No rendering changed: no `PreviewCacheKey.currentPipelineVersion` bump, no
golden touched, no migration. The time between the check and the write is
not closed (a file that becomes a master's in between is replaced), as
accepted for export in #160. Cost of the check with the standard library:
one catalog read of every image row and one folder resolution per master
folder per render, plus a SHA-256 of `--out` only when it exists and has a
master's size.

Files:
- `Sources/PhotoCore/Commands/RenderCommands.swift`: `refuseOriginal`,
  `isSameFile`, the call in `runRender`, `--out`'s summary.
- `Sources/PhotoCore/Commands/CommandRegistry.swift`: `CommandError.Code.outputIsMaster`,
  `CommandEnvironment.openLibraryForReading`.
- `Sources/PhotoCore/Catalog/Catalog.swift`: `Catalog.openForReading(at:)`
  and an init that doesn't migrate.
- `Tests/PhotoCoreTests/RenderOutputProtectionTests.swift`: new suite.
- `docs/USER_GUIDE.md`: Scripting says `render --out` never writes over an
  original and which library it asks.

## Results

Baseline at `4cf2107`: `swift build` clean; full `swift test` 998 tests in
145 suites passed, 1 known issue.

| Check | Result |
| --- | --- |
| `swift build` | Clean, no new warnings (the test build's two warnings are in `SmartAlbumTests` and `VirtualCopiesTests`, untouched) |
| `swift test --filter RenderOutputProtectionTests` | 8 tests passed |
| `swift test --filter "RenderOutputProtectionTests\|CommandTests\|LensCommandTests\|BatchCommandTests\|ExportMasterProtectionTests"` (before the ruling) | 84 tests in 16 suites passed |
| `swift test` (full, final) | 1001 tests in 145 suites passed, 1 known issue (as at baseline) |

No debug-script checks: `photocli` only, no app change.

## Bug section mapped to checks

| Item | Check |
| --- | --- |
| The #166 repro refused, master unchanged | `versionOntoItsOwnMaster` |
| Every catalogued master refused by place (case, linked folder), named library | `anyMasterByPlace` |
| A master's bytes elsewhere refused | `masterByContent` |
| No `--library-root`: the standard library asked, read-only, place and content | `standardLibraryAskedForAFileRender` |
| A standard library that can't be read: refused, nothing written | `unreadableStandardLibraryRefuses` |
| Read-only open creates, migrates and writes nothing | `catalogOpenForReading`, `standardLibraryAskedForAFileRender` (catalog bytes) |
| No library anywhere: the input itself refused, other files written | `inputItselfWithoutLibrary` |
| Ordinary files still replaced | `ordinaryFilesStillReplaced` |
| `mounted:` passed explicitly | Code review (`refuseOriginal`) |

For a person (optional; not scriptable without touching the real library):
a `photocli render <file> --out <a master in the real standard library>`
with the app open and closed, to see it refused and the library unchanged.

## Open questions

- None blocking. The ruling's last point was applied as described under
  "How it was applied": no catalog at the standard location lets the render
  go ahead with only the input refused; an unreadable one refuses. Code
  review or the owner may prefer requiring a library instead.

## README

Nothing for the README: no requirement, build command or layout changed.
`photocli`'s output contract gains one error code, `outputIsMaster`, and a
file render without `--library-root` now reads the standard library.

## Summary for the issue

Fixed on `bug/squash-top-10`: `photocli render --out` refuses (code
`outputIsMaster`, exit 1, nothing written) the file being rendered (by place
or identity) and any catalogued master by place or content
(`Catalog.masterFiles(mounted:)`, mounted volumes passed explicitly). The
catalog is the library the command opens, or, per the owner's ruling, the
standard library opened read-only (no migration, no lock); none there means
only the input is refused, an unreadable one refuses the render. Checked
before rendering; ordinary files are still replaced. `RenderOutputProtectionTests`:
8 tests, 6 fail without the fix. Full `swift test`: 1001 passed. No rendering
change, no pipeline bump. Details: `docs/features/render-out-overwrites-master/status.md`.
