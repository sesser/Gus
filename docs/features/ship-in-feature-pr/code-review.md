# Ship in the feature PR, QA on bug fixes: code review

Owner: code-reviewer. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/ship-in-feature-pr` (PR #45), 6baf2b5..2a4001a (one commit).
Build and tests: not run. The diff is documentation and agent prompts only
(`docs/WORKFLOW.md`, the agent table in `CLAUDE.md`,
`.claude/agents/{product-manager,swift-macos-engineer,qa-tester,code-reviewer}.md`);
no file under `Sources/`, `Tests/`, `Scripts/` or `Package.swift` changed.

No feature folder, PRD or design: the owner's decision as relayed by the
main session is the spec (Ship becomes step 5, the branch's last commit,
merge is step 6 with nothing after it; bug fixes get a folder, a **Bug**
section in `status.md`, code review then QA, and the design review only when
the UI changes).

## Verdict

Not ready to merge as it stands, though nothing is a blocker. The new order
is stated consistently in `WORKFLOW.md`, `CLAUDE.md` and the product-manager
and engineer prompts, and nothing outside the roadmap still describes Ship
after the merge. But two prompts the bug-fix path depends on were not
brought along: the code reviewer's prompt still reviews only against a PRD,
and nothing tells the designer what to review a bug fix against. The
prompts also disagree on where the design review goes for a bug fix that
changes the UI. Ship-before-merge also opens two gaps the old order didn't
have: concurrent Ship edits conflicting on `develop`, and which date counts
as the ship date. Five Should fix, six Nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C1 | Should fix | `.claude/agents/code-reviewer.md:8`, `:12`, `:22` | The code-reviewer prompt does not know about the bug-fix path this change adds. Orient step 1 reads `prd.md`, `design.md` and `status.md` only "for a feature". The Tests check is "every acceptance criterion the PRD marks testable". Line 8 still says a branch without a feature folder gets its review in the report, but every bug fix now has a folder. Only the Report line (`:79`) changed. | On a `bug/…` branch, a code reviewer that follows its prompt alone finds no PRD, never reads `status.md`, and so never checks the **Bug** section or that "the test that fails without the fix" really does fail without it. Yet `swift-macos-engineer.md:37` and `WORKFLOW.md:20` both say code review checks against that section. | WORKFLOW step 4 and the bug-fix paragraph; owner decision 2 |
| C2 | Should fix | `code-reviewer.md:79`; `swift-macos-engineer.md:73`; `WORKFLOW.md:8`, `:20` | The prompts disagree on where the design review goes for a bug fix that changes the UI. `WORKFLOW.md:8` says QA runs after the design review "so that `qa.md` is the one list", and `qa-tester.md:3` agrees ("after the designer's review when there is one"). But the code reviewer's next step waits for the designer only "for a feature". The engineer's "code-reviewer, then qa-tester (and the designer only if the UI changed)" puts the designer after QA, or leaves it unplaced. The bug-fix paragraph says "Code review comes first, then QA" and never places the design review. | A bug fix changes a toolbar item. The code reviewer reports "next step: qa-tester", QA runs and writes its P list, and only then does the designer add M-checks to `review.md`. `qa.md` is then no longer the one list of what a person must check, and the main session has to decide whether to run QA again. Fix: in all three places, say "code review, the design review if the UI changed, then QA". | WORKFLOW step 4 ordering |
| C3 | Should fix | `.claude/agents/apple-ui-designer.md:80` (unchanged) | The designer's Review bullet reviews "against `design.md` and the acceptance criteria". A bug fix has neither, and the prompt says nothing about bug fixes. | When the main session runs the designer on a UI-changing bug fix (which `WORKFLOW.md:20` now requires), the designer either reports that there is nothing to review against or picks some baseline on its own (the nearest feature's `design.md`, the HIG, the UI on `develop`). Fix: one sentence saying a bug fix is reviewed against the **Bug** section's expected behavior, the existing design of the surface it touches (named in `status.md`), and the HIG. | WORKFLOW step 4; "No agent resolves … by guessing" |
| C4 | Should fix | `WORKFLOW.md:15`, `:17`; `product-manager.md:26` | Nothing covers a Ship commit that conflicts with `develop`. Under the old order, Ship passes ran one after another on `develop`. Now each one sits on its own branch. Two open PRs that both Ship edit the same parts of PM-owned files: the end of the roadmap's Shipped table, the dated log paragraphs, the "Updated … (Ship pass)" block in `_inventory.md`, and the end of "Scope so far" in `CLAUDE.md`. Nothing says who resolves such a conflict, whether merging `develop` into the branch counts as a "later commit" that needs Ship again, or whether the branch must be up to date with `develop` before Ship. | PR A ships and merges. PR B's Ship commit then conflicts in `docs/roadmap.md`, and GitHub blocks the merge. Whoever resolves it is editing PM-owned files without the PM ("do not do one agent's job from another"). Even without a textual conflict, B's log entry can say something that stopped being true when A merged (for example "Now has two items"), because B's PM never saw A's changes. Fix: Ship runs on a branch already merged up to date with `develop`. If `develop` moves and the Ship files conflict, the main session merges `develop` and runs the PM in Ship mode again on the merged tree instead of resolving the conflict by hand. | WORKFLOW Ownership; "do not do one agent's job from another" |
| C5 | Should fix | `product-manager.md:28`, `:29`; `WORKFLOW.md:15` | Which date Ship records is not defined. The roadmap's Shipped table has a date column, and the PRD line is `Shipped <date>, PR #<n>`. Ship now runs before the merge, and a later build or CI fix "leaves it standing", so the only date the PM can write is the date of the Ship pass. `WORKFLOW.md:17` says the record "becomes true when the pull request merges", and `:18` says nothing runs after the merge. | Ship runs on 2026-11-06 and the owner merges on 2026-11-09. The roadmap and PRD say "Shipped 2026-11-06" for good, and the reconcile check (`product-manager.md:96`) cannot see a difference to correct. If the merge date is what matters, nothing can ever record it. The owner has to choose (see Q1). Whichever is chosen, the PM prompt should name it ("the date of the Ship pass" or "the expected merge date"). | Owner decision 1 ("describe what the branch delivers") |
| C6 | Nit | `WORKFLOW.md:18` | "Nothing runs after the merge" is too absolute. The qa-tester's description (`qa-tester.md:3`) still includes "to work down open manual checks on shipped features", and its `qa.md` Follow-up records P items "when the owner reports it done". Turning "Shipped, checks pending" into Shipped is left to whoever reconciles. | Read literally, the main session declines to run QA follow-ups or a reconcile for a merged feature, and "checks pending" never clears. Suggested wording: "Nothing in this feature's pass runs after the merge; open checks are worked down later on their own branch (qa-tester), and the product manager records them when reconciling." | Internal consistency |
| C7 | Nit | `WORKFLOW.md:17`; `product-manager.md:36` | The triggers for running Ship again are narrower than what Ship writes. WORKFLOW lists "behavior or scope that the README or Scope so far describe, or a check opened or closed". Ship also writes the roadmap row, which in practice sums up code review and QA results and costs (see the editor-follow-edit-drop row), the PRD Status line and `_inventory.md`. The PM prompt's "behavior, scope or an open check" is a third wording. WORKFLOW also doesn't say whether a source commit after Ship (the "build fix" example) goes back through code review. | A commit after Ship fixes a second-pass code-review finding, or changes a cost QA noted (an O-note, not a P check). No trigger fires, so the merged roadmap row still says "Code review: ready to merge, no findings" or gives the old cost. Fix: one trigger list, used in both files: "anything the Ship pass wrote". | Internal consistency |
| C8 | Nit | `WORKFLOW.md:3`, `:62`, `:71` | Line 3 says "Do not skip steps", yet bug fixes now skip steps 1, 2 and (conditionally) 5, and the design review. "Requirements live in `prd.md`" (`:62`) leaves out the **Bug** section, and the Typical session covers only features. Separately, the bug-fix paragraph doesn't say that a bug fix which skips Ship is recorded at the next reconcile, as `product-manager.md:96` now requires. | An agent reading line 3 alone treats the bug-fix path as a violation. Fix: "except as the bug-fix paragraph below says"; add "(for a bug fix, the **Bug** section of `status.md`)" to the Rules line; add one sentence to the bug-fix paragraph about the reconcile. | Internal consistency |
| C9 | Nit | `WORKFLOW.md:20`; `swift-macos-engineer.md:37`; `qa-tester.md:13` | The three lists of what the **Bug** section holds differ. Engineer: repro, expected and actual, root cause, failing test. WORKFLOW: no root cause. QA: no actual behavior and no root cause. | Nothing breaks, but the owner's decision names all five parts, and a reviewer that checks against WORKFLOW won't ask for the root cause. Use the engineer's list in all three places. | Owner decision 2 |
| C10 | Nit | `qa-tester.md:70` | The qa-tester report doesn't name the next step, though the code-reviewer and engineer prompts now do. | After QA passes, the next step depends on the change: Ship (step 5) for a feature or a bug fix with a roadmap row or README/`CLAUDE.md` impact, otherwise merge. Findings go to the engineer. Without this, the main session has to work it out from WORKFLOW each time. | Consistency with the other prompts |
| C11 | Nit | `WORKFLOW.md:15` | Nothing says when the pull request is opened, or by whom. CI (`.github/workflows/build.yml`) runs on `pull_request` and on pushes to `develop` and `master` only, so "CI is green" before Ship requires the PR to be open already. | Not a failure today (PRs have been opened before review), but an agent reading step 5 alone cannot tell whether opening the PR is part of Ship or comes before it. One clause fixes it: "the pull request, opened when the engineer reports Done". | Completeness |
| C12 | Nit (PM-owned, not a blocker) | `docs/roadmap.md:158`, `:164`, `:177`, `:178`, `:179`, `:180` | Six roadmap rows still describe bug fixes under the old rule. Line 177 (appkitbutton-enablement, the known one) has "bug fixes skip steps 1, 2 and 6". Lines 158 and 164 have "bug fix without a feature folder", and 178–180 (ci-test-crash, debug-script-undo-groups, qa-test-gaps) have "For the engineer, no feature folder". Every bug fix now gets a folder, and step 6 is now Merge. | The engineer picking up reads-beside-write-chain or qa-test-gaps from the roadmap is told there is no folder, while WORKFLOW says there is one with a **Bug** section. For the PM's next reconcile. The dated log entries (lines 29, 42, 63) are history and fine. | WORKFLOW bug-fix paragraph |

