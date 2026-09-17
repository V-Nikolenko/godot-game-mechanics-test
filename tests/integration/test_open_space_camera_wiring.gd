## INTENT tests for the wiring between OpenSpacePlayerShip and OpenSpaceCameraRig — the
## anti-inert gate for this epic's headline bug fix
## (`docs/plans/open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy/3-plan.md` →
## Design → Thread 2).
##
## Every case in tests/unit/test_open_space_camera_rig.gd is green on a build where
## OpenSpaceCameraRig exists only as a script that was never added to player_ship.tscn, and
## on a build where the OLD `facing * _LEAD_MAX * t` formula is still wired up — step()
## never receives `rotation`, so nothing at the unit level can see that regression. THIS is
## the file that fails on both: it drives a REAL ship, with a REAL rotation, under a
## Camera2D + CameraDirector harness, and reads the effect actually pushed to the director.
##
## The harness reproduces sector_hub.tscn:80-85 exactly — a Camera2D named "Camera2D" as a
## DIRECT CHILD of the ship, with a CameraDirector as a child of THAT — because
## _update_camera_feel() finds both by get_node_or_null on those exact names
## (player_ship.gd) and silently returns if either is missing. Get the parenting wrong here
## and every case in this file passes vacuously.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0


## set_physics_process(false) immediately after spawning: once in the tree, the ship's real
## _physics_process would run _handle_rotation + _handle_thrust + move_and_slide against
## whatever get_global_mouse_position() returns headlessly, racing the hand-set
## rotation/velocity and the hand-called _update_camera_feel() below
## (tests/README.md's "keep _physics_process out of the tree and call it by hand").
func _spawn_ship() -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	return ship


func _rig_of(ship: Node) -> OpenSpaceCameraRig:
	## By CLASS, never by node path: a renamed node must not silently pass.
	for child: Node in ship.get_children():
		if child is OpenSpaceCameraRig:
			return child as OpenSpaceCameraRig
	return null


## Builds the sector_hub.tscn:80-85 camera harness under `ship` and returns the director.
func _attach_camera(ship: Node) -> CameraDirector:
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	ship.add_child(cam)
	var director := CameraDirector.new()
	director.name = "CameraDirector"
	cam.add_child(director)
	return director


func test_rig_is_a_direct_child_of_the_ship_found_by_class() -> void:
	var ship := _spawn_ship()
	assert_not_null(_rig_of(ship),
			"OpenSpaceCameraRig must be wired into player_ship.tscn as a direct child")


func test_a_physics_frame_pushes_a_speed_feel_effect_matching_the_rig() -> void:
	var ship := _spawn_ship()
	var director := _attach_camera(ship)
	var rig := _rig_of(ship)

	ship.rotation = 0.0
	ship.velocity = Vector2(420.0, 0.0)
	ship._update_camera_feel(D)

	assert_true(director._effects.has(&"speed_feel"),
			"one physics frame must push a speed_feel effect into the director")
	assert_eq(director._effects[&"speed_feel"]["offset"], rig.get_offset(),
			"the pushed offset must be exactly what the rig computed")


## THE DEFINING CASE (plan review B1): only here is `rotation` real. Nose pointing DOWN
## (rotation = PI) while travelling UP (velocity = (0, -400)) must still lead the camera
## UP — where the ship is actually going, not where its nose points. This FAILS on the old
## `facing * _LEAD_MAX * t` formula, which reads (0, -400) rotated by PI as facing DOWN and
## leads the camera the wrong way.
func test_camera_leads_where_the_ship_travels_not_where_the_nose_points() -> void:
	var ship := _spawn_ship()
	var director := _attach_camera(ship)

	ship.rotation = PI       ## nose pointing down
	ship.velocity = Vector2(0.0, -400.0)  ## travelling up
	for _i in range(30):
		ship._update_camera_feel(D)

	var offset: Vector2 = director._effects[&"speed_feel"]["offset"]
	assert_lt(offset.y, 0.0,
			"travelling up must lead the camera up regardless of the nose's facing")


## The mirror case, so a stuck sign convention cannot pass the case above.
func test_camera_leads_where_the_ship_travels_mirror_case() -> void:
	var ship := _spawn_ship()
	var director := _attach_camera(ship)

	ship.rotation = 0.0      ## nose pointing up
	ship.velocity = Vector2(0.0, 400.0)   ## travelling down
	for _i in range(30):
		ship._update_camera_feel(D)

	var offset: Vector2 = director._effects[&"speed_feel"]["offset"]
	assert_gt(offset.y, 0.0,
			"travelling down must lead the camera down regardless of the nose's facing")
