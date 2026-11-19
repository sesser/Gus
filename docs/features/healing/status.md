Issue: #86

# Spot healing and cloning: status

Owner: swift-macos-engineer. Branch `feature/healing`. Spec: the PRD (issue
#86 body, rev 2) and [`design.md`](design.md) (rulings R-1 to R-3, §20).

State: **Done** (2026-11-18). Every criterion is built and tested or has a scripted check; the checks only a person can make are listed under "For a person".

## Baseline

- 2026-11-18, `develop` at beb27a3 on this branch: `swift build` clean,
  `swift test` 1137 tests in 170 suites passed (about 70 s).

## Steps

| # | Step | State |
|---|---|---|
| 1 | Core: the `spots` operation, strict read, limit, `spots` group, paste and presets, renderer and kernels, CPU reference, automatic source, goldens | Done (34e9a40) |
| 2 | Editor state and actions (`SpotEditing`), the session's automatic source | Done |
| 3 | Inspector: Spots heading (`SpotsSection`) | Done |
| 4 | Loupe: overlay (`SpotOverlayView`), clicks, drags, keys, context menu, Spot Limit badge, canvas value | Done |
| 5 | Menus (Adjust ▸ Spots), palette toolbar item, menu state, Remove from Album dimmed with a spot selected | Done |
| 6 | Debug script (`DebugSpotCommands`), strings, user guide, `photobench scenes` dusty sky | Done |

## Latest results

- `swift build`: clean; no new warnings in the files this branch touches
  (recompiled on purpose to check).
- `swift test`: 1162 tests in 173 suites passed after the second pass; 25 of them new.
- `Scripts/build-app.sh`: built; scripted runs below on a copy with the
  identifier `me.sesser.gus.debugtest` and a scratch library from
  `photobench import` of `photobench scenes --size 3000x2000` (the dusty sky
  as DNG, JPEG pair and TIFF), always with `--library-root`.

## Files

- PhotoCore: `Edits/Spots/Spots.swift` (operation, strict read, `SpotLimits`),
  `SpotGeometry.swift` (source rules), `SpotRenderer.swift` (renderer and
  kernels), `SpotSourceFinder.swift` (automatic source, `LuminanceWindow`);
  `Adjustments` (`spots`, `Group.spots`, `Group.presetGroups`,
  `Section.spots`), `AdjustmentPresets` (paste and presets leave spots and
  their on/off), `AdjustmentRenderer` (`spotStep`, whole sensor for spots),
  `EditStack.decode` (validation), `LiveRenderSession.spotSource`.
- PhotoApp: `Model/SpotEditing.swift`, `SpotActions.swift`,
  `DebugSpotCommands.swift`; `Loupe/SpotOverlayView.swift`;
  `Views/SpotsSection.swift`; edits in `AdjustmentEditor`, `LoupeView`,
  `LibraryCommands`, `LibraryMenuContext`, `LibraryToolbar`,
  `PhotoContextMenu`, `AdjustView`, `AdjustControls` (`SectionHeader`'s
  reset title, `AdjustText`), `CurveEditor` (`AppKitSegmented` tooltips and
  label), `ReviewActions`, `ComparisonActions`, `PresetActions`,
  `PresetManagerSheet`, `DebugScript`.
- Fixtures and tools: `TestScene.dustySky`, `photobench scenes` writes it.
- Tests: `SpotTests.swift` (model, rendering, catalog), `Reference/SpotReference.swift`,
  goldens `spots-heal-dustySky`, `spots-clone-dustySky`,
  `spots-healCropTurn-dustySky`; `AdjustmentsTests` and `CommandTests` adjusted
  for the new group (spots are objects, not a module of parameters).

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

## Acceptance criteria

| AC | Check | State |
|---|---|---|
| AC1 | Script S1/S2: `spots on` then `spot add` (the click's path, `LoupeController.addSpot` → `AdjustmentEditor.addSpot`) adds a spot of the set size and mode; `snapshot` shows the healed specks (`c-healed.png`). A real click: P1 | Done |
| AC2 | `SpotRenderingTests.automaticSourceHealsDust` (all three specks within 0.008–0.010 of the clean sky, tolerance 0.025; sources inside, clear of their own and other spots), `movingTheSourceChangesTheResult` | Done |
| AC3 | Script S2: select, `spot drag spot|size|source`, `spot mode`, `spot delete`, `spots overlay off|on`, `key v`; positions printed by `spots print` | Done |
| AC4 | `SpotRenderingTests.spotsStayOnContentUnderCrop`; golden `spots-healCropTurn-dustySky` | Done |
| AC5 | `SpotModelTests.noSpotsChangesNothing`; every existing golden passes untouched; `PreviewCacheKey.currentPipelineVersion` not bumped (confirmed: no stored stack or render hash changes); no migration | Done |
| AC6 | Script S2/S3: History lists Add Spot, Move Spot, Resize Spot, Move Spot Source, Choose Spot Source, Spot Feather, Spot Opacity, Turn Off / On Spots, Delete Spot, Delete All Spots, one entry each; undo and redo restore the spots | Done |
| AC7 | One renderer (`AdjustmentRenderer.upstream`) for previews, export, `photocli render` and live frames; `photocli render --version 5` shows the same heals as the loupe; S4 frame trace at 100%: a drag gives sharp region frames (5–7 ms with three spots) | Done |
| AC8 | `SpotRenderingTests.everyDecoderHeals` (system-decoded DNG, LibRaw decode of the same DNG, JPEG; one stored shape) | Done |
| AC9 | `SpotModelTests.limit` (101 unreadable, `exceedsLimits`, never written over by the existing rule); script S3: `spot fill 99` + one click = 100, the next click refused (notice, caption, beep; badge shown while editing) | Done |
| AC10 | `SpotModelTests.pasteAndPresetsLeaveSpots` (paste and presets keep the target's spots and on/off, carry none), `SpotCatalogTests.duplicateCopiesSpots`, `spotsArePerFileAndNeverSidecars` | Done |
| AC11 | Script S3: while comparing `canEditSpots` is false, `H` does nothing; the Adjust tab's existing Not Available While Comparing state; spots render in the panes | Done |
| AC12 | `SpotCatalogTests.spotsArePerFileAndNeverSidecars` (no sidecar row queued) | Done |
| AC13 | `SpotRenderingTests.matchesReference` (float: 6 × 10⁻⁸, 0.002 of the derived tolerance), `halfFloatBound` (0.25–0.64 of the derived bound); sources above | Done |
| AC14 | `SpotRenderingTests.sourceIsDeterministic`, `sessionSourceMatchesPlacement` (the editor's session: re-sourcing after the spot's source moved and the check box went off gives placement's answer); one undo step "Choose Spot Source" (S2); menu item off with no spot selected (`menuitems`) | Done |
| AC15 | `SpotRenderingTests.offRendersAsNone` (byte for byte), `SpotModelTests.groupTurnsSpotsOff`; script: Turn Off / Turn On Spots in History; paste/presets keep on/off (AC10 test) | Done |

## Scripted checks

`$S` is `/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa`.

- S1 `focus 0; loupe; spots on; spot add …; history; undo; redo; spot enable off|on; spot clear; undo` on a JPEG.
- S2 `focus 4` (the dusty-sky DNG): three spots, `spots overlay off`, snapshots; select, mode, drags, `spot source auto`, nudges, feather, opacity, check box, delete, History, undo.
- S3 `focus 5` (TIFF): `key h`, `key opt+left`, `key opt+cmd+up`, `key escape` twice (deselect, then tool off), `spot fill 99`, the refused click, `key delete`, `key v`, `compare` then `key h`.
- S4 at 100% (`zoom`): `print frames` around drags with 3 spots, with 93 spots, and a brush mask's scrub for comparison.

## Measurements

- CPU reference (float context): largest difference 6 × 10⁻⁸, 0.002 of the
  derived tolerance (3 × 10⁻⁵), four cases (heal, hard-edged heal, clone at
  80 % opacity, three overlapping spots one at the frame's corner).
- Half-float context: 0.25 to 0.64 of the derived bound 5 · 2⁻¹¹ of the
  largest value.
- AC2: the three specks of `dustySky`, sourced automatically, heal to within
  0.008 to 0.010 of the clean sky (perceptual; tolerance 0.025, derived from
  the scene's grain); before, 0.34 to 0.38.
- Live drag at 100% (S4, 1760 × 1369 region of a 3000 × 2000 TIFF): 3 spots
  5.9–7.3 ms per sharp frame; a brush mask's scrub 2.7–7.7 ms. 93 spots:
  44–56 ms per sharp frame, and 210–290 ms for the whole-photo frame after a
  pause. At fit, 99 spots: 130–166 ms per frame (drafts drop the size).
- Render cost alone (2560 × 1707, empty image): 1 spot 3 ms, 25 spots 23 ms,
  100 spots 102 ms; at 256 × 192, 100 spots 26 ms. About a quarter of the
  cost is the two kernel passes each spot needs, the rest the chain of
  composites every pixel goes through.

## Crop to the kernel's extent

Core Image dropped `cropped(to:)` when the rectangle equalled the kernel
image's own extent, and the general kernel's output then covered the whole
frame when composited (every pixel of the photo changed). The spot kernel is
applied one pixel wider than it is kept, so the crop is real
(`SpotRenderer.apply`).

## Decisions made within the design

- **Default size** 0.3 % of the long edge (an 18-pixel radius at 24 MP);
  Size 0.1 % … 10 %, one decimal (design §3 asked the engineer).
- **No source** (design §5.4, §15): when no candidate on the five rings lies
  inside the photo clear of the spot and every other spot. In practice a
  spot larger than about a fifth of the short edge, or one hemmed in by other
  spots. A render failure is reported the same way (and logged).
- **Held option-arrow** is one undo step: committed on the arrow's key up, or
  1.5 s after the last nudge when the key up goes elsewhere.
- **Analysis image** for the automatic source: the session's full-size (fit,
  2560 px) decode after the Lens steps, without spots; other spots are
  avoided by geometry. So placement and Choose Source Automatically ask the
  same question of the same image (AC14).
- **Spots turned off** keep a stack of schema 2, so its render hash differs
  from the same stack without spots (as masks turned off do); the pixels are
  the same byte for byte (AC15). Changing that would change existing hashes.

## For a person

- P1 Real mouse: click adds with the crosshair and size ring; drag inside a
  ring moves it; the handle resizes; the source ring drags and stops at its
  spot and at the edge; a drag on empty photo pans; a double-click adds one
  spot and stays in the loupe; right-click on a spot selects it and shows
  Heal, Clone, Choose Source Automatically, Delete Spot first.
- P2 Menus with the window key: Adjust ▸ Spots enablement in the loupe, grid,
  review, crop and comparing; Remove from Album dimmed while a spot is
  selected and ⌫ deleting the spot; ⌥-arrows and ⌥⌘-arrows.
- P3 Overlay legibility on a white sky and a dark foreground; Increase
  Contrast (heavier strokes, darker hairline); the arrowhead and cross.
- P4 The Spots heading's layout and captions in light and dark; the
  palette toolbar item.
- P5 A 24 MP raw: a dust spot at the default size; a drag at 100%.

## Known limitations

- **Many spots are slow** (Measurements): near the cap a drag at 100% is
  several times slower than a brush mask. Follow-up #211.
- If the spot kernels can't compile, spots are skipped with no message, as
  the Lens heading's corrections are (RI-CR1's rule).
- Touch: the handles' grab distance is 10 pt for every event, as ruled
  (design.md §20, DQ-2).

## README

- `photobench scenes` also writes the spots' dusty sky (TIFF, JPEG, DNG).
- Layout: `Sources/PhotoCore/Edits/Spots/` (for `CLAUDE.md`'s Layout,
  proposed to the owner).

## Rulings

- DQ-1 (design.md §20): Show / Hide Spot Overlay stays in Adjust ▸ Spots
  (bare `V`), as built.
- DQ-2 (design.md §20): one 10 pt grab distance for every event, as built.

## Review findings (2026-11-18)

Code review (`code-review.md`) and design review (`review.md`), all fixed in
one commit after 1a6c8dd.

| # | Fix |
|---|---|
| C1 | A nudge chosen from Adjust ▸ Spots ▸ Move Spot / Move Source with the mouse (no key down) is saved at once, as its own step; only a held ⌥-arrow in the loupe waits, for its key up. As a safety net, `change(_:phase:_:)` saves a waiting run first, under its own name, before any other action or save (`SpotNudgeRule` in PhotoCore, tested by `SpotModelTests.nudgeRunIsItsOwnStep`); an undo, redo or another writer's save drops a waiting run. Script S5 (`spot nudge right hold`, then `spot mode clone`; again, then `spot delete`): History lists Move Spot, Change Spot Mode, Move Spot, Delete Spot, the deletion under its own name. Limit: when the safety net acts (a key still held while another control is clicked), the two History entries share one ⌘Z, since AppKit groups the registrations of one event. |
| C2 | The placement and Choose Source tasks clear their handle only when not cancelled, so a cancelled task never clears the next photo's. |
| C3 | The debug script saves a waiting nudge before it closes a command's undo group. |
| C4 | `SpotLimits.spots`'s comment cites the measurements (102 ms at 2560 × 1707) and #211. |
| C5 | One "Measurements" and one "Crop to the kernel's extent" section. |
| F1 | Confirmed: before the fix `accessibility any` with the tool on listed the canvas (`AXImage 'dusty-sky, RAW plus JPEG' value 'Editing spots, 3 spots, 5 of 6'`) and no spot. The canvas (`LoupeHostView.accessibilityChildren`) now returns the overlay's spot elements while Edit Spots is on and the overlay shown, with the canvas as their parent. The probe (`AccessibilityProbe`) now also visits the children of AppKit element views, which the window walk does not reach without an assistive app. Run S6 below. |
| F2 | The eye moved from the heading to the context row, beside the trash and ⋯; the heading has one trailing control, so its check box keeps the column. |
| F3 | A dragged or nudged spot's center is held inside the crop (`AdjustmentEditor.heldInCrop`), so a selected spot never leaves the view. |
| F4 | The pointer is set from `mouseMoved`: the arrow over a ring or a handle (`target(at:)`), the crosshair elsewhere; the square cursor rectangles are gone. |
| F5 | A click that adds a spot, and a click on a spot or handle, post `.browserShouldTakeFocus` with the window, so the loupe takes the keyboard back from an inspector field. M6 checks it with a real click. |
| F6 | The user guide names Finish Editing Spots and Adjust ▸ Spots ▸ Hide Spot Overlay. |

**S6 (F1)**, on the dusty-sky DNG with three spots: `spots on; accessibility
AXButton 3 press; accessibility AXButton 4 Switch to Clone; accessibility
AXButton 5 Delete Spot; history`:

```
debug-script: accessibility press on 3: done
spot 1 selected: heal at 0.3125,0.3516 …
debug-script: accessibility Switch to Clone on 4: done
debug-script: accessibility Delete Spot on 5: done
debug-script:   3 AXButton 'Spot 1, Heal, left' actions [Select, Switch to Clone, Move Spot Left, Move Spot Right, …, Choose Source Automatically, Delete Spot]
debug-script:   4 AXButton 'Spot 2, Clone, center' actions [Select, Switch to Heal, …]
debug-script: history row 0 Delete Spot
debug-script: history row 1 Change Spot Mode
```

With `spots overlay off` no spot buttons are listed. The probe lists each spot
twice (indexes 3–4 and 5–6 after the delete): it reaches the canvas by two of
its own paths; the canvas returns each spot once (checked with a temporary
log of its children). **A VoiceOver press on empty canvas** does nothing: the
canvas is an image element with no press action, so no spot is added (the
accepted limit R-3); its custom actions are the loupe's as before.

## Second pass (2026-11-18)

| # | Fix |
|---|---|
| R2-1 | Confirmed by a test, and worse than a float rounding: a stored point is rounded to 10⁻⁶ (`MaskPoint`), so with the old clamp 20 of 32 far drags (four crops with turns and Straighten, eight targets past edges and corners) came back outside the crop. `SpotCrop` in PhotoCore now holds the point (`held`: clamp in the output, map back, and if the stored point still maps outside, clamp again 10⁻⁶, 10⁻⁵, … inside) and tests visibility with a 10⁻⁹ tolerance (`contains`); the editor's `heldInCrop`, `isVisible` and `selectedSourceIsOutsideCrop` use them. Test: `SpotModelTests.heldInCropStaysVisible` (all 32 held on the edge they were pushed to, within 2 × 10⁻³, and counted visible). Script S7 below. |
| R2-2 | The user guide's first Spots sentences put the crosshair with turning the tool on, then Finish Editing Spots. |
| C6 | `pickFringe`'s doc comment is back above `pickFringe`. |

**S7 (R2-1)**, the dusty-sky DNG cropped with 4° of Straighten (`adjust crop
begin; adjust crop angle 4; adjust crop rect 0.15 0.15 0.7 0.7; adjust crop
done`), spot 2 dragged far past each edge (`spot drag spot 3 0.5`, `-3 0.5`,
`0.5 -3`, `0.5 3`), `spots print` after each, then `accessibility AXButton`:

```
spots: … count 3, visible 2 …
spot 2 selected: heal at 0.8491,0.4634 … shown 1.0000,0.5000 …
spot 2 selected: heal at 0.1509,0.5366 … shown 0.0000,0.5000 …
spot 2 selected: heal at 0.4837,0.1509 … shown 0.5000,0.0000 …
spot 2 selected: heal at 0.5163,0.8491 … shown 0.5000,1.0000 …
debug-script:   4 AXButton 'Spot 2, Heal, bottom' value 'Selected' actions [Select, Switch to Clone, …]
```

Each time the spot stays selected, counted visible (spot 3 lies outside the
crop) and listed as a VoiceOver button.

**Flakiness** (code-reviewer saw one unnamed failure in 1 of 4 full runs):
four full `swift test` runs in a row after these fixes, 1162 tests each, all
passed. No spot test failed in any run; the spot suites use fixed scenes and
seeds, render through their own contexts and have no sleeps or timing
thresholds. The reviewer's failure is not reproduced here.

## Open questions

None.
