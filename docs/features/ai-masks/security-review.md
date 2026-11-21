# Security review: ai-masks (issue #88)

Branch `feature/ai-masks`, diff against `develop`. Read-only review; nothing was built or run.

**Verdict: nothing meets the bar for High or Medium.** The branch adds no network code, no subprocess and no file writing outside the library. Two Low findings and four notes follow. The Lows are hardening of the stored-PNG read and of the unreferenced-row cleanup. A normal catalog cannot reach either one. A damaged or hand-edited catalog can.

Trust model: the catalog is the owner's own SQLite file, and a shared or copied catalog is the only realistic way to supply hostile rows. Vision's output is trusted OS data.

## Scope checks

| Item | Result |
| --- | --- |
| Network, subprocess, dynamic loading | None added. A grep of the added lines found no `URLSession`, `Process`, `NSTask`, `dlopen` or `URL(string:)`. Vision's two requests run on device; the code never starts a model download. |
| File writing | None added. The only new file access is `FileManager.default.fileExists` on the master in `MaskCommands.detect` (`Commands/MaskCommands.swift`, in `detect`). The path comes from the catalog's own `image.relativePath` and the volume. It is read and never written. The `--shape` detection reads the original through the existing `PreviewGenerator.decode`. |
| Originals | Never written. |
| SQL parameterization | All new SQL is parameterized (see 4). |

## 1. PNG decode of stored results

`MaskRaster.pixels(fromPNG:)` (`Sources/PhotoCore/Edits/Masks/MaskRaster.swift`, the `pixels` function).

What is good:
- The `&&` guard chain checks `CGImageSourceGetCount == 1`, 8-bit gray, no alpha, a monochrome colour space and `width/height <= 4096` before it touches `image.dataProvider?.data`. That access is what forces the pixel decode. A PNG whose IHDR claims 60000x60000 is therefore refused before any pixel buffer is allocated.
- The copy loop is bounded. `bytes.count >= bytesPerRow*(height-1)+width` is checked first, and the product is at most about 16.7M.
- Palette, 16-bit, gray+alpha and tRNS-with-alpha PNGs are all rejected, and a non-PNG blob gives `unreadable`. `MaskRasterStore.entry` also requires the decoded size to equal the row's `width` and `height`, and a failed read is never cached as a result.
- Damaged rows (wrong encoding, unknown request, bad bytes) all map to `.missing` and select nothing. Nothing crashes: no force unwrap is reachable except `raw.baseAddress!`, and that exists for any non-empty data.

### L1 (Low): the 4096 side cap is far above what Vision produces, and the memory it allows is not small

`maximumSide = 4096` (`MaskRaster.swift`, `maximumSide`) while the comments say rows are 2 to 110 KB and "at most 256 KB at Vision's sizes" (`MaskRasterStore.swift`, header comment). A crafted row of 4096x4096 all-zero gray compresses to a few KB. Per component it then costs:
- 16 MB of `levels`;
- 64 MB for the `[Float]` copy in `GuidedMaskFilter.stretched` (`GuidedMaskFilter.swift:52-53`), plus a second 64 MB `Data` copy of it from `withUnsafeBytes { Data($0) }`;
- the guided-filter passes on top.

The store keeps up to `capacity = 48` decoded entries, so about 770 MB of levels alone. A stack may name up to 32 masks x 16 components. A hostile or damaged catalog can therefore drive the loupe, export or `photocli render` to several GB of memory. This is a local denial of service from a file the owner chose to open. No code execution or data loss follows.

Fix:
- Lower `maximumSide` to 1024. Vision's masks are 512 on the long side, and the reader and writer share the constant.
- Check the row's own `width` and `height` against it in `Catalog.maskRaster(_:digest:)` before decoding. Today `entry` compares them only after decoding.
- Cap the blob in SQL with `AND length(data) <= <bound>` (about 1 MiB), or select `length(data)` first. At present `row["data"]` loads a blob of any size, and ImageIO is then run on it.
- Optionally read `CGImageSourceCopyPropertiesAtIndex` (pixel width and height) before `CreateImageAtIndex`. This is defence in depth. In practice the check order already prevents decoding.