## Questions

For the owner (through the main session):

- **Q1 (C5).** Should Ship record the date of the Ship pass or the merge
  date? If the merge date, someone has to write it after the merge, which
  conflicts with "nothing runs after the merge". The other option is a
  roadmap convention that the Shipped date is the date of the Ship pass.
- **Q2 (C7).** Does a source commit after Ship (the "build or CI fix"
  example) go back through code review, and through QA if it touches
  behavior? Today a post-Ship fix could merge with no reviewer having seen
  it, while the Ship record still cites the earlier reviews.
- **Q3.** CI is known to crash now and then (roadmap ci-test-crash). Does a
  red CI run on the docs-only Ship commit block the merge, or is the green
  run before Ship enough? WORKFLOW requires green CI only before Ship.
- **Q4.** For a bug that only a test can show (a PhotoCore bug with no
  debug-script route), "show the bug on `develop`" means running the new
  test against `develop`'s sources. That means putting a test file into a
  scratch tree, which sits awkwardly with qa-tester's "never edit anything
  under `Tests/`". Is that allowed in a scratch copy, or should QA read the
  test and point to the engineer's run in `status.md`?

## Checked and fine

- The step numbers in the changed files are consistent: Ship is step 5 in
  `WORKFLOW.md:15`, `product-manager.md:26` and the engineer's note
  (`swift-macos-engineer.md:36`), and Merge is step 6. The `CLAUDE.md`
  agent table, the PM frontmatter description and the Typical session all
  describe Ship before the merge.
