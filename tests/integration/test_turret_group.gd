## Turret groups and the power source (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.1–§2.10.4; task plan
## docs/plans/cmvqw0vnl0183qs2xbphzonu7/3-plan.md, whose row numbers these tests follow). INTENT tests, not characterization. R8.24's
## "power-source shutdown of a turret group" is row 4, in both harnesses.
##
## Rows run in both harnesses (`tests/helpers/enemy_ai_harness.gd`) unless the name says `assault_` / `open_space_` or nothing is mode-dependent.
## They are hand-ticked: a row calls `spawn_members()` itself (the production path is the deferred call from `_ready()`, pinned by row 1), turns off
## the physics tick of the group, every member and every member's `AssaultDrift`, then steps `group.tick(DT)` followed by `member._physics_process(DT)`
## for the members it drives. Deaths are a direct lethal `received_damage.emit`. Mount numbers are read from the mount scenes, never typed.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const ASSAULT_PAIR: PackedScene = preload("res://assault/scenes/structures/turret_group/presets/assault_pair.tscn")
const PRESET_DIR := "res://assault/scenes/structures/turret_group/presets/"
const TURRET: PackedScene = preload("res://assault/scenes/enemies/defense_turret/defense_turret.tscn")
const SOURCE: PackedScene = preload("res://assault/scenes/enemies/power_source/power_source.tscn")
const SOURCE_CONFIG: PowerSourceConfig = preload("res://assault/scenes/enemies/power_source/power_source_config.tres")  # read only
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const MOUNT_SCRIPT: Script = preload("res://assault/scenes/enemies/defense_turret/mounts/turret_mount.gd")
const BURST_SCRIPT: Script = preload("res://assault/scenes/enemies/defense_turret/mounts/burst_cannon_mount.gd")
const RING_MOUNT_SCRIPT: Script = preload("res://assault/scenes/enemies/defense_turret/mounts/pulse_ring_mount.gd")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
## The group origin: inside the Assault view (0..1280 x 0..720), with room below for the player.
const G := Vector2(640.0, 300.0)
const LETHAL := 10000
const BURST := TurretMount.Variant.BURST_CANNON
const RING := TurretMount.Variant.PULSE_RING
const BEAM := TurretMount.Variant.BEAM_CANNON
const LANCE := TurretMount.Variant.LANCE
## Row 8's ring turret rng seed: fixes the ring's gap bearing so the run is reproducible (the row asserts the band crossed the source outside a gap).
const RING_SEED := 7


func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


## A code-built group: one `TurretGroupSlot` per `[scene, variant, offset]` (a 4th element sets the slot's `rest_bearing_deg`).
func _group_of(specs: Array) -> TurretGroup:
	var g := TurretGroup.new()
	for i in specs.size():
		var spec: Array = specs[i]
		var slot := TurretGroupSlot.new()
		slot.name = "Slot%d" % i
		slot.member_scene = spec[0]
		slot.variant = spec[1]
		slot.position = spec[2]
		if spec.size() > 3:
			slot.rest_bearing_deg = spec[3]
		g.add_child(slot)
	return g


## Adds `g` at `at`, spawns its members at once and turns off every physics tick (the group's, the members', their drifts'). Returns the members.
func _spawn(h, g: TurretGroup, at: Vector2 = G) -> Array[Node2D]:
	g.position = at
	h.root.add_child(g)
	g.spawn_members()
	g.set_physics_process(false)
	var members := g.members()
	for m in members:
		m.set_physics_process(false)
		var drift := m.get_node_or_null("AssaultDrift") as AssaultDrift
		if drift != null:
			drift.set_physics_process(false)
	return members


func _step(g: TurretGroup, drive: Array, n: int = 1, clock: Array = []) -> void:
	for i in n:
		if not clock.is_empty():
			clock[0] += DT
		g.tick(DT)
		for m in drive:
			if is_instance_valid(m) and not (m as Node).is_queued_for_deletion():
				m._physics_process(DT)


