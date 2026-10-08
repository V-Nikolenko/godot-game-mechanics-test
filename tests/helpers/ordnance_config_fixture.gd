## Stand-in for `BomberConfig` while t9 has not created its ordnance fields: the same field names
## the plan gives (3-plan.md §2.3/§2.4), the shipped tuning values. The enemy-ordnance tests and the
## per-kind lifetime rows read every speed and time from here instead of typing a number. Once
## `BomberConfig` carries these fields, point the callers at it and delete this file.
##
## No `class_name`: test-only types stay out of the global class list.
extends Resource

@export var gravity_bomb_speed: float = 120.0
@export var rail_bomb_speed: float = 120.0
@export var gravity_bomb_fuse: float = 1.0
@export var gravity_bomb_arm_delay: float = 0.3
@export var pursuit_launch_speed: float = 90.0
@export var pursuit_steer_window: float = 1.5
@export var pursuit_turn_rate: float = 1.2
@export var pursuit_final_speed: float = 380.0
@export var pursuit_lead: float = 0.6
@export var mine_eject_speed: float = 160.0
@export var mine_arm_delay: float = 0.5
@export var mine_warning: float = 0.5
@export var mine_life: float = 8.0
@export var max_mines_per_run: int = 5
@export var min_run_period: float = 4.0
@export var trigger_radius: float = 80.0
@export var pursuit_trigger_radius: float = 48.0
@export var gravity_blast_radius: float = 48.0
@export var gravity_blast_damage: int = 40
@export var mine_blast_radius: float = 48.0
@export var mine_blast_damage: int = 30
@export var pursuit_blast_radius: float = 40.0
@export var pursuit_blast_damage: int = 30
