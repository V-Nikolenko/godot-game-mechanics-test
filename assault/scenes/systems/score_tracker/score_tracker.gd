## ScoreTracker — owns all assault-mission scoring math.
##
## Lives in a level scene next to LevelDirector / WaveManager. Subscribes to:
##   - WaveManager.enemy_spawned     → starts tracking each enemy
##   - BaseEnemy.died / AsteroidBase.died → award kill points + grow combo
##   - Node.tree_exited              → detect off-screen escapes (vs kills)
##   - EventBus.player_health_changed → damage = combo penalty + reset survival
##   - EventBus.skill_challenge_completed → award skill bonus
##
## Publishes results via EventBus signals (score_changed, combo_changed,
## score_event). UI nodes (HUDScoreWidget, ScorePopup) subscribe there.
##
## See docs/superpowers/specs/2026-05-20-scoring-system-design.md
class_name ScoreTracker
extends Node

## Bookkeeping for one wave's clear bonus.
class WaveTally:
	var expected: int = 0
	var killed: int = 0
	var base_value_sum: int = 0
	var escaped: bool = false
	var resolved: bool = false  # bonus paid or invalidated

@export var wave_manager: WaveManager
@export var score_config: ScoreConfig = preload("res://global/resources/score_config_default.tres")

# ── Runtime state ─────────────────────────────────────────────────────────────

var _total_score: int = 0
var _combo: float = 1.0
var _combo_decay_remaining: float = 0.0
var _survival_remaining: float = 15.0
var _last_known_health: int = -1
var _wave_state: Dictionary = {}  # int (wave_index) → WaveTally
var _running: bool = false

# Categorised totals for the debrief breakdown panel.
var _breakdown: Dictionary = {
	"kills": 0,
	"wave_clear": 0,
	"survival": 0,
	"skill": 0,
	"bonus_target": 0,
}


# ── Public API ────────────────────────────────────────────────────────────────

func _ready() -> void:
	if score_config == null:
		score_config = preload("res://global/resources/score_config_default.tres")
	_survival_remaining = score_config.survival_interval

func start_tracking() -> void:
	_running = true
	set_process(true)
	if wave_manager:
		if not wave_manager.enemy_spawned.is_connected(_on_enemy_spawned):
			wave_manager.enemy_spawned.connect(_on_enemy_spawned)
		## Clear stale wave tallies every time a new section starts so that wave
		## indices 0, 1, 2 … from section N don't collide with those from section
		## N-1.  Without this, a wave-0 tally that was resolved in section 1 would
		## block wave-clear bonuses for section 2's wave 0, and an unresolved
		## section-1 tally could cause an unexpected wave-clear bonus mid-section-2.
		if not wave_manager.section_loaded.is_connected(_on_section_loaded):
			wave_manager.section_loaded.connect(_on_section_loaded)
	if not EventBus.player_health_changed.is_connected(_on_player_health_changed):
		EventBus.player_health_changed.connect(_on_player_health_changed)
	if not EventBus.skill_challenge_completed.is_connected(_on_skill_completed):
		EventBus.skill_challenge_completed.connect(_on_skill_completed)
	# Orphans (asteroid splits, ad-hoc spawns) route through the same handler
	# but always carry wave_index = -1, so they never count toward wave clears.
	if not EventBus.enemy_spawned_orphan.is_connected(_on_orphan_spawned):
		EventBus.enemy_spawned_orphan.connect(_on_orphan_spawned)
	EventBus.score_changed.emit(_total_score)
	EventBus.combo_changed.emit(_combo, 0.0)


## Called when WaveManager starts a new section.  Clears wave-tally state so
## that wave indices from the new section are tracked independently.
## Enemies from the old section that are still alive keep their signal
## connections — their kills still award individual score, they just no longer
## count toward any wave-clear bonus (the tally they belonged to is gone).
func _on_section_loaded() -> void:
	_wave_state.clear()


func _on_orphan_spawned(enemy: Node) -> void:
	_on_enemy_spawned(enemy, -1)

