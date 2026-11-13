# Export overwrites masters: code review

Owner: code-reviewer. Date: 2026-11-12. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/export-overwrites-masters`, the uncommitted working tree on
`cd992f9` (`git diff develop` plus the untracked `MasterFiles.swift`,
`ExportMasterProtectionTests.swift` and this folder). Build and tests:
`swift build` clean; `swift test` 834 tests in 124 suites passed, 1 known
issue.

Checked against the **Bug** section of `status.md`, issue #160 and its ruling
(owner, 2026-11-12: export never overwrites a catalogued master), and
`CLAUDE.md`.

## Verdict

Not ready for QA: one blocker. The rule is right, it is in the right place
(PhotoCore, shared by the app and `photocli`), and it holds for every case the
Bug section names, but masters are placed by each volume's recorded mount path
only, so `photocli export --policy overwrite` still replaces a master on a
volume that is mounted somewhere else than the catalog last saw it (C1,
reproduced). C2 is a missing test on the branch that keeps a failed catalog
read from exporting unprotected.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Blocker | `Sources/PhotoCore/Catalog/MasterFiles.swift:101-131` (`Catalog.masterFiles`, the mount path at 110-112 and 126-127) | Masters are placed at `volume.mountPath`, the last mount point the catalog recorded. Nothing asks where the volume is mounted now. The app brings `mountPath` up to date at launch and on mount notifications (`LibraryModel.refreshVolumes`); `photocli` never does (`CommandEnvironment.openLibrary`, `CommandRegistry.swift:217`), so there every volume mounted elsewhere than recorded has unprotected masters. | Reproduced on a scratch library and a scratch disk image. Photo 1 `IMG_00001.JPG` on an APFS image mounted at `…/m1`; photo 2, also `IMG_00001.JPG`, on the internal disk. Control, volume at `m1`: `photocli export --version 2 --to …/m1/Shoot/Shoot-001 --policy overwrite` gives `"protectedMasters": 1`, writes `IMG_00001-2.jpg`, master unchanged. Then detach and attach the same image at `…/m2`: the same command with `--to …/m2/Shoot/Shoot-001` gives `"protectedMasters": 0`, `written: […/m2/Shoot/Shoot-001/IMG_00001.jpg]`, and photo 1's master (SHA-256 `4178360e…`, 125 KB) is now the 7,987-byte export (`28755ad6…`). Same cause, not run: a share mounted at two paths, exported through the one the catalog doesn't record; and the app in the moment between a remount and its refresh. | Architecture rules: "Originals are never moved, copied or modified"; "Volumes are matched by identity (UUID) so a remount elsewhere is found". Issue #160: "volume-resolved", "so `photocli` is covered". |
| C2 | Should fix | `Sources/PhotoCore/Export/ExportJob.swift:172-185`; no test in `Tests/PhotoCoreTests/ExportMasterProtectionTests.swift` | The branch that writes nothing when the catalog can't be read ("Without the answer nothing is written") has no test. Only its cancelled half is covered (`videosOfflineMastersAndCancellationAreReported`). | Change the `catch` to fall back to `MasterFiles.none` (or `try?`) and all 834 tests still pass; an export with Replace into a folder of originals then replaces them whenever the read fails. A test can pass `items:` and break the read (the in-memory catalog's `image` table renamed after the items are read), then expect no file written, the masters' bytes unchanged and one failure per photo. | Workflow, Bug fixes: the fix's tests check the behavior the Bug section describes; `status.md` states this behavior ("writes nothing and reports every photo as failed"). |
| C3 | Nit | `Sources/PhotoCore/Export/ExportJob.swift:162-185` | The destination folder is created before the masters are read. | Catalog read fails, destination doesn't exist yet: the export reports every photo failed and leaves a new empty folder behind. "Writes nothing" is true of files only. | None; `status.md`'s own wording. |
| C4 | Nit | `Sources/PhotoApp/Model/ExportModel.swift:283-313`, `Sources/PhotoApp/Views/ExportSheet.swift:57-63` | `requestExport` checks `isExporting` once, then awaits twice (`items`, now also `clashes`, a whole-catalog read plus one file-system lookup per catalogued folder). The Export button is disabled only by `isExporting`, which turns true in `start`. Older than this branch (the first await was there); the branch lengthens the gap. | Return pressed twice before the first request reaches `start`: both pass the guard and both call `start`. Two jobs plan the same names into one folder; `task` holds only the second, so Stop can't reach the first, and whichever loses each name reports "could not be written". No original is at risk (`replacing: false` moves never overwrite). | Correctness (state drift). |

## Questions

For the main session to relay; none is a code finding.

1. **Owner / product manager: the `photocli render --out` follow-up.** It is
   real. Run on a scratch library: `photocli render --version 2 --out <that
   version's own master> --long-edge 200` exits 0 and the master goes from
   131,530 to 7,558 bytes, with no flag, question or warning. That is a shorter
   way to the same loss than #160 was (export at least needed `--policy
   overwrite`), so I would file it as a `bug` now, `on-roadmap`, ahead of
   enhancements, rather than leave it as a note in `status.md`. Keeping it out
   of this branch is defensible (new scope goes to its own issue), but the
   owner's ruling reads "never overwrite masters", and whether that already
   covers `render` is the owner's call, not the engineer's or mine. Three
   things the new issue should say:
   - With a library (`--version`, or `--library-root`): refuse an `--out` that
     `Catalog.masterFiles()` contains. `render` names one exact file, so the
     numbered-name fallback of export doesn't fit: an error is the answer.
   - Without a library (`render <file>`): refusing an `--out` that is the
     input itself needs no catalog (same resolved folder and folded name).
     Whether a plain file render should also open the standard library just to
     ask is the decision the engineer names.
   - It inherits C1: whatever `masterFiles()` misses, `render` will miss.
   The engineer's claim that this is the only other place that replaces a file
   at a caller's path holds for shipped commands. The debug script's
   `snapshot`, the scroll benchmark and the import grid probe also write to a
   path the caller names (`WindowSnapshot.swift:29`, `ScrollBenchmark.swift:196`,
   `ImportGridProbe.swift:76`); they are developer tooling and I would leave
   them. The preset save goes through `NSSavePanel`, which asks.
2. **Engineer / owner: network volumes.** Every export resolves every
   catalogued folder against the file system (`MasterFiles.init(namesByFolder:)`,
   `MasterFiles.swift:35-39`), in the app twice (before the alert, then at
   start), with no cancellation check in that loop and nothing on screen while
   the sheet waits. Locally this is nothing: I measured 5,040 existing folders
   in 0.08 s and 5,040 on an unmounted volume in 0.23 s, and the whole read on
   a 100,000-row catalog adds about 0.13 s to a `photocli export` (debug
   build), matching `status.md`. I could not measure a slow or sleeping network
   share, where each folder is at least one round trip. If the owner's library
   has masters on a NAS, a timing there would settle it; QA's P4 (external
   volume) could carry it.
3. **Designer: DQ1 to DQ3** in `status.md` (the alert's wording, Replace when
   every clash is an original, nothing in Activity) are theirs. Nothing in the
   code stands in the way of any of the three answers.

## Checked and fine

- **The plan** (`ExportNaming.entries`): under every policy a first-choice
  name that is a master's never becomes `.write(_, replacing: true)`; the
  numbered fallback avoids masters, existing files and the batch's own names;
  names numbered inside the batch (`a-2.jpg`) are checked against masters too.
  Skip still skips an existing master; a missing master's place is not taken.
- **Tests fail without the fix.** In a scratch copy with `masters: .none`
  passed in `ExportJob`, the four job tests and the `photocli` test fail (20
  issues), each on the masters' bytes having changed. The naming tests assert
  `.write(a-2.jpg, replacing: false)` where the old plan gave `.write(a.jpg,
  replacing: true)`. Deterministic, Swift Testing, no sleeps, no golden or
  tolerance touched.
- **Folder resolution** (`MasterFiles.resolvedFolder`), probed with a copy of
  the function: a folder that is a symbolic link, a link on the way,
  `Link/../Shoot` where `Link` points into another tree (resolved as the file
  system does, not lexically), `/tmp` against `/private/tmp` and
  `/System/Volumes/Data/private/tmp`, doubled and trailing slashes, another
  capitalization on a case-insensitive volume, and a tail that doesn't exist
  (kept under the deepest existing folder, folded) all come out as one folder.
- **Name folding**: case, composed against decomposed accents, `ß`/`SS`,
  dotted capital I, title-case digraphs. A case-sensitive volume protects a
  name too many, never too few.
- **Links to files.** A symbolic link in the destination that points at a
  master: `replaceItemAt` fails ("doesn't exist"), the master is untouched and
  the photo is reported failed. A hard link to a master: the link is replaced,
  the master's content stays. The importer never catalogues a file through a
  symbolic link (`FileScanner`: `isRegularFile`), so a master's own path is
  never a link to a file.
- **Races.** `replacing: false` writes use `moveItem`, which never overwrites,
  so a file that appears after planning costs a failure, not a file. The app
  asks the catalog again in `run`, after the alert, not only when counting
  clashes. Left as is: a file planned for Replace that is imported in place
  while the export runs; it was an ordinary file the person asked to replace.
- **Cancellation**: a masters read cut short by Stop is reported as stopped,
  not as failures, and writes nothing (covered by the existing test).
- **Concurrency**: `Catalog.masterFiles()` and `ExportJob.clashes` are
  nonisolated async on Sendable types, so the catalog read, the folder
  resolution and the `fileExists` checks run off the main actor (the old
  `existingCount` ran its file checks on it). The folder resolution happens
  outside the database read. `MasterFiles` is a plain Sendable value.
- **Catalog**: one read of `image` and `volume`, no write, no migration, no
  join on `imagePair`; videos and every other row of `image` are covered.
- **Export rule**: names are still decided for the whole batch first and each
  file is moved into place only when complete.
- **Localization and branding**: the new message has its String Catalog entry
  with `one` and `other`; "Keep Both writes the new files under numbered
  names." kept its entry; `LocalizationTests` and `BrandingTests` pass.
  `protectedMasters` and every other new name are generic.
- **No pipeline bump, golden, sidecar, undo or dependency change**, and none
  was needed. `docs/USER_GUIDE.md` is updated in the same change.

## Follow-up

### Second pass, 2026-11-12

Reviewed: the uncommitted working tree on `cd992f9` again (nothing is
committed, so there is no commit to name; every "Fixed" below is in the
working tree). Build and tests: `swift build` clean; `swift test` 842 tests in
126 suites passed, 1 known issue.

**Verdict.** C1, C2 and C3 are fixed and their tests bite. One new finding,
C5 (Should fix): the C1 fix finds a moved volume by its identity, and a volume
that has neither a UUID nor a remount URL carries its mount point in its
identity, so its masters are still replaced after a remount elsewhere
(reproduced). It is rare and not a regression, but it is the same loss, so it
needs a fix or the owner's ruling before sign-off. Everything the Bug section
names holds.

| # | Result | How it was checked |
|---|---|---|
| C1 | **Fixed** | `Catalog.masterFiles(mounted:)` (`MasterFiles.swift:109-144`) places each volume at its recorded mount path and at every current mount of the same identity; `ExportJob` passes the live list to both `clashes` and `run` (`ExportJob.swift:106`, `140`, `171`), so the app and `photocli` share it. The first pass's reproduction run again on a fresh scratch library and APFS image, same master (SHA-256 `4178360e…`, 124,836 bytes). Control at `…/m1`: `"protectedMasters": 1`, `IMG_00001-2.jpg`. Detached, attached at `…/m2`, `photocli export --version 2 --to …/m2/Shoot/Shoot-001 --policy overwrite`: `"protectedMasters": 1`, `IMG_00001-3.jpg`, no failures, the master's hash unchanged, `volume.mountPath` still `…/m1` (nothing written to the catalog). Trial in a scratch copy with only the recorded path used: `aVolumeIsPlacedWhereItIsMountedNowAndWhereItWasRecorded` fails (6 issues) and "A master on a volume mounted elsewhere than the catalog recorded is not replaced" fails (4 issues, one of them the master's bytes). |
| C2 | **Fixed** | "When the catalog can't say where the masters are, nothing is written and no folder is made" (`ExportMasterProtectionTests.swift:397`). Trial with the `catch` falling back to no masters: it fails with 5 issues (files written, the masters' folder changed, no failures reported, the new folder made). |
| C3 | **Fixed** | The masters are read, and the destination's taken, before `createDirectory` (`ExportJob.swift:165-190`); `ExportNaming.entries(…protected:)` plans from names taken earlier. Two trials: the folder made before the read fails the C2 test's last line (the empty folder is left); the destination's names taken after the folder is made fails "A missing master's place is kept when the export makes its folder again" (6 issues). So the order is pinned from both sides. |
| C4 | **Not fixed**, left as ruled | No original at risk; proposed as its own issue in `status.md`. Nothing in this pass changes it. |
| F1 (designer's) | Code side as `review.md` R1 asks | `ExportClashes.originals` picks the case in PhotoCore (4 tests); `conflictMessage(count:masters:)` has the four messages, letter for letter those of R1's table; the three String Catalog entries are there (one with `one` and `other`), the first wording's key is gone; `ExportSheet` passes the count. The wording itself is the designer's to confirm. |

**New finding.**

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C5 | Should fix | `Sources/PhotoCore/Catalog/MasterFiles.swift:129-134` (the match at 133); the identity it matches on, `Sources/PhotoCore/Import/VolumeResolver.swift:19-26` | Current mounts are matched by identity alone. A volume with no UUID and no remount URL has the identity `mount:<name>@<mountPath>`: it names the mount point, so the same volume mounted elsewhere matches nothing and its masters are placed at the recorded path only. For that kind of volume C1 is still open. Not a regression (the first pass had it, and the catalog has never recognized such a volume once moved: its photos show offline), but the C1 fix stops at it. | Reproduced. A FAT32 image with volume serial 0 (`newfs_msdos -I 0`; `volumeUUIDString` nil, catalogued as `mount:NOUUID@…/f1`) holding `DCIM/IMG_00001.JPG`, and another `IMG_00001.JPG` on the internal disk. Control at `…/f1`: `"protectedMasters": 1`, `IMG_00001-2.jpg`, master unchanged. Detached and attached at `…/f2`: `photocli export --version 2 --to …/f2/DCIM --policy overwrite` gives `"protectedMasters": 0`, `written: […/f2/DCIM/IMG_00001.jpg]`, and the master (124,836 bytes, `4178360e…`) is now the 7,002-byte export (`9c3e61ce…`). The app takes the same path (`ExportJob.run`), with Replace as the trigger. How rare: FAT32 and exFAT images made with `hdiutil` both have a UUID; only the zero serial lost it. Same cause, not run: a share whose remount URL differs from the catalogued one (another spelling of the server, another user) mounted at another path, and FUSE file systems that report neither value. | Architecture rules: "Originals are never moved, copied or modified". Issue #160's ruling: export never overwrites a catalogued master. |

Two ways it could go, for the engineer and the owner to choose between, not a
design: (a) for a catalogued volume whose identity is of the `mount:` kind,
also place it at every mounted volume of that kind with the same name (a name
too many protected, never one too few); (b) independent of where anything is
mounted, never replace a file whose size and SHA-256 are a catalogued
master's (the catalog has both; one `stat` per file about to be replaced, a
hash only when a size matches). (b) also covers the cases identity can never
see (question 4).

**Looked at for what the fixes brought in, and fine.**

- **Cost of listing the mounts.** `VolumeAvailability.mountedVolumes()` on
  this Mac (11 volumes, no network share among them): 4.6 ms the first time, 0.4 ms
  after. Once per `clashes` and once per `run`, inside nonisolated async
  functions (tools version 6.0, no upcoming feature that keeps them on the
  caller's actor), so off the main actor. Default arguments are evaluated by
  the caller: `catalog.masterFiles()` with no argument from a main-actor
  caller would list volumes there. No such caller exists (only tests use the
  default; `ExportJob` passes its own list), but the `render --out` follow-up
  should pass one too.
- **The internal disk is not doubled.** `mountedVolumeURLs` reports it once,
  at `/`, the path and UUID the catalog records for files under `/Users` and
  `/tmp`; `/System/Volumes/Data` is not in the list. A volume at its recorded
  path is one entry (`Set`).
- **Another volume at a recorded path** (two cards of one name): the absent
  card's masters are placed on the present one. Over-protection only, as
  decision 1 already accepts.
- **The straddle between the lookups and making the folder.** The masters'
  folders and the destination are resolved in one expression, before the
  folder exists, and the plan uses those names afterwards; `clashes` makes no
  folder. A missing folder spelled in another case than the masters' (`GONE`
  for `Gone`) folds to the same key. The two C3 trials above are the proof
  that the tests hold the order.
- **Fail closed, still.** A failed read reports every photo and returns
  before `createDirectory`; a stopped read is reported as stopped. A Stop that
  lands during the folder resolution (no cancellation check there, question
  2) still makes the destination folder and then writes nothing, as before
  this branch.
- **Tests**: Swift Testing, no sleeps, injected mounts
  (`ExportJob.mountedVolumes`, `masterFiles(mounted:)`), no golden or
  tolerance touched. The catalog is not written by any of the new code
  (asserted in the mount test; seen on the real remount).

**Questions, second pass.**

- Question 1 (`photocli render --out`): being filed as its own issue by the
  main session. It will inherit C5 as it would have inherited C1.
- Question 2 (network volumes): still open, and now also covers listing the
  mounts: `mountedVolumeURLs(includingResourceValuesForKeys:)` asks every
  mounted volume for its UUID and remount URL, which I could not time against
  a slow or unreachable share. With "For a person" check 4.
- Question 4, new (owner / product manager): **what "never" covers when the
  catalog cannot recognize the volume.** Protection by place can only be as
  good as volume identity. The same files reached as another volume (C5's
  cases; a nested NFS export mounted on its own; a share under a second URL)
  are, to the catalog, unknown files. If the ruling is meant to hold there
  too, the rule has to look at content as well as place (option (b) above).
  If it is not, C5 can be closed by ruling and recorded as a known limit in
  `status.md` and `qa.md`.

### Third pass, 2026-11-13

Reviewed: the uncommitted working tree on `cd992f9` again (still nothing
committed). Scope: C5 as built after the owner's ruling (question 4: an
existing file whose size and SHA-256 are a catalogued master's is never
replaced, wherever it is mounted): `MasterFiles.holdsContent(ofFileAt:)`, the
content checks in `ExportNaming` and their wiring in `ExportJob`. Build and
tests: `swift build` clean; `swift test` 854 tests in 128 suites passed, 1
known issue.

**Verdict.** C5 is fixed: the rule is right, it fails closed, its tests bite,
and the FAT32 reproduction now leaves the master alone. One new finding
before QA, C6 (Should fix): the new hashing loop keeps every chunk it reads
until the whole pass returns, so a count or a plan holds in memory all the
bytes it hashes (measured: 2 GiB for 2 GiB read). C7 is a nit for C4's
follow-up issue. No original is at risk from either.

| # | Result | How it was checked |
|---|---|---|
| C5 | **Fixed** | Read: `Catalog.masterFiles` takes `fileSize` and `contentHash` from every row of `image` in the one read (no join, no filter: offline masters and videos included; a virtual copy is a version and has no row of its own; both columns are `NOT NULL`, the hash `UNIQUE`), and `holdsContent` compares the size, then the SHA-256, which is computed as the importer computes it (`SHA256ContentHasher`: the whole file, lowercase hex). Run: the second pass's reproduction on a fresh scratch library and FAT32 image with serial 0, built without the app (`photobench import`), catalogued as `mount:NOUUID@…/f1`, the same master (124,836 bytes, `4178360e…`). Control at `…/f1`: `"protectedMasters": 1`, `IMG_00001-2.jpg`. Detached, attached at `…/f2`, `photocli export --version 2 --to …/f2/DCIM --policy overwrite`: `"protectedMasters": 1`, `IMG_00001-3.jpg`, no failures, the master's SHA-256 unchanged, the catalog's volume row unchanged. The second pass got `"protectedMasters": 0` and the master replaced here. Also run: an ordinary file on that volume is still replaced (the same name written twice, `protectedMasters` 0); a symbolic link in the destination that points at a master now gives a numbered name and leaves link and master alone (the first pass got a failed photo there); an exact copy of the card's master under the export's name in another folder: Replace numbers it (`protectedMasters` 1), Skip skips it, Keep Both numbers it without counting it, the copy's bytes unchanged each time. |

**Tests fail without the fix.** Nine trials in a scratch copy of the tree, the
export and command suites run after each (86 tests):

| Trial | Result |
|---|---|
| `holdsContent` always says no | 7 tests fail, 18 issues: the two job tests, the `photocli` C5 test and four of "Master files: a master's content, wherever it is" |
| The job's plan doesn't ask for content | the two job tests and the `photocli` test fail, 10 issues (the master's bytes among them) |
| The catalog read brings no sizes or hashes | those three and `theCatalogGivesEveryMastersSizeAndHash` fail, 14 issues |
| The count before the alert doesn't ask for content | `theQuestionCountsThemBeforeAPolicyIsChosen` and the job test's `clashes` fail |
| An unreadable file of a master's size counts as ordinary (fail open) | `aFileIsReadOnlyWhenItsSizeIsAMasters`, `aReadCutShortByCancellationCountsAsAMaster` fail |
| Links not followed | `aFileWithAMastersBytesIsOneWhateverItsNameOrPlace` fails |
| Every existing file read, whatever its size | `aFileIsReadOnlyWhenItsSizeIsAMasters` fails |
| No cancellation check between chunks | `aReadCutShortByCancellationCountsAsAMaster` fails |
| `ExportJob.clashes` without its `Task.checkCancellation()` | **all 86 pass**: see C7 |

**New findings.**

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C6 | Should fix | `Sources/PhotoCore/Catalog/MasterFiles.swift:97-107` (the loop at 101-105); the passes that call it without a suspension in between, `Sources/PhotoCore/Export/ExportNaming.swift:151-178` | `hash(of:)` reads with `FileHandle.read(upToCount:)`, which hands back autoreleased data, in a synchronous loop with no autorelease pool, and `ExportNaming.entries` hashes file after file in one synchronous call. Nothing is released until the count or the plan returns, so its memory is the sum of every file it hashed, not one 4 MiB chunk. | Measured in a scratch copy, each in a process of its own, files of random bytes, the process's memory footprint before and after. One 2 GiB file of a master's size, `holdsContent`: 25 MiB to 2,082 MiB. 128 files of 16 MiB, each of a master's size, one `ExportNaming.clashes`: 27 MiB to 2,084 MiB. The same loop with `autoreleasepool` around each chunk, 2 GiB: 25 MiB to 29 MiB. So the cases the content rule is for hold all they read: Replace into a card or a backup folder of 2,000 JPEG originals of 12 MB is 24 GB held by the count, released, then 24 GB again by the plan; one 3 GB TIFF of a master's size is 3 GB. This Mac has 24 GB of memory in all. | Correctness. `status.md` gives the cost as "a read", "cancellable between chunks", with only the two sets counted as memory. |
| C7 | Nit | `Sources/PhotoApp/Views/ExportSheet.swift:57-63`, `Sources/PhotoApp/Model/ExportModel.swift:300-311`, `Sources/PhotoCore/Export/ExportJob.swift:145-147` | The count before the alert now reads files, and nothing can stop it or shows that it runs: the Export button's task is not kept, the sheet's Cancel only closes the sheet, the button stays enabled (C4). The cancellation check in `clashes` guards a task nothing cancels, and has no test (last trial above). | By reading, not run (the app is QA's). Export with a destination where the count reads for a while (C6's cases; a slow card: 1,000 originals of 10 MB at 90 MB/s is about two minutes): the sheet shows nothing. Cancel, change the selection, open Export again before the count ends: `begin()` clears `conflict`, the old request then sets it, the alert comes up on the new sheet with the old count, and Replace runs `start(items:)` with the old request's photos into the folder and settings now showing. No original is at risk (the plan is made again in `run`). | Correctness (state drift). Belongs with C4's follow-up issue, which should say so. |

For the engineer, C6: a pool per chunk, or reading into one reused buffer,
either is enough; the fix changes no behavior, so only this review looks at it
again. Whoever fixes it can use the footprint (`task_vm_info`'s
`phys_footprint`) as I did, or leave it untested and I measure it again.

**Cost, measured** (debug build, internal disk, warm file cache):

- **The masters read**, 100,000 masters in 500 folders with their sizes and
  hashes: 0.19 s, as `status.md` says; about 36 MB more resident while it is
  built (names, sizes and hashes together).
- **Files of no master's size**: 100 existing files of 16 MiB, count 5.6 ms,
  plan under Replace 4.9 ms (one `stat` each, 0.05 ms).
- **Files of a master's size** (the worst case asked about): the same 100
  files with one master of exactly that size in the catalog: count 0.62 s,
  plan under Replace 0.63 s. Each file is read whole (the size is all that can
  rule it out), at about 2.5 GiB/s here; a cold cache or a card reads at the
  disk's speed. Both passes read, so the app reads such files twice: confirmed.
  `photocli` reads once (it has no count).
- How it comes about without copies of originals: files written before at a
  fixed size (uncompressed TIFFs of one camera) replaced again, when one master
  in the library has exactly that size. Each is then read twice and found
  ordinary. Slow, not wrong; C6 is what makes it more than slow.
- One 2 GiB file: 0.79 s.

**Looked at, and fine.**

- **Fail closed.** No hashes, no read (`MasterFiles.none`). A file of a
  master's size that can't be opened or read, a read cut short by
  cancellation, an item whose attributes have no size: all count as a master,
  so nothing is replaced. A file that isn't there is not a master (there is
  nothing to replace; the write then uses `moveItem`, which never overwrites).
  A failed catalog read still writes nothing (C2's test).
- **Cancellation.** Checked before every chunk. In `run`, a Stop during the
  plan's reads makes every file still to be read a master, so nothing is
  planned for replacing, and no render starts (`startNext` checks first); the
  summary is `cancelled`, its `protectedMasters` then too high, which nothing
  shows. In `clashes` see C7.
- **Links.** `holdsContent` follows a link to the file it names (run, above;
  hard links and clones have the bytes and are covered by them). A dangling
  link is no file to `fileExists`, so it is never planned for replacing.
- **Chunks.** 4 MiB, the importer's loop and the importer's digest text, so
  the hash of a file is the catalog's hash of it (the real remount above
  matches a hash made by the importer). An empty read ends the loop.
- **The plan.** Content is asked only for a file that exists, is no master by
  place, and would be replaced or is being counted; a master by place is not
  read; numbered names never land on an existing file, so they need no read.
  A first-choice name numbered inside the batch (`a-2.jpg`) is asked like any
  other.
- **Between the check and the write.** The plan is made once; each file is
  replaced when its render ends, which can be much later. Only a destination
  planned as `replacing: true` is open to it, and it takes an ordinary file at
  that name being swapped for a file with a master's bytes while the export
  runs. The export itself never writes a master's bytes. Left as the first
  pass left a file imported in place during an export; if the owner wants it
  closed, the place is `ExportRenderer.write`'s replace branch
  (`ExportRenderer.swift:135`), asking again just before `replaceItemAt`.
- **Limits of the rule as ruled**, for `qa.md`'s known limits rather than a
  finding: content is what the catalog last hashed. A master another app has
  changed since (the catalog learns of it in `SidecarSync`,
  `updateMasterFile`) is known by place only, so on a volume the catalog
  can't recognize it is an ordinary file. An empty master (0 bytes) makes
  every empty file one.
- **Nothing else moved.** The other suites pass unchanged; no migration,
  pipeline bump, golden, tolerance, dependency, sidecar or undo change; no new
  UI string (the four messages are the second pass's); `USER_GUIDE.md` says
  what the rule now covers. `ExportNaming.plan` and `clashes` have no caller
  but `ExportJob`.

**Questions, third pass.**

- **Follow-up issue, proposed (`bug`), not from this branch.** The importer's
  hashing has the same loop and the same cost: `SHA256ContentHasher.contentHash`
  on a 2 GiB file took the footprint from 25 MiB to 2,082 MiB (measured as
  C6). `CopyImporter`'s copy loop and `hash(of:uncached:)`
  (`CopyImporter.swift:327-334`, `355-357`) read the same way; not measured.
  Title: "Hashing a file holds the whole file in memory (import, copy
  verification)". Body: a 20 GB video is 20 GB held while it is hashed, times
  the hashing concurrency (4 by default); a pool per chunk brought the same
  loop to 4 MiB. Whatever C6's fix is should be shared with it.
- **Designer: N1** in `status.md` (an exact copy of an original is counted and
  worded as "an original in the library") is theirs. The code can't tell the
  two apart where it matters, as `status.md` says.
- Question 2 (network volumes) is still open and now includes reading files of
  a master's size over the network. With "For a person" checks 4 and 5.
- `/security-review`: yes, run it on this branch. It changes the code that
  decides which existing files outside the library an export replaces, and it
  now opens and reads files a chosen folder names, following links.

### Fourth pass, 2026-11-13

Reviewed: the uncommitted working tree on `cd992f9` again (still nothing
committed). Scope: C6 only. Two files changed since the third pass, by
modification time: `MasterFiles.swift` (`hash(of:)`, lines 95-127) and
`ExportMasterProtectionTests.swift` (two tests, lines 248-300). Build and
tests: `swift build` clean; `swift test` 856 tests in 128 suites passed, 1
known issue.

**Verdict.** C6 is fixed and the source needs nothing more: the same two
cases that held 2 GiB now hold about 1 MiB, the hash is the catalog's, and
every failure still counts as a master. Two findings, both in the tests and
neither a risk to an original: the new read-error branch has no test (C8),
and the footprint guard can fail without a fault, by my estimate in about one
full run in 300 on this Mac (C9). QA's result does not depend on either.

| # | Result | How it was checked |
|---|---|---|
| C6 | **Fixed** | Read: one descriptor, one 1 MiB buffer allocated once and used for every chunk, nothing autoreleased in the loop. Measured as in the third pass (scratch copy of the tree, each case in a process of its own, files of random bytes, the process's `phys_footprint` before and after, its peak the same). One 2 GiB file of a master's size, `holdsContent`: 17.0 MiB to 17.1 MiB (third pass: 25 to 2,082), 0.83 s (was 0.79 s). 128 files of 16 MiB, each of a master's size, one `ExportNaming.clashes`: 17.6 MiB to 18.9 MiB (third pass: 27 to 2,084), 0.93 s; the plan under Replace straight after: still 18.9 MiB, 0.80 s, 128 replaced. No slower than before (about 2.5 GiB/s). |

**Correctness of the new loop** (`MasterFiles.swift:107-127`), read and run:

- **Same SHA-256.** The 2 GiB file: `MasterFiles.hash(of:)`, `shasum -a 256`
  and `SHA256ContentHasher` all give `d8a5527f…16b9`, and `holdsContent` says
  yes once that hash is catalogued. The chunk is 1 MiB now where the importer
  reads 4 MiB; the digest does not depend on it.
- **Short reads.** Whatever `read` returns is hashed for exactly that many
  bytes and the loop goes on until it returns 0. Trials: hashing the whole
  buffer instead of the bytes read, and ending on a short read, each fail 6
  tests (19 issues), `aFileOfSeveralChunksHashesAsTheCatalogDoes` among them.
- **EINTR.** A read that fails with it transfers nothing and leaves the offset,
  so `continue` loses and repeats no bytes; it goes back through the
  cancellation check. By reading: a local disk does not produce it, so not run.
- **Errors fail closed.** `open` failing (run: a missing file, ENOENT; a file
  without permission, EACCES) and `read` failing (run: a directory, which
  opens and then fails with EISDIR) all throw, and `holdsContent` takes a
  throw for a master. `errno` is read after the path closure returns; the
  codes above came out right 2,000 times each, and a wrong code would still
  throw. `open` interrupted (EINTR) is not retried: it throws, so the file
  counts as a master.
- **The descriptor is closed on every path.** `defer` follows the `guard`, and
  the buffer's `defer` follows its allocation. Run: 2,000 rounds of five paths
  (read to the end, read error, open refused, missing, cancelled before the
  first chunk): 7 descriptors open before, 7 after. A 2 GiB read cancelled
  part way, five times: 7 before, 7 after.
- **Cancellation before each chunk.** The check is the first statement of the
  loop, before the first read too. Run on the 2 GiB file (0.76 s whole):
  cancelled at once, after 20, 100 and 300 ms, it threw `CancellationError`
  0.2 to 0.3 ms after the cancel each time (one chunk is about 0.4 ms), and
  `holdsContent` cancelled part way said yes. Trial without the check:
  `aReadCutShortByCancellationCountsAsAMaster` fails.
- **No close-on-exec flag** on the descriptor: checked that `Process` (the
  ExifTool launch) does not hand a descriptor opened this way to its child.
- Unchanged from before, for the record: a named pipe of a master's size
  (0 bytes, so only with an empty master in the catalog) would block in
  `open`, as `FileHandle(forReadingFrom:)` did.

**The guard does catch the fault.** Trial with the `FileHandle.read(upToCount:)`
loop put back: `hashingALargeFileHoldsOneChunkNotTheFile` fails, growth 1,236,
1,029 and 1,024 MiB in its three attempts, as `status.md` says.

**New findings.**

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C8 | Should fix | `Sources/PhotoCore/Catalog/MasterFiles.swift:119-122`; no test in `Tests/PhotoCoreTests/ExportMasterProtectionTests.swift` | The read-error branch is new hand-written code (before, `FileHandle` threw by itself) and nothing tests that it throws. The tests of an unreadable file stop at `open` (`aFileIsReadOnlyWhenItsSizeIsAMasters`: no permission; `aFileOfSeveralChunksHashesAsTheCatalogDoes`: missing). | Trial: `break` in place of the `throw` at line 121, so a failed read ends the file as if it were whole. All 88 tests of the export and command suites pass. With that change a file of a master's size whose read fails part way (a failing card, a share that drops) hashes as its first part, matches nothing, counts as ordinary and is replaced under Replace: fail open. A test needs no fault injection: `MasterFiles.hash(of:)` on a folder opens and then fails to read (EISDIR), so it must throw; with the trial change it returned a hash 2,000 times of 2,000. | Tests: the fail-closed rule in `status.md` ("a file of a master's size that can't be read … is taken for the master") is checked for a file that can't be opened only. Same kind as C2. |
| C9 | Should fix | `Tests/PhotoCoreTests/ExportMasterProtectionTests.swift:281-300` (the limit at 296 and 298, the three attempts at 292) | The guard measures the whole test process, and the other tests move its footprint by far more than the limit while it runs, so it can fail with nothing wrong. Not seen failing in 8 full runs (1 on the working tree, 7 on a scratch copy; the engineer's 2 besides); estimated from samples at about 0.3% of full runs here. On the CI runners (fewer cores, another GPU) I can't measure it. | Measured on a scratch copy with the fix in: the test printing each attempt, and a thread sampling the process's footprint every 10 ms through 7 full runs (about 21,000 samples). The footprint goes from 46 MiB to 3.7 GiB and back within a run, by up to 2.1 GiB in a second. An attempt takes 0.46 to 0.57 s beside the suite. A window of that length grows by 256 MiB or more at 4.4 to 5.5% of starting moments, two in a row at 1.5 to 1.9%, three in a row (the test failing with no fault) at 0.32 to 0.42%. Seen directly: running the export and command suites alone (88 tests), the first attempt was over the limit in 2 of 4 runs (284 and 325 MiB) and the second attempt saved it. The other way round: a window gives back 768 MiB or more at 1.5% of moments, so with the fault back the guard would pass a full run now and then (it fails every time run alone). | Tests: deterministic. CI: a red run that is not signal 11 fails the job and needs a rerun by hand. |

For the engineer, C9, three ways the samples support; the choice is theirs:

- The limit at half the file (512 MiB) instead of a quarter: three windows in
  a row over it at 0 of about 21,000 moments. The fault adds 1,024 MiB to
  every attempt, so it is still caught.
- Five attempts instead of three, limit unchanged: 0 to 2 of about 20,000.
  Costs nothing when the first attempt is quiet (the test stops there).
- The measurement in a process of its own, where nothing else moves the
  footprint: tried in the scratch copy as a Swift Testing exit test
  (`#expect(processExitsWith:)`, Swift 6.4.2 here; whether the CI's Xcode
  26.3 has it needs checking). Growth 1.3 MiB alone and 1.3 MiB beside the
  whole suite (twice), and it fails with the old loop. This one is
  deterministic; the first two only make a false failure rarer.

