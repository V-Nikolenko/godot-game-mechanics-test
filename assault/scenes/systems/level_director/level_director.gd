## LevelDirector — sequences LevelSection resources in order.
##
## On each section start:
##   background.transition_to(section.background_phase, section.transition_in_duration)
##   wave_manager.load_section(section.waves)
##
## Add sections via add_section(), then call start().
class_name LevelDirector
extends Node

signal section_started(index: int, section_name: StringName)
signal level_complete

@export var background:   BackgroundController
@export var wave_manager: WaveManager

var _sections:        Array[LevelSection] = []
var _current_index:   int   = -1
var _section_elapsed: float = 0.0

func _process(delta: float) -> void:
	if _current_index < 0 or _current_index >= _sections.size():
		return
	_section_elapsed += delta
	var s := _sections[_current_index]
	if s.end_condition == LevelSection.EndCondition.DURATION and _section_elapsed >= s.duration:
		_advance()

## Append a section to the sequence.
func add_section(s: LevelSection) -> void:
	_sections.append(s)

## Start sequencing from section 0.
func start() -> void:
	if wave_manager:
		if wave_manager.waves_complete.is_connected(_advance):
			wave_manager.waves_complete.disconnect(_advance)
		if wave_manager.waves_complete.is_connected(_wait_enemies_cleared):
			wave_manager.waves_complete.disconnect(_wait_enemies_cleared)
	_current_index = -1
	_advance()

# ── Internal ──────────────────────────────────────────────────────────────────

func _advance() -> void:
	_current_index += 1
	if _current_index >= _sections.size():
		print("[LevelDirector] All sections complete")
		level_complete.emit()
		set_process(false)
		return

	_section_elapsed = 0.0
	var s := _sections[_current_index]
	print("[LevelDirector] Section %d: '%s'  end=%s  transition_in=%.1f s" % [
		_current_index, s.section_name,
		LevelSection.EndCondition.keys()[s.end_condition],
		s.transition_in_duration
	])
	section_started.emit(_current_index, s.section_name)

	if background:
		background.transition_to(s.background_phase, s.transition_in_duration)

	if wave_manager:
		wave_manager.load_section(s.waves)

	match s.end_condition:
		LevelSection.EndCondition.DURATION:
			set_process(true)
		LevelSection.EndCondition.WAVES_COMPLETE:
			set_process(false)
			if wave_manager:
				wave_manager.waves_complete.connect(_advance, CONNECT_ONE_SHOT)
		LevelSection.EndCondition.ENEMIES_CLEARED:
			set_process(false)
			if wave_manager:
				wave_manager.waves_complete.connect(_wait_enemies_cleared, CONNECT_ONE_SHOT)
		_:
			push_error("[LevelDirector] Unhandled EndCondition: %d" % s.end_condition)


func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var waited := 0.0
	while container.get_child_count() > 0 and waited < 10.0:
		await get_tree().create_timer(0.15).timeout
		if not is_instance_valid(self):
			return
		waited += 0.15
	print("[LevelDirector] Enemies cleared (%.1f s) — %d remaining" % [
		waited, container.get_child_count()
	])
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return
	_advance()
