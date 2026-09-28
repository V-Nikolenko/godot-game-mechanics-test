## SpawnEntryResource — data for one ship (or formation) in a wave.
## WaveManager reads these when loading a LevelResource.
class_name SpawnEntryResource
extends Resource

@export var ship_scene: PackedScene
@export var base_offset: Vector2 = Vector2.ZERO
@export var spawn_delay: float = 0.0
@export var movement: MovementResource
@export var exit_mode: EnemyPathMover.ExitMode = EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
## Explicit lifetime for FREE_ON_DURATION exit. 0 = use movement.total_duration().
@export var exit_time: float = 0.0
@export var look_in_moving_direction: bool = true
## Fixed rotation (radians) used when look_in_moving_direction is false.
## Sprite convention: 0 = down, PI = up, PI/2 = left, -PI/2 = right.
@export var look_angle: float = 0.0
@export var formation: FormationResource        ## Optional — expands into N ships.
## Loose entries in the same wave that share a non-empty id form one squad (docs/plans/
## cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.4.1). Ignored on a formation entry — a formation is
## always automatically one squad regardless of this field.
@export var squad_id: StringName = &""
## Properties to set on the spawned entity via entity.set(key, value) at spawn time.
## Replaces the on_spawned Callable pattern. Example: {"direction": 1.0}
@export var initial_props: Dictionary = {}
