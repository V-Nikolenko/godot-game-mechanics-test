# Context — `ExplosionEffect`'s container resolution

## The complaint, verbatim

> `explode()` resolves its target as `get_parent().get_parent()` with no check on what that
> is, so attaching the effect one level too deep silently parents the particles inside the
> entity instead of the container — they are then freed with the entity and inherit its
> rotation, with no error. ... A `push_warning` when the resolved container is itself an
> ancestor-owned node, or an explicit `container` export, would turn a silent visual bug into
> a loud one.
>
> Found on 2026-09-03 while fixing the shared-component signal/logging defects.

## Finding: already resolved, by a different completed task

This backlog item describes `global/components/explosion_effect.gd` **as it existed before
2026-09-08**. Confirmed against history: `git show 4126376~1:global/components/explosion_effect.gd`
shows the exact code shape complained about —

```gdscript
func explode(at: Variant = null) -> void:
	var actor := get_parent() as Node2D
	if not actor:
		return
	var container := actor.get_parent()
	if not container:
		return
```

— a fixed two-hop walk, both failure branches silent (`return` with no warning), no way for a
caller to override the container.

Commit `4126376` ("agent: cycle 2026-09-08-0038-i1") shipped the fix for a separate, already-`done`
backlog task, **`explosioneffect-orphans-its-particles-onto-whatever-the-dying`**
(`docs/plans/explosioneffect-orphans-its-particles-onto-whatever-the-dyin/`), filed and completed
independently of this one. Its plan (`3-plan.md`) rewrote the same method for a different set of
symptoms (racers with no explosion, blasts at the origin, blasts hundreds of px off) — but the fix
covers this backlog item's complaint too, change for change:

1. **The fixed-hop walk is gone.** `actor` is now found by `_nearest_node2d()`, walking up from the
   effect's parent to the nearest `Node2D` ancestor — not a hard-coded hop count. "One level too
   deep" no longer silently returns nothing or mis-resolves; it still finds the right actor.
2. **An explicit `container` argument exists** (`explode(at, container)`) — literally the second
   option this backlog item proposed ("or an explicit `container` export"). Documented at
   `explosion_effect.gd:34-36`: *"lets a caller whose actor's parent is not a safe home (an entity
   that is itself freed with a larger wreck, for instance) say so explicitly."* Used today by
   `station_turret.gd` to route the blast to the station's own container instead of the hull.
3. **The remaining silent-failure branch (no `Node2D` ancestor found) now `push_warning`s** before
   returning (`explosion_effect.gd:44-47`), covered by
   `tests/unit/test_explosion_effect.gd::test_an_effect_with_no_node2d_ancestor_warns_and_does_not_crash`.

## Why a generic runtime guard for "resolved container is ancestor-owned" isn't the right fix

The backlog item's first proposed option — warn when the resolved container is
"an ancestor-owned node" — turns out not to be a meaningful runtime check given the design that
shipped. By construction, the **default** container is always `actor.get_parent()`, i.e. always an
ancestor of the actor; that is the intended, documented default ("Particles are spawned directly
into a container (the actor's parent by default...)"), not a symptom of anything wrong. The actual
risk is narrower: whether that ancestor *also* gets freed as part of the same death — and
`explode()` has no way to know that from inside itself, since it runs strictly before the caller's
`queue_free()`. There is no future free() to inspect at the time `explode()` runs.

The shipped design resolves that narrower risk the same way research for the prior task
recommended (reject "guess and warn" schemes prone to false negatives, e.g. the rejected
group-based FX host, `3-plan.md`'s "Alternatives rejected"): the one call site where it is a real
risk (`station_turret.gd`, a sub-node whose parent — the station hull — dies with it) passes an
explicit `container` instead of relying on the default, and the invariant test
`tests/integration/test_explosion_effect_placement.gd::test_a_destroyed_turret_leaves_its_blast_outside_the_hull`
gates it — it instantiates a real `SpaceStation`, kills a real turret, and asserts the resulting
particles are **not** descendants of the station (i.e. they survive the wreck).

## Verification run this cycle (no code changed)

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit \
  -ginclude_subdirs -gselect=test_explosion_effect -gexit
→ 11/11 passed (includes the loud-warning and explicit-container-override cases)

godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration \
  -ginclude_subdirs -gselect=test_explosion_effect_placement -gexit
→ 6/6 passed (includes the turret-survives-the-wreck ancestor-ownership case)
```

## Conclusion

No implementation is needed. This task is closed as resolved by the already-completed
`explosioneffect-orphans-its-particles-onto-whatever-the-dying` task, which shipped both remedies
this item proposed (explicit override + loud warning on the remaining silent path) as part of a
larger fix for the same component. No plan/review stage follows, since there is no design decision
left to make or review — the design decision was already made, reviewed and approved in the other
task's `4-review.md`.
