## A Minefield: a visible placed structure of mines with a warning beacon (plan §2.10,
## docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md), never an invisible collider. Works in both modes.
##
## Patterns: AUTHORED keeps the `EnemyMine` children placed in the editor under `Mines`; RING, GRID and SCATTER instance
## mines from `EnemyMineScenes` in `_ready()` (load time, never inside a physics flush). The variant of each generated
## mine is drawn from the flat `w_*` weights with the field's own seeded rng, so a seed builds the same field twice.
##
## Every mine the field holds is `placed = true` (self-owned, registers on its own launch) with the field's `hostility`
## (ALL by default: set off by, and hurting, enemies as well as the player). The field NEVER sets `placed_life`, so every
## mine keeps 0 and never fizzles, whatever `mine_life` its scene authors (`mine.tscn` authors 8.0 for the Bomber).
##
## AUTHORED children are readied BEFORE the field, so this `_ready()` sets `placed` / `hostility` on mines whose own
## `_ready()` already ran: they rely on the mine's deferred `_start_if_placed()` and its launch-time mask. Authored
## drifting mines keep the direction and leash they were authored with and only get `drift_leash` when they have none,
## and a random direction when they have none (a standalone drifting mine with a zero direction is still).
##
## Assault (an `assault_arena` provider exists): the field moves itself down at `assault_drift_speed`, the wreck
## precedent for scrolling, and frees itself once every mine is below `EnemyWorld.projectile_world_rect()`, or after
## `ASSAULT_MAX_LIFE` seconds. Open Space: the field is still (its drifting mines move inside their leash).
## One owner: the field frees itself `DARK_TIME` after its last mine is gone; the mines free themselves.
class_name Minefield
extends Node2D

enum Pattern { AUTHORED, RING, GRID, SCATTER }

## Seconds the beacon stays dark before the emptied field frees itself.
const DARK_TIME := 1.0
## An Assault field frees itself after this long whatever it is doing.
const ASSAULT_MAX_LIFE := 40.0

@export var pattern: Pattern = Pattern.RING
## RING / SCATTER: how many mines; GRID: how many cells are filled, row by row. Ignored by AUTHORED.
@export var count: int = 9
## RING: the circle's radius; SCATTER: the disc the points fall in.
@export var radius: float = 200.0
## GRID: distance between neighbouring mines.
@export var spacing: float = 110.0
## 0 = a fixed seed of 1, so an unseeded field is still the same every time.
@export var rng_seed: int = 0
@export_group("Variant weights")
@export var w_proximity: float = 1.0
@export var w_drifting: float = 0.0
@export var w_homing: float = 0.0
@export var w_chain: float = 0.0
@export var w_pulse: float = 0.0
@export var w_emp: float = 0.0
@export_group("Mines")
@export var hostility: EnemyMine.Hostility = EnemyMine.Hostility.ALL
## Each placed DRIFTING mine ping-pongs within this distance of its place (see `EnemyMine.drift_leash`).
@export var drift_leash: float = 120.0
@export_group("Assault")
@export var assault_drift_speed: float = 60.0

## Set by `spawn_into()`: a runtime field, as opposed to one placed in a scene.
var spawned: bool = false

var _rng := RandomNumberGenerator.new()
var _assault: bool = false
var _age: float = 0.0
var _dark_clock: float = 0.0
var _dark: bool = false
var _pending_transform: bool = false
var _at: Vector2 = Vector2.ZERO

@onready var _mines: Node2D = $Mines
@onready var _beacon: MinefieldBeacon = get_node_or_null("Beacon") as MinefieldBeacon


## Adds the field to [param container] at the next message flush, at [param at]. Safe inside a physics callback. The
## deferred call is made on the FIELD (`Wreck.spawn_into` pattern), so a freed container leaks nothing.
func spawn_into(container: Node, at: Vector2) -> void:
	_at = at
	_pending_transform = true
	spawned = true
	_attach.call_deferred(container)


## Untyped on purpose: a typed `Node` parameter makes the deferred call itself fail on a freed container.
func _attach(container) -> void:
	if is_instance_valid(container) and (container as Node).is_inside_tree():
		(container as Node).add_child(self)
	else:
		queue_free()


