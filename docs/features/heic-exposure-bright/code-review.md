# Some HEICs render brighter than Quick Look (#277): code review

Owner: code-reviewer. Date: 2026-11-24. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/heic-exposure-bright`, 139b39e..23856fa (two commits, both
signed). Build and tests: `swift build` clean; full `swift test` 1533 tests in
216 suites pass (87 s); the CI toolchain build (`DEVELOPER_DIR=…Xcode_26.3…
swift build --build-tests --scratch-path .build-xcode26.3`) up to date and
clean; the opt-in `HEIC_GAINMAP_SAMPLE` test on the owner's file passes and
prints the figures `status.md` records (SDR mean 0.273, −0.01 stops from
ImageIO's SDR decode; Exposure −1 0.137; Contrast +20 0.292).

## Verdict

Ready for QA. The fix is the one the owner ruled (RI-1, option C): a two-line
change of what `decodeHDR` counts as HDR content, with the HLG and PQ path
unchanged, and the tests the Bug section names fail without it (checked here).
No Blocker or Should fix; three Nits, one risk question about CI, and a
correction to the proposed `CLAUDE.md` wording.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Nit | `Tests/PhotoCoreTests/GainMapRenditionTests.swift:104-115`, `Sources/PhotoFixtures/HDRTestImages.swift:41-51` | "An HLG or PQ HEIC keeps its HDR rendition, with or without a gain map" never checks that the `gainMap: true` files have one. The fixture's own comment says Core Image "writes one only when the encoder supports it". | A probe here showed Core Image writes no gain map at all for a flat 200 × 150 picture in a PQ or HLG HEIC (it does for the 800 × 600 synthetic picture). On an encoder that doesn't, the two `gainMap: true` cases silently test a plain PQ/HLG file and still pass, so "with a gain map" is unproven there. Add `#expect(Self.hasGainMap(url) == gainMap)`. | Tests check the behavior they name |
| C2 | Nit | `Tests/PhotoCoreTests/GainMapRenditionTests.swift:119-136` | The opt-in real-file test asserts only that there is no HDR rendition; the SDR-equals-system check (within 0.05 stops) that the synthetic test makes is printed, not asserted. | A future change that moved the real file's SDR render (the owner's actual complaint: brighter than the system) would still pass the opt-in run; the reader has to read the printed figure. Assert `abs(sdr.stops(over: system)) < 0.05` for the identity stack. | Tests |
| C3 | Nit | `Tests/PhotoCoreTests/StalePreviewTests.swift:93-122` | The stale-hash test's HDR rendition at Exposure −2 sits just above `RenderEngine.minimumHDRHeadroom` (1.05), and `#require` needs it to exist. | Measured here (scratch probe on this branch): the PQ HEIC's rendition at −2 EV has headroom 1.064 at 512 px and 1.082 at full size, 1.4 % to 3 % over the threshold. One 10-bit PQ code value near 4× SDR white is of that order, and HEVC is lossy, so a runner whose encoder rounds the patch one code lower can give nil and fail the `#require`. Not a regression: the gain-map JPEG it replaced was thinner still (1.052 at full size, nil at 512 px, measured on the unfixed code). An edit of −1 EV (headroom 2.13) would keep the test's point with room. | Determinism of tests |

## Questions

- **Q1 (for the main session, about CI).** This branch is the first time the
  test suite writes HEIC files (`heifRepresentation`, `heif10Representation`
  in `HDRTestImages`, `PreviewTests.hdrRenditionsKeepHighlightsAboveWhite` and
  `StalePreviewTests`); before it, every HDR fixture was a gain-map JPEG. HEIC
  writing goes through the HEVC encoder, and the CI runners are virtual Macs
  (their paravirtual GPU already fails large renders, `docs/features/full-render-main-thread-stall/status.md`).
  I could not establish here whether their ImageIO can encode HEIC. If it
  can't, `writeGainMap(container: .heic)`, `writeHDREncoded` and the two
  edited existing tests throw on CI, and the pull request's run is the first
  place that shows it. Nothing to change before then; if CI fails there, the
  fix is a skip with the reason (as `LargeRenderTests` is gated) or a
  check of `CGImageDestinationCopyTypeIdentifiers()`, not a weaker assertion.
