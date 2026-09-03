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
//   ./scripts/backlog-cli.js ideas list
//   ./scripts/backlog-cli.js ideas consume <ideaId>
//   ./scripts/backlog-cli.js draft-epic < epic.json
//   ./scripts/backlog-cli.js set-epic-status <epicId> draft|active|done
//   ./scripts/backlog-cli.js add-task <epicId> <head> [--top]   (body on stdin, optional)
"use strict";

const path = require("path");
const fs = require("fs");
const S = require("/agent/backlog-store.js");

const REPO = path.resolve(__dirname, "..");
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
// backlog-store.js's withLock). Plain reads (`next`, `ideas list`) skip the
// lock entirely - save()'s atomic rename means a reader only ever sees a
// fully-old or fully-new file, never a torn one, so there is nothing to race.
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

// die() THROWS rather than calling process.exit() directly. process.exit() halts
// the process immediately and does NOT run pending finally blocks on the current
// stack (verified empirically) - a die() call from inside mutate()'s callback
// would exit before withLock's finally released the lock, stranding it for the
// full stale-lock window. Throwing lets normal JS unwinding run every finally
// on the way out; the one process.exit() call is the outer catch below, after
// everything has already unwound and every lock is released.
class BacklogCliError extends Error {}
function die(msg) { throw new BacklogCliError(msg); }

const [, , cmd, ...args] = process.argv;

try {
switch (cmd) {
  case "next": {
    const store = S.load(FILE);
    const n = S.nextTask(store, REPO);
    if (!n) { console.log(JSON.stringify({ task: null })); break; }
    console.log(JSON.stringify({
      epicId: n.epic.id, epicTitle: n.epic.title, taskId: n.task.id,
      head: n.task.head, body: n.task.body, state: n.task.state,
      planDir: n.task.planDir, reason: n.reason,
    }, null, 2));
    break;
  }

  case "set-state": {
    const [taskId, state] = args;
    if (!["todo", "in_progress", "done"].includes(state)) die("state must be todo|in_progress|done");
    mutate((store) => {
      const found = S.findTask(store, taskId);
      if (!found) die("no such task: " + taskId);
      found.task.state = state;
      if (state === "done") found.task.badge = null;
    });
    console.log("ok: " + taskId + " -> " + state);
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
    mutate((store) => {
      const found = S.findTask(store, taskId);
      if (!found) die("no such task: " + taskId);
      found.task.planDir = dir;
    });
    console.log("ok: " + taskId + " planDir -> " + dir);
    break;
  }

  case "ideas": {
    const [sub, ideaId] = args;
    if (sub === "list") {
      const store = S.load(FILE);
      console.log(JSON.stringify(store.ideas.filter((i) => i.status === "pending"), null, 2));
    } else if (sub === "consume") {
      mutate((store) => {
        const idea = store.ideas.find((i) => i.id === ideaId);
        if (!idea) die("no such idea: " + ideaId);
        idea.status = "drafted";
      });
      console.log("ok: idea " + ideaId + " marked drafted");
    } else die("ideas subcommand must be list|consume");
    break;
  }

  case "draft-epic": {
    // stdin: { "title": "...", "tasks": [{ "head": "...", "body": "..." }, ...] }
    let spec;
    try { spec = JSON.parse(readStdin()); } catch (e) { die("stdin must be valid JSON: " + e.message); }
    if (!spec.title || !Array.isArray(spec.tasks) || !spec.tasks.length) {
      die("need { title, tasks: [{head, body}, ...] } on stdin");
    }
    let epicId;
    mutate((store) => {
      const epic = S.addEpic(store, spec.title, "draft");
      epicId = epic.id;
      for (const t of spec.tasks) S.addTask(store, epic.id, t.head, t.body || "", false);
    });
    console.log(JSON.stringify({ epicId: epicId, taskCount: spec.tasks.length, status: "draft" }, null, 2));
    break;
  }

  case "set-epic-status": {
    const [epicId, status] = args;
    if (!["draft", "active", "done"].includes(status)) die("status must be draft|active|done");
    mutate((store) => {
      const epic = S.findEpic(store, epicId);
      if (!epic) die("no such epic: " + epicId);
      epic.status = status;
    });
    console.log("ok: " + epicId + " -> " + status);
    break;
  }

  case "add-task": {
    const top = args.includes("--top");
    const [epicId, head] = args.filter((a) => a !== "--top");
    if (!epicId || !head) die("usage: add-task <epicId> <head> [--top]  (body on stdin)");
    const body = readStdin();
    let taskId;
    mutate((store) => {
      if (!S.findEpic(store, epicId)) die("no such epic: " + epicId);
      const task = S.addTask(store, epicId, head, body, top);
      taskId = task.id;
    });
    console.log(JSON.stringify({ taskId: taskId }, null, 2));
    break;
  }

  default:
    die("usage: backlog-cli.js {next|set-state|set-badge|set-plandir|ideas|draft-epic|set-epic-status|add-task} ...");
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
