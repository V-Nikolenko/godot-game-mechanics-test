## EmpPulse - the one EMP entry point (Phase 7 plan §2.8). Calls the duck-typed `apply_emp(seconds, source)` on every
## node in group `player` whose CENTRE is within `radius` (the `Hazards.pulse_damage()` distance rule) and returns how many
## it reached. The EMP mine calls it; Phase 9's EMP Pulse weapon and any jammer call it too and extend the target set
## (enemies, the player's seeking weapons) without changing this signature.
class_name EmpPulse
extends RefCounted


static func emit(tree: SceneTree, at: Vector2, radius: float, seconds: float, source: Node) -> int:
	if tree == null or seconds <= 0.0:
		return 0
	var reached := 0
	for node in tree.get_nodes_in_group(&"player"):
		var target := node as Node2D
		if target == null or target.is_queued_for_deletion() or not target.has_method(&"apply_emp"):
			continue
		if target.global_position.distance_to(at) > radius:
			continue
		target.apply_emp(seconds, source)
		reached += 1
	return reached
