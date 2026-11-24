class_name SpaceFortress
extends BaseEnemy

## The Space Fortress (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.5; Phase 11 t5, task plan docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md): the
## 360 degree boss that replaces level 1's station. A ring hull r 176 with nine parts, fought by circling it. A `FortressBrain` decides and an `EnemyMover`
## moves it through `BaseEnemy`'s shared tick (t6 builds the movement, t7 the batteries, t16 the geometry weapons, t8 the bays, t9 the art).
##
## THE HULL IS ARMOUR (the Carrier's rule). `deflects_hit()` / `is_armored()` answer true always, so every player projectile crossing the hull overlaps it
## without being consumed and reaches whichever part lies on its path; `_on_received_damage` refuses every hit (white flash, `armor_deflected`). Root body
## layer 0 / mask 0: it blocks nothing, the player's mining laser included.
##
## THE PARTS (`Modules`, coordinated by `ModularHull`; local bearing 0 degrees = +x, 90 = +y): five WEAPON batteries on the ring (spread 45, pulse 135,
## artillery 225, missiles 315, sweep 0 degrees), the HANGAR at 180 degrees (locked; its doors open it, t8), two WEAK_POINT shield generators north and
## south (locked until `shields_exposed`) and the CORE (locked until `core_exposed`). THE CORE'S DEATH IS THE FORTRESS'S: it sets the hull `Health` to 0.
##
## SECTOR SHIELDS (`ShieldSector`, t15): `shield_north` keeps a bubble on the artillery, missile and hangar parts, `shield_south` on the spread, pulse and
## sweep batteries, until the generator dies (the sector is then bare for good). A locked part's bubble absorbs nothing (the hangar's only while open).
##
## THE PHASE LADDER is data: four `BossPhase`s on `PhaseDriver` (batteries -> shields_exposed at 2 batteries lost -> core_exposed at both generators ->
## critical at core <= 40 %). `_on_phase_entered` applies the consequences (vulnerability and visuals here; the brain's `on_boss_phase()` the rest), and
## `phase_snapshot()` shows them (IDEAS §25 as a gate: built only from phase-driven state, never from which parts are alive).
##
## DEATH (the station's order): `died`, a harmless corpse, `suspend_ai()`, every mount powered down, the brain silenced, every escort scuttled,
## `death_started` (the `BossDeathSequence`), then `death_duration` later the escort container and the hull are freed.
##
## EMP: every source's window is `emp_factor` of its own (Ph11 owner choice 6). It keeps answering EMP while dying, with `apply_emp` a no-op then, so an EMP
## Blast never process-disables the wreck and stalls its death.
##
## Never call it a "station": Open Space has "Fortuna Space Station". Spawn with `b.space_fortress()`. Gated by `tests/integration/test_space_fortress.gd`.

## Every hit the armoured hull refused, with its damage.
signal armor_deflected(damage: int)
## Once, the instant the core dies, after `died`: what `BossDeathSequence` listens to.
signal death_started

@export var config: SpaceFortressConfig = load("res://assault/scenes/enemies/space_fortress/space_fortress_config.tres")
## A wave spawn lands at a camera-relative point; this removes the camera's pan from x once in `_ready()` (the Carrier's rule).
@export var world_anchored_x: bool = true
## A generator's opened shutter, shown from `shields_exposed` (`generator_open.png`; the part's `intact_texture` is the closed shutter).
@export var shutter_open_texture: Texture2D
## The core's opened plating, shown from `core_exposed` (`core_open.png`; the part's `intact_texture` is the plated core).
@export var core_open_texture: Texture2D
## The hangar with its doors open (`hangar_open.png`), shown while its bay's doors are opening or open (`BossReinforcements.door_changed`); the
## part's `intact_texture` is the closed hangar and `wreck_texture` the wreck, so this is the third door state. Null: the hangar never changes.
@export var hangar_open_texture: Texture2D

