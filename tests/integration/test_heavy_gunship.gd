## The Heavy Gunship's shell, parts, movement and Assault life (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.4; Phase 10 t4, task plan
## docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md), and its hull phases, VENT, EMERGENCY, rear missiles and cannon shield (§2.5 / §2.9; t5, task
## plan docs/plans/cmwafsrb400abqs2yt38khcyu/3-plan.md, section "Phases (t5)" below). Intent tests, both harnesses unless a row says otherwise.
##
## Hand-ticked at 1/60 (`_tick`: `_physics_process(dt)`, then the position integrated from the velocity, the corvette tests' shape); the test
## moves the harness player itself. `_spawn()` writes `engage_seconds = 1000` (the budget is live in the Assault harness and would end every
## long row at 9 s); only the Assault-life rows put the shipped 9.0 back. The projectile rows run on real physics at the 16x clock with the hull
## held still (`set_physics_process(false)`: no brain, no mover), so a shot meets the authored geometry exactly.
##
## Frame: the art is nose-down, so the nose is local +y and port (the hull's left) is local +x; `_nose()` / `_port()` read them off the rotation.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const PH10: GDScript = preload("res://tests/helpers/ph10_exit_keys.gd")
const PROBE: GDScript = preload("res://tests/helpers/specialist_exit_probe.gd")
const REPLAY: GDScript = preload("res://tests/helpers/level1_slice_replay.gd")
const SINGLE_WRITER: GDScript = preload("res://tests/integration/test_enemy_mover_single_writer.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/heavy_gunship/heavy_gunship.tscn")
const SHIPPED: HeavyGunshipConfig = preload("res://assault/scenes/enemies/heavy_gunship/heavy_gunship_config.tres")  # read only
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")
const Phase := HeavyGunshipBrain.Phase

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const ASSAULT_PLAYER := Vector2(640.0, 620.0)
## Where the projectile rows hold the hull (inside the Assault view, clear of the player stub).
const TARGET_AT := Vector2(640.0, 300.0)
## A projectile row's shot starts this far outside the edge it is aimed at (px).
const SHOT := 110.0
## The flush-edge tolerance (review N2: the outer side is authored exactly on the hull coordinate).
const FLUSH_EPS := 0.01
## The angle bands of the facing rows (degrees).
const FACING_TOL := 20.0
## The x band an Assault strafing player stays in (the view's 1280 px less a margin).
const STRAFE_X := Vector2(200.0, 1080.0)
## The Cloud Descent window the budget is derived from (§2.12 / §2.4.3: the 62.0 + 0.8 s heavy at rel −13.2 s of a 10 s timeout). t11 replaces
## it with the live `test_engagement_deadline.gd::_deadline_rows` figure.
const CLOUD_DESCENT_WINDOW := 23.2
## `test_engagement_deadline.gd`'s MARGIN.
const DEADLINE_MARGIN := 0.5
## (id, role, max_health, starts_vulnerable, hull_share) in tree order.
const PARTS := [
	[&"battery_port", EnemyModule.Role.WEAPON, 160, true, 0.0],
	[&"battery_starboard", EnemyModule.Role.WEAPON, 160, true, 0.0],
	[&"cannon", EnemyModule.Role.WEAPON, 200, true, 0.0],
	[&"missiles", EnemyModule.Role.WEAPON, 140, true, 0.0],
	[&"vent_port", EnemyModule.Role.WEAK_POINT, 0, false, 1.0],
	[&"vent_starboard", EnemyModule.Role.WEAK_POINT, 0, false, 1.0],
]
## id -> [variant, traverse_deg, rest_bearing_deg].
const MOUNTS := {
	&"battery_port": [TurretMount.Variant.BURST_CANNON, 160.0, 0.0],
	&"battery_starboard": [TurretMount.Variant.BURST_CANNON, 160.0, 180.0],
	&"cannon": [TurretMount.Variant.HEAVY_CANNON, 70.0, 90.0],
	&"missiles": [TurretMount.Variant.ROCKET_BATTERY, 360.0, 270.0],
}
const _SPEEDUP := 16  # rule 1: the two real-physics rows wait a count of physics frames, never seconds (tests/README.md -> Gate time)
const _FROZEN_TIME_SCALE := 1e-6  # `_fresh_idle_delta()`: the clock while a hand-ticked boost row runs

var _exit: Dictionary = {}
var _probe_s: float = 0.0
var _roots: Array[Node] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false
var _idle_frozen: bool = false
var _saved_idle_time_scale: float = 1.0


func before_all() -> void:
	var t0 := Time.get_ticks_usec()
	_exit = PH10.heavy_gunship_exit(self)
	_probe_s = float(Time.get_ticks_usec() - t0) / 1e6


func after_each() -> void:
	_thaw_idle_clock()
	_restore_clock()
	_roots.clear()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## A fresh harness world. Any earlier world of this test is taken out of the tree first: its player would still be in group `player` (and its
## camera an arena), and `TargetInfo.player()` reads the first one it finds. It is still freed with the test.
func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = ASSAULT_PLAYER if h.is_assault else Vector2.ZERO
	return h


func _spawn(h, pos: Vector2, props: Dictionary = {}, seed: int = 1, engaged: bool = true) -> HeavyGunship:
	var g := SCENE.instantiate() as HeavyGunship
	var brain := g.get_node("Brain") as HeavyGunshipBrain
	brain.start_engaged = engaged
	brain.rng_seed = seed
	g.config.engage_seconds = 1000.0
	for key in props:
		g.config.set(key, props[key])
	g.global_position = pos
	h.root.add_child(g)
	g.set_physics_process(false)  # hand-ticked
	return g


func _tick(g: HeavyGunship, delta: float = DT) -> void:
	var before := g.global_position
	g._physics_process(delta)
	g.global_position = before + g.velocity * delta


## One tick of the hull, then the player moves on its own velocity.
func _step(g: HeavyGunship, player: CharacterBody2D) -> void:
	_tick(g)
	player.global_position += player.velocity * DT


func _brain(g: HeavyGunship) -> HeavyGunshipBrain:
	return g.get_node("Brain") as HeavyGunshipBrain


func _part(g: HeavyGunship, id: StringName) -> EnemyModule:
	return g.modular_hull().module(id)


func _nose(g: Node2D) -> Vector2:
	return Vector2.DOWN.rotated(g.rotation)


func _port(g: Node2D) -> Vector2:
	return Vector2.RIGHT.rotated(g.rotation)


## Degrees between [param dir] and the bearing from the hull to the player.
func _deg_to_player(g: Node2D, player: Node2D, dir: Vector2) -> float:
	return rad_to_deg(absf(dir.angle_to(player.global_position - g.global_position)))


## A rect in the host's local frame: a part's hurtbox shape, or the root's.
func _local_rect(host: Node2D, shape_node: CollisionShape2D) -> Rect2:
	var xf := host.global_transform.affine_inverse() * shape_node.global_transform
	var r := (shape_node.shape as RectangleShape2D).get_rect()
	return xf * r


## The part's exposed edge as {normal (host-local, outward), a, b (segment ends, host-local)}, or {} when no side is flush within FLUSH_EPS.
func _exposed_edge(hull: Rect2, part: Rect2) -> Dictionary:
	var sides := [
		[Vector2.RIGHT, absf(part.end.x - hull.end.x), Vector2(hull.end.x, part.position.y), Vector2(hull.end.x, part.end.y)],
		[Vector2.LEFT, absf(part.position.x - hull.position.x), Vector2(hull.position.x, part.position.y), Vector2(hull.position.x, part.end.y)],
		[Vector2.DOWN, absf(part.end.y - hull.end.y), Vector2(part.position.x, hull.end.y), Vector2(part.end.x, hull.end.y)],
		[Vector2.UP, absf(part.position.y - hull.position.y), Vector2(part.position.x, hull.position.y), Vector2(part.end.x, hull.position.y)],
	]
	for s in sides:
		if float(s[1]) <= FLUSH_EPS:
			return {"normal": s[0], "a": s[2], "b": s[3]}
	return {}


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## Physics frames until [param p] is spent (freed or queued for deletion), then [param after] more so a second hit in the next step would still
## be counted; at most [param cap] frames before that (a projectile that is never spent waits the whole cap, the old fixed wait). t4 review
## round 1: a fixed 20-frame wait per shot was most of the projectile rows' time.
func _until_spent(p: Node, cap: int, after: int = 2) -> void:
	for _i in cap:
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			break
		await get_tree().physics_frame
	await _frames(after)


## A real projectile launched at [param target] from `SHOT` px away along [param from_dir], nose toward it (player projectiles fly along
## `Vector2.UP.rotated(rotation)`). Its flight ends the way `WeaponBehavior._launch()` ends it: `expired -> queue_free`.
func _fire(parent: Node, scene: PackedScene, target: Vector2, from_dir: Vector2) -> Node2D:
	var p: Node2D = scene.instantiate()
	parent.add_child(p)
	p.global_position = target + from_dir * SHOT
	p.rotation = Vector2.UP.angle_to(-from_dir)
	if p.has_signal("expired"):
		p.expired.connect(p.queue_free)
	return p


func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null, _b = null) -> void: n[0] += 1)
	return n


func _mount_variant(mount: TurretMount) -> int:
	for v in TurretMount.Variant.values():
		var scene := TurretMountScenes.scene_for(v)
		if scene != null and scene.resource_path == mount.scene_file_path:
			return v
	return -1


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_the_hull_is_six_parts_four_mounts_and_a_700_hp_phase_bar(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, Vector2(640.0, 200.0))
	var parts := g.modular_hull().modules()
	assert_eq(parts.size(), PARTS.size(), "%s: six parts" % mode)
	for i in mini(parts.size(), PARTS.size()):
		var row: Array = PARTS[i]
		var part := parts[i]
		assert_eq(part.module_id, row[0], "%s: part %d id" % [mode, i])
		assert_eq(part.role, row[1], "%s: %s role" % [mode, row[0]])
		assert_eq(part.max_health, row[2], "%s: %s max_health" % [mode, row[0]])
		assert_eq(part.is_vulnerable(), row[3], "%s: %s vulnerable" % [mode, row[0]])
		assert_eq(part.hull_share, row[4], "%s: %s hull_share" % [mode, row[0]])
		assert_eq(part.get_parent(), g.get_node("Modules"), "%s: %s sits under Modules" % [mode, row[0]])
	var total := 0
	for id in MOUNTS:
		var mounts := g.modular_hull().mounts_of(id)
		total += mounts.size()
		assert_eq(mounts.size(), 1, "%s: one mount on %s" % [mode, id])
		if mounts.size() == 1:
			var spec: Array = MOUNTS[id]
			assert_eq(_mount_variant(mounts[0]), spec[0], "%s: %s variant" % [mode, id])
			assert_eq(mounts[0].traverse_deg, spec[1], "%s: %s traverse" % [mode, id])
			assert_eq(mounts[0].rest_bearing_deg, spec[2], "%s: %s rest bearing" % [mode, id])
			assert_eq(mounts[0].owner_group(), g.owner_group(), "%s: %s exempts its own hull" % [mode, id])
	assert_eq(total, 4, "%s: four mounts" % mode)
	assert_eq(g.health.max_health, 700, "%s: the hull's phase bar" % mode)
	assert_eq(g.health.current_health, 700)
	assert_eq(g.contact_hit_box.damage, 30, "%s: contact damage" % mode)
	assert_eq(g.contact_profile.mode, ContactProfile.Mode.COLLISION)
	assert_eq(g.score_value, 300)
	assert_true(g.is_ai_driven(), "%s: a brain and a mover" % mode)
	assert_true(g.answers_emp(), "%s: answers EMP" % mode)
	assert_true(g.is_in_group(&"enemies"))
	assert_true(g.is_in_group(g.owner_group()))
	assert_false(g.is_laser_blocking(), "the beam passes over the hull")
	assert_almost_eq(g.rocket_clear_radius(), sqrt(56.0 * 56.0 + 72.0 * 72.0) + 4.0, 0.01, "half-diagonal + 4")
	assert_eq(g.sprite_forward_angle, PI / 2.0, "nose-down hull art")
	assert_false(_brain(g).accepts_tow(), "a heavy is never towed")
	assert_false(g.accept_tow(Vector2(100.0, 0.0)))