### L2 (Low): `MaskRaster(stored:)` trusts the row's digest key

The digest is computed from the bytes (`MaskRaster.init(stored:)`), but the lookup is by the primary key. A row whose key does not match the SHA-256 of its bytes is served, and its digest is then the recomputed value. This only matters in a hand-edited catalog, where an integrity check would not be a security boundary anyway. Suggested fix, optional: in `Catalog.maskRaster(_:digest:)`, treat `raster.digest != digest` as damaged.

## 2. `MaskRasterReferences` text scanner and cleanup

`Sources/PhotoCore/Catalog/MaskRasters.swift`, `removeUnreferencedMaskRasters` and `enum MaskRasterReferences`.

What is good:
- The scanner is a linear byte scan with no regular expression and no JSON parser on the stack text, so it has no catastrophic-backtracking or injection surface. The loop bound `index + key.count + 64 <= bytes.count` keeps every slice in range. A candidate must pass `isDigest` (64 lowercase hex), so a malformed or truncated value is skipped. Malformed JSON is irrelevant because the text is never parsed.
- Over-matching is harmless. A digest quoted inside, say, a free-text field only keeps a row longer.
- All the SQL reads and the delete run in one `database.write` transaction. The delete is chunked at 10,000 with bound parameters, which stays under SQLite's variable limit.
- It runs only from `LibraryModel.start`, at launch, after the library lock is held. The in-process undo stack is empty then, and `photocli` never calls it. Within a session nothing deletes rows. `mask add` writes the row and the stack in one transaction (`setEditStacks(... storing:)`). The app stores the row first and then the stack on the same write chain (`MaskDetectionEditing.land`), so a crash between the two leaves only an orphan, which is cleaned later.
- The `instr(editStack, '"raster"') > 0` prefilter is safe for the current canonical encoding, which has no spaces.

### L3 (Low): damaged `editHistory.maskRasters` fails open to deletion

`MaskRasterReferences.decode` returns `[]` when the JSON array cannot be decoded (`MaskRasters.swift`, `decode`). The cleanup then treats that entry as naming nothing. The entry's snapshot is LZFSE-compressed and is not re-scanned. Failure scenario: a truncated copy or partly written row leaves `maskRasters` unreadable, so rows reachable only through that history entry are deleted at the next launch. Reverting to that entry later gives a `missing` detection (the mask selects nothing). No stack is corrupted, and the owner can re-run Update. The consequence is irreversible loss of a cached result, not a security impact.

Fix: when `decode` fails (not when the column is NULL), decompress that entry's `stack` with `EditHistory.decompress` and scan it with `digests(inStackJSON:)`. Alternatively, skip the whole cleanup for that launch when any non-NULL entry fails to decode. A NULL column is correct for pre-v15 entries, which could not name a row.

Scanner notes, no action needed:
- `Array(bytes[index..<(index+key.count)]) == key` allocates a ten-byte array for every `"` in the stack. That is linear but allocation-heavy. It runs on every history write, over at most a few MB, so it is a performance nit only. Compare with `bytes[index...].starts(with: key)` or `withUnsafeBufferPointer` instead.
- The scanner's correctness depends on the exact `"raster":"` spelling. A future encoder change that adds whitespace would silently lose references. A test that round-trips a stack through the real encoder is in place via `MaskRasterCatalogTests`. Keep it.

## 3. Vision pixel buffers

`VisionMaskDetector.levels(of:)` (`Sources/PhotoCore/Suggestions/MaskDetector.swift`).

- The buffer is locked read-only and unlocked with `defer`. The pixel format is whitelisted (one-component 32-bit float, 16-bit half, 8-bit); anything else returns nil and becomes `unusableMask`. NaN and infinity are mapped to 0, and the value is clamped before the `UInt8` conversion, so there is no trap.
- Rows are addressed with the buffer's reported `bytesPerRow`, so padded rows are handled.

