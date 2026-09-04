## SpaceStation — the Level 1 space-station mini-boss (EPIC sub-item 1: the entity only).
##
## Four turrets, each on its own HP bar, mounted on a 256x256 hull. The core refuses ALL damage
## while any turret is alive, then becomes damageable when the last one dies.
##
## The armour refuses damage inside `_on_received_damage` rather than by disabling the HurtBox,
## because two shipped systems drive damage straight into the signal with no physics involved —
## `plasma_nova_module.gd:41` and `beam_behavior.gd:151` both do
## `get_node_or_null("HurtBox").received_damage.emit(...)` over group "enemies". A disabled
## hurtbox would leak both of them. Keeping it live also means the hit still registers visually,
## which is what teaches the player to shoot the guns first.
##
## Extends BaseEnemy like all nine other enemies (BaseEnemy itself composes from
## global/components/), which gives the HurtBox->Health wiring, hit flash, HitEffect,
## ExplosionEffect, the contact HitBox, `died`, and score_value propagation for free. Refusing
## damage via a `_on_received_damage` override is a shipped pattern — see ram_ship.gd:27.
class_name SpaceStation
extends BaseEnemy

## Emitted when the armoured core absorbs a hit. Feedback hook (sfx/sparks) and the observable
## that proves the core is armoured rather than merely unhittable.
signal armor_deflected(damage: int)

## Emitted exactly once, the moment the last turret dies and the core stops being armoured.
## The phase-transition hook: `StationLaserPhase` starts the laser phase on it, and sub-item 4's
## escalating fire will hang off the same signal rather than a second fan-out over the turrets.
##
## Station-level rather than per-turret because the station owns the armour rule
## (`is_armored()` / `live_turret_count()`), so the *transition* is station-level knowledge.
##
## Zero arguments, deliberately — and declared that way, so a zero-arg handler is correct.
## Every signal in this project must be declared with exactly what it emits; see the arity
## rule in `tests/README.md`.
signal armor_broken

## Emitted the instant HP reaches 0, together with `died` and before the wreck is freed. What
## `StationDeathSequence` listens to. Zero arguments, same rule as `armor_broken` above.
##
## Separate from `died` because the two mean different things to different listeners: `died` is
## "stop doing things" (the laser phase, the gunnery and the reinforcements all shut down on it)
## and `death_started` is "begin the spectacle". Keeping them apart means the sequence node can be
## deleted without touching anything the level's progression depends on.
signal death_started

@export var config: SpaceStationConfig = load("res://assault/scenes/enemies/space_station/space_station_config.tres")

## Seconds the wreck stays in the tree after HP reaches 0. Copied from
## `config.death_sequence_duration` in `_ready()` and never read back through the resource — the
## `.tres` is a single process-wide cached instance, so a runtime read would be a read of mutable
## global state shared with every other station and every test in the process.
##
## PUBLIC, and that is the supported override point: a test shortens the sequence by writing
## `station.death_duration = 0.05` AFTER `_ready()`, exactly as `test_station_laser_phase.gd` and
## `test_station_gunnery.gd` override their nodes' copied timings. Never write to `station.config`.
##
## 0.0 means "free in the same frame", i.e. precisely what BaseEnemy has always done — so a
## station with no config keeps the old behaviour rather than hanging in the container.
var death_duration: float = 0.0

## Latches on the frame HP first reaches 0, so the death path runs exactly once.
##
## Required, not defensive: `health_component.gd:51-53` emits `amount_changed` UNCONDITIONALLY,
## so any damage landing on an already-dead station re-enters `_on_health_changed` with
## `current == 0`. Without this latch a stray bullet mid-sequence would re-emit `died` (scoring
## the boss twice) and restart the death timer. `station_turret.gd:63-66` documents the same trap.
var _dying: bool = false

## A Timer NODE, deliberately not `get_tree().create_timer()`. A SceneTreeTimer awaited across
## this station's own destruction is the leak `tests/README.md` documents, where the gate stays
## green while `ObjectDB instances leaked` prints at exit. A Timer child is freed with its owner.
var _death_timer: Timer

@onready var turret_root: Node2D = $Turrets

## Latches true when `armor_broken` fires, so it fires exactly once.
##
## Its job is idempotence against re-entry through `destroyed` itself — a re-emit from a future
## caller, or a repairable/respawning turret driving the live count 0 -> 1 -> 0. It is NOT about
## the `Health` 0 -> 0 re-emit trap: `StationTurret._on_received_damage` already returns early
## when `not _alive`, so damage aimed at a dead turret never reaches `Health` at all.
var _armor_broken: bool = false


