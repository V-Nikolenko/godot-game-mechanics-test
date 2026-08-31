# Assault Race Mode — Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `assault` race mode on an **absolute track-space** model with **bespoke
per-racer FSMs**, deleting the buggy relative-progress projection and the shared data-driven AI,
and de-duplicating shared components (one `Shield`, one damage reaction) — producing a playable
straight-line dead-race with a real top-speed economy, dash panels, obstacles, and rivals that
each move and think differently.

**Architecture:** One longitudinal coordinate `track_y` per ship + one global `scroll_offset`
owned by `RaceWorld` (`screen_y = base − (track_y − scroll_offset)`); the pinned `ArenaCamera`
and parallax `Level1Background` are untouched. Mechanics (participant/sensors/weapon/mover/
shield/health/damage-reaction) are shared composition components; each racer is its own scene +
its own `RacerStateMachine` of bespoke `State`s. The player flies a normal shmup ship; the world
scrolls at the player's current top speed; the player's screen-Y trims their `track_y`.

**Tech Stack:** Godot 4.6, GDScript (full static typing), `CharacterBody2D`/`Area2D`/`Node`,
the existing `global/statemachine/State`, `BulletPool`, `Shield`, `Health`, `HurtBox`/`HitBox`,
`ThrusterEffect`, `Level1Background`, `WaveManager`/`WaveBuilder`.

**Reference docs (read before starting):**
[deep research](../research/2026-06-01-race-mode-deep-research.md) ·
[architecture](../research/2026-06-01-race-mode-architecture.md) ·
[bespoke AI](../research/2026-06-01-race-ai-bespoke-racers.md).

---

## ⚠️ Post-execution corrections (applied 2026-06-01, verified by headless run)

Two parse bugs in the code blocks below were found and fixed when the level was first compiled
in Godot 4.6.2 headless. If you re-generate code from this plan, apply these:
1. **`sensors.gd` `_all_participants()`** must be typed `-> Array[RaceParticipant]` (and
   `var out: Array[RaceParticipant] = []`). Returning an untyped `Array` makes `var gap :=
   p.track_y - ...` fail with "Cannot infer the type" (Variant element).
2. **`bg_dash_state.gd`** the variable `ready` collides with `Node`'s built-in `ready` signal —
   rename it to **`dash_ready`** (declaration + both assignments) and update the reader in
   `bg_reclaim_state.gd` to `get_state(&"BgDash").get("dash_ready")`.

After these fixes, `race_level_1.tscn` runs headless for 200 physics frames with zero script
errors. (Two unrelated pre-existing project messages remain: a missing `debug_draw_3d`
GDExtension binary and a stale UID in `player/weapons/modes/sniper_shot.tres`.)

## Conventions for this plan

- **No automated tests.** The repo has no test framework (only `godot-git-plugin`). Each task
  ends with a **Verify in Godot** step: open the noted scene, press **F6** (Run Current Scene),
  and confirm the described behavior. Watch the **Output** and **Debugger** panels for errors.
- **No commit steps.** The user handles all git commits (project rule). Do not run `git commit`.
- **Static typing everywhere**; `class_name` on every script referenced elsewhere.
- **Reuse, don't duplicate.** Shared mechanics live in `global/components/` or
  `assault/scenes/race/core/`. Per-racer code lives only under `assault/scenes/race/racers/<name>/`.
- **Skills:** invoke the noted `godot-prompter:*` skill(s) at the start of each task.

## Locked design decisions (resolved from the research's open questions)

1. **World model = absolute track-space (Approach B).** Pinned camera + parallax background
   unchanged.
2. **Player control model (locked):** the player keeps free shmup movement in X **and** Y for
   dodging (Y clamped to a band around `base_screen_y`). The world scrolls at the player's
   current **top speed** (the main forward lever). The player's screen-Y sets a small
   `track_y` **trim**: flying high noses slightly ahead, dropping low to dodge costs a little
   ground. There is **no manual throttle** — speed is governed by the top-speed economy.
3. **Top-speed economy (locked defaults; all `@export`, retune in-engine):**
   `base_top_speed = 220`, `max_top_speed = 600`, `panel_gain = 70`, `decay_per_sec = 22`,
   `loss_per_hit = 90`, `grace_after_panel = 1.5 s`, `panel_lunge = 650`,
   `track_length = 18000` (≈ 60–80 s).
4. **Track authoring = a visible `Track` scene** of objects placed at real `track_y` + lanes,
   with `WaveManager` retained for timed dynamic spawns.
5. **Rebuild (not refactor-in-place):** delete the old `race/` scripts (their `class_name`s
   collide with the new ones) and build the new structure. Salvage concepts, not files.
6. **First-slice roster, then full roster:** prove the pattern with **Fang**, add a **Pacer**
   rabbit, then **Bogomol** (mines), **Booster Gold** (dash-ram), **Isac** (gatling),
   **Reacher** (sniper).

## Collision layers (existing project conventions — reused)

player body 4 · player_hurtbox 128 · enemy_hitbox 256 · enemy_hurtbox 512 · bullets 64 ·
rockets 32 · asteroid-contact 1024 · pickup/panel 8. Racer `HurtBox`: layer **512**,
mask `64 | 1024 = 1088` (player bullets + asteroid). The laser hazard's `896` mask already kills
layer-512 hurtboxes. Racer contact `HitBox`: layer **256** (for rams against the player's
hurtbox 128). Dash panels / mines: layer **8** so racer forward-sensors can see them.

## Groups

`player` (existing) · `racers` · `race_director` · `race_world` · `dash_panels` · `mines` ·
`background` (existing) · `asteroids` (existing).

## Final file map

```
global/components/shield_component.gd         (MODIFY — configurable charge source)
global/components/damage_reaction.gd          (CREATE — shared destructible reaction)

assault/scenes/race/core/race_world.gd        (CREATE — scroll_offset + projection)
assault/scenes/race/core/race_participant.gd  (CREATE — track_y + top-speed economy)
assault/scenes/race/core/race_director.gd     (CREATE — standings + finish/fail)
assault/scenes/race/core/sensors.gd           (CREATE — perception kit)
assault/scenes/race/core/racer_weapon.gd      (CREATE — firing wrapper)
assault/scenes/race/core/lateral_mover.gd     (CREATE — smoothed X glide + avoidance)
assault/scenes/race/core/racer_state_machine.gd (CREATE — manual-tick, name-based FSM)
assault/scenes/race/core/race_ship.gd         (CREATE — shared chassis)

assault/scenes/race/track/track_object.gd     (CREATE — track_y-anchored base)
assault/scenes/race/track/dash_panel.gd       (CREATE)
assault/scenes/race/track/dash_panel.tscn     (CREATE)
assault/scenes/race/track/mine.gd / .tscn      (CREATE)
assault/scenes/race/track/finish_line.gd / .tscn (CREATE)

assault/scenes/race/player_race_controller.gd (CREATE)
assault/scenes/race/ui/race_hud.gd / .tscn     (CREATE)

assault/scenes/race/racers/pacer/        (CREATE — pacer.tscn + states/)
assault/scenes/race/racers/fang/         (CREATE — fang.tscn + states/)
assault/scenes/race/racers/bogomol/      (CREATE)
assault/scenes/race/racers/booster_gold/ (CREATE)
assault/scenes/race/racers/isac/         (CREATE)
assault/scenes/race/racers/reacher/      (CREATE)

assault/scenes/levels/race/race_level_1.tscn        (REPLACE)
assault/scenes/levels/race/race_level_config.gd     (CREATE)

DELETE (old implementation — see Task 1):
  assault/scenes/race/{racer_base,racer_shield,racer_steering,race_participant,
	race_director,track_object,dash_panel,player_throttle_adapter,boost_bar}.gd (+ .tscn/.uid)
  assault/scenes/race/behaviors/*  · assault/scenes/race/ai/*
  assault/scenes/race/racers/*.tscn (old) · assault/scenes/race/race_hud.{gd,tscn}
  assault/scenes/levels/race/race_level_1_config.gd · old race_level_1.tscn
```

---

# PHASE 0 — De-duplicate shared components

*No race logic yet. These changes must leave the existing player and enemies working.*

## Task 1: Remove the old race implementation

**Files:**
- Delete: every file listed in the "DELETE" block of the file map above.

- [ ] **Step 1: Delete the old race scripts, scenes, and `.uid` files**

Remove the entire old race implementation so its `class_name`s (`RaceParticipant`,
`RaceDirector`, `DashPanel`, `TrackObject`, `RacerBase`, `RacerShield`, …) don't collide with
the new ones. Delete, for each, the `.gd`, any `.tscn`, and any `.gd.uid`:

```
assault/scenes/race/racer_base.gd  racer_base.tscn
assault/scenes/race/racer_shield.gd
assault/scenes/race/racer_steering.gd
assault/scenes/race/race_participant.gd
assault/scenes/race/race_director.gd
assault/scenes/race/track_object.gd
assault/scenes/race/dash_panel.gd  dash_panel.tscn
assault/scenes/race/player_throttle_adapter.gd
assault/scenes/race/boost_bar.gd
assault/scenes/race/race_hud.gd  race_hud.tscn
assault/scenes/race/behaviors/        (whole folder)
assault/scenes/race/ai/               (whole folder)
assault/scenes/race/racers/*.tscn     (old racer scenes)
assault/scenes/levels/race/race_level_1_config.gd
assault/scenes/levels/race/race_level_1.tscn
```

Keep all art under `assault/assets/sprites/racers/` and `boost_panel*` — those are reused.

- [ ] **Step 2: Verify the project still opens**

Open the project in Godot. Expected: it loads with **no parse errors** about the deleted race
classes (nothing outside `race/` referenced them). The non-race levels (e.g. `level_1.tscn`) run
normally. If Godot reports a missing-UID warning for the deleted `race_level_1.tscn`, ignore it —
we author a new one in Task 14.

---

## Task 2: Make `Shield` charge-source configurable (deletes the `racer_shield` need)

**Files:**
- Modify: `global/components/shield_component.gd`

- [ ] **Step 1: Add the configurable exports and split the regen-timer setup**

In `global/components/shield_component.gd`, replace the top exports + `_ready()` with a version
that can either bind to `ShipProgressionState` (player) **or** use a fixed export count (racers):

```gdscript
@export var max_temporary: int = 5            ## hard cap on temp stack

## When true (player), initial permanent charges come from ShipProgressionState and track it.
## When false (racers / generic ships), use `permanent_charges` below — no autoload dependency.
@export var bind_progression: bool = false
## Initial & max permanent charges when bind_progression == false.
@export_range(0, 10) var permanent_charges: int = 1

const REGEN_INTERVAL_SEC: float = 5.0
```

Then replace `_ready()`:

```gdscript
func _ready() -> void:
	if bind_progression:
		permanent_max = ShipProgressionState.permanent_shield_count
		ShipProgressionState.permanent_shield_count_changed.connect(_on_progression_changed)
	else:
		permanent_max = permanent_charges
	permanent_active = permanent_max
	_setup_regen_timer()
	_emit_snapshot()

func _setup_regen_timer() -> void:
	_regen_timer = Timer.new()
	_regen_timer.one_shot = true
	_regen_timer.wait_time = REGEN_INTERVAL_SEC
	_regen_timer.timeout.connect(_on_regen_tick)
	add_child(_regen_timer)
```

- [ ] **Step 2: Stop the per-snapshot console spam**

In `_emit_snapshot()`, delete the `print("[Shield] %s" % str(snap))` line (a racer field would
spam it every shield event). Leave the rest of the method unchanged.

- [ ] **Step 3: Set the player's shield to bind progression**