- Nothing in `README.md`, `docs/USER_GUIDE.md`, `docs/features/_inventory.md`,
  `docs/PROFILING.md`, `.claude/settings.json` or `apple-ui-designer.md`
  describes Ship after the merge or refers to the old step numbers. The
  only stale mentions are the roadmap rows in C12. The "step 6" at
  `docs/archive/PHASE2_PLAN.md:84` is a phase-2 plan step, not this
  workflow.
- The PM Ship mode no longer asks for a merge commit (it has none before
  the merge), only the PR number. The `_inventory.md` "develop as of
  <commit>" habit fits "describe what the branch delivers, not a commit".
- The ownership table needs no new rows. Bug-fix folders reuse the
  per-feature files with the same owners, and the main session commits the
  PM's Ship changes because the PM has no shell, which WORKFLOW states.
- The statuses line (`WORKFLOW.md:40`) now matches the new timing.
- A PR closed unmerged never lands the record, and the reconcile rule
  (`product-manager.md:96`) catches merges without a Ship pass. Both match
  the owner's decision.
- The qa-tester's "show it on `develop` in a scratch tree, then gone on the
  branch" matches how the last two bug-fix QA passes worked
  (`editor-follow-edit-drop/qa.md` used `git archive develop` into scratch).
- No parser, subprocess, file writing or network code is involved:
  `/security-review` is not needed.

## Follow-up

