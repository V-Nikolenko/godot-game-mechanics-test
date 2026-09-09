# Review: flying-into-a-log-record-in-open-space-picks-it-up-and-tells

VERDICT: CHANGES_REQUESTED

## Findings

### 1. Test case 4 will leave a permanently-suspended `DialogPlayer.play()` coroutine — contradicts the leak-detection gate (Correctness / test-plan defect)

`3-plan.md:114-118` (case 4) calls the real `_on_body_entered(player_stub)` on a live, in-tree
`LoreLogPickup`. Since the fixture catalogue is non-empty at that point, `_get_dialog_text()`
returns a non-empty string, so `pickup_base.gd:36-49` (`_show_notification`) calls
`DialogPlayer.play(script_res)`.

I traced what `play()` actually does (`global/autoload/dialog_player.gd:34-92` +
`global/ui/dialog_system/ui/dialog_box.gd`):
- `await _box.present_line(line)` resolves on its own once the fade-in tween (0.22s) and the
  INSTANT reveal complete — no player input needed.
- The non-auto-mode branch then does `await _box.line_finished`. `line_finished` is only emitted
  by `DialogBox.advance()` (called from real player input) or `DialogBox.close_now()` /
  `_force_close()` (called from `DialogPlayer.skip_dialog()`). **Nothing in the plan's test 4
  calls either**, so this await never resolves.

This is exactly the class of bug `tests/README.md:393-404` and `scripts/check-test-leaks.sh`
document at length for `LevelDirector`: a suspended `GDScriptFunctionState` that the gate's
`FATAL` regex does not catch, reported only as `ObjectDB instances leaked` /
`resources still in use` *after* GUT has already set the exit code — "the gate stays green
while leaking." Beyond the leak itself, `DialogPlayer.is_active` is left `true` for the rest of
the suite, which is exactly what `tests/unit/test_dialog_player.gd:12-15`'s `before_each()`
asserts is never true at the start of a test — a real risk of cross-test contamination
depending on run order, not just a leak at process exit.

The plan's own "Risks" section (`3-plan.md:120-126`) waves this off with a false precedent: "matching
how `test_dialog_player.gd` and `test_weapon_unlock_sources.gd` interact with `DialogPlayer`
without driving a full typewriter run to completion." I checked both:
- `tests/unit/test_dialog_player.gd:43-52` only ever calls `DialogPlayer.play(null)` and
  `play(empty)` — both guarded and return **before** entering the play loop at all (`dialog_player.gd:38-45`).
  They never reach a suspended await.
- `tests/integration/test_weapon_unlock_sources.gd:130-142`'s
  `test_collecting_an_unlocker_actually_unlocks_the_mode` deliberately calls `pickup._collect(null)`
  directly, **not** `_on_body_entered`, precisely to avoid touching `DialogPlayer`/notification at
  all (its own comment: "It calls `_collect()` directly rather than driving `body_entered`... proves
  the effect, not the trigger").
- I grepped the whole `tests/` tree for `_on_body_entered`, `DialogPlayer.play`, and
  `skip_dialog`: no existing test calls `_on_body_entered` on a pickup with non-empty dialog text,
  and the only `skip_dialog()` call in the suite is the trivial idle no-op case. There is no
  existing precedent for what test case 4 proposes to do, contrary to the plan's claim.

**Fix**: case 4 needs to either not exercise the real notification path (assert via `_collect()` +
`_get_dialog_text()` as cases 1-3 already do, which is sufficient to prove the wiring since
`PickupBase._on_body_entered` is otherwise already covered project-wide per the plan's own
rationale), or, if it keeps calling `_on_body_entered`, it must call `DialogPlayer.skip_dialog()`
(and ideally assert `DialogPlayer.is_active` is `false` again afterward) before the test ends so
the coroutine actually resolves. Either way, `scripts/check-test-leaks.sh` needs to be run once
the test is written, per CLAUDE.md's instruction to run it "after touching anything that awaits."

## Things I checked and did not find a problem with

- **Reuse**: `_collect()`/`_get_dialog_text()` is the correct, minimal hook pair —
  `global/pickups/pickup_base.gd:26-33` — and the plan does not reimplement any part of
  collection, notification, or double-count logic. `LogState.collect_next()`/`get_entry()`
  (`global/autoloads/log_state.gd:64-78`) already have the no-op-when-exhausted contract the plan
  describes verbatim, and are already tested (`tests/unit/test_log_state.gd:70-84`).
- **Fixture claims verified against the actual `.tres` files**
  (`tests/unit/fixtures/log_entries/entry_b.tres`): `entry_beta` has `sequence = 0` (lowest) and
  `title = "Test Entry Beta"`, matching the plan's cases 1-2 exactly.
- **Scope boundary**: the task's own "Done when" bullet in `BACKLOG.json` (task
  `flying-into-a-log-record-in-open-space-picks-it-up-and-tells`) is narrower than the "Player
  outcome" prose: "a `lore_log_pickup.tscn` exists under `global/pickups/scenes/`... collecting it
  advances `LogState`, collecting it twice in one run cannot double-count, and the notification
  text names the entry. Test in `tests/unit/`." Placement in `sector_hub.tscn` is not part of this
  task's actual acceptance criteria and is explicitly owned by a later epic task — excluding it is
  correct, not a scope-boundary error.
- **CLAUDE.md conventions**: no hand-typed/copied `uid://` (plan defers to a proper mint or a
  UID-less reference); no new signals (arity rule N/A); pickups correctly live under
  `global/pickups/` per the 9 existing siblings; `create_map_object` is the skill's documented
  correct tool for a pickup sprite (`.claude/skills/pixel-art-generation/SKILL.md:95`).
