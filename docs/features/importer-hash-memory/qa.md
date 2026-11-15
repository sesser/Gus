# Importer hashing holds whole files in memory: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`. Bug fix, issue #164.
Tested: `bug/squash-top-10` at 7047bad, on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict
Passes. Each of the three loops (content hasher, the card importer's hash in both modes, the verified copy) fails its memory test on `develop`'s code when the test runs alone (footprint grows by about 1.08 GB on a 1 GiB file) and passes with the fix; digests match values computed outside the code.

## Acceptance criteria
The criteria are the Bug section of `status.md` and the issue.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| `SHA256ContentHasher.contentHash` holds about one chunk, whatever the file's size | Test | `ImportHashMemoryTests.theContentHasherHoldsOneChunkNotTheFile` | Pass |
| `CopyImporter.hash(of:uncached:)` holds about one chunk, in both modes | Test | `theCopyImportersHashHoldsOneChunkNotTheFile` | Pass |
| `copyVerified` holds about one chunk in the copy and again in the verification | Test | `aVerifiedCopyHoldsOneChunkNotTheFile` | Pass |
| Digests are identical to before and to an outside implementation (a file ending inside a third chunk, one million "a"s, the empty file; default and odd chunk sizes; `copyVerified` writes a byte-identical copy and reports every byte) | Test | `digestsAreTheKnownOnes`; `ImporterTests.sha256MatchesKnownVectors`, `aFileOfSeveralChunksHashesAsTheCatalogDoes` | Pass |
| Opening errors are unchanged (a missing file still throws `CocoaError`; a failed copy leaves no file); cancellation stops at a chunk boundary | Test | `aMissingFileStillThrowsWhenOpened`; `ImporterTests.cancellationStopsAtAChunkBoundaryAndKeepsWholeChunks` | Pass |
| `MasterFiles.hash` (export's check) still holds one chunk and reads an unreadable file as a master | Test | `hashingALargeFileHoldsOneChunkNotTheFile`; `aFileThatOpensAndCannotBeReadCountsAsAMaster` | Pass |

Tests that fail without the fix: in a scratch copy of the branch with `ContentHasher.swift`, `CopyImporter.swift` and `MasterFiles.swift` put back to `develop`'s, each memory test run on its own failed on all five attempts: content hasher grew by 0.94 to 1.33 GB; the card importer's hash by 1,078,461,184 to 1,078,477,592 bytes in both modes; the verified copy failed both of its assertions (copy loop alone, and copy plus verify). Run together in suite order, only the first two failed: `aVerifiedCopyHoldsOneChunkNotTheFile` passed on the old code because the earlier tests had already raised the process footprint. That is the guard's known limit (`status.md` "Known, not changed"); a regression in `copyVerified` alone is still caught, since nothing earlier would have raised the footprint. The sparse 1 GiB files, five attempts and a limit of half the file were read and are reasonable.

Full run: `swift test` 1032 tests in 153 suites passed, 1 known issue, with the four memory guards and the digest tests among them. `Scripts/build-app.sh all` built.

## Findings
None.

## Scripts
None needed: no UI, and the memory is measured by the tests. The checks that ran:

```
swift test --filter "ImportHashMemoryTests/theContentHasherHoldsOneChunkNotTheFile"
swift test --filter "ImportHashMemoryTests/theCopyImportersHashHoldsOneChunkNotTheFile"
swift test --filter "ImportHashMemoryTests/aVerifiedCopyHoldsOneChunkNotTheFile"
```
Each in the scratch copy with the three files reverted (all fail) and in the checkout (all pass).

## For a person
Nothing. A multi-gigabyte real video import was not timed or measured in the app; the 2 GiB measurements in `status.md` (17.8 to 21.9 MiB after the fix, same time) are the engineer's.

## Follow-up
For the product manager at Ship: `CLAUDE.md`'s #160 entry lists "the importer's hashing loops may hold whole files in memory" as an open follow-up; this fixes it (`status.md` README note).

## Summary for the issue
QA passes (#164). Run alone on the old code, the three memory tests fail (footprint grows by about 1.08 GB on a 1 GiB file); with the fix they pass and digests match outside values. Full `swift test` 1032 passed. Nothing for a person. `docs/features/importer-hash-memory/qa.md`.
