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
## If false, ScoreTracker does not apply the escape-combo penalty when this ship leaves the tree
## unkilled. Independent of `counts_toward_wave_clear` — a reinforcement squad, for example, is
## exempt from wave-clear bonuses but is meant to keep paying the escape penalty.
@export var counts_as_escape: bool = true


## Replace `node`'s `property`-named field with a copy private to that node, if it still holds
## the shared, process-wide resource `ResourceLoader` caches.
##
## Every entity declares `@export var config: XConfig = load("res://.../x_config.tres")`, and
## `ResourceLoader` caches by path — so without this, all ten entities of a type in the process
## hold ONE object, and it is the same object a test's `preload()` returns. Writing to one
## enemy's config rewrote the shipped balance data for every other live enemy of that type.
## `ScoreTracker.score_config` (`property = "score_config"`) is the same pattern with a single
## per-level owner instead of many simultaneous ones — the hazard there is a test writing through
## `tracker.score_config` and poisoning every other `preload()` of the shipped default.
##
## Idempotent by construction: `duplicate()` blanks `resource_path`, so a blank path IS the marker
## of an already-private copy and a second call is a no-op. That is what lets `BaseEnemy` and
## `AllyFighter` call this from BOTH `_init()` and `_enter_tree()` — see their doc comments for
## why both are needed — and what stops a re-parent discarding per-instance values.
##
## Nodes with no `property`-named field, or one holding something that is not a `Resource`, are
## left alone. Same generic `get()`/`is Resource` idiom as `BaseEnemy._ready()`, so no subclass
## type knowledge is needed here and a new entity or property is covered the day it lands.
##
## The copy is shallow, which is complete only while the resource stays flat.
## `tests/integration/test_config_instance_isolation.gd` asserts that flatness for every
## `ShipConfig` subclass, so the day a config gains a nested `Resource`/`Array`/`Dictionary` the
## gate says so rather than silently sharing it.
static func privatise(node: Object, property: String = "config") -> void:
	var res: Variant = node.get(property)
	if res is Resource and not (res as Resource).resource_path.is_empty():
		node.set(property, (res as Resource).duplicate())
