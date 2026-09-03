## StationReinforcements — the SpaceStation calls for help (EPIC sub-item 4b).
##
## Before this, the mini-boss was a duel in a vacuum: the player picked a comfortable spot below
## the hull, streamed into one turret at a time, and only the station's own cadence ever asked
## them to move. Now, **while the turrets are still up**, small squads of existing enemy ships
## cross in from the left, the right, below and above on a fixed, learnable rhythm. The safe spot
## for dodging turret fans is not the safe spot when an interceptor is strafing through it.
##
## A child node of `space_station.tscn` rather than methods on `space_station.gd`, per `CLAUDE.md`'s
## composition rule and modelled on its siblings `StationLaserPhase` and `StationGunnery`.
## `SpaceStation` gains nothing — no new methods, no new signals.
##
## Plan, both review rounds and the measurements behind the numbers:
## `docs/plans/station-reinforcements/`.
##
## ── Phase 1 only, and that is the whole design ───────────────────────────────────────────────
##
## Reinforcements stop on `armor_broken`. Research finding 1 (the Flunky-Boss critique) is that
## *constant* spawns are how a boss ends up overshadowed by its own minions, whereas bosses that
## summon only during specific phases do not. Phase 2 here is already the station's own show:
## `StationLaserPhase` beams every 6.5 s over `StationGunnery` rings every 2.0 s against a
## 48-bullet pool. A third source there would fight both for the player's attention and for screen
## space.
##
## It also disposes of a lifecycle hazard for free. `LevelSection.ENEMIES_CLEARED` polls the enemy
## container's child count (`level_director.gd:116`), so a reinforcement still alive after the boss
## dies holds the section open. Stopping at `armor_broken` means the calls end *before* the core is
## even damageable, and `_stop()` on `died` closes the remaining gap.
##
## ── Ships are SIBLINGS of the station, never children of it ──────────────────────────────────
##
## `_container()` is `_station.get_parent()`, which in the level is `WaveManager.enemy_container`
## (`level_1.tscn:22-26`, a bare Node2D with an identity transform). Parenting a reinforcement
## under the station would drag it around the arena, because `station_laser_phase.gd:123` writes
## `_station.rotation` during phase 2 — and a reinforcement `interceptor` or `fighter` builds its
## own `BulletPool`, whose container is the hardcoded `get_parent().get_parent()`
## (`bullet_pool.gd:47`), so its bullet field would swing with the hull too.
##
## ── Design units in, world units out ─────────────────────────────────────────────────────────
##
## The squad table is authored in 640x360 design space and multiplied by `ArenaCamera.WORLD_SCALE`
## exactly once, at spawn — the same contract as `wave_manager.gd:172`. Speeds are left UNSCALED
## because `EnemyPathMover` applies the scale itself (`enemy_path_mover.gd:77`); pre-multiplying
## either would double it.
##
## ── The timer split is load-bearing for the tests ────────────────────────────────────────────
##
## The `Timer` is `one_shot` and is restarted ONLY from `_on_timer_timeout()`. `spawn_next_squad()`
## touches no timer at all, so a test can force squads after a `_stop()` or against the cap without
## silently re-arming the timer it just asserted stopped.
class_name StationReinforcements
extends Node2D

## Which edge a squad comes from. The order of this enum IS the cycle order: consecutive squads
## come from opposite sides (the Toaplan alternation rule, research finding 3), so the player is
## pulled across the screen rather than nudged. Fixed, never `randf()` — the laser phase already
## established that random attack ordering cannot be balanced or tested.
enum Edge { LEFT, RIGHT, BOTTOM, TOP }