const BATTERY_SPREAD := &"battery_spread"
const BATTERY_PULSE := &"battery_pulse"
const BATTERY_SWEEP := &"battery_sweep"
const BATTERY_ARTILLERY := &"battery_artillery"
const BATTERY_MISSILES := &"battery_missiles"
const HANGAR := &"hangar"
const SHIELD_NORTH := &"shield_north"
const SHIELD_SOUTH := &"shield_south"
const CORE := &"core"
const NORTH_SECTOR: Array[StringName] = [BATTERY_ARTILLERY, BATTERY_MISSILES, HANGAR]
const SOUTH_SECTOR: Array[StringName] = [BATTERY_SPREAD, BATTERY_PULSE, BATTERY_SWEEP]
## Boss phase ids, in ladder order.
const PHASE_BATTERIES := &"batteries"
const PHASE_SHIELDS_EXPOSED := &"shields_exposed"
const PHASE_CORE_EXPOSED := &"core_exposed"
const PHASE_CRITICAL := &"critical"
## `HullBeams/Spoke0..3`.
const SPOKE_COUNT := 4
## A rocket arms this far beyond the hull circle (px), so it never hits its own hull.
const ROCKET_CLEARANCE := 8.0
## Core light modes (the `phase_snapshot()` visuals key).
const CORE_LIGHT_OFF := &"off"
const CORE_LIGHT_BLINK := &"blink"
## The core ring's round (plan §2.7.4): the shared enemy bullet; its life sizes `CoreRingPool`.
const CORE_RING_ROUND: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

## Seconds the wreck stays in the tree after the core's death, copied from `config.death_sequence_duration`. Public: the override point (a test
## shortens it after `_ready()`, the station's rule). 0 frees in the same call, like `BaseEnemy`.
var death_duration: float = 0.0

var _owner_group: StringName = &""
var _assault: bool = false
var _dying: bool = false
var _death_timer: Timer
var _north: ShieldSector
var _south: ShieldSector
var _reinforcements: BossReinforcements
## Phase-driven visual state (what `_on_phase_entered` set): read by `phase_snapshot()`, never the live sprites or lights.
var _shutters_open: bool = false
var _core_plating_open: bool = false
var _generator_light: int = StateLight.State.SHIELDED
var _core_light_mode: StringName = CORE_LIGHT_OFF
var _blink_left: float = 0.0
var _blink_lit: bool = false
## The intact generator / core textures, so the snapshot can name the closed state.
var _shutter_closed_texture: Texture2D
var _core_plated_texture: Texture2D
var _core_ring_pool: BulletPool

