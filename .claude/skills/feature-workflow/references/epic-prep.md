# Epic preparation

Loaded when your work item's kind is `prep`. Turning a rough idea into an epic the owner can
actually decide on happens in stages, each a separate run with its own model and its own artifact:

```
TRIAGE  ->  RESEARCH  ->  PLAN  ->  PLAN REVIEW  ->  the owner decides
(AI-Kanban)   (you: one of these three, named by your item's type)
```

**Triage is not yours.** AI-Kanban runs it as a read-only session when an idea is submitted, and
its code — not the model — creates the epic and the three prep tasks. By the time you run, the
epic exists: its description is the triage summary, and the prompt quotes the **Original idea**.

**Attached documents.** When the owner attached `.md` files to the idea, your prompt carries them in
full under *Attached documents*. They are the owner's detailed spec and outrank the one-line idea
and the triage summary. Every stage works from them:

- **Research:** list every concrete requirement, constraint and open question the documents state
  (in `1-context.md` under *Requirements from the attached documents*, each quoted briefly with the
  document name) and research the ones that need it. Where the documents reference existing code
  or docs (e.g. `docs/enemy-rework/current-enemies.md`), read those too.
- **Plan:** add a *Requirements coverage* table to `3-plan.md` — each requirement → the task key(s)
  in `tasks.json` that deliver it, "later phase N" when another phase owns it, or "out of scope"
  with the reason. Nothing may be silently dropped.
- **Review:** pass the documents to the reviewer along with the idea (see below).

**Phases.** A large idea is split into an ordered chain of phase epics that share one idea
folder, `docs/ideas/<idea id>/`: the attached documents and `DECISIONS.md`, the running log of
decisions every phase must respect. Phase N only starts once phase N-1 is implemented. When your
prompt has a *Phase X of N* section:

- **Stay inside your phase's scope.** Plan and create tasks only for what the scope names;
  requirements owned by other phases go in the coverage table as "later phase N", not into tasks.
- **Build on earlier phases, don't redo them.** Before anything else read `DECISIONS.md` and each
  earlier phase's `3-plan.md` (paths are in the prompt), and read the code they produced. Never
  contradict a recorded decision silently — if one must change, say so explicitly in `3-plan.md`
  and in the decision log.
- **Plan stage: append to `DECISIONS.md`** (never rewrite earlier sections) a
  `## Phase N - <title> (<date>)` section with what later phases must know: architecture choices,
  conventions, names and interfaces they will build on, and what was deliberately deferred.

You are doing **one** stage — the one named by your item's type. Do not run ahead into the next
stage even if it looks quick: each is a fresh session with a clean context on purpose, and the
artifacts are how they hand off.

Everything lives in the **epic plan directory** from your work item (`docs/plans/<Epic ID>/` for
new epics). The harness reads the files named below after your run; **their exact names and shapes
are a contract** — a missing or malformed file fails the run.

**Prep is documents only.** Prep runs skip the project's verification gate (`/agent/verify.sh`), so
they may only change files under the epic plan directory (and, for an idea's phases, the shared
docs/ideas/<idea id>/ folder) — touching any other file fails the run and
nothing is committed. Don't run the gate yourself either; read code, don't change it. Your final
message is shown to the owner on the task, and the plan directory's documents appear in AI-Kanban
under the epic's *Plan documents*.

---

## RESEARCH (type `research`)

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

When both files are written, finish. The harness marks the research done and the epic moves on to
planning.

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

## PLAN (type `plan`)

Two deliverables, and the second matters as much as the first.

