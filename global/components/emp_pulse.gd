## EmpPulse - the one EMP entry point (Phase 7 plan §2.8, extended by Phase 9 §2.6). Every target set uses one rule:
## a node is reached when its CENTRE is within `radius` (the `Hazards.pulse_damage()` distance rule).
##
## `targets` is a bitmask, `TARGET_PLAYER` by default, so every Phase 7 call is unchanged:
## - `TARGET_PLAYER`: the duck-typed `apply_emp(seconds, source)` on every node in group `player`.
## - `TARGET_ENEMIES`: `apply_emp(seconds, source)` on every node in group `enemies` whose duck-typed `answers_emp()` is
##   true (`BaseEnemy.answers_emp()`: the routing question every EMP source asks).
## - `TARGET_SEEKERS`: the duck-typed `jam_guidance(source)` on every seeking rocket of either side
##   (`SeekingOrdnance.GROUP`, `SeekingOrdnance.ENEMY_GROUP`): it loses its guidance and flies straight.
## Returns how many ships it reached (player + enemies); seekers are never counted.
class_name EmpPulse
extends RefCounted

const TARGET_PLAYER := 1
const TARGET_ENEMIES := 2
const TARGET_SEEKERS := 4
const TARGET_ALL := 7


static func emit(tree: SceneTree, at: Vector2, radius: float, seconds: float, source: Node,
		targets: int = TARGET_PLAYER) -> int:
	if tree == null or seconds <= 0.0:
		return 0
	var reached := 0
	if targets & TARGET_PLAYER:
		for node in tree.get_nodes_in_group(&"player"):
			var target := node as Node2D
			if target == null or target.is_queued_for_deletion() or not target.has_method(&"apply_emp"):
				continue
			if target.global_position.distance_to(at) > radius:
				continue
			target.apply_emp(seconds, source)
			reached += 1
	if targets & TARGET_ENEMIES:
		for node in tree.get_nodes_in_group(&"enemies"):
			var enemy := node as Node2D
			if enemy == null or enemy.is_queued_for_deletion():
				continue
			if not enemy.has_method(&"answers_emp") or not enemy.has_method(&"apply_emp"):
				continue
			if enemy.global_position.distance_to(at) > radius or not enemy.answers_emp():
				continue
			enemy.apply_emp(seconds, source)
			reached += 1
	if targets & TARGET_SEEKERS:
		for group: StringName in [SeekingOrdnance.GROUP, SeekingOrdnance.ENEMY_GROUP]:
			for node in tree.get_nodes_in_group(group):
				var seeker := node as Node2D
				if seeker == null or seeker.is_queued_for_deletion() or not seeker.has_method(&"jam_guidance"):
					continue
				if seeker.global_position.distance_to(at) > radius:
					continue
				seeker.jam_guidance(source)
	return reached
