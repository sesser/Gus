Issue: #160

# Export overwrites masters: QA

Owner: qa-tester. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md` (bug fix).
Tested: `bug/export-overwrites-masters`, the **uncommitted working tree** on
`cd992f9` (nothing committed; source files last changed 07:42 on 2026-11-13,
before this pass started; fingerprint of `git diff` plus the two new Swift
files: `5dcc6a14d783`), on a Mac16,8, macOS 27.2.1 (26B131), SDK 27.2,
Swift 6.4.2.

## Verdict

**Passes.** The bug reproduces on `develop` (4 of 5 masters overwritten by
`photocli export --policy overwrite`) and is gone on the branch. Every case
in the Bug section and the owner's ruling (place, current mount, content)
holds in tests, in `photocli` and in the app bundle. All four alert
messages come out of the bundle's compiled catalog. What is left is for a
person: the alert's look and keys, a real click, the wait with large files,
and network volumes (P1 to P4). One note: code-reviewer has not yet
confirmed C8 and C9 in `code-review.md`. Both tests pass here.

Build and tests:

- `swift test`, full: **857 tests in 128 suites passed, 1 known issue**
  (`LiveSessionTests.swift:258`, the existing one). Among them all 41 new
  tests and `hashingALargeFileHoldsOneChunkNotTheFile` (C9).
- `Scripts/build-app.sh all`: builds both bundles. `vtool`: minos 15.0,
  sdk 27.2.

## Acceptance criteria

The Bug section of `status.md` and the issue's ruling, case by case.

| AC | How | Evidence | Result |
|---|---|---|---|
| B0. The bug exists on `develop` | Script | D1 (`develop`'s `photocli`): 4 masters replaced | Shown |
| B1. Replace into the photos' own folder changes no original (Steps 1 to 3) | Test, Script | "Replace into the photos' own folder leaves every master as it was"; S-A (app), S1 (`photocli`) | Pass |
| B2. `photocli export --policy overwrite` never writes over a master | Test, Script | "export --policy overwrite never writes over a master (issue #160)"; S1 | Pass |
| B3. A template that names an export like another photo's master | Test, Script | `anotherPhotosMasterIsNotReplacedEither`, "A template that names an export like another photo's master…"; S2 | Pass |
| B4. A RAW whose export name is its pair's JPEG | Test, Script | the "Replace into the photos' own folder…" test (`a.DNG` to `a.jpg`); S1 (`PAIR_00004.DNG` exported, `PAIR_00004.JPG` kept); D1 shows it replaced on `develop` | Pass |
| B5. Folder reached through a symbolic link | Test, Script | `aFolderReachedThroughASymbolicLinkIsTheSameFolder`, "The source folder reached through a symbolic link…"; S2, S-C | Pass |
| B6. Names that differ only in case (`IMG_1.JPG` against `IMG_1.jpg`) | Test, Script | `namesMatchAsTheFileSystemComparesThem`, `aFolderSpelledInAnotherCaseIsTheSameWhereTheVolumeSaysSo`, "A master whose name differs…only in case…"; every script (the generator writes `.JPG`, export writes `.jpg`) | Pass |
| B7. An ordinary file is still replaced (ruling) | Test, Script | `anOrdinaryFileIsStillReplaced`, "A file that is no master is replaced, in the masters' folder too"; S2, S-A (`RAW_0000N.jpg` replaced) | Pass |
| B8. The whole catalog is covered, not only the batch | Test | `theCatalogListsEveryMasterWhereExportReadsIt` | Pass |
| R1. By place on the volume's **current mount** (C1) | Test, Script | `aVolumeIsPlacedWhereItIsMountedNowAndWhereItWasRecorded`, "A master on a volume mounted elsewhere…"; S3, which also changes the master's bytes so that only the current mount can protect it | Pass |
| R2. By **size and SHA-256 content** on a volume the catalog can't recognize (C5) | Test, Script | "A master on a volume the catalog can't recognize…", the `photocli` C5 test, the "Master files: a master's content…" suite; S4 (FAT32, serial 0) | Pass |
| R3. Same content under another name or folder is protected; same size with other bytes is not | Test, Script | `aFileWithAMastersBytesIsOneWhateverItsNameOrPlace`, `theSameSizeWithOtherBytesIsAnOrdinaryFile`; S2 (backup), S-C | Pass |
| R4. Fails closed: the catalog can't be read, a file can't be read, a read is cancelled (C2, C3, C8) | Test | "When the catalog can't say where the masters are, nothing is written and no folder is made", `aFileIsReadOnlyWhenItsSizeIsAMasters`, `aReadCutShortByCancellationCountsAsAMaster`, `aFileThatOpensAndCannotBeReadCountsAsAMaster` | Pass |
| R5. Hashing holds one chunk, not the file (C6, C9) | Test | `hashingALargeFileHoldsOneChunkNotTheFile`, `aFileOfSeveralChunksHashesAsTheCatalogDoes` | Pass |
| R6. A missing master's place is not taken (decision 1) | Test | `aMissingMastersPlaceIsNotTaken`, "A missing master's place is kept when the export makes its folder again" | Pass |
| R7. Keep Both and Skip behave as before | Test, Script | `skipLeavesAnExistingMasterAndKeepBothNumbersIt`, `existingFilesAreSkippedOverwrittenOrKept`; S-A, S2 | Pass |
| A1. The alert's message: four cases (`review.md` R1), final English `review.md` R5 | Test, Script, Person | the four tests of "Export clashes: how many of the files in the way are originals" pick the case; S-A and S-B printed all four from the bundle (in R1's wording, before R5); the final wording read by the owner in P1 at sign-off | Pass |
| A2. Title, buttons, order, default and cancel unchanged | Person | P1, P2 (`review.md` requirements 2 and 3 pass by reading) | Open |
| M1. The message fits, wrapped, nothing cut off | Person | P1 | Open |
| M2. A real click on Replace; Return and Esc | Person | P2 | Open |
| M3. Mixed clashes: the title counts all, the message only the originals | Script, Person | counts and text: S-A run 2, S-B run 2, S-C; the look: P1 | Pass (logic), Open (look) |
| M4. Exact copies counted as originals; no wait that looks like a hang | Script, Person | the count and the numbering: S2, S-C; the wait with large raws: P3 | Pass (logic), Open (wait) |
| CR-Q2. Network volumes: time to the question and to the start | Person | P4 | Open |

Code-review findings: C1, C2, C3, C5, C6, C8 and C9 are covered by the rows
above; their tests pass. C4 and C7 are left as ruled, for one follow-up issue
(`status.md`, Follow-ups), and no original is at risk from them. F1 is
covered by A1.

Counts: 17 rows pass (5 by test only, 12 by test and script), B0 is shown on
`develop`, 4 rows are open for a person, plus the person halves of M3 and
M4. None failed.

### Known limits (as ruled; not findings)

- **A master that another app changed since the catalog last hashed it**, on a
  volume the catalog can't recognize, is an ordinary file and is replaced.
  Shown in S4b. On a recognized volume, place still protects it (S3).
- **A 0-byte master** in the catalog makes every empty file count as a master
  (over-protection only). A named pipe at such a place would block in `open`.
  This comes from code review (third and fourth passes) and was not run here.
- **Network volumes**: resolving folders, listing the mounts and reading
  files of a master's size have not been timed on a slow or sleeping share
  (P4).
- **Between the check and the write (TOCTOU)**: a file planned for Replace
  that becomes a master's bytes, or is imported in place, while the export
  runs is replaced. Accepted. The fix would be to ask again in
  `ExportRenderer.write` before `replaceItemAt`. Files planned without
  replacing use `moveItem`, which never overwrites.
- Under Keep Both the summary's "originals kept" (`protectedMasters`) counts
  the photos whose name is a master's (decision 3), e.g. S-A run 3. Nothing
  in the UI shows it yet (the Activity row is follow-up R3).

## Findings

None for the engineer.

Notes for the main session:

- **C8 and C9** are fixed according to `status.md`, but `code-review.md`'s
  fourth pass still lists them without confirmation. Their tests pass in this
  full run. The reviewer should confirm them in its own file before sign-off.
- The follow-ups in `status.md` stand: C4 and C7 as one issue, `photocli
  render --out`, the importer's hashing memory, `photocli` reading masters at
  the recorded mount path, and the Activity row. Nothing new to add.

## Scripts

`$S` is the scratch folder
(`/private/tmp/claude-501/-Users-randy-Projects-Gus/9529190c-90b5-476a-b193-11dcfdde8b7f/scratchpad`).
Photos come from `swift run -c release photobench generate --output … --jpeg N
--dng N --heic 0 --pairs N --per-folder 10 --jpeg-size 1200x800 --dng-size
1200x800`. They were catalogued with `photobench import --library-root …
--source …`. Before and after each run, every master's SHA-256 was compared
with `shasum -a 256 -c`. The app is a copy of `build/Gus.app` with
`CFBundleIdentifier` `me.sesser.gus.debugtest`, re-signed ad hoc, run as
`timeout 180 "$S/app/Gus.app/Contents/MacOS/Gus" --library-root <lib>
--debug-script "<script>"`. Export settings in every `photocli` run:
`--settings '{"sizing": "longEdge", "edgeLength": 200}'`.

**D1, `develop` (built in a scratch copy from `git archive develop`).**
Library: `IMG_00001..3.JPG` and the pair `PAIR_00004.DNG` + `PAIR_00004.JPG`
in `dev-photos/Shoot-001`.

    $S/dev/.build/debug/photocli export --version 1 --version 2 --version 3 --version 4 \
      --to $S/dev-photos/Shoot-001 --policy overwrite --settings '…' --library-root $S/dev-lib

Result: `written` lists `IMG_0000N.jpg` and `PAIR_00004.jpg`, with no
`protectedMasters` key. `IMG_00001..3.JPG` and `PAIR_00004.JPG` FAILED their
checksums (now 7 to 9 KB renders). Only the DNG survived. **The bug is on
`develop`.**

**S1, the branch, the same library and command** (`swift run photocli …`),
run twice. Result: `protectedMasters 4`, no failures; written
`IMG_0000N-2.jpg` and `PAIR_00004-2.jpg`, then `-3` on the second run. All 5
masters OK.

**S2, the branch's `photocli`, same library:**

| Run | Result |
|---|---|
| `--version 2 --to $S/link-to-shoot` (a link to the photos' folder) | `protectedMasters 1`, `IMG_00002-4.jpg` |
| `--version 1 --to <photos> --settings '{…, "naming": "template", "fileNameTemplate": "IMG_00003"}'` | `protectedMasters 1`, `IMG_00003-4.jpg` |
| `--version 1 --to $S/out-ord`, twice | `protectedMasters 0`, `IMG_00001.jpg` both times, one file: replaced |
| `$S/backup` holds an exact copy of `IMG_00001.JPG` named `IMG_00001.jpg`: `--version 1 --to $S/backup` with overwrite, then skip, then keepBoth | overwrite: `protectedMasters 1`, `IMG_00001-2.jpg`; skip: skipped 1; keepBoth: `IMG_00001-3.jpg`, `protectedMasters 0`. The copy is unchanged |
| `$S/backup/IMG_00002.jpg` is an ordinary export of another photo: `--version 2 --to $S/backup --policy overwrite` | `protectedMasters 0`, `IMG_00002.jpg` replaced |

Masters afterwards: all 5 OK.

**S3, C1 on a real remount.** An APFS image (`hdiutil create -size 20m -fs
APFS -volname QARemount`), attached at `$S/vol/m1` with `-nobrowse`, holding
`Shoot/IMG_00001.JPG`. `internal-a/IMG_00001.JPG` (other bytes) is on the
internal disk. Both were imported into `lib-a`. The volume is
`uuid:CFD19FE6-…`, recorded at `…/m1`.

| Step | Result |
|---|---|
| `export --version 2 --to …/m1/Shoot --policy overwrite` | `protectedMasters 1`, `IMG_00001-2.jpg`, master `7dd5a1d4…` unchanged |
| detach, attach at `…/m2`, same with `--to …/m2/Shoot` | `protectedMasters 1`, `IMG_00001-3.jpg`, master unchanged |
| append one byte to the master at `m2` (content no longer the catalog's), same command | `protectedMasters 1`, `IMG_00001-4.jpg`, the changed file unchanged: protected by its current mount alone |
| catalog `volume.mountPath` afterwards | still `…/m1` (nothing written) |

**S4, C5 on a FAT32 volume with no UUID.** A 40 MB FAT32 image whose file
system was made again with `newfs_msdos -F 32 -I 0 -v NOUUID` (`diskutil`:
Volume UUID all zeros), attached at `…/f1` and holding
`DCIM/IMG_00001.JPG`. Another `IMG_00001.JPG` is on the internal disk. Both
were imported into `lib-f`; the catalog records the card as
`mount:NOUUID@…/f1`.

| Step | Result |
|---|---|
| `export --version 2 --to …/f1/DCIM --policy overwrite` | `protectedMasters 1`, `IMG_00001-2.jpg`, master unchanged |
| detach, attach at `…/f2`, `--to …/f2/DCIM` | `protectedMasters 1`, `IMG_00001-3.jpg`, master `7dd5a1d4…` unchanged |
| **S4b, known limit:** append one byte to the master at `f2`, same command | `protectedMasters 0`, `IMG_00001.jpg` written over it (place can't find it, content no longer matches) |

Both images are detached.

**S-A, the app, library A** (`IMG_00001.JPG`, `IMG_00002.JPG`,
`RAW_00003.DNG`, `RAW_00004.DNG` in `$P` = `appA-photos/Shoot-001`):

    wait 2; print items; selectall; export window; export set format=jpeg names=original dest=$P size=long:200 reveal=off; export print; export run overwrite; export run overwrite; export run keepboth; export run skip; export close; deselectall; focus IMG_00002; export window; export run overwrite; export close; wait 1; print items; snapshot $S/appA-after.png; quit

| Run | Printed |
|---|---|
| overwrite 1 | `export conflicts 2 originals 2`; "They are all originals in the library. Originals are never replaced, so the new files are written under numbered names."; `exported 4 … originals kept 2`: `IMG_00001-2.jpg`, `IMG_00002-2.jpg`, `RAW_00003.jpg`, `RAW_00004.jpg` |
| overwrite 2 | `export conflicts 4 originals 2`; "2 of them are originals in the library. Originals are never replaced, so those photos are written under numbered names."; `IMG_…-3.jpg`, `RAW_00003.jpg` and `RAW_00004.jpg` replaced |
| keepboth | same count and message; `IMG_…-4.jpg`, `RAW_…-2.jpg`; `originals kept 2` (decision 3) |
| skip | `exported 0 … skipped 4 originals kept 0` |
| one photo, overwrite | `export conflicts 1 originals 1`; "It is an original in the library. Originals are never replaced, so the new file is written under a numbered name."; `IMG_00002-5.jpg` |

The messages quoted in S-A, S-B and S-C are the final ones (`review.md` R5,
after the owner's P1 finding). This pass's runs printed the earlier R1
wording ("…so Replace, like Keep Both, writes…"); the counts, cases and file
names above are what the runs showed. The scripts were not run again after
R5 (no builds in the sign-off pass); the owner read the final text in P1.

`print items` before and after: `IMG_00001:0 IMG_00002:0 RAW_00003:0
RAW_00004:0`. In the snapshot the grid's four photos all show their pictures
and badges, with no offline mark (the glass panes come out blank, a known
limit of `snapshot`). Masters: all 4 OK.

**S-B, the app, library B** (`IMG_00001.JPG`, `RAW_00002.DNG`):

    wait 2; selectall; export window; export set format=jpeg names=original dest=$P size=long:200 reveal=off; export run overwrite; export run overwrite; export close; print items; quit

Run 1: `conflicts 1 originals 1`, "It is an original…", `IMG_00001-2.jpg`.
Run 2: `conflicts 2 originals 1`, "1 of them is an original in the library.
Originals are never replaced, so that photo is written under a numbered
name.", `IMG_00001-3.jpg`
and `RAW_00002.jpg` replaced. Masters OK.

**S-C, the app, library A: content and a link.** `$S/backupA` holds an exact
copy of `IMG_00001.JPG` named `IMG_00001.jpg` and an earlier
`RAW_00003.jpg`. `$S/linkA` is a symbolic link to `$P`.

    wait 2; selectall; export window; export set format=jpeg names=original dest=$S/backupA size=long:200 reveal=off; export run overwrite; export set dest=$S/linkA; export run overwrite; export close; quit

To `backupA`: `conflicts 2 originals 1`, "1 of them is…", written
`IMG_00001-2.jpg`, `IMG_00002.jpg`, `RAW_00003.jpg` (replaced; the render was
byte-identical to the earlier one), `RAW_00004.jpg`. The copy is unchanged.
Through `linkA`: `conflicts 4 originals 2`, `IMG_00001-5.jpg`,
`IMG_00002-6.jpg`, both `RAW_…jpg` replaced. Masters OK.

**Afterwards:** no `Gus` process is running (`pgrep -x Gus` finds nothing).
Nothing under `~/Library/Application Support/Gus` is newer than the start of
this pass. The only preference file written is
`me.sesser.gus.debugtest.plist`. Both disk images are detached.
`/Applications` was not touched, and the working tree is as it was.

## For a person

Each item below covers the designer's manual checks and `status.md`'s "For a
person" items named with it. Build with `Scripts/build-app.sh` and run with
`--library-root` on a scratch library from `photobench` (or a copy of your own
photos). Use File ▸ Add Folder Without Copying… on a folder of JPEGs.

- **P1, the alert's look** (M1, M3; `status.md` items 1 and 3). Select every
  photo of a project. File ▸ Export…, JPEG, Original Name, the project's own
  folder, Export. Under the usual title, read "They are all originals in the
  library. Originals are never replaced, so the new files are written under
  numbered names." (`review.md` R5): wrapped, nothing cut off, same four buttons in the same order,
  Keep Both the default. Repeat with one photo ("It is an original…"). Then
  export a few photos once to that folder with a template such as
  `{name}-web`, and export them again together with others, so that both
  kinds of file are in the way: the title counts all of them, and the message
  "N of them are originals…" counts only the originals.
- **P2, a real click** (M2; `status.md` item 2). In P1's alert, click
  **Replace** with the mouse. New `-2` files appear in the Finder, and the
  originals still open in the loupe and in Quick Look. No photo shows as
  missing or changed. Open the alert again: Return chooses Keep Both, Esc
  cancels.
- **P3, exact copies and the wait** (M4; `status.md` item 5). Copy, in the
  Finder, a project folder of JPEG originals, the largest you have. Export
  those photos as JPEG with Original Name into the copy. Because names match
  regardless of case, each copy is in the way. The alert counts the copies
  as originals, and Replace writes `-2` files and leaves the copies as they
  were. Watch how long the question takes to appear: it should not look like
  a hang. Each copy is read in full twice, once for the count and once
  under Replace.
- **P4, external and network volumes** (`status.md` item 4; code review
  question 2). With originals on an external disk, export into their own
  folder with Replace: numbered names, originals unchanged. If you have
  masters on a NAS, time from Export to the question, and from Replace to
  the start, ideally once with the share asleep.

## Follow-up

**Sign-off, 2026-11-13.** The owner ran P1 to P4 on a scratch library and
signed off with **no checks left open**. Commit signed off: `371aa4a`
("Export never overwrites a catalogued master (#160)").

- **P1:** done. The owner found the wording "Replace, like Keep Both,
  writes…" confusing and ruled to drop the comparison. The engineer changed
  the messages (`status.md`, "Owner's findings at sign-off"), the designer
  accepted the five final messages in `review.md` R5, and code-reviewer
  closed it in its sixth pass. The quotes in Scripts and P1 above now give
  R5's text. Fixed.
- **P2, P3, P4:** done by the owner, nothing found.
- Code-review C8 and C9 (the note under Findings): confirmed fixed in
  `code-review.md`'s fifth pass (2026-11-13).
- **Not part of #160:** the owner also found that Fujifilm RAF files do not
  render in the loupe. That is issue #161, filed apart. It was not caused by
  this branch and was not checked in this QA.

Not rerun by qa-tester after R5: no builds or tests in this pass.
