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
decisions every phase must respect. Phase N only starts once phase N-1 is implemented, and more
phases may be planned later as the chain goes on (the prompt shows the chain so far). When your
prompt has a *Phase X of N* section:

- **Stay inside your phase's scope.** Plan and create tasks only for what the scope names;
  requirements owned by other phases go in the coverage table as "later phase N", not into tasks.
- **Build on what was actually built, not on what was planned.** Before anything else read
  `DECISIONS.md` — especially each earlier phase's *as built* section — each finished phase's
  dossier `docs/epics-done/<epic id>/REPORT.md`, and their `3-plan.md` (paths are in the prompt).
  Then read the code: where the code and the documents disagree, **the code is the truth**. Never
  contradict a recorded decision silently — if one must change, say so explicitly in `3-plan.md`
  and in the decision log.
- **Research: re-validate your scope first.** Your scope was written before the earlier phases
  ran. Check it against the code and the as-built notes: if an earlier phase already did part of it,
  changed the approach it assumed, or left a gap that belongs to you, adjust the scope — and put a
  *Scope check* section at the top of `2-research.md` saying exactly what changed and why, so the
  plan and the owner see it.
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

**If the prompt has a Plan review history (older prompts: Human Feedback), or the plan directory
has a `4-review.md`, read them first.** Someone saw a previous version of this plan and sent it
back. Address every point explicitly — a revision that quietly ignores half the comment gets sent
back again, at full cost.

### `3-plan.md`

Build on `1-context.md` and `2-research.md`. Do not re-derive them.

**The prompt's *Output contract* decides the plan's structure; this section says what goes in it.**
The plan is no longer read whole by the agents that build from it: each task's agent is handed
only the section every task gets and the sections its own task names. So the shape matters:

```markdown
# <Epic>
## Summary for the owner
At most 20 lines, plain language, no file names or task keys: what changes for the player, what
gets built, what is left out, the main risks, and every choice you need the owner to make - each
as a question with the default you took. This is what the owner reads before approving.
## For every task
At most 60 lines: the decisions, names, interfaces and conventions every task of the epic must
follow. Every implementation agent is given this section.
## 1. Problem
What the player experiences today and what should change. Player-facing, not code-facing.
## 2. Design
The chosen approach, and alternatives rejected with reasons. Real files, nodes, signals.
### 2.1 <one part of the design>
### 2.2 <another>
## 3. Build sequence
Ordered steps, each independently testable and each small enough to finish and verify in one
session. This ordering becomes the task list below, so make it real.
## 4. Test plan
The GUT tests that will prove this works, named, with specific cases - including boundary cases.
## 5. Risks
## 6. Out of scope
## 7. Response to feedback
<only when this is a revision: each point raised, and what changed>
```

- **Number every heading after the two opening sections**, and split the design into numbered
  sub-sections by part (`### 2.3 Enemy ordnance`), not into one long section: tasks point at
  sections by number.
- **Make each section readable on its own.** An agent given `2.3` has not seen `2.1`: repeat a
  name or a number rather than writing "as above".
- Put the test rows a task needs where that task can be pointed at them - under its design
  section, or in a numbered sub-section of the test plan - not only in one table for the whole epic.

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
      "dependsOn": [],
      "planSections": ["2.1", "2.3"]
    },
    { "key": "t2", "title": "...", "type": "test", "complexity": "small", "dependsOn": ["t1"], "planSections": ["2.3", "4.2"] }
  ]
}
```

- 1 to 30 tasks. `key` is any short unique label: it is used for `dependsOn` in this file, and it
  is how the plan, the review and the task's own prompt refer to the task afterwards - use the
  same keys in `3-plan.md`.
- `planSections`: **for every task**, the headings of `3-plan.md` it builds from, by number
  (`"2.3"`) or opening words; a heading brings everything under it; at most 12. This is all of the
  plan the task's agent is given, besides *For every task* - so list every section it needs (its
  design, its interfaces, its test rows) and nothing it doesn't. A task with the wrong sections
  builds from the wrong text; the plan review checks them.
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
{ "verdict": "APPROVE", "findings": "<the findings, written for the owner - see below>" }
```

`verdict` is `APPROVE`, `CHANGES_REQUESTED` or `REJECT` (the reviewer writes `APPROVED` /
`REJECTED` in `4-review.md`; map them). `findings` is required unless the verdict is `APPROVE`.

**The owner reads `findings` on the board and decides from it**, so it is not the review pasted
whole. Write it in Markdown, as the prompt's *Output contract* asks: first one short paragraph in
plain language - what is wrong and what you would do, no task keys or file names (in a later
round: how many earlier findings are now resolved); a blank line; a table
`| # | Severity | Problem | Fix | Tasks |` with one row per finding (blocking or minor, a sentence
each); then each finding's detail under its number. The full evidence stays in `4-review.md`.

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
> - **A task's `planSections` are wrong.** The agent that builds a task is given only the plan's
>   `For every task` section and the sections that task lists in `tasks.json` — not the whole plan.
>   For each task ask: with just those, could it be built? A section it needs but doesn't list, a
>   heading that doesn't exist, or a section that only makes sense after reading another one is a
>   finding.
> - Tests are missing for something that can regress.
>
> Write your verdict to `<epic plan directory>/4-review.md`, appending below any earlier round,
> beginning with exactly one of: `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or
> `VERDICT: REJECTED`. Then list findings, each naming the file and line you checked, and for
> task-level findings the task key from `tasks.json`. Approving a plan with real problems is worse
> than rejecting a good one — do not rubber-stamp.
