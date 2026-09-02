## Integration test for StationGunnery (EPIC sub-item 4a).
##
## NOT characterization: `StationGunnery`, the `BulletPool`/`Gunnery` nodes in
## `space_station.tscn` and the ten `SpaceStationConfig` gunnery fields are all new code, so
## these assert intended behaviour. Plan: `docs/plans/station-bullet-hell/3-plan.md`.
##
## ── Three harness rules this file must obey ──────────────────────────────────────────────────
##
## 1. **Never write to `station.config`.** `space_station.gd:36` `load()`s the `.tres` and
##    ResourceLoader caches, so every station in the process shares ONE object — the same one
##    `preload()` hands this file. Timings are overridden on the GUNNERY NODE, which copies the
##    config in `_ready()` and never reads it again.
## 2. **All ring tests set `LaserPhase.rotation_speed = 0.0` first.** `station_laser_phase.gd:123`
##    rotates the hull at 0.5 rad/s during exactly the phase the ring fires in; without pinning it
##    to 0 every absolute-angle assertion becomes timing-dependent.
## 3. **The station is parented to a container `Node2D`**, both because `bullet_pool.gd:47`
##    resolves `get_parent().get_parent()` and because `ExplosionEffect` parents its particles to
##    `actor.get_parent()`.
##
## Volleys are driven by calling the gunnery's fire methods directly rather than by awaiting real
## timers, so the assertions are deterministic and the file is fast. One test exercises the timers.
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const STATION_CONFIG := preload("res://assault/scenes/enemies/space_station/space_station_config.tres")

var _container: Node2D
var _station: SpaceStation
var _gunnery: StationGunnery
var _player: Node2D


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_station = STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(_station)
	_station.global_position = Vector2(640.0, 180.0)
	_gunnery = _station.get_node("Gunnery") as StationGunnery
	## Pin the hull still; individual tests opt back in.
	(_station.get_node("LaserPhase") as StationLaserPhase).rotation_speed = 0.0
	## Stop the real cadence — every volley in this file is forced.
	_gunnery._turret_timer.stop()
	_gunnery._ring_timer.stop()


func _add_player(at: Vector2) -> Node2D:
	_player = Node2D.new()
	_container.add_child(_player)
	_player.add_to_group("player")
	_player.global_position = at
	return _player


## Filtered, never a raw `get_children()`: a destroyed turret's `ExplosionEffect` parents its
## CPUParticles2D to `actor.get_parent()`, and for a turret that IS the `Turrets` node. So from
## the first kill onward the container also holds particle nodes, and in an unfiltered list every
## `child as StationTurret` cast on one of those returns null. Same filter `SpaceStation._turrets()`
## applies, which is why the gunnery's own `_live_turrets()` was never affected.
func _turrets() -> Array[StationTurret]:
	var out: Array[StationTurret] = []
	for child in _station.get_node("Turrets").get_children():
		var t := child as StationTurret
		if t != null:
			out.append(t)
	return out


func _kill_turret(index: int) -> void:
	var t := _turrets()[index] as StationTurret
	t.hurt_box.received_damage.emit(t.health.max_health)


func _kill_all_turrets() -> void:
	for i in _turrets().size():
		_kill_turret(i)


## Bullets land in the container, not under the station — that is the whole point of the pool's
## grandparent resolution.
func _bullets() -> Array:
	var out: Array = []
	for child in _container.get_children():
		if child is EnemyBullet:
			out.append(child)
	return out


func _bullet_directions() -> Array[float]:
	var out: Array[float] = []
	for b in _bullets():
		out.append((b as EnemyBullet)._direction.angle())
	return out


# ── Wiring ────────────────────────────────────────────────────────────────────

func test_nothing_is_fired_before_the_first_volley() -> void:
	assert_eq(_bullets().size(), 0, "the station must not fire on spawn")


