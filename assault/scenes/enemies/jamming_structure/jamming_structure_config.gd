## JammingStructureConfig - a jamming tower's flat stats (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.8, Phase 9 t7).
##
## One `.tres` per variant directory (`jamming_structure/` local, `sector_jammer/`, `pulsed_jammer/`); the scene's `Field` (a `HazardField`)
## authors the same values and `JammingStructure._ready()` writes these over it. `counts_as_escape` false, `collision_damage` 0 (contact NONE),
## `wreck_chance` 0 and the hazard fields 0 (no brain, no mover).
class_name JammingStructureConfig
extends ShipConfig

@export_group("Assault")
## Downward drift in Assault, px/s (copied onto the `AssaultDrift` child).
@export var assault_drift_speed: float = 60.0

@export_group("Field")
## The jamming field's radius, px: inside it a lit field locks the player's H abilities and K rockets.
@export var field_radius: float = 240.0
## Seconds the lock outlasts leaving the field (or the field going dark).
@export var stabilise_seconds: float = 0.75
## The pulsed cycle, seconds: TELEGRAPH -> ACTIVE -> QUIET on a loop. All 0 = always on.
@export var cycle_telegraph: float = 0.0
@export var cycle_active: float = 0.0
@export var cycle_quiet: float = 0.0
