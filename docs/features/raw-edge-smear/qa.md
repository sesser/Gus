# RAW edge smear: QA

Owner: qa-tester. Date: 2026-11-10. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/raw-edge-smear`, the uncommitted working tree on `13b1f90`
(nothing is committed yet), on a Mac16,8, macOS 27.2 (26B123), SDK 27.2
(both bundles record `minos 15.0`, `sdk 27.2`). Bug fix for GitHub issue #55;
checked against the **Bug** section of `status.md`. No roadmap row.

## Verdict

Passes. On `develop` the bug shows in the tests (5 of 7 real-file cases fail)
and in the app (smeared loupe and cached previews); on the branch every check
passes, the app shows the same photos clean, and memory stays level. Nothing
was run on macOS 26 or 15 (see P2).

## Acceptance criteria

The Bug section has one criterion, "every photo looks the same whatever was
rendered before it". Its table of paths is broken out into rows below.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. The bug shows on `develop` | Test + Script | `RAWEdgeSmearTests` in a scratch copy of `develop` fails 5 of 7 cases (Run 2); the `develop` bundle's loupe and 3 cached previews are smeared (Script S1) | Pass (shown) |
| B2. Cached preview and thumbnail don't depend on the raw decoded before | Test + Script | `RAWEdgeSmearTests.previews`; S1/S2: 54 cached previews from the app's own import | Pass |
| B3. Loupe live frames | Test + Script | `RAWEdgeSmearTests.liveFrames`; S2 loupe snapshot of P1040058 opened after P1040027 | Pass |
| B4. Live frames at 100% (`LiveRegionRenderer`) | Test | `RAWEdgeSmearTests.liveRegion` | Pass |
| B5. Export, 2048 px long edge and full size | Test | `RAWEdgeSmearTests.exports(resized:)`, both cases (full size is a guard: clean on `develop` too) | Pass |
| B6. Color Alignment, Align automatically stores the same values | Test | `RAWEdgeSmearTests.colorAlignment` (`develop`: red 5.19 / blue −2.55 against 5.13 / −2.43 alone; branch: equal) | Pass |
| B7. Auto Exposure and Auto White Balance | Test | `RAWEdgeSmearTests.measurements` (a guard: passes on `develop` too) | Pass |
| B8. Every path that renders a RAW filter's image is keyed (CI guard) | Test | `RAWDecodeGraphTests` (5 tests); `rawFiltersAreMadeInKnownPlaces` fails on `develop`'s source (Run 2) | Pass |
| B9. No memory left behind per decode (code review C1) | Test | `RAWContextSoakTests.previews` at 12,000 (Run 3) | Pass |
| B10. The two raws in turn stay equal to their render alone | Test | `RAWContextSoakTests.realFilesInTurn`, 1,200 renders (Run 3) | Pass |
| B11. Code review C4: the soak's limits scale with the count and the per-preview figure is asserted | Test (read) | `SoakGrowth`, `SoakGrowthTests.tellsALeakFromALevelRun`, `RAWContextSoakTests.previews` asserts `fittedPerPreview < 10` KB; fewest previews 3,000 | Pass |
| B12. No healthy photo looks different | Script | S2: 51 of 54 previews have identical edge bands to `develop`'s (mean difference 0.00 levels); the other 3 are the smeared ones | Pass |
| B13. Old smeared previews are replaced (pipeline 7 → 8) | Script + Person | S2: the branch writes under `Previews/v8`; the owner's own library: P1 | Pass (scratch) / Open (P1) |
| B14. Fault and fix on macOS 26 and 15 | Person | P2 | Open |

## Findings

None for the engineer.

Notes, not findings:

- `RAWDecodeGraphTests.swift` lines 186 and 187 are two blank lines in a row
  (cosmetic).
- `rawFiltersAreMadeInKnownPlaces` checks source text. A call site that passed
  one fixed key would pass CI with the smear back. Code review already noted
  this. Only the real-file suites can catch it, so P2 matters.
- Which photos smear depends on decode order. In S1, `develop` smeared
  P1040057, P1040058 and P1040080, but not P1040065, which `status.md` lists.

## Runs

All runs used the owner's originals in place, read-only: `P1040027.RW2`
(SHA-256 `87e23765e99ee0d4…`) and `P1040058.RW2` (`7a6bdc6c935c227e…`). Both
were unchanged afterwards (same hash, no newer modification time).

1. **Full suite, branch.** `swift test`: 690 tests in 116 suites passed,
   1 known issue (the existing `LiveSessionTests` "Values above white survive
   the cached stages"). `Edge bands`, `Soak growth` and `RAW decode graphs`
   passed. The gated suites were skipped, as expected.
2. **The test fails without the fix.** A scratch copy of `develop` (`git
   archive 13b1f90`, outside the checkout) plus the engineer's
   `RAWDecodeGraphTests.swift` and `RAWDecodeGraph.swift` (unused there; the
   tests need the type to compile), so `decodeRAW` takes `raw.outputImage`
   as `develop` does:
   `RAW_EDGE_SAMPLES="<Kayaking>/P1040027.RW2:<Kayaking>/P1040058.RW2" swift test --filter "RAWEdgeSmearTests|RAWDecodeGraphTests"`.
   Results: previews, the 2048 px export, live frames, the 100% region and
   Color Alignment fail. Repeated edge rows were 0.18 to 0.53 of rows against
   0.00 to 0.009 alone, and the bands differed from the render alone by 9.3
   to 10.8 levels. The full-size export and the auto measurements pass (the
   guards). `rawFiltersAreMadeInKnownPlaces` fails (4 issues).
3. **Real-file suites, branch.**
   `RAW_EDGE_SAMPLES=<the same pair> swift test --filter RAWEdgeSmearTests`:
   6 tests (7 cases) passed; Color Alignment took 82 s.
   `RAW_CONTEXT_SOAK=12000 RAW_EDGE_SAMPLES=<the same pair> swift test --filter RAWContextSoakTests`:
   both passed. Synthetic DNG, 12,000 previews: 428, 428, 435, 440, 441, 439,
   435, 438, 444, 446, 445, 442 MB, 0.9 KB a preview fitted. Camera raws in
   turn, 1,200: none differed from alone, footprint 3,731 to 3,944 MB, level.
   No `AGX` message.
4. **Bundles.** `Scripts/build-app.sh all`: exit 0, `build/Gus.app` and
   `build/Gus Importer.app`, SDK 27.2. The `develop` bundle was built with
   `Scripts/build-app.sh` in the scratch copy. Each was copied to scratch,
   given `CFBundleIdentifier` `me.sesser.gus.debugtest` and re-signed ad hoc.

## Scripts

Scratch library sources: copies of the 54 Kayaking RW2 files
(`cp -p … *.RW2 <scratch>/kayak`), each bundle on an empty library of its
own. The executable was started from a shell (no key window was needed).

**S1, `develop` bundle copy** (and **S2**, the same script on the branch
copy with `lib-branch` and `branch-` file names):

```
<copy>/Gus.app/Contents/MacOS/Gus --library-root <scratch>/lib-develop --debug-script "wait 2; addfolder <scratch>/kayak; waitimport; wait 90; print activity; focus P1040027; loupe; wait 5; print previews; focus P1040058; wait 6; print previews; snapshot <scratch>/shots/develop-loupe-58.png; grid; wait 2; snapshot <scratch>/shots/develop-grid.png; quit"
```

Both printed `projects kayak=54 | Imported: 54` and, for each photo,
`previews … memory preview true disk preview true disk thumbnail true`.

- **Loupe snapshot, P1040058 after P1040027.** `develop`: the left edge
  (about 3% of the width) and right edge (about 4%) are horizontal streaks of
  repeated pixels across the trees and water. Branch: the same frame is clean
  to both edges. Both snapshots were looked at.
- **Cached previews** (`Previews/v7` on `develop`, `Previews/v8` on the
  branch, 54 previews and 54 thumbnails each). These were checked with a
  stdlib Python script that finds each file's preview by SHA-256, converts it
  with `sips` and computes the same measures as `EdgeBands` (share of
  left/right 2% band rows that are constant within 2 levels; mean band
  difference):

  | File | `develop` constant rows | branch constant rows | branch vs `develop`, levels |
  | --- | --- | --- | --- |
  | P1040057 | 0.248 | 0.002 | 9.27 |
  | P1040058 | 0.152 | 0.000 | 10.44 |
  | P1040080 | 0.316 | 0.001 | 13.65 |
  | The other 51 | at most 0.048 (skies) | the same | 0.00 |

## For a person

The bundle and its debug run cover the behavior on this Mac. A person is
needed only for the owner's own library and for other macOS versions.

To build the bundle and run it on a scratch library (zsh; a scratch copy with
its own bundle identifier, so your preferences and library are untouched):

```
cd ~/Projects/Gus && Scripts/build-app.sh
rm -rf /tmp/gus-qa && mkdir -p /tmp/gus-qa/kayak && cp -R build/Gus.app /tmp/gus-qa/ && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest /tmp/gus-qa/Gus.app/Contents/Info.plist && codesign --force --deep --sign - /tmp/gus-qa/Gus.app
cp -p ~/Pictures/Photos/2026/2026-11\ Kayaking/*.RW2 /tmp/gus-qa/kayak/
open -n /tmp/gus-qa/Gus.app --args --library-root /tmp/gus-qa/library
```

Then drag `/tmp/gus-qa/kayak` onto the window.

- **P1. Your own library after the update** (only if you choose to open it
  with this build; pipeline version 8 can't be undone for previews, but they
  regenerate). Open the library that holds `2026-11 Kayaking`. Look at
  P1040057, P1040058, P1040065 and P1040080 in the grid, in the loupe and at
  100% (Z). Check that the left and right edges show real detail, not
  horizontal streaks, and that the photos look as before otherwise. Previews
  regenerate on demand and the old `v7` cache folder is removed. Not a
  designer M-check (no design review for this fix).
- **P2. macOS 26 and macOS 15** (not covered here; CI has no camera raws). On
  a Mac running each, first run
  `RAW_EDGE_SAMPLES=<Kayaking>/P1040027.RW2:<Kayaking>/P1040058.RW2 swift test --filter RAWEdgeSmearTests`
  on this branch: all 7 cases should pass. To learn whether the fault exists
  there at all, run it again with `RAWDecodeGraph.output(of: raw)` changed to
  `raw.outputImage` in `PreviewGenerator.decodeRAW`, in a scratch copy.
  `status.md` asks for this on every new macOS.

## Follow-up

### Sign-off, 2026-11-10

Relayed by the main session. The owner's words: "P1 passes, I can't check
P2, set to pending verification."

- **Signed off** on 2026-11-10. The commit signed off is the tree tested
  above (uncommitted on `13b1f90`), to be committed on `bug/raw-edge-smear`.
  The main session commits it.
- **P1: Passed.** The owner checked it on their own library.
- **P2 (macOS 26 and 15): Open.** The owner left it open, so the fix ships
  as "checks pending" (B14 stays Open).
- **`CLAUDE.md` and `.claude/settings.json`.** The owner approved the
  Rendering rule (`RAWDecodeGraph.output(of:)`) and the
  `RAW_EDGE_SAMPLES` / `RAW_CONTEXT_SOAK` commands. They are now in the
  working tree, in `CLAUDE.md` (Commands and Architecture rules) with allow
  entries in `.claude/settings.json`. I did not rerun anything for these
  changes, which are docs and settings only.