Both fixes are in the test file only, so they change no behavior: a short look
from this review, nothing for QA to repeat.

**Questions, fourth pass.**

- **The follow-up issue on the importer's hashing stands** (third pass's
  questions). `status.md` says "not measured"; it is: `SHA256ContentHasher`
  on the 2 GiB file again, 17 MiB to 2,074 MiB within the one call. The loop
  never suspends, so no caller's pool can release a chunk before the file
  ends: a file's size is held while it is hashed, whatever the caller does.
  `CopyImporter`'s two loops read the same way and are still not measured.
- Question 2 (network volumes) is unchanged and still with "For a person".
- `/security-review`: still yes, as the third pass says; the fix adds a
  hand-written `open` and `read` loop on files a chosen folder names.

### Fifth pass, 2026-11-13: C8 and C9 confirmed

Reviewed: the uncommitted working tree on `cd992f9` (still nothing
committed). Scope: C8 and C9 only, both in
`Tests/PhotoCoreTests/ExportMasterProtectionTests.swift`. **By reading: this
pass built and ran nothing** (QA was running the tests at the same time, and
a second SwiftPM run in the same tree would collide with it). What stands in
for a run of my own:

- **What changed.** Three files are newer than the fourth pass: the test
  file, `status.md`, and `MasterFiles.swift` by its date only. Its SHA-256
  (`f4b12889…`) is that of the copy the fourth pass measured, so the source
  is byte for byte what was reviewed. Against the fourth pass's copy of the
  test file the difference is one new test (lines 277-294) and, in the
  guard, the limit, the number of attempts and its comment (lines 296-323).
