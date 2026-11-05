## Workflow

Features move through three agents in order. Do not skip steps, and do not do one agent's job from another.

1. **product-manager** turns an idea into requirements. It writes `docs/features/<slug>/prd.md` and maintains `docs/roadmap.md`. For a thin idea it returns questions first.
2. **apple-ui-designer** designs against the PRD, following Apple's Human Interface Guidelines. It writes `docs/features/<slug>/design.md`.
3. **swift-macos-engineer** implements against the PRD and design, writes tests for the acceptance criteria, and keeps `docs/features/<slug>/status.md` current.
4. **Review:** after implementation, the designer reviews the result against `design.md` and the acceptance criteria.

### Ownership

| File | Owner | Others |
|------|-------|--------|
| `docs/roadmap.md` | product-manager | read-only (designer may set a feature to Designed) |
| `docs/features/<slug>/prd.md` | product-manager | read-only |
| `docs/features/<slug>/design.md` | apple-ui-designer | read-only |
| `docs/features/<slug>/status.md` | swift-macos-engineer | read-only |

Slugs are kebab-case. A whole-app redesign is a feature: `docs/features/ui-redesign/`.

### Questions go back to the owner

Agents cannot call each other, so the main session relays.

- The engineer returns **Design questions** for the designer and **Requirements issues** for the product manager.
- The designer returns **Requirements issues** for the product manager.
- The main session takes each to the owning agent, which records the ruling in its own file. Then resume the agent that was blocked.
- No agent resolves another agent's question by guessing. If the owner (the human) is needed, ask them.

### Build

- `swift build` and `swift test`.
- `Scripts/build-app.sh` assembles the `.app` bundle.
- There is no Xcode project. Do not use `xcodebuild` or SwiftUI previews to verify work.

### Rules

- Requirements live in `prd.md`, UI decisions in `design.md`, progress in `status.md`. Not in code comments or chat.
- Every acceptance criterion maps to a test or an explicit manual check.
- Prefer system components. Custom chrome needs a written justification in `design.md`.
- Keep the roadmap's Now column to three items or fewer.
- Treat `.claude/agents/` files like source code: changes go through review.

### Typical session

Start a feature by asking the product-manager agent to take the idea. After the PRD exists, ask apple-ui-designer to design it. When `design.md` is done, ask swift-macos-engineer to implement. Finish with a designer review.
