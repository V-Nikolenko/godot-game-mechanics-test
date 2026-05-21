# Assault Mission — Enemy Spawning & Scoring Internals

**Audience:** developers working on the assault mission codebase.
For the player-facing rules see `docs/scoring_guide.md`.
For the original design spec see `docs/superpowers/specs/2026-05-20-scoring-system-design.md`.

---

## 1. Overview

Three systems collaborate to run each assault mission section:

```
LevelDirector
  └─ advances sections, calls WaveManager.load_section()

WaveManager
  └─ times spawns within a section
  └─ emits enemy_spawned(entity, wave_index) → ScoreTracker

ScoreTracker
  └─ wires die/escape signals onto each enemy
  └─ does all scoring math
  └─ broadcasts results via EventBus (score_changed, combo_changed, score_event)
```

All signal connections between these systems are made at runtime, not in the
scene tree. The level scene only needs the three nodes to be siblings and their
`@export` references wired in the Inspector.

---

## 2. Enemy spawning pipeline

### 2.1 Sections and waves

A **section** (`LevelSection`) is a named phase of the level (e.g., `deep_space`,
`asteroid_belt`, `planet_approach`). Each section owns an array of
`WaveResource` objects — the waves that run during that phase.

`LevelDirector._advance()` is called at the end of every section (or
immediately at start). It calls:

```gdscript
wave_manager.load_section(section.waves)
```

`load_section` resets the wave clock to zero and re-indexes waves from 0:

```gdscript
func load_section(waves: Array[WaveResource]) -> void:
    _waves.clear()
    _next_wave_index = 0   # ← always resets to 0
    _time_elapsed    = 0.0
    ...
    section_loaded.emit()  # ScoreTracker listens to this
    set_process(not _waves.is_empty())
```

**Important:** wave indices are section-local. Section 1's wave 0 and section
2's wave 0 are completely separate waves. See §5 for why this matters.

### 2.2 Wave timing

`WaveManager._process(delta)` advances `_time_elapsed` each frame and
fires any wave whose `trigger_time <= _time_elapsed`:

```
t = 0.0 s   → wave 0 triggers (5 fighters in V formation)
t = 2.0 s   → wave 1 triggers (2 drones)
t = 5.0 s   → wave 2 triggers (3 fighters U-sweep)
...
```

When a wave triggers, `_trigger_wave(wave, index)` iterates its spawn
descriptors, expands any formation into one descriptor per slot, then calls
`_spawn_with_delay(spawn)` for each. Spawns inside a wave can have an
individual `delay:` float, so a V-formation of 5 can stagger its arrivals by
`0.0, 0.1, 0.2, 0.3, 0.4 s`.

### 2.3 _spawn_ship in detail

```gdscript
func _spawn_ship(spawn: Dictionary) -> void:
    var cam  := get_viewport().get_camera_2d()
    var pos  := cam.global_position + spawn.get("offset", Vector2.ZERO)
    var entity: Node = scene.instantiate()
    entity.global_position = pos

    if spawn.has("on_spawned"):          # initial property overrides
        spawn.on_spawned.call(entity)

    enemy_container.add_child(entity)   # _ready() fires here

    enemy_spawned.emit(entity, wave_idx) # ScoreTracker hooks up here

    if spawn.has("movement"):           # attach EnemyPathMover
        var mover := EnemyPathMover.new()
        mover.movement  = spawn["movement"]
        mover.exit_mode = spawn.get("exit_mode", FREE_ON_SCREEN_EXIT)
        ...
        entity.add_child(mover)
```

Key ordering:
1. `add_child` — `_ready()` runs on the enemy; health, hurtbox, stats all set up.
2. `enemy_spawned.emit` — ScoreTracker connects to `died` and `tree_exited`
   AFTER the enemy is fully initialised.
3. `EnemyPathMover.add_child` — starts driving position next physics frame.

### 2.4 EnemyPathMover exit modes

`EnemyPathMover` has two exit strategies:

| Mode | Behaviour |
|------|-----------|
| `FREE_ON_SCREEN_EXIT` (default) | Watches viewport bounds; frees the actor when it has been on-screen and then crosses the margin (80 px). Guards against culling pre-entry enemies with `_has_been_on_screen` flag. |
| `FREE_ON_DURATION` | Frees after `exit_time` seconds (or `movement.total_duration()` if `exit_time == 0`). Used for enemies that follow a fixed-length path regardless of screen position. |

Both exit modes call `_actor.queue_free()` on the **actor** (the enemy
CharacterBody2D), not on the mover itself. The mover is a child, so it is freed
with the actor.

