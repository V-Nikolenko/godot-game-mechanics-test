# open_space/scenes/gui/mission_list_item.gd
## One row in the mission list.
## Call configure() once after instantiating, then set_hovered() when cursor moves.
class_name MissionListItem
extends Node2D

const _ICON_ASSAULT      := preload("res://assault/assets/sprites/ui/menu_mission_select_list_item_icon_assault.png")
const _ICON_INFILTRATION := preload("res://assault/assets/sprites/ui/menu_mission_select_list_item_icon_land.png")
const _ICON_UNKNOWN      := preload("res://assault/assets/sprites/ui/menu_mission_select_list_item_icon_unknown.png")

const _COLOR_NORMAL  := Color.WHITE
const _COLOR_HOVERED := Color(1.4, 1.4, 1.0)
const _COLOR_LOCKED        := Color(0.45, 0.45, 0.45)
const _COLOR_LOCKED_HOVERED := Color(0.65, 0.65, 0.65)

@onready var _bg:    Sprite2D = $Background
@onready var _icon:  Sprite2D = $Icon
@onready var _label: Label    = $NameLabel
@onready var _stars: Label    = $StarsLabel

var _locked: bool = false

func configure(mission: MissionConfigResource, locked: bool) -> void:
	_locked = locked
	var num: String = "%02d. " % mission.mission_number
	if locked:
		_icon.texture = _ICON_UNKNOWN
		_label.text   = num + "??"
	else:
		_label.text = num + mission.display_name
		if mission is InfiltrationMissionResource:
			_icon.texture = _ICON_INFILTRATION
		else:
			_icon.texture = _ICON_ASSAULT
	var stars: int = MissionState.get_stars(mission.mission_number)
	_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	modulate = _COLOR_LOCKED if locked else _COLOR_NORMAL

func set_hovered(hovered: bool) -> void:
	if _locked:
		modulate = _COLOR_LOCKED_HOVERED if hovered else _COLOR_LOCKED
		return
	modulate = _COLOR_HOVERED if hovered else _COLOR_NORMAL