## The regression test for the design's single load-bearing hazard. It fails if the pool is
## missing entirely, not merely misplaced — see the header of `station_gunnery.gd`.
func test_the_pool_is_a_direct_child_of_the_station() -> void:
	var found: BulletPool = null
	for child in _station.get_children():
		if child is BulletPool:
			found = child as BulletPool
	assert_not_null(found, "a BulletPool must be a DIRECT child of SpaceStation")
	assert_eq(_gunnery.bullet_pool, found,
		"the gunnery's exported bullet_pool must point at that node (check node_paths= in the scene)")
	for holder_name in ["Gunnery", "LaserPhase", "Turrets"]:
		var holder := _station.get_node_or_null(holder_name)
		if holder != null:
			assert_null(holder.get_node_or_null("BulletPool"),
				"the pool must not live under %s — its container would resolve to the rotating station" % holder_name)


func test_config_values_are_copied_onto_the_gunnery() -> void:
	assert_eq(_gunnery.turret_fire_interval, STATION_CONFIG.turret_fire_interval, "turret_fire_interval copied")
	assert_eq(_gunnery.turret_burst_count, STATION_CONFIG.turret_burst_count, "turret_burst_count copied")
	assert_eq(_gunnery.turret_burst_arc, STATION_CONFIG.turret_burst_arc, "turret_burst_arc copied")
	assert_eq(_gunnery.turret_bullet_damage, STATION_CONFIG.turret_bullet_damage, "turret_bullet_damage copied")
	assert_eq(_gunnery.turret_bullet_speed, STATION_CONFIG.turret_bullet_speed, "turret_bullet_speed copied")
	assert_eq(_gunnery.core_ring_interval, STATION_CONFIG.core_ring_interval, "core_ring_interval copied")
	assert_eq(_gunnery.core_ring_count, STATION_CONFIG.core_ring_count, "core_ring_count copied")
	assert_eq(_gunnery.core_ring_step, STATION_CONFIG.core_ring_step, "core_ring_step copied")
	assert_eq(_gunnery.core_bullet_damage, STATION_CONFIG.core_bullet_damage, "core_bullet_damage copied")
	assert_eq(_gunnery.core_bullet_speed, STATION_CONFIG.core_bullet_speed, "core_bullet_speed copied")
	## The copy must not write back through the shared process-wide resource.
	assert_eq(STATION_CONFIG.core_ring_step, 0.24, "the shipped .tres must be left untouched")


# ── Phase 1: the turret volley ────────────────────────────────────────────────

func test_a_volley_fires_one_fan_per_live_turret() -> void:
	_add_player(Vector2(640.0, 600.0))
	_gunnery.fire_turret_volley()
	assert_eq(_bullets().size(), 12, "4 live turrets x 3 bullets = 12")


## The headline test: killing a gun visibly removes it from the volley. Asserts the bullets come
## from the SURVIVING turrets, so a version that fires 6 bullets from the wrong guns still fails.
func test_destroying_turrets_removes_their_guns() -> void:
	_add_player(Vector2(640.0, 600.0))
	_kill_turret(0)
	_kill_turret(1)

	_gunnery.fire_turret_volley()
	assert_eq(_bullets().size(), 6, "2 surviving turrets x 3 bullets = 6")

	var survivors: Array[Vector2] = []
	for t in _turrets():
		var turret := t as StationTurret
		if turret.is_alive():
			survivors.append(turret.global_position)
	for b in _bullets():
		var pos: Vector2 = (b as EnemyBullet).global_position
		var near := false
		for s in survivors:
			## spawn_radius is 26, so a bullet from a live gun sits within ~27 px of it.
			if pos.distance_to(s) < 30.0:
				near = true
		assert_true(near, "every bullet must originate at a SURVIVING turret, not a dead one")


func test_turret_bullets_are_aimed_at_the_player() -> void:
	var player := _add_player(Vector2(300.0, 620.0))
	_gunnery.fire_turret_volley()

	## Group the 12 bullets by their firing turret and check each fan against that turret.
	for t in _turrets():
		var turret := t as StationTurret
		var expected: float = (player.global_position - turret.global_position).angle()
		var fan: Array[float] = []
		for b in _bullets():
			var bullet := b as EnemyBullet
			if bullet.global_position.distance_to(turret.global_position) < 30.0:
				fan.append(bullet._direction.angle())
		assert_eq(fan.size(), 3, "each live turret fires a 3-bullet fan")
		fan.sort()
		var half: float = _gunnery.turret_burst_arc / 2.0
		assert_almost_eq(absf(fan[1] - expected), 0.0, 0.01, "the centre bullet points at the player")
		assert_almost_eq(fan[0], expected - half, 0.01, "the fan straddles the aim by -arc/2")
		assert_almost_eq(fan[2], expected + half, 0.01, "the fan straddles the aim by +arc/2")


