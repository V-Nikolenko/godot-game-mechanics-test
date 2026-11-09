## INTENT tests for Phase 9 plan §2.8 / §2.9 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md; task plan
## docs/plans/cmw5k4yk100aeqs2xwrdu7hwz/3-plan.md): the Jamming Structure in its three variants (local, sector, pulsed).
##
## A static `BaseEnemy` (no brain, no mover) with a child `HazardField` (kind `jammer`, avoid weight 0, `disables_abilities`)
## whose radius, stabilisation and cycle come from its flat `JammingStructureConfig`. Inside a lit field the player's H
## abilities and K rockets are locked (the t1 lock), enemy ships fly as if it were empty, and seeking rockets fly straight;
## a Missile Corvette's Pursuit / Cluster roll at a player inside becomes Dumb (`test_missile_corvette.gd`). Its EMP answer
## switches the field off for the window and leaves the tower shootable (`HazardField.suppress`); the EMP Blast rows through
## the real H seam live in `test_emp_blast_module.gd`.
##
## Behaviour rows run in both harnesses; the lock row uses both real player scenes, hand-ticked at 1/60 (the shape of
## `test_player_ability_lock.gd`), with real bullets on real physics at the 8x clock. Jammers are hand-ticked: their root
## (the BaseEnemy EMP clock), `Field` and `AssaultDrift` have physics off and `_step()` drives them.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const LOCAL: PackedScene = preload("res://assault/scenes/enemies/jamming_structure/jamming_structure.tscn")
const SECTOR: PackedScene = preload("res://assault/scenes/enemies/sector_jammer/sector_jammer.tscn")
const PULSED: PackedScene = preload("res://assault/scenes/enemies/pulsed_jammer/pulsed_jammer.tscn")
const FIGHTER: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_PLAYER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const D := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const VARIANTS := ["local", "sector", "pulsed"]

## The epic plan §2.8 table.
const TABLE := {
	"local": {"scene": LOCAL, "config": "res://assault/scenes/enemies/jamming_structure/jamming_structure_config.tres",
		"hp": 140, "radius": 240.0, "stab": 0.75, "cycle": [0.0, 0.0, 0.0], "score": 60},
	"sector": {"scene": SECTOR, "config": "res://assault/scenes/enemies/sector_jammer/sector_jammer_config.tres",
		"hp": 260, "radius": 640.0, "stab": 1.25, "cycle": [0.0, 0.0, 0.0], "score": 120},
	"pulsed": {"scene": PULSED, "config": "res://assault/scenes/enemies/pulsed_jammer/pulsed_jammer_config.tres",
		"hp": 160, "radius": 300.0, "stab": 0.75, "cycle": [0.8, 3.0, 2.5], "score": 80},
}

const _SPEEDUP := 8
var _saved_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_steps: int = 8
var _scaled: bool = false
var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func after_each() -> void:
	if _scaled:
		_scaled = false
		Engine.time_scale = _saved_scale
		Engine.physics_ticks_per_second = _saved_ticks
		Engine.max_physics_steps_per_frame = _saved_steps


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func _scale_clock() -> void:
	_scaled = true
	_saved_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_steps = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_steps * _SPEEDUP
	Engine.time_scale = _saved_scale * _SPEEDUP


func _world(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = Vector2(640.0, 2000.0)  # far from every jammer unless a row moves it
	return h


## A jammer of [param scene] in [param parent] at [param at], hand-ticked (root, field, drift and the art / light clocks off).
func _jammer(parent: Node, scene: PackedScene = LOCAL, at: Vector2 = Vector2(640.0, 300.0)) -> JammingStructure:
	var j := scene.instantiate() as JammingStructure
	j.position = at
	parent.add_child(j)
	_freeze(j)
	return j


func _freeze(j: JammingStructure) -> void:
	j.set_physics_process(false)
	j.set_process(false)
	j.field().set_physics_process(false)
	(j.get_node("AssaultDrift") as AssaultDrift).set_physics_process(false)
	(j.get_node("Field/Art") as JammerFieldArt).set_process(false)


## One physics tick of the jammer: BaseEnemy's EMP clock, then the field (the engine's parent-first order), then the light.
func _step(j: JammingStructure, ticks: int = 1) -> void:
	for i in ticks:
		j._physics_process(D)
		j.field()._physics_process(D)
		j._update_light(D)


func _art(j: JammingStructure) -> JammerFieldArt:
	return j.get_node("Field/Art") as JammerFieldArt


func _light(j: JammingStructure) -> StateLight:
	return j.get_node("StateLight") as StateLight


## A real player alone in an autofreed box, physics off, at [param at].
func _player(mode: String, parent: Node, at: Vector2) -> PlayerBase:
	var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_PLAYER_SCENE).instantiate() as PlayerBase
	parent.add_child(p)
	p.set_physics_process(false)
	p.global_position = at
	p.rotation = 0.0
	p.velocity = Vector2.ZERO
	return p


