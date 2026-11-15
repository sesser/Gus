# photocli render --out overwrites a master: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`. Bug fix, issue #166.
Tested: `bug/squash-top-10` at 7047bad, on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict
Passes. The bug reproduces on `develop` (a master goes from 124,939 to 6,861 bytes, exit 0) and is gone on the branch (exit 1, code `outputIsMaster`, bytes unchanged); the 6 tests that cover it fail on a copy of the branch with the check taken out, and pass with it. Nothing needs a person.

## Acceptance criteria
The criteria are the Bug section of `status.md` and the issue.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| Expected: `render --version N --out <its own master>` refuses, writes nothing, master keeps its bytes (the #166 repro) | Test, Script | `RenderOutputProtectionTests.versionOntoItsOwnMaster`; Script S1 (develop shows the bug, branch shows the fix) | Pass |
| Any other catalogued master is refused by place: another photo's, another case, through a linked folder, with `--version` or a file | Test | `anyMasterByPlace`; Script S2 (other case) | Pass |
| A copy of a master's bytes elsewhere is refused | Test, Script | `masterByContent`; Script S3 | Pass |
| No `--library-root`: the standard library is asked, read-only (no migration, no lock, nothing in the catalog written), by place and content; an ordinary file is still written | Test | `standardLibraryAskedForAFileRender` (catalog and WAL bytes unchanged) | Pass |
| A standard catalog that exists but can't be read: `failed`, nothing written, catalog untouched | Test | `unreadableStandardLibraryRefuses` | Pass |
| No library anywhere: the input itself refused (same path, other case, hard link), another file written, nothing created at the library location | Test | `inputItselfWithoutLibrary` | Pass |
| Read-only open creates no catalog or folder, migrates nothing, refuses a write | Test | `catalogOpenForReading` | Pass |
| Ordinary existing files at `--out` are still replaced | Test, Script | `ordinaryFilesStillReplaced`; Script S4 | Pass |
| `mounted:` passed explicitly | Review | Read `RenderCommands.refuseOriginal`: `VolumeAvailability.mountedVolumes()` | Pass |
| Tests are hermetic (code review C1): `swift test` never opens the owner's catalog | Test, Script | `HermeticCommandTests` (2 tests); the owner's `catalog.sqlite-shm` kept its time (10:42:12) through the full run | Pass |

Tests that fail without the fix: in a scratch copy of the branch with only the call to `refuseOriginal` removed, 6 of the suite's 8 tests failed with 34 issues (`versionOntoItsOwnMaster`, `anyMasterByPlace`, `masterByContent`, `standardLibraryAskedForAFileRender`, `unreadableStandardLibraryRefuses`, `inputItselfWithoutLibrary`). `ordinaryFilesStillReplaced` and `catalogOpenForReading` pass either way, as the engineer says. I read the suite: each refused case asserts the exit code, the `outputIsMaster` code and the file's bytes.

Full run: `swift test` 1032 tests in 153 suites passed, 1 known issue (`LiveSessionTests`, as on `develop`). `Scripts/build-app.sh all` built both bundles.

## Findings
None.

## Scripts
The `photocli` runs use a scratch library made with
`photobench generate --output lib166/src --jpeg 4 --dng 0 --heic 0` and
`photobench import --library-root lib166/app --source lib166/src`. Every command passes `--library-root` (a render with no `--library-root` would read the owner's standard library, so none was run). `D=lib166/src/Shoot-001`, `LR=lib166/app`.

S1, on `develop` (built from `git archive develop` in a scratch folder, `photocli` debug build):

```
photocli render --version 1 --out $D/IMG_00001.JPG --long-edge 200 --library-root $LR
```
Exit 0; the master went from 124,939 to 6,861 bytes (SHA-256 changed). The bug, as the issue says.

S1 to S4, on the branch's `photocli` (the master's SHA-256 recorded before and after):

```
photocli render --version 1 --out $D/IMG_00001.JPG --long-edge 200 --library-root $LR                (S1)
photocli render $D/IMG_00001.JPG --out $D/img_00003.jpg --long-edge 200 --library-root $LR           (S2)
photocli render $D/IMG_00001.JPG --out lib166/copy.jpg --long-edge 200 --library-root $LR            (S3; copy.jpg is a byte copy of IMG_00002.JPG)
echo hello > lib166/ordinary.png; photocli render --version 1 --out lib166/ordinary.png --long-edge 200 --library-root $LR   (S4)
```
S1 to S3: exit 1, `{"code":"outputIsMaster", ...}`, both masters' hashes unchanged. S4: exit 0, the file replaced by a PNG.

## For a person
Nothing. The engineer's optional check (a render onto a master of the real standard library) would touch the owner's library and is covered by `standardLibraryAskedForAFileRender` on a scratch one.

## Follow-up
Open for the main session (not findings): `docs/USER_GUIDE.md` and `status.md` already say a file render with no library at the standard location goes ahead with only the input refused; the owner's ruling allowed either that or requiring a library, and the engineer asks the owner or code review to confirm (status.md "Open questions").

## Summary for the issue
QA passes (#166). On `develop` `photocli render --out <master>` rewrote the master (124,939 to 6,861 bytes); on the branch it exits 1 with `outputIsMaster` and the bytes are unchanged, by place, other case, linked folder and content. 6 of 8 tests fail without the check; full `swift test` 1032 passed. Nothing for a person. `docs/features/render-out-overwrites-master/qa.md`.
