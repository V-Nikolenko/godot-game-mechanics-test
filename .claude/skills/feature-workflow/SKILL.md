---
name: feature-workflow
description: Use at the start of every autonomous work item - routes the item to the right amount of process based on its kind, type and complexity, from the full research/plan/review pipeline for epic preparation down to a direct implement-and-test path for small bugs. Every stage checkpoints to disk so an interrupted cycle resumes instead of restarting.
---

# Feature Workflow

The router for a work item. It exists because an unattended agent has two expensive failure modes,
not one:

- Confidently building the **wrong thing** for five hours.
- Spending a research-plan-review pipeline on a **one-line label fix**.

So the amount of process is matched to the item, and the item already says how much it needs.

**Every stage writes a file, and every stage is resumable.** Runs happen in 5-hour windows that
can end mid-item. Nothing already done may be redone: re-reading the codebase and re-running the
same web searches costs a large part of a window and produces the same answer.

---

## Step 1 — Read your work item

The harness injected it at the top of your prompt as JSON, and already set it `in_progress`. You
do not choose your own work. The fields that matter here:

| Field | What it decides |
|---|---|
| `kind` | `prep` = you are preparing an epic. `impl` = you are building something. |
| `type` | `research` / `plan` / `plan-review` for prep; `feature` / `bug` / `refactor` / `test` / `art` / `chore` for impl. |
| `complexity` | `small` / `medium` / `large` — the main lever on how much process. |
| `reason` | `todo` = fresh. `resume` / `resume-plan` = a previous cycle started this; continue it. |
| `feedback` | Present when the user sent the epic back. Their words, verbatim. Read them first. |

## Step 2 — Route

| Your item | Track | What you do |
|---|---|---|
| `kind: "prep"` | **Preparation** | Read `references/epic-prep.md` and do the one stage named by `type`. |
| `kind: "impl"`, complexity `small` | **Direct** | Implement → test → verify. No plan directory, no subagent. |
| `kind: "impl"`, complexity `medium`, **and `prepDir` is set** | **Direct** | Same, working from the epic's approved plan. |
| `kind: "impl"`, complexity `medium`, **and `prepDir` is `null`** | **Escalated** | See below. |
| `kind: "impl"`, complexity `large` | **Escalated** | Your own plan directory, context → plan → independent review → implement. |

### Why `prepDir: null` matters

The Direct track is cheap **because the thinking was already paid for**: the epic was researched,
planned, reviewed and approved before any of its tasks became workable, and `prepDir` points at
that plan. An epic with `prepDir: null` never went through that — it was hand-made in the web UI,
or predates the preparation pipeline. Its tasks have **no plan behind them at all**.

So a medium task with no `prepDir` is not "cheap work with the thinking done", it is "work nobody
has thought about yet", and it takes the escalated track. Only genuinely `small` items (a typo, a
wrong constant, a stale reference, a missing null check) skip planning on their own merits.

Do not paper over this by inventing a plan and carrying on as if it were approved — write it
properly and get it reviewed, which is exactly what the escalated track is.

**Route on the fields, not on the wording of the task title.** A task called "fix the enemy
spawn bug" marked `large` is an escalated item; one called "rework spawning" marked `small` is a
direct one. If you believe the classification is wrong, say so with `set-meta` (below) rather than
quietly working a different track than the board shows.

---

## Track: Direct

For a small fix, or a medium task whose epic already has an approved plan: a bug fix, a stale
reference, a rename, tuning a value, adding a test, a contained piece the plan already described.

1. **Read the epic's plan.** `<prepDir>/3-plan.md` is the design this task came out of, and it was
   reviewed and approved by the user. **Do not re-derive it and do not redesign it.** If `prepDir`
   is `null` and this item is not genuinely small, you are on the wrong track — go back to the
   routing table.
2. **Write the failing test first**, from the plan's test plan where one exists. Watch it fail.
3. Implement.
4. `bash /agent/verify.sh`.
5. `./scripts/backlog-cli.js set-state <taskId> done`.

No plan directory. No research stage. No subagent review. The epic's preparation already paid for
those, and paying twice is exactly the waste this track exists to stop.

### When to abandon this track

Escalate the moment any of these turn out to be true — do not push on:

- The fix requires changing project structure, an autoload's contract, or a shared component.
- It touches three or more systems, or a dependency.
- The obvious fix would break something the plan did not consider.
- **The gate has failed twice on this item.**

