# Research — per-instance ship config resources

Scope of the search: how shipped Godot projects handle a custom `Resource` that carries
per-entity tuning data, what the engine actually guarantees, and whether the idiomatic answer is
`duplicate()`, `resource_local_to_scene`, or "keep sharing and never write".

## Findings

| Finding | Tradeoff | Typical values / measurement | Source |
|---|---|---|---|
| **Sharing is the engine's deliberate default, not a bug.** An exported `Resource` is a reference; every node that loads the same path gets the same object, so textures/meshes/materials load once. The failure mode only appears for a resource that carries *mutable game state* — "enemy stats, inventory data, UI styling" is the exact list given. | Duplicating unconditionally throws away the memory win the default exists for. The decision is per-resource-kind, not global: duplicate stats, never duplicate textures. | "A single material shared by 100 enemies is far more efficient than 100 duplicate materials." | [bugnet.io — Godot resource sharing / unintended state](https://bugnet.io/blog/fix-godot-resource-sharing-unintended-state) |
| **`resource_local_to_scene` is duplication performed by `PackedScene.instantiate()`.** The docs are explicit: "If `true`, the resource is duplicated for each instance of all scenes using it," and `setup_local_to_scene()` "is automatically called from `PackedScene.instantiate()` by the newly duplicated resource **within the scene instance**." | It only reaches resources the **scene file stores**. A resource a script `load()`s in its own property initializer is never in the scene state, so `instantiate()` has nothing to duplicate. Also: "Changing this property at run-time has no effect on already created duplicate resources." | — | [Godot docs — `Resource`](https://docs.godotengine.org/en/stable/classes/class_resource.html) |
| **Measured in this repo, Godot 4.6.3 — `resource_local_to_scene` does nothing for our pattern.** A scratch `.tres` with `resource_local_to_scene = true` plus a node declaring `@export var config = load(that path)` yields `a.config == b.config → true` across two `instantiate()` calls. The *same* `.tres` referenced as a **stored scene override** (`config = ExtResource("2")` in the `.tscn`) yields `false`, with `resource_path` blanked on the copies. | The "just tick Local to Scene" fix is only available if we also move all 10 config references out of the scripts and into the `.tscn` files — two files to remember per new enemy, with no runtime signal when one is forgotten. | `a.config == b.config`: `true` (script initializer) / `false` (scene-stored override) | Measured here (probe scenes created and deleted this cycle); consistent with the docs row above |
| **`resource_local_to_scene` is additionally unreliable for nested/dynamically-instantiated scenes.** Marking a shape "Local to Scene" inside a child scene and instantiating the *parent* twice returns the identical resource object. The reporter's own workaround — make the outer scenes local too — is noted as unmaintainable. | Our enemies are always instantiated dynamically by `WaveBuilder`, i.e. exactly the path with the known engine gaps. Betting the invariant on this flag means betting on the fragile half of the feature. | Issue open against 4.2 milestone, unresolved | [godotengine/godot#77380](https://github.com/godotengine/godot/issues/77380) |
| **`duplicate()` is shallow, and the deep form has a hole.** `duplicate(true)` recurses into nested arrays/dictionaries, but a `Resource` found inside is "only duplicated if it's local"; the practitioner writeup states flatly that "subresources inside Array and Dictionary properties are **never** duplicated" and that only `@export`ed properties are copied at all. Its author's broader advice is to avoid needing duplicates. | Shallow `duplicate()` is a *complete* copy only for a flat resource. `1-context.md` already established all 10 config classes are flat (no `Resource`/`PackedScene`/`Texture2D`/`Curve`/`Array[...]` exports), so this hole does not apply — but it becomes a live hazard the day someone adds an `Array[...]` field to a config. That is an argument for a gate test, not for prose. | — | [simondalvai.org — Duplicate Godot custom resources deeply, for real](https://simondalvai.org/blog/godot-duplicate-resources/) |
| **The community's stated best practice is "Resources for reusable definitions and tuning values; normal variables for runtime state."** Duplication is prescribed only where the resource *is* the mutable state ("there will need to be an instance of it for each unit… so they don't all share the same pool of data"). | This is the cheapest stance and the one this project already follows — nothing writes to `config`; `BaseEnemy._ready()` and every station child copy *values* out into their own fields. It leaves the sharing in place and rests the invariant on human memory, which is what already failed once (laser-phase plan, review round 2). | — | [shaggydev.com — A brief look at custom resources in Godot 4](https://shaggydev.com/2026/04/08/godot-custom-resources/), [godotlearning.com — Godot resources explained](https://godotlearning.com/blog/godot-resources-explained) |

## Measured costs (this repo, Godot 4.6.3)

- `SpaceStationConfig.duplicate()` × 1000 → **13.6 ms total, ≈13.6 µs per call**. A wave spawns
  tens of enemies, so the added cost is well under a frame's noise.
- `duplicate()` copies every `PROPERTY_USAGE_STORAGE` property identically (0 mismatches) and
  **blanks `resource_path`**. The blank path is a feature here: a copy can never be re-cached by
  `ResourceLoader` and can never be written back over the shipped `.tres`.

## What this means for the plan

1. `resource_local_to_scene` is **rejected on measurement**, not on taste: it is inert for a
   script-side `load()` initializer, and the alternative arrangement it needs (config stored in
   each `.tscn`) is the arrangement with the open engine bug for dynamically instantiated scenes.
2. `duplicate()` at **property-initialisation time** is the only mechanism that satisfies every
   reader, because the station's child nodes (`station_gunnery.gd:102`, `station_laser_phase.gd:90`,
   `station_reinforcements.gd:107`, `station_death_sequence.gd:108`) read `_station.config` in
   their own `_ready()`, which runs **before** the parent's. A copy installed in the station's
   `_ready()` arrives too late for all four. Their own comments already say the export is
   "initialised at property-init time" and that this is what they rely on.
