# A model and effort for each project agent: code review

Owner: code-reviewer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/agent-models-effort`, b71add0..cc5ac3f (one commit).
Build and tests: not run. The diff is the frontmatter of the five files in
`.claude/agents/`; nothing under `Sources/`, `Tests/`, `Scripts/` or
`Package.swift` changed.

No feature folder, PRD or design: a docs and process change. The owner's
decision as relayed by the main session is the spec (engineer and code
reviewer `fable` / `high`; QA and designer `opus` / `medium`; product
manager `sonnet` / `medium`).

## Verdict

Ready for the pull request, on one condition that is being checked
separately: that Claude Code reads an `effort:` key in agent frontmatter
(U1). The diff is exactly the ten lines the owner asked for, the
frontmatter is well formed, and nothing else in the repository contradicts
it. One Nit, and one question for the owner about the product manager.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C1 | Nit | `CLAUDE.md` "Claude Code setup" (the agent table and the paragraph above it; the owner's section) | The split and its reason are recorded only in the commit message. `CLAUDE.md` describes each agent by use and tools and does not say that the agents pin a model and effort, or why (the stronger model where defects are found, a cheaper one for documents). | A sixth agent, or a later edit to one of these, has no stated rule to follow: it copies `model: inherit` from an older file or moves a tier, and no reviewer can say which was meant. Proposed for the owner: one sentence under the table, such as "Each agent sets its own `model` and `effort`: the engineer and code reviewer run on the strongest model at high effort, QA and the designer one tier down, the product manager on the cheapest; a session's own model does not change them." | WORKFLOW Rules: decisions live in files, "not in code comments or chat"; Ownership: agents propose changes to the rest of `CLAUDE.md` |

## Unverified

- **U1. Whether agent frontmatter honors `effort:`, and `fable` as a
  `model:` alias.** Not researched, as instructed. What this checkout
  shows: the installed CLI (2.1.322) lists `fable`, `opus` and `sonnet` as
  aliases for `--model` and `low, medium, high, xhigh, max` as levels for
  `--effort`, so the values are ones the CLI knows; its help says nothing
  about agent files. This review ran as the `code-reviewer` agent from this
  branch: it ran on Fable 5.2 and its shell had `CLAUDE_EFFORT=high`, while
  the owner's settings give Fable `medium` by default. That is consistent
  with the key being read, but does not prove it: the session's own model
  is also Fable, and its effort may have been raised by hand. If the key
  turns out to be ignored, the agents keep the session's effort, as before;
  nothing breaks, but the five `effort:` lines and the commit message would
  then claim something that does not happen, and the lines should come out.
  A check that would settle it: start a session on the default (Fable,
  medium), run `product-manager` on a trivial question, and see that it
  reports Sonnet.

## Questions

For the owner.

- **Q1. Is the product manager's output read closely enough for the
  cheapest tier?** Nothing in its prompt needs a particular model: it has
  no shell and never builds, so there is no conflict in the text. Two
  facts are worth knowing before deciding the split is final.
  1. Ship is the one agent output no other agent reads afterwards. Step
     4's second pass is for commits that change source or tests; Ship
     changes `README.md`, the roadmap, the inventory and `CLAUDE.md`'s
     "Scope so far" and "Not yet" only, and the main session commits it.
     The last two are loaded as instructions by every later agent. The
     prompt's own guards ("Write only what the files show", "Touch no
     other part of `CLAUDE.md`") are the only ones; the owner's reading of
     the pull request is the check.
  2. The reading load is large and grows with every feature. Ship on the
     largest feature so far (`chromatic-aberration`, 272 KB of Markdown)
     plus the roadmap (62 KB), `CLAUDE.md` (31 KB), the inventory (25 KB),
     `docs/WORKFLOW.md` and the README is about 410 KB. A reconcile, which
     reads every feature's `status.md`, `review.md`, `code-review.md` and
     `qa.md`, is about 760 KB of those plus the same 130 KB. Whether that
     fits in one context depends on the window `sonnet` gets here, which I
     did not check; if it does not, the run compacts and writes from a
     summary, which is where "only what the files show" is most at risk.
  Options, if either matters: leave it (the owner reads Ship's diff
  anyway); or keep Sonnet for Intake and Spec and have the main session
  ask for a stronger model when it runs Ship or a reconcile.
- **Q2. Contributors without access to a named model.** `CLAUDE.md` says
  `.claude/` is checked in "so every contributor starts from the same
  baseline". With `inherit` an agent ran on whatever the contributor had;
  now the engineer and code reviewer ask for `fable`. What Claude Code does
  when an account cannot use an alias (falls back, or fails the agent) is
  not something I checked. It does not matter while the owner is the only
  contributor.

## Checked and fine

- **Only those lines changed.** `git diff b71add0...cc5ac3f`: five files,
  ten insertions, five deletions; in each, `model: inherit` became one
  `model:` line and one `effort:` line, between `tools:` and the closing
  `---`. No trailing whitespace (`git diff --check` clean), no change to
  `name`, `description`, `tools` or any prompt body.
- **Frontmatter is valid.** Each file still opens with `---`, has five
  `key: value` lines with plain scalar values for the two new ones, and
  closes with `---`. The values match the owner's split agent by agent.
- **Nothing else contradicts it.** No text in `CLAUDE.md`,
  `docs/WORKFLOW.md`, `README.md`, the five prompt bodies,
  `.claude/settings.json` or `.github/workflows/` names a model or an
  effort, or says the agents inherit the session's. The agent table in
  `CLAUDE.md` has no model column to go stale. The only other
  `model: inherit` lines are in `.claude/worktrees/`, which is not tracked
  (`.git/info/exclude`): sessions started in those worktrees keep the old
  behavior until they take `develop`.
- **No local override.** `.claude/settings.json` sets permissions only;
  there is no `.claude/settings.local.json`; no subagent-model variable is
  set in the environment.
- **Workflow.** A change to `.claude/agents/` gets code review and no QA,
  sign-off or Ship (`docs/WORKFLOW.md`, Docs and process changes).
- **Security.** No parser, subprocess, file writing or network code:
  `/security-review` is not needed.

## Follow-up

None yet.