### 2.5 Orphan enemies (asteroid splits)

When `BigAsteroid` is destroyed it spawns 2–4 `SmallAsteroid` shards. These are
not managed by `WaveManager` at all; instead `BigAsteroid._on_destroyed()`:

```gdscript
parent.call_deferred("add_child", small)          # deferred: safe during physics
call_deferred("_announce_shard", small)            # deferred: fires AFTER add_child

func _announce_shard(shard: Node) -> void:
    if is_instance_valid(shard):
        EventBus.enemy_spawned_orphan.emit(shard)  # ScoreTracker listens
```

Both calls go into Godot 4's global `MessageQueue` (FIFO). Because `add_child`
is queued first, the shard's `_ready()` has run by the time `enemy_spawned_orphan`
fires, so `score_value` and other exported properties already hold their correct
scene-file values.

`ScoreTracker._on_orphan_spawned` calls `_on_enemy_spawned(enemy, -1)`.
Wave index −1 means "no wave clear contribution" — the shard is tracked for
individual kill score only.

### 2.6 Bonus drone spawning

Bonus drones bypass `WaveManager` entirely and are spawned directly by
`Level1Director._spawn_bonus_drone()`. After `add_child` the director manually
emits the signal:

```gdscript
wave_manager.enemy_spawned.emit(entity, -1)
```

Wave index −1 again — bonus drones have `counts_toward_wave_clear = false`
on their config so they are excluded from wave tallies.

---

## 3. Scoring pipeline

### 3.1 Tracking life-cycle

`ScoreTracker.start_tracking()` is called by `Level1Director` at level start.
It connects:

| Signal | Source | Handler |
|--------|--------|---------|
| `enemy_spawned` | WaveManager | `_on_enemy_spawned` |
| `section_loaded` | WaveManager | `_on_section_loaded` |
| `enemy_spawned_orphan` | EventBus | `_on_orphan_spawned` → `_on_enemy_spawned` |
| `player_health_changed` | EventBus | `_on_player_health_changed` |
| `skill_challenge_completed` | EventBus | `_on_skill_completed` |

`stop_tracking()` is called when the level ends. It marks any still-open wave
tallies as `escaped = true` so no wave-clear bonus can fire retroactively.

### 3.2 Per-enemy wiring (_on_enemy_spawned)

For every enemy, `ScoreTracker` connects two one-shot signals:

```gdscript
# Kill path — fires when health reaches zero
enemy.died.connect(
    _on_enemy_died.bind(enemy, wave_index, base_value, counts_in_wave),
    CONNECT_ONE_SHOT
)

# Escape path — fires when the node exits the scene tree for any reason
enemy.tree_exited.connect(
    _on_enemy_freed.bind(enemy, wave_index, counts_in_wave),
    CONNECT_ONE_SHOT
)
```

`CONNECT_ONE_SHOT` ensures each handler runs **exactly once** per enemy,
regardless of how many times `tree_exited` might otherwise fire.

Because an enemy that is **killed** will trigger both signals (it emits `died`,
then `queue_free()` causes `tree_exited`), `_on_enemy_freed` guards against
double-counting with:

```gdscript
func _on_enemy_freed(enemy: Node, ...) -> void:
    if not is_instance_valid(enemy) or enemy.get("was_killed"):
        return   # died handler already ran; nothing to do
    ...          # escape path: combo penalty, mark tally escaped
```

`was_killed` is set to `true` in `BaseEnemy._on_health_changed` and
`AsteroidBase._on_health_changed` **before** `died.emit()`, so it is always
readable when `tree_exited` fires.

### 3.3 Kill flow

```
Weapon hits HurtBox
  → HurtBox.received_damage(damage)
  → BaseEnemy._on_received_damage → health.decrease(damage)
  → Health.amount_changed(0)
  → BaseEnemy._on_health_changed(0):
      was_killed = true
      died.emit()               ← ScoreTracker._on_enemy_died fires here
      _explosion_effect.explode()
      queue_free()              ← later: tree_exited fires, _on_enemy_freed returns early
```

Inside `_on_enemy_died`:

```gdscript
var points := int(floor(base_value * _combo))
_total_score += points
_combo = minf(_combo + combo_step, combo_cap)   # grow multiplier
_combo_decay_remaining = combo_decay_seconds     # reset decay timer
EventBus.score_changed.emit(_total_score)
EventBus.combo_changed.emit(_combo, _combo_decay_remaining)
EventBus.score_event.emit(kill_pos, points, "kill")
if counts_in_wave:
    _maybe_award_wave_clear(wave_index, tally, kill_pos)
```

