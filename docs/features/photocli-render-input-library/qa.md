# photocli render --input opens the default library: QA

Owner: qa-tester. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix: the
criteria are the **Bug** section of `status.md`, issue #222, and the owner's
ruling RI-1, option A, which narrows #166's).
Tested: `bug/photocli-render-input-library` at a669660, on an Apple M4 Pro,
macOS 27.2.1 (26B131), Xcode SDK 27.2, Swift 6.4.2.

## Verdict

Passes. A file render with no `--library-root` reaches no library (the test
that shows it fails on the pre-fix sources, with the reported symptom: `-shm`
changed, database and WAL not), and `--version` renders and renders with
`--library-root` still refuse masters, as the scripted run on a scratch library
and the mutation checks show. No findings, no manual checks. The one thing no
test or script here ran is the real binary on a file render without
`--library-root`; that was deliberately left to the hermetic tests (safety rule).

## Safety record

The owner's data folders were listed (`stat`, read only) before and after.
`~/Library/Application Support/Gus/Library`: `catalog.sqlite` 2026-11-17
13:50:09, `catalog.sqlite-shm` 2026-11-19 15:57:44, `catalog.sqlite-wal`
2026-11-19 16:00:19, `library.lock` 2026-11-19 15:57:44 (its process, 33445, is
not running: a stale lock), `LUTs` 2026-11-07 08:03:05. After all runs: the
listing is identical, and `find -newermt` from my start time finds nothing.
`~/Library/Caches/Gus` does not exist, before or after. No Gus, `photocli` or
`photobench` process left running. The -shm and -wal times above are from
before this run began (15:57 and 16:00, I started at about 16:12), so they are
not from this QA. No `photocli render <file>` without `--library-root` was run
at all; every `photocli`, `photobench` call carried `--library-root` on a scratch
library under the scratchpad. The checkout is clean (`git status`).

## Acceptance criteria

