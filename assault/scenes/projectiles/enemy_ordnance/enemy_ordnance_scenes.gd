## EnemyOrdnanceScenes - the ordnance family's scenes and pool sizing (the `EnemyRounds` shape).
## See docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.3.
class_name EnemyOrdnanceScenes
extends RefCounted

const GRAVITY_BOMB: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_ordnance/gravity_bomb.tscn")
const MINE: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_ordnance/mine.tscn")
const PURSUIT_BOMB: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_ordnance/pursuit_bomb.tscn")


static func scene_for(kind: EnemyOrdnance.Kind) -> PackedScene:
	match kind:
		EnemyOrdnance.Kind.MINE:
			return MINE
		EnemyOrdnance.Kind.PURSUIT_BOMB:
			return PURSUIT_BOMB
		_:
			return GRAVITY_BOMB


## Pooled ordnance a Bomber needs so a run never starves its pool while the previous run's mines are
## still on the field. Mines: `max_mines_per_run` per run, each alive `mine_life`, one run no more
## often than every `min_run_period`. Bombs: four. `cfg` is a `BomberConfig` (any object with those
## fields).
static func pool_size_for(kind: EnemyOrdnance.Kind, cfg) -> int:
	if kind == EnemyOrdnance.Kind.MINE:
		return int(cfg.max_mines_per_run) * int(ceil(float(cfg.mine_life) / float(cfg.min_run_period)))
	return 4
