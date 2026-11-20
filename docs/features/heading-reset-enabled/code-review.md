# Adjust headings' reset arrows enabled with nothing to reset: code review

Owner: code-reviewer. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix, issue #221).
Reviewed: `bug/heading-reset-enabled`, d62cd4d..60ec046. Build and tests: `swift build` clean;
full `swift test` 1246 tests in 177 suites passed (71.4 s; `DeferredRenderTests`, #229, did not flake).

## Verdict

Ready for QA. The fix is one modifier on the one view behind seven headings, the same workaround
Crop (287524f), Spots and Black & White already carry; the model rule is unchanged and now pinned
by tests, and the new source check fails on `develop`'s code. No Blocker or Should fix; two Nits on
the source check, both acceptable as they stand.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Nit | `Tests/PhotoCoreTests/HeadingResetTests.swift:113-117` | The source check accepts any `.disabled(` within the 8 lines after the button's first line. It doesn't tie the modifier to the button or its argument to `isEnabled`. | A reset written `isEnabled: canReset` with `.disabled(canReset)` (inverted) passes. So would a reset with no `.disabled` followed within 8 lines by another control's `.disabled(`. In the other direction, `AdjustSection`'s `.disabled` is already the 7th of the 8 lines (three comment lines in between), so two more comment lines would make the test fail with the code still right. The debug-script checks A1 to B5 cover the behavior, so this only matters as a guard. | Tests |
| C2 | Nit | `Tests/PhotoCoreTests/HeadingResetTests.swift:123` | `found.count == 4` is a tripwire, and a deliberate one. It also catches the check going blind: if a reformat moves `symbol:` onto its own line, the button isn't found, the count drops and the test fails. The cost is that adding a fifth heading reset fails until the count is updated, but the message names every location found. It scans only `Sources/PhotoApp/Views`, which today holds all four (`grep` over `Sources/` finds no other `arrow.counterclockwise`). | None today. Judged acceptable as an intentional, self-explaining tripwire; noted so nobody "fixes" it by loosening it to `>= 4`. | Tests |

## Questions

None. No design questions or requirements issues.

## Checked and fine

- **Root cause.** `AppKitButton.updateNSView` sets `button.isEnabled = isEnabled` (`AppKitButton.swift`) and has no other say in the matter. SwiftUI applies its environment's `isEnabled` to a hosted `NSControl`, and an environment that says enabled can override the representable's `false`. That fits 287524f's own commit message ("AppKitButton, which SwiftUI can override, so it showed enabled on an uncropped photo"). It also fits the observed pattern: on `develop` the only three headings right were Crop, Spots and Black & White, the three with `.disabled(!isModified)`. The `adoptEnvironment` trace is the engineer's (removed). It is consistent with the code and the symptoms, and I couldn't contradict it from the code. The general fix stays with #76, as intended.
- **One value, three uses.** `AdjustSection` (`AdjustControls.swift:501-517`) computes `canReset = values.isModified(section)` once. The context menu's Reset (`reset: canReset ? … : nil`), the button's `isEnabled` and `.disabled(!canReset)` all use it, so they can't disagree within one render. The heading's check box and Turn Off/On still go by `modified` (per group), as before. `.disabled` sits on the trailing button only. The `.contextMenu` on `SectionHeader`'s `HStack`, the disclosure and the title button are untouched. This is the same shape as Crop, Spots and Black & White.
- **`.disabled(false)` can't re-enable anything.** SwiftUI's disabled state combines with ancestors, so the change can only dim the reset and never undim it when an ancestor is disabled.
- **What "modified" means** is unchanged: `isModified(section) = resetting(section) != self` (`Adjustments.swift:479`).
  - A group turned off with values kept is modified, because `disabled` and the kept values differ from the reset copy. `resetModule` clears the values and removes the kind from `disabled`, so the reset turns the group back on (`turnedOffGroup` covers every section).
  - Distortion and Lens Vignetting store `on` (`LensProfileCorrections.swift:70,116`), so switched on at Amount 0 they are modified. `edited(.lens)` sets only `isOn`. Black & White on with every filter at 0 is covered by `BlackAndWhiteTests:75-78`.
  - `rawDecode` and `cameraProfile` are in no `Section.groups`. Unknown operations and a newer `kindVersion` go to `preserved`, which `resetting(section)` never touches, so they never enable a heading's reset (`operationsOutsideTheHeadings`).
  - The legacy `9.dng` decoder is read as `machineLearning` with the legacy version cleared (`Adjustments.swift:95-101`), so Details offers its reset and a reset clears it.
- **Reset behavior unchanged.** `editor.reset(section)`, its undo step and its History entry are not in the diff.
- **Tests.**
  - `edited(_:)` switches over `Group` exhaustively, so a new group forces the test to be updated. `editAndReset` checks that only the edited heading is modified and that the reset round-trips through `editStack`.
  - All five tests are Swift Testing, deterministic and without sleeps.
  - I ran the source check's logic on `develop`'s four files. It flags `AdjustControls.swift:509` (no `.disabled`) and passes Crop, Spots and Black & White, which confirms the status.md claim that it fails without the fix.
  - Reading PhotoApp sources from `PhotoCoreTests` through `RepositoryFiles` (`#filePath`) has a precedent in `LibraryModalTests`.
- **Nothing else changed.**
  - The diff touches only `AdjustControls.swift` (9 lines), the new test file and `status.md`.
  - No new strings: `"Reset \(title)"`, `"Turn Off"` and `"Turn On"` already existed. No branding.
  - No migration, no `PreviewCacheKey.currentPipelineVersion` bump, no golden, no rendering change.
  - No menu-bar item resets a single heading, so nothing else reads a second rule.
- **Swift 6 concurrency.** A SwiftUI `View` body on the main actor reading `editor.adjustments`, as before. No new isolation, no `@unchecked Sendable`.
- **Security.** No parser, subprocess, file writing or network code, so `/security-review` is not needed.

## Follow-up

(Second pass: none yet.)