func _run(g: TurretGroup, drive: Array, max_steps: int, done: Callable, clock: Array = []) -> bool:
	for i in max_steps:
		_step(g, drive, 1, clock)
		if done.call():
			return true
	return false


func _kill(e: BaseEnemy) -> void:
	e.hurt_box.received_damage.emit(LETHAL)


func _brain(t: DefenseTurret) -> DefenseTurretBrain:
	return t.get_node("Brain") as DefenseTurretBrain


func _light(t: DefenseTurret) -> StateLight:
	return t.get_node("StateLight") as StateLight


func _source_of(members: Array) -> PowerSource:
	for m in members:
		if m is PowerSource:
			return m
	return null


## The member turret whose first mount is a `script` instance.
func _turret_with(members: Array, script: Script) -> DefenseTurret:
	for m in members:
		var t := m as DefenseTurret
		if t != null and t.mounts().size() > 0 and t.mounts()[0].get_script() == script:
			return t
	return null


func _mx(variant: int, property: StringName) -> Variant:
	return TurretMountScenes.export_of(variant, property, MOUNT_SCRIPT.get_property_default_value(property))


func _circle(radius: float) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	return cs


func _victim(h, at: Vector2) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(_circle(14.0))
	e.add_to_group(&"enemies")
	h.root.add_child(e)
	e.global_position = at
	return e


func _tracker() -> ScoreTracker:
	var tracker := ScoreTracker.new()
	add_child_autofree(tracker)
	tracker.start_tracking()
	tracker.set_process(false)  # `_process` would decay the combo; the rows read it raw
	return tracker


# ── 1. Spawn ────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_preset_spawns_its_members_deferred_as_siblings_at_its_slots(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var announced: Array = []
	var on_orphan := func(e: Node) -> void: announced.append([e, (e as Node2D).global_position])
	EventBus.enemy_spawned_orphan.connect(on_orphan)
	var g := ASSAULT_PAIR.instantiate() as TurretGroup
	g.position = G
	h.root.add_child(g)
	assert_eq(g.members().size(), 0, "%s: the spawn is deferred, nothing inside add_child" % mode)
	assert_eq(announced.size(), 0)
	await get_tree().process_frame
	EventBus.enemy_spawned_orphan.disconnect(on_orphan)

	var members := g.members()
	assert_eq(members.size(), 3, "%s: one member per slot" % mode)
	assert_eq(announced.size(), 3, "%s: each announced once as an orphan" % mode)
	var expected := [G + Vector2(-50.0, 60.0), G + Vector2(50.0, -60.0), G]
	for m in members:
		assert_eq(m.get_parent(), h.root, "%s: a sibling of the group in its parent" % mode)
		assert_true(m.is_in_group(&"enemies"), "%s: %s is an ordinary enemy" % [mode, m.name])
		assert_true(m.is_in_group(g.owner_group), "%s: %s joins the owner group" % [mode, m.name])
		var hits := announced.filter(func(entry: Array) -> bool: return entry[0] == m)
		assert_eq(hits.size(), 1)
	for i in expected.size():
		var entry: Array = announced[i]
		assert_almost_eq((entry[1] as Vector2).distance_to(expected[i]), 0.0, 0.01, "%s: member %d at its slot" % [mode, i])
	assert_not_null(_turret_with(members, BURST_SCRIPT), "%s: the burst cannon turret" % mode)
	assert_not_null(_turret_with(members, RING_MOUNT_SCRIPT), "%s: the pulse ring turret" % mode)
	assert_eq((announced[0][0] as DefenseTurret).mounts()[0].get_script(), BURST_SCRIPT, "%s: the burst turret is the one at (-50, 60)" % mode)
	var source := _source_of(members)
	assert_not_null(source)
	assert_true(source.provides_power())
	assert_false(g.is_in_group(&"enemies"), "%s: the group is a coordinator, never an enemy" % mode)
	assert_false(g.has_signal(&"died"), "%s: the group has no death, so nothing scores it" % mode)
	assert_false(g.counts_toward_wave_clear)
	assert_false(g.counts_as_escape)
	assert_false(g.is_laser_blocking())
	assert_true(g.is_powered())

	var left: Array = []
	g.member_left.connect(func(m: Node) -> void: left.append(m))
	members[0].queue_free()
	members[1].queue_free()
	await get_tree().process_frame
	assert_true(is_instance_valid(g), "%s: the group lives while a member does" % mode)
	assert_eq(left.size(), 2)
	members[2].queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(left.size(), 3, "%s: member_left once per member" % mode)
	assert_false(is_instance_valid(g), "%s: the group frees itself after its last member" % mode)


