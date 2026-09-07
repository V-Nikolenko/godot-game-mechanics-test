# Epic preparation

Loaded when your work item has `kind: "prep"`. Turning a rough idea into an epic the user can
actually decide on happens in four steps, each a separate iteration with its own model and its own
artifact:

```
TRIAGE  ->  RESEARCH  ->  PLAN  ->  PLAN REVIEW  ->  the user decides
```

You are doing **one** of these — the one named by your item's `type`. Do not run ahead into the
next stage even if it looks quick: each is a fresh session with a clean context on purpose, and the
artifacts are how they hand off.

Everything lives in the epic's `prepDir` (`docs/plans/<epicId>/`), which is on your work item.

---

## TRIAGE (work item `kind: "idea"`)

The user submitted a rough idea through the web UI — a sentence or two, not a spec. Your job is to
decide what epic it should become, and nothing more.

1. **Read the idea.** It is in your work item, verbatim.
2. **Read the actual code** for what it would build on. A draft that reinvents an existing system
   wastes the user's review time as much as a bad plan would. This project favours composition —
   the answer is often "assemble existing `global/components/`".
3. **Decide: epic, or not.**
   - Already shipped, a duplicate of a live epic, or something the code shows is already possible:
     `./scripts/backlog-cli.js ideas reject <ideaId>` with the reason on stdin. Closing an idea
     honestly is a good outcome; drafting an epic for work that already exists is not.
   - Otherwise, draft it:

```bash
echo '{"title": "<epic title>", "ideaId": "<ideaId>", "summary": "<one paragraph>"}' \
  | ./scripts/backlog-cli.js draft-epic
```

The `summary` is what the research stage starts from: say what the user seems to want, what you
found that it would build on, and what the open question is. One paragraph, not a plan.

`draft-epic` creates the research, plan and plan-review tasks itself and links the idea to the
epic. **Do not write implementation tasks** — they come out of the reviewed plan, three stages
later. That ordering is the whole point: implementation tasks written off a one-sentence idea are
guesses wearing a checklist's clothing.

4. **Stop.** Do not start the research in the same iteration.

---

## RESEARCH (`type: "research"`)

Investigate as a professional game developer and software engineer would, before anything is
designed. Two outputs.

### `1-context.md` — what is already here

Read the code first. You cannot judge whether an industry pattern fits until you know what exists.
Read `CLAUDE.md`, `docs/architecture/PROJECT.md`, and the module docs involved.

```markdown
# Context
## Modules and files involved
| Path | What it does | Why it matters here |
## Existing code to reuse
| Path | What it gives us |
<be specific - this table is what stops the plan reinventing things>
## Conventions that constrain this
<coordinate space, config-driven .tres, state machine style, autoload contracts>
## Dependencies and blast radius
<what else changes if this changes>
## Risks, edge cases, testing requirements
## Open questions for the plan
```

### `2-research.md` — how shipped games solve it

Use WebSearch. The goal is not to copy an implementation — it is to learn the failure modes other
developers hit, so the plan avoids them.

