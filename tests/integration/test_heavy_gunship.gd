## The Heavy Gunship's shell, parts, movement and Assault life (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.4; Phase 10 t4, task plan
## docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md). Intent tests, both harnesses unless a row says otherwise.
##
## Hand-ticked at 1/60 (`_tick`: `_physics_process(dt)`, then the position integrated from the velocity, the corvette tests' shape); the test
## moves the harness player itself. `_spawn()` writes `engage_seconds = 1000` (the budget is live in the Assault harness and would end every
## long row at 9 s); only the Assault-life rows put the shipped 9.0 back. The projectile rows run on real physics at the 8x clock with the hull
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

var _exit: Dictionary = {}
var _probe_s: float = 0.0
var _roots: Array[Node] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_all() -> void:
	var t0 := Time.get_ticks_usec()
	_exit = PH10.heavy_gunship_exit(self)
	_probe_s = float(Time.get_ticks_usec() - t0) / 1e6


func after_each() -> void:
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


func test_the_phase_enum_is_append_only_and_the_builder_spawns_it() -> void:
	assert_eq([Phase.APPROACH, Phase.BROADSIDE, Phase.BREAK_AWAY, Phase.VENT, Phase.EMERGENCY, Phase.DISENGAGE, Phase.IDLE, Phase.NOTICING,
			Phase.RETURNING], [0, 1, 2, 3, 4, 5, 6, 7, 8])
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
	assert_eq((counts[&"missiles"] as Array[int])[0], 0, "the rear missiles stay closed until t5")


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