Open the player scene (`assault/scenes/player/player_fighter.tscn`), select the `Shield`
component node, and in the Inspector tick **`bind_progression = true`**. (Racer scenes built
later leave it false and set `permanent_charges`.)

- [ ] **Step 4: Verify the player still shields**

Run `assault/scenes/levels/edelia/1/level_1.tscn` (F6). Expected: the player's bubble shield
appears and absorbs hits exactly as before; **no `[Shield]` spam** in Output; no errors.

---

## Task 3: Extract the shared `DamageReaction` component

**Files:**
- Create: `global/components/damage_reaction.gd`

- [ ] **Step 1: Write the component**

A single, sprite-agnostic "destructible ship reacts to a hit" component (modulate-tween flash —
no required `HitFlashAnimationPlayer`). Racers compose this instead of re-implementing
`BaseEnemy`.

```gdscript
## DamageReaction — uniform "ship takes a hit" handling, composed onto any destructible ship.
## Wire it with setup(); it listens to a HurtBox and routes damage through an optional Shield
## to Health, flashes a sprite, runs an optional pre-damage hook, and explodes on death.
class_name DamageReaction
extends Node

signal died

@export var flash_color: Color = Color(1.0, 0.4, 0.4, 1.0)
@export var flash_time: float = 0.18
## Optional extra reaction on every hit (e.g. top-speed loss). Set by the host.
var on_hit: Callable = Callable()

var _health: Health = null
var _shield: Shield = null
var _sprite: CanvasItem = null
var _explosion: ExplosionEffect = null
var _flash_tween: Tween = null

func setup(health: Health, shield: Shield, hurt_box: HurtBox, sprite: CanvasItem) -> void:
	_health = health
	_shield = shield
	_sprite = sprite
	_explosion = ExplosionEffect.new()
	add_child(_explosion)
	if hurt_box and not hurt_box.received_damage.is_connected(_on_received_damage):
		hurt_box.received_damage.connect(_on_received_damage)
	if _health and not _health.amount_changed.is_connected(_on_health_changed):
		_health.amount_changed.connect(_on_health_changed)

func _on_received_damage(damage: int) -> void:
	if on_hit.is_valid():
		on_hit.call(damage)
	_flash()
	if _shield and _shield.consume_one():
		return
	if _health:
		_health.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current <= 0:
		died.emit()
		if _explosion:
			_explosion.explode()
		get_parent().queue_free()

func _flash() -> void:
	if _sprite == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_sprite.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, flash_time)
```

- [ ] **Step 2: Verify it compiles**

In Godot, confirm `damage_reaction.gd` shows **no parse errors** in the Script editor. (It is
exercised for real in Task 9 when the first racer uses it.)

---

# PHASE 1 — Track-space core

## Task 4: `RaceParticipant` (track_y + top-speed economy)

**Files:**
- Create: `assault/scenes/race/core/race_participant.gd`

- [ ] **Step 1: Write the participant**

```gdscript
## RaceParticipant — on EVERY race ship (player + AI). Owns the ship's position along the track
## (track_y) and the TOP-SPEED ECONOMY (panels raise it; damage/idleness bleed it off). AI ships
## self-advance track_y from current_speed; the player's track_y is set externally by the
## PlayerRaceController (its screen-Y trims it). Registers with the RaceDirector on ready.
class_name RaceParticipant
extends Node

signal finished_race(participant: RaceParticipant)
signal top_speed_changed(value: float, maximum: float)
signal panel_boosted

@export var is_player: bool = false

@export_group("Top-speed economy")
@export var base_top_speed: float = 220.0   ## floor; decay never drops below this
@export var max_top_speed: float = 600.0    ## hard cap
@export var panel_gain: float = 70.0        ## top speed added per dash panel
@export var decay_per_sec: float = 22.0     ## bled off when not recently boosted
@export var loss_per_hit: float = 90.0      ## top speed lost on taking a hit
@export var grace_after_panel: float = 1.5  ## seconds of no-decay right after a panel
@export var panel_lunge: float = 650.0      ## instant forward leap on a panel (track_y units)

## AI ease-off: brains scale forward speed in [0..1] (1 = floor it). Player ignores this.
var cruise_factor: float = 1.0

var track_y: float = 0.0
var top_speed: float = 0.0
var current_speed: float = 0.0
var finished: bool = false

var _director: RaceDirector = null
var _grace: float = 0.0
var _lunge_remaining: float = 0.0

func _ready() -> void:
	top_speed = base_top_speed
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	if _director:
		_director.register(self)
	else:
		push_warning("[RaceParticipant] No RaceDirector in group 'race_director'.")
	top_speed_changed.emit(top_speed, max_top_speed)

## The owning ship node (RaceShip for AI; the player ship for the player).
func ship() -> Node2D:
	return get_parent() as Node2D

func global_x() -> float:
	var s := ship()
	return s.global_position.x if s else 0.0

func set_cruise_factor(f: float) -> void:
	cruise_factor = clampf(f, 0.0, 1.0)

## Crossing a dash panel: raise top speed, grant the no-decay grace, lunge forward, flag visuals.
func cross_panel() -> void:
	top_speed = minf(max_top_speed, top_speed + panel_gain)
	_grace = grace_after_panel
	_lunge_remaining += panel_lunge
	top_speed_changed.emit(top_speed, max_top_speed)
	panel_boosted.emit()

## Taking a hit costs top speed (in addition to HP/shield handled by DamageReaction).
func lose_top_speed_on_hit() -> void:
	top_speed = maxf(base_top_speed, top_speed - loss_per_hit)
	top_speed_changed.emit(top_speed, max_top_speed)

func top_speed_fraction() -> float:
	return inverse_lerp(base_top_speed, max_top_speed, top_speed)

func _physics_process(delta: float) -> void:
	if finished or _director == null:
		return
	# Economy: decay toward base once the post-panel grace expires.
	if _grace > 0.0:
		_grace -= delta
	else:
		var decayed := maxf(base_top_speed, top_speed - decay_per_sec * delta)
		if decayed != top_speed:
			top_speed = decayed
			top_speed_changed.emit(top_speed, max_top_speed)

	current_speed = top_speed * (cruise_factor if not is_player else 1.0)

	# AI self-advances along the track. The player's track_y is set by PlayerRaceController.
	if not is_player:
		track_y += current_speed * delta
		if _lunge_remaining > 0.0:
			var step := minf(_lunge_remaining, 2600.0 * delta)
			track_y += step
			_lunge_remaining -= step
		if track_y >= _director.track_length:
			track_y = _director.track_length
			finished = true
			_director.notify_finished(self)
			finished_race.emit(self)

func _exit_tree() -> void:
	if _director:
		_director.unregister(self)
```

- [ ] **Step 2: Verify it compiles**

Confirm no parse errors. (`RaceDirector` is referenced but created in Task 6 — author Task 6
before running anything that instantiates a participant; the class reference resolves once both
exist.)

---

## Task 5: `RaceWorld` (scroll offset + the one projection)

**Files:**
- Create: `assault/scenes/race/core/race_world.gd`

- [ ] **Step 1: Write the world**

```gdscript
## RaceWorld — the single projection seam. Owns scroll_offset (the virtual camera's track
## position), which advances at the PLAYER's current top speed. Every track-space object renders
## at screen_y = base_screen_y - (track_y - scroll_offset). Also drives the parallax background
## scroll from the player's top-speed fraction. Add to group "race_world".
class_name RaceWorld
extends Node

## Screen-Y the player rests around (lower third of an 720-tall play area works well).
@export var base_screen_y: float = 520.0
## Background scroll multiplier at min/max top speed (drives the existing set_throttle_scroll).
@export var bg_scroll_min: float = 3.0
@export var bg_scroll_max: float = 11.0

var scroll_offset: float = 0.0

var _director: RaceDirector = null
var _background: BackgroundController = null

func _ready() -> void:
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	_background = get_tree().get_first_node_in_group("background") as BackgroundController

## Track-space → screen Y. Used by every RaceShip and TrackObject every frame.
func screen_y_for(track_y: float) -> float:
	return base_screen_y - (track_y - scroll_offset)

## Screen Y → track-space. Used by PlayerRaceController to derive the player's track_y.
func track_y_for_screen_y(screen_y: float) -> float:
	return scroll_offset + (base_screen_y - screen_y)

func _physics_process(delta: float) -> void:
	var player := _director.get_player() if _director else null
	if player == null:
		return
	# The world scrolls forward at the player's current top speed (the main forward lever).
	scroll_offset += player.current_speed * delta
	if _background:
		var mult := lerpf(bg_scroll_min, bg_scroll_max, player.top_speed_fraction())
		_background.set_throttle_scroll(mult)
```

- [ ] **Step 2: Verify it compiles** — no parse errors.

---

## Task 6: `RaceDirector` (standings + finish/fail)

**Files:**
- Create: `assault/scenes/race/core/race_director.gd`

- [ ] **Step 1: Write the slim director**

```gdscript
## RaceDirector — one per race level. Owns the participant list, standings (sorted by track_y,
## cached once per frame), the finish line, and the fail-on-player-death signal. No projection
## (that's RaceWorld). Add to group "race_director" so participants self-register.
class_name RaceDirector
extends Node

signal standings_changed(order: Array)   ## Array[RaceParticipant], leader first
signal race_finished(results: Array)     ## Array[RaceParticipant], finish order
signal race_failed                       ## player destroyed

@export var track_length: float = 18000.0

var _participants: Array[RaceParticipant] = []
var _player: RaceParticipant = null
var _results: Array[RaceParticipant] = []
var _standings: Array[RaceParticipant] = []
var _race_over: bool = false

func register(p: RaceParticipant) -> void:
	if p not in _participants:
		_participants.append(p)
	if p.is_player:
		_player = p

func unregister(p: RaceParticipant) -> void:
	_participants.erase(p)
	_standings.erase(p)

func get_player() -> RaceParticipant:
	return _player

## Cached, leader-first. Recomputed once per frame in _physics_process.
func get_standings() -> Array[RaceParticipant]:
	return _standings

func place_of(p: RaceParticipant) -> int:
	var i := _standings.find(p)
	return i + 1 if i >= 0 else _participants.size()

func is_in_front(p: RaceParticipant) -> bool:
	return not _standings.is_empty() and _standings[0] == p

func leader() -> RaceParticipant:
	return _standings[0] if not _standings.is_empty() else null

func gap_to_leader(p: RaceParticipant) -> float:
	var l := leader()
	return (l.track_y - p.track_y) if l else 0.0

func get_ahead(p: RaceParticipant) -> RaceParticipant:
	var i := _standings.find(p)
	return _standings[i - 1] if i > 0 else null

func get_behind(p: RaceParticipant) -> RaceParticipant:
	var i := _standings.find(p)
	return _standings[i + 1] if i >= 0 and i < _standings.size() - 1 else null

## Connect the player's Health so death fails the race (called by RaceLevelConfig).
func bind_player_health(health: Health) -> void:
	if health and not health.amount_changed.is_connected(_on_player_health_changed):
		health.amount_changed.connect(_on_player_health_changed)

func notify_finished(p: RaceParticipant) -> void:
	if p not in _results:
		_results.append(p)
	if p == _player and not _race_over:
		_race_over = true
		race_finished.emit(_results.duplicate())

func _physics_process(_delta: float) -> void:
	if _race_over:
		return
	var sorted: Array[RaceParticipant] = []
	sorted.assign(_participants)
	sorted.sort_custom(func(a, b): return a.track_y > b.track_y)
	if sorted != _standings:
		_standings = sorted
		standings_changed.emit(_standings)
	# Player-finish: the player's track_y is set externally (PlayerRaceController), so unlike AI
	# it is not checked in RaceParticipant — the director detects the player crossing the line.
	if _player and not _player.finished and _player.track_y >= track_length:
		_player.finished = true
		notify_finished(_player)

func _on_player_health_changed(current: int) -> void:
	if current <= 0 and not _race_over:
		_race_over = true
		race_failed.emit()
```

