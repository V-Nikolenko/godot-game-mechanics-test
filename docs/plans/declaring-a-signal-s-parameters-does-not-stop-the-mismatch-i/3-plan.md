# Signal declared-vs-emitted arity sweep

## Problem

A signal's declared parameter list (`signal foo(x: int)`) is never checked by the engine against
how it's actually emitted. Two instances of this drifting silently (`Health.amount_changed`,
`State.state_transition`) were caught by hand and fixed on 2026-09-03, each backed by one
hand-written test that reads `Object.get_signal_list()`. Nothing stops the *next* drift: a
developer (or agent) adds a parameter to an `emit()` call, or changes one, without updating the
`signal` line, and every existing test still passes because nothing else in the suite reads
`get_signal_list()`. The player never sees this directly — it surfaces as a GUT-failing engine
error the moment something actually connects to the signal with the "honest" arity, or as a
reader/editor-completion lie in the meantime.

## Design

Add one project-wide sweep test, `tests/integration/test_signal_emit_arity.gd`, that:

1. Walks every `.gd` file outside `addons/`, `.godot/`, `.git`, `.import` (same skip list as
   `test_resource_uid_integrity.gd`).
2. **Strips comments before any regex runs.** Reviewer round 1 found two live near-misses that
   currently "work" by accident: `space_station.gd:9`'s doc comment containing a literal
   `` `....emit(...)` `` snippet, and `test_health_component.gd:125`'s doc comment containing
   `` `amount_changed.emit(current_health)` ``. Both are harmless today only by coincidence (the
   first is preceded by a `.` so it falls into the member-access exclusion; the second's file
   declares no `amount_changed` signal). A per-line pass removes everything from the first
   unquoted `#` onward *before* the declaration and self-emit regexes ever see the line, so a
   future same-file comment illustrating usage with the wrong argument count cannot produce a
   spurious failure. (String-literal bodies are handled separately, in the arg-counting scan
   itself — a comment marker is never legal inside a GDScript string, so a naive
   first-unquoted-`#` strip is safe: scan the line left to right, toggle a
   single/double-quote flag, and cut at the first `#` seen while that flag is off.)
3. Per (comment-stripped) file, regex-extracts every `signal <name>(...)` or bare `signal <name>`
   declaration into a `{name: String -> declared_arity: int}` map **scoped to that file** — never
   merged across files, because signal names collide across classes with different arities
   (`died` is bare in three files, one-`Vector2`-argument in a fourth; see `1-context.md`).
4. Per (comment-stripped) file, regex-finds every **self-emit** call site — `name.emit(` where
   `name` is not itself preceded by a `.` (i.e. not `something.name.emit(`, which is a call
   through a member/autoload reference on a signal declared in a *different* file, out of reach of
   a per-file text sweep).
5. For each self-emit whose `name` matches a signal declared in the same file, counts the actual
   argument list with a paren/bracket/brace/string-aware scan starting at the `emit(`'s opening
   paren, run against the **original, non-comment-stripped** file text (comment stripping is only
   for finding declarations/call sites; multi-line arg lists must see real source, and stripping
   is line-based so it must not be applied twice) — not a line-based split, since
   `dash_panel.gd`'s multi-line `body_wall_hit.emit(...)` call needs this — and asserts it equals
   the declared arity.
6. On mismatch, fails with the file, line, signal name, declared arity and counted arity — enough
   to fix without re-deriving the scan.

This is a generalization of the two existing hand-written assertions
(`test_amount_changed_declares_the_int_it_emits`, `test_state_transition_declares_the_state_it_emits`),
not a replacement — those stay, since they also assert the *type* of the argument
(`TYPE_INT`, `TYPE_OBJECT`), which a project-wide arity sweep does not attempt.

### Alternatives rejected

- **Full type-resolution to also cover member-access emits** (`hb.received_damage.emit(...)`,
  `EventBus.x.emit(...)`) — would need to infer the static type of every LHS expression across
  files, which is a mini type-checker, not a text sweep. Given the project's existing sweep tests
  (`test_resource_uid_integrity.gd`, `test_enemy_contact_damage.gd`) all stay at the
  regex-over-source-text level and accept a bounded scope, self-emit-only matches that convention
  and still covers the exact pattern both real incidents were (`amount_changed.emit(...)` inside
  `health_component.gd`, `state_transition.emit(...)` inside `state.gd`/its states). Out of scope
  below records the gap explicitly rather than silently.
- **Parsing with Godot's own GDScript tokenizer/AST** instead of regex — no such API is exposed to
  a GUT test at runtime in 4.6; every existing sweep test in this repo works at the regex-over-text
  level for the same reason.
- **Asserting via `get_signal_list()` on an instantiated object for every file**, rather than a
  regex declaration-arity extraction — would require instantiating every script (many require
  scene context, autoload dependencies, or `_init()` arguments) just to read its signal list. The
  UID integrity test already established that reading declarations from disk is both cheaper and
  immune to `.godot/` cache/instantiation side effects; the emitted side has no engine-exposed
  equivalent at all, so it has to be a text scan regardless — keeping the declared side as text too
  keeps one code path instead of two.

