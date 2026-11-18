Issue: #86

# Spot healing and cloning: status

Owner: swift-macos-engineer. Branch `feature/healing`. Spec: the PRD (issue
#86 body, rev 2) and [`design.md`](design.md) (rulings R-1 to R-3, §20).

State: **In progress**

## Baseline

- 2026-11-18, `develop` at beb27a3 on this branch: `swift build` clean,
  `swift test` 1137 tests in 170 suites passed (about 70 s).

## Steps

| # | Step | State |
|---|---|---|
| 1 | Core: the `spots` operation, strict read, limit, `spots` group, paste and presets, renderer and kernels, CPU reference, automatic source, goldens | Done |
| 2 | Editor state and actions (`SpotEditing`), session source | In progress |
| 3 | Inspector: Spots heading | Not started |
| 4 | Loupe: overlay, clicks, drags, keys, context menu, caption badge | Not started |
| 5 | Menus (Adjust ▸ Spots), toolbar item, menu state | Not started |
| 6 | Debug script, strings, user guide | Not started |

## Algorithm (R15, AC13)

Written from published sources only; no code from another project was read
or used.

- **Clone**: the source circle copied over the spot at a whole-pixel offset
  (no resampling of the copied texture), faded over the feather by
  smoothstep from R · (1 − feather) to R, scaled by the opacity.
- **Heal**: the copy plus a harmonic membrane. Pérez, Gangnet and Blake,
  "Poisson Image Editing" (SIGGRAPH 2003): seamless cloning with the
  source's gradients as guidance equals the source plus the harmonic
  function whose boundary values are target − source. Farbman, Hoffer,
  Lipman, Cohen-Or and Lischinski, "Coordinates for Instant Image Cloning"
  (SIGGRAPH 2009): that correction can be interpolated from the boundary
  differences alone. On a disc the harmonic function with given boundary
  values is Poisson's integral (Evans, *Partial Differential Equations*,
  §2.2.4): u(p) = (R² − |p|²)/(2πR) ∮ g(b)/|p − b|² db. Discretized at 64
  equally spaced boundary points and normalized by its own weights (which
  makes constants exact), the factor (R² − |p|²) cancels, leaving weights
  1/|p − b|². Boundary differences are taken one pixel outside the circle,
  averaged over a 3 × 3 window so one noisy pixel does not tint the fill.
- **Order**: after the Lens heading's steps (alignment, fringes), before
  white balance, tone and the crop, in the mask frame; each spot reads what
  the spots before it left.
- **Automatic source** (R3, R16): candidates on rings 2.25, 2.75, 3.5, 4.5 and
  6 radii away, 16 directions each; allowed when inside the photo and clear
  of the spot and every other spot; inside the visible crop first; scored on
  perceptual luminance by the context match of the ring around the spot
  (1.15 to 1.55 radii) with the same ring around the candidate, structure
  plus a quarter of the tone difference (the exemplar match of Criminisi,
  Pérez and Toyama, "Region Filling and Object Removal by Exemplar-Based
  Image Inpainting", IEEE TIP 2004), plus how much busier the candidate's
  own circle is than the spot's surroundings, scaled by 1 + 0.1 per radius
  beyond the nearest ring. Pure arithmetic in a fixed order: deterministic.

## Decisions to confirm (design §15, PRD open questions)

- **No migration, no pipeline bump** (AC5): the stack is stored JSON; the new
  operation exists only on stacks that have spots, so no stored stack and no
  render hash changes. Every existing golden passes untouched (checked:
  `GoldenTests` before the three new goldens were created). Schema version:
  a stack with spots holds objects, so it is schema 2, which this build
  already reads; a build before this one reads the `spots` kind as unknown
  and keeps it (`Adjustments.preserved`), as it does masks of a newer kind.
- **Frame**: positions are in the mask frame (the oriented decode before
  turns, straightening and crop), the same as masks; a raw with spots decodes
  its whole sensor (`RAWDecodeSettings.fullFrame`) and crops to the camera's
  frame when it has no crop of its own. The heal runs after the Fujifilm
  embedded lens correction (inside LibRaw's decode) and after the Lens
  heading's alignment, so the stored position is on the corrected image, the
  one the loupe shows.
- **Cap**: 100 spots (`SpotLimits.spots`).
- **Size**: stored as the radius, a fraction of the long edge (Paint's unit),
  clamped to 0.0005 … 0.25 on read; the inspector offers 0.1 % … 10 %.

## Measurements

- CPU reference (float context): largest difference 6 × 10⁻⁸, 0.002 of the
  derived tolerance (3 × 10⁻⁵), four cases (heal, hard-edged heal, clone at
  80 % opacity, three overlapping spots one at the frame's corner).
- Half-float context: 0.25 to 0.64 of the derived bound 5 · 2⁻¹¹ of the
  largest value.
- AC2: the three specks of `dustySky`, sourced automatically, heal to within
  0.008 to 0.010 of the clean sky (perceptual; tolerance 0.025, derived from
  the scene's grain); before, 0.34 to 0.38.

## Crop to the kernel's extent

Core Image dropped `cropped(to:)` when the rectangle equalled the kernel
image's own extent, and the general kernel's output then covered the whole
frame when composited (every pixel of the photo changed). The spot kernel is
applied one pixel wider than it is kept, so the crop is real
(`SpotRenderer.apply`).

## Acceptance criteria

| AC | Check | State |
|---|---|---|
| AC1 | Manual + debug script (step 4) | Not started |
| AC2 | `SpotRenderingTests.automaticSourceHealsDust`, `movingTheSourceChangesTheResult` | Done (core) |
| AC3 | Debug script (step 4) | Not started |
| AC4 | `SpotRenderingTests.spotsStayOnContentUnderCrop`; golden `spots-healCropTurn-dustySky` | Done |
| AC5 | `SpotModelTests.noSpotsChangesNothing`; every existing golden unchanged; no pipeline bump | Done |
| AC6 | Editor tests / debug script (step 2) | Not started |
| AC7 | Same renderer for previews, export, `photocli render` (`AdjustmentRenderer.upstream`); debug script for the live drag | Not started |
| AC8 | `SpotRenderingTests.everyDecoderHeals` | Done |
| AC9 | `SpotModelTests.limit`; UI refusal (step 2) | Partly |
| AC10 | `SpotModelTests.pasteAndPresetsLeaveSpots`; Duplicate (step 2) | Partly |
| AC11 | Step 3 | Not started |
| AC12 | No sidecar path reads the `spots` kind (step 2 test) | Not started |
| AC13 | `SpotRenderingTests.matchesReference`, `halfFloatBound`; sources above | Done |
| AC14 | `SpotRenderingTests.sourceIsDeterministic`, `sessionSourceMatchesPlacement` | Done (core) |
| AC15 | `SpotRenderingTests.offRendersAsNone`, `SpotModelTests.groupTurnsSpotsOff` | Done (core) |

## Open questions

None yet.