func stop_tracking() -> void:
	_running = false
	set_process(false)
	# Resolve any waves that still have living enemies as escaped (no bonus).
	for wave_index: int in _wave_state.keys():
		var tally: WaveTally = _wave_state[wave_index]
		if not tally.resolved:
			tally.resolved = true
			tally.escaped = true

func get_total_score() -> int:
	return _total_score

func get_breakdown() -> Dictionary:
	# Return a duplicate so callers can't mutate internal state.
	return _breakdown.duplicate()


# ── Frame loop: combo decay + survival ────────────────────────────────────────

func _process(delta: float) -> void:
	if not _running:
		return

	if _combo > 1.0:
		_combo_decay_remaining -= delta
		if _combo_decay_remaining <= 0.0:
			_combo = 1.0
			_combo_decay_remaining = 0.0
			EventBus.combo_changed.emit(_combo, 0.0)
		else:
			# Live tick so HUD bar can shrink smoothly.
			EventBus.combo_changed.emit(_combo, _combo_decay_remaining)

	_survival_remaining -= delta
	if _survival_remaining <= 0.0:
		_award_survival()


# ── Wave / enemy plumbing ─────────────────────────────────────────────────────

func _on_enemy_spawned(enemy: Node, wave_index: int) -> void:
	var counts_in_wave: bool = bool(enemy.get("counts_toward_wave_clear")) \
			if enemy.get("counts_toward_wave_clear") != null else true

	var base_value: int = _read_score_value(enemy)

	if counts_in_wave:
		var tally: WaveTally = _wave_state.get(wave_index)
		if tally == null:
			tally = WaveTally.new()
			_wave_state[wave_index] = tally
		tally.expected += 1
		tally.base_value_sum += base_value

	# Connect "died" (kill path) and "tree_exited" (escape path).
	# BaseEnemy.died has no payload; AsteroidBase.died(world_position: Vector2)
	# has one. We bind the captured args to a common handler and use unbind(1)
	# on the asteroid path so the signal's Vector2 is dropped before forwarding.
	var bound: Callable = _on_enemy_died.bind(enemy, wave_index, base_value, counts_in_wave)
	if enemy is AsteroidBase:
		enemy.died.connect(bound.unbind(1), CONNECT_ONE_SHOT)
	elif enemy is BaseEnemy:
		enemy.died.connect(bound, CONNECT_ONE_SHOT)
	else:
		# Unknown enemy type with a "died" signal — try the generic path.
		if enemy.has_signal("died"):
			enemy.connect("died", bound, CONNECT_ONE_SHOT)

	enemy.tree_exited.connect(
		_on_enemy_freed.bind(enemy, wave_index, counts_in_wave),
		CONNECT_ONE_SHOT,
	)


func _on_enemy_died(enemy: Node, wave_index: int, base_value: int, counts_in_wave: bool) -> void:
	if not _running:
		return
	# Capture position BEFORE the enemy is freed (queue_free happens this frame).
	var kill_pos: Vector2 = enemy.global_position

	var points: int = int(floor(base_value * _combo))
	_total_score += points

	# Reason key feeds both the breakdown panel and the popup label.
	var category: String = "bonus_target" if not counts_in_wave else "kills"
	_breakdown[category] = _breakdown.get(category, 0) + points

	# Grow combo + reset decay timer.
	_combo = minf(_combo + score_config.combo_step, score_config.combo_cap)
	_combo_decay_remaining = score_config.combo_decay_seconds

	EventBus.score_changed.emit(_total_score)
	EventBus.combo_changed.emit(_combo, _combo_decay_remaining)
	EventBus.score_event.emit(kill_pos, points, "kill" if counts_in_wave else "bonus_target")

	# Skill bonus also grows combo, but bonus drones don't count toward
	# wave clear so we only update tallies for normal enemies here.
	if counts_in_wave:
		var tally: WaveTally = _wave_state.get(wave_index)
		if tally:
			tally.killed += 1
			_maybe_award_wave_clear(wave_index, tally, kill_pos)


