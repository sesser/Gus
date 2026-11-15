Issue: #71

# Local Sharpness with the Sharpening group off: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or `design.md`,
`docs/WORKFLOW.md` "Bug fixes") for GitHub issue #71, raised as RI-2 of
sharpen-mask-preview. Branch `bug/squash-top-10`, on top of `493b6a5`.

**Status: Done.** Next: code-reviewer, then the designer (the sharpening map's
badge and legend now read differently with the group off and a sharpening
mask), then qa-tester.

States: Not started · In progress · Done · Blocked · Deferred.

## Ruling

Owner, 2026-11-15, option B: local Sharpness turns off with the Sharpening
group. A mask's stored Sharpness is kept, not applied while the group is off,
and applies again when the group is turned back on. No change to stored
values, to `EditStack.renderHash`, and no migration. (An earlier reading, that
local Sharpness keeps the stored Radius, Detail and Masking with the group
off, was set aside before any code was written.)

## Bug

**Steps to reproduce** (at `493b6a5`).
1. Open a photo in the loupe. In Details ▸ Sharpening set Amount 120,
   Radius 2, Detail 80, Masking 60.
2. Add a mask and give it Sharpness 80.
3. Turn the Sharpening group's check box off.

**Expected** (the ruling). Nothing is sharpened: the masked area looks as it
does with the mask's Sharpness at 0. The sharpening map reads
**Sharpening Map · Not Applied**.

**Actual.** The masked area is still sharpened, with Radius 1, Detail 25 and
Masking 0 (the defaults), so it sharpens noise it did not sharpen while the
group was on. The map's legend says "Masks with Sharpness still sharpen the
areas they cover."

**Root cause.** `Adjustments.effective`, what every renderer path renders,
puts a turned-off group back to its defaults: `Sharpen()` for Sharpening. The
masks' Sharpness lives in `localAdjustments` and was untouched, so
`AdjustmentRenderer.applyMask` still produced a `MaskSharpening`, and
`downstream`'s loop sharpened each one with `adjustments.sharpen`, that is
the defaults (`AdjustmentRenderer.swift`, the local loop in `downstream`).