- [ ] **Step 2: Verify it compiles** — no parse errors. `RaceParticipant`, `RaceWorld`, and
`RaceDirector` now all resolve each other's `class_name`s.

---

## Task 7: Player race integration (controller + a throwaway test level)

**Files:**
- Create: `assault/scenes/race/player_race_controller.gd`
- Create (temporary): `assault/scenes/levels/race/_race_sandbox.tscn`

- [ ] **Step 1: Write the player race controller**

```gdscript
## PlayerRaceController — attached to the shared player ship at race start. The player keeps its
## normal shmup movement; this node (a) clamps the player's screen-Y to a band around the world
## anchor, (b) derives the player's track_y from its screen-Y each frame (high = nose ahead),
## (c) routes dash-panel crossings and damage into the top-speed economy.
class_name PlayerRaceController
extends Node

## Vertical band (px) the player may roam above/below RaceWorld.base_screen_y.
@export var band_ahead: float = 280.0    ## how far ABOVE the anchor (smaller y) the player may fly
@export var band_behind: float = 160.0   ## how far BELOW the anchor the player may drop

var _ship: Node2D = null
var _participant: RaceParticipant = null
var _world: RaceWorld = null

func setup(ship: Node2D, participant: RaceParticipant, health: Health) -> void:
	_ship = ship
	_participant = participant
	_world = get_tree().get_first_node_in_group("race_world") as RaceWorld
	if health:
		health.amount_changed.connect(_on_health_changed)
	if _participant:
		_participant.panel_boosted.connect(_on_panel_boosted)

func _physics_process(_delta: float) -> void:
	if _ship == null or _participant == null or _world == null:
		return
	# Clamp the player's vertical roam to the band (its own input drives the actual move).
	var top := _world.base_screen_y - band_ahead
	var bottom := _world.base_screen_y + band_behind
	_ship.global_position.y = clampf(_ship.global_position.y, top, bottom)
	# Derive track_y from screen-Y: high on screen = a little further along the track.
	_participant.track_y = _world.track_y_for_screen_y(_ship.global_position.y)

func _on_panel_boosted() -> void:
	if _ship and _ship.has_method("set_thruster_state"):
		_ship.set_thruster_state(ThrusterEffect.State.BOOST_PANEL)
		await get_tree().create_timer(_participant.grace_after_panel).timeout
		if is_instance_valid(_ship) and _ship.has_method("clear_thruster_override"):
			_ship.clear_thruster_override()

var _last_health: int = -1
func _on_health_changed(current: int) -> void:
	if _last_health >= 0 and current < _last_health:
		_participant.lose_top_speed_on_hit()
	_last_health = current
```

- [ ] **Step 2: Author a throwaway sandbox scene to prove the core**

Create `assault/scenes/levels/race/_race_sandbox.tscn` (we delete it after Task 8). It needs the
background, the pinned camera, a `RaceDirector`, a `RaceWorld`, the player, and a tiny boot
script. Use this scene text:

```
[gd_scene load_steps=7 format=3]

[ext_resource type="PackedScene" path="res://assault/scenes/levels/edelia/1/level_1_background.tscn" id="1_bg"]
[ext_resource type="Script" path="res://assault/scenes/systems/arena_camera.gd" id="2_cam"]
[ext_resource type="Script" path="res://assault/scenes/race/core/race_director.gd" id="3_dir"]
[ext_resource type="Script" path="res://assault/scenes/race/core/race_world.gd" id="4_world"]
[ext_resource type="PackedScene" path="res://assault/scenes/player/player_fighter.tscn" id="5_player"]
[ext_resource type="Script" path="res://assault/scenes/race/core/race_participant.gd" id="6_part"]

[node name="RaceSandbox" type="Node2D"]

[node name="Level1Background" parent="." groups=["background"] instance=ExtResource("1_bg")]

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(640, 360)
script = ExtResource("2_cam")

[node name="RaceDirector" type="Node" parent="." groups=["race_director"]]
script = ExtResource("3_dir")

[node name="RaceWorld" type="Node" parent="." groups=["race_world"]]
script = ExtResource("4_world")

[node name="Boot" type="Node" parent="."]

[node name="PlayerFighter" parent="." groups=["player"] instance=ExtResource("5_player")]
position = Vector2(640, 520)
```

- [ ] **Step 3: Add a one-off boot script on the `Boot` node**

Select the `Boot` node, attach a new inline script, and paste:

```gdscript
extends Node
func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var participant := RaceParticipant.new()
	participant.name = "RaceParticipant"
	participant.is_player = true
	player.add_child(participant)
	var ctrl := PlayerRaceController.new()
	ctrl.name = "PlayerRaceController"
	player.add_child(ctrl)
	var health := player.get_node_or_null("HealthComponent") as Health
	ctrl.setup(player, participant, health)
```

> If the player's Health node is not named `HealthComponent`, open `player_fighter.tscn`, find
> the `Health` component's node name, and use it here and in Task 14.

- [ ] **Step 4: Verify the track-space core**

Run `_race_sandbox.tscn` (F6). Expected:
- The Level-1 background **scrolls upward continuously** (driven by `RaceWorld` → the player's
  base top speed). Flying the player **up** speeds the background slightly / **down** slows it
  (top-speed fraction unchanged yet, but the band clamp keeps the ship in range).
