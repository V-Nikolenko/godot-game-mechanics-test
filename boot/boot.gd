## Boot — single-frame router that runs on game launch.
## Decides which scene the player actually starts in.
##
## Today: intro cutscene on first launch, hub on every launch after.
## Future hooks (save slot picker, login, splash) belong here too.
extends Node

const INTRO_CUTSCENE_ID := "intro_to_assault"
const INTRO_PATH := "res://cutscenes/intro/intro_cutscene.tscn"
const HUB_PATH := "res://open_space/scenes/levels/sector_hub.tscn"

func _ready() -> void:
	var path: String
	if MissionState.has_cutscene_been_seen(INTRO_CUTSCENE_ID):
		print("[BOOT] intro already seen — going to hub")
		path = HUB_PATH
	else:
		print("[BOOT] first launch — playing intro cutscene")
		path = INTRO_PATH
	get_tree().change_scene_to_file.call_deferred(path)
