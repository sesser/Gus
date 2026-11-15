Issue: #164

# Importer hashing holds whole files in memory: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"), a follow-up from #160's fourth code review. Branch
`bug/squash-top-10`, after `1e855e7`.

**Status: Done.** Next: code-reviewer, then qa-tester. No UI changed, so no
design review. No parser of outside files, subprocess, network code or new
file writing (the copy loop writes the same file it did, through `write(2)`
instead of `FileHandle.write`): code-reviewer to say whether
`/security-review` should run.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `1e855e7`).
1. A file of 2 GiB (random bytes) on the local disk.
2. In a process of its own, note the memory footprint (`phys_footprint`),
   then hash the file once with each of `SHA256ContentHasher.contentHash`,
   `CopyImporter.hash(of:uncached:)` (both modes) and
   `CopyImporter.copyVerified` (the card import's copy and verify), and note
   the footprint after the call and the process's peak.

In the app this is importing a multi-gigabyte video: folder imports hash it
with `SHA256ContentHasher` (`Importer`, `SourceScanner`, and `SidecarSync`
before writing a sidecar), card imports copy it with `copyVerified` and
compare existing files with `CopyImporter.hash`.

**Expected.** Each call holds about one chunk (4 MiB), whatever the file's
size.

**Actual.** Measured (one process per case via `swift test --filter`, from an
async test as the importer calls them; 2 GiB file of random bytes, footprint
before / after the call; the process's peak equalled the after value):

| Loop | Before the fix | After the fix | Time before / after |
| --- | --- | --- | --- |
| `SHA256ContentHasher.contentHash` | 17.7 to 2,074.7 MiB | 17.8 to 21.8 MiB | 0.81 / 0.78 s |
| `CopyImporter.hash(uncached: false)` | 17.7 to 2,074.8 MiB | 17.7 to 21.7 MiB | 0.79 / 0.72 s |
| `CopyImporter.hash(uncached: true)` | 18.2 to 2,075.2 MiB | 17.8 to 21.8 MiB | 0.79 / 0.73 s |
| `CopyImporter.copyVerified`, at the copy loop's last byte | 17.8 to 2,074.8 MiB | 17.8 to 21.9 MiB | |
| `CopyImporter.copyVerified`, copy and verify | 17.8 to 4,131.8 MiB | 17.8 to 21.9 MiB | 2.20 / 1.74 s |

Every digest equalled `shasum -a 256`'s, before and after. So all three loops
grew with the file: a hash held the whole file, and a verified copy held it
twice (the copy loop's chunks, then the verification's). The
`SHA256ContentHasher` figure matches the one in #164 (17 to 2,074 MiB,
`docs/features/export-overwrites-masters/code-review.md`, fourth pass). The
scratch file and the measuring test were deleted afterwards.

**Root cause.** The loops read with `FileHandle.read(upToCount:)`, which
returns autoreleased `Data`, and none of them runs inside an autorelease pool
of its own. Each 4 MiB chunk stayed alive at least until the call returned
(the "after" column), so memory grew by the file's size per pass. This is the
shape #160 fixed in `MasterFiles.hash(of:)` (its C6); the importer's loops
were not changed then.

**Fix.** One shared reader, `FileChunks` (`Sources/PhotoCore/Import/FileChunks.swift`):
`read(2)` into one buffer allocated once per call and used for every chunk,
nothing autoreleased; `sha256(of:chunkSize:)` on top, and `write(_:to:)` for
the copy (all bytes, `write(2)`, `EINTR` retried). `MasterFiles.hash(of:)`,
`SHA256ContentHasher.contentHash`, `CopyImporter.hash(of:uncached:)` and
`copyVerified`'s copy loop all use it. Kept as they were: chunk sizes (4 MiB
for the importer, `SHA256ContentHasher.chunkSize` still public; 1 MiB for
`MasterFiles`), opening through `FileHandle(forReadingFrom:)` in the
importer (so a missing or unreadable file gives the same `CocoaError` and
failure text) and `open(2)` in `MasterFiles`, `F_NOCACHE` for uncached
reads, cancellation (checked before each read in `contentHash`, the copy
loop and `MasterFiles`; not in `CopyImporter.hash`, which had none: a copy
already moved into place is verified to the end), the progress callback per
chunk, and `output.synchronize()` before the move. A read error after the
file opened is now a `POSIXError` (was the `NSError` `FileHandle` threw);
the importer records it as a failure either way.

