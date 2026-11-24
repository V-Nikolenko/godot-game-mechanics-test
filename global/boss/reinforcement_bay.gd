## ReinforcementBay — one launch point of a boss's reinforcements (IDEAS §10; Phase 11 §2.2, docs/plans/cmug256so0031m52wbxomst72/3-plan.md;
## built in t2). A `Node2D` child named `Bay` of the `EnemyModule` that launches; an optional `Marker2D` child `Mouth` is where escorts come out
## (default: the bay's own origin).
##
## Pure data and geometry: what to launch, when, and through which doors. `BossReinforcements` reads every bay of its host and runs them; the
## bay holds no clock. A bay whose part is destroyed is dead for good (IDEAS §26: destroying a module changes what the player fights next).
##
## Tests: tests/integration/test_boss_reinforcements.gd.
class_name ReinforcementBay
extends Node2D

## Append-only.
##   PERIODIC        a launch every `period`, the first `first_delay` after the bay becomes active.
##   ON_SECTOR_LOSS  each destroyed part among `watch_ids` queues one launch.
##   ON_PHASE        entering the boss phase `on_phase` queues one launch.
enum Trigger { PERIODIC, ON_SECTOR_LOSS, ON_PHASE }

## Unique within the host (`BossReinforcements` keys every query on it).
@export var bay_id: StringName = &""
@export var trigger: Trigger = Trigger.PERIODIC
## What one launch puts out (Open Space; Assault too when `assault_payload_scene` is null).
@export var payload_scene: PackedScene
## Assault's payload; null = `payload_scene`.
@export var assault_payload_scene: PackedScene
## Escorts per launch (before the live cap).
@export var count: int = 2
## Assault's count per launch (-1 = `count`).
@export var assault_count: int = -1
## PERIODIC: seconds between two launches' door openings.
@export var period: float = 12.0
## Assault's period (-1 = `period`).
@export var assault_period: float = -1.0
## PERIODIC: seconds from the bay becoming active to its first door opening.
@export var first_delay: float = 3.0
## Empty = active from the start; otherwise no trigger counts until the boss has reached this phase.
@export var active_from_phase: StringName = &""
## ON_SECTOR_LOSS: the part ids whose destruction each queues one launch.
@export var watch_ids: Array[StringName] = []
## ON_PHASE: the boss phase whose entry queues one launch.
@export var on_phase: StringName = &""
## The telegraph: the doors are OPENING this long before each launch.
@export var door_seconds: float = 0.8
## The doors stay OPEN this long after a launch (0 = they close at once).
@export var open_hold_seconds: float = 0.0
## True: the part is hittable only while its doors are open (the Carrier hangar rule).
@export var opens_part: bool = false
## Assault: launches per boss life (-1 = no limit).
@export var assault_launch_limit: int = -1


## The part this bay launches from (its parent), or null.
func part() -> EnemyModule:
	return get_parent() as EnemyModule


## Where escorts come out (global).
func mouth_position() -> Vector2:
	var mouth := get_node_or_null(^"Mouth") as Node2D
	return mouth.global_position if mouth != null else global_position


## Outward: from the host's centre through the mouth, normalised (the host's facing when the mouth sits on the centre).
func launch_direction() -> Vector2:
	var host := _host()
	var centre := host.global_position if host != null else global_position
	var out := mouth_position() - centre
	if out.length_squared() > 1e-6:
		return out.normalized()
	return Vector2.RIGHT.rotated(host.global_rotation if host != null else global_rotation)


## The boss: the parent of the part's `Modules` node.
func _host() -> Node2D:
	var p := get_parent()
	var holder := p.get_parent() if p != null else null
	return holder.get_parent() as Node2D if holder != null else null


## Escorts per launch in the given mode (before the live cap).
func count_for(assault: bool) -> int:
	return assault_count if assault and assault_count >= 0 else count


## Seconds between two PERIODIC launches in the given mode.
func period_for(assault: bool) -> float:
	return assault_period if assault and assault_period >= 0.0 else period