func _on_enemy_freed(enemy: Node, wave_index: int, counts_in_wave: bool) -> void:
	# If the enemy was killed, the died handler already ran and updated state.
	# Guard with is_instance_valid: in rare edge cases (e.g. immediate free before
	# the deferred add_child of a shard runs) the node may already be freed.
	if not is_instance_valid(enemy) or enemy.get("was_killed"):
		return
	if not _running:
		return
	if counts_in_wave:
		var tally: WaveTally = _wave_state.get(wave_index)
		if tally and not tally.resolved:
			tally.escaped = true
			tally.resolved = true
	# Combo penalty for letting an enemy slip past.
	_combo *= score_config.escape_combo_multiplier
	if _combo < 1.0:
		_combo = 1.0
		_combo_decay_remaining = 0.0
	EventBus.combo_changed.emit(_combo, _combo_decay_remaining)


func _maybe_award_wave_clear(wave_index: int, tally: WaveTally, kill_pos: Vector2) -> void:
	if tally.resolved:
		return
	if tally.escaped:
		return
	if tally.killed < tally.expected:
		return
	tally.resolved = true
	var bonus_f: float = tally.base_value_sum * (
		score_config.wave_clear_base_multiplier
		+ score_config.wave_clear_per_enemy_bonus * tally.expected
	)
	var bonus: int = int(bonus_f)
	_total_score += bonus
	_breakdown["wave_clear"] += bonus
	EventBus.score_changed.emit(_total_score)
	EventBus.score_event.emit(kill_pos, bonus, "wave_clear")
	print("[ScoreTracker] Wave %d cleared — bonus +%d (combo x%.1f)" % [wave_index, bonus, _combo])


# ── Player damage + survival ──────────────────────────────────────────────────

func _on_player_health_changed(current: int, _maximum: int) -> void:
	# Filter to actual damage events: first call is just the initial value.
	if _last_known_health < 0:
		_last_known_health = current
		return
	if current < _last_known_health:
		_combo *= score_config.damage_combo_multiplier
		if _combo < 1.0:
			_combo = 1.0
			_combo_decay_remaining = 0.0
		EventBus.combo_changed.emit(_combo, _combo_decay_remaining)
		_survival_remaining = score_config.survival_interval
	_last_known_health = current


func _award_survival() -> void:
	var bonus: int = score_config.survival_bonus
	_total_score += bonus
	_breakdown["survival"] += bonus
	_survival_remaining = score_config.survival_interval

	var pos: Vector2 = Vector2.ZERO
	var player: Node = get_tree().get_first_node_in_group("players")
	if player and player is Node2D:
		pos = (player as Node2D).global_position

	EventBus.score_changed.emit(_total_score)
	EventBus.score_event.emit(pos, bonus, "survival")


# ── Skill challenges ──────────────────────────────────────────────────────────

func _on_skill_completed(clean: bool, bonus: int) -> void:
	if not _running:
		return
	_total_score += bonus
	_breakdown["skill"] += bonus

	if clean:
		# Clean clears also nudge the combo (≈3 kills worth of growth) so a
		# perfect dodge keeps you riding the multiplier into the next wave.
		_combo = minf(_combo + score_config.combo_step * 3.0, score_config.combo_cap)
		_combo_decay_remaining = score_config.combo_decay_seconds
		EventBus.combo_changed.emit(_combo, _combo_decay_remaining)

	var pos: Vector2 = Vector2.ZERO
	var player: Node = get_tree().get_first_node_in_group("players")
	if player and player is Node2D:
		pos = (player as Node2D).global_position

	EventBus.score_changed.emit(_total_score)
	EventBus.score_event.emit(pos, bonus, "skill_clean" if clean else "skill_partial")


# ── Helpers ───────────────────────────────────────────────────────────────────

## Reads score_value from either a BaseEnemy (var) or an AsteroidBase (export),
## both of which expose the same field name.
func _read_score_value(enemy: Node) -> int:
	var v: Variant = enemy.get("score_value")
	return int(v) if v != null else 0
