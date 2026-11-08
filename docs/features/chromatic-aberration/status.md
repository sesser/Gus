# Chromatic aberration and color fringe removal: implementation status

Owner: swift-macos-engineer. Implements [`prd.md`](prd.md) (Approved, owner
2026-11-07, rulings 1–15, R1a–R1c) against [`design.md`](design.md)
(Designed). Branch `feature/chromatic-aberration`, which carries the
stitchable-kernels spike (`1b537e0`).

**Status: In progress.**

States: Not started · In progress · Done · Blocked · Deferred.

## Build and test

- Baseline at `82c4df2` (2026-11-07): `swift build` clean; `swift test` 578
  tests in 100 suites passed, 1 known issue (the `withKnownIssue` in "Live
  render session", pre-existing).
- After the PhotoCore model and renderer: `swift test` 597 tests in 103
  suites passed, 1 known issue (the same). Every existing golden passes
  unchanged; `UPDATE_GOLDENS` never run; `PreviewCacheKey.currentPipelineVersion`
  unchanged.

## Progress

| Step | State |
|---|---|
| PhotoCore model: `ColorFringes`, `ColorAlignment`, section `lens`, groups, parameter descriptions, listed colors, hue names | Done |
| Renderer: run-time compiled kernels, lens step before the crop, fringe map, CPU references, scenes (a)–(c) | Done |
| Measuring color alignment | In progress |
| Paste, presets, batch, Lightroom import, `photocli`, `photobench` | Not started |
| App: Lens heading, slots, picking, fringe map, Color Alignment, debug script, strings, user guide | Not started |
