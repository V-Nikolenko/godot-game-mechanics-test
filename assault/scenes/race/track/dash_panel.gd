## DashPanel — a speed pad placed as a child of the Track node. Because Track scrolls, this
## node's global_position is always correct without any per-object projection.
##
## Detection is internal (geometric poll); effects are external — the level connects to the
## signals below and decides what crossing a pad or clipping a wall means for each ship.
##
## Place at Track local Y = -N to be encountered at race distance N. X = lane position.
class_name DashPanel
extends Node2D

## Emitted once per racer per retrigger_cooldown window when they cross the boost zone.
signal body_boosted(ship: Node2D, participant: RaceParticipant)
## Emitted when a racer clips a side wall. push_dir: +1 = push right, -1 = push left.
## damage and pushback are this panel's own export values, forwarded for the handler.
signal body_wall_hit(ship: Node2D, participant: RaceParticipant, push_dir: float, damage: int, pushback: float)

## Must be > retrigger_cooldown so every ship's personal cooldown expires before the pad
## reactivates — prevents a window where one ship is blocked while others are not.
@export var disabled_duration: float = 2.0
@export var retrigger_cooldown: float = 1.2
@export var wall_damage: int = 15
@export var wall_pushback: float = 60.0
@export var wall_hit_cooldown: float = 0.6
## How far below the bottom of the screen before this node culls itself.
@export var cull_margin: float = 160.0

var _cooldowns: Dictionary = {}       ## RaceParticipant -> boost retrigger cooldown
var _wall_cooldowns: Dictionary = {}  ## RaceParticipant -> wall-hit cooldown
var _disabled: float = 0.0

@onready var _arrows: AnimatedSprite2D = get_node_or_null("PadArrows") as AnimatedSprite2D
@onready var _boost_col: CollisionShape2D = get_node_or_null("PadBoostCollision") as CollisionShape2D
@onready var _frame_l: CollisionShape2D = get_node_or_null("WallL/FrameCollisionL") as CollisionShape2D
@onready var _frame_r: CollisionShape2D = get_node_or_null("WallR/FrameCollisionR") as CollisionShape2D

func _ready() -> void:
	add_to_group("dash_panels")
	if _arrows:
		_arrows.play(&"idle_active")

func _physics_process(delta: float) -> void:
	## Panels that have not yet scrolled into view can skip processing — no ship
	## is near them. Panels that have scrolled PAST the viewport are NOT culled:
	## trailing racers still need to cross them, so they stay alive for the whole race.
	if global_position.y < -cull_margin:
		return

	_tick_cooldowns(_cooldowns, delta)
	_tick_cooldowns(_wall_cooldowns, delta)

	if _disabled > 0.0:
		_disabled -= delta
		if _disabled <= 0.0 and _arrows:
			_arrows.play(&"idle_active")

	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ship := n as Node2D
			if ship == null:
				continue
			var part := ship.get_node_or_null("RaceParticipant") as RaceParticipant
			if part == null:
				continue
			var pos := ship.global_position

			# Wall hits are always live — wall_hit_cooldown prevents per-frame repeat damage.
			# Ships inside the boost zone are safe: PadBoostCollision grants immunity to walls.
			# WALL_MARGIN: the player is a CharacterBody2D that PHYSICALLY collides with the
			# walls (StaticBody2D), so move_and_slide stops it with its CENTRE one body-radius
			# outside the 31 px wall rect — on BOTH faces (the inner face when entering from the
			# track, and the outer face when brushing the panel's side). The player's real
			# collision radius is 13.77 px (CircleShape2D 5.099 × the Collision node's 2.7 scale),
			# so the margin must exceed that for a touching ship to register on either face.
			# 20 covers the radius plus the physics separation skin with a little headroom.
			const WALL_MARGIN := 20.0
			if not _wall_cooldowns.has(part) and not _in_shape(pos, _boost_col):
				if _in_shape(pos, _frame_l, WALL_MARGIN):
					_wall_cooldowns[part] = wall_hit_cooldown
					# Push AWAY from the wall based on which side the ship is on, so a
					# side/outer-face brush shoves outward instead of into the panel.
					# Default to track-centre (+1) when dead-centre on the wall.
					var dir_l := signf(pos.x - _frame_l.global_position.x)
					body_wall_hit.emit(ship, part, dir_l if dir_l != 0.0 else 1.0,
						wall_damage, wall_pushback)
					continue
				elif _in_shape(pos, _frame_r, WALL_MARGIN):
					_wall_cooldowns[part] = wall_hit_cooldown
					var dir_r := signf(pos.x - _frame_r.global_position.x)
					body_wall_hit.emit(ship, part, dir_r if dir_r != 0.0 else -1.0,
						wall_damage, wall_pushback)
					continue

			# Boost zone: skip every ship while the pad is recharging.
			# Explicit continue (rather than a compound condition) makes it impossible
			# for any ship to slip through during the disabled window.
			if _disabled > 0.0:
				continue
			if not _cooldowns.has(part) and _in_shape(pos, _boost_col):
				_cooldowns[part] = retrigger_cooldown
				_disabled = disabled_duration
				if _arrows:
					_arrows.play(&"use")
				body_boosted.emit(ship, part)

func _tick_cooldowns(dict: Dictionary, delta: float) -> void:
	for p in dict.keys():
		dict[p] -= delta
	for p in dict.keys().filter(func(k): return dict[k] <= 0.0):
		dict.erase(p)

## Geometric overlap test against a CollisionShape2D anywhere in the hierarchy.
## Uses col.global_position (correct regardless of parent depth) and accounts for
## the node's own scale — needed because PadBoostCollision uses scale = (2.88, 1).
## x_margin widens the X test without affecting the Y test — use it for wall checks so
## that CharacterBody2D ships whose physics prevents centre-penetration are still caught.
func _in_shape(world_pos: Vector2, col: CollisionShape2D, x_margin: float = 0.0) -> bool:
	if col == null:
		return false
	var rect := col.shape as RectangleShape2D
	if rect == null:
		return false
	var xform := col.get_global_transform()
	var center := xform.get_origin()
	var half := rect.size * 0.5 * xform.get_scale()
	return absf(world_pos.x - center.x) < half.x + x_margin and absf(world_pos.y - center.y) < half.y
