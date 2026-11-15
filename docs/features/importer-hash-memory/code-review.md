# Importer hashing holds whole files in memory: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/squash-top-10`, 1e855e7..05873e0 (the #164 commit; branch head
8d87d90). Build and tests: `swift build` clean; full `swift test` at 8d87d90:
1030 tests in 152 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`), `ImportHashMemoryTests` among them.

## Verdict
Ready for QA. One shared reader with one reused buffer replaces the three
`read(upToCount:)` loops and `MasterFiles`' own copy of the same loop. Digests,
chunk sizes, opening errors and cancellation are unchanged. I found nothing to
fix.

## Findings
None.

## Questions
None.

## Checked and fine
- `FileChunks.forEach`: allocates once (`max(chunkSize, 1)`, so a chunk size
  of 0 can't trap) and frees in `defer`. It retries `read(2)` on `EINTR`,
  maps other errors to `POSIXError`, and checks for cancellation before each
  read when asked. The buffer passed to `body` is a rebased slice of the
  bytes read, so a short read hashes and writes exactly what was read.
- `FileChunks.write`: loops until every byte is written and retries `EINTR`.
  `copyVerified` still calls `output.synchronize()` before the move and
  reports progress per chunk. `FileHandle` keeps no buffer in user space, so
  mixing it with `write(2)` on its descriptor is safe.
- `CopyImporter.hash` stays not cancellable, as before: a copy already moved
  into place is verified to the end. `SHA256ContentHasher.contentHash`
  checks for cancellation per chunk, as before. Files are still opened
  through `FileHandle(forReadingFrom:)`, so a missing file still throws
  `CocoaError` (`aMissingFileStillThrowsWhenOpened`).
- Digests are pinned to outside values: hashlib, the FIPS 180-2 million
  "a"s, and the empty file. They cover a file ending inside a chunk and a
  4,093-byte chunk size.
- Memory tests: one suite, run in series, five tries at half the file's
  size, the same guard as #160's C9. They fail without the fix and pass
  here. The process-wide footprint caveat is recorded in status.
- Copying imports still verify every copy (re-read around the cache, hash
  compared) before it counts.
- Security: `FileChunks` reads bytes only. It parses nothing, takes no path
  from file contents, and holds a fixed-size buffer, and the copy writes to
  the same destination it did before. On its own it does not need
  `/security-review`; the branch's run (for #166) covers it anyway.

## Follow-up