- Search the mechanic by its real name ("coyote time", "input buffering", "hitstop", "bullet hell
  spawn patterns", "boss telegraph timing").
- Prefer postmortems, GDC talks, engine docs and developer writeups over listicles.
- Capture **3 to 5 findings**, each with a source URL and the **tradeoff** it implies. A finding
  without a tradeoff is trivia.
- Record typical parameter values where they exist — these become starting defaults instead of
  guesses.

Write it as a table: `| Finding | Tradeoff | Typical values | Source |`.

### When WebFetch is blocked — do NOT give up on the source

Many of the best sources are game-dev forums and blogs that return **403 to automated clients**
while being perfectly public in a browser. A 403 says nothing about whether the page is worth
reading, and abandoning it throws away exactly the practitioner detail this stage exists to find.

**Never treat a WebFetch 403/401/429/empty result as the end of that source.** Retry through:

```bash
./scripts/fetch-page.sh "<url>" /tmp/source.md
```

It tries a real browser User-Agent first, then a reader proxy that renders the page and returns
markdown. This recovers most "blocked" pages — it was added precisely because a bullet-hell boss
guide 403'd and turned out to contain concrete, directly usable numbers.

- Do not re-issue the identical `WebFetch` call after it fails; go straight to the script.
- The reader proxy sends the URL to a third party. Fine for public docs, blogs and forums.
  **Never use it for private, internal, authenticated, or credential-bearing URLs.**
- If the script also fails, *then* the source is genuinely unreachable — record that and move on.

If a whole topic yields nothing, say so plainly, base the findings on the codebase plus your own
knowledge of the genre, and **label that as a judgement call**. **Never fabricate sources, invent
quotes, or attach plausible-looking numbers to a URL you could not actually read.**

### Subagents

Worth dispatching up to two in parallel here — one sweeping the codebase for reusable pieces, one
on the web research — because they are genuinely independent and each would otherwise fill this
session's context with material the other does not need. Merge their findings yourself; do not
paste two reports end to end and call it research.

---

## PLAN (`type: "plan"`)

Two deliverables, and the second matters as much as the first.

**If your work item has `feedback`, read it first.** The user saw a previous version of this plan
and sent it back in their own words. Address every point explicitly — a revision that quietly
ignores half the comment gets sent back again, at full cost.

### `3-plan.md`

Build on `1-context.md` and `2-research.md`. Do not re-derive them.

```markdown
# <Epic>
## Problem
What the player experiences today and what should change. Player-facing, not code-facing.
## Design
The chosen approach, and alternatives rejected with reasons. Real files, nodes, signals.
## Build sequence
Ordered steps, each independently testable and each small enough to finish and verify in one
session. This ordering becomes the task list below, so make it real.
## Test plan
The GUT tests that will prove this works, named, with specific cases - including boundary cases.
## Risks
## Out of scope
## Response to feedback
<only when this is a revision: each point the user raised, and what changed>
```

### The implementation tasks

Then turn the build sequence into real tasks:

```bash
./scripts/backlog-cli.js add-task <epicId> "<player-facing outcome>" \
  --type feature|bug|refactor|test|art|chore \
  --complexity small|medium|large \
  --depends-on <taskId>,<taskId>          # optional
```

(body on stdin — what "done" looks like, and which files it touches.)

This list is what the user reads and prioritises, so:

- **Each task states a player-facing outcome**, not an implementation step. Not "add a timer" —
  "dashing off a ledge should still work if you press it a moment late".
- **Each task must be finishable and verifiable in one session.** If it is not, split it.
- **Complexity is the honest estimate, not a default.** It picks the workflow track and the model
  the task runs on: `small`/`medium` go straight to implement-and-test on sonnet; `large` gets its
  own plan and an independent review on opus. Marking real system work `small` is how untested
  architecture gets shipped; marking a typo `large` is how a window gets burned.
- **Dependencies only where the order genuinely matters.** A task that depends on an unfinished one
  is not workable, so a wrong dependency stalls the epic.
- Do not over-specify. Each task gets its own context pass when it is worked; leave it room.

---

## PLAN REVIEW (`type: "plan-review"`)

Dispatch a **subagent** (Task tool, `subagent_type: general-purpose`) with the prompt below. It
must be able to genuinely say no. Never review your own plan and call it approved — the verdict
file must come from the subagent.

Then apply the verdict:

- `APPROVED` → `./scripts/backlog-cli.js set-state <taskId> done`. That sends the epic to the user
  for approval; **do not implement anything from it.**
- `CHANGES_REQUESTED` → revise `3-plan.md` and the task list, re-review. **Maximum two rounds**,
  appended to `4-review.md`, never overwritten.
- `REJECTED`, or not approved after two rounds → do not mark the review done. `set-badge <taskId>
  stuck` and report it, so the user sees an epic that needs their input rather than one that
  silently stalled.

### Reviewer prompt

> You are reviewing an implementation plan for a Godot 4.6 game, and the task breakdown generated
> from it. Read `docs/plans/<epicId>/3-plan.md` and its siblings `1-context.md` and `2-research.md`,
> run `./scripts/backlog-cli.js epic show <epicId>` to see the tasks, then read the **actual code**
> they reference — do not take the plan's claims about the codebase on trust. You are the last
> check before hours of unattended implementation.
>
> Request changes or reject if any of these hold:
> - It does not actually solve the original idea (quoted in the epic's research task body).
> - It reinvents something that already exists in `global/components/` or elsewhere.
> - It contradicts a convention in `CLAUDE.md` (composition over inheritance, config-driven `.tres`
>   stats, 640x360 design-space coordinates scaled by `ArenaCamera.WORLD_SCALE`).
> - The test plan cannot actually fail — it asserts nothing meaningful, or has no edge case.
> - There is an unexamined alternative that is plainly simpler, or unnecessary architectural churn.
> - The research has no tradeoffs, or cites sources that do not support the claims.
> - **The task decomposition is wrong**: a task that cannot be finished and verified in one
>   session, a task that is really three, or an ordering that will not work.
> - **A complexity or model assignment is wrong** — system or cross-cutting work marked
>   small/sonnet, or a trivial change marked large/opus.
> - **Dependencies are missing or wrong** — two tasks that will collide, or a chain that stalls.
> - Tests are missing for something that can regress.
>
> Write your verdict to `docs/plans/<epicId>/4-review.md`, beginning with exactly one of:
> `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or `VERDICT: REJECTED`.
> Then list findings, each naming the file and line you checked, and for task-level findings the
> task id. Approving a plan with real problems is worse than rejecting a good one — do not
> rubber-stamp.
