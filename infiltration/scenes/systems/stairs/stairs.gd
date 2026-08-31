@tool
extends Area2D
class_name StairAssist

@export var top_height: float = 48.0
@export var bottom_height: float = 0.0
@export var top_local_point: Vector2 = Vector2.ZERO
@export var bottom_local_point: Vector2 = Vector2.ZERO
@export var show_debug_direction: bool = true
@export var top_marker_color: Color = Color(0.2, 1.0, 0.35, 0.95)
@export var bottom_marker_color: Color = Color(1.0, 0.3, 0.3, 0.95)

@onready var col_poly: CollisionPolygon2D = $CollisionPolygon2D
var tracked_bodies: Array[Node2D] = []


func _ready() -> void:
	if top_local_point == Vector2.ZERO and bottom_local_point == Vector2.ZERO:
		_guess_points_from_polygon()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	queue_redraw()

	if Engine.is_editor_hint():
		return

	for body in tracked_bodies:
		if not is_instance_valid(body):
			continue

		if body.has_method("set_environment_elevation"):
			body.set_environment_elevation(self, _get_height_for_body(body))


func _on_body_entered(body: Node2D) -> void:
	if tracked_bodies.has(body):
		return

	tracked_bodies.append(body)

	if body.has_method("set_environment_elevation"):
		body.set_environment_elevation(self, _get_height_for_body(body))


func _on_body_exited(body: Node2D) -> void:
	tracked_bodies.erase(body)

	if body.has_method("clear_environment_elevation"):
		body.clear_environment_elevation(self)


func _get_height_for_body(body: Node2D) -> float:
	var stair_axis := top_local_point - bottom_local_point
	if stair_axis.length_squared() <= 0.001:
		return bottom_height

	var body_local_position := to_local(body.global_position)
	var progress := (body_local_position - bottom_local_point).dot(stair_axis) / stair_axis.length_squared()
	progress = clampf(progress, 0.0, 1.0)
	return lerpf(bottom_height, top_height, progress)


func _guess_points_from_polygon() -> void:
	if col_poly.polygon.is_empty():
		return

	var highest_point := col_poly.polygon[0]
	var lowest_point := col_poly.polygon[0]
	for point in col_poly.polygon:
		if point.y < highest_point.y:
			highest_point = point
		if point.y > lowest_point.y:
			lowest_point = point

	top_local_point = highest_point
	bottom_local_point = lowest_point


func _draw() -> void:
	if not show_debug_direction:
		return

	var stair_axis := top_local_point - bottom_local_point
	if stair_axis.length_squared() <= 0.001:
		return

	var direction := stair_axis.normalized()
	var arrow_size := 12.0
	var arrow_side := direction.orthogonal() * 5.0
	var arrow_tip := top_local_point
	var arrow_base := top_local_point - direction * arrow_size

	draw_line(bottom_local_point, top_local_point, Color(1.0, 1.0, 1.0, 0.85), 2.0)
	draw_circle(top_local_point, 5.0, top_marker_color)
	draw_circle(bottom_local_point, 5.0, bottom_marker_color)
	draw_line(arrow_base + arrow_side, arrow_tip, top_marker_color, 2.0)
	draw_line(arrow_base - arrow_side, arrow_tip, top_marker_color, 2.0)

	var font := ThemeDB.fallback_font
	var font_size := 12
	if font != null:
		draw_string(font, top_local_point + Vector2(8.0, -8.0), "UP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, top_marker_color)
		draw_string(font, bottom_local_point + Vector2(8.0, 14.0), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, bottom_marker_color)
