## IntroCutscene — the first-launch cinematic.
##
## Beat plan:
##   0. Setup: camera zoomed out, ship at start position pointing toward
##      the top-right at `ship_heading_deg`.
##   1. Ship flies in from start_pos toward mid_pos while the camera
##      simultaneously zooms to gameplay zoom and recenters on the ship.
##   2. Brief pause for narrative breathing room (and future dialog).
##   3. Camera rotates so the ship's heading aligns with screen-up.
##   4. Ship drifts forward in its new (now visually-up) heading and the
##      cutscene transitions to the assault mission.
##
## All distances/times are exported so a designer can re-time the sequence
## from the editor.
class_name IntroCutscene
extends CutsceneBase

@onready var ship: Node2D = $Ship
@onready var sprite: Sprite2D = $Ship/Sprite2D
@onready var comet_trail: CPUParticles2D = $Ship/CometTrail
@onready var thruster: ThrusterEffect = $Ship/Thruster
@onready var camera: Camera2D = $Camera2D

@export_category("Cutscene Beats")
## Camera zoom while the ship is "small in the distance" at beat 0.
@export var start_zoom: Vector2 = Vector2(0.6, 0.6)
## Camera zoom that matches gameplay (player_ship's Camera2D uses Vector2(2,2)).
@export var end_zoom: Vector2 = Vector2(2.0, 2.0)
## Ship's world position at beat 0 (off-screen bottom-left).
@export var ship_start_pos: Vector2 = Vector2(-500.0, 400.0)
## Ship's world position at the end of beat 1 (mid-screen).
@export var ship_mid_pos: Vector2 = Vector2(0.0, 0.0)
## Ship's heading in degrees. +45° = pointing toward the top-right (UP rotated +45° CW).
@export var ship_heading_deg: float = 45.0
## Distance the ship drifts forward during beat 4.
@export var final_drift_distance: float = 50.0

@export_category("Cutscene Timing")
@export var beat1_duration: float = 4.0          ## fly-in + zoom-in
@export var pause_duration: float = 1.0          ## narrative pause
@export var camera_rotation_duration: float = 1.5
@export var final_drift_duration: float = 1.5

func _run_cutscene() -> void:
	# ── Beat 0: setup (instant) ─────────────────────────────────────────
	camera.zoom = start_zoom
	camera.position = (ship_start_pos + ship_mid_pos) * 0.5
	camera.rotation = deg_to_rad(45.0)
	ship.position = ship_start_pos
	ship.rotation = deg_to_rad(ship_heading_deg)
	# Ship starts as a tiny invisible point — only the comet trail is visible.
	# Scale and alpha both grow as the camera zooms close enough to reveal it.
	sprite.modulate.a = 0.0
	ship.scale = Vector2(0.1, 0.1)
	comet_trail.emitting = true
	thruster.set_state(ThrusterEffect.State.BOOST)

	# ── Beat 1: ship flies in + camera zooms + ship reveals ─────────────
	# Comet trail fades out in the first half; ship sprite fades in over
	# the full duration — at zoom distance it transitions from "shooting
	# star" to "that's a ship with engines".
	var t1 := parallel_tween()
	t1.tween_property(ship, "position", ship_mid_pos, beat1_duration)
	t1.tween_property(camera, "position", ship_mid_pos, beat1_duration)
	t1.tween_property(camera, "zoom", end_zoom, beat1_duration)
	t1.tween_property(sprite, "modulate:a", 1.0, beat1_duration)
	t1.tween_property(ship, "scale", Vector2(1.0, 1.0), beat1_duration)
	t1.tween_property(comet_trail, "modulate:a", 0.0, beat1_duration * 0.55)
	await t1.finished
	comet_trail.emitting = false
	if is_skipped(): return

	# ── Beat 2: mission briefing exchange ───────────────────────────────
	await DialogPlayer.play(preload("res://dialog/scripts/intro_briefing.tres"))
	if is_skipped(): return

	# ── Beat 3: camera and ship both rotate back to 0 (standard top-down) ──
	# Rotating ship.rotation → 0 while rotating camera.rotation → 0 means
	# the ship visually "straightens up" and will fly toward the top of the
	# screen in Beat 4. Camera ends at 0 = normal top-down orientation.
	thruster.set_state(ThrusterEffect.State.POWER)
	var t3 := parallel_tween()
	t3.tween_property(camera, "rotation", 0.0, camera_rotation_duration)
	t3.tween_property(ship, "rotation", 0.0, camera_rotation_duration)
	await t3.finished
	if is_skipped(): return

	# ── Beat 4: ship decelerates into the next mission ──────────────────
	thruster.set_state(ThrusterEffect.State.THRUST)
	var forward := Vector2.UP.rotated(ship.rotation)
	var ship_end := ship.position + forward * final_drift_distance
	var t4 := parallel_tween()
	t4.set_ease(Tween.EASE_IN)    ## starts from near-zero — gentle slow drift away
	t4.tween_property(ship, "position", ship_end, final_drift_duration)
	t4.tween_property(camera, "position", ship_end, final_drift_duration)
	await t4.finished
	if is_skipped(): return

	_on_finish()