@onready var _fortress_brain: FortressBrain = $Brain
@onready var _hull: ModularHull = $ModularHull
@onready var _driver: BossPhaseDriver = $PhaseDriver
@onready var _thrusters: CanvasItem = $Thrusters
@onready var _critical_overlay: CanvasItem = $CriticalOverlay


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	_owner_group = StringName("fortress_%d" % get_instance_id())
	add_to_group(_owner_group)
	if config:
		_apply_config(config)
	var tree := get_tree()
	_assault = EnemyWorld.arena(tree) != null
	if world_anchored_x and EnemyWorld.has_view_rect(tree) and EnemyWorld.has_projectile_world_rect(tree):
		global_position.x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x

	# A Timer NODE (freed with the hull), never a SceneTreeTimer awaited across the hull's own free (tests/README.md, the leak trap).
	_death_timer = Timer.new()
	_death_timer.one_shot = true
	_death_timer.timeout.connect(_finish_death)
	add_child(_death_timer)

	var generator := part(SHIELD_NORTH)
	_shutter_closed_texture = generator.intact_texture if generator != null else null
	var core := part(CORE)
	_core_plated_texture = core.intact_texture if core != null else null
	_north = ShieldSector.new(part(SHIELD_NORTH), _parts(NORTH_SECTOR), _shield_params())
	_south = ShieldSector.new(part(SHIELD_SOUTH), _parts(SOUTH_SECTOR), _shield_params())

	var cfg := config if config != null else SpaceFortressConfig.new()
	_reinforcements = BossReinforcements.new(self, _hull, _driver, _fortress_brain.rng, _owner_group,
			cfg.escort_cap_assault if _assault else cfg.escort_cap_open_space, cfg.escort_boost_speed, cfg.escort_boost_seconds)
	_reinforcements.door_changed.connect(_on_door_changed)
	_fortress_brain.config = cfg
	_fortress_brain.bind(_hull, _reinforcements)
	## The five batteries' mounts (t7): one gate, one running pool index; pools are root children, so rounds land in the fortress's parent container.
	_hull.build_mounts(self, _fortress_brain.rng, _owner_group, _fortress_brain.attack_gate, 0)
	## The geometry weapons (t16): the core ring's pool is built here in code (a scene-authored pool would fill itself in its own `_ready()`, before this
	## one could size it), a direct root child, so its container is the fortress's parent.
	_core_ring_pool = BulletPool.new()
	_core_ring_pool.name = "CoreRingPool"
	_core_ring_pool.bullet_scene = CORE_RING_ROUND
	_core_ring_pool.pool_size = core_ring_pool_size(cfg)
	add_child(_core_ring_pool)
	_fortress_brain.bind_geometry(self, spoke_beams(), pulse_ring(), _core_ring_pool, _owner_group)

	if core != null:
		core.destroyed.connect(_on_core_destroyed)
	_driver.phase_entered.connect(_on_phase_entered)
	_driver.bind(_hull, health)
	set_process(false)


func _apply_config(cfg: SpaceFortressConfig) -> void:
	# The parts wrote their `Health` from their own exports in their `_ready()`, which ran first: the config is written on both (the station rule).
	for p in modular_hull().modules():
		match p.role:
			EnemyModule.Role.WEAPON: _set_part_health(p, cfg.battery_health)
			EnemyModule.Role.HANGAR: _set_part_health(p, cfg.hangar_health)
			EnemyModule.Role.WEAK_POINT: _set_part_health(p, cfg.shield_node_health)
			EnemyModule.Role.CORE: _set_part_health(p, cfg.core_health)
	health.max_health = cfg.core_health
	health.current_health = cfg.core_health
	score_value = cfg.score_value
	death_duration = cfg.death_sequence_duration
	## The scene-authored ContactHitBox never reads the config; pinned for the whole roster by test_enemy_contact_damage.gd.
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage


func _set_part_health(p: EnemyModule, hp: int) -> void:
	p.max_health = hp
	if p.health != null:
		p.health.max_health = hp
		p.health.current_health = hp


func _shield_params() -> Dictionary:
	if config == null:
		return {}
	return {
		"capacity": config.sector_shield_capacity,
		"regen_delay": config.sector_shield_regen_delay,
		"regen_seconds": config.sector_shield_regen_seconds,
		"reboot_seconds": config.sector_shield_reboot_seconds,
		"radius_pad": config.sector_shield_pad,
	}


# ── Queries ──────────────────────────────────────────────────────────────────────────────────────

## The parts' coordinator.
func modular_hull() -> ModularHull:
	return _hull if _hull != null else get_node("ModularHull") as ModularHull


## The part with [param id], or null.
func part(id: StringName) -> EnemyModule:
	return modular_hull().module(id)


func phase_driver() -> BossPhaseDriver:
	return _driver if _driver != null else get_node("PhaseDriver") as BossPhaseDriver


## The north (artillery, missiles, hangar) and south (spread, pulse, sweep) shield sectors.
func north_sector() -> ShieldSector:
	return _north


func south_sector() -> ShieldSector:
	return _south


func reinforcements() -> BossReinforcements:
	return _reinforcements


## The group every fortress weapon and escort shares (an enemy beam never hurts its owner set).
func owner_group() -> StringName:
	return _owner_group


