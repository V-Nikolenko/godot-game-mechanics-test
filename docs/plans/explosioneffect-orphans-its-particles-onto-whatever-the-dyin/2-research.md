# Research — detached death VFX ownership

The question is not "how do I make particles outlive an entity" (the component already does
that) but **who should own them**, and how a component can stop depending on an unwritten
placement rule. Five findings, each with the tradeoff it implies for the plan.

| # | Finding | Tradeoff | Typical values / specifics | Source |
|---|---|---|---|---|
| 1 | The standard Godot answer is exactly what this component does: move the effect **up the tree** before the entity is freed, either by `remove_child()`/`add_child()` onto the parent or by reparenting to the scene root. `cybereality`'s reply is the canonical snippet: `remove_child(particles); particles.position = position; get_parent().add_child(particles); call_deferred("queue_free")`. | Reparenting to **`get_parent()`** is the path of least resistance and is what everyone reaches for — which is precisely how FX end up mixed into a gameplay container. Reparenting to the **root** avoids the mixing but loses the world transform if any ancestor is transformed. | Position must be re-set explicitly at the moment of the hop; the reparent is *not* transform-preserving unless you use `reparent()` or set `global_position`. | [godotforums #31774](https://godotforums.org/d/31774-how-to-keep-particles-going-after-queue-free) |
| 2 | Doing the hop **at death time from inside the dying entity** hits Godot's node lifecycle: reparenting from `tree_exiting` fails with *"Parent node is busy setting up children"*, so it must be deferred. The forum's accepted workaround is a `RemoteTransform2D` plus a `call_deferred()` self-reparent to the root. | Deferred reparenting adds a frame of latency and a whole class of ordering bugs, and the thread's own conclusion is that this is "surprisingly manual" in Godot. **This is an argument for the current design** — creating a *fresh, already-detached* particle node at death time (what `explode()` does) sidesteps reparenting entirely. The plan should keep that and fix only the container resolution. | `call_deferred()` required; `tree_exiting` is too late. | [Godot Forum 6637](https://forum.godotengine.org/t/best-way-to-make-effect-attached-to-node-survive-the-nodes-death/6637) |
| 3 | The self-free the component relies on — `p.finished.connect(p.queue_free)` — is only valid because `one_shot = true`. The docs are explicit: *"When `one_shot` is disabled, particles will process continuously, so this is never emitted."* The signal itself only exists because of a long-standing proposal for it. | Any change that flips `one_shot`, or that reuses/pools a particle node across bursts, **silently converts every explosion into a permanent leak** — no error, just growing child counts. Pooling the particles is therefore off the table for this change. | `one_shot = true` + `explosiveness = 0.9`, `lifetime = 0.5` → node lives ~0.5–1 s. | [CPUParticles2D docs](https://docs.godotengine.org/en/stable/classes/class_cpuparticles2d.html), [godot-proposals #649](https://github.com/godotengine/godot-proposals/issues/649) |
| 4 | Engine-architecture practice separates **presentation from gameplay state**: layers exist "to group objects for rendering only, allowing entities from different layers to logically interact while being separated visually". Ambient/impact VFX are treated as a distinct layer with its own budget, not as world entities. | Supports giving FX their own container rather than `enemy_container`. The cost is that a purely visual layer is one more node every level scene must declare, and if it is *missing* the component needs a defined fallback — otherwise a level author's omission becomes a silent no-FX bug (the same class of failure as defect #1). | — | [Separation of Gameplay (Game Developer)](https://www.gamedeveloper.com/programming/separation-of-gameplay), [Core VFX docs](https://docs.coregames.com/tutorials/vfx_tutorial/) |
| 5 | Using a **group** as the "find the FX host" mechanism is a known anti-pattern: groups are magic strings where "making a typo or misremembering the name of a group results in silent faults" (an empty array, no error), they are untyped, and they are largely invisible to runtime debugging. | **This kills the `fx_host` group option.** A mistyped group name would reproduce exactly the failure this task exists to remove — an FX system that silently does nothing. An `@export`ed `NodePath`/`Node` reference, or an explicit argument, is type-checked and visible; it costs more wiring but cannot fail silently. | The recommended alternative is a typed reference or a typed registry, at the cost of boilerplate. | [Do not use — Groups](https://theduriel.github.io/Godot/Do-not-use---Groups) |

## What this implies for the design

- **Keep** the "create a fresh detached node at death time" approach (finding 2). Do not switch
  to reparenting an existing child, and do not pool (finding 3).
- **Reject** the group-based FX-host lookup (finding 5).
- The remaining candidates are an **explicit container reference** and a **robust ancestor
  walk**. Finding 4 says an FX-only container is architecturally right; finding 5 says the way
  it is *found* must be type-checked and must have a defined, non-silent fallback.
- Whatever is chosen, the `as Node2D` early return that hid defect #1 must stop being silent —
  every source here agrees the expensive failures in this area are the quiet ones.

## Judgement calls (no citable source)

- Nothing found addresses "FX nodes inflate a gameplay `get_child_count()` poll" directly; the
  closest is finding 4's general separation argument. The searches for that exact bug returned
  nothing on point. Treating `level_director.gd:131`'s poll as something FX should not
  participate in is **my judgement**, argued from finding 4, not a cited result.