No rendering, migration, catalog or pipeline change; no digest changes.

**Tests that fail without the fix.** `ImportHashMemoryTests`
(`Tests/PhotoCoreTests/ImportHashMemoryTests.swift`, Swift Testing,
serialized). Each hashes a 1 GiB sparse file and passes when one of up to
five attempts grows the footprint by less than half the file (the guard
`hashingALargeFileHoldsOneChunkNotTheFile` uses, #160's C9). Run alone,
before the fix:
- `theContentHasherHoldsOneChunkNotTheFile`: failed, every attempt grew
  by about 1,078 MB (1 GiB file).
- `theCopyImportersHashHoldsOneChunkNotTheFile` (both modes, one after the
  other): failed; uncached grew 1.46 to 2.03 GB per attempt.
- `aVerifiedCopyHoldsOneChunkNotTheFile`: failed, the copy loop by about
  1,078 MB and copy plus verify by about 2,157 MB per attempt.

After the fix all three pass on the first attempt, alone and in the full
suite.

These pass before and after (byte-identical results):
- `digestsAreTheKnownOnes`: digests computed outside this code (Python's
  `hashlib` for a 9 MiB + 13 byte patterned file that ends inside a third
  4 MiB chunk; FIPS 180-2's one million "a"s; the empty file) from
  `SHA256ContentHasher` (default and a 4,093-byte chunk), `CopyImporter.hash`
  in both modes, `MasterFiles.hash` and `copyVerified`, which also reports
  every byte through progress and writes a byte-identical copy.
- `aMissingFileStillThrowsWhenOpened`: the importer's paths still throw
  `CocoaError` for a missing file, and a failed copy leaves no file.

The existing `ImporterTests.sha256MatchesKnownVectors`,
`aFileOfSeveralChunksHashesAsTheCatalogDoes`,
`aFileThatOpensAndCannotBeReadCountsAsAMaster` (EISDIR from `MasterFiles`)
and `hashingALargeFileHoldsOneChunkNotTheFile` pass unchanged. The last one's
footprint helper moved into `ImportHashMemoryTests.swift` as
`processFootprint()`, shared by both suites.

## Build and tests

- Baseline at `1e855e7`: `swift build` green.
- After the fix: `swift build` green, no new warnings.
  `swift test --filter "ImportHashMemoryTests|ExportMasterProtection|MasterFiles|CopyImport|ImporterTests"`:
  70 tests passed.
- Full `swift test` after the fix: 1,019 tests in 149 suites passed, exit 0,
  with the one known issue already marked in `LiveSessionTests` ("Values
  above white survive the cached stages", not touched here). The four memory
  guards and the digest tests passed in it.

## Known, not changed

- The memory guards measure the whole test process, which other suites move
  while they run (#160's C9 analysis applies: five attempts, a limit of half
  the file). A parallel run can, rarely, let a fault pass or fail a quiet
  run; run alone, the fault fails every attempt.
- `Sources/PhotoBench/Benchmarks.swift` copies files with the same
  `read(upToCount:)` loop. A benchmark tool, not the app; left alone.

## README

No change to requirements, build commands or layout. For the product manager
at Ship or the next reconcile: `CLAUDE.md`'s #160 entry lists "the
importer's hashing loops may hold whole files in memory" among open
follow-ups; this fixes it.

## Open questions

None.
