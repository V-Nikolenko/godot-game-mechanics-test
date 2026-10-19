## A test launcher for `EnemyRocket` (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.7, t5): a `CharacterBody2D` with
## a `HurtBox` on 512 / mask 1121 (an enemy's) wired to a `Health`, answering the two duck-typed launcher questions
## the rocket asks - `launch_velocity()` (its `velocity`, settable) and `rocket_clear_radius()` (40, the corvette's hull
## radius) - and firing rockets taken from one `BulletPool` per kind with `persist_after_owner_death`, as the
## Missile Corvette will.
##
## It passes the rocket nothing but `dir`, `aim_point` and itself: the rocket alone owns arming.
##
## No `class_name`: test-only. Preload it and call `build()`, then add the result to a container (the pools resolve
## their container as the launcher's parent).
extends CharacterBody2D

const CLEAR_RADIUS := 40.0
const MAX_HEALTH := 100

## How far ahead of the hull centre, along the fire direction, a rocket appears.
var muzzle_offset: float = 20.0
## False makes `launch_velocity()` answer zero while the fixture still moves: the zero-inheritance control.
var report_velocity: bool = true
var health: Health
var hurt_box: HurtBox
var pools: Dictionary = {}


static func build(at: Vector2) -> CharacterBody2D:
	var f: CharacterBody2D = (load("res://tests/helpers/rocket_launcher_fixture.gd") as GDScript).new()
	f.collision_layer = 0
	f.collision_mask = 0
	f.position = at
	return f


func _ready() -> void:
	health = Health.new()
	health.name = "Health"
	health.max_health = MAX_HEALTH
	health.current_health = MAX_HEALTH
	add_child(health)

	hurt_box = HurtBox.new()
	hurt_box.name = "HurtBox"
	hurt_box.collision_layer = CollisionLayers.ENEMY_HURTBOX
	hurt_box.collision_mask = 1121
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CLEAR_RADIUS
	shape.shape = circle
	hurt_box.add_child(shape)
	add_child(hurt_box)
	hurt_box.received_damage.connect(func(damage: int) -> void: health.decrease(damage))

	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER, EnemyRocket.Kind.WARHEAD]:
		var pool := BulletPool.new()
		pool.name = "Pool%d" % kind
		pool.bullet_scene = EnemyRocketScenes.scene_for(kind)
		pool.pool_size = 4
		pool.persist_after_owner_death = true
		add_child(pool)
		pools[kind] = pool


func launch_velocity() -> Vector2:
	return velocity if report_velocity else Vector2.ZERO


func rocket_clear_radius() -> float:
	return CLEAR_RADIUS


## Acquires a rocket at the muzzle and launches it. Null if the pool is empty.
func fire(kind: EnemyRocket.Kind, dir: Vector2, aim_point: Vector2) -> EnemyRocket:
	var pool: BulletPool = pools[kind]
	var rocket := pool.acquire(global_position + dir.normalized() * muzzle_offset) as EnemyRocket
	if rocket != null:
		rocket.launch(dir, aim_point, self)
	return rocket
