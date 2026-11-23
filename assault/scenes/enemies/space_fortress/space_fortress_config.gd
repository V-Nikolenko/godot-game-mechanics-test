## SpaceFortressConfig - tuning for the Space Fortress (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.5, §2.16; Phase 11 t5, task plan
## docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md). Extends ShipConfig: `max_health` mirrors `core_health` (the armoured hull's bar, which only the core's
## death empties), `collision_damage` is the ARMOR touch, `score_value` the boss kill.
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow `ShipConfig.privatise()` copy is complete.
## Values are §2.16's [judgement] unless marked. The phase rules themselves are `BossPhase` sub-resources on the scene's `PhaseDriver`; the two numbers
## they share with this file (`shields_exposed_battery_losses`, `critical_core_ratio`) must stay equal to the scene's (pinned by test_space_fortress.gd).
## Movement (t6), batteries (t7), geometry weapons (t16) and bays (t8) append their own groups.
class_name SpaceFortressConfig
extends ShipConfig

@export_group("Parts")
## HP of each of the five outer batteries (station turret 120, scaled for ~5 s of focused default fire).
@export var battery_health: int = 260
@export var hangar_health: int = 300
## HP of each of the two shield generators (`shield_north`, `shield_south`).
@export var shield_node_health: int = 360
## HP of the core: its death is the fortress's. The root `Health` is written to the same value (the death plumbing; hits never lower it).
@export var core_health: int = 1500

@export_group("Sector shields")
## Each sector bubble (one per live protected part while its generator lives): points, regen delay and time (s), reboot after a break (s) ...
@export var sector_shield_capacity: int = 120
@export var sector_shield_regen_delay: float = 3.0
@export var sector_shield_regen_seconds: float = 2.0
@export var sector_shield_reboot_seconds: float = 5.0
## ... and its radius over the part hurtbox's (px).
@export var sector_shield_pad: float = 8.0

@export_group("Phases")
## `shields_exposed` is entered once this many batteries are wrecks (Ph11 owner choice 2). Equal to the scene's `BossPhase.count`.
@export var shields_exposed_battery_losses: int = 2
## `critical` is entered once the core is at or below this share of its health. Equal to the scene's `BossPhase.health_ratio`.
@export var critical_core_ratio: float = 0.4
## In `critical` the core light alternates COMMIT / OFF every this many seconds (`StateLight` has no COMMIT blink).
@export var core_blink_period: float = 0.25

@export_group("Death")
## Seconds the wreck stays in the tree after the core dies (station 1.8, scaled to the hull) ...
@export var death_sequence_duration: float = 2.4
## ... with this many chained blasts (`BossDeathSequence`).
@export var death_blast_count: int = 10

@export_group("EMP")
## Every EMP window on the fortress is this share of the source's (Ph11 owner choice 6; every source, never while dying).
@export var emp_factor: float = 0.4

@export_group("Escorts")
## Most live escorts at once (the `BossReinforcements` cap): Open Space (the Carrier's 6) / Assault (the station's 4).
@export var escort_cap_open_space: int = 6
@export var escort_cap_assault: int = 4
## An escort leaves its bay with this committed outward boost (px/s, s; the Carrier's launch).
@export var escort_boost_speed: float = 300.0
@export var escort_boost_seconds: float = 0.4
