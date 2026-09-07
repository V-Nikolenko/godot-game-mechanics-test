## ShipConfig — base resource for all ship configurations.
## Contains only properties shared by every ship type (health and contact damage).
## Each ship type has its own subclass with the properties it actually uses.
class_name ShipConfig
extends Resource

@export var max_health: int = 100
@export var collision_damage: int = 20
## Points awarded to the player for destroying this ship.
## Read by ScoreTracker via the enemy's config resource.
@export var score_value: int = 0
## If false, this ship doesn't count toward wave-clear bonuses (e.g. bonus drones).
@export var counts_toward_wave_clear: bool = true


## Replace `node`'s `config` with a copy private to that node, if it still holds the shared,
## process-wide resource `ResourceLoader` caches.
##
## Every entity declares `@export var config: XConfig = load("res://.../x_config.tres")`, and
## `ResourceLoader` caches by path — so without this, all ten entities of a type in the process
## hold ONE object, and it is the same object a test's `preload()` returns. Writing to one
## enemy's config rewrote the shipped balance data for every other live enemy of that type.
##
## Idempotent by construction: `duplicate()` blanks `resource_path`, so a blank path IS the marker
## of an already-private copy and a second call is a no-op. That is what lets `BaseEnemy` and
## `AllyFighter` call this from BOTH `_init()` and `_enter_tree()` — see their doc comments for
## why both are needed — and what stops a re-parent discarding per-instance values.
##
## Nodes with no `config` property, or one holding something that is not a `ShipConfig`, are left
## alone. Same generic `get()`/`is ShipConfig` idiom as `BaseEnemy._ready()`, so no subclass type
## knowledge is needed here and a new enemy is covered the day it lands.
##
## The copy is shallow, which is complete only while every config class stays flat.
## `tests/integration/test_config_instance_isolation.gd` asserts that flatness, so the day a config
## gains a nested `Resource`/`Array`/`Dictionary` the gate says so rather than silently sharing it.
static func privatise(node: Object) -> void:
	var cfg: Variant = node.get("config")
	if cfg is ShipConfig and not (cfg as ShipConfig).resource_path.is_empty():
		node.set("config", (cfg as ShipConfig).duplicate())