- **Q2 (for the owner, through RI-2).** The issue's title covers "some HEICs";
  this branch fixes gain-map files only, as ruled. HLG HEICs still jump on
  every slider release (about 1.5 stops by the engineer's synthetic
  measurement), and their fitted render disagrees with their 100% render by
  1.6 stops whatever the HDR ruling. If the pull request says `Closes #277`,
  RI-2 needs its own issue first, or that half is lost with the closed issue.
- **Q3 (for the owner, `CLAUDE.md`).** The proposed Rendering rule wording is
  accurate on what counts as HDR content: floating-point DNGs and HLG or PQ
  encoded images, and an HLG/PQ file that also carries a gain map still gets
  its gain map applied (the decode keeps `.expandToHDR`), which "a gain map
  alone" correctly allows. One phrase is not accurate: "everything that edits
  or exports is SDR". The HDR rendition itself applies the edit stack (an HLG,
  PQ or floating-point DNG photo shows its edits in HDR in the loupe once a
  slider is let go); what is SDR is the live frames, the cached previews and
  exports. Suggested: "…its HDR rendition is a different, often brighter
  picture, and live frames, previews and exports are its SDR rendition, so
  gain-map photos show their SDR rendition (HDR editing of them is #282)."
  `docs/features/_inventory.md:154` (the product manager's) still lists gain
  maps as HDR sources, for Ship or the next reconcile.

## Checked and fine

- `PreviewGenerator.decodeHDR`: the raw branch is untouched; for non-raws the
  only change is the gain-map test gone from the guard. `hasHDREncoding` is
  the old `isHLGOrPQ` expression unchanged (header read only), and the decode
  keeps `.expandToHDR` and orientation, so HLG and PQ files, with or without a
  gain map, render byte for byte as before. The guard order still returns nil
  for videos and empty sources before any decode.
- Every caller follows from that one function: `PreviewService.hdrImage`
  (memory-only `#hdr` keys and the `standardRange` set, per process), the
  loupe (`LoupeView`) and comparison panes (`ComparisonView`), and the HDR
  badge, which is driven by the shown image's headroom only
  (`kind.isHDR`, `comparisonHDRHeadroom`). Nothing else in `Sources` tests for
  gain maps or decodes with `.expandToHDR`.
- No `PreviewCacheKey.currentPipelineVersion` bump needed: previews, the 100%
  render, live frames and exports never went through `decodeHDR` and are
  unchanged; HDR renditions were never written to disk. No golden moved, no
  tolerance loosened. Existing tests changed in the fix commit
  (`PreviewTests`, `StalePreviewTests`) change their fixture to keep testing
  the HDR path, and the gain-map JPEG case now asserts the ruled behavior;
  that is a ruled behavior change, not a test bent to pass.
- "Fails without the fix": in a scratch worktree with `develop`'s
  `decodeHDR` (plus the `hasHDREncoding` helper the test calls), the three
  suites failed with 8 issues: 7 in `GainMapRenditionTests` (HEIC and JPEG,
  fit and full size; Exposure −0.5 and +1 and identity in the release test;
  Contrast passed, as the status says) and the gain-map line of
  `PreviewTests`. With the fix all pass. This matches `status.md`.
- Determinism: I accept the engineer's structural argument for
  `GainMapRenditionTests` (each test writes its own file in its own temporary
  folder, no shared mutable state, no timing; assertions compare nil against
  a rendition or levels a stop apart against a 0.05-stop margin). One run of
  the full suite, one more of the three affected suites and one more of
  `GainMapRenditionTests` here, all clean (runs that prove no rate; the
  argument carries it); the one thin
  margin I found is C3, in an edited existing test.
- `HDRTestImages`: test-only fixture in `PhotoFixtures`, a shared static
  `CIContext` (thread-safe; builds under Swift 6 with both toolchains), linear
  scaling done in the extended linear working space as the comment says.
- Swift 6 concurrency: no isolation, task or actor change; the decode stays
  on the render lanes off the main actor.
- `docs/USER_GUIDE.md`: the HDR paragraph matches the code (floating-point
  DNGs and the app's own DNG merges; HLG/PQ images; gain-map-only photos and
  camera raws SDR).
- Project rules: no originals written, no catalog, migration, sidecar, pair,
  undo, UI string, branding or dependency change. No parser, subprocess,
  network or file writing outside the library added, so `/security-review` is
  not needed.

## Follow-up

(Second pass: each finding Fixed, Not fixed (and why) or Withdrawn, with the
commit.)
