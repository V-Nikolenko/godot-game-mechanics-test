## The Space Fortress's brain (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.5, §2.6; Phase 11 t5 builds this SHELL, task plan
## docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md). t6 adds the movement (facing, spins, the Open Space combat zone, the Assault hold and bob), t7 the
## batteries and the attack gate, t16 the geometry weapons, t8 the bays; each fills the hooks below without changing their names.
##
## What the shell does: ticks the fortress's `BossReinforcements` (its only clock; held while not engaged), hears the boss phase ladder through
## `on_boss_phase()`, silences everything it ticks when an EMP window starts (`on_emp_started()`: every attached mount `scan(0.0)`s and the bays get
## one `tick(0.0, false)`, because the brain is not ticked during the window) and when the fortress dies (`silence()`), and refuses tows.
##
## TWO PHASE ENUMS, NEVER MIXED: the boss phase ladder (`BossPhaseDriver` on the root: batteries -> shields_exposed -> core_exposed -> critical) and
## this brain's movement `Phase` below (append-only). `is_engaged()` is HOLD or REPOSITION in both modes: weapons fire and bays run only then.
##
## Requests only (single-writer gate): this brain never writes the body's velocity or rotation.
class_name FortressBrain
extends EnemyBrain

## Append-only. IDLE / NOTICING / RETURNING: the Open Space hub idle; ENTER: the Assault descent; HOLD / REPOSITION: engaged.
enum Phase { IDLE, NOTICING, RETURNING, ENTER, HOLD, REPOSITION }

## Set by `space_fortress.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: SpaceFortressConfig = SpaceFortressConfig.new()
var phase: Phase = Phase.IDLE
## Test seam (t6 reads it): an Open Space fortress starts engaged, skipping the hub idle.
var start_engaged: bool = false

var _hull: ModularHull
var _reinforcements: BossReinforcements


## Hands the brain its parts and its bays (called by the root in `_ready()`).
func bind(hull: ModularHull, reinforcements: BossReinforcements) -> void:
	_hull = hull
	_reinforcements = reinforcements


func tick(delta: float) -> void:
	if _reinforcements != null:
		_reinforcements.tick(delta, is_engaged())


## True in HOLD or REPOSITION (both modes). A stub until t6 builds the movement phases: false.
func is_engaged() -> bool:
	return false


## The batteries' shared `TurretMount.telegraph_gate` (zero arguments). A stub until t7: false.
func attack_gate() -> bool:
	return false


## The boss phase ladder entered [param phase_id] (`SpaceFortress._on_phase_entered`). t6, t7, t16 and t8 add their consequences here.
func on_boss_phase(_phase_id: StringName) -> void:
	pass


## An EMP window started: nothing this brain ticks may hang lit or open through it (the brain is not ticked for the window).
func on_emp_started() -> void:
	_scan_mounts()
	if _reinforcements != null:
		_reinforcements.tick(0.0, false)


## The fortress's death started (after `suspend_ai()`): every mount is already powered down by the root; t16 cancels its beams and rings here.
func silence() -> void:
	pass


## A boss is never towed.
func accepts_tow() -> bool:
	return false


## §25 snapshot parts this brain owns, `[]` until their task builds them: movement (t6), attacks (t7, t16), arena (t16).
func movement_snapshot() -> Array:
	return []


func attacks_snapshot() -> Array:
	return []


func arena_snapshot() -> Array:
	return []


func reinforcements() -> BossReinforcements:
	return _reinforcements


func _scan_mounts() -> void:
	if _hull == null:
		return
	for part in _hull.modules():
		for mount in part.mounts():
			if is_instance_valid(mount):
				mount.scan(0.0)
