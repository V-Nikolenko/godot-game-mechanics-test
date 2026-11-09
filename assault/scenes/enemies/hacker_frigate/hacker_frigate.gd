## The Hacker Frigate (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.10, §2.11; Phase 9 t8 / t9, task plans
## docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md and docs/plans/cmw5k4yk700amqs2xuk3t1oge/3-plan.md): an electronic-warfare frigate that
## attacks the player's tools, not the hull (IDEAS §6.4). It hangs back at medium-long range on a lopsided arc, slides out of the player's
## nose and off their flight line, breaks off hard when rushed and stays on screen in Assault. Its weapon is the Hijack Pulse: a charge
## (TELEGRAPH) any damage cancels, then a window (PULSE) in which it fires `HijackPulse` control darts from its hull centre at the player's
## homing rockets, which turn them back on the player. Behaviour: `ENEMY.md` beside this file.
##
## A `HackerFrigateBrain` decides and an `EnemyMover` moves it, through `BaseEnemy`'s shared tick, so this script defines no
## `_physics_process` and writes no motion. One `CircleShape2D` r 40 is shared by the body, the `HurtBox` and the `ContactHitBox` (COLLISION,
## 15). `Hull` is a `Sprite2D` (`hacker_frigate.png`, t12; the hit flash animates its `self_modulate`); `Dish` is the antenna part
## that unfolds in TELEGRAPH, with the `StateLight` on it (IDEAS §21: a state shows on a part, never a recoloured hull). The charge ring and
## the ripples are code-drawn here, above the hull (`Hull` is `show_behind_parent`) and under the dish. `DartPool` is the darts' `BulletPool`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene), folds the dish, hands the brain the `Health`
## to watch (damage cancels a TELEGRAPH) and joins group `enemies`.
##
## Spawn with b.hacker_frigate().at(x, y). Never in an ENEMIES_CLEARED section (test_engagement_deadline.gd).
class_name HackerFrigate
extends BaseEnemy

## The dish's scale when folded (TELEGRAPH opens it to 1).
const DISH_FOLDED_SCALE := 0.6
## TELEGRAPH's ring of dashes (yellow = charging), closing from `CHARGE_RING_FROM` to `CHARGE_RING_TO` px.
const CHARGE_DASHES := 6
const CHARGE_RING_FROM := 60.0
const CHARGE_RING_TO := 40.0
const CHARGE_COLOR := Color(1.0, 0.85, 0.2, 0.9)
## PULSE's ripples (white = pulsing): one every `RIPPLE_PERIOD` s from the dish, growing `RIPPLE_FROM` -> `RIPPLE_TO` px and fading.
const RIPPLE_PERIOD := 0.4
const RIPPLE_FROM := 12.0
const RIPPLE_TO := 92.0
const RIPPLE_COLOR := Color(1.0, 0.95, 0.85)

@export var config: HackerFrigateConfig = load("res://assault/scenes/enemies/hacker_frigate/hacker_frigate_config.tres")

@onready var _hacker_brain: HackerFrigateBrain = $Brain
@onready var _hacker_mover: EnemyMover = $EnemyMover
@onready var _dish: Node2D = $Dish

var _dish_open: float = 0.0
var _tell_kind: StringName = &""
var _charge_f: float = 0.0
var _pulse_t: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	set_dish_open(0.0)
	_hacker_brain.watch_health(health)