## Seconds a reinforcement lives before `EnemyPathMover` culls it, on every entry.
##
## `FREE_ON_DURATION`, not `FREE_ON_SCREEN_EXIT`: the latter only culls a ship that has been on
## screen at least once (`enemy_path_mover.gd:110-114`), so a ship spawned off screen that never
## quite arrives would live forever and hold `ENEMIES_CLEARED` open. The longest actual transit is
## the side run at ~4.0 s, so 7.0 is margin rather than a cut-off.
##
## Scene/level geometry, not a stat — which is why it is here and not in `SpaceStationConfig`, the
## same split `StationLaserPhase.emitter_radius` and the two gunnery `spawn_radius` values use.
@export var reinforcement_lifetime: float = 7.0

## ── Tuning, copied from SpaceStationConfig in _ready() ────────────────────────
##
## Copied rather than read through `_station.config` per squad, because that resource is a SINGLE
## PROCESS-WIDE INSTANCE (`space_station.gd:36` `load()`s it and ResourceLoader caches), shared by
## every station in the process and by every test that preloads the `.tres`.
##
## The defaults below are the CONSERVATIVE FALLBACK for a station with no config at all: a long
## opening, a slow cadence and a tight cap. They are intentionally different from the shipped
## `.tres` values (8 / 10 / 4), which is what stops the config test passing vacuously.
var reinforcement_first_delay: float = 20.0
var reinforcement_interval: float = 30.0
var reinforcement_max_alive: int = 2

var _station: SpaceStation = null
var _timer: Timer = null
var _stopped: bool = false

## The squad table, built once in `_ready()`. `Array[Array]` of `Array[SpawnEntryResource]`.
var _squads: Array = []

## Index into `_squads` for the NEXT squad. Wraps, so the cycle repeats.
var _next_squad: int = 0

## Ships this node has spawned that may still be alive. Pruned with `is_instance_valid` on every
## squad — without the prune the cap jams permanently once four ships have been culled.
var _alive: Array[Node] = []


func _ready() -> void:
	_station = get_parent() as SpaceStation
	if _station == null:
		## A plain Node2D dropped in the wrong place must not crash.
		push_warning("StationReinforcements has no SpaceStation parent; disabling.")
		return

	## Godot readies children before parents, so this runs BEFORE SpaceStation._ready(). Safe for
	## `config`, which is an @export initialised at property-init time (the same reasoning
	## `station_gunnery.gd:101-104` documents). NOT safe for anything the station derives in its
	## own _ready() — nothing here touches `turret_root`.
	var cfg := _station.config
	if cfg != null:
		reinforcement_first_delay = cfg.reinforcement_first_delay
		reinforcement_interval = cfg.reinforcement_interval
		reinforcement_max_alive = cfg.reinforcement_max_alive

	_squads = _build_squads()

	_timer = Timer.new()
	## one_shot, and restarted only in _on_timer_timeout(). See the header.
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

	_station.armor_broken.connect(_stop)
	## Zero-argument signals, declared and emitted that way (`base_enemy.gd:4`,
	## `space_station.gd:34`), so zero-arg handlers are correct.
	_station.died.connect(_stop)

	if reinforcement_first_delay > 0.0:
		_timer.start(reinforcement_first_delay)


## The squad table. Public and read-only in practice, so tests can assert the geometry without
## spawning anything.
func squads() -> Array:
	return _squads


