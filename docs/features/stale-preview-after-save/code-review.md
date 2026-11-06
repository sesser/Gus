# Stale preview after save: code review

Owner: code-reviewer. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/stale-preview-after-save`, 334312c..369b98e (7b2d575 the fix,
369b98e the pipeline version bump). Build and tests: `swift build` clean;
`swift test` 554 tests in 97 suites passed, 1 known issue (the pre-existing
`LiveSessionTests` `withKnownIssue`).

Spec: no `prd.md` or `design.md` (bug fix); `status.md` in this folder and
QA's report (sharpen-mask-preview `qa.md` Q1).

## Verdict

Approve with nits. The fix is correct at both layers: `PreviewService` can no
longer keep a rendition under a hash other than that of the stack it rendered,
and the editor and batch undo publish a hash only after its write succeeds.
The new tests fail without the guard and pass with it. One nit on a test step
that checks nothing; one owner question on the cost of the pipeline bump.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Nit | `Tests/PhotoCoreTests/StalePreviewTests.swift:155-160` | The last step of `catalogWritesDecideWhatRenders` ("Undo back to no edits: the identity key's rendition is still the original") is always a disk-cache hit. The identity thumbnail was written to disk at line 143, and `clearMemory()` empties only memory, so `image(for:)` returns the file without loading a stack. The step passes with or without the fix and does not cover the undo case `status.md` describes (an undo to no edits published the identity hash before its write). | Checked: with the `staleEditStack` guard disabled (`guard … \|\| versionID >= 0`), this test failed only at lines 147 and 153. Nothing failed at 159. To make the step count, request a tier that is not cached yet (for example `.preview` with the identity hash) *before* `setEditStack(.identity, …)` and expect `staleEditStack`; then expect the original after the write. Or drop the step and its claim in `status.md`. | Tests: every check would fail without the change |

No Blocker and no Should fix.

## Questions

- **Q1 (owner or product-manager): the cost of pipeline version 7.** The
  engineer chose to drop every cached rendition (`status.md`, "Repair of
  previews already cached wrong"). The reasoning holds: the catalog keeps no
  edit history, so a wrong entry cannot be told apart from a right one under
  any hash. The visible cost is a product trade-off nobody has ruled on:
  - every thumbnail and preview regenerates on first view;
  - masters on volumes that are offline at first launch show the
    unavailable glyph until their volume is mounted again.

  For a library kept mostly on external drives, that is the whole archive
  going blank after an update. Earlier bumps (3 to 6) did the same, but they
  came with rendering changes. Ask the owner to confirm this is acceptable.
  If it is not, one alternative is to carry v6 entries forward only for
  masters that are offline at that moment and regenerate them once their
  volume is back. That is the engineer's call to design. It is not a
  code-review blocker.
- **Q2 (product-manager, roadmap): pre-existing data loss.** `status.md`
  Notes, first item: `AdjustmentEditor.follow` loads a stack straight from
  the catalog without waiting for pending writes. Leaving a photo and
  returning within one write's latency, then committing, can write back the
  values from before the last commit and drop that edit. This is outside the
  branch's scope and correctly left alone. It is real data loss, though, so
  it belongs on the roadmap as a bug and not only in this status file.

## Checked and fine

- **Ordering in `AdjustmentEditor.apply` / `showSaved`.** `persist` takes a
  `@MainActor` closure, so `showSaved` runs on the main actor right after
  `setEditStack` resumes, in write-chain order. Cases traced:
  - Quick successive commits A then B: A publishes, then B. A request for A
    that loads after B lands gets `staleEditStack`, and B's publish
    reconfigures the cell.
  - Undo while a write is pending: it goes through `apply` and is queued
    after the write it reverses.
  - A failed write publishes nothing: the library and catalog hashes stay
    equal, and the Activity row reports it as before.
  - Switching photos mid-write: `showSaved` updates only the library when
    `item` has moved on.
  - Show Original and hover previews: their `seedPreviewIfRendered` guards
    hold. The brief showing of the previous hash is noted in `status.md`.
  - Sharpening map frames never seed (`showsPhoto`).
  - Seeding still checks `item.editStackHash == committed.editStack.renderHash`,
    so for A then B it seeds only on B's publish or on B's frame.
  - `[weak self]` is harmless: `editor` is a `let` on `LibraryModel`, and
    the `persist` task holds the model strongly.
- **Batch undo/redo** (`registerEditStacksUndo`): it now publishes inside
  `persist` only after `setEditStacks` succeeds. The forward batch path is
  unchanged and already published on success only. Every hash publisher in
  the app was grepped (`setEditStackHash`, `item?.editStackHash =`): only
  `showSaved`, `catalogChanged` and `showEditStacks` remain, all after a
  successful write.
- **The `staleEditStack` invariant cannot reject legitimate keys:**
  - Rows get their hash only from `stack.renderHash` written with the JSON
    (`setEditStack`, `setEditStacks`, `makeDefault`, `duplicateVersion`
    copies both). No migration or SQL rewrites `editStack`.
    `EditStackCorpusTests:105` pins decoded `renderHash` to the recorded hash.
  - JSON round trip of `EditParameter.number`: 400,000 random and edge
    doubles (including -0.0, subnormals, 1e21/1e22) re-encode to identical
    bytes (scratch test).
  - `schemaVersion` became derived in 1e6da5d, but every earlier stack
    stored 1, so the hash is unchanged.
  - Identity stacks, disabled operations (left out on both sides), videos
    (the poster path checks the same stack), pairs (each `CatalogItem`
    carries its own version's id and hash), and ML fallback `storeForSession`
    (same key) all pass.
  - Unreadable or newer-schema stacks throw from the loader as before.
- **Consumers of a `staleEditStack`:**
  - `PhotoCell` stays silent and is reconfigured by the next publish.
  - `FilmStripCell`, the loupe (preview, HDR, 1:1, neighbors), the
    histogram, the export sheet preview, keyword suggestions and warming all
    use `try?` and either re-key on the hash change or are best-effort.
  - Every `PreviewRequest` is built from one `CatalogItem`
    (`LibraryModel.previewRequest`, photobench), so the id and the hash
    always come from the same row.
  - photocli and export do not go through `PreviewService`.
  - Residual risk, pre-existing and not a finding: `reloadItems` fetches
    outside the write chain. A fetch that read the row before an editor
    write and applies after `showSaved` puts the old hash back. The cell then
    shows the old cached thumbnail, or stays blank if that one was never
    cached, until the next reload. Before this branch the same race wrote the
    new look under the old hash for good, so the branch makes this case
    better.
- **The unfixed code fails the tests.** With the guard disabled, all three
  `StalePreviewTests` failed (16 issues). Restored with `git checkout`;
  worktree clean. The tests are Swift Testing, deterministic and use no
  sleeps.
- **Changes to existing tests are not loosening.**
  `offlineMastersAreServedFromCacheOnly` now uses a key that matches its
  loader. `diskCacheStoresLoadsAndCanBeWiped` uses
  `currentPipelineVersion - 1` for "older".
- **Pipeline bump against CLAUDE.md.** It is in its own commit with a
  one-line reason. There are no rendering changes and no golden changes, and
  `UPDATE_GOLDENS` was not run. The `PreviewCacheKey` doc comment states the
  new reason. No other branch sets version 7, so it collides with nothing.
- **Swift 6:** the build is clean with no new warnings. The static
  `stack(_:versionID:for:)` takes a `@Sendable` loader.
- No strings, migrations, dependencies, branding, parsers, subprocesses or
  network code are touched.

## Follow-up

(To be filled after the engineer's fixes.)
