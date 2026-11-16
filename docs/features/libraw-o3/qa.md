# LibRaw at -O3: QA

Owner: qa-tester. Date: 2026-11-16. Step 4 of `docs/WORKFLOW.md` (bug-fix route, issue #195).
Tested: `feature/libraw-o3` at 5fa9206, on a Mac with an Apple M4 Pro, macOS 27.2.1 (26B131), macOS SDK 27.2, Swift 6.4.2.
`develop` (7218154) was built from `git archive` in a scratch folder outside the checkout for every comparison.

## Verdict

Passes. Release builds compile the vendored LibRaw at `-O3` and debug at `-O0`; the debug and release test suites pass;
LibRaw's output is unchanged in every comparison I made; the bundles build; and the timings reproduce (Bayer full
decodes about 2x as fast, Fujifilm X-Trans about 8 to 9% by `photobench rawcompare`). Nothing for a person to check.
Two notes, neither blocking: a one-off render difference that is in the `develop` (`-Os`) binary, not this branch's
(Q1), and an isolation slip of mine at the top of the next section.

## Isolation check (failed, read-only)

The closing check failed in one respect, so I stopped testing. `photocli render <file>` with no `--library-root`
opens the owner's standard library read-only to ask whether `--out` is a master (by design, #166:
`RenderCommands.refuseOriginal`; no migration, no lock, nothing written). I ran it without `--library-root` (the
`cmp.sh` runs below), so `~/Library/Application Support/Gus/Library/catalog.sqlite-shm` has a modification time
inside my session (15:11:57). `catalog.sqlite` (Nov 15 07:09), `catalog.sqlite-wal` (Nov 15 07:09) and `library.lock`
(Nov 15 08:24) are unchanged, and no instance of the app, importer or photocli was running afterward. I do not
believe the catalog changed, but I cannot prove it from timestamps; the owner should know. No app was launched; no
debug script was run. The renders should have passed `--library-root <scratch library>` (see Q2); rerunning
`$S/cmp.sh` should add that option.

## Acceptance criteria

The contract is the **Bug** section of `status.md` and issue #195 ("Check that LibRaw's output is byte for byte
unchanged, and that build time and binary size are acceptable"). There is no PRD.

| # | Criterion | How | Evidence | Result |
|---|---|---|---|---|
| B1 | Release builds compile CLibRaw at `-O3`, debug at `-O0` | Script (build inspection) | S1 | Pass |
| B2a | `swift build` (debug) and full `swift test` (debug) pass | Test | S2: 1047 tests in 156 suites passed | Pass |
| B2b | `swift test -c release` passes (LibRaw at `-O3`) | Test | S2: 1047 tests in 156 suites passed | Pass |
| B3a | LibRaw suites still pass | Test | `LibRawFallbackTests` with `RAF_SAMPLE=DSCF5123.RAF` (release): 9 of 9; `GoldenTests`, `LibRawDecoderTests`, `LibRawFallbackPipeline`, `RAWDecode`, `LinearRawDecode`, `CameraColor`: 68 tests passed (RAW goldens skipped by fingerprint: this Mac's build is 26B131, goldens are 26B123; same on `develop`) | Pass |
| B3b | LibRaw output unchanged between `-Os` (`develop`) and `-O3` (branch) | Script (renders compared byte for byte) | S3, S4 | Pass (Q1 is a note) |
| B3c | `LibRawAgainstSystemTests` known failures are not this branch's | Test | S5: 8 issues on both, the same expectations | Pass (identical to `develop`) |
| B4 | `Scripts/build-app.sh all` succeeds, with LibRaw built at `-O3` | Script | S6 | Pass |
| B5 | Timing claims reproduce roughly | Script | S4 (`photobench rawcompare`) | Pass |
| B6 | Binary size and build time acceptable | Script | S7 (size reproduces; clean build time not re-measured) | Pass for size; build time taken from `status.md`, not re-measured (S7) |

Test for the Bug itself: none can see the optimization level without adding a C file to the vendored tree, which
`CLAUDE.md` forbids; `status.md` says so and I agree. B1 is therefore a build inspection, repeatable with the
command in S1. That is a gap in automation, not a failure.

## Findings

**Q1 (note, not this branch's; unreproduced).** One render of `DSCF5123.RAF` (the X-E3 file LibRaw decodes) differs
from every other render of it. Steps: `photocli render DSCF5123.RAF --long-edge 3000 --set exposure.ev=0.7 --set
whiteBalance.temperature=4500 --set tone.shadows=40 --out x.tiff`, with the `develop` (`-Os`) binary, the first time
that binary ran: SHA-256 `773573c6…`. Every later run, with either binary (the other 5 batches I ran, 6 repeats of
each binary, and 3 freshly copied and re-signed binaries), gives `042d9c95…`. About 530 of the 18 million 16-bit
samples differ, by at most about 32 of 65535 (the sample alignment is assumed). Expected: identical. Actual: one
difference, in the old build. It matches the engineer's note (the first `-Os` run of `DSCF5123.RAF` at full size,
also unreproduced), so a cold-start effect of the `-Os` binary's first run, downstream of LibRaw (Core Image or the
GPU), is likely; LibRaw's own pixels are proven equal by the engineer's probe and by the equal renders of the 1200
and full-size versions of the same file in the same batch. Nothing to fix on this branch; the engineer proposes a
follow-up issue.

**Q2 (process).** My `photocli render` runs touched the owner's library read-only (above), because I did not pass
`--library-root`. For the main session: QA runs of `photocli render` should always pass `--library-root <scratch>`.

No other findings. Nothing under `Sources/`, `Tests/`, `Scripts/` or `Package.swift` was edited by me.

## Scripts

