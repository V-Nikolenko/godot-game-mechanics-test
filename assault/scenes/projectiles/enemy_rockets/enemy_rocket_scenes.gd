## EnemyRocketScenes - the enemy rocket family's scenes and pool sizing (the `EnemyOrdnanceScenes` shape).
## See docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.6.
class_name EnemyRocketScenes
extends RefCounted

const DUMB: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/dumb_rocket.tscn")
const PURSUIT: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/pursuit_rocket.tscn")
const CLUSTER: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/cluster_rocket.tscn")
const WARHEAD: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/delayed_warhead.tscn")
## Unpooled: only a CLUSTER rocket instantiates it, on its split, and it frees itself on `expired`.
const SUBMUNITION: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/submunition.tscn")


## The scene for `kind`, or null for an unknown kind.
static func scene_for(kind: EnemyRocket.Kind) -> PackedScene:
	match kind:
		EnemyRocket.Kind.DUMB:
			return DUMB
		EnemyRocket.Kind.PURSUIT:
			return PURSUIT
		EnemyRocket.Kind.CLUSTER:
			return CLUSTER
		EnemyRocket.Kind.WARHEAD:
			return WARHEAD
		EnemyRocket.Kind.SUBMUNITION:
			return SUBMUNITION
		_:
			push_error("EnemyRocketScenes: no scene for kind %d" % kind)
			return null


## Pooled rockets a launcher needs so a salvo never starves its pool while the previous salvo is still flying:
## `count × ceil(max_time / cfg.salvo_period_min)`, `count` = `cfg.warhead_salvo_count` for WARHEAD and
## `cfg.salvo_count` otherwise. `cfg` is a `MissileCorvetteConfig` (any object with those fields). `max_time` is the
## kind's own scene export, read without instantiating the scene.
static func pool_size_for(kind: EnemyRocket.Kind, cfg) -> int:
	var count: int = int(cfg.warhead_salvo_count) if kind == EnemyRocket.Kind.WARHEAD else int(cfg.salvo_count)
	return count * int(ceil(max_time_of(kind) / float(cfg.salvo_period_min)))


## The `max_time` export a kind's scene authors (the script default when the scene leaves it unset).
static func max_time_of(kind: EnemyRocket.Kind) -> float:
	var scene := scene_for(kind)
	if scene == null:
		return 0.0
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"max_time":
			return float(state.get_node_property_value(0, i))
	return 4.0
