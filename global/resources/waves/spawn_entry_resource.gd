## SpawnEntryResource — data for one ship (or formation) in a wave.
## WaveManager reads these when loading a LevelResource.
class_name SpawnEntryResource
extends Resource

@export var ship_scene: PackedScene
@export var base_offset: Vector2 = Vector2.ZERO
@export var spawn_delay: float = 0.0
@export var movement: MovementResource
@export var exit_mode: EnemyPathMover.ExitMode = EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
@export var look_in_moving_direction: bool = true
@export var formation: FormationResource        ## Optional — expands into N ships.
## Properties to set on the spawned entity via entity.set(key, value) at spawn time.
## Replaces the on_spawned Callable pattern. Example: {"direction": 1.0}
@export var initial_props: Dictionary = {}
