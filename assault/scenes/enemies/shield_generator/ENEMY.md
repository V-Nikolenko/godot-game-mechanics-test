# Shield Generator — the dish that wraps a turret group in bubbles

**Role:** A support structure of a turret group. It never moves or fires; while it lives and its group has power, every other member of the group
(turrets, the power source) carries a 360° shield bubble that eats bullets and rockets.
**Fantasy / threat:** A dish tethered to its guns by cyan lines. It is no threat in itself; it makes the position harder to crack. Shoot the dish
(or the reactor behind it) and the bubbles fade within a moment; a beam never cared about them.

> **Build state (Phase 8, t9s).** Built on `TurretGroup` (`assault/scenes/structures/turret_group/`). The art task (t15) replaces the code-drawn
> placeholder; the hub site (t18) places one. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.10.5. Test-only preset with a generator:
> `tests/helpers/shielded_site.tscn`.

---

## Stats

| Property | Value |
|---|---|
| HP | 120 (`shield_generator_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 0: `ContactProfile` NONE and **no `ContactHitBox`** (the turret / power-source precedent) |
| Speed | none: no mover. In Assault an `AssaultDrift` child scrolls it down at `assault_drift_speed` 60 px/s |
| Body | one `CircleShape2D` r 30 shared by the body (layer 1) and the `HurtBox` (layer 512, mask 65) |
| Sprite | placeholder, code-drawn: a dish disc with a cyan core. The art task (t15) replaces it |
| Scene / config | `shield_generator.tscn` / `shield_generator_config.tres` (flat `ShieldGeneratorConfig`) |
| Score | 80; **`counts_as_escape` false**, so a generator that drifts off the bottom never breaks the combo |

---

## Behaviour

- **Projection.** Each physics tick, through `BaseEnemy._physics_process` -> `ShieldGeneratorBrain.tick()`, while powered: every live `BaseEnemy` member
  of its turret group **except itself and except a laser-fence post** (a member answering duck-typed `is_fence_post()`; a `LaserFence` is not a
  `BaseEnemy` at all) gets an `EnemyShield` named `GeneratorShield`, added as a child of the member and attached to its hurtbox's absorber slot, then
  `sustain(player position)` every tick. The shield is the Support Ship's projected shield (`SupportShipBrain._make_shield`) with `sustain_mode`, but a
  **bubble** (`arc_deg` 360): `capacity` 50, `regen_delay` 3.0, `regen_seconds` 2.0, `reboot_seconds` 5.0, `radius` = the member's body radius + 8.
  The power source is shielded too.
- **A ward is never displaced.** If the member's absorber slot is already held (a Support Ship's ward), the generator skips it and retries next tick;
  once the slot is free it takes it.
- **What a bubble does.** It absorbs bullets and rockets (an absorbed hit consumes a default bullet and never reaches the hull) and takes the hit's
  damage off its points; a break reboots it. **Beams bypass it** (direct emitters, owner choice 7), so a beam turret still hurts a shielded one.
- **Lapse.** No more `sustain()` — the generator died, or `set_powered(false)` (the group's power source died; same call) — and each bubble lapses
  after its `heartbeat` 0.3 s, then fades 0.3 s and frees. The generator survives a power loss, dark and shooting-gallery-destructible.
- **Tethers.** One cyan `Line2D` (`top_level`, width 2, the Support Ship's tether colour) to every member it shields, refreshed every tick; a dead
  member loses its line at once; all go when the group goes dark. `tethers()` returns them (refreshed).
- **Lone generator** (no group) shields nothing. Fence posts are never shielded, so "shoot a post to drop the fence" stays cheap inside a defended site.
- **Owner group.** `set_turret_group(group)`, before `add_child`, joins the group's `owner_group`, so the group's own beams and rings spare it. Alone it is
  `&"shield_generator_<instance id>"`. Joins `enemies` in `_ready()`, refuses tows (no mover), `is_laser_blocking()` false.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | 120 | HP |
| `collision_damage` | 0 | No contact damage |
| `score_value` | 80 | Kill score |
| `counts_as_escape` | false | Drifting out of Assault never costs the combo |
| `wreck_chance` | 0 | Leaves no wreck (structures as wreckage is Ph19) |
| `shield_capacity` | 50 | Points of each bubble |
| `shield_regen_delay` / `shield_regen_seconds` / `shield_reboot_seconds` | 3.0 / 2.0 / 5.0 | Bubble refill and reboot |
| `shield_radius_margin` | 8 | Bubble radius = member body radius + this |
| `assault_drift_speed` | 60 | Assault scroll, px/s (copied onto `AssaultDrift`) |

---

## Spawn notes

- Not spawned on its own: it is a member of a turret group preset (`TurretGroupSlot.member_scene`). The hub site (t18) will place one; the only preset
  with a generator today is the test-only `tests/helpers/shielded_site.tscn`.
- **Never in an `ENEMIES_CLEARED` section** (its group fires persistently).
- Gate: `tests/integration/test_turret_group.gd` §13 (both harnesses; the bullet row on real physics at 8×), the generator case in
  `test_enemy_dual_mode.gd`, and the roster files (plan §2.19).

---

## Files

```
shield_generator/
├── ENEMY.md                       ← this file
├── shield_generator.tscn
├── shield_generator.gd
├── shield_generator_brain.gd
└── shield_generator_config.gd / .tres
```
