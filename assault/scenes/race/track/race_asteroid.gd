## RaceAsteroid — places an existing asteroid as a static track hazard. Extends AsteroidBase
## for the visuals + rocket-break (HurtBox layer 512 / mask 32, damage_type 1=ROCKET), but it
## does NOT self-move or self-cull: it is a child of Track and scrolls with the world, living
## until it scrolls past. Joins "race_hazards" and exposes the lethal contract so HazardSystem
## one-shots ships on contact and Sensors can dodge it.
class_name RaceAsteroid
extends AsteroidBase

## Lethal footprint in px (roughly the asteroid's visible size).
@export var danger_size: Vector2 = Vector2(56, 56)

func _ready() -> void:
	super()                      ## AsteroidBase setup (sprite, Health, HurtBox, ContactHitBox)
	add_to_group("race_hazards")
	set_physics_process(false)   ## no contact-damage speed scaling; it rides Track, doesn't move
	## Lethal contact is handled centrally by HazardSystem; disable the per-asteroid
	## ContactHitBox so damage isn't double-applied through the shield path.
	if has_node("ContactHitBox"):
		($ContactHitBox as Node2D).set_deferred("monitoring", false)

## Hazard contract — world-space lethal rect, centred on this node.
func danger_rect() -> Rect2:
	return Rect2(global_position - danger_size * 0.5, danger_size)

## Hazard contract — lethal until it's been destroyed by a rocket.
func is_lethal_now() -> bool:
	return not was_killed
