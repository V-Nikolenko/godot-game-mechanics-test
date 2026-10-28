## INTENT tests for the enemy energy-weapon core: `EnemyBeam`, `EnergyHitScan` and `EnemyBeamScenes`
## (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.1 / §2.2 / §2.3; task t2, task plan docs/plans/cmvqw0vmx017bqs2x5pghfctf/3-plan.md).
##
## Every row is hand-ticked at `DT` (the beam's owner-driven clock: `start()`, `tick(delta)`, `cancel()`) and runs in both harnesses, except
## the static rows (scene exports only) and the real-frame player cadence rows, which run on real physics at a **4×** clock: the player's
## i-frame `Timer` runs on idle frames, and at 8× one headless idle frame (~6.9 ms real) spans more than the 0.05 s between the player's
## 0.5 s window and the beam's 0.55 s re-hit, so 8× refuses a re-hit about once in 27 (measured in the t2 plan review; tests/README.md →
## Gate time rule 1 keeps such a row at a lower multiplier).
##
## Every weapon number is read from the beam scenes through `EnemyBeamScenes.export_of` (fallback: the script default), and every player
## number off an instance of `player_fighter.tscn` / `player_ship.tscn` — never typed here. `R` (reaction time) and the 0.5 s reactable floor
## are rule constants of §2.3.
##
## Victims are `fixture_enemy.tscn` with a 14 px `CircleShape2D` added to its `HurtBox` and group `enemies` joined at runtime (the shared
## scene is not edited), real asteroids, rams, allies and player scenes.
extends GutTest

const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const ALLY_SCENE: PackedScene = preload("res://assault/scenes/allies/ally_fighter/ally_fighter.tscn")
const RAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://assault/scenes/hazards/big_asteroid/big_asteroid.tscn")
const DUMB_ROCKET: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/dumb_rocket.tscn")
const BEAM_SCRIPT: GDScript = preload("res://assault/scenes/projectiles/enemy_beams/enemy_beam.gd")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const FIXTURE_RADIUS := 14.0
const FIXTURE_HP := 1000
## Reaction time and the reactable lock floor (§2.3: Ph4's Sniper `lock_seconds`): rule constants, not tuning.
const R := 0.25
const REACTABLE_FLOOR := 0.5
## The held window of the cadence rows: 2.0 s from the first lethal tick, last tick included.
const CADENCE_SECONDS := 2.0
const CADENCE_SPEEDUP := 4
const EMITTER := Vector2(200.0, 300.0)
const OWNER_GROUP := &"beam_test_owner_group"
## Every export of the §2.1 table.
const TABLE: Array[StringName] = [
	&"telegraph_seconds", &"commit_seconds", &"active_seconds", &"fade_seconds", &"ignite_grace", &"length", &"hit_half_width",
	&"draw_half_width", &"tip_grace_px", &"damage", &"rehit_interval", &"telegraph_width", &"sweep_arc_deg", &"sweep_rate",
	&"blocked_by_cover", &"registers_hazard", &"avoid_weight", &"hazard_pad",
]

var _sandbox := SaveSandbox.new()
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func after_each() -> void:
	_restore_clock()


func _scale_clock(speedup: int) -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * speedup
	Engine.max_physics_steps_per_frame = _saved_max_steps * speedup
	Engine.time_scale = _saved_time_scale * speedup


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


# ---------------------------------------------------------------------------------------------
# Builders and readers
# ---------------------------------------------------------------------------------------------

func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


## Every kind whose scene is built (TWIN joins with the endpoint-beam task).
func _built_kinds() -> Array[int]:
	var out: Array[int] = []
	for kind: int in EnemyBeam.Kind.values():
		if EnemyBeamScenes.scene_for(kind) != null:
			out.append(kind)
	return out


func _default(property: StringName) -> Variant:
	return BEAM_SCRIPT.get_property_default_value(property)


func _export(kind: int, property: StringName) -> Variant:
	return EnemyBeamScenes.export_of(kind, property, _default(property))


func _export_of_scene(scene: PackedScene, property: StringName) -> Variant:
	return EnemyBeamScenes.export_of_scene(scene, property, _default(property))


## Ticks a phase of [param seconds] lasts on the beam's clock (it ends on the tick whose summed delta reaches it).
func _ticks(seconds: float) -> int:
	return ceili(seconds / DT - 1e-3)


## [param kind]'s scene with [param changes] applied, re-packed: a synthetic copy for a boundary case.
func _synthetic(kind: int, changes: Dictionary) -> PackedScene:
	var inst: Node = EnemyBeamScenes.scene_for(kind).instantiate()
	for key: StringName in changes:
		inst.set(key, changes[key])
	inst.scene_file_path = ""
	var scene := PackedScene.new()
	assert_eq(scene.pack(inst), OK, "the synthetic copy packs")
	inst.free()
	return scene


