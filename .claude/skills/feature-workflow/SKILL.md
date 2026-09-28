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

**Every stage writes a file, and every stage is resumable.** A run has a time limit and a rate-limit
window, and can end mid-item. Nothing already done may be redone: re-reading the codebase and
re-running the same web searches costs a large part of a run and produces the same answer.

---

## Step 1 — Read your work item

AI-Kanban chose it and put it in your prompt. You do not choose your own work, and you never
change its status yourself: the board moves it when your run ends. The parts that matter here:

| Prompt section | What it decides |
|---|---|
| **Work item → Kind** | `prep` = you are preparing an epic. `impl` = you are building something. |
| **Work item → Type** | `research` / `plan` / `plan-review` for prep; `feature` / `bug` / `refactor` / `test` / `art` / `chore` for impl. |
| **Work item → Complexity** | `small` / `medium` / `large` — the main lever on how much process. |
| **Work item → Task ID / Epic ID** | Join keys: plan directories and dossiers are named after them, **exactly**. |
| **Work item → Epic plan directory** | Where the epic's research and approved plan live (the old `prepDir`). |
| **Previous Attempts** | Present when an earlier run already worked on this task — you are resuming, see below. |
| **Human Feedback** | The owner's words when they sent the epic back. Verbatim. Read them first. |

## Step 2 — Route

| Your item | Track | What you do |
|---|---|---|
| Kind `prep` | **Preparation** | Read `references/epic-prep.md` and do the one stage named by the type. |
| Kind `impl`, complexity `small` | **Direct** | Implement → test → verify. No plan directory, no subagent. |
| Kind `impl`, complexity `medium`, **and the epic plan directory has a `3-plan.md`** | **Direct** | Same, working from the epic's approved plan. |
| Kind `impl`, complexity `medium`, **and there is no `3-plan.md`** | **Escalated** | See below. |
| Kind `impl`, complexity `large` | **Escalated** | Your own plan directory, context → plan → independent review → implement. |

### Why a missing epic plan matters

The Direct track is cheap **because the thinking was already paid for**: the epic was researched,
planned, reviewed and approved before any of its tasks became workable, and its plan directory
holds that plan. An epic with no `3-plan.md` never went through that — it was hand-made on the
board, or predates the preparation pipeline. Its tasks have **no plan behind them at all**.

So a medium task with no epic plan is not "cheap work with the thinking done", it is "work nobody
has thought about yet", and it takes the escalated track. Only genuinely `small` items (a typo, a
wrong constant, a stale reference, a missing null check) skip planning on their own merits.

Do not paper over this by inventing a plan and carrying on as if it were approved — write it
properly and get it reviewed, which is exactly what the escalated track is.

**Route on the fields, not on the wording of the task title.** A task called "fix the enemy
spawn bug" marked `large` is an escalated item; one called "rework spawning" marked `small` is a
direct one. If you believe the classification is wrong, escalate (below) rather than quietly
working a different track than the board shows.

### Ending a run

Your **final message** is what the owner reads on the task, so end every run with it:

```markdown
## Result
DONE | ESCALATE | BLOCKED — one line on why
## What shipped
<files, with paths>
## How it was verified
<exact commands and what they showed>
## Assumptions
## Follow-ups
<concrete defects or next steps you hit but did not act on — the owner decides what becomes a task>
```

The harness runs the verification gate after you and commits only if it passes; the task then
waits in *In review* for the owner. Never try to update the board yourself.

### Working inside a phase (the prompt has *Phase X of N*)

A big idea is built as a chain of phase epics. Later phases are researched and planned from the
shared idea folder `docs/ideas/<idea id>/`, and the code decides whether they succeed, so keep that
folder true to what was actually built:

- **Log deviations as you make them.** If your implementation departs from the approved plan in a
  way a later phase will depend on — a renamed or removed class, signal or interface, a changed data
  format or scene structure, a piece dropped or deferred — append a line to `DECISIONS.md` under
  this phase's section before you finish: what changed and why. Small internal choices don't belong
  there.
- **Closing the phase.** If yours is the last open task of a phase epic, you are finishing the
  phase: write the epic dossier (below) and append a `## Phase X - as built (<date>)` section to
  `DECISIONS.md`: what was actually built (key files, nodes, signals), every deviation from the
  plan, and the gaps left for later phases. The next phase's research starts from this section and
  from the code.

---

## Track: Direct

For a small fix, or a medium task whose epic already has an approved plan: a bug fix, a stale
reference, a rename, tuning a value, adding a test, a contained piece the plan already described.

1. **Read the epic's plan.** `<epic plan directory>/3-plan.md` is the design this task came out
   of, and it was reviewed and approved by the owner. **Do not re-derive it and do not redesign
   it.** If there is no `3-plan.md` and this item is not genuinely small, you are on the wrong
   track — go back to the routing table.
