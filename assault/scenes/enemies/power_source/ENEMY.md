# Power Source — the reactor a turret group runs on

**Role:** The weak point of a turret group. It never moves or fires; it powers every turret of its group, and destroying it turns all of them dark
and harmless at once, for good.
**Fantasy / threat:** A reactor tied to its guns by amber power lines. It is no threat in itself; the threat is the crossing fire of the turrets
around it. You get through by finding a lane to the reactor.

> **Build state (Phase 8, t9).** Built with `TurretGroup` (`assault/scenes/structures/turret_group/`). The art task (t15) replaces the code-drawn
> placeholder; the hub site (t18) and level 1 (t19) place groups. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.10.2; task plan
> `docs/plans/cmvqw0vnl0183qs2xbphzonu7/3-plan.md`.

---

## Stats

| Property | Value |
|---|---|
| HP | 150 (`power_source_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 0: `ContactProfile` NONE and **no `ContactHitBox`** (the Bonus Drone / turret precedent) |
| Speed | none: no brain, no `EnemyMover`. In Assault an `AssaultDrift` child scrolls it down at `assault_drift_speed` 60 px/s |
| Body | one `CircleShape2D` r 34 shared by the body (layer 1) and the `HurtBox` (layer 512, mask 65) |
| Sprite | placeholder, code-drawn: a dark housing disc (r 36) with an amber core. The art task (t15) replaces it |
| Scene / config | `power_source.tscn` / `power_source_config.tres` (flat `PowerSourceConfig`) |
| Score | 80; **`counts_as_escape` false**, so a source that drifts off the bottom never breaks the combo |

---

## Behaviour

- **No behaviour of its own.** It has no brain: it does not aim, perceive or fire. It joins group `enemies` in `_ready()`, refuses tows (no mover)
  and answers `is_laser_blocking()` false, so the player's mining beam treats it as a target.
- **Power.** `provides_power()` is true. The `TurretGroup` that spawns it registers it with `add_power_provider()`. When it dies (`died`), the group
  calls `set_powered(false)` on every live member **in the same call** if no other provider is left; the turrets go UNPOWERED (beams cancelled or
  faded, bursts stopped, lights OFF, heads drooped) and never restart in this phase. They stay destructible and still score. A source that leaves without
  dying (drifted out of Assault) does not darken its group.
- **Owner group.** `set_turret_group(group)`, before `add_child`, joins the group's `owner_group`, so the group's own beams and pulse rings never hurt
  it. Alone it is `&"power_source_<instance id>"`.
- **Power lines.** While its group is powered, it draws one amber `Line2D` (code-built, `top_level`, width 3) from itself to every live member that is
  not itself a provider, refreshed every frame; the lines go when the group goes dark or a member dies. `power_lines()` returns them (refreshed).

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | 150 | HP |
| `collision_damage` | 0 | No contact damage |
| `score_value` | 80 | Kill score |
| `counts_as_escape` | false | Drifting out of Assault never costs the combo |
| `wreck_chance` | 0 | Leaves no wreck (structures as wreckage is Ph19) |
| `assault_drift_speed` | 60 | Assault scroll, px/s (copied onto `AssaultDrift`) |

---

## Spawn notes

- Not spawned on its own: it is a member of a turret group preset (`TurretGroupSlot.member_scene`), e.g. `assault_pair.tscn`, spawned with
  `b.turret_group(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR)` — see `docs/enemy-roster.md`.
- **Never in an `ENEMIES_CLEARED` section** (its group fires persistently).

---

## Files

```
power_source/
├── ENEMY.md                 ← this file
├── power_source.tscn
├── power_source.gd
└── power_source_config.gd / .tres
```
