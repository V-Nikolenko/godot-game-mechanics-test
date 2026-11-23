## BossPhase — one rung of a boss's phase ladder (IDEAS §25; Phase 11 §2.1, docs/plans/cmug256so0031m52wbxomst72/3-plan.md; built in t1).
##
## A flat, scene-authored `Resource` (a sub-resource of the host's `PhaseDriver`). It says WHEN the phase starts (`trigger`) and WHICH
## aspects of the fight it changes (`changes`), nothing more: `BossPhaseDriver` decides when it is entered and the host applies the
## consequences. **Never written at runtime** — `ResourceLoader` caches by path, so every instance of the boss shares it.
##
## §25 as a rule: every phase after the first changes at least two of movement, attacks, vulnerable areas, arena control, reinforcements
## and visuals (`BossPhaseDriver.validate()`, swept over every shipped ladder by `tests/integration/test_boss_phase_rules.gd`).
##
## Tests: tests/unit/test_boss_phase_driver.gd.
class_name BossPhase
extends Resource

## Append-only.
enum Trigger {
	## Entered when the driver binds (the first phase only).
	START,
	## `count` parts destroyed among `module_ids` (else among `roles`, else any part).
	PARTS_DESTROYED,
	## The `health_module` part's `Health` (empty = the host root's) is at or below `health_ratio` of its maximum.
	HEALTH_AT_OR_BELOW,
}

## Bit flags, append-only.
enum Change {
	MOVEMENT = 1,
	ATTACKS = 2,
	VULNERABLE = 4,
	ARENA = 8,
	REINFORCEMENTS = 16,
	VISUALS = 32,
}

@export var phase_id: StringName = &""
@export var trigger: Trigger = Trigger.START
## PARTS_DESTROYED: the parts to count, by `EnemyModule.module_id`. Wins over `roles` when both are set.
@export var module_ids: Array[StringName] = []
## PARTS_DESTROYED: the `EnemyModule.Role` values to count, used when `module_ids` is empty. Both empty counts any part.
@export var roles: Array[int] = []
## PARTS_DESTROYED: how many of the counted parts must be wrecks.
@export var count: int = 1
## HEALTH_AT_OR_BELOW: the part whose `Health` is read; empty = the host root's `Health`.
@export var health_module: StringName = &""
## HEALTH_AT_OR_BELOW: the fraction of maximum health, strictly between 0 and 1. Reached exactly at the boundary (`current <= ratio * max`).
@export var health_ratio: float = 0.5
## The aspects this phase changes; the host's `phase_snapshot()` must show each one.
@export_flags("Movement", "Attacks", "Vulnerable", "Arena", "Reinforcements", "Visuals") var changes: int = 0


## How many aspects [param mask] sets.
static func change_count(mask: int) -> int:
	var n := 0
	for bit in [Change.MOVEMENT, Change.ATTACKS, Change.VULNERABLE, Change.ARENA, Change.REINFORCEMENTS, Change.VISUALS]:
		if mask & bit != 0:
			n += 1
	return n
