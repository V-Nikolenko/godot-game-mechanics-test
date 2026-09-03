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

function persist(store) {
  S.save(FILE, store);
  fs.writeFileSync(MD, S.render(store));
}

function readStdin() {
  try { return fs.readFileSync(0, "utf8"); } catch (e) { return ""; }
}

function die(msg) { process.stderr.write("backlog-cli: " + msg + "\n"); process.exit(1); }

const [, , cmd, ...args] = process.argv;
const store = S.load(FILE);

try {
switch (cmd) {
  case "next": {
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
    const found = S.findTask(store, taskId);
    if (!found) die("no such task: " + taskId);
    found.task.state = state;
    if (state === "done") found.task.badge = null;
    persist(store);
    console.log("ok: " + taskId + " -> " + state);
    break;
  }

  case "set-badge": {
    const [taskId, badge] = args;
    if (!["blocked", "stuck", "clear"].includes(badge)) die("badge must be blocked|stuck|clear");
    const found = S.findTask(store, taskId);
    if (!found) die("no such task: " + taskId);
    found.task.badge = badge === "clear" ? null : badge;
    persist(store);
    console.log("ok: " + taskId + " badge -> " + (found.task.badge || "none"));
    break;
  }

  case "set-plandir": {
    const [taskId, dir] = args;
    const found = S.findTask(store, taskId);
    if (!found) die("no such task: " + taskId);
    found.task.planDir = dir;
    persist(store);
    console.log("ok: " + taskId + " planDir -> " + dir);
    break;
  }

  case "ideas": {
    const [sub, ideaId] = args;
    if (sub === "list") {
      console.log(JSON.stringify(store.ideas.filter((i) => i.status === "pending"), null, 2));
    } else if (sub === "consume") {
      const idea = store.ideas.find((i) => i.id === ideaId);
      if (!idea) die("no such idea: " + ideaId);
      idea.status = "drafted";
      persist(store);
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
    const epic = S.addEpic(store, spec.title, "draft");
    for (const t of spec.tasks) S.addTask(store, epic.id, t.head, t.body || "", false);
    persist(store);
    console.log(JSON.stringify({ epicId: epic.id, taskCount: spec.tasks.length, status: "draft" }, null, 2));
    break;
  }

  case "set-epic-status": {
    const [epicId, status] = args;
    if (!["draft", "active", "done"].includes(status)) die("status must be draft|active|done");
    const epic = S.findEpic(store, epicId);
    if (!epic) die("no such epic: " + epicId);
    epic.status = status;
    persist(store);
    console.log("ok: " + epicId + " -> " + status);
    break;
  }

  case "add-task": {
    const top = args.includes("--top");
    const [epicId, head] = args.filter((a) => a !== "--top");
    if (!epicId || !head) die("usage: add-task <epicId> <head> [--top]  (body on stdin)");
    if (!S.findEpic(store, epicId)) die("no such epic: " + epicId);
    const body = readStdin();
    const task = S.addTask(store, epicId, head, body, top);
    persist(store);
    console.log(JSON.stringify({ taskId: task.id }, null, 2));
    break;
  }

  default:
    die("usage: backlog-cli.js {next|set-state|set-badge|set-plandir|ideas|draft-epic|set-epic-status|add-task} ...");
}
} catch (e) {
  // Last resort: any unexpected failure (bad data, disk error) becomes a clean
  // one-line message instead of a Node stack trace the agent has to interpret.
  die("unexpected error: " + ((e && e.message) || e));
}