The Bug section's items, plus the #166 behavior the ruling keeps.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. A file render with no `--library-root` leaves the standard library's folder (every file's bytes and modification time, `-shm` included) as it was | Test | `RenderInputLibraryTests.fileRenderLeavesTheStandardLibraryAlone`. Read: closed library with db, `-wal`, `-shm` all required present, injected through `CommandEnvironment.hermetic(standardLibrary:)`, before/after state of every file, and the render must succeed. Fails without the fix (M1 below): `catalog.sqlite-shm` 32768 B with a new modification time, database and WAL unchanged | Pass |
| B2. A file render with no `--library-root` reads no library: another photo's master and a byte copy of one are ordinary files to it (written), the input itself is refused, catalog bytes (db, WAL, `-shm`) unchanged | Test | `RenderOutputProtectionTests.fileRenderAsksNoLibrary`; fails on the pre-fix sources (M1b) | Pass |
| B3. A damaged standard catalog doesn't stop a file render; a `--version` render with no `--library-root` still reads it and fails with `failed`, writing nothing and creating no `-wal`/`-shm` | Test | `unreadableStandardLibraryIsNotRead` (C1's `failed` check is in); fails on pre-fix sources (M1b) | Pass |
| B4. The input is refused as its own output with no library anywhere (same path, other case, hard link); nothing is created at the standard location | Test | `inputItselfWithoutLibrary` | Pass |
| B5. `--version` (with or without `--library-root`) and a file render with `--library-root` still refuse masters, by place (another photo's, other case, linked folder) and by content | Test | `namedLibraryAndVersionRendersStillProtectMasters`, `versionOntoItsOwnMaster` (the #166 repro), `anyMasterByPlace`, `masterByContent`; M2 shows they fail when the `--library-root` check is dropped | Pass |
| B6. Ordinary existing files are still replaced with a library open | Test | `ordinaryFilesStillReplaced` | Pass |
| B7. The #166 repro on the built binary: `render --version 1 --library-root <scratch> --out <its master>` refused, master untouched | Script | Script 1, cases 1 and 2 (`outputIsMaster`, exit 1, checksums of the masters unchanged) | Pass |
| B8. `render <file> --library-root <scratch> --out <a master>` refused (by place, through the `/tmp` link of the scratch path, and a byte copy elsewhere by content) | Script | Script 1, cases 3, 3b and 6 | Pass |
| B9. `render <file> --library-root <scratch> --out <fresh path>` works | Script | Script 1, case 4 (exit 0, 7,114-byte PNG, `decoder: imageIO`) | Pass |
| B10. A file render whose `--out` equals its input is refused (also through the link) | Script | Script 1, cases 5 and 5b | Pass |
| B11. The tests never reach the owner's library | Test | `HermeticCommandTests` (2 tests) pass; the new tests use `.hermetic(standardLibrary:)` with temporary folders | Pass |
| B12. Help text and USER_GUIDE say what the command now does | Read | `photocli help render` on the built binary prints the new `libraryRoot` and `out` summaries; USER_GUIDE Scripting diff read; both match the code | Pass |
| B13. No other behavior changed (no pipeline bump, golden, migration, rendering) | Test | Full `swift test`: 1242 tests in 177 suites passed, 0 issues, 0 failures (`grep -c` of failures in the log: 0) | Pass |

## Findings

None.

Notes for the owner and the engineer, not findings:
- N1. As recorded in RI-1, `photocli render <file> --out <a master of the
  standard library>` with no `--library-root` now writes over that master. It is
  the ruling's cost; the hermetic test `fileRenderAsksNoLibrary` asserts it. Not
  run on the real binary (safety rule).
- N2. Nothing here exercises the built `photocli` on a file render without
  `--library-root`. The hermetic test injects the standard library as a temporary
  folder, so it proves the code path touches nothing there; it can't prove that
  some other standard path (the real Caches folder) is not reached. The code
  review read every step of `runRender` for that case and found none; the Caches
  folder did not exist before or after this run, though this run never rendered
  without `--library-root`, so it is not evidence.

## Scripts

Test runs (all from the checkout at a669660; logs in the scratchpad,
`/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa222/`):

```
swift test                                   # full-test.log: 1242 tests in 177 suites passed, 0 issues (the flaky DeferredRenderTests #229 passed; no rerun needed)
swift test --filter "RenderInputLibraryTests|RenderOutputProtectionTests|HermeticCommandTests"
                                             # filtered.log: 12 tests in 3 suites passed
```

### Script 1: #166 kept, file render with `--library-root`

Scratch library, then the checks. `photobench generate` made 4 JPEGs and, by its
defaults, 100 DNGs and 100 HEICs (4.8 GB in the scratchpad; `--dng 0 --heic 0`
makes it small). Every call below names `--library-root`; none renders a file
without it.

```
S=/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa222
swift run -c release photobench generate --output $S/photos --jpeg 4 --jpeg-size 256x192
swift run -c release photobench import --library-root $S/lib --source $S/photos --imageio
swift build -c release --product photocli
```

`$S/check.zsh`, verbatim:

```
#!/bin/zsh
# #222 QA: every photocli call below names --library-root (a scratch library). None renders a file without it.
S=/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa222
P=/Users/randy/Projects/Gus/.claude/worktrees/photocli-render-input-library/.build/out/Products/Release/photocli
LIB=$S/lib
M1=$S/photos/Shoot-001/IMG_00001.JPG
M2=$S/photos/Shoot-001/IMG_00002.JPG
FRESH=$S/out-fresh.png
rm -f $FRESH
cksum $M1 $M2 > $S/masters.before
run() { echo "--- ${*//$S/\$S}"; out=$("$P" "$@" 2>&1); code=$?; echo "exit $code"; echo "$out" | head -c 400 | tr -s ' \n' ' '; echo; }
ALIAS=${S#/private}
echo "# 1 --version 1 --library-root onto its own master (#166): expect refused outputIsMaster"
run render --version 1 --library-root $LIB --out $M1 --long-edge 64
echo "# 2 --version 1 onto another photo's master: expect refused"
run render --version 1 --library-root $LIB --out $M2 --long-edge 64
echo "# 3 file render with --library-root onto a master: expect refused"
run render $M1 --library-root $LIB --out $M2 --long-edge 64
echo "# 3b same, the master named through /private/tmp (link): expect refused"
run render $M1 --library-root $LIB --out $ALIAS${M2#$S} --long-edge 64
echo "# 4 file render with --library-root onto a fresh path: expect success"
run render $M1 --library-root $LIB --out $FRESH --long-edge 64
ls -la $FRESH
echo "# 5 file render with --library-root, --out equals input: expect refused"
run render $M1 --library-root $LIB --out $M1 --long-edge 64
echo "# 5b --out is the input through /private: expect refused"
run render $M1 --library-root $LIB --out $ALIAS${M1#$S} --long-edge 64
echo "# 6 byte copy of a master elsewhere, file render with --library-root: expect refused (by content)"
cp $M2 $S/copy-of-m2.jpg
run render $M1 --library-root $LIB --out $S/copy-of-m2.jpg --long-edge 64
cksum $M1 $M2 > $S/masters.after
diff $S/masters.before $S/masters.after && echo "masters unchanged"
```

(The comments of 3b and 5b say `/private/tmp`; the alias is the scratch path
without its `/private` prefix, that is, the `/tmp` link.) Result: cases 1, 2,
3, 3b, 5, 5b, 6 exit 1 with code `outputIsMaster`; case 4 exits 0 and writes the
PNG; "masters unchanged". Output in `check.log`.

### Mutation checks (scratch copies of a669660 made with `git archive`, outside the checkout; the checkout was not touched)

- M1: `Sources/PhotoCore/Commands/RenderCommands.swift` and `CommandRegistry.swift`
  replaced by their `d62cd4d` versions (the standard-library branch and
  `openLibraryForReading` back), tests as on the branch.
  `swift test --filter RenderInputLibraryTests` **fails**: `after == before`
  false; `catalog.sqlite-shm` 32768 B with a new modification time, database
  and WAL unchanged (the reported symptom). M1b: `--filter
  RenderOutputProtectionTests` on the same copy fails 6 issues in 2 tests
  (`fileRenderAsksNoLibrary`, `unreadableStandardLibraryIsNotRead`).
- M2: in `runRender`, `refuseOriginal(out, source: source, library:
  arguments.string("input") != nil ? nil : library)` (no master check for a
  file render with `--library-root`). `swift test --filter
  RenderOutputProtectionTests` **fails**: 21 issues in 3 tests
  (`namedLibraryAndVersionRendersStillProtectMasters`,
  `anyMasterByPlace`, `masterByContent`).

## For a person

None. The change has no UI, and the one run a person might want (the real
`photocli` on a file with no `--library-root`) is what this fix exists to keep
away from the real library.

## Follow-up

(Reruns after fixes, and the owner's sign-off, go here.)
