## EscortContainer — where a boss's reinforcements live (IDEAS §10; Phase 11 §2.2, docs/plans/cmug256so0031m52wbxomst72/3-plan.md; built in t2).
## A static helper, never instanced.
##
## A boss's escorts are never added straight to the enemy container: they go into ONE `Node2D` sibling of the boss named `<boss name>Escorts`
## (group `&"boss_escorts"`, meta `boss` = the boss), created lazily at the first launch. So `LevelDirector._wait_enemies_cleared()`, which
## counts the enemy container's children, waits on the boss, its bullets and this one container, and the container goes with the boss: it is
## freed on the boss's `tree_exiting` (and the boss's own `_finish_death()` frees it explicitly). Escort pools resolve their container as
## the escort's parent, so escort bullets and explosion particles live and die here too.
##
## Tests: tests/integration/test_boss_reinforcements.gd.
class_name EscortContainer
extends RefCounted

const GROUP := &"boss_escorts"
const BOSS_META := &"boss"


## The escort container of [param host], created on first use as a sibling of the host (null when the host has no parent).
static func ensure(host: Node2D) -> Node2D:
	var existing := of(host)
	if existing != null:
		return existing
	if host == null or not is_instance_valid(host):
		return null
	var parent := host.get_parent()
	if parent == null:
		return null
	var container := Node2D.new()
	container.name = "%sEscorts" % host.name
	container.add_to_group(GROUP)
	container.set_meta(BOSS_META, host)
	parent.add_child(container)
	host.tree_exiting.connect(container.queue_free, CONNECT_ONE_SHOT)
	return container


## The escort container of [param host], or null when it has none (yet).
static func of(host: Node) -> Node2D:
	if host == null or not is_instance_valid(host):
		return null
	var parent := host.get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is Node2D and child.is_in_group(GROUP) and not child.is_queued_for_deletion() \
				and child.get_meta(BOSS_META, null) == host:
			return child as Node2D
	return null