Second pass, 2026-11-06. I reviewed the fixes uncommitted in the working
tree on top of 2a4001a (`git diff`). They touch six files: `docs/WORKFLOW.md`
and `.claude/agents/{apple-ui-designer,code-reviewer,product-manager,qa-tester,swift-macos-engineer}.md`.
Nothing was committed yet, so the commit column says "uncommitted". Build and
tests were not run (docs and prompts only).

### Owner rulings on the questions

- **Q1.** Ship records the date of the Ship pass. Now in `WORKFLOW.md:15`
  ("The date it records is the date of the Ship pass") and
  `product-manager.md:28`–`29`.
- **Q2.** Any commit that changes source or tests after a review, including
  one after Ship, gets a code-review second pass, and QA as well when it
  changes behavior. Now in `WORKFLOW.md:14` and `:18`.
- **Q3.** A red CI run on the Ship commit gets one rerun. If it fails again,
  it blocks the merge. Now in `WORKFLOW.md:20`.
- **Q4.** qa-tester may add the engineer's test to a scratch copy of
  `develop` outside the checkout, never in the repo. Now in `qa-tester.md:8`
  and `:13`.

### Findings

| # | Result | Where it was fixed | Commit |
|---|--------|--------------------|--------|
| C1 | Fixed | `code-reviewer.md:8` (every feature and bug fix has a folder; a branch without one, such as a docs-only change, uses the path it is given), `:12` (for a bug fix, read the **Bug** section of `status.md` with all five parts), `:22` (the test the Bug section names fails without the fix). | uncommitted |
| C2 | Fixed | One order everywhere: code review and, when there is one, the design review, then QA last. `WORKFLOW.md:8` ("QA runs last, after both"), the bug-fix paragraph ("QA still runs last"), `code-reviewer.md:79`, `swift-macos-engineer.md:73`, the `qa-tester.md` description, and `apple-ui-designer.md:80` ("Your review comes before QA's"). | uncommitted |
| C3 | Fixed | `apple-ui-designer.md:80`: a UI bug fix is reviewed against the Bug section, the `design.md` of the feature it touches, and the HIG. This matches the bug-fix paragraph in `WORKFLOW.md`. | uncommitted |
| C4 | Fixed, with C13 and C14 below | `WORKFLOW.md:15`: `develop` is merged into the branch before Ship. `:19`: when another PR shipped first, merge again, take `develop`'s side of Ship's files and run Ship again. `product-manager.md:36`: the PM rewrites its entries against `develop`'s version. The wording of this fix raises C13 and C14. | uncommitted |
| C5 | Fixed | Q1 ruling, `WORKFLOW.md:15`, `product-manager.md:28`–`29`. | uncommitted |
| C6 | Fixed | `WORKFLOW.md:21`: "No agent step follows the merge"; pending checks are worked down later and the PM clears them at its next reconcile. `product-manager.md:96` adds that clearing to the reconcile. | uncommitted |
| C7 | Fixed | One trigger list in `WORKFLOW.md:18` and `product-manager.md:36`: what the feature does or its scope, a check opened or closed, a follow-up named. A build or CI fix that changes none of these leaves the record standing and still gets its second code review (Q2). | uncommitted |
| C8 | Fixed | `WORKFLOW.md:3` (except the steps a bug fix skips), the Rules (`:66`–`67` name the Bug section), the bug-fix paragraph (a fix merged without Ship is recorded at the next reconcile), and a bug-fix Typical session (`:76`). | uncommitted |
| C9 | Fixed | The same five parts (steps to reproduce, expected and actual behavior, root cause, failing test) in `WORKFLOW.md`, `swift-macos-engineer.md:37`, `qa-tester.md:13` and `code-reviewer.md:12`. | uncommitted |
| C10 | Fixed | `qa-tester.md:70`: findings go back to the engineer; with none, Ship if it applies, then the owner merges. | uncommitted |
| C11 | Fixed | `WORKFLOW.md:8`: the main session opens the pull request when the engineer reports Done, so CI runs during review. The Typical sessions match. | uncommitted |
| C12 | Not fixed (on purpose) | Left for the product manager's next reconcile, as the main session decided: `docs/roadmap.md:158`, `:164`, `:177`–`:180`. Not a blocker. | n/a |

