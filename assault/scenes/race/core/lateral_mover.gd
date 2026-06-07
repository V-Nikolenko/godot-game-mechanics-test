## LateralMover — critically-damped horizontal glide toward a target X, clamped to arena bounds.
## Avoidance is OFFERED (avoidance_nudge); each brain decides whether to add it.
class_name LateralMover
extends Node

@export var smooth_tau: float = 0.12
@export var min_x: float = 80.0
@export var max_x: float = 1200.0
@export var avoid_radius: float = 110.0

func step(current_x: float, target_x: float, delta: float) -> float:
	var k := 1.0 - exp(-delta / maxf(0.01, smooth_tau))
	return clampf(lerpf(current_x, target_x, k), min_x, max_x)

## Sum of pushes away from hazards within avoid_radius in X and lookahead in Y. Brains opt in.
func avoidance_nudge(host: RaceShip, lookahead: float) -> float:
	var push := 0.0
	for grp in ["asteroids", "mines"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var h := n as Node2D
			if h == null:
				continue
			var diff := host.global_position - h.global_position
			if absf(diff.y) > lookahead or absf(diff.x) > avoid_radius:
				continue
			var away := signf(diff.x) if absf(diff.x) > 0.5 else 1.0
			push += away * (avoid_radius - absf(diff.x))
	return push
