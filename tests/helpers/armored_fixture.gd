## A hull that deflects (hit-blind `is_armored()`, like the space station's core) with one
## `ArmorPlate` in front, for tests/integration/test_armor_query.gd. Declares NO `homing_point`
## — that is the control for "a target without the method behaves as before". No `class_name`:
## test-only. Build with `make()`.
extends Node2D

const HULL_RADIUS: float = 40.0
const PLATE_OFFSET := Vector2(0.0, -30.0)

var plates: Node2D
var plate: ArmorPlate
var hull: HurtBox




func _ready() -> void:
	hull = HurtBox.new()
	hull.name = "HurtBox"
	hull.collision_layer = CollisionLayers.ENEMY_HURTBOX
	hull.collision_mask = CollisionLayers.PLAYER_ROCKETS | CollisionLayers.PLAYER_HITBOX
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HULL_RADIUS
	shape.shape = circle
	hull.add_child(shape)
	add_child(hull)

	plates = Node2D.new()
	plates.name = "Plates"
	add_child(plates)
	plate = ArmorPlate.new()
	plate.name = "PlateFront"
	plate.position = PLATE_OFFSET
	plates.add_child(plate)


## The hull deflects everything (the plate answers for itself).
func is_armored() -> bool:
	return true
