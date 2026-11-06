## ShieldGeneratorBrain - the shield generator's projection (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.5; Phase 8 t9s).
##
## No mover. Each physics tick, through `BaseEnemy._physics_process`, while powered: every live `BaseEnemy` member of the host's turret group - except
## the host itself and a laser-fence post (`is_fence_post()` duck-typed; a `LaserFence` is not a `BaseEnemy` and is never a member's hull) - carries a
## 360 degree `EnemyShield` in sustain mode (the Support Ship's projected-shield path, `SupportShipBrain._make_shield`), fed `sustain(player position)`
## every tick. The bubble is a child of the member and takes its hurtbox's one absorber slot; if the slot is already held (a Support Ship's ward) the
## member is skipped and retried next tick - a ward is never displaced. Unpowered (`power_down()`), dead, or freed: no more `sustain()`, so every
## bubble lapses after its `heartbeat` and fades. Bubbles absorb bullets and rockets, never beams (direct emitters).
##
## It owns the cyan tethers (`Line2D`, `top_level`, `SupportShip.TETHER_COLOR`) to every member it shields. A tow is always refused (moot: no mover).
class_name ShieldGeneratorBrain
extends EnemyBrain

## Append-only.
enum Phase { IDLE, PROJECTING, UNPOWERED }

signal phase_changed(new_phase: int)

const SHIELD_NAME := &"GeneratorShield"
const TETHER_WIDTH := 2.0
## The bubble radius of a member with no body shape.
const DEFAULT_HULL_RADIUS := 30.0
## Where a bubble faces when there is no player to face, px ahead of the member.
const IDLE_FACING_DISTANCE := 100.0

var config: ShieldGeneratorConfig
var phase: int = Phase.IDLE

## Member -> its bubble.
var _shields: Dictionary = {}
## Member -> its tether.
var _lines: Dictionary = {}


func enter_phase(new_phase: int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(new_phase)


## Unpowered for good: no more `sustain()`, the tethers go at once, the bubbles lapse by themselves. Idempotent.
func power_down() -> void:
	if phase == Phase.UNPOWERED:
		return
	enter_phase(Phase.UNPOWERED)
	_shields.clear()
	_refresh_tethers()


func accepts_tow() -> bool:
	return false


func tick(_delta: float) -> void:
	if actor == null or config == null or not actor.is_inside_tree() or phase == Phase.UNPOWERED:
		return
	var generator := actor as ShieldGenerator
	var target := TargetInfo.player(actor.get_tree())
	var wanted := _eligible_members(generator)
	for member in _shields.keys():
		if not wanted.has(member):
			_shields.erase(member)
	for member: BaseEnemy in wanted:
		var shield := _shields.get(member) as EnemyShield
		if shield == null or not is_instance_valid(shield) or shield.is_queued_for_deletion():
			_shields.erase(member)
			shield = _make_shield(member)
			if shield == null:
				continue
			_shields[member] = shield
		shield.sustain(target.position if target.has_target else member.global_position + Vector2.DOWN * IDLE_FACING_DISTANCE)
	enter_phase(Phase.PROJECTING if not _shields.is_empty() else Phase.IDLE)
	_refresh_tethers()


## The tethers, refreshed now (a member killed since the last tick loses its line at once).
func tethers() -> Array[Line2D]:
	_refresh_tethers()
	var out: Array[Line2D] = []
	for line: Line2D in _lines.values():
		out.append(line)
	return out


## The live members of the host's group that may carry a bubble: not the host, not a fence post, with a hurtbox.
func _eligible_members(generator: ShieldGenerator) -> Array:
	var out: Array = []
	var group := generator.turret_group()
	if group == null or not is_instance_valid(group) or not group.has_method("members"):
		return out
	for member: Node2D in group.call("members"):
		var enemy := member as BaseEnemy
		if enemy == null or enemy == generator or enemy.is_queued_for_deletion() or enemy.hurt_box == null:
			continue
		if enemy.has_method("is_fence_post") and enemy.call("is_fence_post"):
			continue
		out.append(enemy)
	return out


## An `EnemyShield` in sustain mode on `member`'s hurtbox, or null when another absorber holds the slot (never displaced).
func _make_shield(member: BaseEnemy) -> EnemyShield:
	if member.hurt_box.has_absorber():
		return null
	var s := EnemyShield.new()
	s.name = SHIELD_NAME
	s.sustain_mode = true
	s.arc_deg = 360.0
	s.capacity = config.shield_capacity
	s.regen_delay = config.shield_regen_delay
	s.regen_seconds = config.shield_regen_seconds
	s.reboot_seconds = config.shield_reboot_seconds
	s.radius = _hull_radius(member) + config.shield_radius_margin
	if not s.attach(member.hurt_box):
		s.free()
		return null
	member.add_child(s, true)
	return s


## The member's body radius (its `CollisionShape2D`, circle or otherwise), else `DEFAULT_HULL_RADIUS`.
func _hull_radius(e: BaseEnemy) -> float:
	var body := e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body == null or body.shape == null:
		return DEFAULT_HULL_RADIUS
	var scale_max := maxf(absf(body.global_scale.x), absf(body.global_scale.y))
	if body.shape is CircleShape2D:
		return (body.shape as CircleShape2D).radius * scale_max
	return body.shape.get_rect().size.length() * 0.5 * scale_max


func _refresh_tethers() -> void:
	if actor == null:
		return
	var wanted: Array = []
	if phase != Phase.UNPOWERED:
		for member: Variant in _shields.keys():
			var shield := _shields[member] as EnemyShield
			if is_instance_valid(member) and not (member as Node).is_queued_for_deletion() \
					and is_instance_valid(shield) and not shield.is_queued_for_deletion():
				wanted.append(member)
	for member in _lines.keys():
		if not wanted.has(member):
			(_lines[member] as Line2D).free()
			_lines.erase(member)
	for member: Node2D in wanted:
		var line := _lines.get(member) as Line2D
		if line == null:
			line = Line2D.new()
			line.name = "Tether"
			line.top_level = true
			line.width = TETHER_WIDTH
			line.default_color = SupportShip.TETHER_COLOR
			line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
			actor.add_child(line)
			_lines[member] = line
		line.set_point_position(0, actor.global_position)
		line.set_point_position(1, member.global_position)
