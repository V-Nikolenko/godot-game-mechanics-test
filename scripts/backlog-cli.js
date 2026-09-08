#!/usr/bin/env node
// The agent's only sanctioned way to touch the backlog. Never hand-edit
// BACKLOG.json or BACKLOG.md with the Write/Edit tool - malformed JSON here
// silently breaks the web UI and every future iteration's `next` lookup.
//
// Run from /work/repo (this script's directory's parent):
//   ./scripts/backlog-cli.js next
//   ./scripts/backlog-cli.js set-state <taskId> todo|in_progress|done
//   ./scripts/backlog-cli.js set-badge <taskId> blocked|stuck|clear
//   ./scripts/backlog-cli.js set-plandir <taskId> <docs/plans/...>
//   ./scripts/backlog-cli.js set-meta <taskId> [--type T] [--complexity C] [--model M]
//   ./scripts/backlog-cli.js ideas list
//   ./scripts/backlog-cli.js ideas claim <ideaId>          (harness; marks it triaging)
//   ./scripts/backlog-cli.js ideas reject <ideaId>         (reason on stdin)
//   ./scripts/backlog-cli.js draft-epic < epic.json        ({title, ideaId, summary})
//   ./scripts/backlog-cli.js epic show <epicId>
//   ./scripts/backlog-cli.js close-epic <epicId>
//   ./scripts/backlog-cli.js add-task <epicId> <head> [flags]   (body on stdin, optional)
//   ./scripts/backlog-cli.js record-run <taskId> --raw <log>   (harness, after each iteration)
//   ./scripts/backlog-cli.js sweep-triaging                (harness, once per cycle)
"use strict";

const path = require("path");
const fs = require("fs");

// Both paths are env-overridable purely so the harness tests can run this CLI
// against a scratch BACKLOG.json on a machine that has no /agent mount. Nothing
// in production sets them; the defaults are the container's real layout.
const S = require(process.env.BACKLOG_STORE || "/agent/backlog-store.js");
const REPO = process.env.BACKLOG_REPO || path.resolve(__dirname, "..");
const FILE = path.join(REPO, "BACKLOG.json");
const MD = path.join(REPO, "BACKLOG.md");
const LOCK = FILE + ".lock";

function persist(store) {
  S.save(FILE, store);
  fs.writeFileSync(MD, S.render(store));
}

// Every MUTATING command runs its whole load -> mutate -> persist sequence
// inside one lock, so the web UI writing at the same instant can't silently
// lose one side's change (verified under real multi-process concurrency, see
// backlog-store.js's withLock). Plain reads (`next`, `ideas list`, `epic show`)
// skip the lock entirely - save()'s atomic rename means a reader only ever sees
// a fully-old or fully-new file, never a torn one, so there is nothing to race.
function mutate(fn) {
  return S.withLock(LOCK, () => {
    const store = S.load(FILE);
    const result = fn(store);
    persist(store);
    return result;
  });
}

function readStdin() {
  try { return fs.readFileSync(0, "utf8"); } catch (e) { return ""; }
}

function out(obj) { console.log(JSON.stringify(obj, null, 2)); }

// die() THROWS rather than calling process.exit() directly. process.exit() halts
// the process immediately and does NOT run pending finally blocks on the current
// stack (verified empirically) - a die() call from inside mutate()'s callback
// would exit before withLock's finally released the lock, stranding it for the
// full stale-lock window. Throwing lets normal JS unwinding run every finally
// on the way out; the one process.exit() call is the outer catch below, after
// everything has already unwound and every lock is released.
class BacklogCliError extends Error {}
function die(msg) { throw new BacklogCliError(msg); }

// --- flag parsing --------------------------------------------------------------
// Positional args and --flags can be interleaved; pull the flags out first so the
// positional order stays readable at the call site.
function parseFlags(argv, names) {
  const flags = {}, rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const name = a.slice(2);
      if (!names.includes(name)) die("unknown flag: " + a);
      if (name === "top") { flags.top = true; continue; }
      const v = argv[++i];
      if (v === undefined) die("--" + name + " needs a value");
      flags[name] = v;
    } else rest.push(a);
  }
  return { flags, rest };
}

function checkEnum(label, value, allowed) {
  if (value === undefined) return undefined;
  if (!allowed.includes(value)) die(label + " must be " + allowed.join("|"));
  return value;
}

