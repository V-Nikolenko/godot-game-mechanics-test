## WallBarrier — generic wall-collision component for the race mode.
##
## Drop a Node2D with this script anywhere in the scene, then add any number of
## StaticBody2D children, each with ONE CollisionShape2D (RectangleShape2D). Each
## StaticBody2D is one wall piece — size and place them freely to match the level
## (e.g. separate pieces for the side walls and the start / finish stands).
##
## Two effects per piece:
##   • Hard barrier — the StaticBody2D (collision_layer = 1) blocks the player's
##     move_and_slide. Pure physics; works for any size/position.
##   • Damage + knockback — a geometric point-in-rect poll (this script) detects
##     contact for EVERY ship, including AI racers (which are assignment-positioned
##     and pass through StaticBody2D), and routes the hit through WallImpact.resolve.
##
## Detection is full 2D (both axes) against each shape's global transform, so pieces
## of different sizes/positions are handled independently and may be parented under a
## scrolling Track without any special-casing.
class_name WallBarrier
extends Node2D

## Damage dealt per contact — routed through HurtBox so shields absorb first.
@export var wall_damage: int = 15
## Lateral position nudge (px) applied to AI ships on contact.
@export var wall_ai_push: float = 60.0
## Seconds before the same ship can be hit again (prevents per-frame spam).
@export var hit_cooldown: float = 0.6
## Extra margin (px) added to the lateral edge of each rect so a CharacterBody2D
## stopped one body-radius outside the wall by physics still registers a hit.
@export var wall_margin: float = 20.0

## String(instance_id) → seconds remaining until the ship can be hit again.
var _cooldowns: Dictionary = {}
## Every CollisionShape2D found anywhere under this node at _ready (recursive).
var _shapes: Array[CollisionShape2D] = []

func _ready() -> void:
	# Collect every CollisionShape2D under this node, at any depth — robust to how the
	# wall pieces are wrapped in the scene. Each shape should live under a StaticBody2D
	# (collision_layer = 1) so move_and_slide stops the player; this poll adds the
	# damage/knockback on top and also covers AI racers that pass through physics.
	_collect_shapes(self)
	if _shapes.is_empty():
		push_warning("WallBarrier '%s': no CollisionShape2D found — walls will do nothing." % name)

func _collect_shapes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			_shapes.append(child as CollisionShape2D)
		_collect_shapes(child)

func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	if _shapes.is_empty():
		return

	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ship := n as Node2D
			if ship == null:
				continue
			## Require a RaceParticipant so stray group members don't cause errors.
			if ship.get_node_or_null("RaceParticipant") == null:
				continue
			var key := str(ship.get_instance_id())
			if _cooldowns.has(key):
				continue

			var pos := ship.global_position
			for shape in _shapes:
				if _point_in_shape(pos, shape, wall_margin):
					_cooldowns[key] = hit_cooldown
					## Push the ship away from the side it's on (toward the lane centre).
					var dir := signf(pos.x - shape.global_position.x)
					WallImpact.resolve(ship, dir if dir != 0.0 else 1.0,
						wall_damage, wall_ai_push)
					break  ## one wall contact per ship per tick

## Full 2D point-in-rect test against a shape's global transform. x_margin widens the
## rect's local-X (lateral) extent only, so a ship physically stopped one body-radius
## outside still registers. Handles the shape being parented under a scrolling node.
func _point_in_shape(world_pos: Vector2, col: CollisionShape2D, x_margin: float) -> bool:
	var rect := col.shape as RectangleShape2D
	if rect == null:
		return false
	var local: Vector2 = col.get_global_transform().affine_inverse() * world_pos
	var half := rect.size * 0.5
	return absf(local.x) < half.x + x_margin and absf(local.y) < half.y

func _tick_cooldowns(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
	for key in _cooldowns.keys().filter(func(k): return _cooldowns[k] <= 0.0):
		_cooldowns.erase(key)