## Build sequence

1. Write `tests/integration/test_signal_emit_arity.gd` with the file walk, declaration regex, and
   a private `_count_top_level_args(text, open_paren_index)` helper (paren/bracket/brace depth +
   quote-aware).
2. Add one `test_all_self_emits_match_their_declared_arity()` that walks every file, builds the
   per-file declared map, finds self-emit call sites, and asserts counted == declared with a
   descriptive failure message (file:line, signal, declared, actual).
3. Add boundary-case tests that feed the helpers synthetic snippets directly, so each is pinned
   independently of whatever the codebase currently contains:
   - `test_helper_counts_top_level_args_with_no_args()`, `..._across_multiple_lines()`,
     `..._does_not_split_a_comma_inside_a_string_argument()` for `_count_top_level_args` (zero
     args, a multi-line `if/else`-expression call mirroring `dash_panel.gd`, and a string literal
     containing a comma).
   - `test_declared_arity_ignores_a_trailing_comment()` — `signal foo(x: int)  ## some, note`
     must parse as arity 1, not choke on the comment's comma.
   - `test_declared_arity_handles_a_nested_generic_param()` — a synthetic
     `signal foo(order: Array[int], other: int)` must parse as arity 2, since the comma inside
     `Array[int]`'s brackets is not a parameter separator (mirrors `race_director.gd`'s
     `Array`-typed params, extended with the bracketed-generic case that file doesn't happen to
     use, so a future edit to the regex can't silently regress it unnoticed).
   - `test_comment_stripping_does_not_hide_a_real_self_emit()` — a synthetic same-file
     `signal foo(x: int)` / `foo.emit(1, 2)` pair with a decoy comment
     (`## foo.emit() takes zero args`) on an earlier line must still be caught as a mismatch —
     proving the comment strip removes only the comment, not the real call site beneath it.
4. Run the new test file alone via the GUT cmdline pointed at it, confirm all pass, then run the
   full suite to confirm the project's current ~150 self-emit call sites contain no real
   mismatches (expected — the two known ones are already fixed).
5. `bash /agent/verify.sh`.

Each step is independently checkable: step 1-2 is the sweep itself, step 3 the boundary cases
proving each helper is correct rather than accidentally-agreeing with today's source text, steps
4-5 are verification.

## Test plan

- `test_all_self_emits_match_their_declared_arity()` — the sweep itself; failure message includes
  file, line, signal name, declared arity, counted arity.
- `test_helper_counts_top_level_args_with_no_args()` — `emit()` → 0.
- `test_helper_counts_top_level_args_across_multiple_lines()` — synthetic multi-line snippet
  modeled on `dash_panel.gd:83-84` → asserts the actual argument count (5), not the count a
  per-line split would silently produce.
- `test_helper_does_not_split_a_comma_inside_a_string_argument()` — `emit(pos, points, "a, b")` →
  3, not 4. Mirrors real call sites like `score_tracker.gd`'s `EventBus.score_event.emit(kill_pos,
  points, "kill" if counts_in_wave else "bonus_target")` even though that one is a member-access
  emit out of the sweep's own scope — the helper must still be correct on it in isolation.
- `test_declared_arity_ignores_a_trailing_comment()` and
  `test_declared_arity_handles_a_nested_generic_param()` — pin the declaration-side parser the
  same way, per reviewer round 1's required change (see `4-review.md`).
- `test_comment_stripping_does_not_hide_a_real_self_emit()` — proves the comment strip added for
  round 1 doesn't remove a genuine call site along with a decoy comment above it.

## Risks

- **False positive on a self-emit whose target signal isn't declared in the same file** (e.g. an
  inherited signal re-emitted by a subclass by name, if that pattern exists anywhere). Mitigated
  by only asserting when the name is found in *that file's* declaration map — if not found, the
  call site is silently skipped, matching the member-access exclusion already in the design.
- **Regex declaration parser mis-parsing a typed default or nested generic** (e.g.
  `Array[RaceParticipant]` inside a param list) — checked directly against
  `race_director.gd`'s `standings_changed(order: Array)` / `race_finished(results: Array)`
  during implementation; comma-splitting is only ever done at bracket-depth 0 relative to the
  param list, same depth-aware approach as the emit-arg counter.

## Out of scope

- Member-access emit call sites (`hb.received_damage.emit(...)`, `EventBus.*.emit(...)`,
  `t.destroyed.emit(t)`) — see Alternatives rejected. Left as a known, documented gap rather than
  attempted with an approach likely to false-positive on legitimate cross-file emits.
- `emit_signal("name", ...)` (Godot 4's string-based emit form) — confirmed by grep to be unused
  anywhere in the project today, so not scanned for. A future call site written this way would be
  invisible to this sweep.
- Re-litigating or replacing the two existing hand-written type-checking tests.
- Any change to signal declarations themselves — this is a test-only task; if the sweep finds a
  live mismatch it becomes a new bug task, not an in-place fix bundled into this one.
