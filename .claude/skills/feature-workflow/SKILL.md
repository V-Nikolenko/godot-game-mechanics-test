---
name: feature-workflow
description: Use when implementing any non-trivial feature or mechanic - resumable pipeline that gathers context, researches how shipped games solve the problem, writes a plan, gets it reviewed by an independent subagent, and only implements after approval. Every stage checkpoints to disk so an interrupted cycle resumes instead of restarting.
---

# Feature Workflow

The pipeline for adding a mechanic or feature to this game. It exists because an unattended
agent's most expensive failure is not bad code — it is confidently building the *wrong thing*
for five hours.

**Every stage writes a file, and every stage is resumable.** Runs happen in 5-hour windows that
can end mid-feature. Nothing already done may be redone: re-reading the codebase and re-running
the same web searches costs a large part of a window and produces the same answer.

---

## Stage 0 — ALWAYS START HERE: resume or begin

Before anything else, check for work already in progress:

```bash
ls docs/plans/*/STATUS.md 2>/dev/null
```

**If a `STATUS.md` exists with unchecked boxes, you are resuming.** Read it, read the artifacts
of the completed stages, and continue from the **first unchecked stage**. Do not re-gather
context, do not re-run research, do not rewrite an approved plan. The `Next action` line at the
bottom of `STATUS.md` tells you exactly where to pick up.

Only if there is no in-progress plan do you start a new item from `BACKLOG.md`.

### Choosing a track (new work only)

| Track | When | Stages |
|---|---|---|
| **A — Full** | New mechanic or system, more than ~3 files, or any design choice a reasonable person could disagree about | 1 to 7 |
| **B — Direct** | Bug fix, stale reference, rename, tuning an existing value, adding a test | 5 to 7 |

If unsure, it is Track A. Track B needs no plan directory — but if a Track B change fails the
gate twice, promote it to Track A and create one.

### Creating the checkpoint directory

For Track A, your first action is to create `docs/plans/<slug>/STATUS.md` (`<slug>` kebab-case
from the backlog item):

```markdown
# STATUS — <feature name>

**Track:** A
**Backlog item:** <verbatim from BACKLOG.md>
**Started:** <YYYY-MM-DD>

- [ ] 1. Context gathered → `1-context.md`
- [ ] 2. Research done → `2-research.md`
- [ ] 3. Plan written → `3-plan.md`
- [ ] 4. Reviewed and APPROVED → `4-review.md`
- [ ] 5. Implemented → `5-progress.md`
- [ ] 6. Gate green
- [ ] 7. Docs updated, backlog ticked

**Next action:** Gather context (stage 1).
```

**Tick a box the moment its artifact is written, and rewrite `Next action` every time.** If your
window ends, that line is the only thing standing between the next cycle and starting over.

---

## Stage 1 — Gather context → `1-context.md`

Read the code before searching the web. You cannot judge whether an industry pattern fits until
you know what is already here.

- Read `CLAUDE.md`, `docs/architecture/PROJECT.md`, and the module doc(s) involved.
- Find code that already does something adjacent. This project favours **composition** — the
  feature may be mostly assembling existing `global/components/`.

Write `1-context.md`:

```markdown
# Context

## Modules and files involved
| Path | What it does | Why it matters here |

## Existing code to reuse
| Path | What it gives us |
<be specific - this table is what stops the next cycle reinventing things>

## Conventions that constrain this
<coordinate space, config-driven .tres, state machine style, etc.>

## Open questions for research
```

Tick box 1. Update `Next action`.

## Stage 2 — Research how shipped games solve it → `2-research.md`

Use WebSearch. The goal is not to copy an implementation — it is to learn the failure modes other
developers hit, so the plan avoids them.

- Search the mechanic by its real name ("coyote time", "input buffering", "hitstop",
  "bullet hell spawn patterns", "boss telegraph timing").
- Prefer postmortems, GDC talks, engine docs and developer writeups over listicles.
- Capture **3 to 5 findings**, each with a source URL and the **tradeoff** it implies. A finding
  without a tradeoff is trivia.
- Record typical parameter values where they exist — these become starting defaults instead of
  guesses.

Write `2-research.md` as a table: `| Finding | Tradeoff | Typical values | Source |`.

### When WebFetch is blocked — do NOT give up on the source

Many of the best sources are game-dev forums and blogs that return **403 to automated clients**
while being perfectly public in a browser. A 403 says nothing about whether the page is worth
reading, and abandoning it throws away exactly the hard-won practitioner detail this stage exists
to find.

**Never treat a WebFetch 403/401/429/empty result as the end of that source.** Retry it through:

```bash
./scripts/fetch-page.sh "<url>" /tmp/source.md
```

It tries a real browser User-Agent first, then a reader proxy that renders the page and returns
markdown. Read the resulting file. This recovers most "blocked" pages — it was added precisely
because `shmups.system11.org`'s bullet-hell boss guide 403'd, and it turned out to contain
concrete, directly usable numbers.

