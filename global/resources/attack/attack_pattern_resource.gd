## AttackPatternResource — pure data describing how a ship fires.
##
## Contains configuration only (no runtime timer state). Runtime state lives in
## AttackController, so multiple ships can safely share the same .tres asset.
## Subclasses override fire() to implement bullet acquisition and configuration.
class_name AttackPatternResource
extends Resource

@export var fire_interval: float = 0.8  ## Seconds between shots.
@export var start_delay: float = 0.0    ## Initial delay before first shot.

## Called by AttackController when the interval timer fires.
## ship: the Node2D that owns the AttackController
## pool: the BulletPool to call acquire() on
func fire(_ship: Node2D, _pool: BulletPool) -> void:
	pass