## A beam of [param kind] in the harness at [param at], pointing along [param angle]; owner set from [param host] / [param group].
func _beam(h, kind: int, host: Node2D = null, group: StringName = &"", parent: Node = null,
		at: Vector2 = EMITTER, angle: float = 0.0) -> EnemyBeam:
	var b := EnemyBeamScenes.scene_for(kind).instantiate() as EnemyBeam
	(parent if parent != null else h.root).add_child(b)
	if parent == null:
		b.global_position = at
		b.global_rotation = angle
	b.setup(host, group)
	return b


func _circle(radius: float) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	return cs


## `fixture_enemy.tscn` made a beam victim: a 14 px circle on its `HurtBox` and group `enemies`, [param hp] health.
func _victim(h, at: Vector2, hp: int = FIXTURE_HP, shape: CollisionShape2D = null) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(shape if shape != null else _circle(FIXTURE_RADIUS))
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = hp
	health.current_health = hp
	h.root.add_child(e)
	e.global_position = at
	return e


func _hp(node: Node) -> int:
	return (node.get_node("Health") as Health).current_health


## Every `target_hit` as `[target, damage]`.
func _hits(b: EnemyBeam) -> Array:
	var record: Array = []
	b.target_hit.connect(func(target: Node2D, damage: int) -> void: record.append([target, damage]))
	return record


func _hits_on(record: Array, target: Node) -> int:
	var n := 0
	for entry: Array in record:
		if entry[0] == target:
			n += 1
	return n


func _tick(b: EnemyBeam, n: int) -> void:
	for i in n:
		b.tick(DT)


## Starts [param b] and ticks it to its first lethal tick (telegraph, then ignite grace).
func _ignite(b: EnemyBeam, kind: int) -> void:
	b.start()
	_tick(b, _ticks(float(_export(kind, &"telegraph_seconds"))) + _ticks(float(_export(kind, &"ignite_grace"))))
	assert_true(b.is_lethal(), "precondition: lethal after telegraph + ignite grace")


## The hit length of an emitter beam: its drawn length less the free tip's grace.
func _hit_length(kind: int) -> float:
	return float(_export(kind, &"length")) - float(_export(kind, &"tip_grace_px"))


## The real player of [param mode] in place of the harness's stand-in, shield zeroed, health raised to [param hp].
func _real_player(h, mode: String, at: Vector2, hp: int) -> PlayerBase:
	h.player.remove_from_group(&"player")
	h.player.queue_free()
	var player: PlayerBase = (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate()
	h.root.add_child(player)
	player.global_position = at
	player.set_physics_process(false)
	player.set_process(false)
	player.shield_component.set_all_zero()
	player.health_component.max_health = hp
	player.health_component.current_health = hp
	return player


## Both player scenes, off-tree: `r_p` = the larger hurtbox circumscribed radius about the body origin (local transforms), `v_c` = the
## slower `cruise_speed()`, `windows` = every i-frame window (PlayerBase's, and Health's when that one is enabled).
func _player_terms() -> Dictionary:
	var r_p := 0.0
	var v_c := INF
	var windows: Array[float] = []
	for scene: PackedScene in [FIGHTER_SCENE, SHIP_SCENE]:
		var p := scene.instantiate() as PlayerBase
		v_c = minf(v_c, p.cruise_speed())
		windows.append(p.invincibility_sec)
		var health := p.get_node_or_null("HealthComponent") as Health
		if health != null and health.invincibility_frames_enabled:
			windows.append(health.invincibility_time_in_sec)
		var hurt := p.get_node("HurtBox") as Node2D
		for child in hurt.get_children():
			var cs := child as CollisionShape2D
			if cs == null or cs.disabled or cs.shape == null:
				continue
			var xf := hurt.transform * cs.transform
			var rect := cs.shape.get_rect()
			var far := 0.0
			for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), rect.end]:
				far = maxf(far, corner.length())
			var s := maxf(absf(xf.get_scale().x), absf(xf.get_scale().y))
			r_p = maxf(r_p, xf.origin.length() + far * s)
		p.free()
	return {"r_p": r_p, "v_c": v_c, "windows": windows}


# ---------------------------------------------------------------------------------------------
# §2.1 timeline
# ---------------------------------------------------------------------------------------------

