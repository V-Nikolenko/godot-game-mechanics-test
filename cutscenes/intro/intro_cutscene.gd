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
@onready var thruster: ThrusterEffect = $Ship/Thruster
@onready var camera: Camera2D = $Camera2D
@onready var dialog: DialogPresenter = $DialogLayer

@export_category("Cutscene Beats")
## Camera zoom while the ship is "small in the distance" at beat 0.
@export var start_zoom: Vector2 = Vector2(0.6, 0.6)
## Camera zoom that matches gameplay (player_ship's Camera2D uses Vector2(2,2)).
@export var end_zoom: Vector2 = Vector2(2.0, 2.0)
## Ship's world position at beat 0 (off-screen bottom-left).
@export var ship_start_pos: Vector2 = Vector2(-500.0, 400.0)
## Ship's world position at the end of beat 1 (mid-screen).
@export var ship_mid_pos: Vector2 = Vector2(0.0, 0.0)
## Ship's heading. -45° = pointing toward the top-right (UP rotated -45°).
@export var ship_heading_deg: float = -45.0
## Distance the ship drifts forward during beat 4.
@export var final_drift_distance: float = 350.0

@export_category("Cutscene Timing")
@export var beat1_duration: float = 4.0          ## fly-in + zoom-in
@export var pause_duration: float = 1.0          ## narrative pause
@export var camera_rotation_duration: float = 1.5
@export var final_drift_duration: float = 1.5

func _run_cutscene() -> void:
	# ── Beat 0: setup (instant) ─────────────────────────────────────────
	camera.zoom = start_zoom
	camera.position = (ship_start_pos + ship_mid_pos) * 0.5
	camera.rotation = 0.0
	ship.position = ship_start_pos
	ship.rotation = deg_to_rad(ship_heading_deg)
	thruster.set_state(ThrusterEffect.State.THRUST)

	# ── Beat 1: ship flies in + camera zooms to gameplay zoom ───────────
	var t1 := parallel_tween()
	t1.tween_property(ship, "position", ship_mid_pos, beat1_duration)
	t1.tween_property(camera, "position", ship_mid_pos, beat1_duration)
	t1.tween_property(camera, "zoom", end_zoom, beat1_duration)
	await t1.finished
	if is_skipped(): return

	# ── Beat 2: narrative pause + future dialog hook ────────────────────
	# Replace this stub call with actual lines once the dialog system
	# has portraits/voice. The await contract is already in place.
	# await dialog.present("Captain", "We've reached the target sector.", pause_duration)
	await wait_secs(pause_duration)
	if is_skipped(): return

	# ── Beat 3: camera rotates so ship heading aligns with screen-up ────
	# Camera rotation == ship rotation makes the ship's local +Up appear
	# as screen +Up — i.e. the gameplay top-down orientation.
	thruster.set_state(ThrusterEffect.State.BOOST)
	await tween_property(camera, "rotation", ship.rotation,
			camera_rotation_duration, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	if is_skipped(): return

	# ── Beat 4: ship drifts forward into the next mission ───────────────
	var forward := Vector2.UP.rotated(ship.rotation)
	var ship_end := ship.position + forward * final_drift_distance
	var t4 := parallel_tween()
	t4.tween_property(ship, "position", ship_end, final_drift_duration)
	t4.tween_property(camera, "position", ship_end, final_drift_duration)
	await t4.finished

	_on_finish()
