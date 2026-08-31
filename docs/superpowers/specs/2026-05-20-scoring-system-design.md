# Assault Mission Scoring System — Design

**Date:** 2026-05-20
**Status:** Approved by user, ready for implementation plan
**Scope:** Add score tracking, combo multipliers, wave clear bonuses, bonus targets, skill challenges, post-mission debrief, star ratings, and score-gated mission unlocks to assault missions.

---

## 1. Goals

- Reward skilled play with a visible, racking score during assault missions.
- Translate score into the existing 1–3★ mission rating already displayed in the mission select menu.
- Give scoring depth via combos, full-wave clears, optional bonus targets, and skill challenges — not just per-kill points.
- Allow high scores on completed missions to unlock additional content (e.g., the moon mission on Level 3).

## 2. Non-goals

- No leaderboards, no online sync.
- No replay/ghost system.
- No retroactive scoring for missions completed before this lands (existing saves get 1★ on completed missions).
- No mid-mission save/resume of score.

---

## 3. Architecture

A single `ScoreTracker` node lives in each assault level scene, sibling to `LevelDirector` and `WaveManager`. It is the only place scoring math happens. It reads from gameplay (enemies, waves, player damage) and broadcasts results via the existing `EventBus` autoload. UI components (HUD, debrief) subscribe to `EventBus` — they never touch `ScoreTracker` directly.

```
Level scene
├── LevelDirector
├── WaveManager  ─── enemy_spawned, wave_triggered ──┐
├── ScoreTracker  ◄──────────────────────────────────┤
│   ├── listens BaseEnemy.died, AsteroidBase.died    │
│   ├── listens EventBus.player_health_changed       │
│   ├── listens SkillChallenge.completed             │
│   └── emits via EventBus:                          │
│       ├── score_changed(total: int)                │
│       ├── combo_changed(multiplier: float,         │
│       │                 decay_remaining: float)    │
│       ├── score_event(position, points, reason)    │
│       └── wave_cleared(wave_index, bonus)          │
└── (existing nodes)

HUDScoreWidget ────── subscribes to EventBus
LevelDebriefScreen ── reads tracker.get_breakdown() at end
MissionState ──────── receives final score + derived stars
```

**Why a node, not an autoload:** scoring is per-mission and must die with the level scene to avoid leaking state between runs. UI components that need global access use `EventBus` (the established pattern).

---

## 4. Scoring math

### 4.1 Per-enemy base values

Stored as `score_value: int` on each enemy's `*Config.gd` resource (e.g., `FighterConfig.score_value`). Designer-tunable; no code change to retune.

| Target            | Base pts |
|-------------------|----------|
| Small asteroid    | 5        |
| Drone             | 10       |
| Big asteroid      | 15       |
| Fighter           | 25       |
| Ram ship          | 35       |
| Sniper            | 60       |
| Bomber            | 80       |
| Gunship           | 200      |
| Bonus drone       | 500      |

### 4.2 Combo multiplier

- Starts at **x1.0**, displayed to one decimal.
- Each kill: `combo += 0.1`, capped at **x8.0**.
- Each kill resets the decay timer to **4.0 s**.
- Idle 4 s with no kills → combo snaps to x1.0.
- Player takes damage → `combo *= 0.5`.
- Enemy escapes screen alive → `combo *= 0.75`.

**Each kill awards:** `floor(base_value * combo_multiplier)` to total score.

### 4.3 Wave-clear bonus

Separate award, on top of combo math (not multiplied by combo).

- Trigger: `expected_kills == actual_kills` for a wave AND no enemy from that wave escaped.
- Formula: `wave_clear_bonus = sum(base_values_in_wave) * (1 + 0.5 * enemies_in_wave)`
  - 3-enemy fighter wave: 75 × 2.5 = **187**
  - 5-enemy fighter wave: 125 × 3.5 = **437**

### 4.4 Passive survival tick

Every 15 s of damage-free play → **+50 pts**, no combo effect. Resets on damage.

### 4.5 Skill challenge bonus

Per `SkillChallengeResource`:
- Clean clear (no damage taken): designer-specified, default **500 pts**, also adds 0.3 to combo (equivalent to 3 kills).
- Partial (reached end but took damage): default **150 pts**, no combo effect.

### 4.6 Star thresholds (per mission)

Defined in `MissionConfigResource`:
- 1★ = mission complete (any score)
- 2★ = score ≥ `star_2_score`
- 3★ = score ≥ `star_3_score`

**Level 1 targets:** 2★ = 6,000, 3★ = 11,000 (calibrated against ~8k–14k clean run estimate).

---

## 5. Components

### 5.1 `ScoreTracker` (new, Node, in level scene)

