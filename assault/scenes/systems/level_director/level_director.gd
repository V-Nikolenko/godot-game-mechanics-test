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


## Awaits either [container]'s next child_exiting_tree signal OR a fallback
## timeout of [poll_seconds] — whichever happens first.
##
## The deadline is a Time.get_ticks_msec() comparison rather than a SceneTreeTimer, deliberately.
## The loop already resumes once per frame, so a timer bought no precision — but it outlived an
## early return by the whole remaining [poll_seconds], and anything that tore the tree down inside
## that window (a test returning, the level ending) stranded it. Godot reports that at process exit
## as `ObjectDB instances leaked` / `resources still in use`, neither of which matches the gate's
## fatal-error regex, so it leaked in silence. Wall-clock also agrees with `_wait_enemies_cleared()`
## below, whose own deadline has always been ticks-based — the two no longer disagree while
## `Engine.time_scale` is off 1.0 (trajectory_calc_module.gd:34).
func _wait_for_child_exit_or_timeout(container: Node, poll_seconds: float) -> void:
	var exited := [false]
	var on_exit := func(_n: Node) -> void:
		exited[0] = true
	container.child_exiting_tree.connect(on_exit, CONNECT_ONE_SHOT)

	var deadline_ms: int = Time.get_ticks_msec() + int(poll_seconds * 1000.0)
	while not exited[0] and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return

	if is_instance_valid(container) and container.child_exiting_tree.is_connected(on_exit):
		container.child_exiting_tree.disconnect(on_exit)


## Frame-polled sleep, for the same reason as the helper above: a SceneTreeTimer is stranded by
## anything that ends the tree inside the wait, and this one is only a settle before _advance().
func _wait_seconds(seconds: float) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return


func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var start_ms: int = Time.get_ticks_msec()

	## Connected as a zero-arg one-shot (see _advance), so the section has to be looked up rather
	## than passed in. The bounds guard covers a section list emptied mid-wait.
	var timeout: float = 10.0
	if _current_index >= 0 and _current_index < _sections.size():
		timeout = _sections[_current_index].enemies_cleared_timeout
	var deadline_ms: int = start_ms + int(timeout * 1000.0)

	while container.get_child_count() > 0:
		if Time.get_ticks_msec() >= deadline_ms:
			push_warning("[LevelDirector] enemy cleanup timed out with %d remaining" % container.get_child_count())
			## Free whatever is left rather than carrying it into the next section. A boss has no
			## EnemyPathMover, so nothing else would ever remove it — it would hang on screen for
			## the rest of the level and, since this method polls the same container, block the
			## next ENEMIES_CLEARED section forever.
			##
			## The container is not enemies-only: bullet_pool.gd:45-47 reparents in-flight bullets
			## to get_parent().get_parent(), which for an enemy ship is this container. Freeing
			## them here is safe — bullet_pool.gd:98-100 already frees in-flight bullets when the
			## owning ship exits, and _recycle guards against re-entry.
			##
			## Each freed child emits tree_exited without `died`, so ScoreTracker takes its escape
			## path (score_tracker.gd:197-215): the wave tally is marked escaped and the combo is
			## multiplied by escape_combo_multiplier (0.75). That cost is intended — timing out is
			## a failure to finish the fight.
			for child in container.get_children():
				child.queue_free()
			break
		await _wait_for_child_exit_or_timeout(container, 1.0)
		if not is_instance_valid(self):
			return

	var elapsed_ms: int = Time.get_ticks_msec() - start_ms
	print("[LevelDirector] Enemies cleared (%.2f s) — %d remaining" % [
		elapsed_ms / 1000.0, container.get_child_count()
	])
	await _wait_seconds(0.2)
	if not is_instance_valid(self):
		return
	_advance()