### 3.4 Escape flow

```
EnemyPathMover._check_off_screen → _actor.queue_free()
  (or enemy's own _check_off_screen → queue_free)

end-of-frame: actor freed → tree_exited
  → ScoreTracker._on_enemy_freed:
      if was_killed → return (it was actually a kill, handled above)
      tally.escaped = true; tally.resolved = true
      _combo *= escape_combo_multiplier   # 0.75 — penalty
      EventBus.combo_changed.emit(...)
```

No score is ever awarded in the escape path. Only the combo is penalised.

### 3.5 Wave-clear bonus

`_maybe_award_wave_clear` is called after every kill that `counts_in_wave`.
It fires the bonus only when all conditions are satisfied:

```gdscript
func _maybe_award_wave_clear(wave_index, tally, kill_pos) -> void:
    if tally.resolved:  return   # already paid or already denied
    if tally.escaped:   return   # at least one enemy fled
    if tally.killed < tally.expected: return   # wave not fully cleared yet
    tally.resolved = true
    var bonus := int(tally.base_value_sum *
        (wave_clear_base_multiplier + wave_clear_per_enemy_bonus * tally.expected))
    _total_score += bonus
    EventBus.score_event.emit(kill_pos, bonus, "wave_clear")
```

`WaveTally` fields:

| Field | Set by | Meaning |
|-------|--------|---------|
| `expected` | `_on_enemy_spawned` (once per enemy that counts) | Total enemies the wave must contribute |
| `killed` | `_on_enemy_died` | Kills so far for this wave |
| `base_value_sum` | `_on_enemy_spawned` | Sum of base scores for bonus formula |
| `escaped` | `_on_enemy_freed` | Any enemy fled → bonus impossible |
| `resolved` | bonus paid OR first escape | Prevents double-pay |

### 3.6 Other score sources

| Source | Trigger | Amount |
|--------|---------|--------|
| Survival tick | Every 15 s of damage-free play (`_process`) | +50 pts flat |
| Skill challenge (clean) | `EventBus.skill_challenge_completed(true, bonus)` | Configurable (default 500) + combo nudge |
| Skill challenge (partial) | `EventBus.skill_challenge_completed(false, bonus)` | Configurable (default 150) |

Survival ticks emit `score_event(pos, 50, "survival")` → green "SAFE +50" popup in the HUD.

---

## 4. Score events and HUD

`EventBus.score_event(world_position, points, reason)` is the single channel
between scoring logic and UI. `ScorePopupSpawner` listens to it and instantiates
a floating `ScorePopup` label at the world-space kill position for each event.

| `reason` string | Popup text | Colour |
|-----------------|-----------|--------|
| `"kill"` | `+N` | White |
| `"wave_clear"` | `WAVE! +N` | Gold |
| `"bonus_target"` | `BONUS +N` | Gold |
| `"survival"` | `SAFE +N` | Green |
| `"skill_clean"` | `PERFECT! +N` | Cyan |
| `"skill_partial"` | `SURVIVED +N` | Orange |

`HUDScoreWidget` subscribes to `score_changed` (total score) and
`combo_changed` (multiplier + decay seconds). The score label tweens from the
previous displayed value to the new total over 0.4 s so large gains feel
satisfying rather than snapping instantly.

---

## 5. The wave-index collision bug (and fix)

### What went wrong

`WaveManager.load_section()` resets `_next_wave_index = 0` on every section
transition. This means **section 1's wave 0 and section 2's wave 0 share the
same dictionary key** inside `ScoreTracker._wave_state`.

Two failure modes depending on what state section 1 left behind:

**Case A — section 1's wave 0 was fully resolved (all enemies killed)**

`WaveTally` at key `0` has `resolved = true`. When section 2 starts, new
enemies are added to `tally.expected` (it grows past what section 2 alone
needs). `_maybe_award_wave_clear` always returns early because
`tally.resolved = true`. The player kills every enemy in section 2's wave 0
and receives **no wave-clear bonus**.

**Case B — section 1's wave 0 had enemies still alive when the section changed**

`WaveTally` at key `0` has `resolved = false`, `killed < expected`. When
section 2 starts, its enemies pile onto the same tally. If the combination of
"section 1 leftover kills + section 2 kills" satisfies `killed >= expected`,
`_maybe_award_wave_clear` fires — the player sees a **wave-clear popup at an
unexpected moment**, appearing to award score without the player consciously
clearing any wave.