**If the prompt has Human Feedback, or the plan directory has a `4-review.md`, read them first.**
Someone saw a previous version of this plan and sent it back. Address every point explicitly — a
revision that quietly ignores half the comment gets sent back again, at full cost.

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
<only when this is a revision: each point raised, and what changed>
```

### `tasks.json` — the implementation tasks

Turn the build sequence into real tasks. The harness validates this file after your run and creates
the tasks on the board (replacing any earlier proposal for this epic that has not started):

```json
{
  "tasks": [
    {
      "key": "t1",
      "title": "<player-facing outcome, max 200 chars>",
      "description": "<what done looks like, and which files it touches>",
      "acceptanceCriteria": "<optional: checkable conditions>",
      "type": "feature",
      "complexity": "medium",
      "dependsOn": []
    },
    { "key": "t2", "title": "...", "type": "test", "complexity": "small", "dependsOn": ["t1"] }
  ]
}
```

- 1 to 30 tasks. `key` is any short unique label, used only for `dependsOn` inside this file.
- `type`: `feature` | `bug` | `refactor` | `test` | `art` | `chore`.
  `complexity`: `small` | `medium` | `large`.
- `dependsOn` lists other keys in this file; no cycles.
- Write it with a tool that produces valid JSON (e.g. build it in a script and `JSON.stringify`
  it), then re-read it. A malformed file fails the run and the whole stage is retried.

This list is what the owner reads and prioritises, so:

- **Each task states a player-facing outcome**, not an implementation step. Not "add a timer" —
  "dashing off a ledge should still work if you press it a moment late".
- **Each task must be finishable and verifiable in one session.** If it is not, split it.
- **Complexity is the honest estimate, not a default.** It picks the workflow track and the model
  the task runs on: `small`/`medium` go straight to implement-and-test on sonnet; `large` gets its
  own plan and an independent review on opus. Marking real system work `small` is how untested
  architecture gets shipped; marking a typo `large` is how a run gets burned.
- **Dependencies only where the order genuinely matters.** A task that depends on an unfinished one
  is not workable, so a wrong dependency stalls the epic.
- Do not over-specify. Each task gets its own context pass when it is worked; leave it room.

---

## PLAN REVIEW (type `plan-review`)

Dispatch a **subagent** (Task tool, `subagent_type: general-purpose`) with the prompt below, the
epic plan directory filled in, and the **Original idea** and any **Attached documents** from your own prompt pasted at the end —
the subagent cannot see your prompt. It must be able to genuinely say no. Never review your own plan and call it approved — the verdict
must come from the subagent.

Then record its verdict in `review.json` next to `4-review.md`:

```json
{ "verdict": "APPROVE", "findings": "<the reviewer's findings, verbatim>" }
```

`verdict` is `APPROVE`, `CHANGES_REQUESTED` or `REJECT` (the reviewer writes `APPROVED` /
`REJECTED` in `4-review.md`; map them). `findings` is required unless the verdict is `APPROVE`.

**One verdict per run — do not revise the plan yourself.** The harness routes it:

- `APPROVE` → the epic goes to the owner for approval. **Do not implement anything from it.**
- `CHANGES_REQUESTED`, first round → the plan stage runs again in a fresh session, with this
  review to address. That is where the revision happens.
- `REJECT`, or changes requested again → the epic goes to the owner with the findings, so they see
  an epic that needs their input rather than one that silently stalled.

### Reviewer prompt

> You are reviewing an implementation plan for a Godot 4.6 game, and the task breakdown generated
> from it. Read `<epic plan directory>/3-plan.md`, its siblings `1-context.md` and
> `2-research.md`, and the proposed tasks in `tasks.json`, then read the **actual code** they
> reference — do not take the plan's claims about the codebase on trust. You are the last check
> before hours of unattended implementation.
>
> Request changes or reject if any of these hold:
> - It does not actually solve the original idea (pasted at the end of this prompt), or it drops a
>   requirement from the attached documents without listing it as out of scope with a reason.
> - It reinvents something that already exists in `global/components/` or elsewhere.
> - It contradicts a convention in `CLAUDE.md` (composition over inheritance, config-driven `.tres`
>   stats, 640x360 design-space coordinates scaled by `ArenaCamera.WORLD_SCALE`).
> - The test plan cannot actually fail — it asserts nothing meaningful, or has no edge case.
> - There is an unexamined alternative that is plainly simpler, or unnecessary architectural churn.
> - The research has no tradeoffs, or cites sources that do not support the claims.
> - **The task decomposition is wrong**: a task that cannot be finished and verified in one
>   session, a task that is really three, or an ordering that will not work.
> - **A complexity assignment is wrong** — system or cross-cutting work marked small, or a trivial
>   change marked large.
> - **Dependencies are missing or wrong** — two tasks that will collide, or a chain that stalls.
> - Tests are missing for something that can regress.
>
> Write your verdict to `<epic plan directory>/4-review.md`, appending below any earlier round,
> beginning with exactly one of: `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or
> `VERDICT: REJECTED`. Then list findings, each naming the file and line you checked, and for
> task-level findings the task key from `tasks.json`. Approving a plan with real problems is worse
> than rejecting a good one — do not rubber-stamp.
