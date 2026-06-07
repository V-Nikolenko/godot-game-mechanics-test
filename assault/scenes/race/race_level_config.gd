## RaceLevelConfig — boots the race: attaches RaceParticipant + PlayerRaceController to the
## shared player, binds player death to the director, and wires all DashPanel signals so the
## level reacts to boost crossings and wall hits. Racers and track furniture are authored in
## the scene (or spawned by WaveManager); they self-register.
class_name RaceLevelConfig
extends Node

@export var director: RaceDirector
@export var player_health_node: NodePath = ^"HealthComponent"

## Racer body collision — two ships whose centres are within BUMP_RADIUS px deal
## BUMP_DAMAGE to each other and are pushed apart laterally. Per-pair cooldown
## prevents per-frame spam. All lateral; no Y push (RaceShip overwrites Y from
## track_y every frame anyway).
const BUMP_RADIUS    : float = 36.0    ## px — sum of two ship radii (18+18)
const BUMP_DAMAGE    : int   = 10
const BUMP_COOLDOWN  : float = 0.8     ## s between re-hits for the same pair
const BUMP_PUSH_AI   : float = 50.0    ## desired_x nudge for AI ships
const BUMP_PUSH_PLAYER: float = 140.0  ## velocity.x impulse for the player

## Dash-panel wall hit — lateral knockback SPEED (px/s) the player is shoved off the
## wall. Applied via PlayerBase.apply_knockback() so it decays naturally and input
## can't instantly cancel it. AI ships use the panel's own positional `pushback` instead.
const WALL_KNOCKBACK_PLAYER: float = 420.0

var _bump_cds: Dictionary = {}         ## String key -> float seconds remaining

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var participant := RaceParticipant.new()
		participant.name = "RaceParticipant"
		participant.is_player = true
		player.add_child(participant)
		var ctrl := PlayerRaceController.new()
		ctrl.name = "PlayerRaceController"
		player.add_child(ctrl)
		var health := player.get_node_or_null(player_health_node) as Health
		ctrl.setup(player, participant, health)
		if director and health:
			director.bind_player_health(health)
	if director:
		director.race_failed.connect(_on_race_failed)
		# Single source of truth: the hand-placed Finish node's Track-local Y defines the race
		# length. (An object at Track-local Y = -N is reached at distance N, so
		# track_length = -finish.position.y.)
		var finish := get_tree().get_first_node_in_group("finish_line") as Node2D
		if finish:
			director.track_length = absf(finish.position.y)

	# Connect to every dash panel already in the scene. Panels register themselves in
	# "dash_panels" during their own _ready(), which runs before this node's _ready().
	for panel: DashPanel in get_tree().get_nodes_in_group("dash_panels"):
		panel.body_boosted.connect(_on_panel_boosted)
		panel.body_wall_hit.connect(_on_panel_wall_hit)

# ── DashPanel hooks ───────────────────────────────────────────────────────────

func _on_panel_boosted(_ship: Node2D, participant: RaceParticipant) -> void:
	participant.cross_panel()

func _on_panel_wall_hit(ship: Node2D, _participant: RaceParticipant,
		push_dir: float, damage: int, pushback: float) -> void:
	## Route through HurtBox so DamageReaction (AI) and PlayerBase._apply_damage (player)
	## both check the shield first — identical path as bullets, mines, and bump collisions.
	var hb := ship.get_node_or_null("HurtBox") as HurtBox
	if hb:
		hb.received_damage.emit(damage)
	if ship.has_method("steer_toward"):
		# AI racer: positional nudge (its X is driven by direct assignment, not physics),
		# then retarget desired_x so LateralMover glides from the pushed position.
		ship.global_position.x += push_dir * pushback
		ship.steer_toward(ship.global_position.x)
	elif ship.has_method("apply_knockback"):
		# Player: a velocity impulse decays naturally and survives held input (move_state
		# yields while it's active), so the shove off the wall is actually felt. Pure
		# lateral — Y is owned by PlayerRaceController's band clamp.
		ship.apply_knockback(Vector2(push_dir * WALL_KNOCKBACK_PLAYER, 0.0))

# ── Racer body collision ──────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_check_racer_collisions(delta)

func _check_racer_collisions(delta: float) -> void:
	## Tick down cooldowns and prune expired ones.
	for key in _bump_cds.keys():
		_bump_cds[key] -= delta
	for key in _bump_cds.keys().filter(func(k): return _bump_cds[k] <= 0.0):
		_bump_cds.erase(key)

	## Collect every ship: player then AI racers.
	var ships: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("player"):
		var s := n as Node2D
		if s:
			ships.append(s)
	for n in get_tree().get_nodes_in_group("racers"):
		var s := n as Node2D
		if s:
			ships.append(s)

	## Check every unique pair (i < j avoids double-checking).
	for i in range(ships.size()):
		for j in range(i + 1, ships.size()):
			var a := ships[i]
			var b := ships[j]
			var key := _bump_key(a, b)
			if _bump_cds.has(key):
				continue
			if a.global_position.distance_to(b.global_position) > BUMP_RADIUS:
				continue
			_bump_cds[key] = BUMP_COOLDOWN
			_apply_bump_damage(a, BUMP_DAMAGE)
			_apply_bump_damage(b, BUMP_DAMAGE)
			_apply_bump_push(a, b)

func _bump_key(a: Node2D, b: Node2D) -> String:
	## Stable key regardless of argument order.
	## IMPORTANT: do NOT use Array as a Dictionary key — GDScript arrays use
	## reference equality, so [id_a, id_b] != [id_a, id_b] on lookup.
	var ia := a.get_instance_id()
	var ib := b.get_instance_id()
	return str(mini(ia, ib)) + "_" + str(maxi(ia, ib))

func _apply_bump_damage(ship: Node2D, damage: int) -> void:
	var hb := ship.get_node_or_null("HurtBox") as HurtBox
	if hb:
		hb.received_damage.emit(damage)

func _apply_bump_push(a: Node2D, b: Node2D) -> void:
	var dx := a.global_position.x - b.global_position.x
	var push := signf(dx) if dx != 0.0 else 1.0   ## lateral only — no Y component
	_push_ship(a,  push)
	_push_ship(b, -push)

func _push_ship(ship: Node2D, push_x: float) -> void:
	if ship.has_method("steer_toward"):
		## AI racer: nudge desired_x; LateralMover will glide toward it.
		ship.steer_toward(ship.global_position.x + push_x * BUMP_PUSH_AI)
	else:
		## Player: add to velocity.x so move_and_slide carries the impulse.
		ship.velocity.x += push_x * BUMP_PUSH_PLAYER

# ── Race lifecycle ────────────────────────────────────────────────────────────

func _on_race_failed() -> void:
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()
