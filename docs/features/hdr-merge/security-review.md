# HDR merge: security review

Date: 2026-11-20. Branch `feature/hdr-merge` (issue #150), diff against `develop`, including the uncommitted working-tree changes present at review time (naming by stem, `sameContent`, 16-bit-only DNG, XMP document id). Read-only review; nothing was built or run.

## Verdict

Nothing reaches High. The placement into the folder beside a master is sound: it never replaces an existing file. There are two Medium findings, both denial of service (a crash or runaway memory from a hostile or oversized input frame), and several Low ones. No network code and no subprocess were added.

## Scope checks

- **No network, no subprocess.** The added Swift has no `Process`, `NSTask`, `posix_spawn`, `URLSession`, `URLRequest` or `dlopen`. The only `try!` is in `PhotoBench/MergeBenchmark.swift` (benchmark tool, trusted input), and `withMemoryRebound` appears once, in the benchmark's `proc_pid_rusage`. `Package.swift` and `Scripts/` are unchanged. Alignment uses the system's Vision framework in-process.
- **`photocli merge`** (`Commands/MergeCommands.swift`): declared `access: .write`, so `CommandRegistry.run` takes the `LibraryLock` first and refuses while the app holds it. `--format` is validated to `tiff` or `dng`. `--version` goes through the typed integer parameter, and ids are resolved only against the catalog, so no path or name comes from argv. Frame paths come from catalog rows only.

## Findings

### M1. Medium: no pixel or memory bound; hostile or very large frames crash or exhaust memory

`Merge/HDRMerger.swift:92` (`held`: `Data(count: width * height * 8)`), `Merge/MergeBitmap.swift:43`, `Merge/MergeOutput.swift:97` (TIFF: `Data(count: rowBytes * height)`, the whole 8-byte-a-pixel image), `Merge/HDRMergeJob.swift:122`.

`MergeLimits` bounds the frame count (9) and the alignment, but nothing bounds pixels. Only LibRaw raws are capped (`LibRawDecoder.maximumSensorPixels`, 150 MP). For system-decoded raws and for JPEG, HEIC, TIFF and PNG, the size is whatever the file's header says.

Scenario: a 4-byte-per-pixel-claiming PNG or TIFF with a small file size and a header of, say, 60000 x 60000 (3.6 GP), plus a second one of the same size. They pass the catalog's pixel-size equality check, because the catalog recorded the header's size. `measuringCopy` works (a lazy, reduced render). `fullFrame` then asks for a 28.8 GB `Data(count:)` per frame. The process is killed or aborts; `Data(count:)` doesn't throw. A legitimate 100 MP x 9 frame bracket holds 7.2 GB of half floats, plus 0.8 GB for the TIFF buffer, with no look at available memory.

All frames are decoded to full size before the size comparison at `HDRMergeJob.swift:132` (and the catalog's check only helps when `pixelSize` is recorded).

Crash consequences: no data loss (edits are saved per gesture; the `.partial` file may remain). It does take the whole app down from one selected file.

Fix: add `MergeLimits.maximumPixels` (for example 200 MP per frame) and a total budget (frames x pixels x 8 bytes against a fraction of `ProcessInfo.physicalMemory`). Check it in `MergeSelection.refusal` from the catalog's `pixelSize`, and again in the job from each decoder's extent before `held` allocates, mapped to `Failure.noMemory`. For the TIFF, write in bands instead of one buffer (the DNG path already does).

### M2. Medium: DNG strip offsets trap above 4 GiB, after the temporary file exists

`Merge/LinearDNGWriter.swift:288`: `UInt32(start + row * rowBytes)` traps (Swift overflow) when the pixel data passes 4 GiB, which for 16-bit RGB is above about 715 MP. `rowBytes`, `StripByteCounts` and the strip count are otherwise fine (a strip is at most about 1 MiB, or one row, and `max(1, …)` covers the width > 174762 case, where the division would give 0).

Reachable only with M1-sized inputs, but the trap happens in `header()`, called from `init` after `createFile` at line 72. The `defer` in `writeInPlace` doesn't run on a trap, so an empty `.<name>.<UUID>.partial` stays beside the master.

Fix: in `init`, `guard UInt64(width) * UInt64(height) * 6 + headerSize <= UInt32.max else { throw … }` (a clear "too large for a DNG" failure), before creating the file. The same cap belongs with M1's pixel limit. The TIFF side has no equivalent trap: ImageIO fails the finalize cleanly (reason string empty, see L5).

### L1. Low: a file name over about 200 bytes can't be merged (hidden temporary name too long)

`Merge/MergeOutput.swift:190`: the temporary name is `.` + final name + `.` + 36-character UUID + `.partial`, so it is 46 bytes longer than the result name. The result is the master's stem + `_HDR.tif` (8 bytes). Masters whose stem is 202 to 247 bytes (legal on APFS, NAME_MAX 255) get a final name that fits but a temporary name that doesn't. `createFile` or ImageIO fails with ENAMETOOLONG, surfaced as a generic write failure. For the TIFF, `CGImageDestinationFinalize` fails and the reason is `""`. Stems over 247 bytes fail on the final name as well. This is a clean failure, nothing is written, and there is no traversal. Fix: build the temporary name from a short fixed prefix (`.merge-<UUID>.partial`), not from the final name.

### L2. Low: `removeItem(at: url)` after `sameContent` deletes by path

`Merge/HDRMergeJob.swift:217`. After the catalog refuses the new file, the job deletes whatever is at `url`. The job just linked that file there, so normally it is the right file. But the catalog check is by hash or path (`conflictingPaths` as well as duplicate hashes both give `sameContent` now), and the delete is by path, not identity. If another process replaced or renamed the file in the (short) window, the other file is deleted. Fix: record `stat` (device and inode) right after the link in `writeInPlace`, and delete only when they still match; or compare the size and mtime held in `NewMaster`. Symlinks are safe here (`removeItem` removes the link, not its target).

### L3. Low: exposure metadata is trusted without bounds (garbage output, not memory-unsafe)

`Merge/MergeExposure.swift:59` and `metadataExposure` (line 96). `exposureTime`, `fNumber` and `iso` come from the catalog (parsed from the file at import). `time > 0` accepts `+inf`; a tiny or huge value gives an `a / b` of `inf`, `NaN` or 0 for `stepRatio` when pixels can't give a measured ratio. Then `relative[...] / base` can divide by zero, and NaN exposures flow into the weights, the percentile sort (`brightest`) and the output. The result is a black or corrupt merged photo, written and catalogued. No trap was found: `Int(...)` conversions are on clamped or percentile values, and alignment rejects NaN or inf homographies through `isHandHeld` (NaN comparisons are false) before `Int(source.x…)` in `correlation`. Fix: in `metadataExposure` require `isFinite` on all inputs and clamp the ratio (for example 2^-16 to 2^16, else 1); also reject a non-finite or non-positive measured `ratio` result and exposure.

### L4. Low: `fileExists` in `photocli merge` accepts a stale mount path

`Commands/MergeCommands.swift:53`: `isOnline = online.contains(volume.identity) || fileExists(mountPath)`. If a volume is unmounted but its recorded `mountPath` exists as a plain directory (or another disk is mounted there), the CLI treats the volume as online and reads and writes there, and catalogues the result under the original volume id. The folder must exist and be writable (`MergePreflight`), so this takes a coincidence, but a new file lands on the wrong volume. Fix: require the identity match (as the app does), or compare the volume identity at the path.

### L5. Low: `String(describing: error)` logged as `.public`

`Merge/HDRMergeJob.swift:126` (and :219): errors such as `Failure.undecodable(URL)` and `CocoaError` include absolute paths, which land in the unified log unredacted (file names are `.private`, but the error text isn't). Fix: log the error with `.private`.

### L6. Low: hidden `.partial` files are left after a crash, kill or quit

`defer` removes the temporary file on every normal and cancelled exit, but not on a trap (M2), SIGKILL, power loss, or Stop and Quit that terminates before the task unwinds (also in `code-review.md` C2). Result: a hidden, possibly multi-GB file beside the master. Nothing reads or imports it. A launch-time or next-merge sweep of `.*.partial` older than a day, in the folder being written, would clean up.

### L7. Low: a file system without hard links falls back to check-then-`moveItem`

`Merge/MergeOutput.swift:213-217`. `link(2)` is the right primitive: it fails with `EEXIST` instead of replacing, which also covers a dangling symlink at the destination (it isn't followed), a file that appeared after the name was chosen, and case-insensitive collisions. The fallback runs for any errno other than `EEXIST` (not only `ENOTSUP` or `EPERM`, for example `EACCES`, `ENOSPC`, `EMLINK`), and is a `fileExists` then `moveItem`, a narrow TOCTOU on FAT/exFAT cards and some SMB shares, as far as `moveItem` itself replaces nothing (Foundation documents an error when the destination exists; I have not verified it uses an exclusive rename). Fix: limit the fallback to `ENOTSUP`/`EPERM`/`EOPNOTSUPP`, and use `renamex_np(…, RENAME_EXCL)` there. Other errors should map to `writeFailed`.

### L8. Low: a stem from the catalog is joined into a path unchecked

`Merge/MergeSelection.swift` (`resultName`) uses `referenceFrame.fileName` and `MergeSelection.swift:73`/`HDRMergeJob.newMaster` use `relativePath`. A normal catalog never holds a `/` in `fileName` (the file system can't). A catalog from elsewhere (a copied library, a hostile `.sqlite`) could, and then `folder.appending(path: "../../x_HDR.tif")` would write outside the master's folder. This needs a crafted library, which already lets its author name any master path, so the practical risk is low. Fix: in `resultURL`, require `name == name.lastPathComponent`, not `.`/`..`, and no NUL; and require `fileName == (relativePath as NSString).lastPathComponent`.

## Checked, no finding

- **Placement and replacement**: `link(2)` with the temporary and final name in the same folder; `EEXIST` becomes `nameTaken`, retried 3 times with a fresh free name (`HDRMergeJob.swift`, the `for attempt` loop). Existing files, masters and symlinks are never replaced. The free name is also now chosen from a directory listing (stem-wise), so symlinks and dangling links are seen. If the listing fails (`try?`), the name falls back to master names only, and `link(2)` still protects.
- **Temporary file**: UUID v4 in the name, so a symlink can't be planted ahead; `createFile` then `FileHandle(forWritingTo:)` are two opens on a name only this process knows. Mode is the process umask default (typically 0644), as for masters and exports. The temporary is unlinked after the link.
- **Folder that is a symlink**: the folder is wherever the master was read from; writing through the link lands beside the master. Consistent with how the master was reached. Preflight needs an existing, writable, non-read-only folder.
- **Odd characters**: NUL or control characters can't be in a file system name; `withUnsafeFileSystemRepresentation` is used for `link`. Case-folding and normalization are handled by `MasterFiles.folded` and by the file system. A very long name: see L1. `ExportNaming.unique`-style numbering terminates (`fileExists` returns false for an over-long name).
- **DNG/TIFF layout**: entries sorted by tag; `UInt16(entries.count)`, `UInt32(entry.count)` and offsets are bounded by a header of a few KB plus XMP and text (no cap on caption or XMP size, but they come from the user's own library values and can't pass 4 GiB). `rational`s check finite and non-negative; `srational`/GPS values go through `fraction`, whose clamp makes `Int64(...)`, `UInt32(numerator)` and `Int32(numerator)` safe for NaN and inf (no trap; GPS NaN gives a bounded junk fraction). ISO uses `UInt16(clamping:)`. The strip count and `StripByteCounts` are right for any width (one row per strip when a row exceeds 1 MiB). `write(rows:)` preconditions are guaranteed by the band loop. `scratch`/`halves` hold one band only.
- **Frame reading**: LibRaw frames are capped; alignment is on a 2048-pixel copy, so its cost doesn't grow with the image; `values[count / 2]` and `maxima[min(count - 1, …)]` are guarded by non-empty checks; integer division in naming and layout has non-zero divisors.
- **Metadata**: `Metadata.sendableValue` converts NSNumber safely (`int64Value` of an out-of-range or infinite double doesn't trap in Foundation). GPS of the reference is copied into the merged TIFF and DNG (the export's "all" level), and the rating, flag and label go into the XMP, by design (R7).
- **Catalog**: `insertMergedMaster` is one transaction with bound arguments; `pairPartners` builds its `IN` list with `databaseQuestionMarks` and bound values (no interpolated data). `photocli merge` with several thousand `--version` arguments could exceed SQLite's variable limit and fail with an error (not a crash).