Owns all scoring math.

**State:**
- `_total_score: int`
- `_combo: float = 1.0`
- `_combo_decay_remaining: float`
- `_survival_remaining: float = 15.0`
- `_wave_state: Dictionary[int, WaveTally]`
- `_breakdown: Dictionary` — categorized totals for debrief panel

**Inner class `WaveTally`:**
- `enemies: Array[Node]`
- `base_value_sum: int`
- `killed: int`
- `expected: int`
- `escaped: bool`
- `resolved: bool` — prevents double-paying or paying after escape

**Public API:**
- `start_tracking()` — called by LevelDirector at level start
- `stop_tracking()` — called at level complete; resolves any open waves as escaped
- `get_breakdown() -> Dictionary` — totals by category for debrief
- `get_total_score() -> int`

**Connects on `_ready()`:**
- `WaveManager.enemy_spawned` → `_on_enemy_spawned`
- `EventBus.player_health_changed` → `_on_player_health_changed`

### 5.2 `WaveManager` (modified)

Add one signal and one emit:

```gdscript
signal enemy_spawned(enemy: Node, wave_index: int)

# At end of _spawn_ship() after add_child:
enemy_spawned.emit(entity, _current_wave_index)
```

`_current_wave_index` is the index of the wave being processed in `_trigger_wave`.

### 5.3 `BaseEnemy` / `AsteroidBase` (modified)

Both already emit `died`. Add a `_was_killed: bool = false` flag set to `true` inside the `died.emit()` path. ScoreTracker reads this flag via `tree_exited` to distinguish kill from escape.

For consistency:
- `BaseEnemy` adds `var was_killed: bool = false`, sets it before `died.emit()`.
- `AsteroidBase` adds the same field.

### 5.4 `ScoreConfig` (new, Resource)

Optional centralized tuning resource (for future flexibility). For v1, combo settings are constants inside `ScoreTracker`. Enemy base values live on individual `*Config.gd` resources.

```gdscript
class_name ScoreConfig
extends Resource

@export var combo_step: float = 0.1
@export var combo_cap: float = 8.0
@export var combo_decay_seconds: float = 4.0
@export var damage_combo_multiplier: float = 0.5
@export var escape_combo_multiplier: float = 0.75
@export var survival_interval: float = 15.0
@export var survival_bonus: int = 50
@export var wave_clear_base_multiplier: float = 1.0
@export var wave_clear_per_enemy_bonus: float = 0.5
```

`ScoreTracker` exports a `ScoreConfig` reference with a default `.tres`.

### 5.5 Enemy config changes (modified)

Each existing config gets one new field:

```gdscript
# fighter_config.gd, drone_config.gd, sniper_config.gd,
# gunship_config.gd, bomber_config.gd, ram_config.gd,
# asteroid configs
@export var score_value: int = 0
```

Resource files (`.tres`) updated with the values from §4.1.

### 5.6 `BonusDrone` (new enemy)

`assault/scenes/enemies/bonus_drone/`
- 1 HP, no weapons, no contact damage.
- 50% larger sprite than drone, gold-tinted modulate.
- `bonus_drone_config.gd`: `score_value = 500`.
- Telegraph: 0.5s warning indicator (`!` icon) on screen edge before spawn.
- Spawned via `WaveBuilder.bonus_drone()` fluent method — designers place them inside existing waves.
- **Does not count toward wave_clear bonus** — ScoreTracker excludes bonus drones from `WaveTally` (checked by type or a `counts_toward_wave_clear: bool = true` flag on the config).

### 5.7 `SkillChallengeResource` (new)

```gdscript
class_name SkillChallengeResource
extends Resource

@export var trigger_time: float = 0.0
@export var challenge_name: String = "DANGER ZONE"
@export var duration: float = 4.0
@export var hazard_pattern: PackedScene  # spawns hazard nodes for the window
@export var clean_bonus: int = 500
@export var partial_bonus: int = 150
@export var clean_combo_bonus: float = 0.3
```

**Runtime:** `LevelSection.waves` already accepts heterogeneous resources. `WaveManager` detects `SkillChallengeResource` entries and spawns a `SkillChallengeRunner` node that:
1. Instantiates `hazard_pattern` for `duration` seconds.
2. Displays "DANGER ZONE" prompt with countdown via `EventBus.score_event`.
3. Tracks player damage during the window.
4. On end: emits `EventBus.skill_challenge_completed(clean: bool, bonus: int)` — ScoreTracker awards bonus.

**Two challenges in Level 1:**
1. **Asteroid corridor** — deep space section. Asteroid walls with sliding vertical gap. 4s duration.
2. **Bullet weave** — planet approach section. Sniper barrage with telegraphed safe gaps. 5s duration.