- **It compiles and passes, seen not run.** The working tree's test binary
  was linked at 07:43:04, after the test file's last change (07:42:57), and
  holds the new test's name. A full run logged in the session's scratchpad
  (`swifttest.log`, 07:45 to 07:46, not mine) needed no rebuild and ends
  "857 tests in 128 suites passed … with 1 known issue", both tests among
  the passed. 857 is the fourth pass's 856 and the one new test, as
  `status.md` says.

**Verdict.** Both fixed. No finding is open from code review except C4 and
C7, left as ruled for their follow-up issue. Ready for QA.

| # | Result | How it was checked |
|---|---|---|
| C8 | **Fixed** | `aFileThatOpensAndCannotBeReadCountsAsAMaster` (lines 279-294) is the test the finding asked for, and stricter. A folder named like a photo is hashed: `MasterFiles.hash(of:)` must throw a `POSIXError` whose code is `EISDIR`. `open(O_RDONLY)` on a folder succeeds and only `read` gives that code, so a pass proves the open went through and the throw came from lines 119-122, not from the `guard` at 111. Then `holdsContent` must take a folder of a master's size for a master, and one of another size for ordinary. Traced against the fourth pass's trial (`break` for the `throw` at line 121): `hash(of:)` returns the hash of nothing, so the first expectation fails (no error thrown); `holdsContent` gets a hash that is not `"any"` and says no, so the second fails too. Two of its three expectations bite; the third is the size-first rule, already pinned by `aFileIsReadOnlyWhenItsSizeIsAMasters`. Both halves rest on what the fourth pass ran: unchanged, a folder threw `EISDIR`; with the trial, it returned a hash 2,000 times of 2,000. Not vacuous: the size comes through `#require`, so a folder with no size fails the test instead of skipping the two lines after it. The matcher form of `#expect` (`#expect { … } throws: { … }`) is used nowhere else in the tests; the installed Swift Testing has it for a synchronous body, marked for deprecation only at a far-off Swift version, so no warning, and it has been there since 6.0, so CI's toolchain has it. |
| C9 | **Fixed**, as proposed (the first two ways together) | `hashingALargeFileHoldsOneChunkNotTheFile` (lines 303-323): `limit` is `size / 2` (512 MiB of the 1 GiB file), used for both the early exit and the final expectation; five attempts; it stops at the first quiet one, so a quiet run costs one read as before. A false failure now needs five attempts in a row each pushed over 512 MiB by other tests. The fourth pass's samples had three in a row over that at 0 of about 21,000 starting moments, and five in a row can't be more often than three. The fault is still caught: it adds the file's size, twice the limit, to every attempt (`status.md`: 1,052 MiB, then 1,028 MiB on each of the other four, run alone, the test failing; the engineer's trial, not repeated here). |