## True in Assault (an arena exists when the fortress readied).
func is_assault() -> bool:
	return _assault


## The hull circle's radius (px).
func hull_radius() -> float:
	var shape := ($CollisionShape2D as CollisionShape2D).shape as CircleShape2D
	return shape.radius if shape != null else 0.0


## True from the instant the core dies until the wreck is freed.
func is_dying() -> bool:
	return _dying


## The four hull spokes' beams (`HullBeams/Spoke0..3/Beam`), in spoke order: Spoke0 local 270 degrees, Spoke1 90, Spoke2 0, Spoke3 180.
func spoke_beams() -> Array[EnemyBeam]:
	var out: Array[EnemyBeam] = []
	for i in SPOKE_COUNT:
		var beam := get_node_or_null("HullBeams/Spoke%d/Beam" % i) as EnemyBeam
		if beam != null:
			out.append(beam)
	return out


## The arena-control ring pulse.
func pulse_ring() -> EnergyRing:
	return get_node_or_null(^"PulseRing") as EnergyRing


## The core bullet ring's pool (built in `_ready()`).
func core_ring_pool() -> BulletPool:
	return _core_ring_pool


## The core ring's pool size for [param cfg]: `EnemyRounds.pool_size_for(core_ring_count, life, core_ring_period)`, `life` = min(the round's `max_time`,
## `max_distance` / `core_ring_speed`) read from the round scene's own `ProjectileLifetime` (72 at the shipped values; a fixed 48 would run dry).
static func core_ring_pool_size(cfg: SpaceFortressConfig) -> int:
	var max_time := float(EnemyBeamScenes.export_of_scene(CORE_RING_ROUND, &"max_time", 18.0, ^"ProjectileLifetime"))
	var max_distance := float(EnemyBeamScenes.export_of_scene(CORE_RING_ROUND, &"max_distance", 2400.0, ^"ProjectileLifetime"))
	var life := minf(max_time, max_distance / cfg.core_ring_speed) if cfg.core_ring_speed > 0.0 else max_time
	return EnemyRounds.pool_size_for(cfg.core_ring_count, life, cfg.core_ring_period)


## `BaseEnemy`'s one AI tick, then, while the brain is not ticked (an EMP window or the death sequence), a cancelled spoke or ring is ticked through its
## FADE to OFF (it would otherwise stay drawn: nothing else ticks it; no `Timer`).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_ai_suspended() or is_emp_disrupted():
		_fortress_brain.tick_fades(delta)


# ── The phase ladder ─────────────────────────────────────────────────────────────────────────────

## The consequences of each boss phase this task owns (vulnerability, visuals); the brain adds movement, attacks, arena and reinforcements.
## Unlocks are deferred: the triggering kill usually lands inside a physics flush.
func _on_phase_entered(_index: int, phase_id: StringName) -> void:
	# A part killed during the death sequence may still step the ladder; a wreck takes no new consequence.
	if _dying:
		return
	match phase_id:
		PHASE_SHIELDS_EXPOSED:
			for id in [SHIELD_NORTH, SHIELD_SOUTH]:
				var generator := part(id)
				if generator != null:
					generator.call_deferred(&"set_vulnerable", true)
			_shutters_open = true
			_open_shutters.call_deferred()
		PHASE_CORE_EXPOSED:
			var core := part(CORE)
			if core != null:
				core.call_deferred(&"set_vulnerable", true)
			_core_plating_open = true
			_open_core_plating.call_deferred()
			_thrusters.visible = true
		PHASE_CRITICAL:
			_critical_overlay.visible = true
			_core_light_mode = CORE_LIGHT_BLINK
			_blink_left = 0.0
			_blink_lit = false
			set_process(true)
	_fortress_brain.on_boss_phase(phase_id)