func test_the_config_is_applied_and_carries_the_plan_values() -> void:
	var h = _world("open_space")
	var g := _spawn(h, Vector2(0.0, -560.0))
	var mover := g.get_node("EnemyMover") as EnemyMover
	assert_eq([mover.max_speed, mover.acceleration, mover.max_turn_rate], [140.0, 120.0, 0.9])
	assert_eq([mover.hazard_avoidance, mover.hazard_margin, mover.hazard_resistance], [1.0, 90.0, 0.6])
	assert_same(_brain(g).config, g.config)
	var c := SHIPPED
	assert_eq([c.max_health, c.collision_damage, c.score_value, c.wreck_chance], [700, 30, 300, 0.0])
	assert_eq([c.preferred_range, c.assault_preferred_range, c.range_drift, c.range_tolerance, c.min_range], [560.0, 420.0, 90.0, 100.0, 260.0])
	assert_eq([c.orbit_angular_speed, c.assault_orbit_angular_speed, c.assault_arc_half_deg, c.reversal_min, c.reversal_max],
			[0.16, 0.26, 70.0, 5.0, 8.0])
	assert_eq([c.break_speed, c.break_seconds, c.break_rearm], [360.0, 0.7, 3.0])
	assert_eq([c.engage_seconds, c.exit_speed, c.exit_acceleration], [9.0, 300.0, 240.0])
	assert_eq([c.perceive_radius, c.lose_radius, c.notice_time, c.idle_radius, c.idle_speed], [900.0, 1500.0, 0.6, 180.0, 0.4])
	assert_lt(c.orbit_angular_speed * (c.preferred_range + c.range_drift), c.max_speed, "the open-sky arc stays under max_speed")
	assert_lt(c.assault_orbit_angular_speed * (c.assault_preferred_range + c.range_drift), c.max_speed, "so does the Assault arc")
	assert_gt(c.lose_radius, c.preferred_range + c.range_drift + c.range_tolerance, "its own fight never reads as losing the player")
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")
	assert_almost_eq(_brain(g).attack_window(), 1.05, 1e-6, "the heavy cannon's 0.7 s charge + 0.35 s gap")
	assert_lte(c.break_seconds, _brain(g).attack_window(), "a break-away never defers DISENGAGE past the attack window")
	assert_eq([c.overheat_ratio, c.emergency_ratio, c.heat_limit, c.vent_seconds, c.vent_speed_factor, c.emergency_period, c.emergency_boost_speed,
			c.emergency_boost_seconds, c.missile_window, c.missile_rear_arc_deg, c.emergency_range, c.emergency_assault_extra, c.shield_arc_deg,
			c.shield_capacity, c.shield_regen_delay, c.shield_regen_seconds, c.shield_reboot_seconds], T5_CONFIG, "the t5 Phases / Defense values (§2.16)")
	assert_lte(c.emergency_boost_seconds, c.emergency_period, "one emergency boost ends before the next is due")
	assert_lt(c.emergency_ratio, c.overheat_ratio, "the bands are ordered")
	assert_almost_eq(_brain(g).salvo_window(), 0.85, 1e-6, "the rear salvo: 0.5 s glow + 0.35 s gap (read off the mount)")