## Closes the open *Discovered* item: the turret sprite's barrels point along local -Y and no
## turret sets `rotation`, so before this change every barrel pointed at the top of the screen
## while firing somewhere else. Fails by ~180 degrees against the pre-4a code.
func test_turret_barrels_face_the_player_when_firing() -> void:
	var player := _add_player(Vector2(300.0, 620.0))
	_gunnery.fire_turret_volley()
	for t in _turrets():
		var turret := t as StationTurret
		var expected: Vector2 = (player.global_position - turret.global_position).normalized()
		## The barrel is local -Y, so this is where it actually points once rotated.
		var barrel := Vector2.UP.rotated(turret.global_rotation)
		assert_almost_eq(absf(barrel.angle_to(expected)), 0.0, 0.01,
			"the barrel must point at the player, not at the top of the screen")


## The regression test for the rotation trap: bullets must live in the enemy container, not under
## the station, or the whole bullet field would sweep with the rotating hull.
func test_bullets_live_in_the_enemy_container_not_in_the_station() -> void:
	_add_player(Vector2(640.0, 600.0))
	_gunnery.fire_turret_volley()
	assert_gt(_bullets().size(), 0, "something was fired")
	for b in _bullets():
		assert_eq(b.get_parent(), _container,
			"bullets must be parented to the station's parent, not to the station")


func test_volleys_are_deterministic() -> void:
	_add_player(Vector2(300.0, 620.0))
	_gunnery.fire_turret_volley()
	var first := _bullet_directions()
	first.sort()

	_gunnery.fire_turret_volley()
	var all_dirs := _bullet_directions()
	var second: Array[float] = []
	for i in range(first.size(), all_dirs.size()):
		second.append(all_dirs[i])
	second.sort()

	assert_eq(second.size(), first.size(), "both volleys fire the same number of bullets")
	for i in first.size():
		assert_almost_eq(second[i], first[i], 0.0001,
			"an unmoved player must produce identical volleys — fails the moment anyone adds randf()")


# ── Phase 2: the core ring ────────────────────────────────────────────────────

func test_the_core_does_not_fire_until_the_armor_breaks() -> void:
	assert_false(_gunnery.is_core_firing(), "the core is silent while the armour holds")
	_gunnery.fire_core_ring()
	assert_eq(_bullets().size(), 0, "a forced ring does nothing before armor_broken")

	_kill_all_turrets()
	assert_true(_gunnery.is_core_firing(), "the core starts firing when the last turret dies")


func test_a_core_ring_is_a_full_evenly_spaced_ring() -> void:
	_kill_all_turrets()
	_gunnery._ring_timer.stop()
	_gunnery.fire_core_ring()

	var dirs := _bullet_directions()
	assert_eq(dirs.size(), _gunnery.core_ring_count, "one bullet per core_ring_count")
	dirs.sort()
	var spacing: float = TAU / float(_gunnery.core_ring_count)
	for i in dirs.size() - 1:
		assert_almost_eq(dirs[i + 1] - dirs[i], spacing, 0.001, "ring bullets are evenly spaced")
	for b in _bullets():
		var offset: float = ((b as EnemyBullet).global_position - _station.global_position).length()
		assert_almost_eq(offset, _gunnery.core_spawn_radius, 0.5,
			"ring bullets emerge from the hull rim, not the centre")