## The generators' shutters open (never over a wreck).
func _open_shutters() -> void:
	if shutter_open_texture == null:
		return
	for id in [SHIELD_NORTH, SHIELD_SOUTH]:
		var generator := part(id)
		if generator != null and not generator.is_destroyed() and generator.sprite != null:
			generator.sprite.texture = shutter_open_texture


## The core's plating opens (never over a wreck: the Carrier's R2-4 rule).
func _open_core_plating() -> void:
	var core := part(CORE)
	if core == null or core.is_destroyed() or core.sprite == null or core_open_texture == null:
		return
	core.sprite.texture = core_open_texture


## The hangar's doors (t9 art): the open art while its own bay's doors are opening or open, the closed art once they shut, never over a wreck.
## The generators' bays report through the same signal and change nothing here.
func _on_door_changed(bay_id: StringName, open: bool) -> void:
	var hangar := part(HANGAR)
	if hangar_open_texture == null or hangar == null or hangar.is_destroyed() or hangar.sprite == null:
		return
	var bay := hangar.get_node_or_null(^"Bay") as ReinforcementBay
	if bay == null or bay.bay_id != bay_id:
		return
	hangar.sprite.texture = hangar_open_texture if open else hangar.intact_texture


## The core light blink in `critical` (COMMIT / OFF every `core_blink_period`): `StateLight` has no COMMIT blink.
func _process(delta: float) -> void:
	var core := part(CORE)
	if _dying or _core_light_mode != CORE_LIGHT_BLINK or core == null or core.is_destroyed():
		set_process(false)
		return
	var light := core.get_node_or_null(^"Light") as StateLight
	if light == null:
		return
	_blink_left -= delta
	if _blink_left > 1e-6:
		return
	_blink_left += config.core_blink_period if config != null else 0.25
	_blink_left = maxf(_blink_left, 0.0)
	_blink_lit = not _blink_lit
	light.set_state(StateLight.State.COMMIT if _blink_lit else StateLight.State.OFF)


## IDEAS §25 as a gate: six keys, each built ONLY from phase-driven state (what `_on_phase_entered` and the brain's per-phase settings set), never from
## which parts are alive, so the hit that triggers a phase can never count as one of its changes. `movement` / `attacks` / `arena` are the brain's
## (t6; t7 and t16; t16; t8), `reinforcements` is `[activated bay ids, surge queued]`. `vulnerable` lists every part whose
## `is_vulnerable()` is true (a wreck keeps its flag), the hangar excluded (its doors, not the phase, decide). `visuals` reads the fields the phase
## handler set (shutters, plating, the generator light the fortress keeps, the core light MODE, thrusters, overlay), never a live light or a wreck
## texture: a wreck turns its own light off and a blinking light alternates.
func phase_snapshot() -> Dictionary:
	var vulnerable: Array[StringName] = []
	for p in modular_hull().modules():
		if p.module_id != HANGAR and p.is_vulnerable():
			vulnerable.append(p.module_id)
	vulnerable.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var shutter := shutter_open_texture if _shutters_open else _shutter_closed_texture
	var plating := core_open_texture if _core_plating_open else _core_plated_texture
	return {
		&"movement": _fortress_brain.movement_snapshot(),
		&"attacks": _fortress_brain.attacks_snapshot(),
		&"vulnerable": vulnerable,
		&"arena": _fortress_brain.arena_snapshot(),
		&"reinforcements": _fortress_brain.reinforcements_snapshot(),
		&"visuals": [
			shutter.resource_path if shutter != null else "",
			plating.resource_path if plating != null else "",
			_generator_light,
			_core_light_mode,
			_thrusters.visible,
			_critical_overlay.visible,
		],
	}


# ── Damage, death and EMP ────────────────────────────────────────────────────────────────────────

## Armour: every hit is refused with a flash; the hull `Health` moves only when the core dies. A dying hull neither flashes nor reports.
func _on_received_damage(damage: int) -> void:
	if _dying:
		return
	armor_deflected.emit(damage)
	hit_flash_player.play("hit")