Escalating is one command, and it is not a failure — it is the system working:

```bash
./scripts/backlog-cli.js set-meta <taskId> --complexity large --model opus
```

Then say so in your report and **stop for this iteration**. The next one restarts on opus with the
escalated track. Do not try to do architectural work on the model that was budgeted for a typo.

---

## Track: Escalated

For `complexity: "large"` implementation: a new mechanic or system, more than ~3 files, or any
design choice a reasonable person could disagree about.

### Create the checkpoint directory first

Use the **exact** `taskId` from your work item as the directory name — never re-derive or reword
it. This is the join key the web UI uses to show a task's artifacts, so a mismatch makes them
invisible in the UI even though the files exist.

```markdown
# STATUS — <feature name>

**Track:** Escalated
**Task:** <taskId> (epic: <epicId>)
**Item:** <head, verbatim>
**Started:** <YYYY-MM-DD>

- [ ] 1. Context gathered → `1-context.md`
- [ ] 2. Plan written → `3-plan.md`
- [ ] 3. Reviewed and APPROVED → `4-review.md`
- [ ] 4. Implemented → `5-progress.md`
- [ ] 5. Gate green
- [ ] 6. Docs updated, task ticked

**Next action:** Gather context.
```

**Immediately after creating the directory:**
`./scripts/backlog-cli.js set-plandir <taskId> docs/plans/<taskId>`. This is what lets a later
cycle find this task's `STATUS.md` and resume it if the current iteration is interrupted — skip it
and a crashed run's `in_progress` task is invisible to resume detection and gets silently
abandoned rather than picked back up.

**Tick a box the moment its artifact is written, and rewrite `Next action` every time.** If your
window ends, that line is the only thing standing between the next cycle and starting over.

### 1. Context → `1-context.md`

Read the code before anything else. Start from the epic's `2-research.md` if it has one — that
research was done for this epic and is yours to use, not to repeat.

```markdown
# Context
## Modules and files involved
| Path | What it does | Why it matters here |
## Existing code to reuse
| Path | What it gives us |
<be specific - this table is what stops the next cycle reinventing things>
## Conventions that constrain this
<coordinate space, config-driven .tres, state machine style, etc.>
```

Only search the web if the epic's research did not cover this and the question is genuinely a
genre/design one. If you do, `references/epic-prep.md`'s research rules apply, including the
never-abandon-a-403 rule.

### 2. Plan → `3-plan.md`

```markdown
# <Feature>
## Problem
What the player experiences today and what should change. Player-facing, not code-facing.
## Design
The chosen approach, and alternatives rejected with reasons. Real files, nodes, signals.
## Build sequence
Ordered steps, each independently testable and small enough to finish and verify.
## Test plan
The GUT tests that will prove this works, named, with specific cases -
including at least one boundary case.
## Risks
## Out of scope
```

### 3. Independent review → `4-review.md` (blocking)

Dispatch a **subagent** (Task tool, `subagent_type: general-purpose`) with the reviewer prompt in
`references/epic-prep.md` under "Reviewer prompt", pointed at this plan directory.

- `APPROVED` → proceed.
- `CHANGES_REQUESTED` → revise `3-plan.md`, re-review. **Maximum two rounds.** Append each round
  to `4-review.md` rather than overwriting — the history matters.
- `REJECTED`, or not approved after two rounds → **stop. Do not implement.** Commit every
  artifact, mark `STATUS.md` blocked with the reason, `set-badge <taskId> stuck`, and report it.
  A cycle producing a well-researched rejected plan is a **successful** cycle.

Never review your own plan and call it approved. The review file must come from the subagent.

### 4. Implement → `5-progress.md`

```markdown
# Progress
- [x] Step 1 of build sequence — <what was done, which files>
- [ ] Step 2 — <not started>

**Resume at:** step 2.
**Deviations from plan:** <or "none">
```

- Tests first. Update `5-progress.md` after **each build step**, not at the end — a window can end
  at any moment.
- If reality contradicts the plan, update `3-plan.md`. A stale plan is worse than none.
- Discovered work goes into a new task via
  `./scripts/backlog-cli.js add-task <epicId> "<head>" --type bug --complexity small` (body on
  stdin) — never silently folded into this change.

### 5. Verify, 6. Document

```bash
bash /agent/verify.sh
```

