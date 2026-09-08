## Invariant test: an entity that dies explodes AT ITS OWN DEATH POSITION, in a container that
## survives it — across real entity scenes and real death paths, not synthetic fixtures.
##
## NOT characterization: `ExplosionEffect`'s ancestor walk, its explicit `container` argument
## and its position-after-parenting fix are all new code from this task. Plan:
## `docs/plans/explosioneffect-orphans-its-particles-onto-whatever-the-dyin/3-plan.md`.
##
## Before this change three things were visibly wrong, each fixed by a different part of the
## component (see `1-context.md` for the headless proof of all three):
##  1. Six AI racers died with NO explosion — `DamageReaction extends Node`, so the old
##     single-hop `get_parent() as Node2D` cast on the effect's parent came back null.
##  2. A hazard-eliminated racer's blast landed at the world origin, not the wreck.
##  3. Race walls, race asteroids and station turrets exploded well away from themselves,
##     because the particle's world position was assigned before the particle had a parent.
##
## Every entity here is parented through a container `Node2D` owned by `add_child_autofree`,
## per the `ExplosionEffect` rule in `tests/README.md` — a bare test-script parent leaves an
## unfreed `CPUParticles2D` behind for ~0.5 s.
extends GutTest

const _RACER_DIR := "res://assault/scenes/race/racers"
const RACE_WALL_SCENE: PackedScene = preload("res://assault/scenes/race/track/race_wall.tscn")
const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const GUNSHIP_SCENE: PackedScene = preload("res://assault/scenes/enemies/gunship/gunship.tscn")

## Six racers today. A sweep that finds fewer has broken, and a broken sweep passes every
## assertion below vacuously.
const _MIN_ROSTER: int = 6


