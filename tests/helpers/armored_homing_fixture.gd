## `armored_fixture.gd` plus `homing_point()`: the nearest live plate, else the hull centre.
## No `class_name`: test-only.
extends "res://tests/helpers/armored_fixture.gd"


func homing_point(from: Vector2) -> Vector2:
	var best := global_position
	var best_d := INF
	for p in plates.get_children():
		var plate_node := p as ArmorPlate
		if plate_node == null or not plate_node.is_alive():
			continue
		var d := from.distance_squared_to(plate_node.global_position)
		if d < best_d:
			best_d = d
			best = plate_node.global_position
	return best
