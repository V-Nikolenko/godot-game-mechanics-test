## Generic idle -> combat handover for a brain patrolling a fixed anchor
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.5). A brain owns one, feeds it `delta`,
## its own `global_position` and a `TargetInfo` every tick, and reads back which of IDLE /
## NOTICING / COMBAT / RETURNING it is in. It decides *when* only - the idle/return motion is the
## brain's own request (§2.7.3, §2.8.4), and AnchorIdle never touches velocity or rotation.
##
## Hysteresis is the point of having two radii: COMBAT only drops to RETURNING beyond
## `lose_radius`, so a target drifting back and forth across `perceive_radius` (while staying
## under `lose_radius`) never flips state. `perceive_radius >= lose_radius` would remove that
## margin entirely, so it is rejected at construction.
class_name AnchorIdle
extends RefCounted

enum State { IDLE, NOTICING, COMBAT, RETURNING }

var anchor: Vector2
var perceive_radius: float
var lose_radius: float
var notice_time: float
## RETURNING reaches IDLE once within this distance of `anchor` - the drone's idle orbit ring, not
## the anchor point itself (Swarm ~170, Razor ~200; see plan §2.5, §2.7.3, §2.8.4 and plan-review
## N16). A brain that idles tighter or looser than the default should pass its own ring radius.
var home_radius: float
## An external reason to keep fighting (e.g. a squad mate still engaged). While true, COMBAT
## never drops to RETURNING regardless of distance. Clearing it re-checks on the next update().
var hold_combat: bool = false

var _state := State.IDLE
var _notice_elapsed: float = 0.0


func _init(p_anchor: Vector2, p_perceive_radius: float, p_lose_radius: float, p_notice_time: float, p_home_radius: float = 8.0) -> void:
	anchor = p_anchor
	perceive_radius = p_perceive_radius
	notice_time = p_notice_time
	home_radius = p_home_radius
	if p_perceive_radius >= p_lose_radius:
		push_error("AnchorIdle: perceive_radius (%s) must be < lose_radius (%s); clamping" % [p_perceive_radius, p_lose_radius])
		lose_radius = p_perceive_radius * 1.25
	else:
		lose_radius = p_lose_radius


## IDLE or RETURNING -> NOTICING immediately (a squad mate saw the target). No-op from NOTICING
## or COMBAT.
func force_notice() -> void:
	if _state == State.IDLE or _state == State.RETURNING:
		_enter_noticing()


## Advances the state by one tick and returns the resulting State (as int - see
## SquadController.claim_side for why this boundary uses int rather than the enum type).
func update(delta: float, actor_pos: Vector2, target: TargetInfo) -> int:
	match _state:
		State.IDLE:
			if _within(actor_pos, target, perceive_radius):
				_enter_noticing()
		State.NOTICING:
			_notice_elapsed += delta
			if _notice_elapsed >= notice_time:
				_state = State.COMBAT
		State.COMBAT:
			if not hold_combat and not _within(actor_pos, target, lose_radius):
				_state = State.RETURNING
		State.RETURNING:
			if _within(actor_pos, target, perceive_radius):
				_enter_noticing()
			elif actor_pos.distance_squared_to(anchor) <= home_radius * home_radius:
				_state = State.IDLE
	return _state


func _enter_noticing() -> void:
	_state = State.NOTICING
	_notice_elapsed = 0.0


func _within(actor_pos: Vector2, target: TargetInfo, radius: float) -> bool:
	return target.has_target and actor_pos.distance_squared_to(target.position) <= radius * radius