func _rocket(parent: Node, kind: EnemyRocket.Kind, at: Vector2, dir: Vector2) -> EnemyRocket:
	var r: EnemyRocket = EnemyRocketScenes.scene_for(kind).instantiate()
	parent.add_child(r)
	r.global_position = at
	r.reset()
	r.set_physics_process(false)
	(r.get_node("ProjectileLifetime") as Node).set_physics_process(false)
	r.launch(dir, at + dir * 400.0, null)
	return r


## Flies [param r] for [param ticks] and returns `[position, heading, guiding, in_field]` per tick.
func _fly(r: EnemyRocket, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		var guiding := r.is_guiding()
		r._tick(D)
		out.append([r.global_position, r.heading(), guiding, Hazards.jammer_at(r.global_position) != null])
	return out


# ── 1. Per variant: config, scene and registered info ────────────────────────────────────────────────────────────────

func test_each_variant_matches_its_config_and_registers_a_jammer(variant: String = use_parameters(VARIANTS)) -> void:
	var row: Dictionary = TABLE[variant]
	var cfg := load(row.config) as JammingStructureConfig  # read only
	assert_eq([cfg.max_health, cfg.field_radius, cfg.stabilise_seconds, [cfg.cycle_telegraph, cfg.cycle_active, cfg.cycle_quiet],
			cfg.score_value], [row.hp, row.radius, row.stab, row.cycle, row.score], "%s: the plan table" % variant)
	assert_eq([cfg.collision_damage, cfg.counts_as_escape, cfg.wreck_chance, cfg.assault_drift_speed], [0, false, 0.0, 60.0],
			"%s: no contact, never an escape, no wreck, 60 px/s drift" % variant)
	# The scene authors the same values the config writes in `_ready()` (the field registers with them in `_enter_tree()`).
	var raw := (row.scene as PackedScene).instantiate() as JammingStructure
	var raw_field := raw.get_node("Field") as HazardField
	assert_eq([raw_field.radius, raw_field.stabilise_seconds, [raw_field.cycle_telegraph, raw_field.cycle_active, raw_field.cycle_quiet],
			(raw.get_node("Health") as Health).max_health], [row.radius, row.stab, row.cycle, row.hp], "%s: scene == config" % variant)
	raw.free()
	for mode: String in MODES:
		var h := _world(mode)
		var j := _jammer(h.root, row.scene)
		var info := j.field().hazard_info()
		assert_eq([info.kind, info.avoid_weight, info.pull_force, info.movement_penalty, info.radius, info.stabilise_seconds],
				[&"jammer", 0.0, 0.0, 0.0, row.radius, row.stab], "%s/%s: the registered info" % [variant, mode])
		assert_true(j.field().disables_abilities, "%s/%s: a jammer" % [variant, mode])
		if variant == "pulsed":
			assert_false(info.disables_abilities, "%s: starts in TELEGRAPH, unlit" % mode)
			_step(j, 60)  # 1.0 s: ACTIVE
		assert_true(info.disables_abilities, "%s/%s: lit" % [variant, mode])
		var c := j.global_position
		assert_not_null(Hazards.jammer_at(c + Vector2(row.radius - 1.0, 0.0)), "%s/%s: 1 px inside the edge" % [variant, mode])
		assert_null(Hazards.jammer_at(c + Vector2(row.radius + 1.0, 0.0)), "%s/%s: 1 px outside" % [variant, mode])
		assert_eq(j.health.max_health, row.hp, "%s/%s: HP from the config" % [variant, mode])
		assert_true(j.is_in_group(&"enemies"), "%s/%s: an enemy" % [variant, mode])
		assert_false(j.is_laser_blocking(), "%s/%s: a target for the mining beam" % [variant, mode])
		assert_false(j.accept_tow(Vector2(40.0, 0.0)), "%s/%s: no tow" % [variant, mode])
		assert_false(j.counts_as_escape, "%s/%s" % [variant, mode])
		assert_eq(j.contact_profile.mode, ContactProfile.Mode.NONE, "%s/%s: contact NONE" % [variant, mode])
		assert_null(j.get_node_or_null("ContactHitBox"), "%s/%s: no contact box" % [variant, mode])
		assert_false(j.is_ai_driven(), "%s/%s: no brain, no mover" % [variant, mode])
		assert_true(j.answers_emp(), "%s/%s: answers EMP" % [variant, mode])
		h.root.free()


# ── 2. The pulsed cycle ───────────────────────────────────────────────────────────────────────────────────────────────

## TELEGRAPH 0.8 s -> ACTIVE 3.0 s -> QUIET 2.5 s on a loop (on exactly ticks 48, 229, 379, 427); a player-side lock
## (`jammer_at`) only in ACTIVE; the ring flickers and the light blinks in TELEGRAPH, both lit in ACTIVE, quiet / dark in QUIET.
func test_pulsed_phases_follow_0_8_3_0_2_5_and_lock_only_in_active() -> void:
	var h := _world("open_space")
	var j := _jammer(h.root, PULSED)
	var f := j.field()
	var changes: Array = []
	f.phase_changed.connect(func(p: int) -> void: changes.append(p))
	var change_ticks: Array = []
	var lit_ok := true
	var looks := {}
	var lights := {}
	var last := f.phase()
	for tick in range(1, 7 * 60 + 30):  # through 7.1 s (tick 427)
		_step(j)
		if f.phase() != last:
			last = f.phase()
			change_ticks.append(tick)
		var in_active := f.phase() == HazardField.Phase.ACTIVE
		if (Hazards.jammer_at(j.global_position) != null) != in_active:
			lit_ok = false
		var key := "%d" % f.phase()
		if not looks.has(key):
			looks[key] = {}
			lights[key] = {}
		looks[key][_art(j).look()] = true
		lights[key][_light(j).get_state()] = true
	assert_eq(changes, [HazardField.Phase.ACTIVE, HazardField.Phase.QUIET, HazardField.Phase.TELEGRAPH, HazardField.Phase.ACTIVE],
			"the loop")
	# 0.8, 3.8, 6.3, 7.1 s: the `fposmod` sum of 1/60 sits just under 3.8 and 6.3 on ticks 228 and 378, so those edges land a tick later.
	assert_eq(change_ticks, [48, 229, 379, 427], "the exact change ticks")
	assert_true(lit_ok, "jammer_at finds the field exactly while ACTIVE")
	assert_eq(looks["%d" % HazardField.Phase.ACTIVE].keys(), [JammerFieldArt.Look.LIT], "ACTIVE: the lit ring")
	assert_eq(looks["%d" % HazardField.Phase.TELEGRAPH].keys(), [JammerFieldArt.Look.FLICKER], "TELEGRAPH: flicker")
	assert_eq(looks["%d" % HazardField.Phase.QUIET].keys(), [JammerFieldArt.Look.QUIET], "QUIET: the faint outline")
	assert_eq(lights["%d" % HazardField.Phase.ACTIVE].keys(), [StateLight.State.ARMED], "ACTIVE: light on")
	var telegraph_lights: Array = lights["%d" % HazardField.Phase.TELEGRAPH].keys()
	telegraph_lights.sort()
	assert_eq(telegraph_lights, [StateLight.State.OFF, StateLight.State.CHARGING], "TELEGRAPH: the light blinks")
	assert_eq(lights["%d" % HazardField.Phase.QUIET].keys(), [StateLight.State.OFF], "QUIET: dark")


## The flicker alternates 0.35 / 0.1 every 0.1 s; the lit ring is 0.35, the quiet outline 0.08.
func test_the_ring_alpha_per_look() -> void:
	var h := _world("open_space")
	var j := _jammer(h.root, PULSED)
	var art := _art(j)
	var seen := {}
	for i in 30:  # TELEGRAPH (0.5 s)
		art._clock += D
		seen[roundi(art.ring_alpha() * 100.0)] = true
	var alphas: Array = seen.keys()
	alphas.sort()
	assert_eq(alphas, [10, 35], "TELEGRAPH flickers between 0.1 and 0.35 (alpha x 100)")
	_step(j, 60)
	assert_eq(art.look(), JammerFieldArt.Look.LIT)
	assert_almost_eq(art.ring_alpha(), 0.35, 1e-6)
	_step(j, 3 * 60 + 6)
	assert_eq(art.look(), JammerFieldArt.Look.QUIET)
	assert_almost_eq(art.ring_alpha(), 0.08, 1e-6)


# ── 3. Locked inside; killed from inside with the main gun; unlocked 0.75 s later ──────────────────────────────────

func test_a_real_ship_inside_is_locked_and_unlocks_0_75_s_after_the_jammer_is_shot_dead(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var box := Node2D.new()
	add_child_autofree(box)
	var j := LOCAL.instantiate() as JammingStructure
	j.position = Vector2(640.0, 200.0)
	box.add_child(j)
	var p := _player(mode, box, Vector2(640.0, 360.0))  # 160 px below the tower: inside its 240 px field
	p._step_disruption(D)
	assert_true(p.abilities_locked(), "%s: locked inside the lit field" % mode)
	var deaths: Array = []
	j.died.connect(func() -> void: deaths.append(true))
	for k in 3:  # 3 x 50 >= 140: primary fire, from inside the field
		var b: Node2D = BULLET_SCENE.instantiate()
		box.add_child(b)
		b.global_position = p.global_position + Vector2(0.0, -40.0 - 40.0 * k)
		b.rotation = 0.0
		b.expired.connect(b.queue_free)
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(j):
			break
	assert_eq(deaths.size(), 1, "%s: the main gun kills the jammer" % mode)
	assert_false(is_instance_valid(j), "%s: freed; its field unregistered" % mode)
	assert_null(Hazards.jammer_at(p.global_position), "%s: no lit field left" % mode)
	p._step_disruption(D)  # the exit tick T
	assert_true(p.abilities_locked(), "%s: still locked on the exit tick" % mode)
	for i in 44:
		p._step_disruption(D)
	assert_true(p.abilities_locked(), "%s: locked at T+44" % mode)
	p._step_disruption(D)
	assert_false(p.abilities_locked(), "%s: unlocked at T+45 (0.75 s)" % mode)


# ── 4. Assault: drift, free below the world rect, world-anchored x ──────────────────────────────────────────────────

func test_assault_drift_is_60_px_s_and_frees_below_the_world_rect_and_x_is_world_anchored() -> void:
	var h := _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	cam.offset = Vector2(100.0, 0.0)
	var tree := get_tree()
	assert_almost_eq(EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x, 100.0, 0.001,
			"sanity: the view is panned +100 px")
	for anchored: bool in [true, false]:
		var j := LOCAL.instantiate() as JammingStructure
		j.world_anchored_x = anchored
		j.global_position = cam.global_position + cam.offset + Vector2(-64.0, -100.0) * ArenaCamera.WORLD_SCALE  # WaveManager's formula
		var y := j.global_position.y
		h.root.add_child(j)
		_freeze(j)
		assert_almost_eq(j.global_position.x, 512.0 if anchored else 612.0, 0.001, "anchored %s: world x" % anchored)
		assert_eq(j.global_position.y, y, "anchored %s: y stays camera-relative" % anchored)
		j.free()
	var j := _jammer(h.root, LOCAL, Vector2(640.0, 100.0))
	var drift := j.get_node("AssaultDrift") as AssaultDrift
	for i in 60:
		drift.step(D)
	assert_almost_eq(j.global_position.y, 160.0, 0.01, "60 px in 1 s")
	assert_eq(j.field().global_position, j.global_position, "the field moves with it")
	assert_eq(j.field().hazard_info().position, j.global_position, "and so does its registered footprint")
	j.global_position.y = EnemyWorld.projectile_world_rect(tree).end.y - 0.5
	drift.step(D)
	assert_true(j.is_queued_for_deletion(), "freed below the projectile world rect")


func test_open_space_neither_drifts_nor_shifts_x() -> void:
	var h := _world("open_space")
	var j := _jammer(h.root, LOCAL, Vector2(612.0, 100.0))
	assert_eq(j.global_position.x, 612.0, "no view rect: x untouched")
	var drift := j.get_node("AssaultDrift") as AssaultDrift
	for i in 60:
		drift.step(D)
	assert_eq(j.global_position, Vector2(612.0, 100.0), "no drift in Open Space")


# ── 5. Enemies fight inside it: avoid weight 0 ───────────────────────────────────────────────────────────────────────

func _fighter_path(h: RefCounted) -> Array:
	var f := FIGHTER.instantiate() as Fighter
	f.global_position = Vector2(640.0, -360.0)
	(f.get_node("Brain") as FighterBrain).start_engaged = true
	(f.get_node("Brain") as FighterBrain).rng_seed = 7  # the same draws in every run
	h.root.add_child(f)
	f.set_physics_process(false)
	f.config.engage_seconds = 1000.0
	var path: Array = []
	for i in 240:
		var before := f.global_position
		f._physics_process(D)
		f.global_position = before + f.velocity * D
		path.append(f.global_position)
	f.free()
	return path


## The same Fighter APPROACH (the `test_enemy_dual_mode.gd` well row's start) with a real jammer whose field covers its leg,
## and with none: the positions agree tick for tick. Non-vacuity: the path runs inside the field.
func test_a_fighters_path_through_a_jammer_field_is_unchanged(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	h.player.global_position = Vector2(640.0, 360.0)
	var control := _fighter_path(h)
	# The body 120 px off the curve, square to it at tick 90 (an offset in x lands on the westward leg): the field over the leg.
	var normal := ((control[91] as Vector2) - (control[89] as Vector2)).orthogonal().normalized()
	var j := _jammer(h.root, LOCAL, (control[90] as Vector2) + normal * 120.0)
	var clearance := INF
	for p: Vector2 in control:
		clearance = minf(clearance, p.distance_to(j.global_position))
	assert_gt(clearance, 100.0, "%s: sanity: the path never touches the tower body (%.1f px)" % [mode, clearance])
	var with_jammer := _fighter_path(h)
	var inside := 0
	var worst := 0.0
	for i in control.size():
		worst = maxf(worst, (with_jammer[i] as Vector2).distance_to(control[i]))
		if (control[i] as Vector2).distance_to(j.global_position) < j.field().radius:
			inside += 1
	assert_gt(inside, 30, "%s: non-vacuous, the approach runs through the field (%d ticks)" % [mode, inside])
	assert_lt(worst, 1e-4, "%s: identical path (worst %.6f px)" % [mode, worst])
	# Positive control: the same field with an avoid weight bends the path, so avoidance is live in this set-up.
	j.field().avoid_weight = 1.0
	j.field().restart_cycle()
	var avoiding := _fighter_path(h)
	var bent := 0.0
	for i in control.size():
		bent = maxf(bent, (avoiding[i] as Vector2).distance_to(control[i]))
	assert_gt(bent, 5.0, "%s: control: with avoid weight 1.0 the same field bends the path (%.1f px)" % [mode, bent])


# ── 6-7. Seekers fly straight inside a lit field ─────────────────────────────────────────────────────────────────────

## A Pursuit rocket launched up from the jammer's centre at a player off to the right: every guided tick inside the lit field
## keeps its heading; after it leaves it steers again (inside its guidance window). Control: with no field the same stretch turns.
func test_an_enemy_pursuit_rocket_flies_straight_inside_a_lit_field_and_steers_after(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	h.player.global_position = Vector2(1100.0, 100.0)
	var start := Vector2(640.0, 700.0)
	var control := _fly(_rocket(h.root, EnemyRocket.Kind.PURSUIT, start, Vector2.UP), 150)
	_jammer(h.root, LOCAL, start)
	var run := _fly(_rocket(h.root, EnemyRocket.Kind.PURSUIT, start, Vector2.UP), 150)
	var guided_inside := 0
	var straight := true
	var turned_after := false
	var control_turned := false
	for i in range(1, run.size()):
		var turn := absf((run[i - 1][1] as Vector2).angle_to(run[i][1]))
		if run[i][2] and run[i - 1][3]:
			guided_inside += 1
			if turn > 1e-9:
				straight = false
			if absf((control[i - 1][1] as Vector2).angle_to(control[i][1])) > 1e-4:
				control_turned = true
		elif run[i][2] and not run[i - 1][3] and turn > 1e-4:
			turned_after = true
	assert_gt(guided_inside, 10, "%s: non-vacuous, guided ticks inside the field (%d)" % [mode, guided_inside])
	assert_true(straight, "%s: constant heading inside the lit field" % mode)
	assert_true(control_turned, "%s: control: with no field the same ticks turn" % mode)
	assert_true(turned_after, "%s: it steers again after leaving" % mode)


func test_a_dumb_rocket_is_unchanged_by_a_field(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	h.player.global_position = Vector2(1100.0, 100.0)
	var start := Vector2(640.0, 700.0)
	var control := _fly(_rocket(h.root, EnemyRocket.Kind.DUMB, start, Vector2.UP), 90)
	_jammer(h.root, LOCAL, start)
	var run := _fly(_rocket(h.root, EnemyRocket.Kind.DUMB, start, Vector2.UP), 90)
	for i in run.size():
		assert_eq(run[i][0], control[i][0], "%s: tick %d position" % [mode, i])
		if run[i][0] != control[i][0]:
			break


func test_a_pulsed_field_in_quiet_jams_nothing() -> void:
	var h := _world("assault")
	h.player.global_position = Vector2(1100.0, 100.0)
	var start := Vector2(640.0, 700.0)
	var control := _fly(_rocket(h.root, EnemyRocket.Kind.PURSUIT, start, Vector2.UP), 90)
	var j := _jammer(h.root, PULSED, start)
	_step(j, 4 * 60)  # 4.0 s: QUIET until 6.3 s; the field is not ticked while the rocket flies
	assert_eq(j.field().phase(), HazardField.Phase.QUIET, "sanity: quiet")
	var run := _fly(_rocket(h.root, EnemyRocket.Kind.PURSUIT, start, Vector2.UP), 90)
	var worst := 0.0
	for i in run.size():
		worst = maxf(worst, absf((run[i][1] as Vector2).angle_to(control[i][1])))
	assert_lt(worst, 1e-9, "a quiet field leaves the rocket's guidance alone")


# ── 8. EMP: the field goes quiet, the tower stays tangible, the cycle keeps running ─────────────────────────────────

func test_an_emp_suppresses_the_field_for_its_window_and_the_tower_stays_tangible(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var j := _jammer(h.root, LOCAL)
	var info := j.field().hazard_info()
	j.apply_emp(2.0, null)
	assert_false(info.disables_abilities, "%s: quiet on the call itself" % mode)
	assert_true(j.is_emp_disrupted(), "%s: disrupted" % mode)
	assert_true(j.field().is_suppressed())
	var overlay := j.get_node_or_null("EmpStatic") as CanvasItem
	assert_true(overlay != null and overlay.visible, "%s: the EmpStatic overlay shows" % mode)
	assert_eq(j.process_mode, Node.PROCESS_MODE_INHERIT, "%s: still processing" % mode)
	assert_true(j.hurt_box.monitorable and j.hurt_box.monitoring, "%s: the hurtbox stays in physics" % mode)
	assert_true(j.is_in_group(&"enemies"))
	_step(j, 1)
	assert_eq(_art(j).look(), JammerFieldArt.Look.QUIET, "%s: the quiet look" % mode)
	assert_eq(_light(j).get_state(), StateLight.State.OFF, "%s: the light dark" % mode)
	_step(j, 118)
	assert_false(info.disables_abilities, "%s: quiet after tick 119" % mode)
	_step(j, 1)
	assert_true(info.disables_abilities, "%s: lit again after tick 120 (2.0 s)" % mode)
	assert_false(j.is_emp_disrupted(), "%s: the window is over" % mode)
	assert_false(overlay.visible, "%s: overlay hidden" % mode)
	assert_eq(_art(j).look(), JammerFieldArt.Look.LIT)
	assert_eq(_light(j).get_state(), StateLight.State.ARMED)
	j.apply_emp(1.0, null)
	j.apply_emp(0.5, null)
	_step(j, 59)
	assert_false(info.disables_abilities, "%s: the longest window wins" % mode)
	_step(j, 1)
	assert_true(info.disables_abilities, "%s: lit after 1.0 s" % mode)


## A pulsed jammer EMP'd in ACTIVE stays quiet for the window; underneath its cycle kept running, so afterwards its phase
## and progress equal an untouched twin's.
func test_a_suppressed_pulsed_jammer_keeps_its_cycle_phase() -> void:
	var h := _world("open_space")
	var a := _jammer(h.root, PULSED, Vector2(300.0, 300.0))
	var b := _jammer(h.root, PULSED, Vector2(1000.0, 300.0))
	_step(a, 60)
	_step(b, 60)
	assert_eq([a.field().phase(), b.field().phase()], [HazardField.Phase.ACTIVE, HazardField.Phase.ACTIVE], "sanity: both lit")
	a.apply_emp(2.0, null)
	for i in 119:
		_step(a)
		_step(b)
		assert_false(a.field().hazard_info().disables_abilities, "quiet on tick %d" % (i + 1))
		assert_true(b.field().hazard_info().disables_abilities, "the twin is lit on tick %d" % (i + 1))
		if not b.field().hazard_info().disables_abilities:
			break
	_step(a)
	_step(b)
	assert_eq(a.field().phase(), b.field().phase(), "same phase after the window")
	assert_almost_eq(a.field().phase_progress(), b.field().phase_progress(), 1e-9, "same progress: the clock ran underneath")
	assert_eq(a.field().hazard_info().disables_abilities, b.field().hazard_info().disables_abilities, "and both lit alike")


# ── 9. WaveBuilder ───────────────────────────────────────────────────────────────────────────────────────────────────

func test_wave_builder_jammer_variants() -> void:
	var b := WaveBuilder.new()
	assert_eq(b.jammer()._scene, WaveBuilder.JAMMER, "local by default")
	assert_eq(b.jammer(&"local")._scene, WaveBuilder.JAMMER)
	assert_eq(b.jammer(&"sector")._scene, WaveBuilder.SECTOR_JAMMER)
	assert_eq(b.jammer(&"pulsed")._scene, WaveBuilder.PULSED_JAMMER)
	assert_eq([WaveBuilder.JAMMER, WaveBuilder.SECTOR_JAMMER, WaveBuilder.PULSED_JAMMER],
			[LOCAL.resource_path, SECTOR.resource_path, PULSED.resource_path], "the constants are the three scenes")


# ── 10. A config overridden before `add_child` takes at once (`HazardField.restart_cycle`) ─────────────────────────────

func test_a_config_overridden_before_add_child_registers_at_once() -> void:
	var h := _world("open_space")
	var j := LOCAL.instantiate() as JammingStructure
	# The local scene does not author `config`, so this is already the private copy `BaseEnemy._init()` made; an authored one
	# would be the shared cached `.tres` until `_enter_tree()`.
	assert_true(j.config.resource_path.is_empty(), "the private copy")
	j.config.field_radius = 100.0
	j.config.cycle_telegraph = 1.0
	j.config.cycle_active = 1.0
	j.config.cycle_quiet = 1.0
	j.position = Vector2(640.0, 300.0)
	h.root.add_child(j)
	_freeze(j)
	var info := j.field().hazard_info()
	assert_eq(info.radius, 100.0, "the override's radius is registered")
	assert_eq(j.field().phase(), HazardField.Phase.TELEGRAPH, "the override's cycle starts in TELEGRAPH")
	assert_false(info.disables_abilities, "so it is unlit at once")
	_step(j, 60)
	assert_true(info.disables_abilities, "lit after the 1.0 s telegraph")


# ── 11. Shooters take their spots inside a jammer field (their own ground) ─────────────────────────────────────────────

const SNIPER_SCENE: PackedScene = preload("res://assault/scenes/enemies/sniper/sniper.tscn")


func _sniper(h: RefCounted) -> Sniper:
	h.player.global_position = Vector2(640.0, 560.0)
	var s := SNIPER_SCENE.instantiate() as Sniper
	var brain := s.get_node("Brain") as SniperBrain
	brain.start_engaged = true
	brain.rng_seed = 4242
	s.config.engage_seconds = 1000.0
	s.config.decoy_telegraph = false
	s.global_position = Vector2(640.0, 80.0)
	h.root.add_child(s)
	s.set_physics_process(false)
	return s


func _sniper_pick(h: RefCounted) -> Dictionary:
	var s := _sniper(h)
	var brain := s.get_node("Brain") as SniperBrain
	var before := s.global_position
	s._physics_process(D)
	s.global_position = before + s.velocity * D
	var out := {"point": brain.target_point, "candidates": brain.last_candidates.duplicate(), "next": brain.rng.randf()}
	s.free()
	return out


## The control sniper's firing point; a lit local jammer centred on it; the same seeded sniper picks the same point, keeps every
## candidate inside the field and draws the same rng. (A well over the same point rejects it:
## `test_sniper.gd::test_a_candidate_inside_a_well_is_never_chosen`.)
func test_a_snipers_firing_point_inside_a_jammer_field_is_kept(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var control := _sniper_pick(h)
	assert_true((control.point as Vector2).is_finite(), "%s: sanity: a point" % mode)
	var j := _jammer(h.root, LOCAL, control.point + Vector2(120.0, 0.0))  # the field over the point, the body off it
	var run := _sniper_pick(h)
	assert_eq(run.point, control.point, "%s: the same point inside the field" % mode)
	assert_eq(run.next, control.next, "%s: the same next draw" % mode)
	var inside := 0
	for c: Dictionary in run.candidates:
		if (c["point"] as Vector2).distance_to(j.global_position) <= j.field().radius + 90.0:
			inside += 1
			assert_true(c["hazard_ok"], "%s: a candidate in the jammer's reach is fine" % mode)
	assert_gt(inside, 0, "%s: non-vacuous, candidates fell in the field" % mode)
	# In-row control: a well stand-in over the same point marks the candidates in its reach.
	j.free()
	var well := HazardField.new()
	well.kind = &"gravity_well"
	well.radius = 100.0
	well.position = control.point
	h.root.add_child(well)
	var with_well := _sniper_pick(h)
	var rejected := 0
	for c: Dictionary in with_well.candidates:
		if (c["point"] as Vector2).distance_to(control.point) <= 100.0 + 90.0:
			assert_false(c["hazard_ok"], "%s: control: a candidate in the well's reach is rejected" % mode)
			rejected += 1
	assert_gt(rejected, 0, "%s: control: some candidate fell in the well" % mode)
	assert_ne(with_well.point, control.point, "%s: control: the well moves the pick" % mode)


func test_a_fighter_cover_point_inside_a_jammer_field_is_kept(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var f := FIGHTER.instantiate() as Fighter
	(f.get_node("Brain") as FighterBrain).start_engaged = true
	f.global_position = Vector2(640.0, -300.0)
	h.root.add_child(f)
	f.set_physics_process(false)
	var brain := f.get_node("Brain") as FighterBrain
	var point := Vector2(400.0, 200.0)
	var wreck_info := HazardInfo.new()
	_jammer(h.root, LOCAL, point)
	assert_false(brain._inside_other_hazard(point, wreck_info), "%s: a jammer field does not spoil a cover point" % mode)
	var well := HazardField.new()
	well.kind = &"gravity_well"
	well.radius = 100.0
	well.position = point
	h.root.add_child(well)
	assert_true(brain._inside_other_hazard(point, wreck_info), "%s: control: a gravity well does" % mode)