# ── 2-3. World-anchored x ───────────────────────────────────────────────────────────────────────────────────────────

func test_assault_the_group_is_world_anchored_in_x() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	cam.offset = Vector2(100.0, 0.0)
	var tree := get_tree()
	assert_almost_eq(EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x, 100.0, 0.001,
			"sanity: the view is panned +100 px")
	for anchored in [true, false]:
		var g := ASSAULT_PAIR.instantiate() as TurretGroup
		g.world_anchored_x = anchored
		g.global_position = cam.global_position + cam.offset + Vector2(-64.0, -220.0) * ArenaCamera.WORLD_SCALE  # WaveManager's formula
		var y := g.global_position.y
		h.root.add_child(g)
		var want := 512.0 if anchored else 612.0
		assert_almost_eq(g.global_position.x, want, 0.001, "anchored %s: the group's x" % anchored)
		assert_eq(g.global_position.y, y, "anchored %s: y stays camera-relative" % anchored)
		g.spawn_members()
		var xs: Array = []
		for m in g.members():
			xs.append(roundf(m.global_position.x))
		xs.sort()
		assert_eq(xs, [want - 50.0, want, want + 50.0], "anchored %s: the members' x" % anchored)


func test_open_space_the_group_x_is_untouched() -> void:
	var h = _world("open_space")
	var g := ASSAULT_PAIR.instantiate() as TurretGroup
	g.global_position = Vector2(612.0, -80.0)
	h.root.add_child(g)
	assert_eq(g.global_position.x, 612.0, "no arena, no anchor")
	g.spawn_members()
	var xs: Array = []
	for m in g.members():
		xs.append(roundf(m.global_position.x))
	xs.sort()
	assert_eq(xs, [562.0, 612.0, 662.0])


# ── 4-5. Power-source shutdown (R8.24) ──────────────────────────────────────────────────────────────────────────────