- **No simpler unexamined alternative**: the rejected `@export var entry_id` alternative is sound
  reasoning — `LogState.collect_next()` genuinely has no id parameter and its docstring explains
  why.
- Test cases 1-3 assert real, falsifiable behavior (collected count, specific id, dialog text
  content, exhaustion boundary) against the actual `_collect()`/`_get_dialog_text()` code shown in
  the plan — none of them is a tautology.

## Round 2

VERDICT: CHANGES_REQUESTED

### 1. The revised case 4 calls `skip_dialog()` before `play()`'s coroutine has reached the await it's meant to unblock — the fix is based on a false timing premise and does not resolve the leak (Correctness / test-plan defect)

`3-plan.md:118-121` now has case 4 call `DialogPlayer.skip_dialog()` and assert
`DialogPlayer.is_active == false` "immediately after" `_on_body_entered()` returns. I traced the
exact call stack this produces, and the premise — that by this point `play()`'s coroutine is
parked at `await _box.line_finished` — is wrong.

`_on_body_entered` (`global/pickups/pickup_base.gd:13-23`) calls `_show_notification(text)`
(no `await`), which calls `DialogPlayer.play(script_res)` (`pickup_base.gd:49`), also with no
`await`. Godot still runs an un-awaited coroutine synchronously up to its first internal suspend
point before returning control to the caller. Following that chain:

- `play()` (`dialog_player.gd:64-71`) enters the `for` loop and reaches
  `await _box.present_line(line)` (`dialog_player.gd:71`).
- `present_line()` (`dialog_box.gd:52-107`) runs synchronously up through building the fade-in
  tween and hits `await _fade_in_tween.finished` (`dialog_box.gd:100-103`) — a genuine suspend
  point that requires the engine to actually process ~0.22s of frames (`_FADE_SEC`,
  `dialog_box.gd:35`) for the tween to complete. No frames are processed inside a synchronous
  test method.

So by the time `_on_body_entered()` returns to the test, execution is parked at
`await _fade_in_tween.finished` inside `present_line()` — an *earlier* await than
`await _box.line_finished` inside `play()` (`dialog_player.gd:84`), which has not been reached at
all yet. This is exactly the ordering hazard the task brief asked me to check for, and it's real.

Calling `skip_dialog()` at this point (`dialog_player.gd:95-99`) calls `_box.close_now()` →
`_force_close()` (`dialog_box.gd:209-219`), which does `_fade_in_tween.kill()`. Per this same
file's own documented behavior for the analogous `_typing_tween` (`dialog_box.gd:169`: "kill()
does NOT emit finished in Godot 4" — the reason `skip_typing()` has to manually
`typing_completed.emit()` afterward at `dialog_box.gd:173`), killing `_fade_in_tween` does **not**
emit `finished`. `_force_close()` has no equivalent manual resolve for the FADE_IN case — it only
emits `line_finished` (`dialog_box.gd:219`), which nothing is awaiting yet since `play()` never
got past `await _box.present_line(...)`.

Net effect of calling `skip_dialog()` at this point:
- `present_line()`'s `await _fade_in_tween.finished` is now **permanently** stuck — the tween is
  killed and will never fire `finished`, whereas before this call it would eventually have
  resolved on its own once real frames elapsed.
- `play()`'s `await _box.present_line(line)` is therefore also permanently stuck, so `play()`
  never reaches its own `for` loop's post-`present_line` code, never reaches `_finish()`
  (`dialog_player.gd:90-91, 102-110`), and `is_active` is **never set back to `false`**.
- The `line_finished` emitted by `_force_close()` is emitted into the void (no listener yet) and
  lost.

Consequently the test's own new assertion, `assert DialogPlayer.is_active == false`
(`3-plan.md:119`), would **fail** — this isn't merely a leak that slips past the gate's `FATAL`
regex as in round 1's finding, it's a test that doesn't pass GUT at all under the trace above. And
even setting the assertion aside, the leak is not fixed: instead of one suspended coroutine parked
on `line_finished` (which at least *could* be resolved by a correctly-timed `skip_dialog()` call),
there are now two nested suspended coroutines, one of them parked on a tween that has been
explicitly killed and can never complete.

**This doesn't work as written.** A correct fix needs to either (a) let `present_line()`'s
fade-in actually complete before calling `skip_dialog()` — e.g. `await` real time past
`_FADE_SEC` (0.22s) first, so `play()` genuinely reaches `await _box.line_finished` before
`skip_dialog()` is called, which the plan's own "Risks" section (`3-plan.md:123-133`) says it
wants to avoid ("driving a full typewriter run to completion"), or (b) avoid entering the
`DialogPlayer.play()` path at all for this case, e.g. by setting `DialogPlayer.is_active = true`
before calling `_on_body_entered()` so `_show_notification`'s guard (`pickup_base.gd:39-40`)
short-circuits it — case 4's stated purpose is proving `_on_body_entered`'s wiring through
`PickupBase` (collect + queue_free), which cases 1-3 plus this guard-triggered no-op notification
path can still establish without ever starting a real `play()` coroutine. Round 1's suggested fix
(sidestep the real notification path) remains the safer option; round 2 took the other branch and
implemented it incorrectly.

### Other sections re-checked

- "Risks" (`3-plan.md:123-133`) still correctly identifies *that* an unresolved await is the
  danger and correctly points at `scripts/check-test-leaks.sh`, but its claim that calling
  `skip_dialog()` "before the test ends" is sufficient is the same false premise as the test case
  itself — it doesn't account for *when* in the coroutine chain that call lands.
- Build sequence (`3-plan.md:75-85`) is unaffected by this issue and still internally consistent.
- Everything else re-verified against round 1 (art, scene shape, scope boundary, `LogState`
  reuse) is unchanged from round 1's plan and still holds.
