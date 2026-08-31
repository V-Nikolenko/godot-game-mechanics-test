## RaceDirector — one per race level. Owns the participant list, standings (sorted by track_y,
## cached once per frame), the finish line, and the fail-on-player-death signal. No projection
## (that's RaceWorld). Add to group "race_director" so participants self-register.
class_name RaceDirector
extends Node

signal standings_changed(order: Array)   ## Array[RaceParticipant], leader first
signal race_finished(results: Array)     ## Array[RaceParticipant], finish order
signal race_failed                       ## player destroyed

@export var track_length: float = 18000.0

var _participants: Array[RaceParticipant] = []
var _player: RaceParticipant = null
var _results: Array[RaceParticipant] = []
var _standings: Array[RaceParticipant] = []
var _race_over: bool = false

func register(p: RaceParticipant) -> void:
	if p not in _participants:
		_participants.append(p)
	if p.is_player:
		_player = p

func unregister(p: RaceParticipant) -> void:
	_participants.erase(p)
	_standings.erase(p)

func get_player() -> RaceParticipant:
	return _player

## Cached, leader-first. Recomputed once per frame in _physics_process.
func get_standings() -> Array[RaceParticipant]:
	return _standings

func place_of(p: RaceParticipant) -> int:
	var i := _standings.find(p)
	return i + 1 if i >= 0 else _participants.size()

func is_in_front(p: RaceParticipant) -> bool:
	return not _standings.is_empty() and _standings[0] == p

func leader() -> RaceParticipant:
	return _standings[0] if not _standings.is_empty() else null

func gap_to_leader(p: RaceParticipant) -> float:
	var l := leader()
	return (l.track_y - p.track_y) if l else 0.0

func get_ahead(p: RaceParticipant) -> RaceParticipant:
	var i := _standings.find(p)
	return _standings[i - 1] if i > 0 else null

func get_behind(p: RaceParticipant) -> RaceParticipant:
	var i := _standings.find(p)
	return _standings[i + 1] if i >= 0 and i < _standings.size() - 1 else null

## Connect the player's Health so death fails the race (called by RaceLevelConfig).
func bind_player_health(health: Health) -> void:
	if health and not health.amount_changed.is_connected(_on_player_health_changed):
		health.amount_changed.connect(_on_player_health_changed)

func notify_finished(p: RaceParticipant) -> void:
	if p not in _results:
		_results.append(p)
	if p == _player and not _race_over:
		_race_over = true
		race_finished.emit(_results.duplicate())

## Force the race to fail immediately (e.g. a one-shot hazard killed the player).
## Bypasses the health path so it doesn't trigger the assault game-over overlay —
## just emits race_failed, which RaceLevelConfig reloads the scene on.
func fail_race() -> void:
	if not _race_over:
		_race_over = true
		race_failed.emit()

func _physics_process(_delta: float) -> void:
	if _race_over:
		return
	var sorted: Array[RaceParticipant] = []
	sorted.assign(_participants)
	sorted.sort_custom(func(a, b): return a.track_y > b.track_y)
	if sorted != _standings:
		_standings = sorted
		standings_changed.emit(_standings)
	# Player-finish: the player's track_y is set externally (PlayerRaceController), so unlike AI
	# it is not checked in RaceParticipant — the director detects the player crossing the line.
	if _player and not _player.finished and _player.track_y >= track_length:
		_player.finished = true
		notify_finished(_player)

func _on_player_health_changed(current: int) -> void:
	if current <= 0 and not _race_over:
		_race_over = true
		race_failed.emit()
