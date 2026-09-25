## The single lookup of the Assault-vs-Open-Space provider (see
## assault/scenes/systems/arena_camera.gd's class doc and
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.5a / §2.5a).
##
## The provider is whatever node has joined the &"assault_arena" group (today, only ArenaCamera).
## This file is the only code project-wide that looks that group up, and it does so duck-typed
## (has_method), so nothing under global/ names the Assault-only ArenaCamera class. With no
## provider in the tree, the mode is Open Space: no rect, no cull, no constraint.
##
## Every rect/constraint getter has a has_* companion, because an absent result and a
## legitimately empty Rect2() (position and size both zero) are not distinguishable by value
## alone.
class_name EnemyWorld
extends RefCounted

const ARENA_GROUP : StringName = &"assault_arena"


## The Assault provider node, or null when there is none (Open Space).
static func arena(tree: SceneTree) -> Node:
	if tree == null:
		return null
	return tree.get_first_node_in_group(ARENA_GROUP)


## True when there is a provider that answers projectile_world_rect().
static func has_projectile_world_rect(tree: SceneTree) -> bool:
	var provider := arena(tree)
	return provider != null and provider.has_method("projectile_world_rect")


## The Assault corridor's projectile world bounds, or an empty Rect2() with no provider.
static func projectile_world_rect(tree: SceneTree) -> Rect2:
	if not has_projectile_world_rect(tree):
		return Rect2()
	return arena(tree).projectile_world_rect()


## True when there is a provider that answers enemy_cull_rect().
static func has_cull_rect(tree: SceneTree) -> bool:
	var provider := arena(tree)
	return provider != null and provider.has_method("enemy_cull_rect")


## The Drone Interceptor's legacy off-screen cull rect, or an empty Rect2() with no provider.
static func cull_rect(tree: SceneTree) -> Rect2:
	if not has_cull_rect(tree):
		return Rect2()
	return arena(tree).enemy_cull_rect()


## True when there is a provider that answers enemy_movement_constraint(). False for a provider
## that predates that method (added in a later task) as well as for no provider at all.
static func has_movement_constraint(tree: SceneTree) -> bool:
	var provider := arena(tree)
	return provider != null and provider.has_method("enemy_movement_constraint")


## A fresh MovementConstraint from the provider, or null with no provider, or with a provider
## that does not yet implement enemy_movement_constraint().
static func movement_constraint(tree: SceneTree) -> Object:
	if not has_movement_constraint(tree):
		return null
	return arena(tree).enemy_movement_constraint()