### New on this pass

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C13 | Should fix | `WORKFLOW.md:19`; `product-manager.md:36` | "Take `develop`'s version of those files" takes whole files. Two of Ship's files are only partly the PM's: in `CLAUDE.md` it owns only "Scope so far" and "Not yet" (the rest is the owner's), and `README.md` can carry the owner's own edits. A branch that changes another part of one of them (this PR changes the `CLAUDE.md` agent table) loses that change without anyone noticing. The PM's rerun rewrites only its own sections, so nothing puts the lost change back. | This branch, run through Ship, conflicts in "Scope so far" because another PR shipped first. The main session follows line 19 and checks out `develop`'s `CLAUDE.md`, which reverts this PR's product-manager row in the agent table. The PM then rewrites only Scope so far and Not yet, and the PR merges with the old agent-table text. Fix: take `develop`'s side only of the conflicting PM-owned parts (`docs/roadmap.md`, `docs/features/_inventory.md`, the PRD Status line, the README sections Ship edits, and `CLAUDE.md` "Scope so far" and "Not yet"), keep the branch's side everywhere else, then run Ship again. | Ownership table; "do not do one agent's job from another" |
| C14 | Should fix | `WORKFLOW.md:14` with `:15` and `:19`; `code-reviewer.md:75` | Merging `develop` into the branch, which step 5 now does every time and again when another PR shipped first, is a commit that changes source and tests on the branch whenever `develop` has moved. Read literally, line 14 then calls for a code-review second pass, and QA too if behavior changed, before every Ship. On that pass the code reviewer's "read only the new commits" pulls in the other PR's whole diff, which was already reviewed on its own branch. | PR A merges, and the main session merges `develop` into PR B to Ship it. The merge brings A's `Sources/` changes, so by line 14 B goes back to code review (which reviews A's changes again) and possibly QA, and then may need to merge `develop` again. Either this loops, or the main session quietly skips the rule. Fix: a merge of `develop` with no conflicts under `Sources/`, `Tests/`, `Scripts/` or `Package.swift` needs no second pass (CI covers it). A merge whose code conflicts were resolved by hand gets a second pass on the resolution only (for example `git show --remerge-diff <merge>`). | WORKFLOW step 4 second-pass rule (Q2) |

I found nothing else that the fixes contradict. Specifically:

- The `CLAUDE.md` agent table, the code-reviewer and designer frontmatter
  descriptions and the statuses line are consistent with the new text.
- The PM prompt's "pull request is open" agrees with the PR now being
  opened at Done.
- qa-tester's scratch-copy exception is limited to outside the checkout,
  and the rest of its prompt, including "the only file you write is
  `qa.md`", still holds for the repository.
- The bug-fix Typical session leaves out "merge `develop` first" before
  Ship. That is covered by step 5, so it is not a finding.

**Verdict on this pass.** C1–C11 are fixed and C12 is deferred to the
product manager on purpose. The two new Should fix items, C13 and C14,
both come from the wording of the C4 fix and the Q2 ruling. Each needs a
sentence in `WORKFLOW.md` (C13 also in `product-manager.md:36`). Ready to
merge once they are fixed, or once the owner accepts them as they stand.

### Third pass

2026-11-06. This pass checks only C13 and C14, in the working tree, which
is still uncommitted on top of 2a4001a.

| # | Result | Where it was fixed | Commit |
|---|--------|--------------------|--------|
| C13 | Fixed | `WORKFLOW.md:19`: when another PR shipped first, take `develop`'s side only in the conflicting parts the product manager wrote at Ship. Those parts are named: its roadmap entries, the PRD status, the inventory, its README lines, and `CLAUDE.md` "Scope so far" and "Not yet". The branch's side is kept everywhere else, the owner's other `CLAUDE.md` and README edits included. `product-manager.md:36`: the product manager rewrites its entries against `develop`'s and touches nothing outside the parts it owns. In the C13 example, this branch's agent-table change now survives. | uncommitted |
| C14 | Fixed | `WORKFLOW.md:14`: a merge of `develop` with no conflict in `Sources/`, `Tests/`, `Scripts/` or `Package.swift` does not count as a commit that needs a second pass (CI covers it). When code conflicts were resolved by hand, the second pass reviews only the resolution (`git show --remerge-diff <merge>`). `code-reviewer.md:75` says the same from the reviewer's side: skip a merge of `develop`, or review only its hand resolution. `--remerge-diff` runs on this Mac's git (2.54.0). The step 5 merge can no longer loop back into review. | uncommitted |

The two new sentences contradict nothing in the other files. "Ship's
files" in `WORKFLOW.md:15` and the product manager's ownership line
(`product-manager.md:90`) name the same set as line 19.

**Final verdict.** Ready to merge. C1–C11, C13 and C14 are fixed. C12
(the stale roadmap rows) is left for the product manager's next reconcile,
on purpose, and does not block. `/security-review` is not needed.
