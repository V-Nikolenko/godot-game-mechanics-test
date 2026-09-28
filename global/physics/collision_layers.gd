## Named constants for every physics collision layer bit the project uses.
##
## Mirrors `project.godot [layer_names]` exactly - one constant per named `2d_physics/layer_N`,
## equal to `1 << (N - 1)`. Layer numbers and every scene's `collision_layer`/`collision_mask`
## values are unchanged; this only gives code a name to write instead of a magic number.
## Gated by `tests/integration/test_collision_layer_names.gd`.
class_name CollisionLayers
extends RefCounted

const ENVIRONMENT := 1
const ENVIRONMENT_INTERACTABLE := 2
const ENVIRONMENT_PLAYER := 4
const PICKUPS := 16
const PLAYER_ROCKETS := 32
const PLAYER_HITBOX := 64
const PLAYER_HURTBOX := 128
const ENEMY_HITBOX := 256
const ENEMY_HURTBOX := 512
const HAZARD_CONTACT := 1024
