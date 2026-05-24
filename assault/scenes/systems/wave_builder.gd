## Wave builder utilities — shared helpers for defining enemy waves.
## Usage: var b = WaveBuilder.new()
##        b.wave(3.0, [ b.fighter().at(0, -150).move(b.straight(120)).delay(0.5) ])
class_name WaveBuilder

# ── SpawnConfig — fluent spawn entry builder ──────────────────────────────────

class SpawnConfig:
	var _scene: String
	var _offset: Vector2                                             = Vector2.ZERO
	var _movement: MovementResource                                  = null
	var _delay: float                                                = 0.0
	var _exit_mode: EnemyPathMover.ExitMode = EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
	var _exit_time: float                                            = 0.0
	var _formation: FormationResource                                = null
	var _props: Dictionary                                           = {}
	var _look_in_moving_direction: bool                              = true
	var _look_angle: float                                           = 0.0

	func _init(scene: String) -> void:
		_scene = scene

	## Spawn position relative to camera centre (px).
	func at(x: float, y: float) -> SpawnConfig:
		_offset = Vector2(x, y)
		return self

	## Movement path to follow.
	func move(m: MovementResource) -> SpawnConfig:
		_movement = m
		return self

	## Seconds after the wave trigger before this ship spawns.
	func delay(d: float) -> SpawnConfig:
		_delay = d
		return self

	## Free the entity after a fixed number of seconds (FREE_ON_DURATION).
	func free_after(seconds: float) -> SpawnConfig:
		_exit_mode = EnemyPathMover.ExitMode.FREE_ON_DURATION
		_exit_time = seconds
		return self

	## Expand this entry into a formation of ships.
	func formation(f: FormationResource) -> SpawnConfig:
		_formation = f
		return self

	## Shoot straight in the direction of travel (ignores player position).
	func shoot_forward() -> SpawnConfig:
		_props["aim_mode"] = "FORWARD"
		return self

	## Aim each shot at the nearest player.
	func shoot_at_player() -> SpawnConfig:
		_props["aim_mode"] = "PLAYER"
		return self

	## Face the direction of travel (default — provided for symmetry/clarity).
	func look_in_travel_direction() -> SpawnConfig:
		_look_in_moving_direction = true
		return self

	## Lock the ship to a fixed rotation (radians).
	## Sprite convention: 0 = down, PI = up, PI/2 = left, -PI/2 = right.
	func look_at_angle(angle: float) -> SpawnConfig:
		_look_in_moving_direction = false
		_look_angle = angle
		return self

	## Set an arbitrary initial property on the spawned node: entity.set(key, value).
	func prop(key: String, value: Variant) -> SpawnConfig:
		_props[key] = value
		return self

# ── Ship constructors ─────────────────────────────────────────────────────────

func fighter()        -> SpawnConfig: return SpawnConfig.new(FIGHTER)
func drone()          -> SpawnConfig: return SpawnConfig.new(DRONE)
func ram()            -> SpawnConfig: return SpawnConfig.new(RAM)
func sniper()         -> SpawnConfig: return SpawnConfig.new(SNIPER)
func sniper_enemy()   -> SpawnConfig: return SpawnConfig.new(SNIPER_ENEMY)
func gunship()        -> SpawnConfig: return SpawnConfig.new(GUNSHIP)
func bomber()         -> SpawnConfig: return SpawnConfig.new(BOMBER)
func ally()           -> SpawnConfig: return SpawnConfig.new(ALLY)
func big_asteroid()   -> SpawnConfig: return SpawnConfig.new(BIG_ASTEROID)
func small_asteroid() -> SpawnConfig: return SpawnConfig.new(SMALL_ASTEROID)
func bonus_drone()    -> SpawnConfig: return SpawnConfig.new(BONUS_DRONE)

# ── Movement helpers ──────────────────────────────────────────────────────────

func straight(speed: float, angle: float = 0.0, duration: float = 0.0) -> StraightMovement:
	var m := StraightMovement.new()
	m.speed = speed
	m.angle = angle
	m.duration = duration
	return m

func arc(direction: ArcMovement.ArcDirection = ArcMovement.ArcDirection.LEFT, amplitude: float = 130.0, duration: float = 3.5) -> ArcMovement:
	var m := ArcMovement.new()
	m.direction = direction
	m.amplitude = amplitude
	m.duration = duration
	return m

func sine(base_speed: float, amplitude: float, frequency: float = 2.5) -> SineMovement:
	var m := SineMovement.new()
	m.base_speed = base_speed
	m.amplitude = amplitude
	m.frequency = frequency
	return m

func hold(duration: float) -> HoldMovement:
	var m := HoldMovement.new()
	m.duration = duration
	return m

func sequence(steps: Array) -> SequenceMovement:
	var m := SequenceMovement.new()
	m.steps.assign(steps)
	return m

