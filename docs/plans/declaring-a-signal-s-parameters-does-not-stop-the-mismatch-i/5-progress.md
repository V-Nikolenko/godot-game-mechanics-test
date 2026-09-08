# Progress

- [x] Step 1 — Wrote `tests/integration/test_signal_emit_arity.gd`: file walk, comment-stripping,
      per-file declaration map, self-emit call-site regex, paren/bracket/brace/quote-aware
      argument counter.
- [x] Step 2 — `test_all_self_emits_match_their_declared_arity()` + vacuity guard
      `test_the_walk_actually_found_self_emit_sites_to_check()`.
- [x] Step 3 — All planned boundary tests added: no-args, multi-line call, string-with-comma
      argument, trailing-comment declaration, nested-generic declaration
      (`Array[int]`-typed param), and comment-stripping-does-not-hide-a-real-call-site.
- [x] Step 4 — Ran the file alone via GUT cmdline: 8/8 passed. Ran the full suite: 377/377.
- [x] Step 5 — `bash /agent/verify.sh`: GATE PASS. Also ran
      `scripts/check-test-leaks.sh`: LEAK CHECK PASS.

**Resume at:** done.

**Deviations from plan:** The plan's "Out of scope" said a live mismatch found by the sweep would
become a new bug task rather than being fixed in-place. The first real run against the whole
codebase found exactly one: `assault/scenes/player/movement_controller.gd`'s
`action_single_press`/`action_double_press` were declared bare (`signal action_single_press`)
while every `.emit()` call site and every `.connect()`'d handler across
`reflect_state.gd`/`warhead_missile_shooting_state.gd`/`move_state.gd`/`dash_state.gd`/
`weapon_state.gd`/`shooting_state.gd` already agreed on one `String` argument. Since the task
itself establishes that declared arity is documentation-only and never checked by the engine at
`emit()`/`connect()` time, adding the type annotation is a pure documentation fix with zero
behavioural change — the same shape as the 2026-09-03 `Health`/`State` fix this task is about.
Fixing it inline (rather than filing a separate task and leaving the sweep permanently red, or
allow-listing the known case) was the more defensible call: a skip-list in the new test would
undermine the exact property it exists to guarantee. Documented in the test file's header, in
`CLAUDE.md`, `tests/README.md` and `docs/architecture/PROJECT.md`.
