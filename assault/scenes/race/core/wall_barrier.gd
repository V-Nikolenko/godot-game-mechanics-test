## WallBarrier — generic vertical wall-collision component for the race mode.
##
## Drop a Node2D with this script anywhere in the scene.  Add StaticBody2D children
## (each with ONE CollisionShape2D / RectangleShape2D) to define the walls.
##
## Detection logic checks X distance to each wall's shape centre ONLY — no Y check.
## Side walls run the full track height by definition, so the Y centre of the shape
## in the editor is irrelevant and is deliberately ignored here.  This makes the
## component immune to the Godot editor repositioning shapes vertically on save.
##
## Hard barrier for the player:
##   • StaticBody2D (collision_layer = 1) blocks move_and_slide — pure physics.
##   • As a fallback, _physics_process also clamps the player's X to the innermost
##     face of each wall, matching what the physics would do if for any reason it
##     does not trigger.
class_name WallBarrier
extends Node2D

## Damage dealt per contact — routed through HurtBox so shields absorb first.
@export var wall_damage: int = 15
## Lateral position nudge (px) applied to AI ships on contact.
@export var wall_ai_push: float = 60.0
## Seconds before the same ship can be hit again (prevents per-frame spam).
@export var hit_cooldown: float = 0.6
## Extra X width added to each contact test.  A CharacterBody2D stopped by the
## StaticBody2D sits with its CENTRE one body-radius outside the rect; this margin
## makes it register.  Default 20 matches DashPanel.WALL_MARGIN (radius ≈ 14 px).
@export var wall_margin: float = 20.0

## String(instance_id) → seconds remaining until the ship can be hit again.
var _cooldowns: Dictionary = {}
## All CollisionShape2D nodes discovered from StaticBody2D children at _ready.
var _shapes: Array[CollisionShape2D] = []

func _ready() -> void:
	for child in get_children():
		if not child is StaticBody2D:
			continue
		for sub in child.get_children():
			if sub is CollisionShape2D:
				_shapes.append(sub as CollisionShape2D)

func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	if _shapes.is_empty():
		return

	## Pre-compute wall inner faces so the player clamp can use the same values.
	## inner_faces: Array of [inner_x, push_dir] where push_dir shoves away from the wall.
	var inner_faces: Array = _compute_inner_faces()

	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ship := n as Node2D
			if ship == null:
				continue
			if ship.get_node_or_null("RaceParticipant") == null:
				continue

			## Hard X clamp for the player — ensures they cannot pass through the wall
			## even if the StaticBody2D physics did not catch them.
			if ship.has_method("apply_knockback"):
				for face: Array in inner_faces:
					var ix: float = face[0]
					var pd: float = face[1]
					## pd > 0 → push right (wall is on the left), clamp from below.
					## pd < 0 → push left  (wall is on the right), clamp from above.
					if pd > 0.0 and ship.global_position.x < ix:
						ship.global_position.x = ix
					elif pd < 0.0 and ship.global_position.x > ix:
						ship.global_position.x = ix

			var key := str(ship.get_instance_id())
			if _cooldowns.has(key):
				continue

			var pos := ship.global_position
			for shape in _shapes:
				if _near_wall_x(pos.x, shape):
					_cooldowns[key] = hit_cooldown
					var dir := signf(pos.x - _shape_center_x(shape))
					WallImpact.resolve(ship, dir if dir != 0.0 else 1.0,
						wall_damage, wall_ai_push)
					break

func _compute_inner_faces() -> Array:
	## Returns [[inner_x, push_dir], ...] for each shape.
	## The inner face is the edge of the shape closest to the track centre (x = 640).
	var result: Array = []
	for shape in _shapes:
		var cx := _shape_center_x(shape)
		var hw := _shape_half_width(shape)
		## Wall on the left → inner face is the RIGHT edge (cx + hw), push right (+1).
		## Wall on the right → inner face is the LEFT  edge (cx - hw), push left  (−1).
		if cx < 640.0:
			result.append([cx + hw, 1.0])
		else:
			result.append([cx - hw, -1.0])
	return result

## X-only contact test — ship centre within (half_width + wall_margin) of wall centre.
func _near_wall_x(ship_x: float, col: CollisionShape2D) -> bool:
	return absf(ship_x - _shape_center_x(col)) < _shape_half_width(col) + wall_margin

func _shape_center_x(col: CollisionShape2D) -> float:
	return col.get_global_transform().get_origin().x

func _shape_half_width(col: CollisionShape2D) -> float:
	var rect := col.shape as RectangleShape2D
	if rect == null:
		return 0.0
	return rect.size.x * 0.5 * col.get_global_transform().get_scale().x

func _tick_cooldowns(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
	for key in _cooldowns.keys().filter(func(k): return _cooldowns[k] <= 0.0):
		_cooldowns.erase(key)