func test_the_phase_enum_is_append_only_and_the_builder_spawns_it() -> void:
	assert_eq([Phase.APPROACH, Phase.BROADSIDE, Phase.BREAK_AWAY, Phase.VENT, Phase.EMERGENCY, Phase.DISENGAGE, Phase.IDLE, Phase.NOTICING,
			Phase.RETURNING], [0, 1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq([HeavyGunshipBrain.HullPhase.CONTROLLED, HeavyGunshipBrain.HullPhase.OVERHEAT, HeavyGunshipBrain.HullPhase.EMERGENCY], [0, 1, 2],
			"HullPhase is append-only too")
	assert_eq(WaveBuilder.HEAVY_GUNSHIP, "res://assault/scenes/enemies/heavy_gunship/heavy_gunship.tscn")
	assert_eq(WaveBuilder.new().heavy_gunship()._scene, WaveBuilder.HEAVY_GUNSHIP)
	assert_true(ResourceLoader.exists(WaveBuilder.HEAVY_GUNSHIP))


# ── The flush-edge rule (§2.4.1, review N2) ──────────────────────────────────────────────────────

func test_every_part_is_flush_with_the_hull_edge_and_homes_on_its_midpoint() -> void:
	var h = _world("open_space")
	var g := _spawn(h, Vector2(300.0, 200.0))
	var body := g.get_node("CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is RectangleShape2D, "the body is one rectangle")
	assert_eq((body.shape as RectangleShape2D).size, Vector2(112.0, 144.0))
	assert_same((g.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape, body.shape, "the root hurtbox is the body's shape")
	assert_same((g.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D).shape, body.shape, "so is the contact box")
	var hull := _local_rect(g, g.get_node("HurtBox/CollisionShape2D"))
	var rects: Array[Rect2] = []
	for part in g.modular_hull().modules():
		var shape := part.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
		assert_true(shape.shape is RectangleShape2D, "%s: a rectangle" % part.module_id)
		var r := _local_rect(g, shape)
		rects.append(r)
		assert_true(hull.grow(FLUSH_EPS).encloses(r), "%s: inside the hull outline" % part.module_id)
		var edge := _exposed_edge(hull, r)
		assert_false(edge.is_empty(), "%s: its outer side lies on a hull side within %.2f px" % [part.module_id, FLUSH_EPS])
		if edge.is_empty():
			continue
		var mid: Vector2 = ((edge["a"] as Vector2) + (edge["b"] as Vector2)) * 0.5
		var homing: Vector2 = g.global_transform.affine_inverse() * part.homing_point()
		assert_almost_eq(homing, mid, Vector2(FLUSH_EPS, FLUSH_EPS), "%s: the HomingPoint is the exposed-edge midpoint" % part.module_id)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "parts %d and %d do not overlap" % [i, j])


## Boundary: the static row's check rejects a part pulled 1 px inside the outline and one standing 1 px proud.
func test_the_flush_check_rejects_an_inset_or_a_proud_part() -> void:
	var hull := Rect2(-56.0, -72.0, 112.0, 144.0)
	assert_false(_exposed_edge(hull, Rect2(24.0, -10.0, 32.0, 40.0)).is_empty(), "control: the battery's rect is flush")
	assert_true(_exposed_edge(hull, Rect2(23.0, -10.0, 32.0, 40.0)).is_empty(), "1 px inset is refused")
	assert_true(_exposed_edge(hull, Rect2(25.0, -10.0, 32.0, 40.0)).is_empty(), "1 px proud is refused")


# ── Every part is reachable (real physics, 8x) ───────────────────────────────────────────────────

func test_a_bullet_through_each_exposed_edge_hits_that_part_and_the_hull(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, TARGET_AT)
	g.set_physics_process(false)
	_scale_clock()
	await _frames(2)
	var hull_rect := _local_rect(g, g.get_node("HurtBox/CollisionShape2D"))
	var probe := BULLET_SCENE.instantiate() as Node
	var damage := (probe.get_node("HitBox") as HitBox).damage
	probe.free()
	# Control first: a closed vent's edge. The hull takes the shot once; the vent refuses it (a white ping).
	var vent := _part(g, &"vent_port")
	var pings := _count(vent.deflected)
	var hp := g.health.current_health
	var b0 := _fire(h.root, BULLET_SCENE, vent.homing_point(), Vector2.RIGHT)
	await _until_spent(b0, 20)
	assert_false(is_instance_valid(b0) and not b0.is_queued_for_deletion(), "%s: the hull consumed the shot" % mode)
	assert_eq(hp - g.health.current_health, damage, "%s: a closed vent: the hull once" % mode)
	assert_eq(pings[0], 1, "%s: the closed vent pinged once" % mode)
	# A bare stretch of flank: the hull only.
	hp = g.health.current_health
	var dmg_counts := {}
	for part in g.modular_hull().modules():
		dmg_counts[part.module_id] = _count(part.damaged)
	var b1 := _fire(h.root, BULLET_SCENE, g.to_global(Vector2(56.0, 51.0)), Vector2.RIGHT)
	await _until_spent(b1, 20)
	assert_eq(hp - g.health.current_health, damage, "%s: a bare flank shot hurts the hull once" % mode)
	for id in dmg_counts:
		assert_eq((dmg_counts[id] as Array[int])[0], 0, "%s: and no part (%s)" % [mode, id])
	# Each part through its own edge.
	for part in g.modular_hull().modules():
		if part.role == EnemyModule.Role.WEAK_POINT:
			part.set_vulnerable(true)  # opened for the row (t5's VENT)
		var shield := part.get_node_or_null("Shield")
		if shield != null:
			shield.free()  # t5's frontal cannon shield would eat this shot; it releases the absorber slot on exit (its own row is t5's)
		var edge := _exposed_edge(hull_rect, _local_rect(g, part.get_node("HurtBox/CollisionShape2D")))
		var normal: Vector2 = (edge["normal"] as Vector2).rotated(g.rotation)
		var hp_before := g.health.current_health
		var hits := _count(part.damaged)
		var b := _fire(h.root, BULLET_SCENE, part.homing_point(), normal)
		await _until_spent(b, 20)
		assert_false(is_instance_valid(b) and not b.is_queued_for_deletion(), "%s: %s consumed the shot" % [mode, part.module_id])
		assert_eq(hits[0], 1, "%s: %s took the shot exactly once" % [mode, part.module_id])
		var expected := roundi(float(damage) * (1.0 + part.hull_share))
		assert_eq(hp_before - g.health.current_health, expected,
				"%s: %s: the hull took the shot directly (and the vent's hull_share forwarded it again)" % [mode, part.module_id])
		if part.max_health > 0:
			assert_eq(part.health.current_health, part.max_health - damage, "%s: %s lost the bullet's damage" % [mode, part.module_id])


func test_a_homing_rocket_from_the_port_side_steers_into_the_port_battery(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, TARGET_AT)
	g.set_physics_process(false)
	_scale_clock()
	await _frames(2)
	var battery := _part(g, &"battery_port")
	assert_eq(g.homing_point(g.to_global(Vector2(300.0, 0.0))), battery.homing_point(), "%s: from port the rocket aims at the port battery's edge" % mode)
	var hits := _count(battery.damaged)
	var rocket := HOMING_SCENE.instantiate()
	rocket.set(&"locked_target", g)
	h.root.add_child(rocket)
	rocket.global_position = g.to_global(Vector2(320.0, 120.0))
	rocket.rotation = Vector2.UP.angle_to(Vector2.LEFT)
	var damage := (rocket.get_node("HitBox") as HitBox).damage
	var hp := g.health.current_health
	await _until_spent(rocket, 60)
	assert_eq(hits[0], 1, "%s: the rocket hit the port battery" % mode)
	assert_eq(battery.health.current_health, battery.max_health - damage, "%s: for its damage" % mode)
	assert_eq(hp - g.health.current_health, damage, "%s: and the hull took the same shot once" % mode)


# ── Range, broadside and the side swap ───────────────────────────────────────────────────────────

## `held_range() ± (range_drift + range_tolerance)` from the first tick inside it to the end of 20 s, against one circling the heavy at 200
## px/s (strafing round it, the way a player works a broadside hull; in Assault it sweeps back and forth along that arc inside the view). Not a
## player jinking on a circle of its own: a 120 px/s^2 hull cannot follow a 200 px/s jink, which alone moves the range by the circle's radius
## (the task plan's 300 px circle; t4 DECISIONS). The still-player case is the first scenario of
## `test_against_a_still_player_it_holds_its_range_turns_a_battery_side_on_and_keeps_that_side` (t4 review round 1: one run per mode).
func test_it_holds_its_range_against_a_circling_player(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var centre: Vector2 = h.player.global_position
	var held := SHIPPED.assault_preferred_range if h.is_assault else SHIPPED.preferred_range
	var g := _spawn(h, centre + Vector2(0.0, -held - 150.0))
	var band := _range_band(held)
	var first := -1
	var worst := Vector2(INF, -INF)
	var sense := 1.0
	for i in int(20.0 / DT):
		var px: float = h.player.global_position.x
		if h.is_assault and (px > STRAFE_X.y or px < STRAFE_X.x):
			sense = -1.0 if px > STRAFE_X.y else 1.0
		var rel: Vector2 = h.player.global_position - g.global_position
		h.player.velocity = rel.orthogonal().normalized() * 200.0 * sense
		h.player.global_position += h.player.velocity * DT
		_tick(g)
		var d := g.global_position.distance_to(h.player.global_position)
		if first < 0 and d >= band.x and d <= band.y:
			first = i
		if first >= 0:
			worst = Vector2(minf(worst.x, d), maxf(worst.y, d))
	_assert_range(mode + "_circling", first, worst, band)


func _range_band(held: float) -> Vector2:
	return Vector2(held - SHIPPED.range_drift - SHIPPED.range_tolerance, held + SHIPPED.range_drift + SHIPPED.range_tolerance)


func _assert_range(case: String, first: int, worst: Vector2, band: Vector2) -> void:
	assert_gte(first, 0, "%s: it reached the band" % case)
	assert_gte(worst.x, band.x, "%s: never closer than %.0f (worst %.1f)" % [case, band.x, worst.x])
	assert_lte(worst.y, band.y, "%s: never further than %.0f (worst %.1f)" % [case, band.y, worst.y])


## 20 s against a still player (Assault: the shipped arc, clamp and corridor, the player low in the view), from 150 px beyond the held range:
## `{first, worst, band}` for the range, `share` = the share of BROADSIDE ticks whose nose is 90 ± 20 degrees off the bearing to the player, and
## `sides` = every chosen battery side in order.
func _still_player_run(mode: String, turn_rate: float) -> Dictionary:
	var h = _world(mode)
	var held := SHIPPED.assault_preferred_range if h.is_assault else SHIPPED.preferred_range
	var g := _spawn(h, (h.player.global_position as Vector2) + Vector2(0.0, -held - 150.0), {"max_turn_rate": turn_rate})
	var brain := _brain(g)
	var band := _range_band(held)
	var first := -1
	var worst := Vector2(INF, -INF)
	var inside := 0
	var total := 0
	var sides: Array[int] = []
	for i in int(20.0 / DT):
		_tick(g)
		var d := g.global_position.distance_to(h.player.global_position)
		if first < 0 and d >= band.x and d <= band.y:
			first = i
		if first >= 0:
			worst = Vector2(minf(worst.x, d), maxf(worst.y, d))
		if brain.side != HeavyGunshipBrain.SIDE_NONE and (sides.is_empty() or sides[-1] != brain.side):
			sides.append(brain.side)
		if brain.phase != Phase.BROADSIDE:
			continue
		total += 1
		if absf(_deg_to_player(g, h.player, _nose(g)) - 90.0) <= FACING_TOL:
			inside += 1
	return {"first": first, "worst": worst, "band": band, "share": float(inside) / float(total) if total > 0 else 0.0, "sides": sides}


## Three rows over one scenario per mode (t4 review round 1: they used to tick 20 + 20 + 16 s each): the range is held, a battery side is
## turned to the player, and with both batteries alive the chosen side never changes (the control for the swap below). The facing control: a
## hull that can hardly turn misses the band.
func test_against_a_still_player_it_holds_its_range_turns_a_battery_side_on_and_keeps_that_side(mode: String = use_parameters(MODES)) -> void:
	var run := _still_player_run(mode, SHIPPED.max_turn_rate)
	_assert_range(mode + "_still", int(run["first"]), run["worst"], run["band"])
	var share: float = run["share"]
	assert_gte(share, 0.8, mode + ": the nose is 90 ± 20 degrees off the bearing for %.0f %% of BROADSIDE" % (share * 100.0))
	assert_eq((run["sides"] as Array).size(), 1, "%s: one side all along (%s)" % [mode, run["sides"]])
	var control: float = _still_player_run(mode, 0.05)["share"]
	assert_lt(control, 0.8, mode + ": control: a hull that can hardly turn misses the band (%.0f %%)" % (control * 100.0))


## Ticks until `pred` first holds, then whether it held to the end of `seconds`; -1 if never.
func _settle(g: HeavyGunship, player: CharacterBody2D, seconds: float, pred: Callable) -> Dictionary:
	var first := -1
	var held := true
	for i in int(round(seconds / DT)):
		_step(g, player)
		var ok: bool = pred.call()
		if first < 0 and ok:
			first = i
		elif first >= 0 and not ok:
			held = false
	return {"seconds": first * DT if first >= 0 else -1.0, "held": held and first >= 0}


func test_a_dead_battery_turns_the_other_side_then_the_nose_then_away(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var held := SHIPPED.assault_preferred_range if h.is_assault else SHIPPED.preferred_range
	var g := _spawn(h, h.player.global_position + Vector2(0.0, -held))
	var brain := _brain(g)
	brain.side = HeavyGunshipBrain.SIDE_PORT
	var port_on := func() -> bool: return _deg_to_player(g, h.player, _port(g)) <= FACING_TOL
	var starboard_on := func() -> bool: return _deg_to_player(g, h.player, -_port(g)) <= FACING_TOL
	var nose_on := func() -> bool: return _deg_to_player(g, h.player, _nose(g)) <= FACING_TOL
	var nose_away := func() -> bool: return _deg_to_player(g, h.player, -_nose(g)) <= FACING_TOL
	var r := _settle(g, h.player, 6.0, port_on)
	assert_true(r["held"], "%s: precondition: the port side faces the player (from %.2f s)" % [mode, r["seconds"]])
	_part(g, &"battery_port").destroy()
	r = _settle(g, h.player, 10.0, starboard_on)
	assert_between(float(r["seconds"]), 0.0, 5.0, "%s: the starboard side turns to the player within 5 s" % mode)
	assert_true(r["held"], "%s: and stays" % mode)
	assert_eq(brain.side, HeavyGunshipBrain.SIDE_STARBOARD)
	_part(g, &"battery_starboard").destroy()
	r = _settle(g, h.player, 8.0, nose_on)
	assert_between(float(r["seconds"]), 0.0, 5.0, "%s: no battery: the nose (the cannon) turns to the player" % mode)
	assert_true(r["held"], "%s: and stays" % mode)
	_part(g, &"cannon").destroy()
	r = _settle(g, h.player, 8.0, nose_away)
	assert_between(float(r["seconds"]), 0.0, 5.0, "%s: missiles only: the nose turns away" % mode)
	assert_true(r["held"], "%s: and stays" % mode)


# ── Break-away ───────────────────────────────────────────────────────────────────────────────────

func test_a_rusher_inside_min_range_draws_one_boost_until_the_rearm(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var held := SHIPPED.assault_preferred_range if h.is_assault else SHIPPED.preferred_range
	var g := _spawn(h, h.player.global_position + Vector2(0.0, -held))
	var brain := _brain(g)
	var mover := g.get_node("EnemyMover") as EnemyMover
	for _i in 30:
		_tick(g)
	assert_eq(brain.breaks_started, 0, "%s: precondition: no break at range" % mode)
	var entries := [0]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == Phase.BREAK_AWAY:
			entries[0] += 1)
	# A 300 px/s rusher put 200 px off the hull every tick for 2.5 s (inside min_range, inside the 3 s rearm).
	var boost_from := Vector2.ZERO
	var boost_away := Vector2.ZERO
	var boost_moved := Vector2.ZERO
	for i in int(2.5 / DT):
		var toward: Vector2 = (g.global_position - h.player.global_position).normalized()
		if i == 0:
			h.player.global_position = g.global_position - toward * 200.0
		h.player.velocity = toward * 300.0
		if i == 0:
			boost_from = g.global_position
			boost_away = toward  # player -> hull
		_tick(g)
		if i == 0:
			assert_true(mover.is_boosting(), "%s: the boost is committed at once" % mode)
		if i == int(SHIPPED.break_seconds / DT) - 1:
			boost_moved = g.global_position - boost_from
		h.player.global_position = g.global_position - (g.global_position - h.player.global_position).normalized() * 200.0
	assert_eq(entries[0], 1, "%s: exactly one break-away" % mode)
	assert_eq(brain.breaks_started, 1)
	# break_contact against a closing threat: 1 part away, 1.2 parts sideways, so about 0.64 of the boost is away from the rusher.
	assert_gt(boost_moved.length(), 0.9 * SHIPPED.break_speed * SHIPPED.break_seconds, "%s: the boost carried it %.0f px" % [mode, boost_moved.length()])
	assert_gt(boost_moved.dot(boost_away), 0.5 * SHIPPED.break_speed * SHIPPED.break_seconds,
			"%s: away from the rusher (%.0f px of it)" % [mode, boost_moved.dot(boost_away)])
	for _i in int(1.0 / DT):
		h.player.global_position = g.global_position + Vector2(0.0, 200.0)
		_tick(g)
	assert_eq(brain.breaks_started, 2, "%s: once the rearm has run out, another" % mode)


# ── Assault ──────────────────────────────────────────────────────────────────────────────────────

## Over three seeds (review M5: a reversal near the top of the arc must not park it on a lucky seed). "Never holds a y within 8 px for more
## than 2 s" is read as: in every 2 s window its y spans more than 16 px.
func test_in_assault_it_never_parks_and_stays_above_the_player_inside_the_corridor(seed: int = use_parameters([1, 2, 3])) -> void:
	var h = _world("assault")
	var g := _spawn(h, ASSAULT_PLAYER + Vector2(0.0, -SHIPPED.assault_preferred_range), {}, seed)
	var corridor: Rect2 = (g.get_node("EnemyMover") as EnemyMover).constraint.inner_rect()
	var band_rect := corridor.grow((AssaultCorridorConstraint.new()).soft_band)
	var ys: PackedFloat32Array = PackedFloat32Array()
	var dir := 1.0
	var below := 0
	var outside := 0
	for _i in int(9.0 / DT):
		if h.player.global_position.x > 940.0:
			dir = -1.0
		elif h.player.global_position.x < 340.0:
			dir = 1.0
		h.player.velocity = Vector2(150.0 * dir, 0.0)
		_step(g, h.player)
		ys.append(g.global_position.y)
		if g.global_position.y >= h.player.global_position.y:
			below += 1
		if not band_rect.has_point(g.global_position):
			outside += 1
	var lo := INF
	var hi := -INF
	for y in ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
	assert_gte(hi - lo, 120.0, "seed %d: the y spread over 9 s is %.0f px" % [seed, hi - lo])
	var window := int(round(2.0 / DT))
	var flattest := INF
	for i in range(0, ys.size() - window):
		var wlo := INF
		var whi := -INF
		for j in range(i, i + window + 1):
			wlo = minf(wlo, ys[j])
			whi = maxf(whi, ys[j])
		flattest = minf(flattest, whi - wlo)
	assert_gt(flattest, 16.0, "seed %d: every 2 s window spans more than 16 px of y (flattest %.1f px)" % [seed, flattest])
	assert_eq(below, 0, "seed %d: never level with or below the player" % seed)
	assert_eq(outside, 0, "seed %d: never past the corridor's soft band" % seed)
	assert_ne(_brain(g).phase, Phase.DISENGAGE)


## Every mount's TELEGRAPH over one gunship's life, with the budget left at that tick.
func _telegraph_log(g: HeavyGunship) -> Array:
	var log: Array = []
	for part in g.modular_hull().modules():
		for mount in part.mounts():
			mount.phase_changed.connect(func(p: int) -> void:
				if p == TurretMount.Phase.TELEGRAPH:
					log.append(_brain(g).budget.remaining()))
	return log


func test_the_assault_budget_ends_in_a_measured_curved_exit() -> void:
	var h = _world("assault")
	var g := _spawn(h, ASSAULT_PLAYER + Vector2(0.0, -SHIPPED.assault_preferred_range), {"engage_seconds": SHIPPED.engage_seconds}, 3)
	var brain := _brain(g)
	var telegraphs := _telegraph_log(g)
	var disengaged_at := -1.0
	var t := 0.0
	var freed_after := -1.0
	var dir := 1.0
	for _i in int((SHIPPED.engage_seconds + 2.0 + float(_exit["seconds"])) / DT):
		if h.player.global_position.x > 900.0:
			dir = -1.0
		elif h.player.global_position.x < 380.0:
			dir = 1.0
		h.player.velocity = Vector2(120.0 * dir, 0.0)
		_step(g, h.player)
		t += DT
		if disengaged_at < 0.0 and brain.phase == Phase.DISENGAGE:
			disengaged_at = t
		if g.is_queued_for_deletion():
			freed_after = t - disengaged_at
			break
	assert_between(disengaged_at, SHIPPED.engage_seconds - DT, SHIPPED.engage_seconds + brain.attack_window() + 2.0 * DT,
			"DISENGAGE at the budget's end, deferred at most the attack window")
	assert_gt(freed_after, 0.0, "it was freed after DISENGAGE")
	assert_lte(freed_after, float(_exit["seconds"]) + 2.0 * DT, "within the measured exit (%.2f s)" % float(_exit["seconds"]))
	assert_gt(telegraphs.size(), 0, "it fought: at least one telegraph")
	for left in telegraphs:
		assert_gte(float(left), 1.05 + HeavyGunshipBrain.ATTACK_GATE_MARGIN - 1e-6, "no telegraph started with less than the window left")


## The battery telegraphs of one gunship as `[time since spawn, budget left]`, `time` counted from the budget (`engage_seconds - remaining`).
func _battery_telegraphs(g: HeavyGunship) -> Array:
	var log: Array = []
	for id in [HeavyGunshipBrain.BATTERY_PORT, HeavyGunshipBrain.BATTERY_STARBOARD]:
		for mount in g.modular_hull().mounts_of(id):
			mount.phase_changed.connect(func(p: int) -> void:
				if p == TurretMount.Phase.TELEGRAPH:
					var left := _brain(g).budget.remaining()
					log.append([g.config.engage_seconds - left, left]))
	return log


## The 1 s-budget scenario: the player straight off the port beam at the held range, so the port battery bears at once.
func _late_scenario(engage: float, bypass: bool) -> Array:
	var h = _world("assault")
	h.player.global_position = Vector2(820.0, 300.0)
	var g := _spawn(h, Vector2(400.0, 300.0), {"engage_seconds": engage}, 5)
	if bypass:
		for part in g.modular_hull().modules():
			for mount in part.mounts():
				mount.telegraph_gate = Callable()
	var log := _battery_telegraphs(g)
	for _i in int(minf(engage, 3.0) / DT) + 30:
		_tick(g)
	return [g, log]


## The 1 s boundary: the window does not fit, so no gun telegraphs, and the life ends in DISENGAGE.
func test_a_1_s_budget_never_telegraphs_and_ends_in_disengage() -> void:
	var run := _late_scenario(1.0, false)
	assert_eq((run[1] as Array).size(), 0, "no battery telegraph with 1 s of budget")
	assert_eq(_brain(run[0]).phase, Phase.DISENGAGE, "the life ends in DISENGAGE")


## Review M6, constructive: the first battery telegraph of the scenario with a long budget is at `t0`; with `engage_seconds = t0 +
## attack_window() / 2` the ungated hull telegraphs with less than the window left, and the gated one never does.
func test_the_attack_gate_refuses_a_telegraph_that_would_outlive_the_budget() -> void:
	var long_run := _late_scenario(1000.0, false)
	var first: Array = long_run[1]
	assert_gt(first.size(), 0, "precondition: the port battery telegraphs in the scenario")
	if first.is_empty():
		return
	var t0: float = (first[0] as Array)[0]
	var window := _brain(long_run[0]).attack_window()
	var engage := t0 + window / 2.0
	var ungated: Array = _late_scenario(engage, true)[1]
	var late := ungated.filter(func(e: Array) -> bool: return float(e[1]) < window + HeavyGunshipBrain.ATTACK_GATE_MARGIN)
	assert_gt(late.size(), 0, "control: ungated, the battery telegraphs at %.2f s with %.2f s left" % [t0, window / 2.0])
	var gated: Array = _late_scenario(engage, false)[1]
	assert_eq(gated.size(), 0, "gated: no telegraph that would end after the budget (%s)" % [gated])


func test_open_space_has_no_budget_so_it_never_disengages() -> void:
	var h = _world("open_space")
	var g := _spawn(h, Vector2(0.0, -SHIPPED.preferred_range), {"engage_seconds": SHIPPED.engage_seconds})
	for _i in int(12.0 / DT):
		_tick(g)
		assert_ne(_brain(g).phase, Phase.DISENGAGE)
	assert_false(g.is_queued_for_deletion())


func test_the_measured_assault_exit_is_printed_and_bounded() -> void:
	gut.p("heavy gunship exit: worst %.2f s from %s, %d runs, %d capped (probe %.2f s wall)" % [_exit["seconds"], _exit["start"], _exit["runs"],
			_exit["capped"], _probe_s])
	assert_eq(int(_exit["runs"]), 2166, "every corridor start at break_speed and 10 px/s")
	assert_eq(int(_exit["capped"]), 0, "no run hit the cap")
	assert_gt(float(_exit["seconds"]), 0.0)
	# Review M8, §2.4.3 / §2.16: the budget was derived from the Cloud Descent window, so the measured exit must fit it.
	var window := engage_life_window()
	assert_lt(window, CLOUD_DESCENT_WINDOW, "engage %.1f + attack window + exit %.2f + margin %.1f = %.2f s < %.1f s (margin %.2f s)" % [SHIPPED.engage_seconds,
			float(_exit["seconds"]), DEADLINE_MARGIN, window, CLOUD_DESCENT_WINDOW, CLOUD_DESCENT_WINDOW - window])


## `engage_seconds + attack_window() + measured exit + MARGIN` at full strength (the heavy cannon's 1.05 s window).
func engage_life_window() -> float:
	var h = _world("assault")
	var g := _spawn(h, ASSAULT_PLAYER + Vector2(0.0, -400.0))
	return SHIPPED.engage_seconds + _brain(g).attack_window() + float(_exit["seconds"]) + DEADLINE_MARGIN


func test_the_exit_key_is_built_once_and_the_hook_changes_nothing() -> void:
	var before: int = PROBE.measured
	assert_eq(PH10.heavy_gunship_exit(self), _exit, "the same figure")
	assert_eq(PROBE.measured, before, "a second call is a memo hit")
	var hook_a: Callable = PH10.prepare_probe
	var hook_b: Callable = PH10.prepare_probe
	assert_true(hook_a == hook_b and hook_a.hash() == hook_b.hash(), "the static hook is one Callable on every reference")
	var h = HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = PROBE.MID_VIEW + Vector2(0.0, 300.0)
	# A corner start at break_speed, and the worst start (the view centre heading right at 10 px/s).
	var starts := [[PROBE.MID_VIEW + Vector2(-720.0, -720.0), Vector2(1.0, 1.0).normalized() * SHIPPED.break_speed],
			[PROBE.MID_VIEW, Vector2.RIGHT * PH10.SLOW_START]]
	for s: Array in starts:
		h.player.add_to_group(&"player")
		var plain: float = PROBE.disengage_seconds(h.root, SCENE, Phase.DISENGAGE, s[0], s[1], PH10.CAP)
		assert_true(h.player.is_in_group(&"player"), "precondition: without the hook the stub is a player")
		var hooked: float = PROBE.disengage_seconds(h.root, SCENE, Phase.DISENGAGE, s[0], s[1], PH10.CAP, PH10.prepare_probe)
		assert_false(h.player.is_in_group(&"player"), "the hook took the stub out of group player")
		assert_eq(hooked, plain, "bit-identical exit from %s with the parts, sprite, contact box, light and body shape stripped" % [s[0]])


## No test builds a Ph10 probe call by hand: every `worst_disengage(` naming `HeavyGunshipBrain` lives in `ph10_exit_keys.gd`.
func test_no_test_hand_builds_a_ph10_probe_call() -> void:
	var calls := 0
	var flagged: Array = []
	for path: String in _scripts("res://tests"):
		if path == "res://tests/helpers/ph10_exit_keys.gd":
			continue
		var source := FileAccess.get_file_as_string(path)
		if not source.contains("worst_disengage("):
			continue  # no call to read: a file without the text has nothing the comment-stripping parse could find
		var found := _ph10_probe_calls(source)
		calls += int(found["calls"])
		for args: String in found["flagged"]:
			flagged.append("%s: %s" % [path, args.strip_edges()])
	assert_gte(calls, 10, "the sweep reads the known calls")
	assert_eq(flagged, [], "no worst_disengage( call outside ph10_exit_keys.gd names the Heavy Gunship's brain")
	var synthetic := "var r := SpecialistExitProbe.worst_disengage(self, load(P),\n\tHeavyGunshipBrain.Phase.DISENGAGE, s, 20.0, c, hook)"
	assert_eq((_ph10_probe_calls(synthetic)["flagged"] as Array).size(), 1, "boundary: the sweep fires on a hand-built probe")


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


## `{calls, flagged}`: each line stripped of comments and string contents, then each `worst_disengage(` call's argument text up to its matching
## `)` checked for the Heavy Gunship's brain (the `test_hacker_frigate.gd` sweep's shape).
static func _ph10_probe_calls(source: String) -> Dictionary:
	var lines := PackedStringArray()
	for line in source.split("\n"):
		lines.append(SINGLE_WRITER._code_only(line))
	var code := "\n".join(lines)
	var calls := 0
	var flagged: Array = []
	var at := code.find("worst_disengage(")
	while at >= 0:
		calls += 1
		var open := at + "worst_disengage".length()
		var depth := 0
		var close := code.length()
		for i in range(open, code.length()):
			if code[i] == "(":
				depth += 1
			elif code[i] == ")":
				depth -= 1
				if depth == 0:
					close = i
					break
		var args := code.substr(open, close - open + 1)
		if args.contains("HeavyGunshipBrain"):
			flagged.append(args)
		at = code.find("worst_disengage(", close)
	return {"calls": calls, "flagged": flagged}


## §2.4.3: the three Assault-only assumptions are gone. The gunship's scripts read no camera or viewport rect, define no `_physics_process` of
## their own and run no `Timer` (the brain's clocks are its tick).
func test_no_camera_hold_no_own_physics_process_no_timer() -> void:
	for path in ["res://assault/scenes/enemies/heavy_gunship/heavy_gunship.gd", "res://assault/scenes/enemies/heavy_gunship/heavy_gunship_brain.gd"]:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			code += SINGLE_WRITER._code_only(line) + "\n"
		for banned in ["get_camera_2d", "get_visible_rect", "func _physics_process", "Timer"]:
			assert_false(code.contains(banned), "%s uses %s" % [path.get_file(), banned])


# ── Fire ─────────────────────────────────────────────────────────────────────────────────────────

func test_the_port_battery_fires_at_a_player_off_its_beam_and_the_rear_missiles_stay_closed() -> void:
	var h = _world("open_space")
	var g := _spawn(h, Vector2.ZERO)
	h.player.global_position = Vector2(SHIPPED.preferred_range, 0.0)
	var counts := {}
	for part in g.modular_hull().modules():
		for mount in part.mounts():
			counts[part.module_id] = _count(mount.round_fired)
	var first_port := -1.0
	for i in int(20.0 / DT):
		_tick(g)
		if first_port < 0.0 and (counts[&"battery_port"] as Array[int])[0] > 0:
			first_port = i * DT
	assert_between(first_port, 0.0, 4.0, "the port battery fires within 4 s (first round at %.2f s)" % first_port)
	assert_eq((counts[&"missiles"] as Array[int])[0], 0, "the rear missiles stay closed outside EMERGENCY")


# ── Hub idle ─────────────────────────────────────────────────────────────────────────────────────

func test_the_hub_idle_patrols_notices_fights_and_goes_home() -> void:
	var h = _world("open_space")
	var anchor := Vector2(500.0, -400.0)
	h.player.global_position = anchor + Vector2(0.0, 5000.0)
	var g := _spawn(h, anchor + Vector2(SHIPPED.idle_radius, 0.0), {}, 1, false)
	var brain := _brain(g)
	brain.patrol_anchor = anchor
	var worst := 0.0
	for i in int(10.0 / DT):
		_tick(g)
		assert_eq(brain.phase, Phase.IDLE)
		if i >= int(3.0 / DT):
			worst = maxf(worst, absf(g.global_position.distance_to(anchor) - SHIPPED.idle_radius))
	assert_lte(worst, 40.0, "it rides its %.0f px ring (worst %.1f px off it)" % [SHIPPED.idle_radius, worst])
	h.player.global_position = g.global_position + Vector2(0.0, SHIPPED.perceive_radius - 100.0)
	var seen: Array[int] = []
	for _i in int(2.0 / DT):
		_tick(g)
		if seen.is_empty() or seen[-1] != brain.phase:
			seen.append(brain.phase)
	assert_eq(seen.slice(0, 2), [Phase.NOTICING, Phase.APPROACH], "a beat of NOTICING, then the fight (%s)" % [seen])
	for _i in int(4.0 / DT):
		_tick(g)
	assert_gt(g.global_position.distance_to(anchor), SHIPPED.idle_radius + 50.0, "precondition: the fight took it off its ring")
	# Straight on past lose_radius from wherever the fight took it, on the far side from the anchor (so the way home leads away from the player).
	h.player.global_position = g.global_position + (g.global_position - anchor).normalized() * (SHIPPED.lose_radius + 400.0)
	var saw_returning := false
	var home := false
	for _i in int(30.0 / DT):
		_tick(g)
		saw_returning = saw_returning or brain.phase == Phase.RETURNING
		if brain.phase == Phase.IDLE:
			home = true
			break
	assert_true(saw_returning, "beyond lose_radius it goes home")
	assert_true(home, "and patrols again")


# ── EMP, rails and the view (review M3, M4) ─────────────────────────────────────────────────────

## Rounds fired by every mount of [param g], counted in [code][0][/code].
func _rounds(g: HeavyGunship) -> Array[int]:
	var n: Array[int] = [0]
	for part in g.modular_hull().modules():
		for mount in part.mounts():
			mount.round_fired.connect(func(_p: Node2D) -> void: n[0] += 1)
	return n


func _light(g: HeavyGunship) -> int:
	return (g.get_node("StateLight") as StateLight).get_state()


func _any_mount_in(g: HeavyGunship, p: int) -> bool:
	for part in g.modular_hull().modules():
		for mount in part.mounts():
			if mount.phase() == p:
				return true
	return false


## The player straight off the port beam at the held range (rotation 0: port is +x), so the port battery bears at once.
func _beam_scenario(h) -> HeavyGunship:
	var held := SHIPPED.assault_preferred_range if h.is_assault else SHIPPED.preferred_range
	var at := Vector2(400.0, 300.0) if h.is_assault else Vector2.ZERO
	h.player.global_position = at + Vector2(held, 0.0)
	return _spawn(h, at)


## An EMP during a battery TELEGRAPH cancels it: no round from any mount for the window and the light OFF; the battery fires again after.
func test_an_emp_cancels_a_shown_telegraph_and_the_battery_fires_again_after(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _beam_scenario(h)
	var battery: TurretMount = g.modular_hull().mounts_of(HeavyGunshipBrain.BATTERY_PORT)[0]
	var guard := 0
	while battery.phase() != TurretMount.Phase.TELEGRAPH and guard < int(4.0 / DT):
		_tick(g)
		guard += 1
	assert_eq(battery.phase(), TurretMount.Phase.TELEGRAPH, "%s: precondition: the port battery telegraphs" % mode)
	assert_eq(_light(g), StateLight.State.CHARGING, "%s: precondition: the light shows it" % mode)
	var rounds := _rounds(g)
	g.apply_emp(2.0, null)
	assert_eq(_light(g), StateLight.State.OFF, "%s: the EMP turned the light off" % mode)
	assert_false(_any_mount_in(g, TurretMount.Phase.TELEGRAPH), "%s: no telegraph survives the EMP" % mode)
	for _i in int(1.9 / DT):
		_tick(g)
		assert_eq(_light(g), StateLight.State.OFF)
	assert_eq(rounds[0], 0, "%s: nothing fired in the window" % mode)
	for _i in int(4.0 / DT):
		_tick(g)
	assert_gt(rounds[0], 0, "%s: it fights again after the window" % mode)


## A railed heavy (level 2, and level 1's Cloud Descent rows until t11) rides and fires nothing, its light OFF.
func test_a_railed_heavy_fires_nothing_and_shows_no_light(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _beam_scenario(h)
	for _i in 6:
		_tick(g)
	var rounds := _rounds(g)
	g.suspend_ai()
	for _i in int(5.0 / DT):
		_tick(g)
	assert_eq(rounds[0], 0, "%s: a suspended heavy never fires" % mode)
	assert_eq(_light(g), StateLight.State.OFF, "%s: and shows no light" % mode)
	assert_false(_any_mount_in(g, TurretMount.Phase.TELEGRAPH), "%s: and shows no telegraph" % mode)


## Review M4, the turret rule: in Assault a hull held above the view never starts a telegraph, though the player is inside the cannon's arc and
## range. Control: the same hull held just inside the view's top edge does.
func test_in_assault_it_never_opens_fire_from_outside_the_view() -> void:
	for y in [-200.0, 20.0]:
		var h = _world("assault")
		var at := Vector2(640.0, y)
		var g := _spawn(h, at)
		assert_lt(at.distance_to(h.player.global_position), 900.0, "precondition: in the heavy cannon's range")
		var log := _telegraph_log(g)
		for _i in int(3.0 / DT):
			_tick(g)
			g.global_position = at
		if y < 0.0:
			assert_eq(log.size(), 0, "above the view: no telegraph in 3 s")
		else:
			assert_gt(log.size(), 0, "control: inside the view the cannon telegraphs")


## Review M2 (N10), measured for t11: the deep_space 3.5 s heavy from its real spawn point (read from the director through the replay helper,
## placed by `WaveManager`'s formula: camera centre + offset x WORLD_SCALE) against the replays' player stub. Its first battery FIRE lands
## inside the 9 s budget; the time is printed and recorded in DECISIONS.
func test_the_deep_space_heavy_fires_a_battery_inside_its_budget() -> void:
	var rows: Array = REPLAY.placed(WaveBuilder.HEAVY_GUNSHIP).filter(func(r: Dictionary) -> bool: return r["section"] == &"deep_space")
	assert_eq(rows.size(), 1, "one deep_space heavy")
	if rows.is_empty():
		return
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	h.player.global_position = cam.global_position + REPLAY.PLAYER_OFFSET
	var spawn: Vector2 = cam.global_position + cam.offset + (rows[0]["offset"] as Vector2) * ArenaCamera.WORLD_SCALE
	var g := _spawn(h, spawn, {"engage_seconds": SHIPPED.engage_seconds})
	var fired := [-1.0]
	var t := [0.0]
	for id in [HeavyGunshipBrain.BATTERY_PORT, HeavyGunshipBrain.BATTERY_STARBOARD]:
		for mount in g.modular_hull().mounts_of(id):
			mount.phase_changed.connect(func(p: int) -> void:
				if p == TurretMount.Phase.FIRE and fired[0] < 0.0:
					fired[0] = t[0])
	while t[0] < SHIPPED.engage_seconds and fired[0] < 0.0:
		_tick(g)
		t[0] += DT
	gut.p("deep_space heavy from %s: first battery FIRE at %.2f s of a %.1f s budget" % [spawn, fired[0], SHIPPED.engage_seconds])
	assert_between(fired[0], 0.0, SHIPPED.engage_seconds, "a battery fires inside the budget")


# ── Phases (t5): hull bands, heat and VENT, weak points, EMERGENCY, rear missiles, the cannon shield ─────────────────────────────
# Task plan docs/plans/cmwafsrb400abqs2yt38khcyu/3-plan.md (rows numbered as there). Long hand-ticked scenarios run once per harness and are
# shared by several rows (`_heat_run`, `_emergency_run`; tests/README.md -> Gate time rule 2: plain data only).

## The t5 config fields' §2.16 values, in the order `test_the_config_is_applied_and_carries_the_plan_values` reads them.
const T5_CONFIG := [0.6, 0.3, 4, 2.2, 0.6, 5.0, 420.0, 0.9, 2.0, 200.0, 800.0, 120.0, 120.0, 60, 2.0, 4.0, 5.0]
## The heat run's player: still, at this hull-local bearing (degrees; 0 = port, 90 = the nose) and distance.
const HEAT_BEARING_DEG := 67.5
const HEAT_RANGE := 420.0
## The emergency run's player distance (px): inside the batteries' ≈ 770 px and the pod's 900 px reach.
const PURSUIT_RANGE := 450.0

var _heat_runs: Dictionary = {}
var _emergency_runs: Dictionary = {}


## Where the hand-ticked phase rows hold the hull: the Open Space origin, or a point inside the Assault view.
func _held_at(h) -> Vector2:
	return Vector2(560.0, 200.0) if h.is_assault else Vector2.ZERO


## One tick with the hull held: position, rotation and velocity written back.
func _held_tick(g: HeavyGunship, at: Vector2, rot: float) -> void:
	_tick(g)
	g.global_position = at
	g.rotation = rot
	g.velocity = Vector2.ZERO


## A hand-ticked `move_and_slide()` (outside a physics frame) moves the hull by the last IDLE frame's delta. `_tick` overwrites the position,
## but the mover turns the hull toward its face point from the moved position, so a boost seen through a long idle delta swings the hull off its
## broadside. Every row with a boost whose facing matters starts here: the engine clock is slowed to `_FROZEN_TIME_SCALE` (restored by
## `after_each`) and one frame awaited, so the idle delta is ≈ 0 however long the machine's frames are. Waiting for a short frame instead (the
## first version: up to 5 frames until one was ≤ 1/60 s) left the rows to the machine's speed: a 0.14 s idle delta, the engine's ceiling,
## failed 6 rear-missile rows. The rows that call this await no physics frame afterwards (frozen, none would come).
func _fresh_idle_delta() -> void:
	if not _idle_frozen:
		_idle_frozen = true
		_saved_idle_time_scale = Engine.time_scale
		Engine.time_scale = _saved_idle_time_scale * _FROZEN_TIME_SCALE
	await get_tree().process_frame


func _thaw_idle_clock() -> void:
	if not _idle_frozen:
		return
	_idle_frozen = false
	Engine.time_scale = _saved_idle_time_scale


## Every mount's phase entries and rounds, stamped with `tick[0]` (the caller advances it): `phases` [tick, id, phase], `rounds` [tick, id,
## scene path, speed].
func _phase_log(g: HeavyGunship) -> Dictionary:
	var log := {"tick": [0], "phases": [], "rounds": []}
	var tick: Array = log["tick"]
	var phases: Array = log["phases"]
	var rounds: Array = log["rounds"]
	for part in g.modular_hull().modules():
		var id := part.module_id
		for mount in part.mounts():
			mount.phase_changed.connect(func(p: int) -> void: phases.append([tick[0], id, p]))
			mount.round_fired.connect(func(r: Node2D) -> void: rounds.append([tick[0], id, r.scene_file_path, r.get(&"speed")]))
	return log


func _is_gun(id: StringName) -> bool:
	return id in HeavyGunshipBrain.GUN_PARTS


## [phase, hull_phase, heat, vent_port open, vent_starboard open, max_speed, hull light, 6 part lights (tree order), 4 mount phases (tree order)].
func _snapshot(g: HeavyGunship, brain: HeavyGunshipBrain, mover: EnemyMover) -> Array:
	var row: Array = [brain.phase, brain.hull_phase, brain.heat, _part(g, &"vent_port").is_vulnerable(),
			_part(g, &"vent_starboard").is_vulnerable(), mover.max_speed, _light(g)]
	for part in g.modular_hull().modules():
		row.append((part.get_node("Light") as StateLight).get_state())
	for part in g.modular_hull().modules():
		for mount in part.mounts():
			row.append(mount.phase())
	return row


## The heat run (rows 1-5, memo per mode). The hull held at `_held_at()` with rotation 0, the player still at hull-local bearing 67.5 degrees
## 420 px out, so the port battery (±80 about +x) and the cannon (55 - 125) both bear. Phase A at full health until 4 gun bursts have ended
## (cap 15 s); then the bar is set to 400 (57 %, OVERHEAT); phase B until 3.5 s after the first VENT ends (cap 24 s).
func _heat_run(mode: String) -> Dictionary:
	if _heat_runs.has(mode):
		return _heat_runs[mode]
	var h = _world(mode)
	var at := _held_at(h)
	h.player.global_position = at + Vector2.RIGHT.rotated(deg_to_rad(HEAT_BEARING_DEG)) * HEAT_RANGE
	var g := _spawn(h, at)
	var brain := _brain(g)
	var mover := g.get_node("EnemyMover") as EnemyMover
	var log := _phase_log(g)
	var tick: Array = log["tick"]
	var snaps: Array = []
	var b_start := -1
	var vent_in := -1
	var vent_out := -1
	var a_cap := int(round(15.0 / DT))
	var b_cap := int(round(24.0 / DT))
	var i := 0
	while true:
		if b_start < 0:
			var ends := (log["phases"] as Array).filter(func(e: Array) -> bool: return _is_gun(e[1]) and e[2] == TurretMount.Phase.COOLDOWN)
			if ends.size() >= 4 or i >= a_cap:
				b_start = i
				g.health.set_health(400)
		elif i - b_start >= b_cap or (vent_out >= 0 and i - vent_out >= int(round(3.5 / DT))):
			break
		tick[0] = i
		_held_tick(g, at, 0.0)
		var row := _snapshot(g, brain, mover)
		snaps.append(row)
		if vent_in < 0 and row[0] == Phase.VENT:
			vent_in = i
		elif vent_in >= 0 and vent_out < 0 and row[0] != Phase.VENT:
			vent_out = i
		i += 1
	var run := {"b_start": b_start, "vent_in": vent_in, "vent_out": vent_out, "snaps": snaps, "phases": log["phases"], "rounds": log["rounds"]}
	_heat_runs[mode] = run
	return run


## Burst ends (a gun mount entering COOLDOWN) as ticks, from [param from] on.
func _burst_end_ticks(run: Dictionary, from: int) -> Array:
	var out: Array = []
	for e in run["phases"]:
		if e[0] >= from and _is_gun(e[1]) and e[2] == TurretMount.Phase.COOLDOWN:
			out.append(e[0])
	return out


func test_heat_builds_only_in_overheat_and_the_fourth_burst_vents(mode: String = use_parameters(MODES)) -> void:
	var run := _heat_run(mode)
	var b_start: int = run["b_start"]
	var snaps: Array = run["snaps"]
	assert_gte(_burst_end_ticks(run, 0).filter(func(t: int) -> bool: return t < b_start).size(), 4,
			"%s: phase A: 4 gun bursts ended at full health" % mode)
	for k in b_start:
		var row: Array = snaps[k]
		if row[1] != HeavyGunshipBrain.HullPhase.CONTROLLED or row[2] != 0 or row[0] == Phase.VENT:
			fail_test("%s: tick %d of phase A: hull phase %d, heat %d, phase %d" % [mode, k, row[1], row[2], row[0]])
			return
	assert_eq((snaps[b_start] as Array)[1], HeavyGunshipBrain.HullPhase.OVERHEAT, "%s: 400 / 700 reads OVERHEAT on the next tick" % mode)
	var ends := _burst_end_ticks(run, b_start)
	assert_gte(ends.size(), 4, "%s: phase B: 4 bursts ended in OVERHEAT" % mode)
	var vent_in: int = run["vent_in"]
	var vent_out: int = run["vent_out"]
	assert_gte(vent_in, 0, "%s: it vented" % mode)
	if ends.size() < 4 or vent_in < 0:
		return
	assert_eq(vent_in, ends[3], "%s: VENT on the tick of the 4th burst end in OVERHEAT (tick %d)" % [mode, ends[3]])
	assert_eq((snaps[vent_in] as Array)[2], 0, "%s: heat back to 0 on VENT entry" % mode)
	assert_gt(vent_out, vent_in, "%s: VENT ended" % mode)
	assert_almost_eq(float(vent_out - vent_in) * DT, SHIPPED.vent_seconds, DT + 1e-6, "%s: VENT lasts vent_seconds" % mode)


func test_venting_starts_no_burst_and_fires_again_after(mode: String = use_parameters(MODES)) -> void:
	var run := _heat_run(mode)
	var vent_in: int = run["vent_in"]
	var vent_out: int = run["vent_out"]
	assert_gt(vent_out, vent_in, "%s: precondition: a whole VENT" % mode)
	if vent_out <= vent_in or vent_in < 0:
		return
	# The bursts already firing at VENT entry: their mounts' FIRE ends.
	var entry: Array = (run["snaps"] as Array)[vent_in]
	var firing: Array[int] = []
	for k in 4:
		if entry[13 + k] == TurretMount.Phase.FIRE:
			firing.append(k)
	var mount_ids: Array = []
	for row in PARTS:
		if MOUNTS.has(row[0]):
			mount_ids.append(row[0])
	var settled := vent_in
	for e in run["phases"]:
		if e[0] > vent_in and e[2] == TurretMount.Phase.COOLDOWN and mount_ids.find(e[1]) in firing:
			settled = maxi(settled, e[0])
	for e in run["phases"]:
		if e[0] > vent_in and e[0] < vent_out:
			assert_false(e[2] == TurretMount.Phase.TELEGRAPH or e[2] == TurretMount.Phase.FIRE,
					"%s: no TELEGRAPH / FIRE entry while venting (%s at tick %d)" % [mode, e[1], e[0]])
	for r in run["rounds"]:
		if r[0] > settled and r[0] < vent_out:
			fail_test("%s: a round from %s at tick %d, after the started bursts ended (%d) and before VENT ended (%d)" % [mode, r[1], r[0], settled, vent_out])
		elif r[0] > vent_in and r[0] <= settled:
			assert_true(mount_ids.find(r[1]) in firing, "%s: only a burst already firing at VENT entry fires on (%s)" % [mode, r[1]])
	var again := (run["phases"] as Array).filter(func(e: Array) -> bool:
		return e[0] >= vent_out and e[0] <= vent_out + int(round(3.5 / DT)) and _is_gun(e[1]) and e[2] == TurretMount.Phase.TELEGRAPH)
	assert_gt(again.size(), 0, "%s: control: a gun telegraphs again within 3.5 s of VENT's end" % mode)


func test_the_vents_open_glow_and_slow_the_hull_only_while_venting(mode: String = use_parameters(MODES)) -> void:
	var run := _heat_run(mode)
	var bad := ""
	var venting := 0
	for k in (run["snaps"] as Array).size():
		var row: Array = run["snaps"][k]
		var vent: bool = row[0] == Phase.VENT
		venting += 1 if vent else 0
		var light_want := StateLight.State.VENTING if vent else StateLight.State.OFF
		if row[3] != vent or row[4] != vent or row[7 + 4] != light_want or row[7 + 5] != light_want:
			bad = "tick %d: phase %d, vents open %s / %s, lights %d / %d" % [k, row[0], row[3], row[4], row[11], row[12]]
			break
		var speed: float = SHIPPED.max_speed * (SHIPPED.vent_speed_factor if vent else 1.0)
		if not is_equal_approx(row[5], speed):
			bad = "tick %d: max_speed %.2f, want %.2f" % [k, row[5], speed]
			break
	assert_eq(bad, "", "%s: the vents are open, orange and the hull slowed exactly while it vents" % mode)
	assert_gt(venting, 0, "%s: precondition: it vented" % mode)
	assert_almost_eq(SHIPPED.max_speed * SHIPPED.vent_speed_factor, 84.0, 1e-6)


func test_a_gun_parts_light_is_yellow_exactly_while_its_mount_charges(mode: String = use_parameters(MODES)) -> void:
	var run := _heat_run(mode)
	var bad := ""
	var charging := 0
	for k in (run["snaps"] as Array).size():
		var row: Array = run["snaps"][k]
		# Weapon parts 0..3 own mounts 0..3 (tree order).
		var hull_want := StateLight.State.OFF
		for m in 4:
			var mp: int = row[13 + m]
			var want := StateLight.State.CHARGING if mp == TurretMount.Phase.TELEGRAPH else StateLight.State.OFF
			charging += 1 if want == StateLight.State.CHARGING else 0
			if row[7 + m] != want:
				bad = "tick %d: part %d light %d, mount phase %d" % [k, m, row[7 + m], mp]
			if m < 3:  # the hull light reads the guns outside EMERGENCY
				if mp == TurretMount.Phase.TELEGRAPH:
					hull_want = StateLight.State.CHARGING
				elif hull_want != StateLight.State.CHARGING and mp in [TurretMount.Phase.TRACK, TurretMount.Phase.FIRE, TurretMount.Phase.COOLDOWN]:
					hull_want = StateLight.State.ARMED
		if bad == "" and row[6] != hull_want:
			bad = "tick %d: hull light %d, want %d" % [k, row[6], hull_want]
		if bad != "":
			break
	assert_eq(bad, "", "%s: each weapon part's light is CHARGING exactly while its mount telegraphs; the hull light keeps t4's mapping" % mode)
	assert_gt(charging, 0, "%s: precondition: a mount telegraphed" % mode)


func test_the_cannon_fires_heavy_shells_at_220_px_s(mode: String = use_parameters(MODES)) -> void:
	var run := _heat_run(mode)
	var shells := (run["rounds"] as Array).filter(func(r: Array) -> bool: return r[1] == HeavyGunshipBrain.CANNON)
	assert_gt(shells.size(), 0, "%s: the cannon fired" % mode)
	for r in shells:
		assert_eq(r[2], EnemyRounds.HEAVY_SHELL.resource_path, "%s: a Heavy Shell" % mode)
		assert_almost_eq(float(r[3]), 220.0, 1e-3, "%s: at 220 px/s" % mode)


## Row 6: VENT forced while the port battery is firing its first burst.
func test_a_burst_firing_when_vent_starts_finishes_all_its_rounds(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var at := _held_at(h)
	h.player.global_position = at + Vector2.RIGHT.rotated(deg_to_rad(HEAT_BEARING_DEG)) * HEAT_RANGE
	var g := _spawn(h, at)
	var brain := _brain(g)
	var log := _phase_log(g)
	var tick: Array = log["tick"]
	var port: TurretMount = g.modular_hull().mounts_of(HeavyGunshipBrain.BATTERY_PORT)[0]
	var i := 0
	while i < int(6.0 / DT) and (log["rounds"] as Array).filter(func(r: Array) -> bool: return r[1] == HeavyGunshipBrain.BATTERY_PORT).is_empty():
		tick[0] = i
		_held_tick(g, at, 0.0)
		i += 1
	var first := i - 1
	assert_eq(port.phase(), TurretMount.Phase.FIRE, "%s: precondition: the port battery is firing its first burst" % mode)
	var telegraphing: Array[TurretMount] = []
	for part in g.modular_hull().modules():
		for mount in part.mounts():
			if mount.phase() == TurretMount.Phase.TELEGRAPH:
				telegraphing.append(mount)
	var tel_rounds: Array[int] = [0]
	for mount in telegraphing:
		mount.round_fired.connect(func(_r: Node2D) -> void: tel_rounds[0] += 1)
	brain.enter_phase(Phase.VENT)
	var forced := i
	tick[0] = i
	_held_tick(g, at, 0.0)
	i += 1
	for mount in telegraphing:
		assert_eq(mount.phase(), TurretMount.Phase.TRACK, "%s: a charge in progress at VENT entry is cancelled" % mode)
	while brain.phase == Phase.VENT and i < forced + int(3.0 / DT):
		tick[0] = i
		_held_tick(g, at, 0.0)
		i += 1
	assert_ne(brain.phase, Phase.VENT, "%s: VENT ended" % mode)
	var vent_out := i - 1
	var port_rounds := (log["rounds"] as Array).filter(func(r: Array) -> bool: return r[1] == HeavyGunshipBrain.BATTERY_PORT and r[0] <= vent_out)
	assert_eq(port_rounds.size(), port.get(&"burst_count"), "%s: the started burst fired all its rounds" % mode)
	var port_end := -1
	for e in log["phases"]:
		if e[0] >= first and e[1] == HeavyGunshipBrain.BATTERY_PORT and e[2] == TurretMount.Phase.COOLDOWN:
			port_end = e[0]
			break
	var burst_s := (float(port.get(&"burst_count")) - 1.0) * float(port.get(&"burst_gap"))
	assert_almost_eq(float(port_end - first) * DT, burst_s, DT + 1e-6, "%s: its FIRE ended on the burst clock" % mode)
	for e in log["phases"]:
		if e[0] >= forced and e[0] < vent_out:
			assert_false(e[2] == TurretMount.Phase.TELEGRAPH or e[2] == TurretMount.Phase.FIRE,
					"%s: nothing starts while venting (%s at tick %d)" % [mode, e[1], e[0]])
	for r in log["rounds"]:
		if r[0] > port_end and r[0] < vent_out:
			fail_test("%s: a round from %s at tick %d during VENT" % [mode, r[1], r[0]])
	assert_eq(tel_rounds[0], 0, "%s: the cancelled charge fired nothing" % mode)


## Row 7.
func test_hull_bands_are_read_off_the_bar_and_never_step_back(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, _held_at(h))
	var brain := _brain(g)
	var bands: Array = []
	brain.hull_phase_changed.connect(func(p: int) -> void: bands.append(p))
	var C := HeavyGunshipBrain.HullPhase.CONTROLLED
	var O := HeavyGunshipBrain.HullPhase.OVERHEAT
	var E := HeavyGunshipBrain.HullPhase.EMERGENCY
	for row in [[427, C], [420, C], [419, O], [413, O], [210, O], [209, E], [203, E]]:
		g.health.set_health(row[0])
		_tick(g)
		assert_eq(brain.hull_phase, row[1], "%s: %d / 700 reads band %d" % [mode, row[0], row[1]])
	assert_eq(g.repair(490 - 203), 490 - 203, "%s: precondition: a Support Ship's repair lands" % mode)
	_tick(g)
	assert_eq(brain.hull_phase, E, "%s: 490 / 700 after a repair: still EMERGENCY (one way)" % mode)
	assert_eq(brain.phase, Phase.EMERGENCY, "%s: and the brain still fights in EMERGENCY" % mode)
	assert_eq(bands, [O, E], "%s: one signal per band entered" % mode)
	var g2 := _spawn(h, _held_at(h) + Vector2(300.0, 0.0))
	var bands2: Array = []
	_brain(g2).hull_phase_changed.connect(func(p: int) -> void: bands2.append(p))
	_tick(g2)
	g2.health.set_health(100)
	_tick(g2)
	_tick(g2)
	assert_eq(bands2, [E], "%s: 700 -> 100 in one hit enters EMERGENCY with one signal" % mode)


## Row 8 (real physics, 16x, the hull still): a bullet through `VentPort`'s edge.
func test_a_shot_into_a_vent_hurts_the_hull_twice_only_while_it_vents(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, TARGET_AT)
	var brain := _brain(g)
	_scale_clock()
	await _frames(2)
	var vent := _part(g, &"vent_port")
	var hits := _count(vent.damaged)
	var pings := _count(vent.deflected)
	var probe := BULLET_SCENE.instantiate() as Node
	var damage := (probe.get_node("HitBox") as HitBox).damage
	probe.free()
	var normal := Vector2.RIGHT.rotated(g.rotation)
	var cases := [["closed", false, damage, 0, 1], ["open", true, 2 * damage, 1, 1], ["closed again", false, damage, 1, 2]]
	for c in cases:
		if c[1]:
			brain.enter_phase(Phase.VENT)
		elif brain.phase == Phase.VENT:
			brain.enter_phase(Phase.BROADSIDE)
		assert_eq(vent.is_vulnerable(), c[1], "%s: precondition: the vent is %s" % [mode, c[0]])
		var hp := g.health.current_health
		var b := _fire(h.root, BULLET_SCENE, vent.homing_point(), normal)
		await _until_spent(b, 20)
		assert_false(is_instance_valid(b) and not b.is_queued_for_deletion(), "%s: %s: the shot was consumed" % [mode, c[0]])
		assert_eq(hp - g.health.current_health, c[2], "%s: %s vent: the hull loses %d" % [mode, c[0], c[2]])
		assert_eq(hits[0], c[3], "%s: %s vent: damaged count" % [mode, c[0]])
		assert_eq(pings[0], c[4], "%s: %s vent: deflected count" % [mode, c[0]])


## A beam rig: `BeamBehavior.tick()` reads only `state.actor`, the actor's rotation and the world.
class BeamRig extends Node2D:
	var actor: Node2D


## Row 9: `BeamBehavior.tick()` called by hand along the vents' line (hull-local y -34, from the port side), then one nova.
func test_the_beam_and_the_nova_never_reach_a_closed_vent(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var at := _held_at(h)
	var g := _spawn(h, at)
	var brain := _brain(g)
	var rig := BeamRig.new()
	rig.actor = rig
	h.root.add_child(rig)
	rig.global_position = at + Vector2(300.0, -34.0)
	rig.rotation = -PI / 2.0  # `Vector2.UP.rotated(rotation)` = -x: across the hull, port to starboard
	var muzzle := Marker2D.new()
	rig.add_child(muzzle)
	var muzzles: Array[Marker2D] = [muzzle]
	var behavior := BeamBehavior.new()
	var vents := [_part(g, &"vent_port"), _part(g, &"vent_starboard")]
	var pings := [_count(vents[0].deflected), _count(vents[1].deflected)]
	var hits := [_count(vents[0].damaged), _count(vents[1].damaged)]
	var hp := g.health.current_health
	for _i in int(2.0 / DT):
		behavior.tick(rig, LASER_MODE, muzzles, DT)
	assert_gt(pings[0][0], 0, "%s: the beam pings the closed port vent" % mode)
	assert_gt(pings[1][0], 0, "%s: and the starboard one" % mode)
	assert_eq([hits[0][0], hits[1][0]], [0, 0], "%s: no damage reaches a closed vent" % mode)
	assert_eq(g.health.current_health, hp, "%s: and nothing is forwarded to the hull" % mode)
	# One nova: the hull's own hit, the four weapon parts', and a ping from each closed vent.
	var part_hp := {}
	for part in g.modular_hull().modules():
		if part.health != null:
			part_hp[part.module_id] = part.health.current_health
	var pinged := [pings[0][0], pings[1][0]]
	var before := get_tree().root.get_children()
	assert_true(PlasmaNovaModule.new().try_activate(h.player), "%s: the nova fires" % mode)
	for child in get_tree().root.get_children():
		if child not in before:
			child.free()  # the nova's full-screen flash layer and its tween
	assert_eq(hp - g.health.current_health, 50, "%s: the nova hurts the hull by its own hit only" % mode)
	assert_eq([pings[0][0] - pinged[0], pings[1][0] - pinged[1]], [1, 1], "%s: each closed vent pinged once" % mode)
	assert_eq([hits[0][0], hits[1][0]], [0, 0], "%s: and took nothing" % mode)
	for id in part_hp:
		assert_eq(part_hp[id] - _part(g, id).health.current_health, 50, "%s: %s took the nova" % [mode, id])
	# Control: an open vent burns and forwards.
	brain.enter_phase(Phase.VENT)
	hp = g.health.current_health
	for _i in int(0.5 / DT):
		behavior.tick(rig, LASER_MODE, muzzles, DT)
	assert_gt(hits[0][0] + hits[1][0], 0, "%s: control: the beam burns an open vent" % mode)
	assert_lt(g.health.current_health, hp, "%s: control: and the hull drops through it" % mode)


## Row 10 (real physics, 16x, the hull still), in order. The cannon's centre is hull-local (0, 60); its exposed edge is the nose edge (y 72).
func test_the_cannon_shield_eats_frontal_shots_and_never_covers_the_hull(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, TARGET_AT)
	_scale_clock()
	await _frames(2)
	var cannon := _part(g, &"cannon")
	var shield := cannon.get_node("Shield") as EnemyShield
	var probe := BULLET_SCENE.instantiate() as Node
	var damage := (probe.get_node("HitBox") as HitBox).damage
	probe.free()
	var broken := _count(shield.broken)
	var side := g.to_global(Vector2(56.0, 60.0))
	var port := Vector2.RIGHT.rotated(g.rotation)
	var nose := Vector2.DOWN.rotated(g.rotation)
	# A Sniper Shot from port at the cannon's level crosses the hull and meets the cannon 90 degrees off the nose.
	var hp := g.health.current_health
	var sniper := _fire(h.root, BULLET_SCENE, side, port)
	sniper.set(&"unlimited_pierce", true)
	await _frames(20)
	assert_true(is_instance_valid(sniper) and not sniper.is_queued_for_deletion(), "%s: the Sniper Shot pierced through" % mode)
	if is_instance_valid(sniper):
		sniper.free()
	assert_eq(hp - g.health.current_health, damage, "%s: sniper: the hull took it" % mode)
	assert_eq(cannon.health.current_health, cannon.max_health - damage, "%s: sniper: the flank shot passed the arc and hurt the cannon" % mode)
	assert_eq(shield.points(), shield.capacity, "%s: sniper: the shield spent nothing" % mode)
	# Frontal bullets into the nose edge, on the centre line.
	var expect := [[cannon.max_health - damage, shield.capacity - damage, 0], [cannon.max_health - damage, 0, 1],
			[cannon.max_health - 2 * damage, 0, 1]]
	for k in expect.size():
		hp = g.health.current_health
		var b := _fire(h.root, BULLET_SCENE, cannon.homing_point(), nose)
		await _until_spent(b, 20)
		assert_false(is_instance_valid(b) and not b.is_queued_for_deletion(), "%s: frontal %d: consumed" % [mode, k + 1])
		assert_eq(hp - g.health.current_health, damage, "%s: frontal %d: the hull still takes the hit" % [mode, k + 1])
		var row: Array = expect[k]
		assert_eq(cannon.health.current_health, row[0], "%s: frontal %d: cannon HP" % [mode, k + 1])
		assert_eq(shield.points(), row[1], "%s: frontal %d: shield points" % [mode, k + 1])
		assert_eq(broken[0], row[2], "%s: frontal %d: broken" % [mode, k + 1])
	# A plain round from port at the cannon's level is spent on the bare flank.
	hp = g.health.current_health
	var cannon_hp := cannon.health.current_health
	var plain := _fire(h.root, BULLET_SCENE, side, port)
	await _until_spent(plain, 20)
	assert_eq(hp - g.health.current_health, damage, "%s: plain flank: the hull" % mode)
	assert_eq(cannon.health.current_health, cannon_hp, "%s: plain flank: never the cannon" % mode)


## Row 11.
func test_the_cannon_shield_takes_its_config_follows_the_nose_and_goes_with_the_cannon(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var g := _spawn(h, _held_at(h))
	var cannon := _part(g, &"cannon")
	var shield := cannon.get_node_or_null("Shield") as EnemyShield
	assert_not_null(shield, "%s: the cannon carries a shield" % mode)
	if shield == null:
		return
	var c := g.config
	assert_eq([shield.arc_deg, shield.capacity, shield.regen_delay, shield.regen_seconds, shield.reboot_seconds],
			[c.shield_arc_deg, c.shield_capacity, c.shield_regen_delay, c.shield_regen_seconds, c.shield_reboot_seconds], "%s: config values" % mode)
	assert_eq(shield.radius, 26.0, "%s: the cannon's half-diagonal + 6" % mode)
	assert_same(cannon.hurt_box.get(&"_absorber"), shield, "%s: it holds the cannon hurtbox's absorber slot" % mode)
	assert_false(g.health.get_parent() == null)
	assert_null(g.hurt_box.get(&"_absorber"), "%s: never the hull's" % mode)
	g.rotation = 2.0
	_tick(g)
	assert_lte(rad_to_deg(absf(shield.facing().angle_to(_nose(g)))), 1.0, "%s: one tick later it faces the nose" % mode)
	cannon.destroy()
	assert_true(not is_instance_valid(shield) or shield.is_queued_for_deletion(), "%s: the shield goes with the cannon" % mode)


## The emergency run (rows 12-14, memo per mode). HP 200 from spawn; the player 450 px off the starboard beam. 0-20 s a pursuer: re-placed
## every tick 450 px from the hull on its current bearing. At 20 s `BatteryStarboard` and `Missiles` are destroyed; 20-50 s the player is
## re-placed every tick on the starboard beam (hull-local -x). In Assault the hull's position is held inside the view (rotation the mover's).
func _emergency_run(mode: String) -> Dictionary:
	if _emergency_runs.has(mode):
		return _emergency_runs[mode]
	var h = _world(mode)
	var at := Vector2(640.0, 300.0) if h.is_assault else Vector2.ZERO
	h.player.global_position = at + Vector2(-PURSUIT_RANGE, 0.0)
	var g := _spawn(h, at)
	g.health.set_health(200)
	var brain := _brain(g)
	var mover := g.get_node("EnemyMover") as EnemyMover
	var log := _phase_log(g)
	var tick: Array = log["tick"]
	var off_nose: Array = []  # [tick, id, kind (phase or -1 = round), degrees off the nose]
	for id in [HeavyGunshipBrain.MISSILES, HeavyGunshipBrain.BATTERY_STARBOARD]:
		for mount in g.modular_hull().mounts_of(id):
			mount.phase_changed.connect(func(p: int) -> void: off_nose.append([tick[0], id, p, _deg_to_player(g, h.player, _nose(g))]))
			mount.round_fired.connect(func(_r: Node2D) -> void: off_nose.append([tick[0], id, -1, _deg_to_player(g, h.player, _nose(g))]))
	var boosts: Array = []  # [tick, hull at start, player at start, commanded dir, hull at end]
	var boosting := false
	var in_view := true
	var lights_after: Array = []  # [starboard light, missiles light, starboard mount phase, missiles mount phase] per tick after 20 s
	var loss := int(round(20.0 / DT))
	for i in int(round(50.0 / DT)):
		tick[0] = i
		if i == loss:
			_part(g, &"battery_starboard").destroy()
			_part(g, &"missiles").destroy()
		if i < loss:
			var off: Vector2 = h.player.global_position - g.global_position
			h.player.global_position = g.global_position + off.normalized() * PURSUIT_RANGE
		else:
			h.player.global_position = g.global_position - _port(g) * PURSUIT_RANGE
		var start := g.global_position
		var player_at: Vector2 = h.player.global_position
		_tick(g)
		if h.is_assault:
			g.global_position = at
			in_view = in_view and EnemyWorld.view_rect(get_tree()).has_point(g.global_position)
		if mover.is_boosting() and not boosting:
			boosts.append([i, start, player_at, brain.emergency_boost_dir, Vector2.INF])
		elif boosting and not mover.is_boosting():
			(boosts[-1] as Array)[4] = g.global_position
		boosting = mover.is_boosting()
		if i >= loss:
			lights_after.append([(_part(g, &"battery_starboard").get_node("Light") as StateLight).get_state(),
					(_part(g, &"missiles").get_node("Light") as StateLight).get_state(),
					g.modular_hull().mounts_of(HeavyGunshipBrain.BATTERY_STARBOARD)[0].phase(),
					g.modular_hull().mounts_of(HeavyGunshipBrain.MISSILES)[0].phase()])
	var run := {"boosts": boosts, "phases": log["phases"], "rounds": log["rounds"], "off_nose": off_nose, "in_view": in_view,
			"lights_after": lights_after, "loss": loss, "phase_end": brain.phase}
	_emergency_runs[mode] = run
	return run


func test_emergency_boosts_away_every_5_s(mode: String = use_parameters(MODES)) -> void:
	await _fresh_idle_delta()
	var run := _emergency_run(mode)
	assert_true(run["in_view"], "%s: precondition: the hull stayed inside the view" % mode)
	var boosts: Array = run["boosts"]
	var period := int(round(SHIPPED.emergency_period / DT))
	assert_eq(boosts.size(), 10, "%s: 10 boosts in 50 s, through the losses (%s)" % [mode, boosts.map(func(b: Array) -> float: return b[0] * DT)])
	for k in mini(boosts.size(), 10):
		var b: Array = boosts[k]
		assert_almost_eq(int(b[0]), k * period, 1, "%s: boost %d at %.2f s" % [mode, k, b[0] * DT])
		var away: Vector2 = (b[1] as Vector2) - (b[2] as Vector2)
		assert_gt((b[3] as Vector2).dot(away), 0.0, "%s: boost %d is commanded away from the player" % [mode, k])
		if mode == "open_space" and int(b[0]) < int(run["loss"]):
			assert_true((b[4] as Vector2).is_finite(), "%s: boost %d ended" % [mode, k])
			assert_gt(((b[4] as Vector2) - (b[1] as Vector2)).dot(away), 0.0, "%s: boost %d moved the hull away" % [mode, k])


## Missiles events relative to the latest boost: [ticks since it, degrees off the nose].
func _missile_events(run: Dictionary, until: int) -> Array:
	var out: Array = []
	for e in run["off_nose"]:
		if e[1] != HeavyGunshipBrain.MISSILES or e[0] >= until:
			continue
		if e[2] != -1 and e[2] != TurretMount.Phase.TELEGRAPH and e[2] != TurretMount.Phase.FIRE:
			continue
		var since := -1
		for b in run["boosts"]:
			if int(b[0]) <= int(e[0]):
				since = int(e[0]) - int(b[0])
		out.append([since, e[3], e[2]])
	return out


func test_the_rear_missiles_fire_only_in_their_window_at_a_player_behind(mode: String = use_parameters(MODES)) -> void:
	await _fresh_idle_delta()
	var run := _emergency_run(mode)
	var events := _missile_events(run, int(run["loss"]))
	assert_gt(events.filter(func(e: Array) -> bool: return e[2] == -1).size(), 0, "%s: at least one rocket before 20 s" % mode)
	var lo := SHIPPED.emergency_boost_seconds
	var hi := SHIPPED.emergency_boost_seconds + SHIPPED.missile_window
	var rear := 180.0 - SHIPPED.missile_rear_arc_deg * 0.5
	for e in events:
		assert_between(float(e[0]) * DT, lo - 1e-6, hi - DT + 1e-6, "%s: a Missiles event (%d) inside its window after a boost" % [mode, e[2]])
		assert_gte(float(e[1]), rear - 1e-3, "%s: with the player behind (%.1f degrees off the nose)" % [mode, e[1]])
	# Front control: the player re-placed every tick on the nose.
	var h = _world(mode)
	var at := Vector2(640.0, 300.0) if h.is_assault else Vector2.ZERO
	var g := _spawn(h, at)
	g.health.set_health(200)
	var mover := g.get_node("EnemyMover") as EnemyMover
	var telegraphs := [0]
	g.modular_hull().mounts_of(HeavyGunshipBrain.MISSILES)[0].phase_changed.connect(func(p: int) -> void:
		if p == TurretMount.Phase.TELEGRAPH:
			telegraphs[0] += 1)
	var boosts := 0
	var boosting := false
	for _i in int(8.0 / DT):
		h.player.global_position = g.global_position + _nose(g) * PURSUIT_RANGE
		_tick(g)
		if h.is_assault:
			g.global_position = at
		if mover.is_boosting() and not boosting:
			boosts += 1
		boosting = mover.is_boosting()
	assert_gte(boosts, 2, "%s: control run: it boosted" % mode)
	assert_eq(telegraphs[0], 0, "%s: a player on the nose never opens the rear pod" % mode)


func test_a_destroyed_battery_or_missile_pod_never_fires_again(mode: String = use_parameters(MODES)) -> void:
	await _fresh_idle_delta()
	var run := _emergency_run(mode)
	var loss: int = run["loss"]
	for id in [HeavyGunshipBrain.BATTERY_STARBOARD, HeavyGunshipBrain.MISSILES]:
		var before := (run["phases"] as Array).filter(func(e: Array) -> bool: return e[1] == id and e[0] < loss and e[2] == TurretMount.Phase.FIRE)
		assert_gt(before.size(), 0, "%s: control: %s fired before its loss" % [mode, id])
		var after := (run["phases"] as Array).filter(func(e: Array) -> bool:
			return e[1] == id and e[0] >= loss and (e[2] == TurretMount.Phase.TELEGRAPH or e[2] == TurretMount.Phase.FIRE))
		assert_eq(after.size(), 0, "%s: %s never telegraphs or fires again" % [mode, id])
		var rounds := (run["rounds"] as Array).filter(func(r: Array) -> bool: return r[1] == id and r[0] >= loss)
		assert_eq(rounds.size(), 0, "%s: and launches nothing" % [mode])
	var bad := (run["lights_after"] as Array).filter(func(row: Array) -> bool:
		return row[0] != StateLight.State.OFF or row[1] != StateLight.State.OFF \
				or row[2] != TurretMount.Phase.UNPOWERED or row[3] != TurretMount.Phase.UNPOWERED)
	assert_eq(bad.size(), 0, "%s: for 30 s both mounts UNPOWERED and both part lights OFF" % mode)
	assert_eq((run["lights_after"] as Array).size(), int(round(30.0 / DT)), "%s: 30 s watched" % mode)


## Row 15 (Open Space only). The gunship's rockets are hand-ticked with it (their own physics and their lifetime's off, re-applied on every launch:
## a pool's `reset()` turns the lifetime back on); a tick on which one expired is followed by one awaited frame so the pool's deferred recycle runs.
## A self-hit is an OPEN rocket HitBox whose shape overlaps the hull's root hurtbox shape (every part lies inside it): the overlap the physics
## step would report, on the same 1/60 steps (review round 1, finding 2).
func test_in_open_space_it_stays_in_the_fight_60_s_into_emergency_and_never_hits_itself() -> void:
	await _fresh_idle_delta()
	var h = _world("open_space")
	var g := _spawn(h, Vector2(0.0, -PURSUIT_RANGE))
	g.health.set_health(200)
	var brain := _brain(g)
	var hull_shape := g.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var rockets: Array[EnemyRocket] = []
	var launched := [0]
	var expired := [false]
	for mount in g.modular_hull().mounts_of(HeavyGunshipBrain.MISSILES):
		mount.round_fired.connect(func(r: Node2D) -> void:
			var rocket := r as EnemyRocket
			launched[0] += 1
			rocket.set_physics_process(false)
			rocket.get_node("ProjectileLifetime").set_physics_process(false)
			if not rockets.has(rocket):
				rockets.append(rocket)
				rocket.expired.connect(func() -> void: expired[0] = true))
	var part_hits: Array = []
	for part in g.modular_hull().modules():
		part_hits.append(_count(part.damaged))
	var hp := g.health.current_health
	var overlaps := 0
	var closest := INF
	var farthest := 0.0
	for _i in int(60.0 / DT):
		var to_hull: Vector2 = g.global_position - h.player.global_position
		var d := to_hull.length()
		h.player.velocity = to_hull / d * minf(300.0, (d - 250.0) / DT) if d > 250.0 else Vector2.ZERO
		_step(g, h.player)
		farthest = maxf(farthest, g.global_position.distance_to(h.player.global_position))
		expired[0] = false
		for rocket in rockets:
			if not is_instance_valid(rocket) or not rocket.get(&"_launched") or rocket.get(&"_done"):
				continue
			rocket._tick(DT)
			rocket.get_node("ProjectileLifetime")._physics_process(DT)
			if rocket.is_armed() and not rocket.get(&"_done"):
				var hit_shape := rocket.get_node("HitBox/CollisionShape2D") as CollisionShape2D
				closest = minf(closest, rocket.global_position.distance_to(g.global_position))
				if hit_shape.shape.collide(hit_shape.global_transform, hull_shape.shape, hull_shape.global_transform):
					overlaps += 1
		if expired[0]:
			await get_tree().process_frame
	gut.p("open-space emergency chase: %d rockets launched, an open rocket came within %.1f px of the hull centre" % [launched[0], closest])
	assert_true(is_instance_valid(g) and not g.is_queued_for_deletion(), "it is still alive")
	assert_eq(brain.phase, Phase.EMERGENCY, "still in EMERGENCY after 60 s")
	assert_lt(farthest, SHIPPED.lose_radius, "never further than lose_radius from its pursuer (%.0f px)" % farthest)
	assert_gte(launched[0], 4, "it fired its rear missiles")
	assert_eq(overlaps, 0, "no open rocket ever overlapped its own hull")
	assert_eq(g.health.current_health, hp, "its hull took nothing")
	for k in part_hits.size():
		assert_eq((part_hits[k] as Array)[0], 0, "part %d took nothing" % k)


## One Assault closure run (rows 16 / 16b): the hull held at (900, 300) with its starboard to the still player at (450, 300) and HP 200 from
## spawn, so EMERGENCY starts on the first tick with [param r] s of budget left. `bypass` drops the Missiles mount's own gate; `defer_at` (s) starts
## a 1.0 s, 1 px/s `mover.boost` there, which defers the expiry. Every Missiles phase entry and rocket is logged as [t, kind (phase, -1 = rocket),
## budget left, expiry seen, brain phase].
func _closure_run(r: float, bypass: bool, defer_at: float = -1.0) -> Dictionary:
	var h = _world("assault")
	var at := Vector2(900.0, 300.0)
	h.player.global_position = Vector2(450.0, 300.0)
	var g := _spawn(h, at, {"engage_seconds": r})
	g.health.set_health(200)
	var brain := _brain(g)
	var mover := g.get_node("EnemyMover") as EnemyMover
	var pod: TurretMount = g.modular_hull().mounts_of(HeavyGunshipBrain.MISSILES)[0]
	if bypass:
		pod.telegraph_gate = Callable()
	var t := [0.0]
	var log: Array = []
	pod.phase_changed.connect(func(p: int) -> void: log.append([t[0], p, brain.budget.remaining(), brain.budget.remaining() <= 0.0, brain.phase]))
	pod.round_fired.connect(func(_r: Node2D) -> void: log.append([t[0], -1, brain.budget.remaining(), brain.budget.remaining() <= 0.0, brain.phase]))
	var in_view := true
	var expiry_tick := -1
	var before_expiry: int = TurretMount.Phase.SCAN
	var phase_at_expiry := -1
	var scan_after_disengage := true
	var disengaged := false
	var deferred := false
	var n := int(round((r + 2.5) / DT))
	for i in n:
		t[0] = (i + 1) * DT
		if defer_at >= 0.0 and not deferred and t[0] >= defer_at - 1e-6:
			deferred = true
			mover.boost(Vector2.RIGHT, 1.0, 1.0)
		var pod_before := pod.phase()
		_tick(g)
		g.global_position = at
		in_view = in_view and EnemyWorld.view_rect(get_tree()).has_point(g.global_position)
		if expiry_tick < 0 and brain.budget.remaining() <= 0.0:
			expiry_tick = i
			before_expiry = pod_before
			phase_at_expiry = brain.phase
		disengaged = disengaged or brain.phase == Phase.DISENGAGE
		if disengaged and pod.phase() != TurretMount.Phase.SCAN:
			scan_after_disengage = false
	return {"log": log, "in_view": in_view, "expiry_tick": expiry_tick, "pod_before_expiry": before_expiry, "phase_at_expiry": phase_at_expiry,
			"disengaged": disengaged, "scan_after_disengage": scan_after_disengage}


func _pod_events(run: Dictionary, kind: int) -> Array:
	return (run["log"] as Array).filter(func(e: Array) -> bool: return e[1] == kind)


func test_in_assault_the_rear_missiles_close_with_the_budget() -> void:
	await _fresh_idle_delta()
	var margin := HeavyGunshipBrain.ATTACK_GATE_MARGIN
	for r in [3.5, 1.0, 1.3]:
		var run := _closure_run(r, false)
		assert_true(run["in_view"], "R %.1f: precondition: the hull stayed in the view" % r)
		var rockets := _pod_events(run, -1)
		if r == 3.5:
			assert_gt(rockets.size(), 0, "R 3.5: a salvo inside the budget")
			for e in rockets:
				assert_gte(float(e[2]), margin - 1e-6, "R 3.5: a rocket left with %.2f s of budget" % e[2])
		else:
			assert_eq(rockets.size(), 0, "R %.1f: no salvo fits" % r)
		if r == 1.3:
			assert_eq(_pod_events(run, TurretMount.Phase.TELEGRAPH).size(), 0, "R 1.3: the window opens with 0.4 s left and the gate refuses")
		for e in run["log"]:
			if e[3]:
				assert_false(e[1] == -1 or e[1] == TurretMount.Phase.TELEGRAPH or e[1] == TurretMount.Phase.FIRE,
						"R %.1f: nothing from the pod after the budget expired (%s)" % [r, e])
		assert_true(run["disengaged"], "R %.1f: it disengaged" % r)
		assert_true(run["scan_after_disengage"], "R %.1f: the pod is in SCAN from DISENGAGE on" % r)
	var control := _closure_run(1.3, true)
	assert_true(control["in_view"], "control: precondition: in view")
	assert_gt(_pod_events(control, TurretMount.Phase.TELEGRAPH).size(), 0, "control: without its gate the pod telegraphs with 0.4 s left")


func test_a_deferred_expiry_cuts_a_rear_salvo_at_the_budget() -> void:
	await _fresh_idle_delta()
	var run := _closure_run(1.3, true, 1.0)
	assert_true(run["in_view"], "precondition: the hull stayed in the view")
	var telegraphs := _pod_events(run, TurretMount.Phase.TELEGRAPH)
	assert_gt(telegraphs.size(), 0, "precondition: the pod telegraphed")
	if not telegraphs.is_empty():
		assert_false(telegraphs[0][3], "precondition: before the expiry")
	assert_eq(run["pod_before_expiry"], TurretMount.Phase.TELEGRAPH, "precondition: still charging on the tick before the expiry")
	assert_eq(run["phase_at_expiry"], Phase.EMERGENCY, "precondition: the expiry is deferred (still EMERGENCY on that tick)")
	assert_eq(_pod_events(run, TurretMount.Phase.FIRE).size(), 0, "no rear FIRE at or after the expiry")
	assert_eq(_pod_events(run, -1).size(), 0, "and no rocket")


## Review round 3, R3-1 (epic §2.5 "venting stops in EMERGENCY"): a hull cut into EMERGENCY while it vents closes its vents through the exit hook
## on its next tick, and never opens them again however many bursts end.
func test_emergency_closes_an_open_vent_for_good(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var at := _held_at(h)
	h.player.global_position = at + Vector2.RIGHT.rotated(deg_to_rad(HEAT_BEARING_DEG)) * HEAT_RANGE
	var g := _spawn(h, at)
	var brain := _brain(g)
	var mover := g.get_node("EnemyMover") as EnemyMover
	_held_tick(g, at, 0.0)
	brain.enter_phase(Phase.VENT)
	_held_tick(g, at, 0.0)
	assert_true(_part(g, &"vent_port").is_vulnerable(), "%s: precondition: venting" % mode)
	g.health.set_health(209)
	_held_tick(g, at, 0.0)
	assert_eq(brain.phase, Phase.EMERGENCY, "%s: 209 / 700 mid-VENT: EMERGENCY on the next tick" % mode)
	var vents := [_part(g, &"vent_port"), _part(g, &"vent_starboard")]
	var opened := [0]
	for vent in vents:
		assert_false(vent.is_vulnerable(), "%s: %s closed" % [mode, vent.module_id])
		assert_eq((vent.get_node("Light") as StateLight).get_state(), StateLight.State.OFF, "%s: %s light OFF" % [mode, vent.module_id])
		vent.vulnerability_changed.connect(func(_m: EnemyModule, on: bool) -> void:
			if on:
				opened[0] += 1)
	assert_eq(mover.max_speed, SHIPPED.max_speed, "%s: the vent's slow is lifted" % mode)
	var ends := [0]
	for mount in g.modular_hull().mounts_of(HeavyGunshipBrain.BATTERY_PORT):
		mount.phase_changed.connect(func(p: int) -> void:
			if p == TurretMount.Phase.COOLDOWN:
				ends[0] += 1)
	for _i in int(12.0 / DT):
		_held_tick(g, at, 0.0)
	assert_gte(ends[0], 2, "%s: control: the port battery kept firing bursts" % mode)
	assert_eq(opened[0], 0, "%s: and no vent opened again" % mode)
	assert_eq(brain.heat, 0, "%s: no heat in EMERGENCY" % mode)


## Row 20 (a): a rail mid-VENT closes it; (b) an EMP cuts a rear salvo being charged, and the pod charges again after the window.
func test_a_rail_closes_a_vent_and_an_emp_cuts_a_rear_salvo(mode: String = use_parameters(MODES)) -> void:
	await _fresh_idle_delta()
	var h = _world(mode)
	var at := _held_at(h)
	h.player.global_position = at + Vector2.RIGHT.rotated(deg_to_rad(HEAT_BEARING_DEG)) * HEAT_RANGE
	var g := _spawn(h, at)
	var brain := _brain(g)
	var mover := g.get_node("EnemyMover") as EnemyMover
	_held_tick(g, at, 0.0)
	brain.enter_phase(Phase.VENT)
	_held_tick(g, at, 0.0)
	assert_eq((_part(g, &"vent_port").get_node("Light") as StateLight).get_state(), StateLight.State.VENTING, "%s: precondition: venting" % mode)
	g.suspend_ai()
	for id in [&"vent_port", &"vent_starboard"]:
		assert_false(_part(g, id).is_vulnerable(), "%s: a rail locks %s again" % [mode, id])
	for part in g.modular_hull().modules():
		assert_eq((part.get_node("Light") as StateLight).get_state(), StateLight.State.OFF, "%s: %s light OFF" % [mode, part.module_id])
	assert_eq(_light(g), StateLight.State.OFF, "%s: hull light OFF" % mode)
	assert_eq(mover.max_speed, SHIPPED.max_speed, "%s: the vent's slow is lifted" % mode)
	# (b) EMERGENCY, the player behind (off the starboard beam), the pod charging.
	h = _world(mode)
	var at2 := Vector2(900.0, 300.0) if h.is_assault else Vector2.ZERO
	h.player.global_position = at2 + Vector2(-PURSUIT_RANGE, 0.0)
	g = _spawn(h, at2)
	g.health.set_health(200)
	brain = _brain(g)
	var pod: TurretMount = g.modular_hull().mounts_of(HeavyGunshipBrain.MISSILES)[0]
	var guard := 0
	while pod.phase() != TurretMount.Phase.TELEGRAPH and guard < int(3.0 / DT):
		_tick(g)
		if h.is_assault:
			g.global_position = at2
		guard += 1
	assert_eq(pod.phase(), TurretMount.Phase.TELEGRAPH, "%s: precondition: the rear pod is charging" % mode)
	var rockets := [0]
	pod.round_fired.connect(func(_r: Node2D) -> void: rockets[0] += 1)
	var telegraphs := [0]
	pod.phase_changed.connect(func(p: int) -> void:
		if p == TurretMount.Phase.TELEGRAPH:
			telegraphs[0] += 1)
	g.apply_emp(2.0, null)
	assert_eq(pod.phase(), TurretMount.Phase.SCAN, "%s: the EMP cut the charge" % mode)
	assert_eq(_light(g), StateLight.State.OFF, "%s: hull light OFF" % mode)
	for part in g.modular_hull().modules():
		if part.role == EnemyModule.Role.WEAPON:
			assert_eq((part.get_node("Light") as StateLight).get_state(), StateLight.State.OFF, "%s: %s light OFF" % [mode, part.module_id])
	for _i in int(2.0 / DT):
		_tick(g)
		if h.is_assault:
			g.global_position = at2
	assert_eq(rockets[0], 0, "%s: no rocket in the window" % mode)
	for _i in int(1.5 / DT):
		_tick(g)
		if h.is_assault:
			g.global_position = at2
	assert_gt(telegraphs[0], 0, "%s: control: the pod charges again after the window" % mode)
