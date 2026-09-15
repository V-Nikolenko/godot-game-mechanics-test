# Context

## The mechanism

`ScoreTracker._on_enemy_freed()` (`assault/scenes/systems/score_tracker/score_tracker.gd:197-215`)
fires on every enemy's `tree_exited`, for **every** enemy, unconditionally:

```gdscript
func _on_enemy_freed(enemy: Node, wave_index: int, counts_in_wave: bool) -> void:
	if not is_instance_valid(enemy) or enemy.get("was_killed"):
		return
	if not _running:
		return
	if counts_in_wave:
		... # wave-tally bookkeeping, unrelated to the combo
	# Combo penalty for letting an enemy slip past.
	_combo *= score_config.escape_combo_multiplier
	...
```

`counts_in_wave` (read from `counts_toward_wave_clear`) only gates the wave-clear tally logic. The
combo multiply below it is **not** gated by anything — every enemy that leaves the tree without
`was_killed` costs `escape_combo_multiplier` (0.75), regardless of `wave_index` or
`counts_toward_wave_clear`.

## The two ad-hoc spawn sources

Both route through `EventBus.enemy_spawned_orphan` / `wave_manager.enemy_spawned` with
`wave_index == -1`, which is the same "outside the wave registry" idiom.

### 1. Station reinforcements — `assault/scenes/enemies/space_station/station_reinforcements.gd:230-258`

`_spawn_entry()` emits `EventBus.enemy_spawned_orphan` and carries a long, explicit comment
(added in commit `9079a20`, "Station reinforcements (EPIC sub-item 4b)") stating this is
**deliberate**:

> It also opts these ships into the game's UNIVERSAL escape penalty... That is a deliberate
> balance decision, not an oversight — adds are a combo *opportunity*, and the alternative (no
> emit) means killing one awards nothing at all, which reads as a bug.

`tests/integration/test_station_reinforcements.gd:394-423`
(`test_a_squad_that_flies_through_costs_two_escape_combo_penalties`) pins the exact number:
`4.0 * 0.75 * 0.75 = 2.25`. This is a considered, tested, documented design choice — not a bug.

### 2. Bonus drone — `assault/scenes/levels/edelia/1/level_1_director.gd:110-144` +
`assault/scenes/enemies/bonus_drone/bonus_drone.gd`

`_spawn_bonus_drone()` emits `wave_manager.enemy_spawned.emit(entity, -1)` directly (same -1
idiom). `BonusDrone`'s own header comment states the **opposite** of what happens:

```gdscript
## BonusDrone — rare, fast, non-shooting medal target.
##
## Awards a large score chunk on kill, with no penalty for missing it
## (counts_toward_wave_clear = false on its config). ...
```

"No penalty for missing it" is only true for the wave-clear tally. `counts_toward_wave_clear`
does not reach the escape-combo multiply at all — a missed drone (it despawns via
`EnemyPathMover.exit_time = 4.0`, `FREE_ON_DURATION`) still multiplies the combo by 0.75 in
`_on_enemy_freed`, exactly like any other escaped enemy. This is a **contradiction between
documented intent and actual behaviour** — nobody deliberated this one; the comment describes the
design the author believed they'd built and the drone's own `counts_toward_wave_clear = false`
plausibly reads as "opts out of everything," which it doesn't.

No test currently exercises the drone's escape path.

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/resources/ship_config.gd:13` `counts_toward_wave_clear` | The exact pattern to mirror for a second, independent opt-out flag: an `@export var` on `ShipConfig`, propagated in `BaseEnemy._ready()` (`base_enemy.gd:60-64`) via the generic `get("config")` idiom, so no per-subclass wiring is needed. |
| `score_tracker.gd:134-135` | The `enemy.get(x) != null` fallback idiom already used for `counts_toward_wave_clear`, safe on `AsteroidBase` and anything else with no such property (defaults to today's behaviour, i.e. `true`). |
| `assault/scenes/enemies/bonus_drone/bonus_drone_config.tres` | Where `counts_toward_wave_clear = false` already lives; the new flag is one more line here. |
| `tests/integration/test_station_reinforcements.gd:408-423` | Must keep passing unchanged — proves the reinforcements case is untouched. |

## Conventions that constrain this

- Config-driven stats: a new balance flag belongs on `ShipConfig`/subclass `.tres`, not hardcoded
  per enemy class (`CLAUDE.md` "Config-driven enemies").
- `ShipConfig.privatise()` requires configs stay flat for the shallow `duplicate()` to be complete
  (`tests/integration/test_config_instance_isolation.gd`) — a plain `bool` is safe.
- Signal arity: no signals change shape here.
- The task body explicitly asks for a general flag ("a `counts_as_escape` flag on the spawn
  rather than a special case for one enemy source"), not an `if enemy is BonusDrone` branch in
  `ScoreTracker`.

## Decision this plan must make

Whether to touch the **reinforcements** balance at all. Precedent:
`docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-/` is an earlier
"design question, not a bug" backlog item; its resolution was to answer the question with
reasoning and pin the answer with a test, without necessarily changing production behaviour.

This plan's answer: **no** — reinforcements' double penalty is called out in the task body itself
as *already, deliberately, and correctly accepted* (commit `9079a20`), pinned by an existing test
with a comment explaining why exempting it would itself read as a bug (free kills). Re-opening
that call here would silently overrule a previous cycle's considered decision on no new
information. The **bonus drone** case is different in kind: its own doc comment asserts behaviour
the code does not deliver, which is a plain contradiction, not a balance judgement call — that
is the part this plan fixes.