### 5.8 `HUDScoreWidget` (new HUD child)

Top-right of HUD. Two stacked elements:
- **Score**: large label, tweens upward smoothly on score change (1.0s `Tween.tween_property` per event, queued).
- **Combo**: `xN.N` label + horizontal decay bar (full = 4s remaining, empty = combo about to reset). Hidden when combo == 1.0.

Subscribes to `EventBus.score_changed`, `EventBus.combo_changed`.

### 5.9 `ScorePopup` (new transient label)

Small `Label` spawned at kill position via `EventBus.score_event`. Shows `+25 x3.0` for 1.0s, floats upward 30px, fades to 0. Pool of ~10 reusable instances.

### 5.10 `LevelDebriefScreen` (new scene)

`assault/scenes/gui/level_debrief.tscn`

Shown after the existing level dialog finishes, before `LevelExitCutscene`.

Layout:
- Title: "MISSION COMPLETE"
- Animated score counter (0 → final over 2.0s with ticking SFX)
- Breakdown panel (appears after counter finishes):
  - "Kill points: 1,650"
  - "Wave bonuses: 800"
  - "Skill bonuses: 500"
  - "Survival: 100"
  - "Bonus targets: 1,500"
- Three star slots fade-pop in left-to-right (gold ★ earned, dim ☆ not)
- "Continue" prompt → existing scene change

### 5.11 `MissionState` (modified, autoload)

Additive — no breaking changes. New methods:

```gdscript
func record_score(mission_number: int, score: int) -> void:
    var entry: Dictionary = _data.get(mission_number, {})
    entry["high_score"] = maxi(entry.get("high_score", 0), score)
    _data[mission_number] = entry
    _save()

func get_high_score(mission_number: int) -> int:
    return _data.get(mission_number, {}).get("high_score", 0)
```

`_save()` / `_load()` extended to persist `high_score` under each mission section in the existing `ConfigFile`.

### 5.12 `MissionConfigResource` (modified)

Two new fields for star thresholds, two for the composed score-based lock:

```gdscript
## Score required to earn 2 stars on this mission.
@export var star_2_score: int = 0
## Score required to earn 3 stars on this mission.
@export var star_3_score: int = 0

## If non-zero, additionally requires [required_score] high score
## on mission [required_score_mission] to unlock.
## Composes with required_mission via AND — both conditions must pass.
@export var required_score_mission: int = 0
@export var required_score: int = 0

func stars_for_score(score: int) -> int:
    if star_3_score > 0 and score >= star_3_score: return 3
    if star_2_score > 0 and score >= star_2_score: return 2
    return 1
```

### 5.13 `MissionSelectMenu._is_locked` (modified)

Composed check — both gates must pass:

```gdscript
func _is_locked(m: MissionConfigResource) -> bool:
    if m.required_mission != 0 \
            and not MissionState.is_complete(m.required_mission):
        return true
    if m.required_score_mission != 0 \
            and MissionState.get_high_score(m.required_score_mission) < m.required_score:
        return true
    return false
```

Locked description string becomes adaptive: shows whichever lock condition is failing.

### 5.14 `EventBus` (modified)

Four new signals:

```gdscript
signal score_changed(total: int)
signal combo_changed(multiplier: float, decay_remaining: float)
signal score_event(world_position: Vector2, points: int, reason: String)
signal skill_challenge_completed(clean: bool, bonus: int)
```

---

## 6. Data flow

### 6.1 Kill

```
Bullet damages Enemy → Enemy.health.amount_changed → 0
  → BaseEnemy: was_killed = true; died.emit(); queue_free
    → ScoreTracker._on_enemy_died(wave_index, enemy):
        # IMPORTANT: capture position BEFORE enemy is freed (next frame).
        var kill_pos: Vector2 = enemy.global_position
        tally.killed += 1
        points = floor(score_value * combo)
        _total_score += points
        combo = min(combo + 0.1, 8.0)
        combo_decay_remaining = 4.0
        EventBus.score_changed.emit(_total_score)
        EventBus.combo_changed.emit(combo, combo_decay_remaining)
        EventBus.score_event.emit(kill_pos, points, "kill")
        if tally.killed == tally.expected and not tally.escaped:
            bonus = tally.base_value_sum * (1.0 + 0.5 * tally.expected)
            _total_score += int(bonus)
            EventBus.score_event.emit(kill_pos, int(bonus), "wave_clear")
            tally.resolved = true
```

### 6.2 Escape