func _ready() -> void:
	super._ready()
	## Consumed by player targeting and AoE: ai_targeting_module.gd:49, plasma_nova_module.gd:34,
	## emp_blast_module.gd:39, warhead_missile_shooting_state.gd:61, beam_behavior.gd:75.
	## NOT what drives LevelSection.ENEMIES_CLEARED — level_director.gd:106 polls
	## wave_manager.enemy_container's child count instead.
	add_to_group("enemies")

	## Same child-before-parent ordering the config block below relies on: every turret has
	## already run its own _ready(), so `destroyed` is safe to connect here.
	for t in _turrets():
		t.destroyed.connect(_on_turret_destroyed)

	## One-shot: started in _on_health_changed, fires once, frees the wreck. Built here rather
	## than authored in the scene so a station instantiated from bare script still has it.
	_death_timer = Timer.new()
	_death_timer.one_shot = true
	_death_timer.timeout.connect(_finish_death)
	add_child(_death_timer)

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		death_duration = config.death_sequence_duration

		## Godot readies children before parents, so every turret's Health already exists and has
		## run its own _ready() (which only clamps). Same ordering gunship.gd:36-37 relies on.
		for t in _turrets():
			t.health.max_health = config.turret_health
			t.health.current_health = config.turret_health

		## BaseEnemy._add_contact_hitbox() hardcodes damage = 20 and never reads the config
		## (base_enemy.gd:56), so it has to be re-applied here. bomber.gd:18-26,
		## light_assault_ship.gd:23, ram_ship.gd:20-23 and gunship.gd:44-51 all do this.
		## tests/integration/test_enemy_contact_damage.gd asserts it for the whole roster, so an
		## enemy that forgets the re-apply now fails the gate instead of silently ramming for 20.
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break


## Public read-only view of the turret list, for nodes that need the emitters themselves rather
## than just the count (`StationGunnery`). Data access, not behaviour: `live_turret_count()` is
## deliberately left untouched because `test_space_station.gd` pins it.
func turrets() -> Array[StationTurret]:
	return _turrets()


func _turrets() -> Array[StationTurret]:
	var out: Array[StationTurret] = []
	for child in turret_root.get_children():
		var t := child as StationTurret
		if t != null and is_instance_valid(t):
			out.append(t)
	return out


## Read live from the container on every call rather than cached in an array or tracked by a
## counter, so it cannot desync from reality and cannot double-decrement. Four children make the
## iteration free.
func live_turret_count() -> int:
	var n := 0
	for t in _turrets():
		if t.is_alive():
			n += 1
	return n


func is_armored() -> bool:
	return live_turret_count() > 0


## Takes the turret argument `StationTurret.destroyed` is declared and emitted with, so a
## one-arg handler is the correct shape.
func _on_turret_destroyed(_turret: StationTurret) -> void:
	if _armor_broken:
		return
	if live_turret_count() > 0:
		return
	_armor_broken = true
	armor_broken.emit()


## Override: refuse damage to the core while any turret lives, but still register the hit.
func _on_received_damage(damage: int) -> void:
	if is_armored():
		armor_deflected.emit(damage)
		hit_flash_player.play("hit")
		return
	super._on_received_damage(damage)


## True from the frame HP reaches 0 until the wreck is freed.
func is_dying() -> bool:
	return _dying


## Override. BaseEnemy frees the actor in the SAME call that emits `died` (base_enemy.gd:65-73),
## which gives a 256x256 mini-boss the identical one-frame death a 40 px interceptor gets. A boss
## needs the wreck to stay in the tree long enough to explode.
##
## Everything BaseEnemy does AT the moment of death still happens at the moment of death — only
## `queue_free()` moves. That ordering is load-bearing for scoring: ScoreTracker connects its kill
## path to `died` (score_tracker.gd:151-164) and its escape path to `tree_exited`, discriminating
## on `was_killed` (:201). Deferring either would score the boss as an ESCAPE and multiply the
## combo by 0.75 (:211) — a silent scoring regression no test of the death sequence would catch.
##
## The `current > 0` branch keeps the hit flash and the HitEffect spark; the death branch drops
## both, deliberately. A corpse that still flashes white on every stray bullet reads as "still
## alive"; one that does not is the readable signal that the fight is over.
func _on_health_changed(current: int) -> void:
	if current > 0:
		super._on_health_changed(current)
		return

	if _dying:
		return

	_dying = true
	print("[Enemy] %s DESTROYED (death sequence, %.2f s) at position %.0f, %.0f" % [
		name, death_duration, global_position.x, global_position.y
	])
	was_killed = true
	died.emit()
	_make_corpse_harmless()
	death_started.emit()

	if death_duration <= 0.0:
		## No config, or explicitly zero: behave exactly as BaseEnemy always has.
		_finish_death()
	else:
		_death_timer.start(death_duration)


## From this instant the station cannot damage the player by any physics route.
##
## The `_dying` latch, NOT this, is the real guard against further DAMAGE TO the station:
## `plasma_nova_module.gd:41` and `beam_behavior.gd:151` emit `received_damage` directly on the
## HurtBox, bypassing `monitoring` entirely.
func _make_corpse_harmless() -> void:
	## Deferred: Godot forbids changing monitoring state during physics callback flushing.
	hurt_box.set_deferred("monitoring", false)

	## The contact HitBox is on layer 256 and the player's HurtBox is the side that MONITORS
	## (mask 1281), so zeroing the layer here is what stops a dead 256 px hull from ramming the
	## player. BaseEnemy._add_contact_hitbox() builds it as a direct child (base_enemy.gd:49-60).
	for child in get_children():
		if child is HitBox:
			(child as HitBox).set_deferred("collision_layer", 0)
			break


## The end of the sequence: one final central blast, then the wreck leaves the container — which
## is what lets LevelSection.ENEMIES_CLEARED advance (level_director.gd:116 polls the container's
## child count, so a lingering wreck holds the section open for free).
##
## Owned by the STATION rather than by StationDeathSequence on purpose. If the visual node called
## queue_free(), a station whose sequence node was renamed or removed would never leave the
## container and `station_assault` would hang for its full 180 s timeout with no error at all.
func _finish_death() -> void:
	_explosion_effect.explode()
	queue_free()