**What C9's fix does not change**, so nobody takes the guard for more than it
is (`status.md` says the same: "a measurement, not a proof"):

- It is still a measurement of the whole test process. With the fault back
  an attempt passes when the other tests give back 512 MiB or more while it
  runs. The fourth pass measured that for 768 MiB only (1.5% of moments);
  for 512 MiB it is at least that, and there are five chances now instead of
  three. So in a full run a returned fault is missed somewhat more often
  than with the first shape: some runs in a hundred, not measured. Run alone
  (`--filter MasterContentTests`) it fails every time. That is the price of
  the limit that stops false failures, and I would take it: the fix does not
  rest on the test, since one reused buffer can't hold more than itself.
- The way that takes the other tests out of it, the measurement in a process
  of its own (an exit test), was not used, for the reason `status.md` gives
  (not confirmed on CI's toolchain). Nothing for this branch; if the guard
  ever goes red without a fault, that is the change to make, not another
  attempt or a higher limit.
- A failing run holds about 5 GiB until the process ends (five attempts of
  1 GiB of zeros). Only with the fault back, in a run that is red anyway.

One remark, not a finding: the guard's comment says that at a quarter of the
file and three attempts "this failed without a fault about once in 300 full
runs". It was never seen failing (8 full runs here, the engineer's besides);
one in 300 is an estimate from the samples. "Would have failed, by the
reviewer's estimate" is what was found.

**Open after this pass.**

- C4 and C7: not fixed, as ruled; one follow-up issue (the main session
  files it).
- Questions unchanged: the importer's hashing loops (follow-up issue,
  measured in the fourth pass), question 2 (network volumes, with "For a
  person" checks 4 and 5), N1 for the designer.
- `/security-review`: still to run on this branch, as the third and fourth
  passes say. This pass adds nothing to it (tests only).

### Sixth pass, 2026-11-13: the alert's wording after the owner's P1

Reviewed: the uncommitted working tree on `cd992f9` (still nothing
committed). Scope: the rewording of the export alert's three messages with
originals (`status.md`, "Owner's findings at sign-off", P1). **By reading:
this pass built and ran nothing**, as asked; `status.md` gives `swift build`
clean, `swift test` 857 tests in 128 suites passed, 1 known issue, and
`Scripts/build-app.sh` building, all after the change. What stands in for a
run of my own is the bundle that build left (`build/*.app`, 08:30:08, after
the last source change at 08:27:39), whose compiled strings I read.

**Verdict.** Wording only, and correct. No finding. Nothing is open from code
review except C4 and C7, left as ruled for their follow-up issue.

**Nothing but wording changed.** Compared with the copy of the tree the
fourth pass made (07:40; the fifth pass changed tests only):

- `Sources/`, `Scripts/` and `Package.swift`: two files differ,
  `ExportModel.swift` and `Localizable.xcstrings`. Every other file is byte
  for byte the same (`MasterFiles.swift` still `f4b12889…`).
- `Tests/`: one file differs, `ExportMasterProtectionTests.swift`, and it was
  last changed at 07:42:57, before the fifth pass: that is the fifth pass's
  state, not a new change.
- `ExportModel.swift`: the three string literals and the doc comment of
  `conflictMessage` (lines 315-320). The `switch`, its four cases, their
  order, the three `comment:` arguments and the "Keep Both writes…" literal
  are untouched.
- `Localizable.xcstrings`: eight lines, at the same line numbers as before
  (the three keys at 472, 5876 and 11251 and their five values). Comments,
  states, structure and every other entry are untouched. Against `cd992f9`
  the whole catalog is three entries added, none removed, none changed.
- `docs/USER_GUIDE.md`: I hold no earlier copy to compare. Its diff against
  `cd992f9` has the sentence `status.md` names (lines 523-524, "When all of them
  are originals, the sheet says so, and the new files are written under
  numbered names.") and nothing that reads out of place.

| Check | Result | How it was checked |
|---|---|---|
| No key referenced but missing | **Fine** | The four literals in `conflictMessage` (lines 324, 327, 330, 333) are each a key of the catalog, character for character; `\(masters)` is an `Int`, so its key has `%lld`, as the catalog's does. The compiled bundle has all three new messages (two in `Localizable.strings`, the plural one in `Localizable.stringsdict`). |
| No key orphaned | **Fine** | None of the old wording ("like Keep Both", "Keep Both gives", "Replace writes those / that") is left anywhere in `Sources/`, `Tests/`, `Scripts/`, `docs/USER_GUIDE.md` or the compiled bundle. Each of the three new keys is referenced once, in `conflictMessage`. The catalog parses, has 1,091 keys, no key twice, and is still in sorted order. |
| Plural variants valid for `%lld` | **Fine** | The "some" key has `one` and `other`, both `translated`, each with exactly one `%lld` and no other argument, as its key (what `LocalizationTests` asks: an `other` form, and the same arguments as the key). Same shape as the catalog's other plurals. Compiled: `NSStringLocalizedFormatKey` `%#@value@`, value type `lld`, `one` "…is an original…, so that photo is written under a numbered name.", `other` "…are originals…, so those photos are written under numbered names." The two plain keys have the value equal to the key. |
| No product name | **Fine** | Not in the three entries (keys, values, comments), the literals or the user guide's sentence. No brand value outside `AppBranding.swift`. |
| The four cases map correctly | **Fine** | `ExportClashes.originals` is unchanged (`ExportNaming.swift:61-65`), and so are its four tests. `.none` (no original) gives "Keep Both writes the new files under numbered names."; `.some(n)` (0 < n < files in the way, so at least two files) gives the plural message with n, and n = 1 takes `one`; `.theOnlyFile` (one file, an original) gives "It is an original…"; `.all` (several, all originals) gives "They are all originals…". Each message's "It", "They" and "of them" has the title's files to refer to ("1 file already exists in…", "N files already exist in…"). `ExportSheet` (line 39) and the debug script (lines 61-62) pass the same `count` and `masters` as before. `status.md` U1 to U4 are the four messages read from the rebuilt bundle, one per case. |

**Not findings; for the main session to relay.**

- **Designer and QA: their files still hold R1's wording.** `review.md` says
  "Keep the four messages of R1 as they are. No string, key or code changes"
  and quotes the old messages; `qa.md`'s script checks quote them too. The
  owner's P1 replaces three of the four. A change to an alert's text is a
  change to the UI, so by `docs/WORKFLOW.md` step 4 it goes to the designer
  as well as here, and each owner records P1 in its own file. Nothing in the
  code waits on it.
- **Designer or owner: Skip Them.** The three messages say the photos "are
  written" under numbered names, with no button named. That is true under
  Keep Both and Replace; under Skip Them those photos are skipped. `status.md`
  says so and the two "all" messages are the owner's own words, so this is
  recorded, not raised: the button's own title says what it does. The user
  guide's sentence reads the same way.

**Open after this pass.** As after the fifth: C4 and C7 (follow-up issue),
the importer's hashing loops (follow-up issue), question 2 (network volumes,
"For a person"), N1 for the designer, and `/security-review` on this branch.
This pass adds nothing to `/security-review` (strings only).