func test_killing_the_power_source_shuts_every_member_down_in_the_same_call(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = G + Vector2(0.0, 250.0)
	var tracker := _tracker()
	var g := _group_of([
		[TURRET, BURST, Vector2(-200.0, 0.0)],
		[TURRET, BEAM, Vector2(-70.0, 0.0)],
		[TURRET, BEAM, Vector2(70.0, 0.0)],
		[TURRET, BURST, Vector2(200.0, 0.0)],
		[SOURCE, -1, Vector2(0.0, -100.0)],
	])
	var members := _spawn(h, g)
	assert_eq(members.size(), 5)
	var a := members[0] as DefenseTurret
	var b := members[1] as DefenseTurret
	var c := members[2] as DefenseTurret
	var d := members[3] as DefenseTurret
	var s := members[4] as PowerSource
	var left: Array = []
	g.member_left.connect(func(m: Node) -> void: left.append(m))
	var powered_log: Array = []
	g.power_changed.connect(func(on: bool) -> void: powered_log.append(on))

	_kill(d)
	assert_true(d.is_queued_for_deletion(), "%s: a turret killed before the source" % mode)

	var c_beam := (c.mounts()[0] as BeamTurretMount).beam()
	assert_true(_run(g, [c], 600, func() -> bool: return c_beam.is_lethal()), "%s: C's beam is lit" % mode)
	var b_beam := (b.mounts()[0] as BeamTurretMount).beam()
	assert_true(_run(g, [b], 600, func() -> bool: return b_beam.phase() == EnemyBeam.Phase.TELEGRAPH), "%s: B telegraphs" % mode)
	var b_dir := Vector2.RIGHT.rotated(b_beam.global_rotation)
	var victim := _victim(h, b_beam.global_position + b_dir * 150.0)
	var b_seg_end := b_beam.global_position + b_dir * b_beam.length
	assert_lte(victim.global_position.distance_to(Geometry2D.get_closest_point_to_segment(victim.global_position, b_beam.global_position, b_seg_end)),
			14.0, "%s: sanity, the victim sits on B's beam line" % mode)
	var b_hits: Array = []
	b_beam.target_hit.connect(func(target: Node2D, _dmg: int) -> void: b_hits.append(target))
	var a_mount := a.mounts()[0] as BurstCannonMount
	var fired: Array = []
	a_mount.round_fired.connect(func(p: Node2D) -> void: fired.append(p))
	assert_true(_run(g, [a], 600, func() -> bool: return a_mount.phase() == TurretMount.Phase.FIRE and fired.size() >= 1), "%s: A is mid-burst" % mode)
	assert_lt(fired.size(), int(TurretMountScenes.export_of(BURST, &"burst_count", BURST_SCRIPT.get_property_default_value(&"burst_count"))),
			"%s: sanity, the burst is not over" % mode)
	assert_eq(c_beam.phase(), EnemyBeam.Phase.ACTIVE, "%s: sanity, C still lit" % mode)
	var pool := a.get_node("PulsePool_0") as BulletPool
	var active_before: int = pool._active.size()
	var fired_before := fired.size()

	_kill(s)
	# Same call: no tick between the lethal hit and these assertions.
	for t: DefenseTurret in [a, b, c]:
		assert_eq(t.mounts()[0].phase(), TurretMount.Phase.UNPOWERED, "%s: %s's mount UNPOWERED at once" % [mode, t.name])
		assert_eq(_brain(t).phase, DefenseTurretBrain.Phase.UNPOWERED, "%s: %s's brain UNPOWERED" % [mode, t.name])
		assert_false(t.is_powered())
		assert_eq(_light(t).get_state(), StateLight.State.OFF, "%s: %s's light OFF" % [mode, t.name])
	assert_false(g.is_powered(), "%s: the group is dark" % mode)
	assert_eq(powered_log, [false], "%s: power_changed(false) once" % mode)
	assert_eq(b_beam.phase(), EnemyBeam.Phase.OFF, "%s: the telegraph is cancelled" % mode)
	assert_eq(c_beam.phase(), EnemyBeam.Phase.FADE, "%s: the lit beam fades" % mode)
	for r in fired:
		assert_true(is_instance_valid(r) and pool._active.has(r), "%s: a round in flight lives on" % mode)

	_step(g, [a, b, c], 300)
	assert_eq(fired.size(), fired_before, "%s: no round in 5 s" % mode)
	assert_lte(pool._active.size(), active_before, "%s: no acquire in 5 s" % mode)
	_step(g, [a, b, c], 300)
	assert_eq(fired.size(), fired_before, "%s: none in 10 s" % mode)
	assert_lte(pool._active.size(), active_before)
	assert_eq(b_hits.size(), 0, "%s: the cancelled telegraph never hit" % mode)
	assert_eq(victim.health.current_health, victim.health.max_health)
	assert_eq(c_beam.phase(), EnemyBeam.Phase.OFF, "%s: the fade ended and nothing restarted" % mode)
	assert_eq(b_beam.phase(), EnemyBeam.Phase.OFF)
	for t: DefenseTurret in [a, b, c]:
		assert_eq(t.mounts()[0].phase(), TurretMount.Phase.UNPOWERED, "%s: %s still dark after 10 s" % [mode, t.name])
	assert_eq(powered_log, [false], "%s: never reversed" % mode)
	assert_false(g.members().has(d), "%s: the turret killed first is never a member again" % mode)
	assert_true(d.is_queued_for_deletion())

	var fresh := SOURCE.instantiate() as PowerSource
	h.root.add_child(fresh)
	g.add_power_provider(fresh)
	assert_false(g.is_powered(), "%s: a new provider never re-powers a dark group" % mode)

	# Dark but destructible, and still scored.
	var score_before := tracker.get_total_score()
	var a_died := [false]
	a.died.connect(func() -> void: a_died[0] = true)
	_kill(a)
	assert_true(a_died[0], "%s: a dark turret still dies" % mode)
	assert_gte(tracker.get_total_score(), score_before + a.score_value, "%s: and still scores" % mode)

	await get_tree().process_frame
	assert_false(is_instance_valid(d), "%s: the turret killed first is freed" % mode)
	assert_true(left.has(d), "%s: and left the group" % mode)


func test_assault_a_source_killed_while_its_turrets_are_above_the_view_still_disables_them() -> void:
	var h = _world("assault")
	h.player.global_position = Vector2(640.0, 600.0)
	var members := _spawn(h, ASSAULT_PAIR.instantiate() as TurretGroup, Vector2(640.0, -300.0))
	var g := (members[0] as DefenseTurret).turret_group() as TurretGroup
	var turrets: Array = members.filter(func(m: Node) -> bool: return m is DefenseTurret)
	assert_eq(turrets.size(), 2)
	_step(g, turrets, 30)
	for t: DefenseTurret in turrets:
		assert_eq(_brain(t).phase, DefenseTurretBrain.Phase.SCAN, "sanity: %s sees nothing from above the view" % t.name)
	_kill(_source_of(members))
	for t: DefenseTurret in turrets:
		assert_eq(t.mounts()[0].phase(), TurretMount.Phase.UNPOWERED, "%s is disabled off-screen too" % t.name)
		assert_false(t.is_powered())


# ── 6. Stagger ──────────────────────────────────────────────────────────────────────────────────────────────────────

## Steps three ring turrets together until each has started a TELEGRAPH; returns the start times (and the ENGAGED times in `engaged`).
func _telegraph_starts(turrets: Array, step: Callable, engaged: Array) -> Array:
	var clock := [0.0]
	var starts: Array = []
	for t: DefenseTurret in turrets:
		t.mounts()[0].phase_changed.connect(func(p: int) -> void:
			if p == TurretMount.Phase.TELEGRAPH:
				starts.append(clock[0]))
		_brain(t).phase_changed.connect(func(p: int) -> void:
			if p == DefenseTurretBrain.Phase.ENGAGED:
				engaged.append(clock[0]))
	for i in 240:
		clock[0] += DT
		step.call()
		if starts.size() >= turrets.size():
			break
	return starts


func test_the_group_staggers_telegraph_starts_by_stagger_seconds(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = G + Vector2(0.0, 150.0)
	var offsets := [Vector2(-100.0, 0.0), Vector2(0.0, 0.0), Vector2(100.0, 0.0)]
	var g := _group_of(offsets.map(func(o: Vector2) -> Array: return [TURRET, RING, o]))
	var members := _spawn(h, g)
	for m in members:
		assert_lte(h.player.global_position.distance_to(m.global_position), float(_mx(RING, &"trigger_range")), "sanity: inside trigger range")
	var engaged: Array = []
	var starts := _telegraph_starts(members, func() -> void: _step(g, members), engaged)
	assert_eq(engaged.size(), 3)
	assert_eq(engaged.min(), engaged.max(), "%s: all three engage on the same tick" % mode)
	assert_eq(starts.size(), 3, "%s: all three telegraph" % mode)
	for i in [1, 2]:
		var gap: float = starts[i] - starts[i - 1]
		assert_gte(gap, g.stagger_seconds - 1e-6, "%s: TELEGRAPH %d starts a stagger after the one before" % [mode, i])
		assert_lte(gap, g.stagger_seconds + 2.0 * DT, "%s: and a refused mount retries the next tick" % mode)

	# Control: the same three turrets with no group start on the same tick.
	var lone: Array = []
	for o: Vector2 in offsets:
		var t := TURRET.instantiate() as DefenseTurret
		t.variant = RING
		t.position = G + o
		h.root.add_child(t)
		t.set_physics_process(false)
		(t.get_node("AssaultDrift") as AssaultDrift).set_physics_process(false)
		lone.append(t)
	for m in members:
		m.queue_free()
	var lone_engaged: Array = []
	var lone_starts := _telegraph_starts(lone, func() -> void:
		for t in lone:
			t._physics_process(DT), lone_engaged)
	assert_eq(lone_starts.size(), 3)
	assert_eq(lone_starts.min(), lone_starts.max(), "%s: control, ungrouped turrets telegraph together" % mode)


# ── 7. Coverage ─────────────────────────────────────────────────────────────────────────────────────────────────────

func test_every_preset_meets_the_coverage_rule() -> void:
	var found := 0
	for file in DirAccess.get_files_at(PRESET_DIR):
		if not file.ends_with(".tscn"):
			continue
		found += 1
		var g := (load(PRESET_DIR + file) as PackedScene).instantiate() as TurretGroup
		assert_not_null(g, "%s is a TurretGroup" % file)
		assert_eq(g.coverage_points().size(), 36, "%s: one point per 10 degrees" % file)
		assert_eq(g.coverage_holes().size(), 0, "%s: every point at coverage_radius is reached by >= coverage_min mounts" % file)
		g.free()
	assert_gt(found, 0, "sanity: the presets directory has presets")

	var pair := ASSAULT_PAIR.instantiate() as TurretGroup
	assert_eq(pair.coverage_radius, 180.0)
	var reaches := pair.mount_reaches()
	assert_eq(reaches.size(), 2, "one reach per turret mount; the source has none")
	var values: Array = reaches.map(func(r: Dictionary) -> float: return r["reach"])
	values.sort()
	assert_eq(TurretMountScenes.reach_of(RING), float(TurretMountScenes.export_of(RING, &"trigger_range",
			RING_MOUNT_SCRIPT.get_property_default_value(&"trigger_range"))), "a ring's reach is its trigger range")
	assert_eq(TurretMountScenes.reach_of(BURST), float(_mx(BURST, &"fire_range")), "a gun's reach is its fire range")
	assert_eq(values, [TurretMountScenes.reach_of(RING), TurretMountScenes.reach_of(BURST)])
	pair.free()


func test_a_preset_missing_a_turret_or_stretched_past_its_reach_fails_the_coverage_rule() -> void:
	for slot_name in ["BurstTurret", "RingTurret"]:
		var g := ASSAULT_PAIR.instantiate() as TurretGroup
		g.get_node(slot_name).free()
		assert_gt(g.coverage_holes().size(), 0, "without %s the preset fails" % slot_name)
		g.free()

	var g := ASSAULT_PAIR.instantiate() as TurretGroup
	var ring_pos := (g.get_node("RingTurret") as Node2D).position
	g.coverage_radius = 240.0
	assert_gt(g.coverage_radius, TurretMountScenes.reach_of(RING) - ring_pos.length(), "sanity: past the ring's reach on the far side")
	var holes := g.coverage_holes()
	assert_gt(holes.size(), 0, "a radius past the ring's reach leaves holes")
	for hole in holes:
		assert_lt(hole.dot(ring_pos), 0.0, "every hole is on the far side from the ring turret")
	var nearest := Vector2.ZERO
	for p in g.coverage_points():
		if nearest == Vector2.ZERO or p.dot(ring_pos) > nearest.dot(ring_pos):
			nearest = p
	assert_false(Array(holes).has(nearest), "the point toward the ring turret is still covered")
	g.free()


# ── 8. Friendly fire ────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_groups_pulse_ring_spares_its_power_source_and_hurts_an_outsider(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var members := _spawn(h, ASSAULT_PAIR.instantiate() as TurretGroup)
	var g := (members[0] as DefenseTurret).turret_group() as TurretGroup
	var ring_t := _turret_with(members, RING_MOUNT_SCRIPT)
	var burst_t := _turret_with(members, BURST_SCRIPT)
	var source := _source_of(members)
	_brain(ring_t).rng.seed = RING_SEED  # in place: the mount draws from this same object
	var ring := (ring_t.mounts()[0] as PulseRingMount).ring()
	var centre := ring_t.mounts()[0].global_position
	var to_source := source.global_position - centre
	var dist := to_source.length()
	h.player.global_position = centre + Vector2(150.0, 100.0)
	var outsiders: Array = []
	for turn in [90.0, 180.0, 270.0]:
		outsiders.append(_victim(h, centre + to_source.rotated(deg_to_rad(turn))))
	var record: Array = []
	ring.target_hit.connect(func(target: Node2D, _dmg: int) -> void: record.append(target))
	var band: float = ring.band
	var crossed := [false]
	assert_true(_run(g, [ring_t], 400, func() -> bool:
		if ring.is_lethal() and absf(ring.radius() - dist) <= band * 0.5 and not ring.in_gap(to_source.angle()):
			crossed[0] = true
		return ring.phase() == EnergyRing.Phase.FADE), "%s: the ring went out" % mode)
	assert_true(crossed[0], "%s: sanity, the band crossed the source outside a gap (seed %d)" % [mode, RING_SEED])
	assert_false(record.has(source), "%s: the group's own ring spares its power source" % mode)
	assert_false(record.has(burst_t), "%s: and its other turret" % mode)
	assert_eq(source.health.current_health, source.health.max_health)
	assert_eq(burst_t.health.current_health, burst_t.health.max_health)
	var hit := outsiders.filter(func(o: Node) -> bool: return record.has(o))
	assert_gt(hit.size(), 0, "%s: the same ring hurts an enemy outside the group" % mode)
	assert_true(g.is_powered())


# ── 9. Power lines ──────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_power_source_draws_a_line_to_each_powered_turret(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var members := _spawn(h, ASSAULT_PAIR.instantiate() as TurretGroup)
	var source := _source_of(members)
	var burst_t := _turret_with(members, BURST_SCRIPT)
	var ring_t := _turret_with(members, RING_MOUNT_SCRIPT)
	var lines := source.power_lines()
	assert_eq(lines.size(), 2, "%s: one line per turret" % mode)
	var ends: Array = []
	for line in lines:
		assert_true(line.top_level, "%s: drawn in world space" % mode)
		assert_almost_eq(line.points[0].distance_to(source.global_position), 0.0, 0.01)
		ends.append(line.points[1])
	for t in [burst_t, ring_t]:
		assert_true(ends.any(func(p: Vector2) -> bool: return p.distance_to(t.global_position) < 0.01), "%s: a line ends at %s" % [mode, t.name])
	_kill(burst_t)
	assert_eq(source.power_lines().size(), 1, "%s: a dead turret loses its line" % mode)
	_kill(source)
	assert_eq(source.power_lines().size(), 0, "%s: a dark group has no lines" % mode)


# ── 10. WaveBuilder through a real WaveManager ──────────────────────────────────────────────────────────────────────

func test_assault_wave_builder_spawns_one_group_and_three_members_through_a_real_wave_manager() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	cam.offset = Vector2(-100.0, 0.0)
	var container := Node2D.new()
	h.root.add_child(container)
	var wm := WaveManager.new()
	wm.enemy_container = container
	h.root.add_child(wm)
	var offsets: Array = []
	wm.enemy_spawned.connect(func(_e: Node, _i: int) -> void: offsets.append(cam.offset.x))
	var b := WaveBuilder.new()
	var w := b.wave(0.0, [b.turret_group(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR).at(-64.0, -220.0)])
	assert_eq(w.entries[0].ship_scene.resource_path, WaveBuilder.TURRET_GROUP_ASSAULT_PAIR)
	wm.load_section([w] as Array[WaveResource])
	for i in 4:
		await get_tree().process_frame
	var groups: Array = []
	var turrets: Array = []
	var sources: Array = []
	for child in container.get_children():
		if child is TurretGroup:
			groups.append(child)
		elif child is DefenseTurret:
			turrets.append(child)
		elif child is PowerSource:
			sources.append(child)
	assert_eq(groups.size(), 1, "one group")
	assert_eq(turrets.size(), 2, "two turrets")
	assert_eq(sources.size(), 1, "one power source")
	assert_eq(container.get_child_count(), 4, "nothing else in the container")
	assert_eq(offsets, [-100.0], "sanity: the view was panned when the wave spawned")
	assert_almost_eq((groups[0] as Node2D).global_position.x, 512.0, 0.001, "the anchor holds on the real spawn path")
	var burst_t := _turret_with(turrets, BURST_SCRIPT)
	assert_eq((burst_t.get_node("PulsePool_0") as BulletPool)._container, container, "a member's pool resolves to the container")


# ── 11. Drift-out and scoring ───────────────────────────────────────────────────────────────────────────────────────

func test_assault_a_group_drifting_out_never_costs_the_combo_and_a_drifted_source_does_not_darken() -> void:
	var h = _world("assault")
	var tracker := _tracker()
	tracker.set("_combo", 4.0)
	assert_false(SOURCE_CONFIG.counts_as_escape, "the shipped power_source_config.tres")
	var end_y := EnemyWorld.projectile_world_rect(get_tree()).end.y
	var g := ASSAULT_PAIR.instantiate() as TurretGroup
	var members := _spawn(h, g, Vector2(640.0, end_y - 100.0))
	EventBus.enemy_spawned_orphan.emit(g)  # the handler WaveManager.enemy_spawned reaches for a wave-spawned group
	var source := _source_of(members)
	assert_false(source.counts_as_escape, "the live source")
	var score0 := tracker.get_total_score()

	(source.get_node("AssaultDrift") as AssaultDrift).step(101.0 / 60.0)
	assert_true(source.is_queued_for_deletion(), "sanity: the source drifted out")
	await get_tree().process_frame
	assert_false(is_instance_valid(source))
	assert_true(g.is_powered(), "a source that leaves without dying does not darken the group")
	for m in g.members():
		assert_ne((m as DefenseTurret).mounts()[0].phase(), TurretMount.Phase.UNPOWERED, "%s is still powered" % m.name)

	for m in g.members():
		(m.get_node("AssaultDrift") as AssaultDrift).step(200.0 / 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(g), "the group freed itself after its last member")
	assert_almost_eq(float(tracker.get("_combo")), 4.0, 0.0001, "no member and not the group cost the combo")
	assert_eq(tracker.get_total_score(), score0, "nothing scored")

	var control := FIXTURE_ENEMY.instantiate() as BaseEnemy
	h.root.add_child(control)
	control.set_physics_process(false)
	EventBus.enemy_spawned_orphan.emit(control)
	control.queue_free()
	await get_tree().process_frame
	assert_almost_eq(float(tracker.get("_combo")), 4.0 * tracker.score_config.escape_combo_multiplier, 0.0001,
			"control: an escaping enemy costs the penalty")


# ── 12. Slot overrides ──────────────────────────────────────────────────────────────────────────────────────────────

func test_open_space_a_slot_sets_its_members_variant_and_rest_bearing() -> void:
	var h = _world("open_space")
	var members := _spawn(h, _group_of([
		[TURRET, LANCE, Vector2(-100.0, 0.0), 270.0],
		[TURRET, -1, Vector2(100.0, 0.0)],
	]))
	var lance := members[0] as DefenseTurret
	var plain := members[1] as DefenseTurret
	assert_true(lance.mounts()[0] is BeamTurretMount, "the slot's variant")
	assert_eq(lance.variant, LANCE)
	assert_eq(lance.mounts()[0].rest_bearing_deg, 270.0, "the slot's rest bearing")
	assert_true(plain.mounts()[0] is BurstCannonMount, "-1 keeps the turret scene's own mount")
	assert_eq(plain.mounts()[0].rest_bearing_deg, 90.0, "NAN keeps its authored bearing")
	var bare := TurretGroupSlot.new()
	assert_true(is_nan(bare.rest_bearing_deg), "the slot default is NAN")
	bare.free()
