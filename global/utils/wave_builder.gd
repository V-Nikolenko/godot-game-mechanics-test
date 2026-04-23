## Wave builder utilities — shared helpers for defining enemy waves.
## Usage: var builder = WaveBuilder.new()
##        var fighter = builder.straight(speed, angle)
class_name WaveBuilder

# ── Movement helpers ───────────────────────────────────────────────────────────

func straight(speed: float, angle: float = 0.0, duration: float = 0.0) -> StraightMovement:
	var m := StraightMovement.new()
	m.speed = speed
	m.angle = angle
	m.duration = duration
	return m

func arc(direction: ArcMovement.ArcDirection, amplitude: float, duration: float) -> ArcMovement:
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

func curve(path: Curve2D, duration: float, loop: bool = false) -> CurveMovement:
	var m := CurveMovement.new()
	m.path = path
	m.duration = duration
	m.loop = loop
	return m

# ── Formation helpers ──────────────────────────────────────────────────────────

func v_formation(count: int, spread: float = 40.0, row_gap: float = 12.0, stagger: float = 0.1) -> VFormation:
	var f := VFormation.new()
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

func cluster_formation(count: int, spread: float = 50.0, seed_override: int = 0) -> ClusterFormation:
	var f := ClusterFormation.new()
	f.count = count
	f.spread = spread
	if seed_override > 0:
		f.random_seed = seed_override
	return f

# ── Spawn entry & wave builders ───────────────────────────────────────────────

func spawn_entry(
		scene_path: String,
		offset: Vector2,
		movement: MovementResource,
		delay: float = 0.0,
		exit_mode: EnemyPathMover.ExitMode = EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT,
		formation: FormationResource = null,
		initial_props: Dictionary = {}) -> SpawnEntryResource:
	var e := SpawnEntryResource.new()
	e.ship_scene = load(scene_path) as PackedScene
	e.base_offset = offset
	e.movement = movement
	e.spawn_delay = delay
	e.exit_mode = exit_mode
	if formation:
		e.formation = formation
	e.initial_props = initial_props
	return e

func wave(trigger_time: float, entries: Array) -> WaveResource:
	var w := WaveResource.new()
	w.trigger_time = trigger_time
	w.entries.assign(entries)
	return w

func level(name: String, waves: Array) -> LevelResource:
	var l := LevelResource.new()
	l.level_name = name
	l.waves.assign(waves)
	return l

# ── Scene path constants ───────────────────────────────────────────────────────

const FIGHTER := "res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn"
const DRONE   := "res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn"
const RAM     := "res://assault/scenes/enemies/ram_ship/ram_ship.tscn"
const SNIPER  := "res://assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn"
const GUNSHIP := "res://assault/scenes/enemies/gunship/gunship.tscn"
const BOMBER  := "res://assault/scenes/enemies/bomber/bomber.tscn"
const ALLY    := "res://assault/scenes/allies/ally_fighter/ally_fighter.tscn"

# ── Arc direction constants ───────────────────────────────────────────────────

const ARC_LEFT := ArcMovement.ArcDirection.LEFT
const ARC_RIGHT := ArcMovement.ArcDirection.RIGHT
const EXIT_SCREEN := EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
const EXIT_DURATION := EnemyPathMover.ExitMode.FREE_ON_DURATION