2. **Write the failing test first**, from the plan's test plan where one exists. Watch it fail.
3. Implement.
4. `bash /agent/verify.sh`.
5. Finish with your final message (`Result: DONE`).

No plan directory. No research stage. No subagent review. The epic's preparation already paid for
those, and paying twice is exactly the waste this track exists to stop.

### When to abandon this track

Escalate the moment any of these turn out to be true — do not push on:

- The fix requires changing project structure, an autoload's contract, or a shared component.
- It touches three or more systems, or a dependency.
- The obvious fix would break something the plan did not consider.
- **The gate has failed twice on this item.**

Escalating is not a failure — it is the system working. Leave the code as it was (revert your
partial edits unless they are a clean, gate-green improvement on their own) and **stop for this
run** with `Result: ESCALATE` and why: what you found, which files it touches, and what size it
really is. The owner re-sizes the task on the board (large, on opus) and the next run takes the
escalated track. Do not try to do architectural work on the model that was budgeted for a typo.

---

## Track: Escalated

For `complexity: "large"` implementation: a new mechanic or system, more than ~3 files, or any
design choice a reasonable person could disagree about.

### Create the checkpoint directory first

Create `docs/plans/<Task ID>/STATUS.md`, using the **exact** Task ID from your work item as the
directory name — never re-derive or reword it. It is the join key a later run uses to find and
resume this work, so a mismatch makes the artifacts invisible even though the files exist.

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
- [ ] 6. Docs updated

**Next action:** Gather context.
```

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
- `REJECTED`, or not approved after two rounds → **stop. Do not implement.** Leave every
  artifact in place (the harness commits them), mark `STATUS.md` blocked with the reason, and end
  with `Result: BLOCKED` quoting the reviewer. A run producing a well-researched rejected plan is
  a **successful** run.

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
- If reality contradicts the plan, update `3-plan.md`. A stale plan is worse than none. In a phase
  epic, also log the deviation in `DECISIONS.md` (see *Working inside a phase*).
- Discovered work goes under **Follow-ups** in your final message — never silently folded into
  this change.

### 5. Verify, 6. Document

```bash
bash /agent/verify.sh
```

Imports the project, boots it headless (autoloads + main scene), and runs the GUT suite. **Do not
delete work to make the gate pass.** If something is genuinely unsalvageable, remove only that part
and say so explicitly in your final message.

Then: invoke **`updating-project-docs`** if the change was structural (required by `CLAUDE.md`),
mark `STATUS.md` complete, and quote the review verdict verbatim in your final message.

---

## Resuming (the prompt lists **Previous Attempts**)

An earlier run already worked on this task. Their errors are in the prompt — read them: a gate
failure or a timeout tells you exactly what to avoid. Then read `docs/plans/<Task ID>/STATUS.md`
if it exists, read the artifacts of the completed stages, and continue from the **first unchecked
stage**. The `Next action` line tells you exactly where to pick up.

Do not re-gather context, do not re-run the same web searches, and do not rewrite an approved plan.
Previous attempts with no plan directory mean a direct-track item: a failed run's edits are not
committed, so check `git status` / `git diff` for anything left behind before starting over.

---

## When an EPIC completes: write the dossier

An epic is done when every one of its tasks is done; AI-Kanban then closes it by itself. Check the
prompt's **Epic tasks** list and **Epic progress**: if yours is the only task not yet done, you are
closing the epic. Before finishing, write `docs/epics-done/<Epic ID>/` — using the **exact** Epic
ID, since that is the join key — three files, drawn from the epic plan directory and the plan
directories you already have. Do this in the same run that finishes the last task, while the detail
is fresh; reconstructing it later from diffs is far more expensive and less accurate.

**`PRD.md`** — what was asked for and why:

```markdown
# <Epic> — PRD
## The ask
The epic's tasks (titles + descriptions) verbatim, plus anything the owner clarified afterwards. If
this epic came from an idea, quote the original idea text (under **Original idea** in the prompt), and
quote every comment under **Human Feedback** — those are the owner's own words about what they
wanted changed.
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

Name the dossier path in your final message so the owner finds it. For a phase epic, also append
the `## Phase X - as built` section to the idea's `DECISIONS.md` (see *Working inside a phase*) —
later phases read `REPORT.md` and that section before planning.

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
- **Escalating silently.** Switching tracks without ending on `Result: ESCALATE` means the board
  shows small/sonnet while the work is large/opus, and the next run makes the same discovery from
  scratch.
- **Treating the reviewer as a formality.** If every plan is approved first time, the reviewer
  prompt is not being followed.
- **Letting `STATUS.md` go stale.** An unticked box that is actually done, or a wrong
  `Next action`, sends the next cycle to redo hours of work.