```
Enemy crosses off-screen boundary → EnemyPathMover frees it
  → BaseEnemy.tree_exited (was_killed == false)
    → ScoreTracker._on_enemy_freed(wave_index, enemy):
        tally.escaped = true
        combo *= 0.75
        EventBus.combo_changed.emit(combo, combo_decay_remaining)
        if not tally.resolved: tally.resolved = true  # no bonus possible
```

### 6.3 Player damage

```
Player takes hit → EventBus.player_health_changed(current, max)
  → ScoreTracker._on_player_health_changed:
      if current < _last_known_health:
          combo *= 0.5
          _survival_remaining = 15.0
          EventBus.combo_changed.emit(combo, combo_decay_remaining)
      _last_known_health = current
```

### 6.4 Frame update

```
ScoreTracker._process(delta):
    combo_decay_remaining -= delta
    if combo_decay_remaining <= 0 and combo > 1.0:
        combo = 1.0
        EventBus.combo_changed.emit(combo, 0.0)
    _survival_remaining -= delta
    if _survival_remaining <= 0:
        _total_score += 50
        _survival_remaining = 15.0
        EventBus.score_changed.emit(_total_score)
        EventBus.score_event.emit(player.global_position, 50, "survival")
```

### 6.5 Mission complete

```
LevelDirector.level_complete
  → Level1Director._on_level_complete:
      score_tracker.stop_tracking()
      DialogPlayer.play(debrief_dialog)
      await DialogPlayer.dialog_finished
      debrief = LevelDebriefScreen.show(score_tracker.get_breakdown())
      await debrief.dismissed
      final_score = score_tracker.get_total_score()
      stars = mission_config.stars_for_score(final_score)
      MissionState.record_score(1, final_score)
      MissionState.complete(1, stars)
      # existing scene change
```

---

## 7. Edge cases

- **Player dies mid-level** → mission failed; no `record_score`, no `complete` call. Score discarded.
- **Section ends with enemies still alive** → ScoreTracker resolves all unresolved waves as `escaped=true`. No combo penalty for already-resolved waves.
- **Combo persists across sections** within a single mission run — rewards continuous play.
- **Two enemies die same frame** → both contribute to combo growth, but each uses the combo value at the moment its death is processed (deterministic by signal connection order).
- **Bonus drone counted in wave_clear** → NO. ScoreTracker excludes bonus drones via `counts_toward_wave_clear: bool = false` on `BonusDroneConfig`.
- **Existing saves** → `get_high_score()` returns 0 for missions completed before this lands. Star count stays at whatever `complete()` already recorded (typically 1).
- **Resetting save** → existing `user://mission_state.cfg` deletion clears everything including high scores. No migration needed.

---

## 8. Level 1 configuration

`mission_01_config.tres`:
- `star_2_score = 6000`
- `star_3_score = 11000`
- (existing fields unchanged)

`mission_03_config.tres` (moon, currently locked):
- `required_mission = 1` (existing)
- `required_score_mission = 1`
- `required_score = 11000` (= Level 1's 3★ threshold)

**Bonus drone placements in Level 1:**
- Deep space section (s1): 1 bonus drone at t=15s
- Asteroid belt (s_ast): no bonus drone (already chaotic)
- Planet approach (s2): 2 bonus drones at t=40s, t=90s
- Cloud descent (s3): 1 bonus drone at t=25s

**Skill challenges in Level 1:**
- Deep space at t=10s: asteroid corridor, 4s, clean=500/partial=150
- Planet approach at t=70s: bullet weave, 5s, clean=700/partial=200

---

## 9. Testing approach

Manual playtest scenarios:
1. **Clean run** — kill every enemy, no damage taken, all challenges clean → should hit 11k+.
2. **Sloppy run** — let half escape, take damage often → should land 3k–5k.
3. **Combo decay** — kill one enemy, wait 5s; verify combo resets to x1.
4. **Damage penalty** — at x5 combo, take damage → verify drops to x2.5.
5. **Escape penalty** — at x5 combo, let one escape → verify drops to x3.75.
6. **Wave clear bonus** — kill all 5 in a wave → verify popup + score jump.
7. **Wave clear denied** — let one escape, kill the rest → verify NO bonus.
8. **Level 3 unlock** — beat Level 1 with <11k → moon locked. Replay for 11k+ → moon unlocked.
9. **Existing-save compatibility** — load a save that completed Level 1 before this lands → still shows 1★, moon still locked (high_score=0).

Unit tests deferred — Godot's testing story is weak; manual coverage is fine for this iteration.

---

## 10. Out of scope (deferred)

- Difficulty scaling of score values.
- Score multipliers from selected ship loadout (e.g., "hard mode = 1.5x score").
- Combo "max chain" displayed mid-run.
- Persistent total career score across all missions.
- Score share / screenshot.
- Achievement system tied to specific score milestones.
