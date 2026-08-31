## LevelExitCutscene — plays after Assault Level 1 waves complete.
## The ship boosts upward and the screen fades to black before the next scene.
##
## Routing: set `LevelExitCutscene.go_to_hub = true` BEFORE calling
## change_scene_to_file() when the player is replaying (already beat assault).
## First-time clears leave it false (default).
class_name LevelExitCutscene
extends CutsceneBase

## Set to true by level_1_waves.gd before transitioning when the player has
## already beaten assault before (replay path → hub). Defaults to false
## (first clear → infiltration). Resets to false after the cutscene reads it.
static var go_to_hub: bool = false

const INFILTRATION_PATH := "res://infiltration/scenes/levels/TestIsometricScene.tscn"
const HUB_PATH := "res://open_space/scenes/levels/sector_hub.tscn"

@onready var ship: Node2D = $Ship
@onready var thruster: ThrusterEffect = $Ship/Thruster
@onready var camera: Camera2D = $Camera2D
@onready var overlay: ColorRect = $OverlayLayer/Overlay

@export_category("Cutscene Timing")
@export var boost_duration: float = 1.6
@export var blast_distance: float = 900.0

func _run_cutscene() -> void:
	# Lock in destination and reset static flag before any awaits
	next_scene_path = HUB_PATH if go_to_hub else INFILTRATION_PATH
	go_to_hub = false

	# Orange flame first — engines warming up
	thruster.set_state(ThrusterEffect.State.THRUST)

	# Brief beat before blast-off, then kick to full afterburner
	await wait_secs(0.4)
	if is_skipped(): return
	thruster.set_state(ThrusterEffect.State.BOOST)

	# Ship rockets upward + screen fades to black simultaneously
	var t := parallel_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(ship, "position", Vector2(0.0, -blast_distance), boost_duration)
	t.tween_property(camera, "position", Vector2(0.0, -blast_distance * 0.6), boost_duration)
	t.tween_property(overlay, "color", Color(0.0, 0.0, 0.0, 1.0), boost_duration)
	await t.finished

	_on_finish()