### Note N1 (Info): there is no explicit stride or size check

The code does not assert `rowBytes >= width * bytesPerPixel`, and it does not call `CVPixelBufferIsPlanar` or `CVPixelBufferGetDataSize`. `[UInt8](repeating:count: width*height)` is allocated before `MaskRaster.init` rejects sides above 4096. Vision is a trusted system component and gives 512x512 or 512x384, so this is not exploitable today. For defence in depth, validate `width, height <= MaskRaster.maximumSide` and `rowBytes >= width * bytesPerPixel` before allocating or reading.

## 4. Migration v15 and catalog SQL

- `addMaskRasters` (`CatalogSchema.swift`) creates `maskRaster` with a text primary key and `NOT NULL` columns, and adds a nullable `editHistory.maskRasters`. It is additive and does not edit an earlier migration, as the project rules require. The existing `editHistory` rows get NULL, which is correct.
- Every statement is parameterized: `INSERT OR IGNORE ... VALUES (?...)`, `SELECT ... WHERE digest = ?` (guarded by `isDigest` first), and the chunked `DELETE ... IN (databaseQuestionMarks)` with `StatementArguments`. The `UPDATE`/`DELETE` check helpers (`deleteMaskRasterForChecks`, `damageMaskRasterForChecks`) are parameterized too. They are marked "for checks only"; the only call sites found are the debug script. Confirm no menu or command reaches them (none found in this diff).
- `Copies.swift` and `EditHistory.swift` carry the new column through remove and restore of a copy and through history writes, all with bound parameters.
- `INSERT OR IGNORE` means a second row with the same digest is dropped silently. Since the digest is the content hash, that is correct.
- Row size is bounded neither by the schema nor by the reader (see L1).

## 5. `photocli mask add --shape ...`

`Sources/PhotoCore/Commands/MaskCommands.swift`, `runAdd`, `detect` and `change`.

- `--shape` is validated against `MaskShape.names`. `subject`, `people` and `background` are matched with `MaskDetectionKind(rawValue:)`, and `--params` is refused with them, so the user cannot inject a digest at creation. The digest in the stack always comes from a raster that was just produced and stored.
- `--dry-run` runs the detection (so Vision executes) and writes nothing: the `setEditStacks` call is skipped for a dry run. The access class is `.writeUnlessDryRun`, so the library lock is applied only for a real write.
- `detect` reads the master path from the catalog. The `fileNotFound` message echoes that path. It reaches only the caller's own terminal and carries no secret.
- Detection failures (`unavailable`, `failed`, `unusableMask`) are not errors. They produce a component without a result. This is by design (R6).
- `mask set --set name=value` accepts only known mask settings, so it cannot change a digest. A digest typed by hand into a stack still goes through `isDigest` (`LocalAdjustments.swift:343`) and the strict reader.
- A stored `raster` digest in a stack that names no row gives `missing` and selects nothing. The renderer never turns a failed lookup into an error that stops the render.

No finding for this item.

## Summary of findings

| ID | Severity | Where | Short |
| --- | --- | --- | --- |
| L1 | Low | `MaskRaster.swift` `maximumSide`; `MaskRasters.swift` `maskRaster(_:digest:)` | A 4096-pixel cap and an unbounded blob allow multi-GB memory from a crafted row; tighten to 1024 and cap `length(data)` |
| L2 | Low | `MaskRaster.swift` `init(stored:)` | The row key is not checked against the SHA-256 of its bytes |
| L3 | Low | `MaskRasters.swift` `decode`, `removeUnreferencedMaskRasters` | A damaged `maskRasters` text makes the cleanup delete rows that history still names; fall back to scanning the entry's snapshot |
| N1 | Info | `MaskDetector.swift` `levels(of:)` | There is no stride or size assertion before allocating |