## Authored through `WaveBuilder`'s public API rather than by hand-filling `SpawnEntryResource`s,
## so squads read in the same vocabulary as `docs/enemy-roster.md` — `.at()`, `.move()`,
## `.free_after()`, `.shoot_forward()` — instead of a second one invented here.
##
## Offsets and speeds are DESIGN units. See the header.
func _build_squads() -> Array:
	var b := WaveBuilder.new()
	var out: Array = []

	## `StraightMovement.sample()` is `Vector2(sin(angle), cos(angle)) * speed * t`, i.e.
	## 0 = down, PI/2 = right, -PI/2 = left, PI = up (`straight_movement.gd:2,13`).

	## LEFT — two interceptors sweeping rightward through the vertical middle. Lanes at design
	## y = 20 / 80, never hugging the top or bottom border: research finding 3, "the edges of the
	## screen don't have lanes to prevent awkward traps".
	out.append(b.wave(0.0, [
		b.interceptor().at(-440.0, 20.0).move(b.straight(200.0, PI / 2.0)).free_after(reinforcement_lifetime),
		b.interceptor().at(-440.0, 80.0).move(b.straight(200.0, PI / 2.0)).free_after(reinforcement_lifetime),
	]).entries)

	## RIGHT — the mirror, so consecutive squads pull the player across the screen.
	out.append(b.wave(0.0, [
		b.interceptor().at(440.0, 20.0).move(b.straight(200.0, -PI / 2.0)).free_after(reinforcement_lifetime),
		b.interceptor().at(440.0, 80.0).move(b.straight(200.0, -PI / 2.0)).free_after(reinforcement_lifetime),
	]).entries)

	## BOTTOM — from behind the player, so deliberately the SLOWEST ships in the table (170 vs 200)
	## and the longest run-up: 580 world px is ~1.7 s of visible approach before they are a threat.
	## Research finding 5 says to spawn furthest from the player, which a fixed table cannot honour
	## literally; the speed and the run-up are the mitigation.
	out.append(b.wave(0.0, [
		b.drone().at(-100.0, 290.0).move(b.straight(170.0, PI)).free_after(reinforcement_lifetime),
		b.drone().at(100.0, 290.0).move(b.straight(170.0, PI)).free_after(reinforcement_lifetime),
	]).entries)

	## TOP — two fighters angling down-and-inward. They enter at design x = +/-250 rather than the
	## border, and the 0.5 rad inward angle keeps them clear of the 256 px hull: from (-250, -290)
	## a ship is at x = -175.7 when it reaches the hull's y = -154 and x = -105.8 at y = -26, a
	## closest approach of 41.8 design units against a 16-unit sprite half-extent.
	##
	## `.shoot_forward()` rather than aimed fire: `EnemyPathMover` writes
	## `rotation = atan2(-vel.x, vel.y)` each frame and `AimedAttackPattern` with
	## `aim_at_player = false` fires `Vector2.DOWN.rotated(ship.rotation)`, so the bullets travel
	## the squad's own diagonal. That reads as a strafing run and never tracks the player.
	##
	## NOT `ram_ship`, which would be the obvious "obstacle" choice: `ram_ship.gd:19` narrows its
	## HurtBox mask to 33, which excludes the player bullet's layer 64 (`bullet.tscn:44`), so a ram
	## ship cannot be hit by the primary weapon at all. Two indestructible obstacles per cycle is
	## not the popcorn role this table is for. `test_station_reinforcements.gd` guards the whole
	## class of mistake for the next person who swaps a ship in here.
	out.append(b.wave(0.0, [
		b.fighter().at(-250.0, -290.0).move(b.straight(170.0, 0.5)).shoot_forward().free_after(reinforcement_lifetime),
		b.fighter().at(250.0, -290.0).move(b.straight(170.0, -0.5)).shoot_forward().free_after(reinforcement_lifetime),
	]).entries)

	return out


## Spawn the next squad in the cycle. Public so tests drive squads without waiting out a real
## interval — and deliberately free of any timer handling, see the header.
##
## A squad is spawned WHOLE or not at all. Skipping it entirely when it would breach the cap is
## what makes `reinforcement_max_alive` mean exactly what it says: an "already at the cap?" check
## would let a 2-ship squad through at 3 alive and peak at 5. Half a squad also reads as a bug
## rather than as a cap.
func spawn_next_squad() -> void:
	if _stopped or _station == null or _squads.is_empty():
		return

	_prune_alive()

	var squad: Array = _squads[_next_squad]
	if _alive.size() + squad.size() > reinforcement_max_alive:
		## Skipped, but the cycle still advances: the next call comes from a different edge, so a
		## cap breach costs the player a squad rather than freezing the rotation on one side.
		_next_squad = (_next_squad + 1) % _squads.size()
		return

	for entry: SpawnEntryResource in squad:
		_spawn_entry(entry)

	_next_squad = (_next_squad + 1) % _squads.size()