Scratch folder: `/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad`
(`$S`). The `develop` copy is `$S/dev`, from `git archive develop`.

**S1. The flag (B1).**

```sh
tr ' ' '\n' < .build/out/Intermediates.noindex/PhotoWorkspace.build/Release/CLibRaw-t.build/Objects-normal/arm64/*-common-args.resp | grep -n '^-O\|^-ffast\|^-ffp'
tr ' ' '\n' < .build/out/Intermediates.noindex/PhotoWorkspace.build/Debug/CLibRaw-t.build/Objects-normal/arm64/*-common-args.resp | grep '^-O'
clang -### -Os -O3 -c t.c 2>&1 | grep -o '"-O[0-9s]"\|-vectorize-loops'
```

Branch release: `7:-Os`, `21:-O3` (no `-ffast-math`, `-Ofast` or `-ffp-` flag). Branch debug: `-O0` only. `develop`
release (the scratch copy): `-Os` alone. clang with both flags hands the compiler `-O3` and `-vectorize-loops`. The
release objects (79) were compiled with that response file.

**S2. Tests.** `swift build`; `swift test` (debug): 1047 tests in 156 suites passed. `swift test -c release`: 1047
tests in 156 suites passed. `RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF swift test -c release --filter
LibRawFallbackTests`: 9 of 9. `swift test -c release --filter 'GoldenTests|LibRawDecoderTests|LibRawFallbackPipeline|RAWDecode|LinearRawDecode|CameraColor'`: 68 tests passed.

**S3. Renders compared (`photocli`, 16-bit TIFF).** `$S/cmp.sh <photocli> <outdir>` renders each of five files three
ways (full size, `--long-edge 1200`, `--long-edge 3000 --set exposure.ev=0.7 --set whiteBalance.temperature=4500
--set tone.shadows=40`): X-E3 `DSCF5123.RAF` and X-T3 `DSCF4583.RAF`, and the three Bayer samples from
`gus-dcp-samples`. Run on `develop`'s release `photocli` and the branch's, three batches each. All 15 files per
batch are byte for byte equal across all six batches, except the single `-Os` render in Q1. Only `DSCF5123.RAF`
reaches LibRaw by this path: the system decoder gives an image for the X-T3 and the three Bayer files, so those
renders show only that nothing else moved; S4 reaches LibRaw directly for all five.

**S4. `photobench rawcompare` (output and timing).**

```sh
D=/Users/randy/Desktop/Export/gus-dcp-samples
FILES="$D/GX85.RW2:$D/Canon5DMkII.CR2:$D/EM5MarkIII.ORF:/private/tmp/claude-501/x/DSCF5123.RAF:/private/tmp/claude-501/cmp/in/DSCF4583.RAF"
$S/dev/.build/release/photobench rawcompare --files "$FILES" --output $S/rc-os --runs 5
.build/release/photobench rawcompare --files "$FILES" --output $S/rc-o3 --runs 5
for f in $S/rc-os/*.png; do cmp -s $f $S/rc-o3/$(basename $f) && echo same || echo DIFF; done
```

`LibRawDecoder.decode` at full size through the color step to 8-bit sRGB, then 1600 px PNGs. All 9 PNGs (LibRaw and
system, five files) are byte for byte the same between `-Os` and `-O3`, and the printed mean differences from the
system decoder are identical (19.46, 44.87, 9.58, 1.73). I looked at `DSCF5123-libraw.png`: the stained glass and
candles, correct and not blank. Times, best of 5, decode plus render:

| File | Full `-Os` | Full `-O3` | Change | Half `-Os` | Half `-O3` |
|---|---|---|---|---|---|
| GX85 RW2 | 0.88 s | 0.40 s | 2.2x | 0.13 | 0.11 |
| 5D II CR2 | 1.15 s | 0.61 s | 1.9x | 0.29 | 0.28 |
| E-M5 III ORF | 1.17 s | 0.62 s | 1.9x | 0.31 | 0.30 |
| X-E3 RAF | 8.65 s | 7.98 s | -8% | 0.59 | 0.60 |
| X-T3 RAF | 9.31 s | 8.49 s | -9% | 0.63 | 0.62 |

The engineer's decode-only figures (2.2x, 1.9x, 1.9x, -13%, -13%) agree roughly; mine include the render, which
`-O3` does not change, so the X-Trans change looks smaller.

**S5. `LibRawAgainstSystemTests`.**
`RAW_BOTH_SAMPLES=GX85.RW2:Canon5DMkII.CR2:EM5MarkIII.ORF:DSCF4583.RAF swift test -c release --filter LibRawAgainstSystemTests`,
on the branch and in the `develop` scratch copy: both fail with 8 issues, the same expectations (Kelvin 2, daylight
ΔE 2, unedited ΔE 2, brightness 1, tone spread 1). Pre-existing; not this branch's.

**S6. Bundles.** `Scripts/build-app.sh all` succeeded: `build/Gus.app` and `build/Gus Importer.app` (both from the
release products, whose CLibRaw response file is `-Os -O3`). Not launched.

**S7. Size and build time.** Executables, `develop` scratch vs branch: `photocli` 15,544,824 B to 15,680,616 B
(+0.9%); `photobench` 16,617,704 B to 16,750,776 B (+0.8%); both in line with the engineer's +0.7% to +1.1%. I did not
repeat the engineer's clean-build timing (87.9 s vs 89.4 s, within noise); LibRaw's 79 files are a small part of a
full build, and I have no reason to doubt it.

## For a person

Nothing. No UI changed, no launch was needed, and every behavior is compared by test, build inspection or bytes.
Optionally, the owner may want to know about the read-only touch of the library described at the top.

## Follow-up

Reruns after fixes: none yet. Sign-off: not yet given.
