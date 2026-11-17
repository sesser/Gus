# LibRaw at -O3: code review

Owner: code-reviewer. Date: 2026-11-16. Step 4 of `docs/WORKFLOW.md` (bug-fix route, issue #195).
Reviewed: `feature/libraw-o3`, 7218154..f53ed71 (one commit). Build and tests: `swift build`
(debug) up to date and clean; `swift test --filter 'LibRawDecoderTests|LibRawFallback|CameraColor|AcknowledgementConsistency'`
63 tests in 8 suites passed (debug); `RAF_SAMPLE=<X-E3 DSCF5162.RAF> swift test -c release --filter
'LibRawDecoderTests|LibRawFallback|CameraColor|GoldenTests'` 51 tests in 7 suites passed (release, LibRaw at -O3).
`RAW_BOTH_SAMPLES=… swift test -c release --filter LibRawAgainstSystemTests` fails with 8 issues, numbers equal to
the engineer's to the last digit (pre-existing; see Follow-up issues below).

## Verdict

Ready for qa-tester. The flag does what it says (release LibRaw compiles at -O3, debug stays -O0), nothing else
in the build moves, and the output is unchanged: by the engineer's probe on five files, by my own byte comparison
of two further LibRaw-only files through the whole pipeline, and by the compiler's floating-point rules. Two Nits
on `status.md`, neither blocking.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Nit | `docs/features/libraw-o3/status.md:136-143` | The Observations list misstates which `LibRawAgainstSystemTests` expectations fail. With the same four files I get the same printed numbers, but the 8 issues are: GX85 Kelvin (−12.8%); 5D Mark II Kelvin (−8.7% against 8%), ΔE 18.9 at 5500 K, −1.232 EV, tone spread −22.6%, ΔE 19.5 unedited; E-M5 III ΔE 10.6 unedited and 11.3 at 5500 K. The X-T3 file passes (ΔE 10.0 is under the Fujifilm limit of 20) and the GX85's ΔE 5.7 at 5500 K passes (limit 10). | The list names two failures that pass and leaves out two that fail; it is the source for the proposed follow-up issue's body. | Accurate records (`docs/WORKFLOW.md` Rules) |
| C2 | Nit | `docs/features/libraw-o3/status.md:146-153`; `docs/PROFILING.md:403-417`; `docs/features/_inventory.md:253` | The hand-off for Ship lists the README (`README.md:92`, "about 9 s") and `CLAUDE.md:716` ("about 9 s for an X-E3 file") but not the inventory line ("full decode about 9 s (X-E3)", product manager's file) nor `PROFILING.md:416`, whose "How to read it" says in the present tense that X-Trans files cost about 9 s at full size and Bayer files a little over 1 s. `PROFILING.md` is not a Ship file (its history is engineering's: #161, #170), so it can take a dated note on this branch; a `photobench rawcompare` run gives numbers comparable with its table (decode plus render), which `status.md`'s decode-only figures are not. | After Ship, the inventory still says 9 s and `PROFILING.md` says Bayer full decodes take over 1 s, where they now take 0.4 to 0.6 s (X-Trans about 8 s). | Docs kept with behavior |

## Questions

None for design or product.

## Checked and fine

- **The flag wins, release only.** Recompiled `ahd_demosaic.cpp` with `swift build -c release -v`: the clang line
  carries `-w` directly and the response file
  `.build/out/Intermediates.noindex/PhotoWorkspace.build/Release/CLibRaw-t.build/Objects-normal/arm64/82b82416…-common-args.resp`
  holds `-Os` and, last, `-O3`. `clang -### -Os -O3` gives cc1 exactly the arguments of `-O3` alone (`-O3`,
  `-vectorize-loops`, `-vectorize-slp`, `-extra-vectorizer-passes`, `-ffp-contract=on`). The debug response
  file holds `-O0` only, and `swift build` (debug) was a no-op after the change, so debug's arguments did not move.
  The 2x Bayer timing in `status.md` independently shows the probe's -O3 build really had -O3.
- **No fast math.** Neither response file nor the command line has `-ffast-math`, `-Ofast`, `-funsafe-math-optimizations`
  or an `-ffp-contract` override; clang gives `-ffp-contract=on` at `-O0`, `-Os` and `-O3` alike. With contraction
  decided per expression in the front end and no reassociation flags, LLVM keeps IEEE results at every level: more
  inlining cannot form new FMAs, and floating-point reductions are not vectorized out of order. What could still
  differ between levels is undefined behavior in LibRaw (uninitialized reads, out-of-bounds, signed overflow), which
  `-Os` already optimizes on the same assumptions; the probe's repeated in-process decodes would have shown
  uninitialized reads as differences.
- **Coverage of the proof.** The probe (`LibRawHashProbe.swift` in the engineer's scratchpad) hashes LibRaw's
  pixels, the whole color step, size, frame and lens flag, and the RGBAh render, full and half size, at -O0, -Os and
  -O3, on Panasonic, Canon (lossless JPEG), Olympus and two Fujifilm compressed X-Trans files, through the app's own
  `LibRawDecoder.decode` settings. That covers AHD, the X-Trans demosaic, highlight mode 1, user multipliers and
  half-size binning. Not covered: the no-color-data branch (LibRaw's own `convert_to_rgb` to Rec. 2020), SuperCCD,
  uncompressed RAF, Sony, Nikon, CR3. I added two LibRaw-only files the system decoder gives no image for
  (`CIRAWFilter`: no image): a FinePix F700 (uncompressed SuperCCD, LibRaw's rotated `fuji_width` path) and a second
  X-E3 lossless file (`DSCF5162.RAF`). `photocli render` to a 16-bit TIFF from the debug build (everything at -O0)
  and from the release build (LibRaw at -O3) gave byte-identical files for both (SHA-256 `a6be42b9…` and
  `1f2ed8db…`). Four damaged files (truncated RAF and CR2, header only, random bytes) fail the same way in both
  builds (`undecodable`). Together with the compiler argument above, enough.
- **Package consumption.** Nothing under `~/Projects` depends on this package; it is an app package, so SwiftPM's
  refusal of `unsafeFlags` in remote dependencies does not apply (the target already used `unsafeFlags(["-w"])`).
- **CI.** Both workflows build and test debug only, so CI neither exercises nor is affected by the release flag;
  release is built only by `Scripts/build-app.sh` (needs Xcode 26), which the engineer ran (`all`).
- **CLAUDE.md rules.** Diff is `Package.swift` and `status.md` only: vendored `Sources/CLibRaw` untouched (the
  upstream `#pragma GCC optimize` in `kodak_decoders.cpp` is behind `__GNUC__ > 4`, which clang does not meet, so it
  was never in play); no golden, tolerance or test changed; no `PreviewCacheKey.currentPipelineVersion` bump, which
  is right since output is unchanged (previews cached by `-Os` builds are what `-O3` makes); no new dependency.
  The LGPL comment ("built from source here, so it can be changed and the apps built again with it") stays true,
  and `THIRD_PARTY_NOTICES.md` states no build flags. "Single-threaded" claims stay true (no OpenMP).
- **Security.** No parser source, subprocess, file writing or network code changed; only the optimization level of
  an existing parser. Damaged inputs behave as before (above). `/security-review` is not needed.

## Follow-up

(Second pass: fill in after the engineer's fixes.)
