## RaceHUD — live standings (leader first, player highlighted), a top-speed "class" bar, and an
## end-of-race overlay. Subscribes to the RaceDirector and the player's RaceParticipant.
class_name RaceHUD
extends CanvasLayer

@export var director: RaceDirector

@onready var _standings: Label = $Panel/Standings
@onready var _speed: ProgressBar = $Panel/SpeedBar
@onready var _overlay: Label = $Overlay

func _ready() -> void:
	_overlay.hide()
	if director:
		director.standings_changed.connect(_on_standings)
		director.race_finished.connect(_on_finished)
		director.race_failed.connect(_on_failed)

func _on_standings(order: Array) -> void:
	var lines: Array[String] = []
	var place := 1
	for p in order:
		var part := p as RaceParticipant
		var tag := "YOU" if part.is_player else "CPU"
		lines.append("%s%d. %s" % [(">" if part.is_player else " "), place, tag])
		if part.is_player and _speed:
			_speed.max_value = part.max_top_speed
			_speed.value = part.top_speed
		place += 1
	_standings.text = "\n".join(lines)

func _on_finished(results: Array) -> void:
	var place := 1
	for i in results.size():
		if (results[i] as RaceParticipant).is_player:
			place = i + 1
	_overlay.text = "FINISH!\nPlace: %d" % place
	_overlay.show()

func _on_failed() -> void:
	_overlay.text = "DESTROYED\nRestarting…"
	_overlay.show()