**Fix.** `Adjustments.effective` also sets every mask's Sharpness to 0 when
the Sharpening operation is turned off. The rule sits in that one place, so
every path that applies local Sharpness follows it without a check of its own:
`AdjustmentRenderer.render`, `sharpeningInput`, `LiveRenderSession.staged`
and `prepare`, the 100% region (through `render`), previews and exports, and
`SharpeningMapStatus` (`masksSharpen` reads `effective`). The stored stack is
not changed, so `renderHash` is not either: turning the group on and off
already changes the hash (the operation's `isEnabled`).

**Tests that fail without the fix**
(`Tests/PhotoCoreTests/LocalSharpenGroupOffTests.swift`, run at `493b6a5`
with only the test file added: 3 of 4 failed, 5 issues):
- `offRendersWithoutLocalSharpness`: with the group off, a mask's Sharpness 80
  renders byte for byte as Sharpness 0, with and without another local value;
  a mask whose only value is Sharpness leaves the photo exactly as it came in.
- `storedValuesAreKept`: the stored Sharpness stays 80 and survives a write
  and read; `effective` has 0 while the group is off and 80 once it is on
  again; turning another group off leaves local Sharpness alone.
- `liveFrames`: the live session's staged path gives the same bytes for
  Sharpness 80 with the group off as for Sharpness 0.
- `onSharpens` (passes before and after): the same mask with the group on does
  sharpen, so the checks above are not vacuous.
- `pipelineVersionBumped` (new with the bump): version 10, and a version 9
  preview is neither found nor kept.

No CPU reference: the expected render is the renderer's own render with
Sharpness 0, compared exactly, which is stricter than a reference with a
tolerance.

## Pipeline version: plain bump

`PreviewCacheKey.currentPipelineVersion` 9 → 10. A plain bump: a cache key
cannot say which stacks have a mask with Sharpness and the group off, so every
preview is made again on demand after the first launch. Previews of photos on
offline volumes cannot be made again until the volume is mounted.

The launch carry-over from #170 (`PreviewDiskCache.carryOver`, moving
version 8's previews written before 2026-11-13 under version 9) was
**removed**, not kept: with version 10 it would have carried version 8's
previews, old local sharpening included, into version 10. It had no other
caller. Removed with it: its private helper `moveEach`, the constants
`PreviewCacheKey.versionCarriedOver` and `libRawDecodingSince`, and its two
tests in `WhiteBalanceAcrossDecodersTests` (`cachedPreviewsAreRegenerated`,
`carryOverSurvivesAFailedRemoval`, #170's AC12). Removal is not risky:
`removeObsoletePipelineVersions` already deletes every other version's folder
at launch, which is what the app now does alone. #181's decision not to bump
is untouched.

## Goldens

None moved and none were touched; `GoldenTests` pass. No golden case turns a
group off; the one with local Sharpness (`mask-combined-hazyLandscape`) has
Sharpening on.

## Other changes

- `SharpeningMapTests.notAppliedRule`: AC11 case (c) of sharpen-mask-preview
  for the group off with a sharpening mask now expects **Not Applied** and no
  note (nothing is sharpened). The Amount 0 half of (c) is unchanged. See
  Requirements issues.
- `docs/USER_GUIDE.md`, Sharpening Map paragraph: masks sharpen with Amount at
  0, and turning Sharpening off turns their Sharpness off too (value kept).
- Comments: `Adjustments.effective`, `AdjustmentRenderer`'s header,
  `SharpeningMapStatus`.

No migration, no new string, no change to stored stacks or render hashes.

## Results

- Baseline at `493b6a5`: `swift build` clean; `swift test` 1027 tests in 151
  suites passed, 1 known issue.
- After the fix: `swift build` clean (no new warnings; the one in
  `VirtualCopiesTests.swift:170` is pre-existing); `swift test` 1030 tests in
  152 suites passed, 1 known issue (−2 carry-over tests, +5 new).
- No debug-script run: the change is in PhotoCore's rendering rule, covered
  above through the renderer and the live session.

## For a person

- P1. Steps to reproduce above in the bundle: with the group off the masked
  area is not sharpened; turning it on brings the mask's Sharpness back.
- P2. Sharpening Map with the group off and a sharpening mask: the badge reads
  **Sharpening Map · Not Applied** and the legend has no sentence about masks.
- P3. After the first launch every thumbnail is made again (expected, one time).

## Design questions

- DQ-1. With the Sharpening group off, a mask's Sharpness slider still moves
  and changes nothing, and editing it does not turn the group on (only a
  group's own controls do, `enableModules`). Options: (a) leave it, the user
  guide says so (cost: none); (b) dim the mask's Sharpness while the group is
  off with a caption such as the Adjust tab's "not applied" ones (cost: a
  string, a dimmed state in the mask inspector, a test); (c) editing a mask's
  Sharpness turns Sharpening back on (cost: a special case in
  `enableModules`, one more thing that changes from a mask edit).
  Recommendation: (b), so the screen doesn't contradict the photo.
  Not built; nothing in the UI was changed.

## Requirements issues

- RI-1. sharpen-mask-preview's AC11 case (c) and its R10 wording treat "group
  off with a mask that sharpens" as applied, with the note "Masks with
  Sharpness still sharpen the areas they cover." Under the #71 ruling that
  case is now "Not Applied" with no note. The product manager should record
  this in that PRD (and the designer in its `design.md` §7 if wanted); the
  legend string itself is unchanged and still serves the Amount 0 case.

## README

No change to requirements, build commands or layout. For the product manager
at Ship: `CLAUDE.md`'s "Scope so far" entry for white balance across decoders
says "`PreviewCacheKey.currentPipelineVersion` is 9, with version 8's previews
… carried over at launch (`PreviewDiskCache.carryOver`)". The version is now
10 and the carry-over is gone.
