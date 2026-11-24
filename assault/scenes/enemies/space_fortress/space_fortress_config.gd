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

@export_group("Movement")
## The facing rule's turn rate (rad/s): Open Space / Assault. A circling player at 500 px out-turns either (plan §2.6: ≤ ¼ of 0.84 rad/s).
@export var turn_rate: float = 0.22
@export var assault_turn_rate: float = 0.30
## The volley spin (t16's `begin_spin()`), the `critical` continuous spin and the Open Space hub idle spin (rad/s).
@export var beam_spin_rate: float = 0.5
@export var critical_spin_rate: float = 0.6
@export var idle_spin_rate: float = 0.08
## Open Space hub idle (`AnchorIdle`): notice inside `perceive_radius` after `notice_time` s, give up beyond `lose_radius`, home within `home_radius` (px).
@export var perceive_radius: float = 1400.0
@export var lose_radius: float = 2600.0
@export var notice_time: float = 0.8
@export var home_radius: float = 8.0
## Open Space combat zone round `patrol_anchor` (px): station points lie on the circle of `station_ring_factor` × `zone_radius`, each at least
## `reposition_min_step` from the last, the one farthest from where the player will be `reposition_lookahead` s ahead.
@export var zone_radius: float = 600.0
@export var station_ring_factor: float = 0.6
@export var reposition_min_step: float = 250.0
@export var reposition_lookahead: float = 1.0
## A new station point every this many seconds (`core_exposed` / `critical`), reached at this speed (px/s); also the speed home to the anchor.
@export var reposition_period: float = 8.0
@export var critical_reposition_period: float = 5.0
@export var reposition_speed: float = 60.0
@export var critical_reposition_speed: float = 90.0
## A held station point: corrected only beyond `hold_tolerance` px, at `hold_speed` px/s.
@export var hold_tolerance: float = 24.0
@export var hold_speed: float = 40.0
## Assault: the descent speed (px/s) to the hold line (world y), then from `core_exposed` a vertical bob of ± `assault_bob_amplitude` px at
## `assault_bob_speed` (`critical_bob_speed` in `critical`). x never moves: only a correction back to the anchored x, at most `assault_x_correct_speed`.
@export var assault_enter_speed: float = 90.0
@export var assault_hold_y: float = 180.0
@export var assault_bob_amplitude: float = 100.0
@export var assault_bob_speed: float = 35.0
@export var critical_bob_speed: float = 55.0
@export var assault_x_correct_speed: float = 20.0

@export_group("Escorts")
## Most live escorts at once (the `BossReinforcements` cap): Open Space (the Carrier's 6) / Assault (the station's 4).
@export var escort_cap_open_space: int = 6
@export var escort_cap_assault: int = 4
## An escort leaves its bay with this committed outward boost (px/s, s; the Carrier's launch).
@export var escort_boost_speed: float = 300.0
@export var escort_boost_seconds: float = 0.4

@export_group("Batteries")
## At most this many battery mounts are in TELEGRAPH or FIRE at once (`FortressBrain.attack_gate()`), `critical_max_concurrent_attacks` in `critical`:
## never a wall of five bursts (plan §2.7.1).
@export var max_concurrent_attacks: int = 2
@export var critical_max_concurrent_attacks: int = 3
## In `critical` every live battery's `cooldown_seconds` is multiplied by this, once, on the instanced mount nodes. The five battery slots author
## `pool_period_factor` equal to it, so the pools are sized for the shorter period (pinned by test_fortress_weapons.gd).
@export var critical_cooldown_factor: float = 0.6
