---
name: feature-workflow
description: Use when implementing any non-trivial feature or mechanic - gathers context, researches how shipped games solve the same problem, writes a plan, gets it reviewed by an independent subagent, and only implements after approval. Skip for one-line fixes.
---

# Feature Workflow

The pipeline for adding a mechanic or feature to this game. It exists because an unattended
agent's most expensive failure is not bad code — it is confidently building the *wrong thing*
for five hours. Every stage below produces a **file on disk**, so a human reading the morning
report can see what was decided and why, and so a cycle that runs out of budget mid-feature can
be resumed by the next one.

## Proportionality — pick a track first

Do not run the full pipeline on small work. Decide honestly:

| Track | When | Stages |
|---|---|---|
| **A — Full** | New mechanic, new system, anything touching more than ~3 files, anything with design choices a reasonable person could disagree about | 1 → 7 |
| **B — Direct** | Bug fix, stale reference, rename, tuning an existing value, adding a test | Stages 5 → 7 only |

If you are unsure which track applies, it is Track A. Record the choice and the reason in the
plan file (Track B: state it in your report instead).

---

## Stage 1 — Gather context

Read before searching the web. You cannot judge whether an industry pattern fits until you know
what is already here.

- Read `CLAUDE.md`, `docs/architecture/PROJECT.md`, and the module doc(s) for the modules involved.
- Find the code that already does something adjacent. This project favours **composition** —
  there is a real chance the feature is mostly assembling existing `global/components/`.
- List what already exists that you should reuse, with file paths. Explicitly note anything you
  are tempted to write that already exists.

## Stage 2 — Research how shipped games solve it

Use WebSearch. The goal is *not* to copy an implementation — it is to learn the failure modes
other developers hit, so the plan avoids them.

- Search for the mechanic by its real name (e.g. "coyote time", "input buffering", "hitstop",
  "bullet hell spawn patterns", "isometric depth sorting").
- Prefer postmortems, GDC talks, engine docs, and developer writeups over listicles.
- Capture **3–5 concrete findings**, each with a source URL and, critically, the *tradeoff* it
  implies. A finding without a tradeoff is trivia.
- Note typical parameter values where they exist (e.g. coyote time is usually 80–150ms). These
  become your starting defaults instead of guesses.

If WebSearch is unavailable or returns nothing useful, say so plainly in the plan and proceed —
do not fabricate sources or invent "industry standard" numbers.

## Stage 3 — Write the plan

Write to `docs/plans/<slug>.md` (create the directory if needed). `<slug>` is kebab-case, derived
from the backlog item. Use this structure:

```markdown
# <Feature>

**Track:** A
**Backlog item:** <verbatim from BACKLOG.md>

## Problem
What the player experiences today, and what should change. Player-facing, not code-facing.

## Existing code to reuse
| Path | What it gives us |

## Research findings
| Finding | Tradeoff | Source |

## Design
The chosen approach, and the alternatives rejected with reasons.
Name real files, real nodes, real signals.

## Build sequence
Ordered steps, each independently testable.

## Test plan
The GUT tests that will prove this works, named, with the specific cases —
including at least one boundary/edge case.

## Risks
What could break, and what you will check.

## Out of scope
What you are deliberately not doing.
```

## Stage 4 — Independent review (blocking)

Dispatch a **subagent** (Task tool, `subagent_type: general-purpose`) to review the plan. Give it
the plan file path and this instruction — it must be able to genuinely say no:

> You are reviewing an implementation plan for a Godot 4.6 game. Read `docs/plans/<slug>.md`,
> then read the actual code it references — do not take the plan's claims about the codebase on
> trust. You are the last check before hours of unattended implementation.
>
> Reject or request changes if any of these hold:
> - The plan reinvents something that already exists in `global/components/` or elsewhere.
> - It contradicts a convention in `CLAUDE.md` (composition over inheritance, config-driven
>   `.tres` stats, 640x360 design-space coordinates scaled by `ArenaCamera.WORLD_SCALE`).
> - The test plan cannot actually fail — it asserts nothing meaningful, or has no edge case.
> - The design has an unexamined alternative that is plainly simpler.
> - The research section has no tradeoffs, or cites sources that do not support the claims.
> - The scope is too large to finish and verify in one session.
>
> Write your verdict to `docs/plans/<slug>.review.md`, beginning with exactly one of:
> `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or `VERDICT: REJECTED`.
> Then list findings, each with the file and line you checked. Approving a plan with real
> problems is a worse outcome than rejecting a good one — do not rubber-stamp.

**The gate:**

- `APPROVED` → proceed to Stage 5.
- `CHANGES_REQUESTED` → revise the plan, re-review. **Maximum two rounds.**
- `REJECTED`, or still not approved after two rounds → **stop. Do not implement.** Commit the
  plan and reviews, write the disagreement in your report, and move to the next backlog item.
  A cycle that produces a well-researched rejected plan is a *successful* cycle.

Never review your own plan and call it approved. The review file must exist and must come from
the subagent.

## Stage 5 — Implement

- Tests first, from the plan's test plan. Watch them fail before you make them pass.
- Follow the build sequence. If reality contradicts the plan, update the plan file to match what
  you actually did — a stale plan is worse than none.
- Keep to Out of scope. Discovered work goes to `BACKLOG.md` under *Discovered*, not into this change.

## Stage 6 — Verify

Run the real gate. Do not claim success without it:

```bash
bash /agent/verify.sh
```

This imports the project, boots it headless (autoloads + main scene), and runs the GUT suite. If
it fails, fix it now — a red gate means the next cycle is spent repairing instead of building.

For anything with visible behaviour, also run the scene headless and check the output:

```bash
godot --headless --path /work/repo <scene or test script>
```

## Stage 7 — Document and report

- Invoke the **`updating-project-docs`** skill if the change was structural. This is required by
  `CLAUDE.md`, not optional.
- Tick the item in `BACKLOG.md`; add anything discovered.
- In your report, link the plan and review files and state the verdict verbatim.

---

## Anti-patterns

- **Skipping review because the plan "is obviously fine."** The review exists precisely for plans
  that feel obviously fine.
- **Treating the reviewer as a formality.** If every plan is approved first time, the reviewer
  prompt is not being followed.
- **Researching after designing.** Then the research is just justification for a decision already made.
- **Planning a feature so large it cannot be verified in one session.** Split it in `BACKLOG.md`
  and build the first piece.
