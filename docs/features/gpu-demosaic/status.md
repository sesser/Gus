Issue: #196

# GPU demosaic for raws LibRaw decodes: implementation status

Feature, branch `feature/gpu-demosaic`, cut from `develop` at `34738c2`. The
PRD is the issue body (`gh issue view 196`), approved by the owner on
2026-11-16 with every open question at its default (Q1 a directional X-Trans
kernel written from published papers; Q2 Bayer in this issue; Q3 the speed
targets as written; Q4 a fixed baseline color noise reduction step with no
control; Q5 a fallback logged, not shown in the app; Q6 a hidden debug switch
keeps LibRaw's demosaic selectable; Q7 the owner's RAFs through environment
variables, never committed). There is no `design.md`: the PRD has no UI
change.

**Status: In progress.**

## Build and tests

Machine: Apple M4 Pro (14 cores), 24 GB, macOS 27.2.1, Xcode 26 toolchain
(MacOSX 27.2 SDK).

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline, `develop` at `34738c2` (2026-11-16) | green, no warnings | 1047 tests in 156 suites passed (one unnamed failure in the first of three runs, not reproduced in the next two: flaky, not this feature's) |

## The PRD's thresholds and targets against the #194 spike (checked first)

Checked before any design decision, against `spike.md` and `status.md` of
`origin/feature/decode-pipeline-spike`.

- **R14 (X-Trans full size at most 1.0 s): confirmed.** The spike's hybrid took
  582 and 609 ms with a bilinear kernel, 525 to 550 ms of it LibRaw's unpack.
  A directional kernel and the noise step add GPU work in tens of
  milliseconds, not hundreds.
- **R15 (Bayer no slower than LibRaw at -O3; Should 0.4 s): confirmed.** The
  spike's Hamilton–Adams path took 92, 294 and 304 ms.
- **R16 (half size no slower than today, about 0.6 s): confirmed.** Unpack-bound;
  the spike's bins took 540 and 566 ms against LibRaw's 605 and 645.
- **R17 (GPU under 100 ms, Should): confirmed as plausible, unmeasured.** The
  spike measured 12 to 17 ms for normalize plus a simple demosaic.
- **R18 (white balance frame no slower): confirmed.** The kept decode and the
  color step are not changed by this feature.
- **R21 (peak at most 400 MB above baseline at 24 MP): confirmed with a
  design condition.** The PRD's sum (194 MB output, 97 MB normalized
  mosaic, 49 MB sensor data) is 340 MB. A noise reduction step that reads
  the demosaiced image and writes a second full-size image would add
  194 MB (534 MB). The design below avoids both the normalized mosaic
  (kernels normalize as they read) and a second full-size image (the noise
  step runs in bands through a small scratch texture), so the bound holds.
  To be measured.
- **AC3 (X-Trans quality against LibRaw's three passes): kept as written;
  unmeasured by the spike** (no directional kernel, no X-Trans truth). Note
  for the record: the X-T3 sample is ISO 6400 (`exiftool`), so its false
  color figure (LibRaw 8.14 against the X-E3's 4.09 at ISO 400) measures
  chroma noise at edges as much as demosaic error.
- **AC4 (edge ΔE76 median at most 5 against LibRaw): kept; flagged as at
  risk on the X-T3.** Per pixel ΔE against LibRaw's own output includes
  LibRaw's chroma noise at ISO 6400, which the noise step removes from ours;
  the spike's bilinear was 8.2 there. Measured with the noise step on and
  off below.
- **AC5, AC6, AC7: kept as written**; measured below.

No requirement needs to change at this point.

## Samples (never committed)

`XTRANS_SAMPLES` (a `:`-separated list of files, or a folder) for the real-file
checks; `BAYER_SAMPLES` likewise for the Bayer files. Unset, those tests are
skipped and say why.

| Class | Decoder (`SystemRAWDecoder.reads`) | Used for |
|---|---|---|
| Fujifilm X-E3, lossless compressed | to be checked | AC3, AC4, AC6, AC9 |
| Fujifilm X-T3 | to be checked | cross-check (AC5) |
| Fujifilm X100S (X-Trans II) | to be checked | another 6x6 layout |
| GX85 RW2, 5D II CR2, E-M5 III ORF | system | Bayer path through the debug switch |

## Requirements and acceptance criteria

| Item | State | Test or check |
|---|---|---|
| R1–R23, AC1–AC16 | Not started | |

## Debug switch (Q6)

To be written.

## Published sources

To be written.

## README

To be written.

## Open questions

None yet.