Notes:
- Do not re-issue the identical `WebFetch` call after it fails; go straight to the script.
- The reader proxy sends the URL to a third party. Fine for public docs, blogs and forums.
  **Never use it for private, internal, authenticated, or credential-bearing URLs.**
- If the script also fails, *then* the source is genuinely unreachable — record that in
  `2-research.md` and move on.

Only after genuinely exhausting a source should you note it as unavailable. If a whole topic
yields nothing, say so plainly, base the plan on the codebase plus your own knowledge of the
genre, and **label that as a judgement call**.

**Never fabricate sources, invent quotes, or attach plausible-looking numbers to a URL you could
not actually read.**

Tick box 2. Update `Next action`.

## Stage 3 — Write the plan → `3-plan.md`

Build on `1-context.md` and `2-research.md` — do not re-derive them.

```markdown
# <Feature>

## Problem
What the player experiences today and what should change. Player-facing, not code-facing.

## Design
The chosen approach, and alternatives rejected with reasons.
Name real files, real nodes, real signals.

## Build sequence
Ordered steps, each independently testable and each small enough to finish and verify.

## Test plan
The GUT tests that will prove this works, named, with specific cases -
including at least one boundary case.

## Risks
What could break and what you will check.

## Out of scope
```

Tick box 3. Update `Next action`.

## Stage 4 — Independent review → `4-review.md` (blocking)

Dispatch a **subagent** (Task tool, `subagent_type: general-purpose`). Give it the plan path and
this instruction — it must be able to genuinely say no:

> You are reviewing an implementation plan for a Godot 4.6 game. Read
> `docs/plans/<slug>/3-plan.md` and its sibling `1-context.md` and `2-research.md`, then read the
> actual code they reference — do not take the plan's claims about the codebase on trust. You are
> the last check before hours of unattended implementation.
>
> Reject or request changes if any of these hold:
> - The plan reinvents something that already exists in `global/components/` or elsewhere.
> - It contradicts a convention in `CLAUDE.md` (composition over inheritance, config-driven
>   `.tres` stats, 640x360 design-space coordinates scaled by `ArenaCamera.WORLD_SCALE`).
> - The test plan cannot actually fail — it asserts nothing meaningful, or has no edge case.
> - There is an unexamined alternative that is plainly simpler.
> - The research has no tradeoffs, or cites sources that do not support the claims.
> - The scope is too large to finish and verify in one session.
>
> Write your verdict to `docs/plans/<slug>/4-review.md`, beginning with exactly one of:
> `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or `VERDICT: REJECTED`.
> Then list findings, each naming the file and line you checked. Approving a plan with real
> problems is worse than rejecting a good one — do not rubber-stamp.

**The gate:**

- `APPROVED` → tick box 4, proceed to stage 5.
- `CHANGES_REQUESTED` → revise `3-plan.md`, re-review. **Maximum two rounds.** Append each round
  to `4-review.md` rather than overwriting — the history matters.
- `REJECTED`, or not approved after two rounds → **stop. Do not implement.** Commit every
  artifact, mark `STATUS.md` as blocked with the reason, and report it. A cycle producing a
  well-researched rejected plan is a **successful** cycle.

Never review your own plan and call it approved. The review file must come from the subagent.

## Stage 5 — Implement → `5-progress.md`

Keep a running log so an interrupted implementation resumes cleanly:

```markdown
# Progress
- [x] Step 1 of build sequence — <what was done, which files>
- [ ] Step 2 — <not started>

**Resume at:** step 2.
**Deviations from plan:** <or "none">
```

- Tests first, from the plan's test plan. Watch them fail before making them pass.
- Update `5-progress.md` after **each build step**, not at the end. A window can end at any moment.
- If reality contradicts the plan, update `3-plan.md` — a stale plan is worse than none.
- Discovered work goes to `BACKLOG.md` under *Discovered*, never silently into this change.

Tick box 5 when the build sequence is complete.

## Stage 6 — Verify

```bash
bash /agent/verify.sh
```

Imports the project, boots it headless (autoloads + main scene), and runs the GUT suite. Fix
failures now — a red gate means the next cycle is spent repairing instead of building.

**Do not delete work to make the gate pass.** If something is genuinely unsalvageable, remove
only that part and say so explicitly in your report.

Tick box 6.

## Stage 7 — Document and report

- Invoke **`updating-project-docs`** if the change was structural — required by `CLAUDE.md`.
- Tick the item in `BACKLOG.md`; add anything discovered.
- In your report, link the plan directory and quote the review verdict verbatim.
- Mark `STATUS.md` complete.

Tick box 7.

---

## Anti-patterns

- **Restarting a stage that already has an artifact.** The single most expensive mistake here.
  Read the file, trust it, move on.
- **Skipping review because the plan "is obviously fine."** The review exists precisely for plans
  that feel obviously fine.
- **Treating the reviewer as a formality.** If every plan is approved first time, the reviewer
  prompt is not being followed.
- **Researching after designing** — then the research is just justification for a decision
  already made.
- **Letting `STATUS.md` go stale.** An unticked box that is actually done, or a wrong
  `Next action`, sends the next cycle to redo hours of work.