func _enter_tree() -> void:
	if _pending_transform:
		global_position = _at
		_pending_transform = false
	_assault = EnemyWorld.arena(get_tree()) != null


func _ready() -> void:
	_rng.seed = rng_seed if rng_seed != 0 else 1
	if pattern == Pattern.AUTHORED:
		_adopt_authored()
	else:
		_build()


## True once the last mine is gone and the beacon is dark.
func is_dark() -> bool:
	return _dark


## The live mines the field holds.
func mines() -> Array[EnemyMine]:
	var out: Array[EnemyMine] = []
	for child in _mines.get_children():
		var mine := child as EnemyMine
		if mine != null and not mine.is_queued_for_deletion():
			out.append(mine)
	return out


func _physics_process(delta: float) -> void:
	_age += delta
	if _dark:
		_dark_clock += delta
		if _dark_clock >= DARK_TIME:
			queue_free()
		return
	var live := mines()
	if live.is_empty():
		_go_dark()
		return
	if not _assault:
		return
	position.y += assault_drift_speed * delta
	for mine in live:
		mine.carry_velocity = Vector2(0.0, assault_drift_speed)
	if _age >= ASSAULT_MAX_LIFE or _all_below_world(live):
		queue_free()


func _go_dark() -> void:
	_dark = true
	_dark_clock = 0.0
	if _beacon != null:
		_beacon.lit = false


func _all_below_world(live: Array[EnemyMine]) -> bool:
	if not EnemyWorld.has_projectile_world_rect(get_tree()):
		return false
	var bottom := EnemyWorld.projectile_world_rect(get_tree()).end.y
	for mine in live:
		if mine.global_position.y <= bottom:
			return false
	return true


func _adopt_authored() -> void:
	for child in _mines.get_children():
		var mine := child as EnemyMine
		if mine == null:
			push_error("Minefield: '%s' under Mines is not an EnemyMine; ignored." % child.name)
			continue
		_claim(mine)
		if mine.variant == EnemyMine.Variant.DRIFTING:
			if mine.drift_leash <= 0.0:
				mine.drift_leash = drift_leash
			if mine.drift_direction == Vector2.ZERO:
				mine.drift_direction = _random_direction()


func _build() -> void:
	for point in _points():
		var variant := _draw_variant()
		var scene := EnemyMineScenes.scene_for(variant)
		var mine := scene.instantiate() as EnemyMine
		_claim(mine)
		if variant == EnemyMine.Variant.DRIFTING:
			mine.drift_direction = _random_direction()
			mine.drift_leash = drift_leash
		mine.position = point
		_mines.add_child(mine)


## The two settings every mine of the field gets, whether it was authored or generated.
func _claim(mine: EnemyMine) -> void:
	mine.placed = true
	mine.hostility = hostility


func _random_direction() -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU)


## Local points of the generated pattern. SCATTER draws from the field's rng, so the seed fixes them.
func _points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := maxi(count, 0)
	match pattern:
		Pattern.RING:
			for i in n:
				out.append(Vector2.from_angle(TAU * float(i) / float(n)) * radius)
		Pattern.GRID:
			var cols := maxi(ceili(sqrt(float(n))), 1)
			var rows := maxi(ceili(float(n) / float(cols)), 1)
			for i in n:
				var c := i % cols
				var r := floori(float(i) / float(cols))
				out.append(Vector2((c - (cols - 1) * 0.5) * spacing, (r - (rows - 1) * 0.5) * spacing))
		Pattern.SCATTER:
			for i in n:
				var dist := radius * sqrt(_rng.randf())
				out.append(Vector2.from_angle(_rng.randf() * TAU) * dist)
	return out


## A variant drawn from the flat weights; PROXIMITY when every weight is 0.
func _draw_variant() -> EnemyMine.Variant:
	var weights := [w_proximity, w_drifting, w_homing, w_chain, w_pulse, w_emp]
	var total := 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return EnemyMine.Variant.PROXIMITY
	var pick := _rng.randf() * total
	for i in weights.size():
		pick -= maxf(weights[i], 0.0)
		if pick < 0.0:
			return i as EnemyMine.Variant
	return EnemyMine.Variant.PROXIMITY
