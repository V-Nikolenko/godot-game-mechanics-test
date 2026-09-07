# Probes — raw measurements behind `3-plan.md`

Run with `godot --headless --path /work/repo -s <script>` on `4.6.3.stable.official.7d41c59c4`.
Both need the scratch scenes described in each script's header, under `res://_probe3/`; those were
created and deleted in the cycle that took the measurement, so re-running requires recreating them
(the sources are inlined below). They are kept out of the project tree on purpose — a scratch scene
left behind would be swept up by `test_project_load_integrity.gd` and by the entity sweeps.

## Scratch scenes used

```gdscript
# _probe3/pcfg.gd — a stand-in for a ShipConfig subclass
extends Resource
class_name _PCfg3
@export var max_health: int = 100
# _probe3/pcfg.tres — max_health = 100, no resource_local_to_scene

# _probe3/base.gd — stand-in for BaseEnemy: privatises in _init(), config declared in the SUBCLASS
class_name _ProbeBase
extends Node2D
func _init() -> void:
	var cfg: Variant = get("config")
	if cfg is _PCfg3 and not (cfg as Resource).resource_path.is_empty():
		set("config", (cfg as Resource).duplicate())

# _probe3/derived.gd + derived.tscn — stand-in for Gunship
extends _ProbeBase
@export var config: _PCfg3 = load("res://_probe3/pcfg.tres")

# _probe3/{init_v,et_v,ini_v}.gd + .tscn — the three copy sites, single-script (no base class):
#   init_v: privatise in _init()      et_v: privatise in _enter_tree()      ini_v: load(p).duplicate() initializer
```

## `probe_init_ordering.gd` — does a BASE-class `_init()` see a SUBCLASS `@export` member?

This is the measurement the whole revised design rests on: `config` is declared on each enemy
subclass, but the copy lives in `BaseEnemy`.

```
  BASE._init: get('config') -> (res://_probe3/pcfg.tres):<Resource#-9223372000481769919> | is _PCfg3: true
   -> privatised in _init
PRE-ADD: a.config == shared -> false
  BASE._init: get('config') -> (res://_probe3/pcfg.tres):<Resource#-9223372000481769919> | is _PCfg3: true
   -> privatised in _init
after pre-add write, fresh instance b.max_health = 100 (shipped 100)
shared.max_health = 100
  DERIVED._ready: config path=''
  DERIVED._ready: config path=''
a.config == b.config -> false
```

**Yes.** Subclass member initializers run before the base `_init()` body, so `get("config")` in
`BaseEnemy._init()` already holds the loaded resource. And the hazardous **pre-`add_child` write**
(`a.config.max_health = 13`) left `shared.max_health` at 100 and a later spawn at 100 — the window
review finding D1 identified is closed at construction.

## `probe_pack_serialisation.gd` — does a per-instance copy get embedded when a scene is packed?

Recorded because review finding D4 correctly rejected the earlier, unrecorded version of this
measurement. `in_tree` says whether the node was added to the `SceneTree` before `pack()`.

```
init_v   in_tree=false sub_resource=true ext_resource_cfg=false
init_v   in_tree=true  sub_resource=true ext_resource_cfg=false
et_v     in_tree=false sub_resource=false ext_resource_cfg=true
et_v     in_tree=true  sub_resource=true ext_resource_cfg=false
ini_v    in_tree=false sub_resource=true ext_resource_cfg=false
ini_v    in_tree=true  sub_resource=true ext_resource_cfg=false
```

**The earlier claim was an artifact.** `et_v`'s one clean row is the out-of-tree case, where
`_enter_tree()` has simply not run yet. Once the node is actually in the tree — the only state in
which the copy exists at all — **all three variants embed a `[sub_resource]`**. So `pack()`
behaviour does not discriminate between the three copy sites and was withdrawn from the plan's
decision table.

Separately, the scenario that row was *meant* to model — a human opening an enemy scene in the
editor and saving — is not modelled by any of these probes, and on reflection does not arise: a
non-`@tool` GDScript gets a placeholder script instance in the editor, so `_init()`, `_enter_tree()`
and `_ready()` never run there and no copy exists to serialise. No `@tool` script exists under
`assault/` or `global/`. This is reasoning, not a measurement — it could only be confirmed in a GUI
editor, which this container does not have.