3. The "keep sharing, enforce read-only" stance is genuinely defensible and already partly
   implemented (`tests/README.md:531-537`, four test headers). Its weakness is that it is prose:
   it has no failure signal, and it already came within one review round of being violated. The
   plan should therefore adopt the copy **and** convert the prose into an invariant test, so the
   guarantee survives the next enemy someone adds.
4. Any fix must not change a single shipped balance value — the copy is a copy, and the test plan
   must assert that against the `.tres` on disk rather than trusting `duplicate()`.

## Sources

- [Godot docs — `Resource` (`resource_local_to_scene`, `setup_local_to_scene`, `duplicate`)](https://docs.godotengine.org/en/stable/classes/class_resource.html)
- [godotengine/godot#77380 — Local to Scene fails to create a new instance for nested scenes](https://github.com/godotengine/godot/issues/77380)
- [godotengine/godot-proposals#1848 — Local to Scene is counter-intuitive](https://github.com/godotengine/godot-proposals/issues/1848) — read, but contributes **no** technical claim; it is a design-philosophy thread and is cited here only to record that it was checked and does not support a limitation claim.
- [bugnet.io — Fix: Godot resource sharing / unintended state between instances](https://bugnet.io/blog/fix-godot-resource-sharing-unintended-state)
- [simondalvai.org — Duplicate Godot custom resources deeply, for real](https://simondalvai.org/blog/godot-duplicate-resources/)
- [shaggydev.com — A brief look at custom resources in Godot 4](https://shaggydev.com/2026/04/08/godot-custom-resources/)
- [godotlearning.com — Godot resources explained: items, stats, tuning data](https://godotlearning.com/blog/godot-resources-explained)

---

## Addendum (review round 1)

The `PackedScene.pack()` measurement that revision 1 of the plan used to reject the
initializer/`_init()` copy sites was an **out-of-tree artifact** and has been withdrawn; the raw
re-measurement is in `probes/probe_pack_serialisation.gd` and `probes/README.md`. The
`resource_local_to_scene` and `duplicate()` findings in the table above were independently
reproduced by the reviewer and stand. One further engine fact was measured in round 2 and is what
the revised design rests on: **a base class's `_init()` body runs after the subclass's member
initializers** (`probes/probe_init_ordering.gd`).