Imports the project, boots it headless (autoloads + main scene), and runs the GUT suite. **Do not
delete work to make the gate pass.** If something is genuinely unsalvageable, remove only that part
and say so explicitly in your report.

Then: invoke **`updating-project-docs`** if the change was structural (required by `CLAUDE.md`),
`./scripts/backlog-cli.js set-state <taskId> done`, mark `STATUS.md` complete, and quote the review
verdict verbatim in your report.

---

## Resuming (`reason: "resume"` or `"resume-plan"`)

A previous cycle started this item. Read `<planDir>/STATUS.md`, read the artifacts of the completed
stages, and continue from the **first unchecked stage**. The `Next action` line tells you exactly
where to pick up.

Do not re-gather context, do not re-run the same web searches, and do not rewrite an approved plan.
`reason: "resume"` with no plan directory means a direct-track item died mid-edit: read the diff
(`git status`, `git diff`) to see how far it got.

---

## When an EPIC completes: write the dossier

An epic is done when every one of its tasks is `done`. Confirm with
`./scripts/backlog-cli.js epic show <epicId>`. Before moving on, write `docs/epics-done/<epicId>/`
— using the **exact** `epicId`, since that is the join key the web UI reads — three files, drawn
from the epic's `prepDir` and the plan directories you already have. Do this in the same cycle that
closes the last task, while the detail is fresh; reconstructing it later from diffs is far more
expensive and less accurate.

**`PRD.md`** — what was asked for and why:

```markdown
# <Epic> — PRD
## The ask
The epic's tasks (heads + bodies) verbatim, plus anything the user clarified afterwards. If this
epic came from an idea, quote the original idea text, and quote every review comment in
`epic show`'s `feedback` — those are the user's own words about what they wanted changed.
## Player-facing goal
What the player should experience. Not implementation.
## Scope
In scope / explicitly out of scope, and where the epic was split and why.
## Constraints
Project constraints that shaped it (view rule, coordinate space, reuse requirements).
## Open questions at the time
What was unknown when planning started, and how each was resolved.
```

**`SOURCES.md`** — where the knowledge came from, merged and de-duplicated from the epic's
`2-research.md` and any escalated task's own research:

```markdown
# <Epic> — sources
| Source (URL) | What it contributed | Where it shows up in the build |
Include sources that were tried and unreachable, marked as such.
Note any finding that was a judgement call with no citable source - label it plainly.
```

**`REPORT.md`** — the epic in full:

```markdown
# <Epic> — completion report
## What was built
Per task: what shipped, the scenes/scripts involved, the commit.
## How it was verified
The actual tests, by name. What the gate covers and what it cannot.
## Decisions and course changes
Where the plan changed mid-build and why. Include plans the reviewer REJECTED and every round of
user feedback, and what changed as a result - a rejected plan is part of the story, not a failure
to hide.
## Numbers
Tuning values chosen (timings, HP, speeds), and where each came from -
research, existing code, or judgement.
## Known gaps
What is unfinished, fragile, or untested. Anything a human still has to eyeball.
## Links
The plan directories, the epic id, key commits.
```

Then `./scripts/backlog-cli.js close-epic <epicId>` — **never** edit `BACKLOG.json` or `BACKLOG.md`
directly for this. Note the dossier path in your report so it reaches the digest.

**Be honest in `Known gaps`.** A dossier claiming everything is finished and verified is worth less
than one that names the two things nobody has looked at — headless tests cannot tell you whether a
boss fight *feels* right, and the report should say so.

---

## Anti-patterns

- **Running the escalated track on a small item.** It is not thoroughness, it is a window spent on
  a typo. The classification is there to be trusted.
- **Skipping the review because the plan "is obviously fine."** The review exists precisely for
  plans that feel obviously fine.
- **Restarting a stage that already has an artifact.** The single most expensive mistake here.
  Read the file, trust it, move on.
- **Re-planning an approved epic from an implementation task.** The user approved that plan. If it
  is wrong, escalate and say why; do not quietly build something else.
- **Escalating silently.** Switching tracks without `set-meta` means the board shows small/sonnet
  while the work is large/opus, and the next iteration makes the same discovery from scratch.
- **Treating the reviewer as a formality.** If every plan is approved first time, the reviewer
  prompt is not being followed.
- **Letting `STATUS.md` go stale.** An unticked box that is actually done, or a wrong
  `Next action`, sends the next cycle to redo hours of work.
