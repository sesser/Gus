Issue: #160

# Export overwrites masters: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or `design.md`,
`docs/WORKFLOW.md` "Bug fixes") for GitHub issue #160. Branch
`bug/export-overwrites-masters`, cut from `develop` at `cd992f9`. Nothing is
committed yet.

**Status: Done.** The first review's findings are fixed ("Review findings"
below: C1, C2, C3 and F1; C4 left as ruled), so is the second pass's C5, by
content, as the owner ruled on 2026-11-12, and the third pass's C6 (memory
while hashing) and the fourth pass's C8 and C9 (tests only). C4 and C7 go
to one follow-up issue, as ruled. The owner's sign-off finding P1 (the
alert's wording) is fixed ("Owner's findings" below). Next: the second pass
that a change after review takes (code-reviewer; the designer, since the
alert's text changed; qa-tester for the strings), then back to the owner.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `cd992f9`).
1. Add a folder of JPEGs to a library (File ▸ Add Folder Without Copying…),
   or a folder with a RAW+JPEG pair.
2. Select the photos, File ▸ Export…, JPEG, Original Name, and choose that
   same folder (the project's source folder) as the destination.
3. Export. The sheet says the files already exist; choose **Replace**.

The same without a question: `photocli export --version N --to <that folder>
--policy overwrite`.

Other ways into the same fault: a template that names an export like another
photo's master (`b` for a photo whose neighbor is `b.jpg`); a RAW whose
export name is its pair's JPEG; the folder chosen through a symbolic link;
masters named `IMG_1.JPG` (the export is `IMG_1.jpg`, the same file wherever
names ignore case, which is the default on a Mac).

**Expected.** No original is changed, whatever is chosen. "Originals are
never moved, copied or modified" (`CLAUDE.md`, Architecture rules). Owner
ruling, 2026-11-12: export must never overwrite a catalogued master.

**Actual.** The master is replaced by the rendered export: the original is
gone, and the catalog row now points at a file with another content hash.

**Root cause.** The export decides every file name up front in
`ExportNaming.plan` (`Sources/PhotoCore/Export/ExportNaming.swift`). For a
name that was taken, the plan asked one question, `fileExists`, and under
`.overwrite` returned `.write(url, replacing: true)`. `ExportRenderer.write`
then swapped the file in with `FileManager.replaceItemAt`. Nothing between
the two knew what the existing file was: the plan never saw the catalog, so a
master was a file like any other. The app at least asked (the alert's
Replace); `photocli export --policy overwrite` did not, and the alert gave no
hint that the files in the way were originals.

**Tests that fail without the fix** (Swift Testing). On `develop` they don't
compile (the plan had no notion of masters). With the protection switched
off behind the new interface (a trial: `ExportNaming.entries` given no
masters; since restored) 12 tests fail with 31 issues, the job and command
ones because the masters' bytes changed:

- `Tests/PhotoCoreTests/ExportMasterProtectionTests.swift`
  - "Export naming: masters are never replaced": 7 of its 8 tests
    (`aPhotoExportedOverItsOwnMasterGetsANumberedName`,
    `anotherPhotosMasterIsNotReplacedEither`,
    `numberedNamesAvoidMastersAndExistingFiles`,
    `namesMatchAsTheFileSystemComparesThem`, `anOrdinaryFileIsStillReplaced`,
    `aMissingMastersPlaceIsNotTaken`,
    `clashesCountExistingFilesAndTheMastersAmongThem`).
  - "Export job: masters are never replaced": "Replace into the photos' own
    folder leaves every master as it was", "A template that names an export
    like another photo's master does not replace it", "The source folder
    reached through a symbolic link is still the source folder", "A master
    whose name differs from the export's only in case is not replaced".
- `Tests/PhotoCoreTests/CommandTests.swift`: "export --policy overwrite never
  writes over a master (issue #160)".

Added after the review, each failing when its fix is taken out again (three
more trials, since restored): "A master on a volume mounted elsewhere than
the catalog recorded is not replaced" and
`aVolumeIsPlacedWhereItIsMountedNowAndWhereItWasRecorded` (C1), "When the
catalog can't say where the masters are, nothing is written and no folder is
made" (C2, C3), "A missing master's place is kept when the export makes its
folder again" (C3's ordering).

Added for C5, each failing with content matching switched off (two trials,
in the job and in the plan, since restored): "A master on a volume the
catalog can't recognize is known by its content and not replaced", "A file
with a master's content under another name is not replaced either",
"export --policy overwrite never writes over a master on a volume the
catalog can't recognize (#160, C5)", and three of the four tests of "Export
naming: a file with a master's content is never replaced".

## The fix

One rule, in PhotoCore so that the app and `photocli` share it: **a name
that is a catalogued master's is never given to an export, and a file that
has a catalogued master's content is never replaced.** The photo gets the
next free numbered name instead (`IMG_1-2.jpg`), written without replacing
anything, exactly as Keep Both does.

A master is known in two ways. By **place**: the folder and name the catalog
has for it, wherever its volume is mounted (C1). By **content** (C5): the
size and SHA-256 the catalog keeps for every master, for files on a volume
the catalog can't recognize, where no place can be trusted.

| Policy | Name is an ordinary existing file | Name is a master's place | Existing file has a master's content |
|---|---|---|---|
| `.overwrite` (Replace) | replaced, as before | numbered name, nothing replaced | numbered name, nothing replaced |
| `.keepBoth` | numbered name, as before | numbered name, as before | numbered name, as before (not read) |
| `.skip` | skipped, as before | skipped when the file is there, as before | skipped, as before (not read) |

- `Sources/PhotoCore/Catalog/MasterFiles.swift` (new). `MasterFiles` is the
  set of places masters are, and `Catalog.masterFiles(mounted:)` builds it
  for the whole catalog, not only for the photos being exported. Two files
  are the same when they are in the same folder under names the file system
  would take for one:
  - **Volumes** (C1). A volume's masters are placed at the mount point the
    catalog recorded (where export reads them from) **and** wherever a volume
    of the same identity is mounted now (`VolumeAvailability.mountedVolumes()`,
    injectable as `mounted:`, like `refreshVolumeAvailability(mounted:)`). A
    volume mounted at several paths is placed at each. Nothing is written to
    the catalog: export stays a read.
  - **Folders** are compared as the file system resolves them: links
    followed, then the folder's canonical path (`URLResourceKey.canonicalPathKey`),
    which gives the spelling on disk. That makes a symbolic link, `/tmp`
    against `/private/tmp`, `..`, the `/System/Volumes/Data` prefix and, on a
    case-insensitive volume, another capitalization all the same folder.
    Links are followed first because a URL's resource values describe a link
    itself when it is the last part of the path (the job test with a linked
    destination caught this).
  - **Names** are compared after Unicode decomposition and case folding,
    which is what APFS and HFS+ do by default. On a case-sensitive volume
    this protects a name too many, never one too few.
  - **Content** (C5). The masters read also brings every master's size and
    SHA-256 (`image.fileSize`, `image.contentHash`), kept as two sets.
    `holdsContent(ofFileAt:)` compares the file's size first and reads the
    file only when that is some master's size, so an ordinary file costs one
    `stat` (0.05 ms in a debug build). A file of a master's size that can't
    be read, or a read cut short by cancellation (checked between 1 MiB
    chunks), counts as a master: nothing is replaced when it can't tell. A
    link is followed to the file it names. The file is read with `read(2)`
    into one buffer used again for every chunk, so hashing holds 1 MiB
    whatever the file's size and however many files a plan reads (C6).
  - Each folder is resolved once, and names are folded only for the folder
    asked about: 100,000 masters in 500 folders take 0.19 s to load with
    their sizes and hashes (0.12 s before C5; debug build), off the main
    actor.
- `Sources/PhotoCore/Export/ExportNaming.swift`. `plan` takes the masters as
  a required argument (`masters:`; `.none` where there is no catalog), next
  to the injected `fileExists`. `entries` is `plan` with what stood in the
  way of each name (a second form takes the folder's masters already
  resolved, `protected:`, for the job); `clashes` replaces `existingCount`
  and also counts the masters among the existing files;
  `ExportClashes.originals` says which of the alert's four cases that is.
  Numbered names avoid masters' names too. Content is asked only where the
  answer decides something: in a plan, for a file that exists, is no master
  by place and would be replaced (`.overwrite`); in `clashes`, for every
  existing file that is no master by place, since the choice comes after the
  count. `holdsMasterContent:` injects the question in tests, as
  `fileExists:` does.
- `Sources/PhotoCore/Export/ExportJob.swift`. `run` reads the masters first
  and takes those of the destination, then makes the destination folder,
  then plans (C3). If the catalog can't be read it writes nothing, makes no
  folder and reports every photo as failed, rather than export unprotected; a
  stopped export is reported as stopped. `ExportSummary.protectedMasters`
  counts the photos renamed for this. `clashes(for:settings:in:)` is what the
  sheet asks before it starts (it also moves that check off the main actor).
  `mountedVolumes` is the injectable source of current mounts.
- `Sources/PhotoCore/Commands/LibraryCommands.swift`. `photocli export`
  prints `"protectedMasters": N` (a new key; nothing else in the object
  changed) and `--policy`'s help says masters are never overwritten.
- `Sources/PhotoApp/Model/ExportModel.swift`, `Views/ExportSheet.swift`.
  The existing-files alert's message is one of four
  (`ExportModel.conflictMessage(count:masters:)`, review.md R1; the wording
  as the owner ruled at sign-off, P1). Title and buttons are unchanged (R2). With no originals among the files the alert is
  as before.
- `Sources/PhotoUI/Resources/Localizable.xcstrings`. Three new entries,
  added by hand (one with singular and plural).
- `Sources/PhotoApp/Model/DebugExportCommands.swift`. `export run` prints
  the originals among the conflicts, the alert's message, and `originals
  kept N` in its summary line.
- `docs/USER_GUIDE.md`. Export and Scripting say so.

Decisions taken where the ruling left room (all on the side of the
originals; say so if any should go the other way):

1. **A master's place is protected even when its file is missing.** A file
   written where a deleted or moved master belongs would later be taken for
   it. Such a name clashes with no file, so the alert doesn't count it; the
   export is numbered silently.
2. **Replace into a folder of originals numbers up on every run**
   (`-2`, then `-3`…), as the ruling says ("the next free numbered name").
   The earlier `-2` export is an ordinary file, but the photo's first name is
   still its master's, so the plan never gets to it.
3. **`protectedMasters` counts under every policy** that writes: under Keep
   Both those photos would be numbered anyway, and they are counted too.
   Photos skipped under Skip are in `skippedExisting` only. One exception
   since C5: a master known only by its content is counted under Replace
   alone, because under Keep Both and Skip the file is never read (nothing
   there can be replaced, and reading it just to count would cost a hash).
4. **A master's content under another name is protected too** (C5; the
   coordinator asked for the choice to be stated). An existing file with a
   master's bytes is never replaced, whatever it is called and wherever it
   is. On a volume the catalog can't recognize there is no telling the
   master from a copy of it, or a renamed master from a backup, and the name
   is the one thing the catalog can't vouch for there. The cost: an exact
   copy of an original (a backup folder) is left alone and the export beside
   it gets a numbered name, and the alert counts it among the originals.
   The other way round, a file with a master's name and other bytes at a
   place the catalog doesn't know is an ordinary file and is replaced: no
   rule could call it a master.

No migration, no pipeline bump, no rendering change, no golden touched.
Sidecars (`.xmp`) are not part of this: an export never has that extension.

## Review findings

From `code-review.md` and `review.md` (2026-11-12), relayed by the main
session.

| # | Finding | Result |
|---|---|---|
| C1, blocker | Masters were placed only at each volume's recorded mount path, so `photocli export --policy overwrite` replaced a master on a volume mounted elsewhere than recorded. | **Fixed.** `Catalog.masterFiles(mounted:)` also places every volume wherever its identity is mounted now, at each such mount, and writes nothing to the catalog. Tests: `aVolumeIsPlacedWhereItIsMountedNowAndWhereItWasRecorded` (injected mounts, two current mounts, a root-level master, the catalog's `mountPath` unchanged afterwards) and the job test "A master on a volume mounted elsewhere than the catalog recorded is not replaced" (injected through `ExportJob.mountedVolumes`; its last line shows the recorded path alone misses the master). The reviewer's case run again on a real remount, R1 below. |
| C2, should fix | No test on the branch that writes nothing when the masters can't be read. | **Fixed.** "When the catalog can't say where the masters are, nothing is written and no folder is made": `items:` passed, the in-memory catalog's `image` table renamed, then Replace into the masters' own folder: nothing written, the folder byte for byte as before, one `writeFailed` per photo, not reported as stopped; `clashes` throws. With the `catch` changed to fall back to no masters (trial) it fails with 5 issues. |
| C3, nit | The destination folder was made before the masters were read, so a failed read left an empty folder. | **Fixed.** The masters are read first. The destination's masters are taken before the folder is made too, because a folder resolves differently once it exists (decision 1 would otherwise be lost for a deleted folder of masters that the export makes again; "A missing master's place is kept when the export makes its folder again" fails when the two are taken on either side of making the folder). C2's test checks that no folder is left. |
| C4, nit | `requestExport` checks `isExporting` once and then awaits twice; Return pressed twice can start two exports. Older than this branch, which lengthens the gap. | **Left, as ruled.** No original is at risk (`replacing: false` moves never overwrite). Proposed as a follow-up below. |
| F1, designer | The message had no subject of its own and did not say when Replace and Keep Both had become the same choice. | **Fixed** as R1 rules: `conflictMessage(count:masters:)` with four messages, the exact English of review.md's table; the old key removed, three keys added; `ExportSheet` passes the clash count; the debug script prints the message. The choice of case is `ExportClashes.originals` in PhotoCore, where it can be tested ("Export clashes: how many of the files in the way are originals", 4 tests); the strings themselves are in the app target, which has no tests, and are checked in the bundle (T1 to T4 below). |
| R2, R3 | Keep Replace as built; no Activity row. | Nothing changed. |

Second pass (`code-review.md`, "Second pass, 2026-11-12"):

| # | Finding | Result |
|---|---|---|
| C5, should fix | A volume with no UUID and no remount URL has its mount point in its identity, so mounted elsewhere it matches nothing and its masters were still replaced. | **Fixed by content** (option (b); owner ruling, 2026-11-12: "never overwrite a catalogued master" also covers volumes the catalog cannot recognize). Place matching is unchanged. Tests: the job test "A master on a volume the catalog can't recognize is known by its content and not replaced" (a `mount:` identity recorded at one path and mounted under another; beside the master a file of the same size and other bytes, which is still replaced; `clashes` is 2 with 1 original), "A file with a master's content under another name is not replaced either" (decision 4; Keep Both does not read it), the `photocli` test, 4 naming tests (what is read under which policy) and 5 on `holdsContent` (size first, fail closed on an unreadable file and on cancellation, links followed, the catalog's sizes and hashes). The reviewer's FAT32 case run again, R2 below. |

Cost of C5, for the reviewer: one `stat` per existing file that would be
replaced, a read only when the size is a master's. The app asks twice (the
count before the alert, then the plan under Replace), so a file of a
master's size is read twice. The worst case is many existing files that
share their exact size with some master (uncompressed TIFFs or DNGs of one
camera exported over files of the same kind): each is read once per pass,
cancellable between chunks. Memory while reading is one 1 MiB buffer (C6
below; my first version held everything it read). The reviewer measured the
masters read at about 36 MB more resident for 100,000 masters (names, sizes
and hashes together) while it is in use; my earlier "about 10 MB" counted
the two sets only and was an estimate.

Third pass (`code-review.md`, "Third pass, 2026-11-13"):

| # | Finding | Result |
|---|---|---|
| C6, should fix | `MasterFiles.hash(of:)` read with `FileHandle.read(upToCount:)`, which hands back autoreleased data, inside a synchronous loop with no autorelease pool; a count or a plan is one synchronous call, so every chunk of every file it hashed stayed in memory until it returned (measured by the reviewer: 25 MiB to 2,082 MiB for one 2 GiB file). | **Fixed.** The file is read with `read(2)` into one 1 MiB buffer that is used again for every chunk (`MasterFiles.hashChunkSize`), so nothing depends on an autorelease pool: hashing holds one chunk whatever the file's size and however many files a plan reads. Same hash, same fail-closed answers, a cancellation check before every chunk as before. Tests: `aFileOfSeveralChunksHashesAsTheCatalogDoes` (two and a half chunks and an empty file against `Digest.sha256Hex` and `SHA256ContentHasher`; a missing file throws) and the footprint guard below. The FAT32 case run once more with the new reader: `"protectedMasters": 1`, the master unchanged. |
| C7, nit | The count before the alert reads files and nothing can stop it or shows that it runs; cancel, reopen and the old request's alert comes up on the new sheet. | **Left, as ruled**: with C4 in one follow-up issue the main session files. |

The footprint guard, `hashingALargeFileHoldsOneChunkNotTheFile`: a 1 GiB
sparse file (no disk used) of a master's size is read whole by
`holdsContent`, and the process's `phys_footprint` (`task_vm_info`) may grow
by less than half of that. Measured alone: growth 0 MiB with the fix; with
the `FileHandle` loop put back (trial, since restored) 1,052 MiB and then
1,028 MiB on each of the other four attempts, and the test fails. How
reliable: the footprint is the whole process's, and other tests run beside
this one, so the test takes the best of up to five attempts (the others can
only add to one attempt, and the leak shows in every one) with a limit of
512 MiB. It takes 0.4 s. It is a measurement, not a proof; see C9 for how
often it could fail without a fault. The fix itself does not rest on the
test: one reused buffer can't hold more than itself.

Fourth pass (`code-review.md`, "Fourth pass, 2026-11-13"; tests only, no
source changed):

| # | Finding | Result |
|---|---|---|
| C8, should fix | The branch of `MasterFiles.hash(of:)` for a read that fails after the file opened had no test. | **Fixed.** `aFileThatOpensAndCannotBeReadCountsAsAMaster`: a folder opens and then can't be read; `hash(of:)` must throw a `POSIXError` with `EISDIR` (the read's error, so the open went through and it is that branch), `holdsContent` takes a folder of a master's size for a master, and one of another size is never opened and is ordinary. |
| C9, should fix | The footprint guard could fail without a fault, by the reviewer's estimate about once in 300 full runs: limit a quarter of the file, three attempts. | **Fixed** as the reviewer proposes, both ways at once: the limit is half the file (512 MiB) and the attempts are five. The reviewer's samples had no three moments in a row over half the file in about 21,000; five in a row is rarer still. It still catches the fault: with the `FileHandle` loop back every attempt grows by about 1,028 MiB, twice the limit. Cost in a failing run only: five attempts hold about 5 GiB until the process ends. An exit test (a process of its own) was not used: I did not confirm that Swift Testing's exit tests work with CI's toolchain. Two full runs of the suite passed with it. |

Seen while fixing C6 and not changed: `SHA256ContentHasher.contentHash` (the
importer) and `CopyImporter.hash(of:uncached:)` read with the same
`FileHandle.read(upToCount:)` loop. Whether they hold their chunks too
depends on where their callers' autorelease pools drain; not measured.
Proposed as a follow-up below.

### Owner's findings at sign-off

| # | Finding | Result |
|---|---|---|
| P1 (owner, 2026-11-13) | The two "all originals" messages said "Replace, like Keep Both, writes…": the comparison confuses. Ruling: drop it; the messages only say what happens. Replace stays on the alert (R2). The "some originals" message to be tightened in the same plain style, without comparing buttons, keeping its plural forms; the message with no originals unchanged. | **Fixed.** The final English, as in the String Catalog: |

- No originals (unchanged): "Keep Both writes the new files under numbered
  names."
- Some of several are originals, one: "%lld of them is an original in the
  library. Originals are never replaced, so that photo is written under a
  numbered name."
- Some of several are originals, other: "%lld of them are originals in the
  library. Originals are never replaced, so those photos are written under
  numbered names."
- The one file is an original: "It is an original in the library. Originals
  are never replaced, so the new file is written under a numbered name."
- All of several are originals: "They are all originals in the library.
  Originals are never replaced, so the new files are written under numbered
  names."

The two "all" messages are the owner's words. The "some" message is mine in
their style: it no longer names Replace or Keep Both, so it also no longer
says that Keep Both numbers every new file (the no-originals message still
says that, and it is not what this message is about). Like the owner's own
wording, the messages with originals say what happens when the photos are
written; under Skip Them they are skipped, as the button says.

Changed for P1: the three keys in `Localizable.xcstrings` (the old three
removed, the new ones at their sorted places, the "some" key with `one` and
`other`), `ExportModel.conflictMessage(count:masters:)`, and one sentence of
`docs/USER_GUIDE.md` ("When all of them are originals, the sheet says so,
and the new files are written under numbered names."). `DebugExportCommands`
prints whatever `conflictMessage` returns, so its output follows without a
change of its own. The tests of the message are those of
`ExportClashes.originals` (which case, in PhotoCore); the case is chosen as
before, so they are unchanged, and no test holds the strings (the app target
has no tests): `LocalizationTests` checks that each literal has its catalog
entry, and the strings are read from the rebuilt bundle (U1 to U4 below).
No behavior changed. This supersedes R1's wording in `review.md` (F1) for
these three messages; the four cases themselves are R1's.

Reviewer's question 2 (network volumes): not measured here either; no
network share to test on. The masters read now also lists the mounted
volumes once (`FileManager.mountedVolumeURLs` with resource values), off the
main actor. A timing on a NAS is still open and is in "For a person".

## Build and tests

On macOS 27.2.1, SDK 27.2.

| | Baseline (`cd992f9`) | First pass | After the review fixes | With C5 | With C6 |
|---|---|---|---|---|---|
| `swift build` | clean | clean, no new warnings | clean, no new warnings | clean, no new warnings | clean, no new warnings |
| `swift test` | not run before the change; 816 by subtraction | 834 tests in 124 suites passed, 1 known issue | 842 tests in 126 suites passed, 1 known issue | 854 tests in 128 suites passed, 1 known issue | 856 tests in 128 suites passed, 1 known issue (run twice); with C8's test 857 in 128 (run twice) |
| `Scripts/build-app.sh` | not run | builds | builds | builds (`vtool`: minos 15.0, sdk 27.2) | not built again (no behavior changed; `photocli` run on the FAT32 case) |

After the owner's P1 (wording only): `swift build` clean, `swift test` 857
tests in 128 suites passed, 1 known issue, `Scripts/build-app.sh` builds.

41 new tests in all: 8 in "Export naming: masters are never replaced", 4 in
"Export naming: a file with a master's content is never replaced", 4 in
"Export clashes: how many of the files in the way are originals", 4 in
"Master files", 8 in "Master files: a master's content, wherever it is", 1
in "Master files: volumes mounted elsewhere than recorded", 10 in "Export
job: masters are never replaced", 2 in "Commands".
Existing tests changed only where the signature did (`masters: .none` at six
`ExportNaming.plan` calls; `existingCount` became `clashes`). The existing
`videosOfflineMastersAndCancellationAreReported` caught a regression while I
worked (a cancelled export reported its photos as failed, because the
masters read throws when cancelled); fixed in `ExportJob.run`.

Two warnings in the test target are older than this branch and untouched
(`SmartAlbumTests.swift:165`, `VirtualCopiesTests.swift:170`).

| What the Bug section asks | Test |
|---|---|
| Same-name master | `aPhotoExportedOverItsOwnMasterGetsANumberedName`; job: "Replace into the photos' own folder…" (`b.jpg` over itself) |
| Another photo's master | `anotherPhotosMasterIsNotReplacedEither`; job: the same test (`a.DNG` exports as its pair's `a.jpg`) and "A template that names an export like another photo's master…" (a master outside the batch) |
| Symlinked path | "Master files": `aFolderReachedThroughASymbolicLinkIsTheSameFolder`; job: "The source folder reached through a symbolic link…" |
| Case-insensitive match | `namesMatchAsTheFileSystemComparesThem`, `aFolderSpelledInAnotherCaseIsTheSameWhereTheVolumeSaysSo`; job: "A master whose name differs from the export's only in case…" |
| Ordinary file still replaced | `anOrdinaryFileIsStillReplaced`; job: "A file that is no master is replaced, in the masters' folder too"; the older `existingFilesAreSkippedOverwrittenOrKept` |
| `photocli --policy overwrite` | "export --policy overwrite never writes over a master (issue #160)" |
| The whole catalog is covered | `theCatalogListsEveryMasterWhereExportReadsIt` |
| A volume mounted elsewhere than recorded (C1) | `aVolumeIsPlacedWhereItIsMountedNowAndWhereItWasRecorded`; job: "A master on a volume mounted elsewhere than the catalog recorded is not replaced" |
| Nothing written when the masters can't be read (C2, C3) | "When the catalog can't say where the masters are, nothing is written and no folder is made" |
| A master on a volume the catalog can't recognize (C5) | job: "A master on a volume the catalog can't recognize is known by its content and not replaced"; "Commands": "export --policy overwrite never writes over a master on a volume the catalog can't recognize (#160, C5)" |
| Same size, other content is still replaced (C5) | `theSameSizeWithOtherBytesIsAnOrdinaryFile`; the same job test (`a.jpg` beside the master) |
| Same content, another name (C5, decision 4) | `aFileWithAMastersBytesIsOneWhateverItsNameOrPlace`; job: "A file with a master's content under another name is not replaced either" |
| Content read only where it decides something (C5) | `replaceNumbersItAndStillReplacesTheOrdinaryFile`, `nothingIsReadWhereNothingWouldBeReplaced`, `aMasterByPlaceIsNotReadAgain`, `theQuestionCountsThemBeforeAPolicyIsChosen`, `aFileIsReadOnlyWhenItsSizeIsAMasters`, `aReadCutShortByCancellationCountsAsAMaster` |
| Hashing holds one chunk, not the file (C6) | `hashingALargeFileHoldsOneChunkNotTheFile`, `aFileOfSeveralChunksHashesAsTheCatalogDoes` |
| A read that fails counts as a master (C8) | `aFileThatOpensAndCannotBeReadCountsAsAMaster` |
| A missing master's place (decision 1) | `aMissingMastersPlaceIsNotTaken`; job: "A missing master's place is kept when the export makes its folder again" |
| The alert's counts and its four cases (F1) | `clashesCountExistingFilesAndTheMastersAmongThem`, `clashes` in three job tests, and the four tests of "Export clashes: how many of the files in the way are originals" |

Every job and command test compares the masters' bytes before and after.

## Debug-script checks

Against a copy of the bundle with the identifier `<release id>.debugtest`,
re-signed ad hoc, started from a shell with `--library-root` on a scratch
library from `photobench generate` (the generator names JPEGs
`IMG_0000N.JPG`, so every export name differs from its master's in case
only). `$P` is the photos' folder, `$O` an empty folder. SHA-256 of the
masters taken before and compared after each run: no change. The test copy
remembers TIFF from older runs, so `format=jpeg` is needed for the names to
clash.

First pass (4 JPEGs; the alert message then was the first wording):

| | Script | Result |
|---|---|---|
| S1, ordinary files | `wait 1; addfolder $P; waitimport; wait 2; selectall; export set format=jpeg dest=$O size=long:200 reveal=off; export run keepboth; export run overwrite` | First run writes 4. Second: `export conflicts 4 originals 0`, the alert message as before the fix, the same 4 names written again (`originals kept 0`): replaced |
| S2, Replace into the photos' folder | `…; export set dest=$P; export run overwrite; export run overwrite` | `export conflicts 4 originals 4`, `exported 4 … originals kept 4`, names `IMG_0000N-2.jpg`; the second run writes `-3`. Masters unchanged |
| S3, Skip there | `…; export run skip` | `exported 0 … skipped 4 originals kept 0` |
| S5, `photocli` | `swift run photocli export --version 1 --version 2 --to $P --policy overwrite --settings '{"sizing": "longEdge", "edgeLength": 200}' --library-root <scratch>` | `"protectedMasters": 2`, written `IMG_00001-3.jpg` and `IMG_00002-2.jpg`, no failures. Masters unchanged |

After the review fixes (the rebuilt bundle; library A is 2 JPEGs and 2
DNGs, library B 1 JPEG and 1 DNG, each exported into its own folder):

| | Script | Result |
|---|---|---|
| T1, all originals, several | A: `wait 2; selectall; export window; export set format=jpeg dest=$P size=long:200 reveal=off; export run overwrite` | `export conflicts 2 originals 2`, message "They are all originals in the library. Originals are never replaced, so Replace, like Keep Both, writes the new files under numbered names." Written `IMG_00001-2.jpg`, `IMG_00002-2.jpg`, `RAW_00003.jpg`, `RAW_00004.jpg` |
| T2, some originals | A: `…; export run overwrite` again | `export conflicts 4 originals 2`, message "2 of them are originals in the library. Originals are never replaced, so Replace writes those photos under numbered names. Keep Both gives every new file a numbered name." The two `RAW_…jpg` replaced, the two `IMG_…` written as `-3` |
| T3, the one file is an original | A: `…; deselectall; focus IMG_00002; export window; export run overwrite` | `export conflicts 1 originals 1`, message "It is an original in the library. Originals are never replaced, so Replace, like Keep Both, writes the new file under a numbered name." Written `IMG_00002-4.jpg` |
| T4, one original of two | B: `…; selectall; export window; export set …; export run overwrite; export run overwrite` | Second run: `export conflicts 2 originals 1`, message "1 of them is an original in the library. Originals are never replaced, so Replace writes that photo under a numbered name. Keep Both gives every new file a numbered name." |
| R1, C1 on a real remount | A 20 MB APFS disk image (`hdiutil create`, `attach -mountpoint …/m1 -nobrowse`) with `Shoot/IMG_00001.JPG`, and another `IMG_00001.JPG` on the internal disk, both added to a scratch library by the test copy (`addfolder`). Control at `m1`: `photocli export --version 2 --to …/m1/Shoot --policy overwrite`. Then `hdiutil detach`, attach the same image at `…/m2`, and the same command with `--to …/m2/Shoot` | Control: `"protectedMasters": 1`, `IMG_00001-2.jpg`. Remounted: `"protectedMasters": 1`, `IMG_00001-3.jpg`, no failures; the master's SHA-256 (`4178360e…`) unchanged; the catalog's `volume.mountPath` still `…/m1` (nothing written). Before the fix the reviewer got `"protectedMasters": 0` and the master replaced here |

(T1 to T4 quote R1's wording, which the owner's P1 has since replaced; U1
to U4 below are the same four cases with the final strings.)

With C5 (the bundle rebuilt again):

| | Script | Result |
|---|---|---|
| R2, C5 on a real FAT32 volume with serial 0 | A 40 MB FAT32 disk image, its file system made again with `newfs_msdos -F 32 -I 0`, mounted at `…/f1`, with `DCIM/IMG_00001.JPG`; another `IMG_00001.JPG` on the internal disk; both added to a scratch library by the test copy. The catalog has the volume as `mount:NOUUID@…/f1`. Control at `f1`: `photocli export --version 2 --to …/f1/DCIM --policy overwrite`. Then detach, attach at `…/f2`, the same command with `--to …/f2/DCIM`; then the test copy: `wait 2; deselectall; focus 1; export window; export set format=jpeg dest=…/f2/DCIM size=long:200 reveal=off; export run overwrite` | Control: `"protectedMasters": 1`, `IMG_00001-2.jpg`. Remounted, `photocli`: `"protectedMasters": 1`, `IMG_00001-3.jpg`, no failures. The app: `export conflicts 1 originals 1`, "It is an original in the library…", `originals kept 1`, `IMG_00001-4.jpg`. The master's SHA-256 (`4178360e…`, 124,836 bytes) unchanged after each. Before C5 the reviewer got `"protectedMasters": 0` and the master replaced by the 7 KB export here |

After the owner's P1 (the bundle rebuilt; fresh scratch libraries, A with 2
JPEGs and 2 DNGs, B with 1 JPEG and 1 DNG, each exported into its own
folder with Replace; the masters' SHA-256 unchanged after both):

| | Script | Result |
|---|---|---|
| U1, all originals, several | A: `wait 1; addfolder $P; waitimport; wait 2; selectall; export window; export set format=jpeg dest=$P size=long:200 reveal=off; export run overwrite` | `export conflicts 2 originals 2`, message "They are all originals in the library. Originals are never replaced, so the new files are written under numbered names." `originals kept 2` |
| U2, some originals | A: `…; export run overwrite` again | `export conflicts 4 originals 2`, message "2 of them are originals in the library. Originals are never replaced, so those photos are written under numbered names." |
| U3, the one file is an original | A: `…; deselectall; focus IMG_00002; export window; export run overwrite` | `export conflicts 1 originals 1`, message "It is an original in the library. Originals are never replaced, so the new file is written under a numbered name." |
| U4, one original of two | B: the same as U1 and U2 | Second run: `export conflicts 2 originals 1`, message "1 of them is an original in the library. Originals are never replaced, so that photo is written under a numbered name." |

The script resolves the conflict itself, so the alert was never on screen:
its text is checked (it comes from the bundle's compiled catalog), its look
is not. The script's `alert` command does not reach an alert on the export
sheet (tried: `alert press Export 4 Photos` finds no such button).

The owner's library was not opened. `/Applications`' copy of the app was
running during these checks (pid 89561, started 16:33, before my first
launch at 16:47); I did not start it or touch it. The disk images are
detached and no test copy is left running.

## Open questions

No question blocks. DQ1 to DQ3 of the first pass are ruled in `review.md`
(R1 built as F1; R2 and R3: nothing to change). One note for the designer:

- **N1.** Since C5 the alert's count of originals includes files known only
  by their content, so an exact copy of an original in a backup folder is
  counted and worded as "an original in the library" (decision 4). The four
  messages are unchanged. If a copy should be worded differently that is new
  copy, and the app can't tell a copy from the master on a volume it doesn't
  recognize, which is the case C5 is about.

## For a person

What the script can't show (for `qa.md`; the designer's M1 to M3 in
`review.md` are the same checks with the final wording):

1. The alert on screen (M1): export a whole project's JPEGs into its own
   folder and read "They are all originals in the library…" under the title,
   wrapped, nothing cut off; with one photo, "It is an original…". With the
   wording of P1: no message compares Replace with Keep Both.
2. Choose Replace there with a real click (M2): new `-2` files appear, the
   originals still open in the loupe and in Quick Look, and the photos are
   not marked missing or changed. Return chooses Keep Both, Esc cancels.
3. A folder with both kinds of file in the way (M3): the title counts all of
   them, the message "N of them are originals…" only the originals; Replace
   replaces the earlier exports and numbers the rest.
4. Originals on an external volume, exported into their own folder. If
   masters are on a network share, how long Export takes to show its
   question or start (code review, question 2).
5. Export with Replace over a folder of exact copies of originals (a
   backup): the alert counts them as originals and Replace numbers the new
   files; with large originals, how long the question takes to appear (each
   copy is read once for the count and once more under Replace).

## Follow-ups (proposed issues)

- **`photocli render --out` can overwrite a master** (`bug`). The main
  session is handling it as its own issue; the reviewer reproduced it
  (`code-review.md`, question 1). `MasterFiles`, `masterFiles(mounted:)` and
  `holdsContent(ofFileAt:)` are there to check against, place and content.
- **The importer's hashing loops may hold what they read** (`bug`, to be
  measured first). `SHA256ContentHasher.contentHash`
  (`Sources/PhotoCore/Import/ContentHasher.swift`) and
  `CopyImporter.hash(of:uncached:)` read with `FileHandle.read(upToCount:)`
  in a loop with no autorelease pool, the shape C6 was. Measure the footprint
  while importing a multi-gigabyte video; if it grows with the file, read
  into one reused buffer as `MasterFiles.hash(of:)` does (or share that
  reader).
- **Export can start twice when Return is pressed twice, and the count
  before the alert can't be stopped** (`bug`, C4 and C7; the main session
  files them as one issue). C7, from `code-review.md`: the count now reads
  files, the Export button's task is not kept, Cancel only closes the sheet;
  after cancel and reopen the old request's alert can come up on the new
  sheet with the old count and photos. C4:
  `ExportModel.requestExport` checks `isExporting`, then awaits the items and
  the clashes before `start` sets it, and the sheet's Export button is
  disabled only by `isExporting`. Two requests can both reach `start`: two
  jobs plan the same names into one folder, `task` holds only the second so
  Stop can't reach the first, and whichever loses a name reports "could not
  be written". No original is at risk. Older than this branch (the first
  await was there); the clashes read lengthens the gap. A flag set before the
  first await, cleared when the request ends, would close it.
- **`photocli` reads masters at the recorded mount path** (`bug`, seen while
  fixing C1). `ExportJob.items` builds each source URL from
  `volume.mountPath`, and `photocli` never refreshes mount paths
  (`CommandEnvironment.openLibrary`), so photos on a volume mounted elsewhere
  than the app last saw it export as offline from `photocli` until the app
  has run (run on R1's library: with the image at `m2`, `export --version 1`
  writes nothing and fails with `offline(volumeName: "RemountTest")`). Not a
  risk to originals; not changed here (export is a read
  command and the review asked for no catalog write).
- **Say in Activity when Replace wrote photos under numbered names to spare
  originals** (`enhancement`), as `review.md` R3 proposes; needs the policy
  carried into `ExportSummary`.

## README

Nothing: no requirement, build command or layout changed. For `CLAUDE.md`
(the owner's part, a proposal): the **Export** architecture rule could gain
"A name that is a catalogued master's is never given to an export, and a
file with a catalogued master's size and SHA-256 is never replaced, whatever
the policy (`MasterFiles`, which places each volume where it is mounted now
as well as where the catalog recorded it)", and the Layout's `Catalog` line
could name `MasterFiles`.
