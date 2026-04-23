## ClusterFormation — ships randomly scattered within a radius.
## Fixed random_seed ensures deterministic placement every run.
class_name ClusterFormation
extends FormationResource

@export var count: int = 4
@export var radius: float = 30.0
@export var random_seed: int = 42
@export var stagger_delay: float = 0.0

func compute_slots() -> Array:
	var slots: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for i: int in count:
		var angle: float = rng.randf() * TAU
		var dist: float = rng.randf() * radius
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		slots.append(FormationResource.FormationSlot.new(offset, stagger_delay * i))
	return slots