func _on_core_destroyed(_part: EnemyModule) -> void:
	if health.current_health > 0:
		health.set_health(0)


## The station's death order, latched once (`Health` re-emits on every later hit): `died` and the kill score at the moment of death, a harmless
## corpse, the AI suspended, every gun silent, every escort scuttled, then `death_started` and the timer that frees the wreck.
func _on_health_changed(current: int) -> void:
	if current > 0:
		super._on_health_changed(current)
		return
	if _dying:
		return
	_dying = true
	if OS.is_stdout_verbose():
		print("[Enemy] %s DESTROYED (death sequence, %.2f s) at position %.0f, %.0f" % [name, death_duration, global_position.x, global_position.y])
	was_killed = true
	died.emit()
	_make_corpse_harmless()
	suspend_ai()
	for p in modular_hull().modules():
		for mount in p.mounts():
			if is_instance_valid(mount):
				mount.power_down()
	_fortress_brain.silence()
	if _reinforcements != null:
		_reinforcements.scuttle_all()
	set_process(false)
	death_started.emit()
	if death_duration <= 0.0:
		_finish_death()
	else:
		_death_timer.start(death_duration)


## From this instant the wreck cannot damage the player by any physics route (deferred: a kill lands inside a physics flush).
func _make_corpse_harmless() -> void:
	hurt_box.set_deferred(&"monitoring", false)
	if contact_hit_box:
		contact_hit_box.set_deferred(&"collision_layer", 0)


## The end of the sequence: one final blast, the escort container, then the hull. Owned here, never by `BossDeathSequence` (the station's rule: a
## renamed spectacle node must not hang the section).
func _finish_death() -> void:
	_explosion_effect.explode()
	var escorts := EscortContainer.of(self)
	if escorts != null:
		escorts.queue_free()
	queue_free()


## True while alive (a brain and a mover) and WHILE DYING: an EMP Blast that found it unanswering would process-disable the wreck and freeze its death.
func answers_emp() -> bool:
	return _dying or super.answers_emp()


## Every source's window is scaled by `emp_factor` (Ph11 owner choice 6); a no-op while dying.
func apply_emp(seconds: float, source: Node) -> void:
	if _dying:
		return
	super.apply_emp(seconds * (config.emp_factor if config != null else 1.0), source)


# ── Duck-typed answers ───────────────────────────────────────────────────────────────────────────

## Where a player homing rocket coming from [param from] steers: the nearest live vulnerable part's `homing_point()`, else the core's centre.
func homing_point(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for p in modular_hull().modules():
		if p.is_destroyed() or not p.is_vulnerable():
			continue
		var at := p.homing_point()
		var d := from.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = at
	if best != Vector2.INF:
		return best
	var core := part(CORE)
	return core.homing_point() if core != null else global_position


## The hull is armour: no player projectile is ever consumed by it (it flies on to the parts).
func deflects_hit(_hit_box: HitBox) -> bool:
	return true


func is_armored() -> bool:
	return true


## The player's mining beam passes over the hull and burns the parts it crosses.
func is_laser_blocking() -> bool:
	return false


func can_be_repaired() -> bool:
	return false


## Duck-typed, read by `SupportShipBrain.is_candidate()`: a shield on an armoured hull would never absorb.
func accepts_ward() -> bool:
	return false


## Duck-typed launcher question (a rocket mount, t7): the hull's own velocity (the mover's).
func launch_velocity() -> Vector2:
	return velocity


## Duck-typed launcher question: the hull radius + 8, so a rocket arms only once clear of the whole ring.
func rocket_clear_radius() -> float:
	return hull_radius() + ROCKET_CLEARANCE


func _parts(ids: Array[StringName]) -> Array[EnemyModule]:
	var out: Array[EnemyModule] = []
	for id in ids:
		var p := part(id)
		if p != null:
			out.append(p)
	return out