- The player ship is **clamped** to a vertical band (can't leave the lower-middle region).
- No errors in Output/Debugger. (Top-speed gain/decay is visible once panels exist — Task 8.)

---

# PHASE 2 — Track furniture

## Task 8: `TrackObject` base + `DashPanel` + `FinishLine`

**Files:**
- Create: `assault/scenes/race/track/track_object.gd`
- Create: `assault/scenes/race/track/dash_panel.gd` + `dash_panel.tscn`
- Create: `assault/scenes/race/track/finish_line.gd` + `finish_line.tscn`

- [ ] **Step 1: Write the track-object base**

```gdscript
## TrackObject — anything that lives at a fixed track_y (panels, mines, finish line). Each frame
## it projects its track_y to a screen-Y via RaceWorld and culls itself once it scrolls off the
## bottom. X is a real screen-X lane, authored per instance. Set `track_y` in the editor.
class_name TrackObject
extends Area2D

@export var track_y: float = 0.0
@export var cull_margin: float = 160.0

var _world: RaceWorld = null

func _ready() -> void:
	_world = get_tree().get_first_node_in_group("race_world") as RaceWorld
	_on_track_ready()

func _physics_process(delta: float) -> void:
	if _world == null:
		return
	global_position.y = _world.screen_y_for(track_y)
	if global_position.y > get_viewport_rect().size.y + cull_margin:
		_on_culled()
		queue_free()
		return
	_on_track_process(delta)

func _on_track_ready() -> void: pass
func _on_track_process(_delta: float) -> void: pass
func _on_culled() -> void: pass
```

- [ ] **Step 2: Write the dash panel**

Uses Area2D **overlap polling** (reliable for directly-positioned ships, unlike `body_entered`).

```gdscript
## DashPanel — a track-anchored speed pad. Any ship whose RaceParticipant overlaps it (polled)
## crosses it once per cooldown: top-speed gain + lunge (RaceParticipant.cross_panel). Reused by
## the player AND every racer. Bogomol later drops mines right after crossing.
class_name DashPanel
extends TrackObject

@export var trigger_half_w: float = 70.0
@export var trigger_half_h: float = 80.0
@export var disabled_duration: float = 1.0
@export var retrigger_cooldown: float = 1.2

var _cooldowns: Dictionary = {}   ## RaceParticipant -> seconds remaining
var _disabled: float = 0.0

@onready var _arrows: AnimatedSprite2D = $BoostPanelArrows

func _on_track_ready() -> void:
	add_to_group("dash_panels")
	collision_layer = 8     ## "pickup" bit so racer forward-sensors can see panels ahead
	collision_mask = 0
	monitoring = false
	if _arrows:
		_arrows.play(&"idle")

func _on_track_process(delta: float) -> void:
	for p in _cooldowns.keys():
		_cooldowns[p] -= delta
	for p in _cooldowns.keys().filter(func(k): return _cooldowns[k] <= 0.0):
		_cooldowns.erase(p)
	if _disabled > 0.0:
		_disabled -= delta
		if _disabled <= 0.0 and _arrows:
			_arrows.play(&"idle")
		return
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ship := n as Node2D
			if ship == null:
				continue
			var part := ship.get_node_or_null("RaceParticipant") as RaceParticipant
			if part == null or _cooldowns.has(part):
				continue
			if absf(ship.global_position.x - global_position.x) < trigger_half_w \
					and absf(ship.global_position.y - global_position.y) < trigger_half_h:
				_cooldowns[part] = retrigger_cooldown
				part.cross_panel()
				if _disabled <= 0.0:
					_disabled = disabled_duration
					if _arrows:
						_arrows.play(&"boost")
```

- [ ] **Step 3: Author `dash_panel.tscn`**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://assault/scenes/race/track/dash_panel.gd" id="1"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/racers/boost_panel.png" id="2"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/racers/boost_panel_arrows.png" id="3"]

[sub_resource type="RectangleShape2D" id="rect"]
size = Vector2(140, 90)

[node name="DashPanel" type="Area2D"]
script = ExtResource("1")

[node name="Pad" type="Sprite2D" parent="."]
texture = ExtResource("2")

[node name="BoostPanelArrows" type="AnimatedSprite2D" parent="."]
texture = ExtResource("3")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("rect")
```

> The `BoostPanelArrows` node uses `play(&"idle"/&"boost")`. If you don't have a `SpriteFrames`
> with those animations yet, either build one from `boost_panel_arrows.png` or temporarily
> change `_arrows.play(...)` calls to no-ops. The panel **logic** does not depend on the art.

- [ ] **Step 4: Write the finish line**

```gdscript
## FinishLine — a track-anchored band at track_y = director.track_length. Purely visual here;
## the actual finish is detected by RaceParticipant crossing track_length. It just shows where.
class_name FinishLine
extends TrackObject

func _on_track_ready() -> void:
	var dir := get_tree().get_first_node_in_group("race_director") as RaceDirector
	if dir:
		track_y = dir.track_length
```

Author `finish_line.tscn` as an `Area2D` (script `finish_line.gd`) with a wide `ColorRect`/
`Sprite2D` band and a `CollisionShape2D` (unused for logic, fine to omit).

- [ ] **Step 5: Drop panels into the sandbox and verify the economy**

Open `_race_sandbox.tscn`, add three `dash_panel.tscn` instances as children, set their
`track_y` to `1500`, `3200`, `5200` and their `position.x` to `420`, `900`, `640`. Run (F6).
Expected:
- Panels **scroll down** from the top at the world speed and **cull** at the bottom.
- Flying the player through a panel: a **boost flare**, and the background **noticeably speeds
  up** (top speed rose). Avoiding panels for a few seconds: the background **eases back down**
  (decay toward base). This proves the top-speed economy end-to-end.

- [ ] **Step 6: Delete the sandbox**

Delete `_race_sandbox.tscn` and the inline `Boot` script — the real level (Task 14) replaces it.

---

# PHASE 3 — Shared racer kit + first bespoke racer (Fang)

## Task 9: The shared racer mechanics (sensors, weapon, mover, FSM, chassis)

**Files:**
- Create: `assault/scenes/race/core/sensors.gd`
- Create: `assault/scenes/race/core/racer_weapon.gd`
- Create: `assault/scenes/race/core/lateral_mover.gd`
- Create: `assault/scenes/race/core/racer_state_machine.gd`
- Create: `assault/scenes/race/core/race_ship.gd`

- [ ] **Step 1: Write `Sensors` (perception; no decisions)**

```gdscript
## Sensors — stateless perception for a racer brain. Reads the RaceDirector standings and small
## group scans. No strategy lives here; brains call these and decide. Attach as a child of the
## RaceShip; it self-resolves its host on setup().
class_name Sensors
extends Node

## Player bullets only by default, so a racer never dodges its OWN just-fired bullet (layer 256).
## Set to 64 | 256 ONLY if you also tag bullets with a shooter and filter self in incoming_threat().
@export var bullet_mask: int = 64
@export var threat_radius: float = 95.0

var _host: RaceShip = null
var _part: RaceParticipant = null
var _director: RaceDirector = null
var _threat_area: Area2D = null

func setup(host: RaceShip) -> void:
	_host = host
	_part = host.participant
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	_threat_area = Area2D.new()
	_threat_area.collision_layer = 0
	_threat_area.collision_mask = bullet_mask
	_threat_area.monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = threat_radius
	shape.shape = circle
	_threat_area.add_child(shape)
	host.add_child(_threat_area)

func _pos() -> Vector2:
	return _host.global_position

## Nearest participant ahead of me on the track, within max_gap track_y and lane_tol px in X.
func ship_ahead(max_gap: float, lane_tol: float) -> RaceParticipant:
	return _nearest_ship(true, max_gap, lane_tol)

func ship_behind(max_gap: float, lane_tol: float) -> RaceParticipant:
	return _nearest_ship(false, max_gap, lane_tol)

func _nearest_ship(ahead: bool, max_gap: float, lane_tol: float) -> RaceParticipant:
	var best: RaceParticipant = null
	var best_gap := max_gap
	for p in _all_participants():
		if p == _part:
			continue
		var gap := p.track_y - _part.track_y     ## >0 = ahead
		if (ahead and gap <= 0.0) or (not ahead and gap >= 0.0):
			continue
		var ag := absf(gap)
		if ag > max_gap or absf(p.global_x() - _pos().x) > lane_tol:
			continue
		if ag < best_gap:
			best_gap = ag
			best = p
	return best

func _all_participants() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("racers"):
		var s := n as RaceShip
		if s and is_instance_valid(s):
			out.append(s.participant)
	if _director and _director.get_player():
		out.append(_director.get_player())
	return out

## Nearest dash panel ahead on screen (smaller y), within max_gap px of vertical reach.
func nearest_panel_ahead(max_gap: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_gap
	for n in get_tree().get_nodes_in_group("dash_panels"):
		var p := n as Node2D
		if p == null:
			continue
		var dy := _pos().y - p.global_position.y   ## >0 = ahead (above me)
		if dy < -80.0 or dy > max_gap:
			continue
		var d := absf(p.global_position.x - _pos().x) + maxf(0.0, dy)
		if d < best_d:
			best_d = d
			best = p
	return best

## True while a bullet/laser is inside the threat circle.
func incoming_threat() -> Node2D:
	if _threat_area == null:
		return null
	var areas := _threat_area.get_overlapping_areas()
	return areas[0] as Node2D if not areas.is_empty() else null

## Nearest hazard (asteroids/mines) ahead within lookahead px, for opt-in avoidance.
func hazard_ahead(lookahead: float) -> Node2D:
	var best: Node2D = null
	var best_d := lookahead
	for grp in ["asteroids", "mines"]:
		for n in get_tree().get_nodes_in_group(grp):
			var h := n as Node2D
			if h == null:
				continue
			var dy := _pos().y - h.global_position.y
			if dy <= 0.0 or dy > lookahead:
				continue
			if dy < best_d:
				best_d = dy
				best = h
	return best

func gap_to(p: RaceParticipant) -> float:
	return p.track_y - _part.track_y if p else 0.0

func player() -> RaceParticipant:
	return _director.get_player() if _director else null
```

- [ ] **Step 2: Write `RacerWeapon` (firing; no target policy)**

```gdscript
## RacerWeapon — pooled forward/aimed firing for a racer. The brain decides target & timing.
class_name RacerWeapon
extends Node

@export var bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
@export var pool_size: int = 12

var _pool: BulletPool = null

func setup(host: RaceShip) -> void:
	_pool = BulletPool.new()
	_pool.bullet_scene = bullet_scene
	_pool.pool_size = pool_size
	## Parent under the racer so BulletPool resolves the EnemyContainer as grandparent.
	host.add_child.call_deferred(_pool)

func fire(from: Vector2, dir: Vector2, damage: int, speed: float) -> void:
	if _pool == null:
		return
	var bullet := _pool.acquire(from) as EnemyBullet
	if bullet == null:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = damage
	bullet.speed = speed
	bullet.set_direction(dir)

func fire_at(from: Vector2, target: Node2D, damage: int, speed: float) -> void:
	if target == null:
		return
	fire(from, (target.global_position - from).normalized(), damage, speed)
```

- [ ] **Step 3: Write `LateralMover` (smoothed X glide + opt-in avoidance)**

```gdscript
## LateralMover — critically-damped horizontal glide toward a target X, clamped to arena bounds.
## Avoidance is OFFERED (avoidance_nudge); each brain decides whether to add it.
class_name LateralMover
extends Node

@export var smooth_tau: float = 0.12
@export var min_x: float = 80.0
@export var max_x: float = 1200.0
@export var avoid_radius: float = 110.0

func step(current_x: float, target_x: float, delta: float) -> float:
	var k := 1.0 - exp(-delta / maxf(0.01, smooth_tau))
	return clampf(lerpf(current_x, target_x, k), min_x, max_x)

## Sum of pushes away from hazards within avoid_radius in X and lookahead in Y. Brains opt in.
func avoidance_nudge(host: RaceShip, lookahead: float) -> float:
	var push := 0.0
	for grp in ["asteroids", "mines"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var h := n as Node2D
			if h == null:
				continue
			var diff := host.global_position - h.global_position
			if absf(diff.y) > lookahead or absf(diff.x) > avoid_radius:
				continue
			var away := signf(diff.x) if absf(diff.x) > 0.5 else 1.0
			push += away * (avoid_radius - absf(diff.x))
	return push
```

- [ ] **Step 4: Write `RacerStateMachine` (manual-tick, name-based FSM)**

This is the race FSM **runner** (infrastructure, no decisions) — distinct from the player's
auto-tick `StateMachine`. Brains transition by **state name**, so no per-edge scene wiring.

```gdscript
## RacerStateMachine — holds a racer's State children, injects the host into each, ticks the
## current state on demand (RaceShip drives the order), and transitions by node NAME. Bespoke
## decision logic lives in the State subclasses, never here.
class_name RacerStateMachine
extends Node

@export var initial_state_name: StringName = &""

var host: RaceShip = null
var current: State = null
var _states: Dictionary = {}   ## StringName -> State

func setup(p_host: RaceShip) -> void:
	host = p_host
	for child in get_children():
		if child is State:
			_states[child.name] = child
			child.set("host", host)      ## inject; each race State declares `var host: RaceShip`
	var start := _states.get(initial_state_name, null) as State
	if start == null and not _states.is_empty():
		start = _states.values()[0]
	current = start
	if current:
		current.enter()

func tick(delta: float) -> void:
	if current:
		current.process_physics(delta)

func transition_to(state_name: StringName) -> void:
	var next := _states.get(state_name, null) as State
	if next == null or next == current:
		return
	if current:
		current.exit()
	current = next
	current.enter()

func get_state(state_name: StringName) -> State:
	return _states.get(state_name, null)
```

- [ ] **Step 5: Write `RaceShip` (the shared chassis — ZERO decisions)**

```gdscript
## RaceShip — the shared AI-racer chassis. It wires the shared components, applies the brain's
## intents to the transform (X from the mover toward desired_x; Y from RaceWorld via track_y),
## and routes damage uniformly. It contains NO decision logic — every choice lives in the
## bespoke RacerStateMachine + State children that make each racer unique.
class_name RaceShip
extends CharacterBody2D

@onready var participant: RaceParticipant = $RaceParticipant
@onready var sensors: Sensors = $Sensors
@onready var weapon: RacerWeapon = $RacerWeapon
@onready var mover: LateralMover = $LateralMover
@onready var brain: RacerStateMachine = $Brain
@onready var health: Health = $Health
@onready var shield: Shield = $Shield
@onready var hurt_box: HurtBox = $HurtBox
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _reaction: DamageReaction = $DamageReaction

## Brain writes this each frame; the chassis glides X toward it.
var desired_x: float = 0.0

var _world: RaceWorld = null

func _ready() -> void:
	add_to_group("racers")
	desired_x = global_position.x
	hurt_box.collision_layer = 512
	hurt_box.collision_mask = 64 | 1024
	_reaction.setup(health, shield, hurt_box, _sprite)
	## Taking a hit also costs top speed (the economy penalty).
	_reaction.on_hit = func(_dmg: int) -> void: participant.lose_top_speed_on_hit()
	_world = get_tree().get_first_node_in_group("race_world") as RaceWorld
	sensors.setup(self)
	weapon.setup(self)
	brain.setup(self)

func _physics_process(delta: float) -> void:
	brain.tick(delta)
	var x := mover.step(global_position.x, desired_x, delta)
	var y := _world.screen_y_for(participant.track_y) if _world else global_position.y
	global_position = Vector2(x, y)

# ── Intent helpers the bespoke States call (actions, not decisions) ───────────────────
func set_forward_floor() -> void: participant.set_cruise_factor(1.0)
func set_forward_coast(f: float = 0.6) -> void: participant.set_cruise_factor(f)

## Match a target's pace, holding `gap` track_y behind it (positive gap = behind).
func set_forward_match(target: RaceParticipant, gap: float) -> void:
	if target == null:
		participant.set_cruise_factor(0.85); return
	var want := target.track_y - gap
	var err := want - participant.track_y       ## >0 = behind desired ⇒ speed up
	participant.set_cruise_factor(clampf(0.85 + err * 0.002, 0.0, 1.0))

func steer_toward(x: float) -> void: desired_x = x
func add_avoidance(lookahead: float = 240.0) -> void:
	desired_x += mover.avoidance_nudge(self, lookahead)

func is_lined_up(target: RaceParticipant, tol: float) -> bool:
	return target != null and absf(global_position.x - target.global_x()) < tol \
		and participant.track_y < target.track_y      ## target ahead of me

func muzzle() -> Vector2:
	return global_position + Vector2(0.0, -24.0)
```

- [ ] **Step 6: Verify the kit compiles**

In the Script editor, confirm `sensors.gd`, `racer_weapon.gd`, `lateral_mover.gd`,
`racer_state_machine.gd`, `race_ship.gd` all show **no parse errors**. (They run for real when
Fang is built next.)

---

## Task 10: Fang — the tail-hunter (the reference bespoke racer)

**Files:**
- Create: `assault/scenes/race/racers/fang/states/fang_hunt_state.gd`
- Create: `assault/scenes/race/racers/fang/states/fang_lunge_state.gd`
- Create: `assault/scenes/race/racers/fang/states/fang_dodge_state.gd`
- Create: `assault/scenes/race/racers/fang/fang.tscn`

Fang's identity (its own FSM): **HUNT** the ship in front and suppress it → **LUNGE** to ram when
lined up → **DODGE** threats. Stats are `@export`s on its states (no personality resource).

- [ ] **Step 1: Write `FangHuntState`**

```gdscript
## FangHuntState — sit behind the ship in front (player or rival), match lane, suppress with
## forward fire. → LUNGE when lined up & close; → DODGE on a threat; chase panels only if there
## is nothing to hunt (Fang prioritises the kill over speed).
class_name FangHuntState
extends State

var host: RaceShip

@export var hunt_range: float = 2200.0   ## track_y units within which Fang engages
@export var lane_tol: float = 220.0
@export var follow_gap: float = 240.0    ## track_y to hold behind the prey
@export var lunge_range: float = 520.0   ## track_y gap at which Fang commits a lunge
@export var aim_tol: float = 70.0
@export var fire_cd: float = 0.7
@export var bullet_damage: int = 8
@export var bullet_speed: float = 300.0

var _cd: float = 0.0

func process_physics(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"FangDodge"); return

	var prey := host.sensors.ship_ahead(hunt_range, lane_tol)
	if prey == null:
		# Nothing to hunt → keep speed up by grabbing a panel, else hold centre.
		var panel := host.sensors.nearest_panel_ahead(600.0)
		host.steer_toward(panel.global_position.x if panel else 640.0)
		host.set_forward_floor()
		return

	host.set_forward_match(prey, follow_gap)
	host.steer_toward(prey.global_x())
	if _cd <= 0.0 and host.is_lined_up(prey, aim_tol):
		host.weapon.fire_at(host.muzzle(), prey.ship(), bullet_damage, bullet_speed)
		_cd = fire_cd

	if host.sensors.gap_to(prey) < lunge_range and host.is_lined_up(prey, aim_tol):
		host.brain.transition_to(&"FangLunge")
```

- [ ] **Step 2: Write `FangLungeState`**

```gdscript
## FangLungeState — a brief invincible over-speed straight up the prey's lane, dealing contact
## damage to any ship passed once. Then back to HUNT.
class_name FangLungeState
extends State

var host: RaceShip

@export var lunge_time: float = 0.7
@export var lunge_cruise: float = 1.0
@export var lunge_lunge: float = 500.0     ## extra track_y leap
@export var contact_damage: int = 22
@export var contact_radius: float = 70.0

var _t: float = 0.0
var _hit: Array = []

func enter() -> void:
	_t = lunge_time
	_hit.clear()
	host.hurt_box.monitoring = false              ## i-frames during the lunge
	host.participant.set_cruise_factor(lunge_cruise)
	host.participant.track_y += lunge_lunge

func process_physics(delta: float) -> void:
	_t -= delta
	_damage_scan()
	if _t <= 0.0:
		host.hurt_box.monitoring = true
		host.brain.transition_to(&"FangHunt")

func exit() -> void:
	host.hurt_box.monitoring = true

func _damage_scan() -> void:
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host or s in _hit:
				continue
			if host.global_position.distance_to(s.global_position) > contact_radius:
				continue
			var hb := s.get_node_or_null("HurtBox") as HurtBox
			if hb:
				hb.received_damage.emit(contact_damage)
			_hit.append(s)
```

- [ ] **Step 3: Write `FangDodgeState`**

```gdscript
## FangDodgeState — sidestep the incoming threat, then resume HUNT once clear.
class_name FangDodgeState
extends State

var host: RaceShip

@export var sidestep: float = 180.0

func process_physics(_delta: float) -> void:
	var threat := host.sensors.incoming_threat()
	if threat == null:
		host.brain.transition_to(&"FangHunt"); return
	var away := signf(host.global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	host.steer_toward(host.global_position.x + away * sidestep)
	host.set_forward_floor()
```

- [ ] **Step 4: Author `fang.tscn`**

The chassis components + Fang sprite + a `Brain` holding the three states. Note the
`RaceParticipant`/`Health`/`Shield` stat values are Fang's "stats."

```
[gd_scene load_steps=14 format=3]

[ext_resource type="Script" path="res://assault/scenes/race/core/race_ship.gd" id="ship"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/racers/fang.png" id="tex"]
[ext_resource type="Script" path="res://global/components/health_component.gd" id="health"]
[ext_resource type="Script" path="res://global/components/shield_component.gd" id="shield"]
[ext_resource type="Script" path="res://global/components/hurtbox_component.gd" id="hurt"]
[ext_resource type="Script" path="res://global/components/damage_reaction.gd" id="react"]
[ext_resource type="Script" path="res://assault/scenes/race/core/race_participant.gd" id="part"]
[ext_resource type="Script" path="res://assault/scenes/race/core/sensors.gd" id="sensors"]
[ext_resource type="Script" path="res://assault/scenes/race/core/racer_weapon.gd" id="weapon"]
[ext_resource type="Script" path="res://assault/scenes/race/core/lateral_mover.gd" id="mover"]
[ext_resource type="Script" path="res://assault/scenes/race/core/racer_state_machine.gd" id="brain"]
[ext_resource type="Script" path="res://assault/scenes/race/racers/fang/states/fang_hunt_state.gd" id="s_hunt"]
[ext_resource type="Script" path="res://assault/scenes/race/racers/fang/states/fang_lunge_state.gd" id="s_lunge"]
[ext_resource type="Script" path="res://assault/scenes/race/racers/fang/states/fang_dodge_state.gd" id="s_dodge"]

[sub_resource type="CircleShape2D" id="body"]
radius = 18.0
[sub_resource type="CircleShape2D" id="hurtshape"]
radius = 18.0

[node name="Fang" type="CharacterBody2D"]
script = ExtResource("ship")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("tex")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("body")

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 512
collision_mask = 1088
script = ExtResource("hurt")
[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("hurtshape")

[node name="Health" type="Node" parent="."]
script = ExtResource("health")
max_health = 70
current_health = 70

[node name="Shield" type="Node" parent="."]
script = ExtResource("shield")
bind_progression = false
permanent_charges = 1

[node name="DamageReaction" type="Node" parent="."]
script = ExtResource("react")

[node name="RaceParticipant" type="Node" parent="."]
script = ExtResource("part")
max_top_speed = 560.0

[node name="Sensors" type="Node" parent="."]
script = ExtResource("sensors")

[node name="RacerWeapon" type="Node" parent="."]
script = ExtResource("weapon")

[node name="LateralMover" type="Node" parent="."]
script = ExtResource("mover")

[node name="Brain" type="Node" parent="." node_paths=PackedStringArray()]
script = ExtResource("brain")
initial_state_name = &"FangHunt"

[node name="FangHunt" type="Node" parent="Brain"]
script = ExtResource("s_hunt")

[node name="FangLunge" type="Node" parent="Brain"]
script = ExtResource("s_lunge")

[node name="FangDodge" type="Node" parent="Brain"]
script = ExtResource("s_dodge")
```

> Adjust `load_steps` if Godot recomputes it. The `Health`/`Shield`/`HurtBox` scripts must be the
> real component script paths — confirm them in `global/components/` (names per the file map).

- [ ] **Step 5: Verify Fang in a quick harness**

Re-create a minimal sandbox (or temporarily re-add the Task 7 sandbox) containing
`RaceDirector`, `RaceWorld`, background, camera, the player (with participant+controller via the
boot script), **two `dash_panel` instances**, and **one `fang.tscn`** placed at `position` near
the player with its `RaceParticipant.track_y` left 0. Run (F6). Expected:
- Fang appears, **slides behind the player**, matches the player's lane, and **fires** at it
  when lined up.
- Flying the player into Fang's lane while it's close triggers a **lunge** (Fang surges through,
  briefly invincible, dealing a chunk of damage).
- Shooting Fang enough **destroys** it (explosion); a threat near Fang makes it **sidestep**.
- No errors. Delete the harness afterward.

---

# PHASE 4 — The rest of the roster

> Each racer is its own scene + states, reusing the Task 9 kit. To author each `*.tscn`, copy
> Fang's scene structure (Task 10 Step 4), swap the `Sprite2D` texture, set the racer's stat
> values on `Health`/`Shield`/`RaceParticipant`, and replace the `Brain`'s state children +
> `initial_state_name` with that racer's states below.

## Task 11: Pacer — the rabbit (2-state pace-setter)

**Files:**
- Create: `assault/scenes/race/racers/pacer/states/pacer_run_state.gd`
- Create: `assault/scenes/race/racers/pacer/states/pacer_dodge_state.gd`
- Create: `assault/scenes/race/racers/pacer/pacer.tscn`

- [ ] **Step 1: Write `PacerRunState`**

```gdscript
## PacerRunState — the benchmark rabbit: chase the nearest panel to keep top speed maxed, hold a
## fast clean line, never fight. → DODGE on a threat.
class_name PacerRunState
extends State

var host: RaceShip

@export var panel_reach: float = 700.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"PacerDodge"); return
	host.set_forward_floor()
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	host.steer_toward(panel.global_position.x if panel else host.global_position.x)
	host.add_avoidance()
```

- [ ] **Step 2: Write `PacerDodgeState`**

```gdscript
## PacerDodgeState — brief sidestep, then back to RUN.
class_name PacerDodgeState
extends State

var host: RaceShip

@export var sidestep: float = 170.0

func process_physics(_delta: float) -> void:
	var threat := host.sensors.incoming_threat()
	if threat == null:
		host.brain.transition_to(&"PacerRun"); return
	var away := signf(host.global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	host.steer_toward(host.global_position.x + away * sidestep)
	host.set_forward_floor()
```

- [ ] **Step 3: Author `pacer.tscn`** — copy Fang's scene; sprite `zipper.png`; `Health
max_health = 60`; `Shield permanent_charges = 1`; `RaceParticipant max_top_speed = 600`;
`Brain initial_state_name = &"PacerRun"` with children `PacerRun` (`pacer_run_state.gd`) and
`PacerDodge` (`pacer_dodge_state.gd`).

- [ ] **Step 4: Verify** — in the Task 14 level (or a harness), the Pacer **beelines panel to
panel** and holds a fast line, setting the pace; it sidesteps threats and never engages.

---

## Task 12: Bogomol (mine-on-panel) — Booster Gold (dash-ram)

### Task 12a: `Mine` track object (shared by Bogomol)

**Files:**
- Create: `assault/scenes/race/track/mine.gd` + `mine.tscn`

- [ ] **Step 1: Write `Mine`**

```gdscript
## Mine — a track-anchored hazard dropped by Bogomol (reuses the bomb idea). After a short arm
## delay it damages any ship whose HurtBox overlaps (polled). In group "mines" so every Sensors
## and LateralMover already avoids it.
class_name Mine
extends TrackObject

@export var damage: int = 30
@export var arm_delay: float = 0.4
@export var trigger_radius: float = 46.0
@export var lifetime: float = 8.0

var _armed: float = 0.0
var _life: float = 0.0

func _on_track_ready() -> void:
	add_to_group("mines")
	collision_layer = 8
	collision_mask = 0
	_armed = arm_delay
	_life = lifetime

func _on_track_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free(); return
	if _armed > 0.0:
		_armed -= delta
		return
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null:
				continue
			if global_position.distance_to(s.global_position) <= trigger_radius:
				var hb := s.get_node_or_null("HurtBox") as HurtBox
				if hb:
					hb.received_damage.emit(damage)
				queue_free()
				return
```

- [ ] **Step 2: Author `mine.tscn`** — `Area2D` root with script `mine.gd`, a small `Sprite2D`
(reuse any small sprite, e.g. `stand.png` recolored) and a `CollisionShape2D` (visual only).

### Task 12b: Bogomol brain + scene

**Files:**
- Create: `assault/scenes/race/racers/bogomol/states/bogomol_seek_state.gd`
- Create: `assault/scenes/race/racers/bogomol/states/bogomol_mine_state.gd`
- Create: `assault/scenes/race/racers/bogomol/states/bogomol_cruise_state.gd`
- Create: `assault/scenes/race/racers/bogomol/states/bogomol_evade_state.gd`
- Create: `assault/scenes/race/racers/bogomol/bogomol.tscn`

- [ ] **Step 1: Write `BogomolSeekState`**

```gdscript
## BogomolSeekState — race for the nearest reachable panel on both axes (it benefits AND will
## deny it). → MINE_DROP on crossing; → CRUISE if no panel; → EVADE on threat.
class_name BogomolSeekState
extends State

var host: RaceShip

@export var panel_reach: float = 900.0
@export var cross_dist: float = 60.0

var _target: Node2D = null

func enter() -> void:
	_target = null

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BogomolEvade"); return
	_target = host.sensors.nearest_panel_ahead(panel_reach)
	if _target == null:
		host.brain.transition_to(&"BogomolCruise"); return
	host.set_forward_floor()
	host.steer_toward(_target.global_position.x)
	if host.global_position.distance_to(_target.global_position) < cross_dist:
		host.brain.get_state(&"BogomolMine").set("drop_at", _target.global_position)
		host.brain.transition_to(&"BogomolMine")
```

- [ ] **Step 2: Write `BogomolMineState`**

```gdscript
## BogomolMineState — drop a mine at the panel just crossed (so trailing ships eat it), then
## resume seeking the next panel.
class_name BogomolMineState
extends State

var host: RaceShip
var drop_at: Vector2 = Vector2.ZERO

const _MINE: PackedScene = preload("res://assault/scenes/race/track/mine.tscn")

func enter() -> void:
	var mine := _MINE.instantiate() as Mine
	## track_y of the drop = the panel's current track position (world-derived).
	var world := host.get_tree().get_first_node_in_group("race_world") as RaceWorld
	mine.track_y = world.track_y_for_screen_y(drop_at.y) if world else host.participant.track_y
	mine.position = Vector2(drop_at.x, drop_at.y)
	host.get_parent().add_child(mine)
	host.brain.transition_to(&"BogomolSeek")

func process_physics(_delta: float) -> void:
	pass
```

- [ ] **Step 3: Write `BogomolCruiseState`**

```gdscript
## BogomolCruiseState — no panel reachable: hold a defensive fast line and occasionally lay a
## mine on its own lane. → SEEK when a panel appears; → EVADE on threat.
class_name BogomolCruiseState
extends State

var host: RaceShip

@export var lay_interval: float = 3.0
const _MINE: PackedScene = preload("res://assault/scenes/race/track/mine.tscn")
var _t: float = 0.0

func process_physics(delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BogomolEvade"); return
	if host.sensors.nearest_panel_ahead(900.0) != null:
		host.brain.transition_to(&"BogomolSeek"); return
	host.set_forward_floor()
	host.add_avoidance()
	_t -= delta
	if _t <= 0.0:
		_t = lay_interval
		var mine := _MINE.instantiate() as Mine
		mine.track_y = host.participant.track_y - 30.0
		mine.position = host.global_position + Vector2(0.0, 40.0)
		host.get_parent().add_child(mine)
```

- [ ] **Step 4: Write `BogomolEvadeState`**

```gdscript
## BogomolEvadeState — sidestep threat, then back to SEEK.
class_name BogomolEvadeState
extends State

var host: RaceShip

@export var sidestep: float = 180.0

func process_physics(_delta: float) -> void:
	var threat := host.sensors.incoming_threat()
	if threat == null:
		host.brain.transition_to(&"BogomolSeek"); return
	var away := signf(host.global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	host.steer_toward(host.global_position.x + away * sidestep)
	host.set_forward_floor()
```

- [ ] **Step 5: Author `bogomol.tscn`** — copy Fang's scene; sprite `bogomol.png`; `Health
max_health = 60`; `Shield permanent_charges = 2`; `RaceParticipant max_top_speed = 560`;
`Brain initial_state_name = &"BogomolSeek"` with children `BogomolSeek`, `BogomolMine`,
`BogomolCruise`, `BogomolEvade` (their scripts).

- [ ] **Step 6: Verify** — Bogomol **races to panels, crosses them, and drops a mine** at each;
mines arm and **damage ships that follow through the panel**; with no panels it cruises and lays
the occasional mine; it evades threats.

### Task 12c: Booster Gold brain + scene (the front-runner / reclaim-dasher)

**Files:**
- Create: `assault/scenes/race/racers/booster_gold/states/bg_frontrun_state.gd`
- Create: `assault/scenes/race/racers/booster_gold/states/bg_grab_panel_state.gd`
- Create: `assault/scenes/race/racers/booster_gold/states/bg_reclaim_state.gd`
- Create: `assault/scenes/race/racers/booster_gold/states/bg_dash_state.gd`
- Create: `assault/scenes/race/racers/booster_gold/states/bg_juke_state.gd`
- Create: `assault/scenes/race/racers/booster_gold/states/bg_evade_state.gd`
- Create: `assault/scenes/race/racers/booster_gold/booster_gold.tscn`

Per your refinement: **stay in front via panels** (panels = very high priority); when **behind**,
**dash** to reclaim. The FSM splits by standing (`director.is_in_front`).

- [ ] **Step 1: Write `BgFrontrunState`** (home state while in 1st)

```gdscript
## BgFrontrunState — active while Booster Gold is in 1st. Defend the lead: GRAB_PANEL preempts
## almost everything (panels keep top speed maxed = lead held). Soft-block the player by drifting
## onto the panel it wants. JUKE if tailed. Does NOT spend the dash here. → RECLAIM if passed.
class_name BgFrontrunState
extends State

var host: RaceShip

@export var panel_reach: float = 900.0
@export var tail_gap: float = 220.0       ## track_y within which a chaser counts as "tailing"
@export var tail_lane: float = 160.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	var dir := host._director()
	if dir and not dir.is_in_front(host.participant):
		host.brain.transition_to(&"BgReclaim"); return

	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	if panel != null:
		host.brain.get_state(&"BgGrabPanel").set("return_to", &"BgFrontrun")
		host.brain.transition_to(&"BgGrabPanel"); return

	# Someone sitting on my tail? Juke to deny the slipstream.
	var chaser := host.sensors.ship_behind(tail_gap, tail_lane)
	if chaser != null:
		host.brain.transition_to(&"BgJuke"); return

	host.set_forward_floor()
	host.steer_toward(host.global_position.x)   ## hold a clean line
```

- [ ] **Step 2: Write `BgGrabPanelState`** (shared, highest opportunity priority)

```gdscript
## BgGrabPanelState — commit to the nearest reachable panel on both axes, then return to whatever
## mode invoked it (Frontrun or Reclaim).
class_name BgGrabPanelState
extends State

var host: RaceShip
var return_to: StringName = &"BgFrontrun"

@export var panel_reach: float = 1000.0
@export var cross_dist: float = 60.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	if panel == null:
		host.brain.transition_to(return_to); return
	host.set_forward_floor()
	host.steer_toward(panel.global_position.x)
	if host.global_position.distance_to(panel.global_position) < cross_dist:
		host.brain.transition_to(return_to)
```

- [ ] **Step 3: Write `BgReclaimState`** (active while NOT in 1st — the dash lives here)

```gdscript
## BgReclaimState — active whenever Booster Gold is not 1st. Floor it, still grab panels greedily
## (GRAB_PANEL preempts), and USE THE DASH: ram the ship ahead if in range & off cooldown, or
## dash as a pure surge if far behind the leader. → FRONTRUN when back in 1st.
class_name BgReclaimState
extends State

var host: RaceShip

@export var panel_reach: float = 900.0
@export var dash_range_min: float = 120.0
@export var dash_range_max: float = 1400.0   ## track_y gap to the ship ahead
@export var dash_aim_tol: float = 90.0
@export var lane_tol: float = 240.0
@export var desperation_gap: float = 2200.0  ## track_y behind leader → dash even with no clean target
@export var fire_cd: float = 0.5
@export var bullet_damage: int = 8
@export var bullet_speed: float = 320.0

var _fire: float = 0.0

func process_physics(delta: float) -> void:
	_fire = maxf(0.0, _fire - delta)
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	var dir := host._director()
	if dir and dir.is_in_front(host.participant):
		host.brain.transition_to(&"BgFrontrun"); return

	host.set_forward_floor()

	# Panels still preempt (greedy): they restore the top speed needed to reclaim.
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	var target := host.sensors.ship_ahead(dash_range_max, lane_tol)

	if host.brain.get_state(&"BgDash").get("ready") and _should_dash(dir, target):
		host.brain.get_state(&"BgDash").set("target", target)
		host.brain.transition_to(&"BgDash"); return

	if panel != null:
		host.brain.get_state(&"BgGrabPanel").set("return_to", &"BgReclaim")
		host.brain.transition_to(&"BgGrabPanel"); return

	# Chase + suppress the ship ahead while the dash recharges.
	if target != null:
		host.steer_toward(target.global_x())
		if _fire <= 0.0 and host.is_lined_up(target, dash_aim_tol):
			host.weapon.fire_at(host.muzzle(), target.ship(), bullet_damage, bullet_speed)
			_fire = fire_cd
	else:
		host.steer_toward(host.global_position.x)

func _should_dash(dir: RaceDirector, target: RaceParticipant) -> bool:
	if target != null:
		var gap := host.sensors.gap_to(target)
		if gap >= dash_range_min and gap <= dash_range_max \
				and absf(host.global_position.x - target.global_x()) <= dash_aim_tol:
			return true
	# No clean target but far behind the leader → surge dash anyway.
	return dir != null and dir.gap_to_leader(host.participant) > desperation_gap
```

- [ ] **Step 4: Write `BgDashState`** (the signature invincible ram)

```gdscript
## BgDashState — invincible boosted lunge up the target's lane (or straight ahead), contact
## damage once per ship passed, then a cooldown before it can dash again. Used from RECLAIM.
class_name BgDashState
extends State

var host: RaceShip
var target: RaceParticipant = null
var ready: bool = true

@export var dash_time: float = 0.85
@export var dash_lunge: float = 950.0
@export var dash_damage: int = 45
@export var dash_radius: float = 72.0
@export var cooldown: float = 7.0

var _t: float = 0.0
var _cd: float = 0.0
var _hit: Array = []

## Cooldown must keep ticking even while OTHER states are active, so it lives in the node's own
## physics callback (guarded to run ONLY when this is not the current state). The ACTIVE dash is
## driven by process_physics (called by brain.tick only while current) — the two never overlap.
func _physics_process(delta: float) -> void:
	if host == null or host.brain.current == self:
		return
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
		if _cd <= 0.0:
			ready = true

func enter() -> void:
	ready = false
	_t = dash_time
	_hit.clear()
	host.hurt_box.monitoring = false              ## i-frames during the dash
	host.participant.set_cruise_factor(1.0)
	host.participant.track_y += dash_lunge

func process_physics(delta: float) -> void:
	_t -= delta
	if target and is_instance_valid(target):
		host.steer_toward(target.global_x())
	_damage_scan()
	if _t <= 0.0:
		host.hurt_box.monitoring = true
		_cd = cooldown
		target = null
		host.brain.transition_to(&"BgReclaim")

func exit() -> void:
	host.hurt_box.monitoring = true

func _damage_scan() -> void:
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host or s in _hit:
				continue
			if host.global_position.distance_to(s.global_position) > dash_radius:
				continue
			var hb := s.get_node_or_null("HurtBox") as HurtBox
			if hb:
				hb.received_damage.emit(dash_damage)
			_hit.append(s)
```

> **Note on the cooldown:** `BgDashState` keeps its `_cd` ticking via its **own**
> `_physics_process` even when it is not the active brain state, so `ready` flips back on time.
> The brain's `tick()` only drives the *current* state's `process_physics`; the dash cooldown
> must persist across states, hence the dual path above.

- [ ] **Step 5: Write `BgJukeState`**

```gdscript
## BgJukeState — brief sidestep to shake a chaser off the tail while leading, then FRONTRUN.
class_name BgJukeState
extends State

var host: RaceShip

@export var juke_distance: float = 320.0
@export var juke_time: float = 0.5

var _t: float = 0.0
var _side: int = 1

func enter() -> void:
	_t = juke_time
	_side = -_side if _side != 0 else 1

func process_physics(delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	_t -= delta
	host.set_forward_floor()
	host.steer_toward(host.global_position.x + float(_side) * juke_distance)
	if _t <= 0.0:
		host.brain.transition_to(&"BgFrontrun")
```

- [ ] **Step 6: Write `BgEvadeState`**

```gdscript
## BgEvadeState — dodge a threat, then resume the right mode based on standing.
class_name BgEvadeState
extends State

var host: RaceShip

@export var sidestep: float = 180.0

func process_physics(_delta: float) -> void:
	var threat := host.sensors.incoming_threat()
	if threat == null:
		var dir := host._director()
		var back := dir and not dir.is_in_front(host.participant)
		host.brain.transition_to(&"BgReclaim" if back else &"BgFrontrun"); return
	var away := signf(host.global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	host.steer_toward(host.global_position.x + away * sidestep)
	host.set_forward_floor()
```

- [ ] **Step 7: Add the `_director()` helper to `RaceShip`**

The Booster Gold states call `host._director()`. Add to `race_ship.gd` (Task 9 Step 5):

```gdscript
var _dir_cache: RaceDirector = null
func _director() -> RaceDirector:
	if _dir_cache == null:
		_dir_cache = get_tree().get_first_node_in_group("race_director") as RaceDirector
	return _dir_cache
```

- [ ] **Step 8: Author `booster_gold.tscn`** — copy Fang's scene; sprite `gold_exprerience.png`;
`Health max_health = 60`; `Shield permanent_charges = 1`; `RaceParticipant max_top_speed = 600`
(highest, agile) with `decay_per_sec = 16` (low decay); `Brain initial_state_name =
&"BgFrontrun"` with children `BgFrontrun`, `BgGrabPanel`, `BgReclaim`, `BgDash`, `BgJuke`,
`BgEvade` (their scripts).

- [ ] **Step 9: Verify** — Booster Gold, while leading, **hogs every panel** and holds the front,
juking when tailed; once the player **passes him**, he flips to **RECLAIM** and **dashes** (an
invincible ram) through whoever's ahead — including the player — to retake 1st, then settles back
into front-running. No errors; the dash cooldown gates repeat dashes.

---

## Task 13: Isac (gatling) — Reacher (sniper)

### Task 13a: Isac

**Files:**
- Create: `assault/scenes/race/racers/isac/states/isac_prowl_state.gd`
- Create: `assault/scenes/race/racers/isac/states/isac_spray_state.gd`
- Create: `assault/scenes/race/racers/isac/states/isac_reposition_state.gd`
- Create: `assault/scenes/race/racers/isac/isac.tscn`

- [ ] **Step 1: Write `IsacProwlState`**

```gdscript
## IsacProwlState — drift toward the densest part of the field, grabbing panels of convenience.
## → SPRAY when any ship is within spray_radius; → REPOSITION on a direct threat.
class_name IsacProwlState
extends State

var host: RaceShip

@export var spray_radius: float = 320.0
@export var panel_reach: float = 600.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"IsacReposition"); return
	if _nearest_ship_within(spray_radius) != null:
		host.brain.transition_to(&"IsacSpray"); return
	host.set_forward_floor()
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	host.steer_toward(panel.global_position.x if panel else host.global_position.x)

func _nearest_ship_within(r: float) -> Node2D:
	var best: Node2D = null
	var bd := r
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host:
				continue
			var d := host.global_position.distance_to(s.global_position)
			if d < bd:
				bd = d; best = s
	return best
```

- [ ] **Step 2: Write `IsacSprayState`**

```gdscript
## IsacSprayState — hose the nearest ship in range continuously (lead it). Occupies space rather
## than chasing. → PROWL when the radius empties; → REPOSITION on a threat.
class_name IsacSprayState
extends State

var host: RaceShip

@export var spray_radius: float = 320.0
@export var fire_interval: float = 0.12
@export var bullet_damage: int = 4
@export var bullet_speed: float = 360.0

var _cd: float = 0.0

func process_physics(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"IsacReposition"); return
	var prey := _nearest_ship_within(spray_radius)
	if prey == null:
		host.brain.transition_to(&"IsacProwl"); return
	host.set_forward_coast(0.8)              ## slow turret; doesn't pursue hard
	host.steer_toward(host.global_position.x + signf(prey.global_position.x - host.global_position.x) * 40.0)
	if _cd <= 0.0:
		host.weapon.fire_at(host.muzzle(), prey, bullet_damage, bullet_speed)
		_cd = fire_interval

func _nearest_ship_within(r: float) -> Node2D:
	var best: Node2D = null
	var bd := r
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host:
				continue
			var d := host.global_position.distance_to(s.global_position)
			if d < bd:
				bd = d; best = s
	return best
```

- [ ] **Step 3: Write `IsacRepositionState`**

```gdscript
## IsacRepositionState — short slide off a threat, never fully fleeing. → PROWL when clear.
class_name IsacRepositionState
extends State

var host: RaceShip

@export var sidestep: float = 150.0
@export var slide_time: float = 0.4

var _t: float = 0.0

func enter() -> void:
	_t = slide_time

func process_physics(delta: float) -> void:
	_t -= delta
	var threat := host.sensors.incoming_threat()
	var away := 1.0
	if threat:
		away = signf(host.global_position.x - threat.global_position.x)
		if away == 0.0:
			away = 1.0
	host.set_forward_floor()
	host.steer_toward(host.global_position.x + away * sidestep)
	if _t <= 0.0:
		host.brain.transition_to(&"IsacProwl")
```

- [ ] **Step 4: Author `isac.tscn`** — copy Fang's scene; sprite `Isac.png`; `Health
max_health = 90` (tanky); `Shield permanent_charges = 1`; `RaceParticipant max_top_speed = 480`,
`decay_per_sec = 14` (steady); `RacerWeapon pool_size = 24` (high fire rate); `Brain
initial_state_name = &"IsacProwl"` with children `IsacProwl`, `IsacSpray`, `IsacReposition`.

- [ ] **Step 5: Verify** — Isac drifts into the pack and **sprays continuously** at the nearest
ship while any are in radius; it doesn't chase, slides when threatened, and is notably tanky.

### Task 13b: Reacher

**Files:**
- Create: `assault/scenes/race/racers/reacher/states/reacher_position_state.gd`
- Create: `assault/scenes/race/racers/reacher/states/reacher_aim_state.gd`
- Create: `assault/scenes/race/racers/reacher/states/reacher_catchup_state.gd`
- Create: `assault/scenes/race/racers/reacher/states/reacher_evade_state.gd`
- Create: `assault/scenes/race/racers/reacher/reacher.tscn`

- [ ] **Step 1: Write `ReacherPositionState`**

```gdscript
## ReacherPositionState — keep a stand-off gap and a clear lane to a target; sidestep to open a
## shot. → AIM when lined up & charged; → CATCH_UP if dropping too far back; → EVADE on threat.
class_name ReacherPositionState
extends State

var host: RaceShip

@export var standoff_gap: float = 1200.0   ## track_y it likes to sit behind the target
@export var lane_tol: float = 90.0
@export var fall_behind_gap: float = 3000.0 ## track_y behind leader → CATCH_UP
@export var charge_time: float = 1.2

var _charge: float = 0.0

func enter() -> void:
	_charge = charge_time

func process_physics(delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"ReacherEvade"); return
	var dir := host._director()
	if dir and dir.gap_to_leader(host.participant) > fall_behind_gap:
		host.brain.transition_to(&"ReacherCatchup"); return

	var target := host.sensors.ship_ahead(8000.0, 9999.0)   ## any ship ahead, any lane
	host.set_forward_match(target, standoff_gap)
	if target:
		host.steer_toward(target.global_x())
	_charge = maxf(0.0, _charge - delta)
	if target and _charge <= 0.0 and absf(host.global_position.x - target.global_x()) < lane_tol:
		host.brain.get_state(&"ReacherAim").set("target", target)
		host.brain.transition_to(&"ReacherAim")
```

- [ ] **Step 2: Write `ReacherAimState`**

```gdscript
## ReacherAimState — brief telegraphed hold, then one heavy long-range shot leading the target.
## Returns to POSITION (which recharges).
class_name ReacherAimState
extends State

var host: RaceShip
var target: RaceParticipant = null

@export var telegraph: float = 0.35
@export var snipe_damage: int = 30
@export var snipe_speed: float = 700.0

var _t: float = 0.0

func enter() -> void:
	_t = telegraph

func process_physics(delta: float) -> void:
	_t -= delta
	host.set_forward_coast(0.7)
	if target and is_instance_valid(target.ship()):
		host.steer_toward(target.global_x())
	if _t <= 0.0:
		if target and is_instance_valid(target.ship()):
			host.weapon.fire_at(host.muzzle(), target.ship(), snipe_damage, snipe_speed)
		target = null
		host.brain.transition_to(&"ReacherPosition")
```

- [ ] **Step 3: Write `ReacherCatchupState`**

```gdscript
## ReacherCatchupState — temporarily prioritise panels to recover lost top speed, then POSITION.
class_name ReacherCatchupState
extends State

var host: RaceShip

@export var recovered_gap: float = 1600.0   ## track_y behind leader to resume positioning

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"ReacherEvade"); return
	host.set_forward_floor()
	var panel := host.sensors.nearest_panel_ahead(900.0)
	host.steer_toward(panel.global_position.x if panel else host.global_position.x)
	var dir := host._director()
	if dir and dir.gap_to_leader(host.participant) < recovered_gap:
		host.brain.transition_to(&"ReacherPosition")
```

- [ ] **Step 4: Write `ReacherEvadeState`**

```gdscript
## ReacherEvadeState — sidestep threat, then POSITION.
class_name ReacherEvadeState
extends State

var host: RaceShip

@export var sidestep: float = 170.0

func process_physics(_delta: float) -> void:
	var threat := host.sensors.incoming_threat()
	if threat == null:
		host.brain.transition_to(&"ReacherPosition"); return
	var away := signf(host.global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	host.steer_toward(host.global_position.x + away * sidestep)
	host.set_forward_floor()
```

- [ ] **Step 5: Author `reacher.tscn`** — copy Fang's scene; sprite `reacher.png`; `Health
max_health = 65`; `Shield permanent_charges = 1`; `RaceParticipant max_top_speed = 560`; `Brain
initial_state_name = &"ReacherPosition"` with children `ReacherPosition`, `ReacherAim`,
`ReacherCatchup`, `ReacherEvade`.

- [ ] **Step 6: Verify** — Reacher **hangs back**, lines up, **telegraphs then lands heavy
shots** on the ship ahead; if it falls far behind it **grabs panels to catch up**, then resumes
sniping; it dodges threats.

---

# PHASE 5 — Level, HUD, finish/fail flow

## Task 14: `RaceLevelConfig` + `race_level_1.tscn` + the authored `Track`

**Files:**
- Create: `assault/scenes/race/race_level_config.gd`
- Create: `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Write the level config (boot)**

```gdscript
## RaceLevelConfig — boots the race: attaches RaceParticipant + PlayerRaceController to the
## shared player, binds player death to the director, and restarts on failure. Racers and track
## furniture are authored in the scene (or spawned by WaveManager); they self-register.
class_name RaceLevelConfig
extends Node

@export var director: RaceDirector
@export var player_health_node: NodePath = ^"HealthComponent"

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var participant := RaceParticipant.new()
		participant.name = "RaceParticipant"
		participant.is_player = true
		player.add_child(participant)
		var ctrl := PlayerRaceController.new()
		ctrl.name = "PlayerRaceController"
		player.add_child(ctrl)
		var health := player.get_node_or_null(player_health_node) as Health
		ctrl.setup(player, participant, health)
		if director and health:
			director.bind_player_health(health)
	if director:
		director.race_failed.connect(_on_race_failed)

func _on_race_failed() -> void:
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()
```

> Confirm the player's Health node name; set `player_health_node` accordingly in the Inspector.

- [ ] **Step 2: Author `race_level_1.tscn`**

Mirror `level_1.tscn` but with the race nodes. Include the background, pinned camera,
`RaceDirector`, `RaceWorld`, an `EnemyContainer` (BulletPool grandparent), a `Track` node with a
few `dash_panel` instances + a `finish_line`, the racers, the HUD (Task 15), `RaceLevelConfig`,
and the player.

```
[gd_scene load_steps=12 format=3]

[ext_resource type="PackedScene" path="res://assault/scenes/levels/edelia/1/level_1_background.tscn" id="bg"]
[ext_resource type="Script" path="res://assault/scenes/systems/arena_camera.gd" id="cam"]
[ext_resource type="Script" path="res://assault/scenes/race/core/race_director.gd" id="dir"]
[ext_resource type="Script" path="res://assault/scenes/race/core/race_world.gd" id="world"]
[ext_resource type="Script" path="res://assault/scenes/race/race_level_config.gd" id="cfg"]
[ext_resource type="PackedScene" path="res://assault/scenes/race/track/dash_panel.tscn" id="panel"]
[ext_resource type="PackedScene" path="res://assault/scenes/race/track/finish_line.tscn" id="finish"]
[ext_resource type="PackedScene" path="res://assault/scenes/race/racers/pacer/pacer.tscn" id="pacer"]
[ext_resource type="PackedScene" path="res://assault/scenes/race/racers/fang/fang.tscn" id="fang"]
[ext_resource type="PackedScene" path="res://assault/scenes/race/racers/booster_gold/booster_gold.tscn" id="bg_racer"]
[ext_resource type="PackedScene" path="res://assault/scenes/player/player_fighter.tscn" id="player"]

[node name="RaceLevel1" type="Node2D"]

[node name="Level1Background" parent="." groups=["background"] instance=ExtResource("bg")]

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(640, 360)
script = ExtResource("cam")

[node name="RaceDirector" type="Node" parent="." groups=["race_director"]]
script = ExtResource("dir")
track_length = 18000.0

[node name="RaceWorld" type="Node" parent="." groups=["race_world"]]
script = ExtResource("world")

[node name="EnemyContainer" type="Node2D" parent="."]

[node name="Track" type="Node2D" parent="."]

[node name="Panel1" parent="Track" instance=ExtResource("panel")]
position = Vector2(420, 0)
track_y = 1600.0
[node name="Panel2" parent="Track" instance=ExtResource("panel")]
position = Vector2(900, 0)
track_y = 3200.0
[node name="Panel3" parent="Track" instance=ExtResource("panel")]
position = Vector2(640, 0)
track_y = 5000.0
[node name="Panel4" parent="Track" instance=ExtResource("panel")]
position = Vector2(300, 0)
track_y = 7200.0
[node name="Finish" parent="Track" instance=ExtResource("finish")]
position = Vector2(640, 0)

[node name="Racers" type="Node2D" parent="."]
[node name="Pacer" parent="Racers" instance=ExtResource("pacer")]
position = Vector2(360, 480)
[node name="Fang" parent="Racers" instance=ExtResource("fang")]
position = Vector2(640, 480)
[node name="BoosterGold" parent="Racers" instance=ExtResource("bg_racer")]
position = Vector2(900, 480)

[node name="RaceLevelConfig" type="Node" parent="." node_paths=PackedStringArray("director")]
script = ExtResource("cfg")
director = NodePath("../RaceDirector")

[node name="PlayerFighter" parent="." groups=["player"] instance=ExtResource("player")]
position = Vector2(640, 520)
```

> Racers' `RacerWeapon` pools parent under each racer; their bullets resolve `EnemyContainer` as
> grandparent only if the racer is a child of a node whose parent is `EnemyContainer`. If bullets
> mis-parent, move the `Racers` node to be a child of `EnemyContainer`, or set the racers'
> `RacerWeapon` to parent the pool under `EnemyContainer` directly. Verify in Step 3.

- [ ] **Step 3: Verify the full level boots**

Run `race_level_1.tscn` (F6). Expected: background scrolls; Pacer/Fang/Booster Gold appear and
behave per their FSMs; panels boost everyone; the player builds/loses top speed; reaching
`track_length` ends the player's race; dying restarts the scene after 2 s. Fix any
bullet-parenting warnings per the Step 2 note.

---

## Task 15: `RaceHUD` (standings + speed class) + finish/fail overlay

**Files:**
- Create: `assault/scenes/race/ui/race_hud.gd` + `race_hud.tscn`

- [ ] **Step 1: Write the HUD**

```gdscript
## RaceHUD — live standings (leader first, player highlighted), a top-speed "class" bar, and an
## end-of-race overlay. Subscribes to the RaceDirector and the player's RaceParticipant.
class_name RaceHUD
extends CanvasLayer

@export var director: RaceDirector

@onready var _standings: Label = $Panel/Standings
@onready var _speed: ProgressBar = $Panel/SpeedBar
@onready var _overlay: Label = $Overlay

func _ready() -> void:
	_overlay.hide()
	if director:
		director.standings_changed.connect(_on_standings)
		director.race_finished.connect(_on_finished)
		director.race_failed.connect(_on_failed)

func _on_standings(order: Array) -> void:
	var lines: Array[String] = []
	var place := 1
	for p in order:
		var part := p as RaceParticipant
		var tag := "YOU" if part.is_player else "CPU"
		lines.append("%s%d. %s" % [(">" if part.is_player else " "), place, tag])
		if part.is_player and _speed:
			_speed.max_value = part.max_top_speed
			_speed.value = part.top_speed
		place += 1
	_standings.text = "\n".join(lines)

func _on_finished(results: Array) -> void:
	var place := 1
	for i in results.size():
		if (results[i] as RaceParticipant).is_player:
			place = i + 1
	_overlay.text = "FINISH!\nPlace: %d" % place
	_overlay.show()

func _on_failed() -> void:
	_overlay.text = "DESTROYED\nRestarting…"
	_overlay.show()
```

- [ ] **Step 2: Author `race_hud.tscn`** — `CanvasLayer` (script `race_hud.gd`) with `Panel`
containing `Standings` (Label), `SpeedBar` (ProgressBar), and a centered `Overlay` (Label,
hidden). Anchor the panel top-left, the overlay center.

- [ ] **Step 3: Wire the HUD into `race_level_1.tscn`** — add a `RaceHUD` instance with
`node_paths` `director = NodePath("../RaceDirector")`.

- [ ] **Step 4: Verify** — running the level shows a live standings list (player highlighted) that
reorders as ships pass each other, a **speed bar that rises on panels and falls on decay/hits**,
and a **FINISH/DESTROYED overlay** at the end.

---

# PHASE 6 — Full roster + obstacles + optimisation

## Task 16: Add Bogomol, Isac, Reacher to the level + obstacle hazards

**Files:**
- Modify: `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Instance the remaining racers** — add `bogomol.tscn`, `isac.tscn`,
`reacher.tscn` under `Racers` at spread start X positions (e.g. 200, 640, 1080), `position.y`
≈ 480. Confirm all six FSMs coexist without errors.

- [ ] **Step 2: Add asteroid + laser hazards along the track** — under `Track`, place existing
asteroid scenes and `laser_ray`/`laser_wall` as `TrackObject`-wrapped or `WaveManager`-spawned
hazards at chosen `track_y`s so ships must dodge (asteroids already damage layer-512 hurtboxes;
lasers already one-hit-kill them). If using `WaveManager`, anchor spawns by `scroll_offset`
thresholds rather than wall-clock time.

- [ ] **Step 3: Verify** — a full six-racer field races a furnished track: rivals **dodge
asteroids/lasers, chase panels, and run their signatures**; the player must dodge + chase panels
to keep up; standings churn; finishing/dying resolves correctly.

## Task 17: Optimisation pass

**Files:**
- Modify: `assault/scenes/race/core/sensors.gd`, `race_director.gd` (as needed)

- [ ] **Step 1: Cache per-frame perception** — if profiling shows cost with the full field,
cache `_all_participants()` and group-scan results once per physics frame in `Sensors` (store on
the host or a shared per-frame cache), and ensure `RaceDirector` sorts standings exactly once per
frame (already does). Skill: `godot-prompter:godot-optimization`.

- [ ] **Step 2: Pool mines/bullets** — confirm `BulletPool` reuse; add a small `Mine` pool if
mine churn is high.

- [ ] **Step 3: Verify** — run the level with the full field for ~2 minutes; the profiler shows a
stable frame time and the Output has no per-frame spam or leaks.

---

## Self-Review — spec coverage

- **Track-space world model (research §4 Approach B):** Tasks 4–8 (`RaceWorld`/`RaceParticipant`/
  `RaceDirector`/`TrackObject`).
- **Top-speed economy (R3; architecture §5):** Task 4 (`cross_panel`/decay/`lose_top_speed_on_hit`),
  Task 8 (panels), Task 9 (`on_hit` wiring), Task 15 (speed bar).
- **Player control model (locked decision #2):** Task 7 (`PlayerRaceController`).
- **No-duplication (R9):** Task 2 (one `Shield`), Task 3 (`DamageReaction`), Task 9 (shared kit).
- **Bespoke per-racer FSMs, no shared brain (R7):** Tasks 10–13 — six racers, each own scene +
  states; no `RacerBehavior`/`RacerPersonality`.
- **Unique attack patterns (R5):** Bogomol mine-on-panel (Task 12b), Booster Gold dash-ram
  (Task 12c); plus Fang lunge, Isac gatling, Reacher snipe.
- **Rivals build top speed via panels (R4):** every brain seeks panels; shared economy applies.
- **Obstacles slow/hurt everyone (R2):** Task 16 (asteroids/lasers/mines reused).
- **Finish / fail flow:** Task 6 (finish/fail signals), Task 14 (restart), Task 15 (overlay).
- **Offline focus on AI movement/thinking (R8):** the entire Phase 3–4 FSM design.

## Execution handoff

Plan complete and saved to
`docs/superpowers/plans/2026-06-01-assault-race-mode-rebuild.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks,
   fast iteration.
2. **Inline Execution** — execute tasks in this session with checkpoints for review.

Which approach? (And confirm the locked decisions at the top — especially #2 player feel and #5
delete-and-rebuild — before Task 1 deletes the old race code.)