func _particles_in(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is CPUParticles2D:
			out.append(child)
	return out


## Directory sweep, not a hand list (precedent: `test_config_instance_isolation.gd`,
## `test_enemy_hurtbox_geometry.gd`) — a seventh racer is covered the day it lands. Reads each
## scene's node table via `get_state()` rather than instantiating, per
## `test_entity_sprite_transparency.gd`'s pattern.
func _racer_scenes_with_damage_reaction() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(_RACER_DIR)
	assert_not_null(dir, "cannot open %s" % _RACER_DIR)
	if dir == null:
		return out
	for sub in dir.get_directories():
		var scene_path := "%s/%s/%s.tscn" % [_RACER_DIR, sub, sub]
		if not ResourceLoader.exists(scene_path):
			continue
		var packed := load(scene_path) as PackedScene
		var state := packed.get_state()
		for i in range(state.get_node_count()):
			if state.get_node_name(i) == "DamageReaction":
				out.append(scene_path)
				break
	return out


func test_the_racer_roster_sweep_finds_the_expected_minimum() -> void:
	assert_gte(
		_racer_scenes_with_damage_reaction().size(),
		_MIN_ROSTER,
		"a sweep finding fewer racers has broken and would pass every test below vacuously"
	)


## Defect 1: a racer killed through ordinary HP loss must explode, at its own position, in a
## container it survives.
##
## Each container is `add_child_autofree`d rather than freed by hand: `RacerWeapon.setup()`
## adds its `BulletPool` with `add_child.call_deferred()`, so a same-frame `free()` destroys the
## ship before that deferred call runs, orphaning the pool node. Awaiting a frame after the ship
## enters the tree lets it flush before the kill.
func test_every_racer_explodes_at_its_own_death_position() -> void:
	for scene_path in _racer_scenes_with_damage_reaction():
		var container := Node2D.new()
		add_child_autofree(container)
		var packed := load(scene_path) as PackedScene
		var ship := packed.instantiate()
		container.add_child(ship)
		await get_tree().process_frame
		ship.global_position = Vector2(700.0, 500.0)
		var expected: Vector2 = ship.global_position

		(ship.get_node("Health") as Health).decrease(99999)

		var found := _particles_in(container)
		assert_eq(found.size(), 1, "%s must explode into its container on death" % scene_path)
		if found.size() == 1:
			assert_almost_eq(
				(found[0] as CPUParticles2D).global_position,
				expected,
				Vector2(0.5, 0.5),
				"%s exploded away from where it died" % scene_path
			)


## Defect 3, the site the first version of `1-context.md`'s table wrongly marked "OK": a wall
## under the track's real authored offset (`race_level_1.tscn:80`) used to explode 777 px
## up-track because the particle's world position was applied before it had a parent.
func test_a_race_wall_under_the_real_track_offset_explodes_at_the_wall() -> void:
	var track := Node2D.new()
	track.position = Vector2(0, -777)
	add_child_autofree(track)
	var wall := RACE_WALL_SCENE.instantiate()
	track.add_child(wall)
	await get_tree().process_frame
	var expected: Vector2 = (wall as Node2D).global_position

	(wall.get_node("HurtBox") as HurtBox).received_damage.emit((wall as Node2D).get("health_amount"))

	var found := _particles_in(track)
	assert_eq(found.size(), 1, "the wall must explode into its container")
	if found.size() == 1:
		assert_almost_eq((found[0] as CPUParticles2D).global_position, expected, Vector2(0.5, 0.5))

	## race_wall.gd:49 awaits a 0.7s SceneTreeTimer before its own queue_free(). If the test
	## returns first, add_child_autofree frees `track` (and the wall with it) while that
	## coroutine is still suspended, stranding the timer — the trap tests/README.md documents
	## for LevelDirector, here on RaceWall's own death cleanup.
	await wait_seconds(0.75)


## Defect 2: a hazard-eliminated racer used to blast at the world origin because the call site
## set the effect's own (parentless, hence local-only) position instead of letting the entity
## be the actor.
func test_a_hazard_eliminated_racer_explodes_at_the_wreck() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var packed := load(_racer_scenes_with_damage_reaction()[0]) as PackedScene
	var ship := packed.instantiate() as RaceShip
	container.add_child(ship)
	await get_tree().process_frame
	ship.global_position = Vector2(300.0, 900.0)
	var expected: Vector2 = ship.global_position

	ship.apply_lethal_hazard()

	var found := _particles_in(container)
	assert_eq(found.size(), 1, "a hazard kill must still explode at the wreck")
	if found.size() == 1:
		assert_ne(
			(found[0] as CPUParticles2D).global_position,
			Vector2.ZERO,
			"must not land at the world origin"
		)
		assert_almost_eq((found[0] as CPUParticles2D).global_position, expected, Vector2(0.5, 0.5))


## Defect 3, second instance: a turret's blast used to land inside the hull's own local space.
## Also proves the turret call-site fix: the blast must survive the wreck, i.e. live in the
## station's own container, not as a descendant of the station.
func test_a_destroyed_turret_leaves_its_blast_outside_the_hull() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var station := STATION_SCENE.instantiate() as SpaceStation
	container.add_child(station)
	station.global_position = Vector2(640.0, 200.0)
	(station.get_node("LaserPhase") as StationLaserPhase).rotation_speed = 0.0

	var turret := station.turrets()[0] as StationTurret
	var expected: Vector2 = turret.global_position
	turret.hurt_box.received_damage.emit(turret.health.max_health)

	var found := _particles_in(container)
	assert_eq(found.size(), 1, "the blast must land in the station's own parent, outside the hull")
	if found.size() == 1:
		assert_almost_eq((found[0] as CPUParticles2D).global_position, expected, Vector2(0.5, 0.5))


## Proves the change is additive for a site that already worked.
func test_a_dying_enemy_still_explodes_into_its_container() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var enemy := GUNSHIP_SCENE.instantiate() as BaseEnemy
	container.add_child(enemy)
	enemy.global_position = Vector2(400.0, 250.0)
	var expected: Vector2 = enemy.global_position

	enemy.health.decrease(99999)

	var found := _particles_in(container)
	assert_eq(found.size(), 1, "a dying enemy must still explode into its container")
	if found.size() == 1:
		assert_almost_eq((found[0] as CPUParticles2D).global_position, expected, Vector2(0.5, 0.5))
