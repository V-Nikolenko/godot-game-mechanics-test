## The decision half of an AI-driven enemy (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.3).
##
## A brain is a child `Node` of the enemy. It *decides*; its sibling `EnemyMover` *moves*. The owner
## (`BaseEnemy._physics_process`) calls `tick(delta)` once per physics frame and then
## `mover.step(delta)`, so a brain's requests are applied in the same frame they are made.
##
## Rules every concrete brain follows:
## - **Clock:** accumulate `delta` in `tick()`. No `Timer` nodes — GUT's `simulate()` does not fire
##   them, and a brain must be steppable frame by frame in a test.
## - **Randomness:** draw only from `rng`. `rng_seed != 0` makes a run reproducible; 0 randomizes.
## - **Perception:** find and predict the player through `TargetInfo.player(tree)` only — never
##   `get_nodes_in_group("player")`.
## - **Movement:** request it from `mover` (`request_velocity`, the `Steering` wrappers, `boost`,
##   `face_toward`). A brain never writes `actor.velocity` / `actor.rotation` and never calls
##   `move_and_slide()` — `EnemyMover` is the single writer, gated by
##   `tests/integration/test_enemy_mover_single_writer.gd`.
## - **Fire:** through `attack` (an `AttackController` with `driven_by_brain = true` is ticked by
##   the brain via `attack.tick(delta)`; `fire_now()` for telegraphed shots).
## - **Suspension:** `on_suspended()` runs once when a rail (`EnemyPathMover`) takes the enemy
##   over via `BaseEnemy.suspend_ai()`; `tick()` is never called again after it.
##
## State vocabulary (IDEAS §4). These are *names*, not an enforced enum: each enemy keeps a 3-5
## state `enum` of its own (or `State` children, for a complex one) and maps onto these words in
## its comments, so designers can compare enemies in one language:
## - SPAWN — entering the fight (off-screen entry, launch from a carrier).
## - SEARCH — no target known; patrol / idle.
## - APPROACH — closing to engagement range.
## - POSITION — taking up an attack position (orbit, stand-off, flank).
## - ATTACK — committing: firing, dashing, ramming.
## - EVADE — dodging an immediate threat.
## - REPOSITION — breaking off to find a new position.
## - DISENGAGE — leaving the fight.
## - PANIC — low-health / leaderless behaviour.
## - DESTROYED — death sequence.
##
## A concrete brain that overrides `_ready()` must call `super._ready()`, which resolves `actor`,
## `mover` and `attack`.
class_name EnemyBrain
extends Node

## 0 = `rng.randomize()` in `_ready()`; any other value seeds `rng` with it, so the same seed gives
## the same decision sequence.
@export var rng_seed: int = 0

## The enemy body this brain drives: the parent, if it is a `CharacterBody2D`. Typed against the
## engine class, not `BaseEnemy`, so nothing in `global/` depends on an Assault class.
var actor: CharacterBody2D
## The first sibling that is an `EnemyMover`, or null.
var mover: EnemyMover
## The first sibling that is an `AttackController`, or null.
var attack: AttackController
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	var parent := get_parent()
	actor = parent as CharacterBody2D
	if parent == null:
		return
	for sibling in parent.get_children():
		if mover == null and sibling is EnemyMover:
			mover = sibling
		elif attack == null and sibling is AttackController:
			attack = sibling


## Virtual: decide this physics frame. Called by the owner before `mover.step(delta)`.
func tick(_delta: float) -> void:
	pass


## Virtual: the enemy's AI was suspended (a rail took it over). Called once.
func on_suspended() -> void:
	pass