func test_timeline_phases_and_lethality(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var b := _beam(h, kind)
	var v := _victim(h, EMITTER + Vector2(300.0, 0.0))
	var phases: Array = []
	b.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var hits := _hits(b)
	var n_tel := _ticks(float(_export(kind, &"telegraph_seconds")))
	var n_ign := _ticks(float(_export(kind, &"ignite_grace")))
	var n_act := _ticks(float(_export(kind, &"active_seconds")))
	var n_fade := _ticks(float(_export(kind, &"fade_seconds")))
	assert_gt(n_ign, 0, "precondition: beam.tscn has an ignite grace")
	assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: a fresh beam is OFF" % mode)

	b.start()
	assert_eq(b.phase(), EnemyBeam.Phase.TELEGRAPH, "%s: start() -> TELEGRAPH" % mode)
	_tick(b, n_tel - 1)
	assert_eq(b.phase(), EnemyBeam.Phase.TELEGRAPH, "%s: still TELEGRAPH one tick before its end" % mode)
	assert_false(b.is_lethal(), "%s: TELEGRAPH is never lethal" % mode)
	assert_eq(hits.size(), 0, "%s: no hit at TELEGRAPH end - 1 tick" % mode)
	_tick(b, 1)
	assert_eq(b.phase(), EnemyBeam.Phase.ACTIVE, "%s: ACTIVE on the tick the telegraph ends" % mode)
	_tick(b, n_ign - 1)
	assert_eq(hits.size(), 0, "%s: no hit inside the ignite grace" % mode)
	assert_false(b.is_lethal(), "%s: not lethal before the ignite grace" % mode)
	_tick(b, 1)
	assert_eq(hits.size(), 1, "%s: hit on the first ACTIVE tick past the ignite grace" % mode)
	assert_eq(_hits_on(hits, v), 1, "%s: the fixture on the line is the one hit" % mode)
	assert_eq(_hp(v), FIXTURE_HP - int(_export(kind, &"damage")), "%s: the hit dealt damage" % mode)

	_tick(b, n_act - n_ign)
	assert_eq(b.phase(), EnemyBeam.Phase.FADE, "%s: FADE once active_seconds is over" % mode)
	# A fresh fixture, so the re-hit table cannot be what spares it.
	var fresh := _victim(h, EMITTER + Vector2(450.0, 0.0))
	_tick(b, n_fade - 1)
	assert_eq(b.phase(), EnemyBeam.Phase.FADE, "%s: still FADE" % mode)
	assert_eq(_hits_on(hits, fresh), 0, "%s: FADE is never lethal" % mode)
	_tick(b, 1)
	assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: OFF once fade_seconds is over" % mode)
	_tick(b, 30)
	assert_eq(_hits_on(hits, fresh), 0, "%s: OFF is never lethal" % mode)
	assert_eq(phases, [EnemyBeam.Phase.TELEGRAPH, EnemyBeam.Phase.ACTIVE, EnemyBeam.Phase.FADE, EnemyBeam.Phase.OFF],
			"%s: phase_changed once per change, in order" % mode)
	for p: Variant in phases:
		assert_eq(typeof(p), TYPE_INT, "%s: phase_changed carries one int" % mode)


func test_cancel_in_telegraph_goes_off_with_no_hits_and_in_active_goes_fade(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var b := _beam(h, kind)
	var v := _victim(h, EMITTER + Vector2(300.0, 0.0))
	var phases: Array = []
	b.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var hits := _hits(b)

	b.start()
	_tick(b, 5)
	b.cancel()
	assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: cancel() in TELEGRAPH -> OFF at once" % mode)
	_tick(b, _ticks(float(_export(kind, &"telegraph_seconds"))) + _ticks(float(_export(kind, &"active_seconds"))))
	assert_eq(hits.size(), 0, "%s: a cancelled telegraph never hits" % mode)
	assert_eq(phases, [EnemyBeam.Phase.TELEGRAPH, EnemyBeam.Phase.OFF], "%s: TELEGRAPH -> OFF" % mode)

	phases.clear()
	_ignite(b, kind)
	assert_eq(_hits_on(hits, v), 1, "%s: lit and hitting" % mode)
	b.cancel()
	assert_eq(b.phase(), EnemyBeam.Phase.FADE, "%s: cancel() in ACTIVE -> FADE" % mode)
	assert_false(b.is_lethal(), "%s: FADE is not lethal" % mode)
	var fresh := _victim(h, EMITTER + Vector2(450.0, 0.0))
	_tick(b, _ticks(float(_export(kind, &"fade_seconds"))))
	assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: and on to OFF" % mode)
	assert_eq(_hits_on(hits, fresh), 0, "%s: nothing hit after the cancel" % mode)
	b.cancel()
	assert_eq(b.phase(), EnemyBeam.Phase.OFF, "%s: cancel() in OFF changes nothing" % mode)
	assert_eq(phases, [EnemyBeam.Phase.TELEGRAPH, EnemyBeam.Phase.ACTIVE, EnemyBeam.Phase.FADE, EnemyBeam.Phase.OFF],
			"%s: one phase_changed per change" % mode)


func test_a_start_while_lit_is_ignored(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var b := _beam(h, EnemyBeam.Kind.BEAM)
	var phases: Array = []
	b.phase_changed.connect(func(p: int) -> void: phases.append(p))
	b.start()
	_tick(b, 3)
	b.start()
	assert_eq(phases, [EnemyBeam.Phase.TELEGRAPH], "%s: a start() in TELEGRAPH neither restarts nor re-emits" % mode)


# ---------------------------------------------------------------------------------------------
# §2.1 re-hit, telegraph width, geometry
# ---------------------------------------------------------------------------------------------

func test_rehit_cadence_over_two_seconds(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var b := _beam(h, kind)
	var v := _victim(h, EMITTER + Vector2(300.0, 0.0))
	var hit_ticks: Array[int] = []
	b.target_hit.connect(func(_target: Node2D, _damage: int) -> void: hit_ticks.append(-1))
	var rehit := float(_export(kind, &"rehit_interval"))
	# Held (beam.tscn's own ACTIVE is shorter than the window).
	b.start(-1.0, 0.0)
	_tick(b, _ticks(float(_export(kind, &"telegraph_seconds"))) + _ticks(float(_export(kind, &"ignite_grace"))) - 1)
	assert_eq(hit_ticks.size(), 0, "precondition: nothing before the first lethal tick")
	var window := roundi(CADENCE_SECONDS / DT)
	for k in window + 1:  # k = 0 is the first lethal tick; the last tick (2.0 s) is included
		b.tick(DT)
		if hit_ticks.size() > 0 and hit_ticks[-1] == -1:
			hit_ticks[-1] = k
	var expected := floori(CADENCE_SECONDS / rehit) + 1
	assert_eq(hit_ticks.size(), expected, "%s: exactly floor(2.0 / rehit_interval) + 1 hits in 2.0 s held" % mode)
	assert_eq(hit_ticks[0] if hit_ticks.size() > 0 else -99, 0, "%s: the first hit is the first lethal tick" % mode)
	for i in range(1, hit_ticks.size()):
		assert_eq(hit_ticks[i] - hit_ticks[i - 1], _ticks(rehit), "%s: hits exactly rehit_interval apart" % mode)
	assert_eq(_hp(v), FIXTURE_HP - expected * int(_export(kind, &"damage")), "%s: each hit dealt damage" % mode)

	# The Lance hits a held fixture once per activation.
	var lance := _beam(h, EnemyBeam.Kind.LANCE, null, &"", null, EMITTER + Vector2(0.0, 200.0))
	var held := _victim(h, EMITTER + Vector2(300.0, 200.0))
	var lance_hits := _hits(lance)
	lance.start()
	var lance_life := _ticks(float(_export(EnemyBeam.Kind.LANCE, &"telegraph_seconds"))) \
			+ _ticks(float(_export(EnemyBeam.Kind.LANCE, &"active_seconds"))) + _ticks(float(_export(EnemyBeam.Kind.LANCE, &"fade_seconds")))
	_tick(lance, lance_life)
	assert_eq(lance.phase(), EnemyBeam.Phase.OFF, "%s: the lance ran its whole timeline" % mode)
	assert_eq(_hits_on(lance_hits, held), 1, "%s: the lance hits a held fixture exactly once" % mode)


func _telegraph_width_ok(scene: PackedScene) -> bool:
	return float(_export_of_scene(scene, &"telegraph_width")) >= 3.0


func test_telegraph_width_is_at_least_3_and_drawn(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	for kind in _built_kinds():
		var width := float(_export(kind, &"telegraph_width"))
		assert_true(_telegraph_width_ok(EnemyBeamScenes.scene_for(kind)), "%s: kind %d telegraph_width %.1f >= 3" % [mode, kind, width])
		var b := _beam(h, kind, null, &"", null, EMITTER, 0.3)
		b.start()
		_tick(b, 1)
		var line := b.get_node("Telegraph") as Line2D
		assert_true(line.visible and line.is_visible_in_tree(), "%s: kind %d draws its telegraph" % [mode, kind])
		assert_eq(line.width, width, "%s: kind %d telegraph Line2D.width == telegraph_width" % [mode, kind])
		var dir := Vector2.RIGHT.rotated(0.3)
		assert_eq(line.points.size(), 2, "%s: one straight line" % mode)
		if line.points.size() == 2:
			assert_almost_eq(line.points[0], EMITTER, Vector2(0.01, 0.01), "%s: kind %d telegraph starts at the emitter" % [mode, kind])
			assert_almost_eq(line.points[1], EMITTER + dir * float(_export(kind, &"length")), Vector2(0.01, 0.01),
					"%s: kind %d telegraph runs the whole path, along local +X" % [mode, kind])
		assert_false((b.get_node("Core") as Line2D).visible, "%s: no core while telegraphing" % mode)
		_tick(b, _ticks(float(_export(kind, &"telegraph_seconds"))) + _ticks(float(_export(kind, &"ignite_grace"))))
		assert_false(line.visible, "%s: kind %d telegraph hidden once lit" % [mode, kind])
		assert_true((b.get_node("Core") as Line2D).visible and (b.get_node("Glow") as Line2D).visible, "%s: kind %d core and glow lit" % [mode, kind])
		assert_gt((b.get_node("Glow") as Line2D).width, (b.get_node("Core") as Line2D).width, "%s: the glow is wider than the core" % mode)
	# Boundary: a 2 px telegraph fails the same predicate.
	assert_false(_telegraph_width_ok(_synthetic(EnemyBeam.Kind.BEAM, {&"telegraph_width": 2.0})), "a 2 px telegraph line fails the >= 3 row")


func test_a_lance_telegraph_turns_white_when_committed(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.LANCE
	var b := _beam(h, kind)
	var n_tel := _ticks(float(_export(kind, &"telegraph_seconds")))
	var n_commit := _ticks(float(_export(kind, &"commit_seconds")))
	b.start()
	_tick(b, n_tel - n_commit - 1)
	assert_false(b.is_committed(), "%s: not committed before the last commit_seconds" % mode)
	var line := b.get_node("Telegraph") as Line2D
	var before := line.default_color
	_tick(b, 1)
	assert_true(b.is_committed(), "%s: committed for the last commit_seconds of TELEGRAPH" % mode)
	assert_ne(line.default_color, before, "%s: the committed telegraph changes colour" % mode)
	_tick(b, n_commit)
	assert_false(b.is_committed(), "%s: not committed once ACTIVE" % mode)
	var beam := _beam(h, EnemyBeam.Kind.BEAM)
	beam.start()
	for i in _ticks(float(_export(EnemyBeam.Kind.BEAM, &"telegraph_seconds"))):
		assert_false(beam.is_committed(), "%s: a beam with commit_seconds 0 never commits" % mode)
		beam.tick(DT)


func test_swept_hit_between_two_ticks(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var pivot := Node2D.new()
	h.root.add_child(pivot)
	pivot.global_position = EMITTER
	var b := _beam(h, kind, null, &"", pivot)
	# A test-only rate: one tick turns the beam 0.2 rad (a 140 px tip jump), which leaves the fixture outside BOTH tick bands.
	var step := 0.2
	var at := EMITTER + Vector2.RIGHT.rotated(step * 0.5) * 500.0
	var v := _victim(h, at)
	var hit_len := _hit_length(kind)
	var hhw := float(_export(kind, &"hit_half_width"))
	for angle: float in [0.0, step]:
		var band := RectangleShape2D.new()
		band.size = Vector2(hit_len, 2.0 * hhw)
		var dir := Vector2.RIGHT.rotated(angle)
		assert_false(EnergyHitScan.hits_band(band, Transform2D(angle, EMITTER + dir * hit_len * 0.5), v),
				"%s: precondition: the band at %.1f rad misses the fixture" % [mode, angle])
	var hits := _hits(b)
	_ignite(b, kind)
	assert_eq(hits.size(), 0, "%s: not hit at the first bearing" % mode)
	pivot.rotation = step
	b.tick(DT)
	assert_eq(_hits_on(hits, v), 1, "%s: the line crossed the fixture between two ticks: the swept test hits it" % mode)


func test_tip_grace(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var b := _beam(h, kind)
	var hit_len := _hit_length(kind)
	var length := float(_export(kind, &"length"))
	assert_lt(hit_len + FIXTURE_RADIUS + 1.0, length, "precondition: the outside fixture's edge is inside the drawn tip")
	var outside := _victim(h, EMITTER + Vector2(hit_len + FIXTURE_RADIUS + 1.0, 0.0))
	var inside := _victim(h, EMITTER + Vector2(hit_len + FIXTURE_RADIUS - 1.0, 0.0))
	var hits := _hits(b)
	_ignite(b, kind)
	assert_eq(_hits_on(hits, outside), 0, "%s: a hurtbox 1 px past the hit length (inside tip_grace_px) is not hit" % mode)
	assert_eq(_hits_on(hits, inside), 1, "%s: a hurtbox 1 px inside the hit length is hit" % mode)


func test_width_plus_minus_one_px(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var b := _beam(h, kind)
	var hhw := float(_export(kind, &"hit_half_width"))
	assert_gt(float(_export(kind, &"draw_half_width")), hhw + 1.0, "precondition: the drawn glow covers the near miss")
	var miss := _victim(h, EMITTER + Vector2(300.0, hhw + 1.0 + FIXTURE_RADIUS))
	var graze := _victim(h, EMITTER + Vector2(400.0, -(hhw - 1.0 + FIXTURE_RADIUS)))
	var hits := _hits(b)
	_ignite(b, kind)
	assert_eq(_hits_on(hits, miss), 0, "%s: an edge hit_half_width + 1 px off the line is not hit" % mode)
	assert_eq(_hits_on(hits, graze), 1, "%s: an edge hit_half_width - 1 px off the line is hit" % mode)


func test_exact_rectangle_wing_crosses(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var b := _beam(h, kind)
	var shapes: Array[CollisionShape2D] = []
	for rot: float in [PI / 2.0, 0.0]:
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(96.0, 44.0)  # the Bomber's hull
		cs.shape = rect
		cs.rotation = rot
		shapes.append(cs)
	var wing := _victim(h, EMITTER + Vector2(250.0, 40.0), FIXTURE_HP, shapes[0])
	var flat := _victim(h, EMITTER + Vector2(450.0, 40.0), FIXTURE_HP, shapes[1])
	var hits := _hits(b)
	_ignite(b, kind)
	assert_eq(_hits_on(hits, wing), 1, "%s: a 96 x 44 hull 40 px off the line whose wing crosses it is hit" % mode)
	assert_eq(_hits_on(hits, flat), 0, "%s: control: the same hull turned flat (22 px half-height) is not" % mode)


func test_export_table_read_through_export_of() -> void:
	for kind in _built_kinds():
		var inst := EnemyBeamScenes.scene_for(kind).instantiate() as EnemyBeam
		assert_eq(int(inst.kind), kind, "kind %d: the scene's kind export matches scene_for" % kind)
		for property in TABLE:
			assert_eq(_export(kind, property), inst.get(property), "kind %d: export_of(%s) is the scene's value" % [kind, property])
		inst.free()
	assert_null(EnemyBeamScenes.scene_for(EnemyBeam.Kind.TWIN), "twin_beam.tscn is the endpoint-beam task's")
	assert_eq(EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, &"damage", -7), -7, "an unbuilt kind answers the fallback")


# ---------------------------------------------------------------------------------------------
# §2.2 victims, the owner set, damage rules, scoring
# ---------------------------------------------------------------------------------------------

func test_victims(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var damage := int(_export(kind, &"damage"))
	var b := _beam(h, kind)
	var enemy := _victim(h, EMITTER + Vector2(100.0, 0.0))
	var asteroid: Node2D = ASTEROID_SCENE.instantiate()
	h.root.add_child(asteroid)
	asteroid.global_position = EMITTER + Vector2(250.0, 0.0)
	asteroid.set_physics_process(false)
	var player := _real_player(h, mode, EMITTER + Vector2(400.0, 0.0), 10 * damage)
	var ally: Node2D = null
	if mode == "assault":
		ally = ALLY_SCENE.instantiate()
		h.root.add_child(ally)
		ally.global_position = EMITTER + Vector2(550.0, 0.0)
		ally.set_physics_process(false)
	var asteroid_hp := _hp(asteroid)
	var ally_hp := _hp(ally) if ally != null else 0
	var hits := _hits(b)
	_ignite(b, kind)
	assert_eq(_hits_on(hits, enemy), 1, "%s: a fixture enemy is hit" % mode)
	assert_eq(_hp(enemy), FIXTURE_HP - damage, "%s: for damage" % mode)
	assert_eq(_hits_on(hits, asteroid), 1, "%s: an asteroid is hit" % mode)
	assert_eq(_hp(asteroid), asteroid_hp - damage, "%s: for damage (the direct emit skips accepted_damage_types)" % mode)
	assert_eq(_hits_on(hits, player), 1, "%s: the real player is hit" % mode)
	assert_eq(player.health_component.current_health, 10 * damage - damage, "%s: the player loses damage" % mode)
	if ally != null:
		assert_eq(_hits_on(hits, ally), 1, "%s: the real ally fighter is hit" % mode)
		assert_eq(_hp(ally), ally_hp - damage, "%s: for damage" % mode)
	for entry: Array in hits:
		assert_eq(entry[1], damage, "%s: target_hit carries the damage" % mode)
	assert_eq(hits.size(), 3 + (1 if ally != null else 0), "%s: one target_hit per delivered hit, nothing else hit" % mode)


func test_owner_set_is_exempt(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var host := _victim(h, EMITTER + Vector2(60.0, 0.0))
	var member := _victim(h, EMITTER + Vector2(250.0, 0.0))
	member.add_to_group(OWNER_GROUP)
	var control := _victim(h, EMITTER + Vector2(450.0, 0.0))
	var b := _beam(h, kind, host, OWNER_GROUP)
	var hits := _hits(b)
	_ignite(b, kind)
	_tick(b, _ticks(float(_export(kind, &"rehit_interval"))) + 1)
	assert_eq(_hits_on(hits, host), 0, "%s: the host is never hit" % mode)
	assert_eq(_hp(host), FIXTURE_HP)
	assert_eq(_hits_on(hits, member), 0, "%s: a member of the owner group is never hit" % mode)
	assert_eq(_hp(member), FIXTURE_HP)
	assert_eq(_hits_on(hits, control), 2, "%s: control: the same fixture outside the group is hit (and re-hit)" % mode)


func test_plated_ram_takes_no_health_damage(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var ram: RamCorvette = RAM_SCENE.instantiate()
	h.root.add_child(ram)
	ram.global_position = EMITTER + Vector2(300.0, 0.0)
	ram.suspend_ai()
	ram.set_physics_process(false)
	assert_true(ram.is_armored(), "precondition: the ram's plates are on")
	var hull := ram.health.current_health
	var b := _beam(h, kind)
	var hits := _hits(b)
	_ignite(b, kind)
	assert_eq(_hits_on(hits, ram), 1, "%s: the beam reaches the plated hull (no plate absorbs it)" % mode)
	assert_eq(ram.health.current_health, hull, "%s: a plated Ram refuses it in its own hull rule" % mode)


func test_sustained_shield_is_bypassed(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var e := _victim(h, EMITTER + Vector2(300.0, 0.0))
	var shield := EnemyShield.new()
	shield.arc_deg = 360.0
	shield.capacity = 500
	shield.sustain_mode = true
	e.add_child(shield)
	assert_true(shield.attach(e.hurt_box), "precondition: the shield holds the hurtbox's absorber slot")
	shield.sustain(EMITTER)
	assert_true(shield.is_up(), "precondition: the bubble is up")
	var b := _beam(h, kind)
	_ignite(b, kind)
	assert_eq(_hp(e), FIXTURE_HP - int(_export(kind, &"damage")), "%s: a shielded enemy takes the full damage" % mode)
	assert_eq(shield.points(), 500, "%s: the bubble never saw the hit" % mode)


func test_ordnance_is_never_hit(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var mine := EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY).instantiate() as EnemyMine
	h.root.add_child(mine)
	mine.global_position = EMITTER + Vector2(200.0, 0.0)
	mine.expired.connect(mine.queue_free)
	mine.launch(Vector2.ZERO, 0.0, mine.global_position)
	var rocket := DUMB_ROCKET.instantiate() as EnemyRocket
	h.root.add_child(rocket)
	rocket.global_position = EMITTER + Vector2(400.0, 0.0)
	rocket.expired.connect(rocket.queue_free)
	rocket.reset()
	rocket.launch(Vector2.DOWN, EMITTER + Vector2(400.0, 600.0), null)
	var received: Array[int] = [0]
	for node: Node in [mine, rocket]:
		(node.get_node("HurtBox") as HurtBox).received_damage.connect(func(_d: int) -> void: received[0] += 1)
	var b := _beam(h, kind)
	var hits := _hits(b)
	_ignite(b, kind)
	_tick(b, _ticks(float(_export(kind, &"rehit_interval"))) + 1)
	assert_eq(hits.size(), 0, "%s: nothing on the line but ordnance" % mode)
	assert_eq(received[0], 0, "%s: neither the mine's nor the rocket's hurtbox took anything" % mode)
	assert_true(is_instance_valid(mine) and not mine.is_queued_for_deletion(), "%s: the mine is still live" % mode)
	assert_true(is_instance_valid(rocket) and not rocket.is_queued_for_deletion(), "%s: the rocket is still live" % mode)


func test_beam_kill_scores(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var damage := int(_export(kind, &"damage"))
	var e := _victim(h, EMITTER + Vector2(300.0, 0.0), damage)
	var died: Array[int] = [0]
	e.died.connect(func() -> void: died[0] += 1)
	var b := _beam(h, kind)
	_ignite(b, kind)
	assert_eq(_hp(e), 0, "%s: one hit kills a damage-HP fixture" % mode)
	assert_true(e.was_killed, "%s: a beam kill is a kill (was_killed), so it scores" % mode)
	assert_eq(died[0], 1, "%s: died fires once" % mode)


func _rehit_clears(scene: PackedScene, windows: Array[float]) -> bool:
	var rehit := float(_export_of_scene(scene, &"rehit_interval"))
	for w in windows:
		if not rehit > w:
			return false
	return true


func test_rehit_interval_exceeds_player_invincibility() -> void:
	var windows: Array[float] = _player_terms().windows
	assert_gte(windows.size(), 2, "both player scenes report their i-frame window")
	for kind in _built_kinds():
		assert_true(_rehit_clears(EnemyBeamScenes.scene_for(kind), windows),
				"kind %d: rehit_interval %.2f > every player i-frame window %s" % [kind, float(_export(kind, &"rehit_interval")), windows])
	# Boundary: a beam re-hitting on the player's own 0.5 s window fails.
	assert_false(_rehit_clears(_synthetic(EnemyBeam.Kind.BEAM, {&"rehit_interval": 0.5}), windows), "a 0.5 s re-hit fails the row")


## Real frames (the player's i-frame `Timer` runs on them) at the 4× clock: a `_Ticker` ticks the beam on the physics step, and cancels it
## 2.0 s (last tick included) after its first lethal tick.
func test_player_cadence_on_real_frames(mode: String = use_parameters(MODES)) -> void:
	_scale_clock(CADENCE_SPEEDUP)
	var h = _world(mode)
	var kind := EnemyBeam.Kind.BEAM
	var damage := int(_export(kind, &"damage"))
	var rehit := float(_export(kind, &"rehit_interval"))
	var player := _real_player(h, mode, EMITTER + Vector2(300.0, 0.0), 10 * damage)
	var losses: Array[int] = []
	var last_hp: Array[int] = [player.health_component.current_health]
	player.health_component.amount_changed.connect(func(current: int) -> void:
		if current < last_hp[0]:
			losses.append(last_hp[0] - current)
		last_hp[0] = current)
	var b := _beam(h, kind)
	var hits := _hits(b)
	var window := roundi(CADENCE_SECONDS / DT)
	var state := {"since_lit": -1, "done": false}
	_tick_each_frame(h.root, func(delta: float) -> void:
		if state.done:
			return
		b.tick(delta)
		if b.is_lethal() and state.since_lit < 0:
			state.since_lit = 0
		elif state.since_lit >= 0:
			state.since_lit += 1
		if state.since_lit >= window:
			b.cancel()
			state.done = true)
	b.start(0.0, 0.0)
	await wait_physics_frames(window + _ticks(float(_export(kind, &"ignite_grace"))) + 8)
	assert_true(state.done, "%s: the 2.0 s window ran" % mode)
	var expected := floori(CADENCE_SECONDS / rehit) + 1
	var delivered := _hits_on(hits, player)
	gut.p("%s: %d hits delivered, %d health losses %s (expected %d +- 1)" % [mode, delivered, losses.size(), losses, expected])
	assert_between(losses.size(), expected - 1, expected + 1, "%s: the player loses health floor(2.0 / rehit) + 1 times" % mode)
	assert_eq(delivered, losses.size(), "%s: every delivered hit lowered health: no hit refused by i-frames" % mode)
	for loss in losses:
		assert_eq(loss, damage, "%s: each loss is the beam's damage" % mode)


## Calls [param fn] with the physics delta on every physics tick while the returned node lives (a child of [param parent], freed with it).
func _tick_each_frame(parent: Node, fn: Callable) -> Node:
	var t := _Ticker.new()
	t.fn = fn
	parent.add_child(t)
	return t


class _Ticker extends Node:
	var fn: Callable

	func _physics_process(delta: float) -> void:
		fn.call(delta)


# ---------------------------------------------------------------------------------------------
# §2.3 fairness (each row's predicate also runs on a synthetic copy pushed past its bound)
# ---------------------------------------------------------------------------------------------

func _static_fair(scene: PackedScene, terms: Dictionary) -> bool:
	var telegraph := float(_export_of_scene(scene, &"telegraph_seconds"))
	var hhw := float(_export_of_scene(scene, &"hit_half_width"))
	return telegraph >= R + (hhw + float(terms.r_p)) / float(terms.v_c) - 1e-9


func test_fairness_static_beams() -> void:
	var terms := _player_terms()
	gut.p("r_p %.2f px, v_c %.1f px/s" % [terms.r_p, terms.v_c])
	assert_gt(float(terms.r_p), 0.0, "precondition: the player hurtbox radius was read")
	for kind: int in [EnemyBeam.Kind.BEAM, EnemyBeam.Kind.SWEEP]:
		var bound := R + (float(_export(kind, &"hit_half_width")) + float(terms.r_p)) / float(terms.v_c)
		assert_true(_static_fair(EnemyBeamScenes.scene_for(kind), terms),
				"kind %d: telegraph %.2f s >= R + (hit_half_width + r_p) / v_c = %.3f s" % [kind, float(_export(kind, &"telegraph_seconds")), bound])
	var beam_bound := R + (float(_export(EnemyBeam.Kind.BEAM, &"hit_half_width")) + float(terms.r_p)) / float(terms.v_c)
	assert_false(_static_fair(_synthetic(EnemyBeam.Kind.BEAM, {&"telegraph_seconds": beam_bound - 0.01}), terms),
			"boundary: a telegraph 0.01 s under the bound fails")


func _sweep_fair(scene: PackedScene, terms: Dictionary) -> bool:
	return float(_export_of_scene(scene, &"sweep_rate")) * float(_export_of_scene(scene, &"length")) <= float(terms.v_c) + 1e-9


func test_fairness_sweep_tip_never_outruns_the_player() -> void:
	var terms := _player_terms()
	var kind := EnemyBeam.Kind.SWEEP
	var tip := float(_export(kind, &"sweep_rate")) * float(_export(kind, &"length"))
	assert_gt(float(_export(kind, &"sweep_rate")), 0.0, "precondition: the sweep scene has a rate")
	assert_true(_sweep_fair(EnemyBeamScenes.scene_for(kind), terms), "sweep tip %.1f px/s <= v_c %.1f px/s" % [tip, terms.v_c])
	var over := (float(terms.v_c) + 1.0) / float(_export(kind, &"length"))
	assert_false(_sweep_fair(_synthetic(kind, {&"sweep_rate": over}), terms), "boundary: a tip 1 px/s faster than the player fails")


func _lance_fair(scene: PackedScene) -> bool:
	var telegraph := float(_export_of_scene(scene, &"telegraph_seconds"))
	var commit := float(_export_of_scene(scene, &"commit_seconds"))
	return commit >= REACTABLE_FLOOR - 1e-9 and telegraph - commit >= R - 1e-9


func test_fairness_lance_commit_and_reaction() -> void:
	var kind := EnemyBeam.Kind.LANCE
	var telegraph := float(_export(kind, &"telegraph_seconds"))
	var commit := float(_export(kind, &"commit_seconds"))
	assert_true(_lance_fair(EnemyBeamScenes.scene_for(kind)),
			"lance: commit %.2f >= %.2f and telegraph - commit %.2f >= R" % [commit, REACTABLE_FLOOR, telegraph - commit])
	assert_false(_lance_fair(_synthetic(kind, {&"commit_seconds": REACTABLE_FLOOR - 0.05})), "boundary: a 0.45 s commit fails")
	assert_false(_lance_fair(_synthetic(kind, {&"telegraph_seconds": commit + R - 0.05})), "boundary: 0.2 s of uncommitted telegraph fails")
