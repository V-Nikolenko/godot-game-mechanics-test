## EnemyRounds — the pooled enemy bullet family: Pulse, Scatter, Gatling Stream and Heavy Shell.
## Each is an inherited scene of enemy_bullet.tscn (rounds/*.tscn); a shooter that wants a
## different speed/damage still sets it on the acquired bullet, same as today's pattern.
## See docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.2.
class_name EnemyRounds
extends RefCounted

const PULSE: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullet/rounds/pulse_round.tscn")
const SCATTER: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullet/rounds/scatter_round.tscn")
const GATLING_STREAM: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullet/rounds/gatling_stream_round.tscn")
const HEAVY_SHELL: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullet/rounds/heavy_shell.tscn")

## A burst of max_burst rounds, each alive for round_lifetime seconds, fired no more often than
## every min_burst_period seconds, needs this many pooled rounds so a burst never starves the
## pool while the previous burst's rounds are still in flight. A self-timed rail cadence with no
## burst grouping is max_burst = 1 and min_burst_period = its fire interval.
static func pool_size_for(max_burst: int, round_lifetime: float, min_burst_period: float) -> int:
	return max_burst * int(ceil(round_lifetime / min_burst_period))
