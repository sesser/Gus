# Review before PR: code review

Owner: code-reviewer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/review-before-pr`, uncommitted changes on dfa0d5c. Build and tests: not run; the change is docs, agent prompts and one GitHub Actions file. The workflow's triggers, the repository rulesets and past CI runs were read from GitHub instead.

## Verdict

Not ready to merge. One premise of the CI change is wrong: `develop` has no classic branch protection, but an active ruleset requires both CI checks with no bypass, so `paths-ignore` would make every docs-only pull request unmergeable (C1). The new order is consistent across `docs/WORKFLOW.md`, `CLAUDE.md` and the prompts; the other findings are gaps in what happens when a step goes wrong.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C1 | Blocker | `.github/workflows/build.yml:7-15` | The ruleset "Default" (id 26039467, active, targets `~DEFAULT_BRANCH`, which is `develop`) requires `Build and test (macos-15)` and `Build and test (macos-26)` and a pull request. `bypass_actors` is empty and `current_user_can_bypass` is `never`. "master: required checks" (id 26659207) requires the same two on `master`. The classic protection API returns 404, which is probably where "no branch protection" came from. | A pull request that changes only `docs/`, `.md` or `.claude/` starts no workflow, so neither check ever reports. GitHub's docs: such checks "remain in a Pending state" and the pull request is "blocked" ("Waiting for status to be reported"). Nobody can bypass, so it cannot be merged. 10 of the last 25 merged PRs were docs-only (#46, 45, 44, 38, 33, 32, 31, 30, 24, 22). This branch escapes only because it changes `build.yml`; the next docs-only PR hangs. A docs-only release PR into `master` would hang the same way. Options under Questions Q1. Whichever is chosen, `WORKFLOW.md:22` "once CI is green" needs a clause if a docs-only PR can have no run. | Owner decision 4 |
| C2 | Should fix | `docs/WORKFLOW.md:16` | Step 6 runs the full `swift test` and `Scripts/build-app.sh all` after merging `develop`, then says "It then runs product-manager". It has no failure path, unlike step 7, and no place for the second pass that line 14 requires when code conflicts are resolved by hand. | The merge brings in a change that breaks a test, or conflicts in `Sources/`. Read in order, the text goes straight on to Ship, and the record is written on a red or unreviewed branch. Suggested: "If it fails, or code conflicts were resolved by hand, stop: the fix or resolution goes through step 4's second pass, and back to the owner only if it changes behavior; then repeat this run." Say too whether line 20's second merge of `develop` repeats the run or leaves it to CI. | Owner decision 1; the "known to work here" aim of step 6 |
| C3 | Should fix | `docs/WORKFLOW.md:24`, `:77` | The merge of `develop` and the full local run live inside step 6, and a bug fix runs step 6 only "when the fix has a roadmap row or changes what the README or `CLAUDE.md` says". Line 77 confirms the path: sign-off, Ship if it applies, "Then push and open the pull request". Bug fixes do reach sign-off and the PR; only this part is lost. | A bug fix with no roadmap row, cut from an old `develop`, reaches the PR never merged with `develop` and with no full run since the engineer's. If it conflicts, GitHub's docs say `pull_request` workflows do not run until the conflict is resolved, so the PR just shows no CI. Suggested: make the merge and full run unconditional and only the product-manager pass conditional. | Owner decision 1 |
| C4 | Should fix | `docs/WORKFLOW.md:14-15`; `.claude/agents/swift-macos-engineer.md:39` | A change the owner asks for at sign-off "goes to the engineer like any finding", but line 14 routes later commits only to code-reviewer and qa-tester, says "the reviewer that raised a finding confirms the fix in its own file" (the owner has no file), and step 5 never says the owner sees the result again. The engineer's prompt lists findings from the three reviewers, not the owner. | The owner reports a spacing problem at sign-off, the check most likely to find one. The engineer changes the UI; code review and QA pass; the designer, whose `review.md` now describes the old UI, is never asked; and nothing says the owner's go-ahead is needed again. A request that is really new scope has no route to the product manager or designer either. Suggested: record owner findings in `qa.md`'s Follow-up, add the designer to line 14 "when it changes the UI", send new scope to its owner, and say that the sign-off repeats after any such change. | Owner decision 3; `WORKFLOW.md` Rules |
| C5 | Should fix | `docs/WORKFLOW.md:15` | "How to run the build" does not say with which library. The bundle from `Scripts/build-app.sh` has identifier `me.sesser.gus`, the release identifier, so `LibraryLaunchGuard.decide` allows a launch without `--library-root` and it opens the real library. `WORKFLOW.md:63` protects "UI checks" by agents, not this step. | A branch with a new migration: the owner double-clicks the bundle as instructed, `Catalog.open` runs the migrator (`Catalog.swift:24`) on the real catalog, and if the branch is then changed or abandoned the catalog stays migrated by unmerged code. Suggested: step 5 names the scratch library and the launch line, unless the owner rules otherwise (Q4). | `CLAUDE.md` launch rule; `docs/WORKFLOW.md` Build |
| C6 | Should fix | `docs/WORKFLOW.md:21` | "If it fails again it blocks the merge: the fix goes to the engineer" has no case for the known CI crash, and CI now runs once, after sign-off, with required checks nobody can bypass. | Since 2026-11-05, 7 of 29 completed runs were red. Five of the seven are the crash or its signature in the test process (42663678027, 42564076836, 42334332669, 42135725552, and 42296234649 with the same helper-process error but no signal line). PR #49's run today is one, so the crash still happens. If the rerun also crashes, the engineer is handed a failure with nothing to fix and the PR cannot merge. The owner earlier asked for this to be raised if it starts blocking merges (Q2). | Owner decision 1 |
| C7 | Should fix | `docs/WORKFLOW.md:15-16`; `.claude/agents/qa-tester.md:65` | The sign-off record has a date and open checks but no commit, and step 6 commits only the product manager's changes ("commits these changes"). | The main session commits exactly what the text says and the `qa.md` entry stays out of the branch. The product manager's later reconcile on `develop` reads `qa.md`'s Follow-up to clear "checks pending" and does not find the list. Without a commit, the record also cannot say which build was signed off, though step 7's "only if it changes behavior" is judged against it. Suggested: record the commit, and commit `qa.md` before step 6's merge. | Owner decision 3 |
| C8 | Nit | `.claude/agents/code-reviewer.md:59` | The template's verdict still reads "ready to merge, or not", the one wording left in the five prompts that assumes merging follows review. | An agent following its own prompt tells the main session a branch is "ready to merge" before QA, sign-off, Ship and CI. Suggested: "ready for sign-off". | Owner decision 1 |
| C9 | Nit | `.claude/agents/qa-tester.md:70` | The report's next step names only the findings or the owner's sign-off, and qa-tester also runs after the sign-off to record it. | On that run the prompt's next step is the sign-off that was just recorded. Suggested: add "or, after recording the sign-off, Ship or the pull request". | Owner decision 3 |

### Non-blocking: product-manager's files (not findings on this change)

- `docs/roadmap.md:296-298` describes a bug fix as needing "code review and QA"; it now also needs the owner's sign-off.
- `docs/roadmap.md:316`, row ci-test-crash, ends "Owner to confirm it still happens". The runs above show it does, latest today.
- `docs/features/_inventory.md:235`, the CI row, should mention skipped paths if `paths-ignore` stays.

## Questions

For the owner:

- **Q1 (C1). How should docs-only PRs get past the required checks?**
  - (a) Drop `paths-ignore` and keep today's behavior: docs-only PRs pay for a full run, as all 10 did. Simplest, and no change to the ruleset.
  - (b) Keep the ruleset and replace `paths-ignore` with a first step in the job that compares changed files and skips Build, Test and bundling. The job still reports both names as success, at the cost of a short macOS runner start. A job-level `if` is riskier here, because the job's name depends on `matrix.os`; test it before relying on it.
  - (c) Keep `paths-ignore` and remove the required checks from both rulesets. "Once CI is green" then rests on the process alone, for code PRs too.
- **Q2 (C6). What should a repeated signal 11 at step 7 do?** Options: treat a signal death as re-runnable beyond the one rerun, rerun `swift test` once on signal death in `build.yml`, or fix the crash first (roadmap ci-test-crash).
- **Q3. Should macOS 15 be checked before sign-off?** As written, a macOS-15-only failure appears after the owner has signed off and nothing can reproduce it here (this Mac is on Darwin 27). `build.yml` has `workflow_dispatch`, so `gh workflow run build.yml --ref <branch>` runs both legs on a pushed branch with no PR. Four phase 5 runs failed on macOS 15 only (41312864213, 41312312664, 41271656418, 41270584102), so this is a real class of failure. It costs runner time and is not a PR, but decision 1 says CI runs at step 7, so it is the owner's call.
- **Q4 (C5). Does the owner want sign-off on a scratch library, or on the real one by choice?**
- **Q5. Does the new order apply to PR #49?** `feature/viewport-render-1to1` was opened under the old order and is open now. The product manager's prompt says "No pull request exists yet", which is false there. The likely answer is that it finishes under the old order or stays open with a Ship record without a number, but the owner should say.
- **Q6. Do docs-only and process branches, like this one, go through sign-off and Ship?** `WORKFLOW.md` defines only features and bug fixes, step 5 records the sign-off in a `qa.md` such a branch does not have, and step 6's full run proves nothing for them.

## Checked and fine

- Step numbers: code-reviewer, qa-tester and the designer cite step 4, qa-tester step 5, product-manager step 6, and `WORKFLOW.md`'s bug-fix paragraph step 6. No stale reference in `CLAUDE.md` or any prompt.
- No remaining "open the pull request" before review, "CI is green" before Ship, or PR number in `WORKFLOW.md`, the prompts' Ship text or the PRD template. `apple-ui-designer.md` needed no change. The PR numbers in `CLAUDE.md`'s "Scope so far" are historical, and the product manager's "never write a PR number" stops new ones copying them.
- Pushing a feature branch runs no CI: `build.yml` pushes only on `develop` and `master`, and `codeql.yml` only on `master`.
- Glob patterns: `**.md` matches at any depth (GitHub's own cheat sheet, `**.js`), and `docs/**` and `.claude/**` are right. A workflow is skipped only when every changed file matches, and a pull request's list is the whole three-dot diff, so a Ship commit on a PR with code still runs CI. `build.yml` itself is not ignored.
- Skipping CI hides no failure on those paths. `RepositoryFiles` is called only for `Sources`, `Scripts`, `Support`, `Sources/PhotoApp/Model` and the three UI targets, plus the golden and fixture folders under `Tests/`. Mentions of `docs/` in tests and sources are comments. `Package.swift` and `Scripts/` read nothing from `docs/`, `.claude/` or Markdown (`Branding.xcconfig:3` names `RENAMING.md` in a comment). No Markdown file lives in `Sources/` or `Tests/`. `docs/feedback/edge-preserve-upsample/repro.swift` is in no target, and `.claude/settings.json` is not read by the build.
- CI failing after sign-off: step 7 routes the fix through the second pass and to the owner on a behavior change, and "Run Ship again" covers a changed record. A later merge of `develop` is covered by line 20 and reruns CI on push.
- Line 21's "nothing before this step has covered" macOS 26 and 15 is true on this Mac.
- The PR number stays findable from the merge commit when the PR is merged or squashed, as past merges were. The ruleset still allows rebase, which would not carry it; `gh pr list --search <sha>` finds it anyway.
- Sign-off with open checks flows through: `WORKFLOW.md:15-16`, `product-manager.md:26-29`, `qa-tester.md:65` and the reconcile rule at `product-manager.md:96` agree.
- `/security-review` is not needed: no parser, subprocess, file writing or network code in the app changes.

## Follow-up

Second pass, 2026-11-09, on the uncommitted fixes in the same worktree (no commit yet, so the commit column is omitted). Build and tests not run; the two CI step scripts were run locally, as below.

**Result: no Blocker left, and nothing in the fixes contradicts the owner's rulings. Three small items remain worth doing before the PR: C10, the rest of C3, and the rest of C7.** C11, C12 and C2's note are optional.

| # | Status | Note |
|---|--------|------|
| C1 | Fixed | `paths-ignore` is gone. The job always runs under its matrix name, so both required contexts report on `develop` and `master`. See "CI step logic" below. |
| C2 | Fixed | `WORKFLOW.md:18` sends a failure to the engineer and hand-resolved conflicts to the second pass, before Ship. Not taken, optional: it does not say the run repeats after the fix, or that a behavior change goes back to the owner as step 7 does. Line 14 leaves a later merge of `develop` to CI, which answers the line 22 question. |
| C3 | Partly fixed | `WORKFLOW.md:26` is right. `WORKFLOW.md:81`, cited in the finding as the then line 77, still goes from sign-off to "Run Ship if…" to "Then push and open the pull request", with no merge of `develop` or full run. Line 79, the feature session, has them. |
| C4 | Fixed | Line 14 adds the designer on UI changes; line 17 records owner findings in `status.md`, repeats the second pass and the sign-off of that change, and sends new scope to the product manager; `swift-macos-engineer.md:39` lists the owner. |
| C5 | Fixed | Line 15 requires an exact command with `--library-root` on a scratch library, and states that the owner's own library is by choice and that a branch's migrations can't be undone on it. |
| C6 | Fixed | The retry in `build.yml:87-96` and line 23. Its two signatures cover all five crashing runs, including 42296234649, whose line ends "exited with unexpected signal code 11". |
| C7 | Partly fixed | Line 17 now has the main session commit the record. The record still has no commit of what was signed off (`WORKFLOW.md:17`, `qa-tester.md:65`), so it can't say which build the owner saw. |
| C8 | Fixed | `code-reviewer.md:59`, "ready for the next step". |
| C9 | Fixed | `qa-tester.md:70` names Ship after the sign-off is recorded. |

### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C10 | Should fix | `.github/workflows/build.yml:43` | `git diff --name-only` follows renames and lists only the new path, so a file moved from a code path into `docs/` looks docs-only. | Shown in a scratch clone: `git mv Sources/PhotoFixtures/FringeScene.swift docs/archive/moved.swift` lists only `docs/archive/moved.swift`, the step prints `code=false`, nothing builds, and both required checks pass with a source file gone from its target. `--no-renames` lists both paths, so the step would print `code=true`. Fix: add `--no-renames`. | Owner ruling 1, "docs-only" |
| C11 | Nit | `.github/workflows/build.yml:106-123` | "Collect crash reports" and its upload run on `failure()` only, and a retried run that passes is a success. | The first crash's `.ips` files are never kept when the retry passes, and most crashes will now end that way. The comment at line 107 says they are for crashes inside Apple's frameworks, which is this crash. The backtrace stays in the log, so roadmap ci-test-crash loses only the system report. Fix if wanted: set an output on retry and add it to those two conditions. | Owner ruling 2 |
| C12 | Nit | `docs/WORKFLOW.md:3` | "Do not skip steps other than those a bug fix skips" now disagrees with the new Docs and process paragraph at line 28, which skips QA, sign-off and Ship. | Someone reading the opening line would hold a roadmap-only change for QA. Fix: add "or a docs and process change". | Owner ruling 4 |

### CI step logic (the points asked about)

Run locally: the two step scripts cut from `build.yml`, the Detect step under `bash -e` and the Test step under `bash --noprofile --norc -eo pipefail` (what `shell: bash` gives), with shallow clones made as `fetch-depth: 2` does.

- **Pull request merge commit.** Depth 2 fetches the merge commit and both parents. `HEAD^1` is the base, so the diff is what the PR adds. Merge of PR #46 (docs only, 2 files): `code=false`. Merge of PR #48 (71 files): `code=true`.
- **Push to `develop`.** A merge or squash has `HEAD^1` as the previous tip, which is right. A rebase merge, which the ruleset still allows, compares only its last commit, which under the new order is the docs-only Ship commit, so that develop run would skip; the PR's own run had built it, and past merges are merge commits. No action needed unless rebase merging starts.
- **Fails safe.** No parent, a failed `git diff`, an empty diff, `workflow_dispatch`, and quoted non-ASCII paths all give `code=true`.
- **Skipped steps and the job result.** Every build step's `if` skips cleanly, and skipped steps leave the job as success, which GitHub's docs count as passing a required check. Because the skip is per step, the job still runs and `matrix.os` expands in the check name.
- **`if: failure()` steps.** With the build skipped no step has failed, so they are skipped too. `Build app bundles` keeps its implicit `success()`, so it does not run after a failed Test.
- **Test step.** Exit status comes through `tee` because `shell: bash` sets `pipefail`. Pass: 1 run, exit 0. Plain failure: 1 run, exit 3. Signal then pass: 2 runs, exit 0. Signal twice: 2 runs, exit 1. Another signal (code 5): 1 run, exit 1.
- **Not yet seen on GitHub.** This branch changes `build.yml`, so its own PR takes the `code=true` path. The docs-only path first runs on the next docs-only PR; check that one reports both checks.

### Answers to the questions

Owner's rulings:

- **Q1:** option (b), as built.
- **Q2:** `swift test` retries once in the same step on `Signal 11: Backtracing` or `unexpected signal code 11`; other failures fail at once.
- **Q4:** scratch library by default, with an exact `--library-root` command; the owner may choose a copy or the real library.
- **Q6:** docs and process changes go straight to a PR with no QA, sign-off or Ship, with code review only when they touch `.claude/agents/`, `docs/WORKFLOW.md` or CI.

Decided by the main session, reasons given, not owner rulings:

- **Q3:** no macOS 15 run before sign-off, because `gh workflow run` would be a second full CI round; the owner was told a macOS 15 failure first shows after sign-off.
- **Q5:** PR #49 finishes under the order it started with; the new order applies to branches with no PR yet. If #49 runs Ship after this merges, the product manager's new prompt will say no PR exists, so tell it otherwise.

Correction to C6: the two red runs I could not explain (42465473912 and 42131457451) and the macOS 15 leg of 42663678027 are not the crash. Their logs show test files failing to compile ("unable to type-check this expression in reasonable time"). The retry rightly does not touch those.

Still for the product manager, non-blocking: `docs/roadmap.md:316` (ci-test-crash) should note the retry, since it hides most crashes from the run's result. `docs/features/_inventory.md:235` should say documentation-only changes report success without building. The third item in the earlier list stands.

### Third pass

2026-11-09, on the uncommitted working tree on dfa0d5c (no commit yet, so the commit column is omitted). Limited to the items below. Build and tests not run: nothing in `Sources/` or `Tests/` changed.

**Result: all five items are confirmed and there are no new findings.** C11 and the product manager's notes stay as decided and were not re-reviewed.

| # | Status | Note |
|---|--------|------|
| C10 | Fixed | `build.yml:44` has `--no-renames`, explained at lines 39-40. Reran `test_detect.py`, which cuts the step's script from `build.yml`: moves from `Sources/` into `docs/` and to a `.md` name give `code=true` (`code=false` without the flag); a move from `docs/` into `Sources/` and a source edit give `code=true`; a move within `docs/` and a docs edit give `code=false`. |
| C3 | Fixed | `WORKFLOW.md:81` merges `develop` and runs the full tests and bundle build "whether or not Ship applies", then Ship if it applies. Line 26 says the same. |
| C7 | Fixed | `WORKFLOW.md:17` and `qa-tester.md:65` both list the commit signed off in the record. |
| C12 | Fixed | `WORKFLOW.md:3` names docs and process changes and points to their paragraph at line 28. |
| C2 (optional note) | Fixed | `WORKFLOW.md:18` repeats the full run after a fix and sends a behavior change back to the owner. This agrees with step 7 (line 23, "back to the owner only if it changes behavior"), with line 17, and with step 4's second pass (line 14), which still applies to the fix. Line 14 leaving a clean merge of `develop` to "the full run before Ship and CI" also still holds. |