const [, , cmd, ...args] = process.argv;

try {
switch (cmd) {
  // The single entry point the harness uses to decide what this iteration does.
  // Returns one work item, already prioritised (idea -> preparation ->
  // implementation) and already carrying the model that item should run on, so
  // neither the choice nor the model depends on the agent remembering a rule.
  case "next": {
    const store = S.load(FILE);
    const work = S.nextWork(store, REPO);
    // A revision round needs the user's own words, not a summary of them, so the
    // feedback travels with the work item rather than needing a second lookup.
    if (work.work === "task") {
      const epic = S.findEpic(store, work.epicId);
      if (epic && epic.feedback.length) work.feedback = epic.feedback;
    }

    // `next --env <file>` is the form run-cycle.sh uses: it writes the JSON work
    // item to <file> and prints shell assignments for the few fields the harness
    // branches on. The plain JSON form still exists for a human reading the queue.
    //
    // Emitting the assignments here rather than having the shell pull them out
    // with jq keeps the harness's control flow from depending on a JSON parser
    // being present: a missing jq would leave every variable empty, which reads
    // in the logs exactly like a normal iteration while the agent is handed an
    // empty task id.
    if (args[0] === "--env") {
      const dest = args[1];
      if (!dest) die("usage: next --env <path-to-write-work-item.json>");
      fs.writeFileSync(dest, JSON.stringify(work, null, 2) + "\n");
      const shq = (v) => "'" + String(v === undefined || v === null ? "" : v).replace(/'/g, "'\\''") + "'";
      const lines = [
        ["WORK_KIND", work.work || "null"],
        ["ITER_MODEL", work.model || ""],
        ["IDEA_ID", work.ideaId || ""],
        ["TASK_ID", work.taskId || ""],
        ["WORK_PLANDIR", work.planDir || ""],
        ["WORK_LABEL", work.work === "idea" ? "idea " + work.ideaId
          : work.work === "task" ? work.kind + " " + work.type + " " + work.taskId + " (" + work.reason + ")"
          : "nothing"],
      ];
      console.log(lines.map((l) => l[0] + "=" + shq(l[1])).join("\n"));
      break;
    }

    out(work);
    break;
  }

  case "set-state": {
    const [taskId, state] = args;
    if (!S.TASK_STATES.includes(state)) die("state must be " + S.TASK_STATES.join("|"));
    const result = mutate((store) => {
      const found = S.findTask(store, taskId);
      if (!found) die("no such task: " + taskId);
      found.task.state = state;
      if (state === "done") found.task.badge = null;
      // Finishing the last preparation task is what sends an epic to the user.
      // Done here rather than left to the agent: a forgotten transition means an
      // epic silently stalls, prepared but never surfaced for approval.
      const moved = S.refreshEpicStatus(store, found.epic);
      return { epicId: found.epic.id, epicStatus: moved };
    });
    console.log("ok: " + taskId + " -> " + state);
    if (result.epicStatus === "review") {
      console.log("EPIC_READY_FOR_REVIEW " + result.epicId);
      console.log("Preparation is complete. The epic now waits for the user's approval in the web UI - do not start its implementation tasks.");
    }
    break;
  }

  case "set-badge": {
    const [taskId, badge] = args;
    if (!["blocked", "stuck", "clear"].includes(badge)) die("badge must be blocked|stuck|clear");
    let finalBadge;
    mutate((store) => {
      const found = S.findTask(store, taskId);
      if (!found) die("no such task: " + taskId);
      found.task.badge = badge === "clear" ? null : badge;
      finalBadge = found.task.badge;
    });
    console.log("ok: " + taskId + " badge -> " + (finalBadge || "none"));
    break;
  }

  case "set-plandir": {
    const [taskId, dir] = args;
    if (!taskId || !dir) die("usage: set-plandir <taskId> <docs/plans/...>");
    mutate((store) => {
      const found = S.findTask(store, taskId);
      if (!found) die("no such task: " + taskId);
      found.task.planDir = dir;
    });
    console.log("ok: " + taskId + " planDir -> " + dir);
    break;
  }

  // Re-classifying a task mid-flight is how escalation is RECORDED rather than
  // decided silently inside one session: a "small bug" that turns out to need an
  // architectural change gets --complexity large --model opus, which puts it on
  // the escalated track, shows the change on the board, and makes the next
  // iteration start with the right model instead of repeating the discovery.
  case "set-meta": {
    const { flags, rest } = parseFlags(args, ["type", "complexity", "model"]);
    const [taskId] = rest;
    if (!taskId) die("usage: set-meta <taskId> [--type T] [--complexity C] [--model M]");
    checkEnum("--type", flags.type, S.TASK_TYPES);
    checkEnum("--complexity", flags.complexity, S.COMPLEXITIES);
    checkEnum("--model", flags.model, S.MODELS);
    if (!flags.type && !flags.complexity && !flags.model) die("set-meta needs at least one of --type/--complexity/--model");
    const result = mutate((store) => {
      const found = S.findTask(store, taskId);
      if (!found) die("no such task: " + taskId);
      const t = found.task;
      if (flags.type) t.type = flags.type;
      if (flags.complexity) t.complexity = flags.complexity;
      // An explicit --model wins; otherwise re-derive it, so raising complexity
      // to "large" upgrades the model without needing to remember to say so.
      t.model = flags.model || S.defaultModel(t.type, t.complexity);
      return { taskId: t.id, type: t.type, complexity: t.complexity, model: t.model };
    });
    out(result);
    break;
  }

  case "ideas": {
    const [sub, ideaId] = args;
    if (sub === "list") {
      const store = S.load(FILE);
      out(store.ideas.filter((i) => i.status === "pending" || i.status === "triaging"));
    } else if (sub === "claim") {
      mutate((store) => {
        const idea = S.findIdea(store, ideaId);
        if (!idea) die("no such idea: " + ideaId);
        if (idea.status !== "pending") die("idea " + ideaId + " is " + idea.status + ", not pending");
        idea.status = "triaging";
      });
      console.log("ok: idea " + ideaId + " -> triaging");
    } else if (sub === "reject") {
      const reason = readStdin().trim();
      mutate((store) => {
        const idea = S.findIdea(store, ideaId);
        if (!idea) die("no such idea: " + ideaId);
        idea.status = "rejected";
        idea.decidedAt = new Date().toISOString();
        if (reason) idea.text = idea.text + "\n\n**Not drafted:** " + reason;
      });
      console.log("ok: idea " + ideaId + " rejected");
    } else die("ideas subcommand must be list|claim|reject");
    break;
  }

  // stdin: { "title": "...", "ideaId": "idea-...", "summary": "..." }
  //
  // Note there is no "tasks" field any more. Implementation tasks are NOT written
  // here - they come out of the reviewed plan, which is the whole point of the
  // preparation stages this command creates.
  case "draft-epic": {
    let spec;
    try { spec = JSON.parse(readStdin()); } catch (e) { die("stdin must be valid JSON: " + e.message); }
    if (!spec.title) die("need { title, ideaId?, summary? } on stdin");
    if (Array.isArray(spec.tasks)) {
      die("draft-epic no longer accepts a `tasks` array. Implementation tasks come from the reviewed plan - this creates the research/plan/plan-review tasks for you.");
    }
    const result = mutate((store) => {
      let epic;
      try { epic = S.draftEpic(store, spec); } catch (e) { die(e.message); }
      return {
        epicId: epic.id, status: epic.status, prepDir: epic.prepDir,
        sourceIdeaId: epic.sourceIdeaId,
        prepTasks: epic.tasks.map((t) => ({ id: t.id, type: t.type, dependsOn: t.dependsOn })),
      };
    });
    out(result);
    break;
  }

  case "epic": {
    const [sub, epicId] = args;
    if (sub !== "show") die("epic subcommand must be show");
    const store = S.load(FILE);
    const epic = S.findEpic(store, epicId);
    if (!epic) die("no such epic: " + epicId);
    const idea = epic.sourceIdeaId ? S.findIdea(store, epic.sourceIdeaId) : null;
    out({
      id: epic.id, title: epic.title, status: epic.status, prepDir: epic.prepDir,
      sourceIdea: idea ? { id: idea.id, text: idea.text } : null,
      feedback: epic.feedback,
      tasks: epic.tasks.map((t) => ({
        id: t.id, head: t.head, state: t.state, kind: t.kind, type: t.type,
        complexity: t.complexity, model: t.model, dependsOn: t.dependsOn, badge: t.badge,
      })),
    });
    break;
  }

  // Only "done" is available to the agent. Approving an epic (draft -> active) is
  // the user's decision and lives solely in the web UI; exposing it here would let
  // an unattended run approve its own plan, which is exactly the gate this whole
  // pipeline exists to enforce.
  case "close-epic": {
    const [epicId] = args;
    if (!epicId) die("usage: close-epic <epicId>");
    mutate((store) => {
      const epic = S.findEpic(store, epicId);
      if (!epic) die("no such epic: " + epicId);
      const open = epic.tasks.filter((t) => t.state !== "done");
      if (open.length) die("epic has " + open.length + " unfinished task(s): " + open.map((t) => t.id).join(", "));
      epic.status = "done";
    });
    console.log("ok: " + epicId + " -> done");
    break;
  }

  case "add-task": {
    const { flags, rest } = parseFlags(args, ["type", "complexity", "model", "depends-on", "top"]);
    const [epicId, head] = rest;
    if (!epicId || !head) die("usage: add-task <epicId> <head> [--type T] [--complexity C] [--model M] [--depends-on a,b] [--top]  (body on stdin)");
    checkEnum("--type", flags.type, S.TASK_TYPES);
    checkEnum("--complexity", flags.complexity, S.COMPLEXITIES);
    checkEnum("--model", flags.model, S.MODELS);
    if (flags.type && S.PREP_TYPES.includes(flags.type)) {
      die("--type " + flags.type + " is a preparation stage; draft-epic creates those. Use feature|bug|refactor|test|art|chore.");
    }
    const body = readStdin();
    const result = mutate((store) => {
      const epic = S.findEpic(store, epicId);
      if (!epic) die("no such epic: " + epicId);
      const deps = flags["depends-on"] ? flags["depends-on"].split(",").map((s) => s.trim()).filter(Boolean) : [];
      for (const d of deps) {
        if (!epic.tasks.some((t) => t.id === d)) die("depends-on: no task " + d + " in epic " + epicId);
      }
      const task = S.addTask(store, epicId, head, body, {
        kind: "impl", type: flags.type, complexity: flags.complexity,
        model: flags.model, dependsOn: deps, top: flags.top,
      });
      return { taskId: task.id, type: task.type, complexity: task.complexity, model: task.model, dependsOn: task.dependsOn };
    });
    out(result);
    break;
  }

  // Record what an iteration ACTUALLY cost and which model actually ran it.
  //
  // The harness knows what it asked for (--model), but not what answered:
  // --fallback-model quietly downgrades an overloaded primary, and subagents and
  // web search pull in other models. Claude already emits all of it in the
  // stream-json `result` event and it was being discarded, so this reads that
  // file rather than asking anyone to measure anything.
  //
  //   record-run <taskId> --raw <stream.log> [--requested M] [--run LABEL] [--gate pass|fail]
  //   record-run --idea <ideaId> --raw ...     (a triage run; lands on the epic it drafted)
  case "record-run": {
    const { flags, rest } = parseFlags(args, ["raw", "requested", "run", "gate", "idea"]);
    if (!flags.raw) die("usage: record-run <taskId>|--idea <ideaId> --raw <stream.log> [--requested M] [--run LABEL] [--gate pass|fail]");

    // Last `result` event wins: it is the run's own summary line.
    let result = null;
    try {
      for (const line of fs.readFileSync(flags.raw, "utf8").split("\n")) {
        if (!line.trim() || line.indexOf('"result"') < 0) continue;
        let j; try { j = JSON.parse(line); } catch (e) { continue; }
        if (j.type === "result") result = j;
      }
    } catch (e) { die("cannot read " + flags.raw + ": " + e.message); }
    if (!result) die("no result event in " + flags.raw + " (the run produced no summary)");

    // modelUsage is keyed by model id. Cost is the honest way to pick the primary:
    // a run is "an opus run" because opus did the work, not because opus appears.
    const usage = result.modelUsage || {};
    const models = {};
    for (const id of Object.keys(usage)) models[id] = Number(usage[id].costUSD) || 0;
    const primary = Object.keys(models).sort((a, b) => models[b] - models[a])[0] || null;

    // A session that never ran is not a run. The case this actually hits is the
    // 5-hour usage limit: Claude answers with subtype "success" but is_error
    // true, a 429, one turn and no model usage at all. Recording it wrote rows
    // claiming a model of "?" at $0, and made the harness commit a file whose
    // only change was that row - which is where the contentless `agent: cycle`
    // commits came from.
    if (!primary) {
      const why = result.is_error
        ? (String(result.result || "").split("\n")[0] || ("api error " + (result.api_error_status || "?")))
        : "the stream reports no model usage";
      console.log("skipped: no model actually ran - " + why);
      break;
    }

    // stdin, optional: one "<sha>\t<subject>" line per commit the iteration made
    // (the harness pipes `git log --format='%h%x09%s' <base>..HEAD`). The
    // harness's own `agent: cycle` bookkeeping commits are dropped - they say
    // nothing about what the task produced.
    const commits = readStdin().split("\n")
      .map((l) => l.trim()).filter(Boolean)
      .map((l) => { const i = l.indexOf("\t"); return i < 0 ? null : { sha: l.slice(0, i), subject: l.slice(i + 1) }; })
      .filter((c) => c && !/^agent: cycle/.test(c.subject));

    const record = {
      run: flags.run || null,
      requested: flags.requested || null,
      commits: commits,
      primary: primary,
      models: models,
      costUSD: Number(result.total_cost_usd) || 0,
      turns: Number(result.num_turns) || 0,
      subagents: (result.subagent_stats && Number(result.subagent_stats.spawned)) || 0,
      // `subtype` says "success" even for a run that died on an API error, so it
      // cannot be the whole story on its own.
      outcome: result.is_error
        ? ("error" + (result.api_error_status ? " " + result.api_error_status : ""))
        : (result.subtype || null),
      gate: flags.gate || null,
    };

    const saved = mutate((store) => {
      let task = null;
      if (flags.idea) {
        // A triage run has no task of its own. It belongs to the epic it drafted,
        // whose research task is the thing that run actually produced.
        const idea = S.findIdea(store, flags.idea);
        if (!idea) die("no such idea: " + flags.idea);
        if (!idea.epicId) return { skipped: "idea " + flags.idea + " produced no epic - nothing to attach the run to" };
        const epic = S.findEpic(store, idea.epicId);
        if (!epic) return { skipped: "epic " + idea.epicId + " no longer exists" };
        task = epic.tasks.find((t) => t.type === "research") || epic.tasks[0];
        if (!task) return { skipped: "epic " + epic.id + " has no tasks" };
      } else {
        const found = S.findTask(store, rest[0]);
        if (!found) die("no such task: " + rest[0]);
        task = found.task;
      }
      return { taskId: task.id, run: S.addRun(task, record) };
    });

    if (saved.skipped) { console.log("skipped: " + saved.skipped); break; }
    console.log("ok: " + saved.taskId + " ran on " + (saved.run.primary || "?") +
      (saved.run.fallbackUsed ? " (asked for " + saved.run.requested + " - FELL BACK)" : "") +
      ", $" + saved.run.costUSD.toFixed(2) + ", " + saved.run.turns + " turns" +
      ", " + saved.run.commits.length + " commit(s)");
    break;
  }

  case "sweep-triaging": {
    const reset = mutate((store) => S.sweepTriaging(store));
    console.log(reset.length ? "reset to pending: " + reset.join(", ") : "nothing to sweep");
    break;
  }

  default:
    die("usage: backlog-cli.js {next|set-state|set-badge|set-plandir|set-meta|ideas|draft-epic|epic|close-epic|add-task|record-run|sweep-triaging} ...");
}
} catch (e) {
  // The one place process.exit() is safe to call directly: everything has
  // already unwound through any mutate()/withLock finally blocks to get here,
  // so no lock is held at this point. die() calls land here as a
  // BacklogCliError; anything else (bad data, disk error, lock timeout) is an
  // unexpected failure - either way this becomes a clean one-line message
  // instead of a raw Node stack trace the agent has to interpret.
  const msg = e instanceof BacklogCliError ? e.message : "unexpected error: " + ((e && e.message) || e);
  process.stderr.write("backlog-cli: " + msg + "\n");
  process.exit(1);
}