func _apply_config(cfg: HackerFrigateConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	_hacker_mover.max_speed = cfg.max_speed
	_hacker_mover.acceleration = cfg.acceleration
	_hacker_mover.max_turn_rate = cfg.max_turn_rate
	_hacker_brain.config = cfg


func brain() -> HackerFrigateBrain:
	return _hacker_brain


## The antenna part (t9 unfolds it, t12 draws it: `Dish/Antenna`).
func dish() -> Node2D:
	return _dish


func state_light() -> StateLight:
	return get_node_or_null("Dish/StateLight") as StateLight


## The body circle's radius (the scene's shared `CircleShape2D`).
func body_radius() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle := cs.shape as CircleShape2D if cs != null else null
	return circle.radius if circle != null else 0.0


# ── The Hijack Pulse (t9) ────────────────────────────────────────────────────────────────────────

## The dart pool (`DartPool`, a `BulletPool` root child: `pool_size` 4, no `persist_after_owner_death`, so the darts go with the ship).
func dart_pool() -> BulletPool:
	return get_node_or_null("DartPool") as BulletPool


## One dart from the hull centre at [param rocket]; null when the pool is exhausted.
func fire_dart(rocket: Node2D) -> HijackPulse:
	var pool := dart_pool()
	if pool == null:
		return null
	var dart := pool.acquire(global_position) as HijackPulse
	if dart == null:
		return null
	dart.launch(rocket, self)
	return dart


## The Disruptor hook (§2.11): the duck-typed `apply_ability_lock(seconds, source)` on `players[0]` of group `player` (the
## `TargetInfo.player()` rule). A player without it (the harness stub) is left alone. Brains never read the group, so this lives here.
func lock_player_abilities(seconds: float) -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var p: Node = players[0]
	if is_instance_valid(p) and p.has_method(&"apply_ability_lock"):
		p.call(&"apply_ability_lock", seconds, self)


## TELEGRAPH unfolds the dish (`f` 0 folded .. 1 open). IDEAS §21: the state shows on a part, never on the hull.
func set_dish_open(f: float) -> void:
	_dish_open = clampf(f, 0.0, 1.0)
	if _dish != null:
		_dish.scale = Vector2.ONE * lerpf(DISH_FOLDED_SCALE, 1.0, _dish_open)


## TELEGRAPH's charge ring: `CHARGE_DASHES` yellow dashes closing from `CHARGE_RING_FROM` to `CHARGE_RING_TO` as `f` goes 0 -> 1.
func show_charge(f: float) -> void:
	_tell_kind = &"charge"
	_charge_f = clampf(f, 0.0, 1.0)
	queue_redraw()


## PULSE's ripples, [param t] seconds into the window: a new ring from the dish every `RIPPLE_PERIOD`, growing and fading over it.
func show_pulse(t: float) -> void:
	_tell_kind = &"pulse"
	_pulse_t = maxf(t, 0.0)
	queue_redraw()


func clear_tell() -> void:
	_tell_kind = &""
	_charge_f = 0.0
	_pulse_t = 0.0
	queue_redraw()


func dish_open() -> float:
	return _dish_open


## `&""` at rest, `&"charge"` in TELEGRAPH, `&"pulse"` in PULSE.
func tell_kind() -> StringName:
	return _tell_kind


## The charge ring's radius (px), or 0 when it is not shown.
func charge_ring_radius() -> float:
	return lerpf(CHARGE_RING_FROM, CHARGE_RING_TO, _charge_f) if _tell_kind == &"charge" else 0.0


## Ripples emitted this PULSE: `floor(t / RIPPLE_PERIOD + 1e-6) + 1`; 0 outside PULSE.
func ripple_count() -> int:
	return int(floor(_pulse_t / RIPPLE_PERIOD + 1e-6)) + 1 if _tell_kind == &"pulse" else 0


func _draw() -> void:
	match _tell_kind:
		&"charge":
			var r := charge_ring_radius()
			var spin := _charge_f * TAU / CHARGE_DASHES
			var half := PI / CHARGE_DASHES * 0.5
			for i in CHARGE_DASHES:
				var a := spin + i * TAU / CHARGE_DASHES
				draw_arc(Vector2.ZERO, r, a - half, a + half, 4, CHARGE_COLOR, 2.0)
		&"pulse":
			var age := fmod(_pulse_t, RIPPLE_PERIOD) / RIPPLE_PERIOD
			var centre := _dish.position if _dish != null else Vector2.ZERO
			draw_arc(centre, lerpf(RIPPLE_FROM, RIPPLE_TO, age), 0.0, TAU, 32, Color(RIPPLE_COLOR, 1.0 - age), 1.5)