## Modelled on `WaveManager._spawn_ship()` (`wave_manager.gd:159-205`). `Level1Director`'s
## `_spawn_bonus_drone()` (`level_1_director.gd:110-144`) is the shipped precedent for spawning
## OUTSIDE the wave registry, but it is not the model: it adds a raw world-px offset (`:125`)
## rather than scaling a design-unit one.
func _spawn_entry(entry: SpawnEntryResource) -> void:
	if entry == null or entry.ship_scene == null:
		return

	var entity := entry.ship_scene.instantiate() as Node2D
	if entity == null:
		return

	entity.global_position = _spawn_origin() + entry.base_offset * ArenaCamera.WORLD_SCALE

	## Applied BEFORE add_child so they are readable during _ready() — which is the whole point for
	## `aim_mode`, the property `.shoot_forward()` sets (`light_assault_ship.gd:33-36`).
	for key: String in entry.initial_props:
		entity.set(key, entry.initial_props[key])

	_container().add_child(entity)
	_alive.append(entity)

	## The registration channel for ad-hoc spawns, already used by `big_asteroid.gd:77` for shards.
	## `ScoreTracker` routes it to `_on_enemy_spawned(enemy, -1)` (`score_tracker.gd:74-75, 89-90`),
	## so a reinforcement kill pays out and never disturbs a wave-clear tally.
	##
	## It also opts these ships into the game's UNIVERSAL escape penalty: `score_tracker.gd:211`
	## multiplies the combo by 0.75 whenever an enemy leaves the tree unkilled, outside the
	## `if counts_in_wave:` block, so `wave_index == -1` does not exempt it. A squad the player
	## ignores therefore costs 0.75 twice. That is a deliberate balance decision, not an oversight
	## — adds are a combo *opportunity*, and the alternative (no emit) means killing one awards
	## nothing at all, which reads as a bug. `test_station_reinforcements.gd` pins the number.
	EventBus.enemy_spawned_orphan.emit(entity)

	if entry.movement is MovementResource:
		var mover := EnemyPathMover.new()
		mover.movement = entry.movement
		mover.exit_mode = entry.exit_mode
		mover.exit_time = entry.exit_time
		mover.look_in_moving_direction = entry.look_in_moving_direction
		mover.look_angle = entry.look_angle
		entity.add_child(mover)


## Where the station's siblings live. In the level this is `WaveManager.enemy_container`; in tests
## it is the harness container. Either way it is the node `LevelSection.ENEMIES_CLEARED` counts.
func _container() -> Node:
	return _station.get_parent()


## The camera's fixed centre, or the constant it is pinned to when there is no camera.
##
## The fallback is not a fudge: `arena_camera.gd:5-6` pins `global_position` at exactly (640, 360)
## and pans through `offset` only (`:8-12`), so the two agree. It exists so a cameraless test
## exercises the real positioning code instead of `WaveManager`'s return-early-with-no-camera path
## (`wave_manager.gd:160-162`).
func _spawn_origin() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		return cam.global_position
	return Vector2(ArenaCamera.SCREEN_W, ArenaCamera.SCREEN_H) * 0.5


## Without this the cap jams permanently: four culled ships would still count against it forever.
func _prune_alive() -> void:
	var live: Array[Node] = []
	for node in _alive:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			live.append(node)
	_alive = live


func _on_timer_timeout() -> void:
	spawn_next_squad()
	if _stopped:
		return
	if reinforcement_interval > 0.0:
		_timer.start(reinforcement_interval)


## Nothing this node drives may outlive phase 1. Ships already in flight are left alone — they are
## on a `FREE_ON_DURATION` mover and cull themselves within `reinforcement_lifetime`, well before
## the boss can die.
func _stop() -> void:
	_stopped = true
	if _timer != null:
		_timer.stop()