## U-shaped sweep: dips down and left, then exits straight up.
## Exit speed is derived from the arc tangent — no separate parameter needed.
func u_sweep(sweep_width: float = 400.0, sweep_depth: float = 500.0, curve_duration: float = 3.0) -> USweepMovement:
	var m := USweepMovement.new()
	m.sweep_width    = sweep_width
	m.sweep_depth    = sweep_depth
	m.curve_duration = curve_duration
	return m

func curve(path: Curve2D, duration: float, loop: bool = false) -> CurveMovement:
	var m := CurveMovement.new()
	m.path = path
	m.duration = duration
	m.loop = loop
	return m

# ── Formation helpers ─────────────────────────────────────────────────────────

## V shape: lead at front, wings trail behind (open toward the player).
func v_formation(count: int, spread: float = 40.0, row_gap: float = 12.0, stagger: float = 0.1) -> VFormation:
	var f := VFormation.new()
	f.count = count
	f.spread = spread
	f.row_gap = row_gap
	f.stagger_delay = stagger
	return f

## Wedge / ^ shape: wings fan forward past the lead.
func wedge_formation(count: int, spread: float = 40.0, row_gap: float = 12.0, stagger: float = 0.1) -> WedgeFormation:
	var f := WedgeFormation.new()
	f.count = count
	f.spread = spread
	f.row_gap = row_gap
	f.stagger_delay = stagger
	return f

func line_formation(count: int, spacing: float = 30.0, axis: LineFormation.Axis = LineFormation.Axis.HORIZONTAL) -> LineFormation:
	var f := LineFormation.new()
	f.count = count
	f.spacing = spacing
	f.axis = axis
	return f

func diagonal_formation(count: int, step_x: float, step_y: float, stagger: float = 0.15) -> DiagonalFormation:
	var f := DiagonalFormation.new()
	f.count = count
	f.step_x = step_x
	f.step_y = step_y
	f.stagger_delay = stagger
	return f

func cluster_formation(count: int, radius: float = 30.0, seed_override: int = 0) -> ClusterFormation:
	var f := ClusterFormation.new()
	f.count = count
	f.radius = radius
	if seed_override > 0:
		f.random_seed = seed_override
	return f

# ── Wave & level builders ─────────────────────────────────────────────────────

func _config_to_entry(c: SpawnConfig) -> SpawnEntryResource:
	var e := SpawnEntryResource.new()
	e.ship_scene    = load(c._scene) as PackedScene
	e.base_offset   = c._offset
	e.movement      = c._movement
	e.spawn_delay   = c._delay
	e.exit_mode     = c._exit_mode
	e.exit_time     = c._exit_time
	e.look_in_moving_direction = c._look_in_moving_direction
	e.look_angle    = c._look_angle
	if c._formation:
		e.formation = c._formation
	e.initial_props = c._props
	return e

func wave(trigger_time: float, entries: Array) -> WaveResource:
	var w := WaveResource.new()
	w.trigger_time = trigger_time
	var resolved: Array[SpawnEntryResource] = []
	for entry in entries:
		if entry is SpawnConfig:
			resolved.append(_config_to_entry(entry))
		else:
			resolved.append(entry as SpawnEntryResource)
	w.entries.assign(resolved)
	return w

func level(name: String, waves: Array) -> LevelResource:
	var l := LevelResource.new()
	l.level_name = name
	l.waves.assign(waves)
	return l

# ── Scene path constants ──────────────────────────────────────────────────────

const FIGHTER        := "res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn"
const DRONE          := "res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn"
const RAM            := "res://assault/scenes/enemies/ram_ship/ram_ship.tscn"
const SNIPER         := "res://assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn"
const SNIPER_ENEMY   := "res://assault/scenes/enemies/sniper_enemy/sniper_enemy.tscn"
const GUNSHIP        := "res://assault/scenes/enemies/gunship/gunship.tscn"
const BOMBER         := "res://assault/scenes/enemies/bomber/bomber.tscn"
const ALLY           := "res://assault/scenes/allies/ally_fighter/ally_fighter.tscn"
const BIG_ASTEROID   := "res://assault/scenes/hazards/big_asteroid/big_asteroid.tscn"
const SMALL_ASTEROID := "res://assault/scenes/hazards/small_asteroid/small_asteroid.tscn"
const BONUS_DRONE    := "res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn"

# ── Direction constants ───────────────────────────────────────────────────────

const LEFT  := ArcMovement.ArcDirection.LEFT
const RIGHT := ArcMovement.ArcDirection.RIGHT

## Kept for compatibility with any code referencing ARC_LEFT / ARC_RIGHT.
const ARC_LEFT  := ArcMovement.ArcDirection.LEFT
const ARC_RIGHT := ArcMovement.ArcDirection.RIGHT

const EXIT_SCREEN := EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