## Asserted as ABSOLUTE angles against a known `_ring_angle`, so it cannot pass vacuously the way
## a "ring 2 == ring 1 + step" comparison of two same-frame volleys could.
func test_successive_rings_precess_by_the_configured_step() -> void:
	_kill_all_turrets()
	_gunnery._ring_timer.stop()
	_gunnery._ring_angle = 0.0

	_gunnery.fire_core_ring()
	var first := _bullet_directions()
	first.sort()

	_gunnery.fire_core_ring()
	var all_dirs := _bullet_directions()
	var second: Array[float] = []
	for i in range(first.size(), all_dirs.size()):
		second.append(all_dirs[i])
	second.sort()

	var spacing: float = TAU / float(_gunnery.core_ring_count)
	for i in first.size():
		## Both rings are the same lane set rotated by the step, so comparing sorted lists means
		## comparing each lane modulo the spacing.
		var delta: float = fposmod(second[i] - first[i], spacing)
		var expected: float = fposmod(_gunnery.core_ring_step, spacing)
		assert_almost_eq(delta, expected, 0.001,
			"ring 2 must be ring 1 advanced by exactly core_ring_step")


## THE DESIGN LOCK. Reads the step and count off the GUNNERY NODE (i.e. the values copied from
## the shipped `.tres`), never from literals — with literals it would lock nothing.
##
## Research (Sparen A3) requires a per-ring step that does not re-tread earlier rings' radial
## lanes, or the pattern leaves a permanent safe lane. The shipped 0.24 comes from the golden
## angle and leaves a largest lane gap of ~9 % of the spacing. The value 0.21 that this plan
## originally carried leaves ~31.8 % and FAILS this test — which is the evidence the lock is real.
##
## The 0.25 * spacing bound deliberately catches re-tread periods 2, 3 and 4 but not 5+: a step of
## spacing/5 re-treads five lanes forever yet leaves only a 20 % gap. That is an accepted bound —
## five lanes at 7.2 degrees apart is not the blind spot three lanes at 31 degrees is.
func test_the_ring_step_leaves_no_permanent_safe_lane() -> void:
	var spacing: float = TAU / float(_gunnery.core_ring_count)
	var offsets: Array[float] = []
	## 20 rings is more than a real phase fires at a 2 s cadence inside a 40-50 s fight.
	for k in range(1, 21):
		offsets.append(fposmod(float(k) * _gunnery.core_ring_step, spacing))
	offsets.sort()

	var largest: float = offsets[0] + spacing - offsets[offsets.size() - 1]
	for i in offsets.size() - 1:
		largest = maxf(largest, offsets[i + 1] - offsets[i])

	assert_lt(largest, 0.25 * spacing,
		"core_ring_step must not re-tread lanes — a gap this wide is a permanent safe lane")


func test_turret_fire_stops_when_the_armor_breaks() -> void:
	_add_player(Vector2(640.0, 600.0))
	_kill_all_turrets()
	assert_true(_gunnery._turret_timer.is_stopped(), "the turret cadence stops at the handover")
	_gunnery.fire_turret_volley()
	assert_eq(_bullets().size(), 0,
		"a forced turret volley after armor_broken fires nothing — every gun is dead anyway")


# ── Teardown ──────────────────────────────────────────────────────────────────

## What stops dead-boss bullets holding `LevelSection.ENEMIES_CLEARED` open: the director polls
## the enemy container's child count, so a bullet left behind blocks the section.
func test_everything_stops_and_bullets_are_freed_when_the_station_dies() -> void:
	_add_player(Vector2(640.0, 600.0))
	_gunnery.fire_turret_volley()
	assert_gt(_bullets().size(), 0, "there are bullets in flight before the boss dies")

	_kill_all_turrets()
	_station.hurt_box.received_damage.emit(_station.health.max_health)

	## Two frames, not one: the queue_free() -> _exit_tree() -> per-bullet queue_free() chain
	## spans the delete-queue flush. Asserted rather than assumed.
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_bullets().size(), 0, "no EnemyBullet may outlive the station")


# ── The one timing test ───────────────────────────────────────────────────────

## Everything else in this file is forced. This is the one test that proves the cadence is
## actually wired to a running Timer rather than only reachable by hand.
func test_the_timers_actually_run() -> void:
	_add_player(Vector2(640.0, 600.0))
	_gunnery.turret_fire_interval = 0.2
	_gunnery._turret_timer.start(0.2)
	await wait_seconds(0.5)
	assert_gt(_bullets().size(), 0, "the turret timer must fire volleys on its own")