### The fix

Three changes were made (commit `31b7e49`):

**1. `WaveManager.load_section()` now emits `section_loaded`**

```gdscript
signal section_loaded   # added at class level

func load_section(...) -> void:
    ...
    section_loaded.emit()   # before set_process, before any new spawns
    set_process(...)
```

**2. `ScoreTracker.start_tracking()` connects to `section_loaded`**

```gdscript
if not wave_manager.section_loaded.is_connected(_on_section_loaded):
    wave_manager.section_loaded.connect(_on_section_loaded)

func _on_section_loaded() -> void:
    _wave_state.clear()
```

Clearing `_wave_state` at the start of each new section means every section's
wave indices begin fresh. Enemies from the **previous section that are still
alive** keep their `died`/`tree_exited` connections and still award individual
kill score — they just no longer contribute to any wave-clear tally (which is
correct; a leftover enemy from section 1 should not influence section 2's
bonuses).

**3. `BigAsteroid._on_destroyed()` defers the orphan emit**

Before the fix, `enemy_spawned_orphan` was emitted **immediately** while
`add_child` was still deferred. ScoreTracker was therefore connecting to shard
nodes whose `_ready()` hadn't run yet, meaning exported properties like
`score_value` still held their default (`0`) rather than the scene-file value.

The fix defers the emit via a second deferred call:

```gdscript
parent.call_deferred("add_child", small)     # queued at position N
call_deferred("_announce_shard", small)      # queued at position N+1

func _announce_shard(shard: Node) -> void:
    if is_instance_valid(shard):
        EventBus.enemy_spawned_orphan.emit(shard)
```

Godot 4's global `MessageQueue` is processed FIFO, so `add_child` (position N)
always runs before `_announce_shard` (position N+1).

**4. `_on_enemy_freed` defensive guard**

```gdscript
if not is_instance_valid(enemy) or enemy.get("was_killed"):
    return
```

`is_instance_valid` handles the edge case where the node is freed before the
deferred orphan announce fires (e.g., if section changes between spawn and
announce). Without it, `get("was_killed")` on a freed node would return `null`
(falsy), causing the escape path to run on a phantom node.

---

## 6. Common confusion: why does score appear without obvious kills?

Two legitimate sources of score that can look "unexpected":

### Survival ticks
Every **15 seconds** of damage-free play, `_award_survival()` fires and emits a
green **"SAFE +50"** popup. This is entirely time-based and has nothing to do with
enemies. It is reset when the player takes damage, then starts counting again.
If a survival tick fires at the same moment an enemy flies off-screen, it can
look like the escape caused the score.

### Asynchronous missile kills
Homing missiles launched by the player continue tracking and detonating seconds
after the player has moved on to another part of the screen. A kill popup from a
missile the player has forgotten about will appear to come "from nowhere".

### No longer: wave-index collision (fixed)
Before the fix described in §5, Case B could cause a wave-clear bonus popup
to fire at an unexpected moment — the player might have been in the middle of
section 2 combat when a cross-section tally accidentally resolved. This is the
most likely cause of the reported "score added without killing enemies" bug.

---

## 7. File reference

| File | Role |
|------|------|
| `assault/scenes/systems/level_director/level_director.gd` | Sequences sections; calls `wave_manager.load_section()` |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Times spawns; emits `enemy_spawned`, `section_loaded` |
| `assault/scenes/systems/score_tracker/score_tracker.gd` | All scoring math; subscribes to `enemy_spawned`, `section_loaded`, `enemy_spawned_orphan` |
| `assault/scenes/enemies/base_enemy.gd` | Base class; sets `was_killed`, emits `died` |
| `assault/scenes/hazards/asteroid_base.gd` | Same pattern for asteroids |
| `assault/scenes/hazards/big_asteroid/big_asteroid.gd` | Spawns split shards, emits orphan signal deferred |
| `assault/scenes/enemies/enemy_path_mover.gd` | Drives enemy positions along paths; calls `queue_free()` on off-screen/duration exit |
| `assault/scenes/gui/score_popup_spawner.gd` | Listens to `EventBus.score_event`; spawns floating labels |
| `assault/scenes/gui/score_popup.gd` | One floating "+N" label; tweens and frees itself |
| `assault/scenes/gui/hud_score_widget.gd` | Score total + combo bar in HUD corner |
| `global/systems/event_bus.gd` | Autoload; carries `score_changed`, `combo_changed`, `score_event`, `enemy_spawned_orphan` |
