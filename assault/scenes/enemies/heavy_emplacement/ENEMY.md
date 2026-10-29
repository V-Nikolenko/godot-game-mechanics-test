# Heavy Emplacement — a big gun platform with two independent cannons

**Role:** The Stationary Defense Turret's heavy sibling: a 128 px platform that carries a beam cannon and a burst cannon at once. Each cannon aims on its
own, so a player who dodges the beam's frozen line is still being tracked by the burst.
**Fantasy / threat:** A fortress gun. The beam is the slow, readable one (it shows its line and never re-aims); the burst keeps leading you. At 1.2 rad/s each
head is slow to swing, so the answer is to break the angle, not to outrun the gun.

> **Build state (Phase 8, t11).** Built on the t6–t8 turret shell. The art task (t15) replaces the code-drawn placeholder; the hub site (t18) and level 1 (t19)
> place it. Mounting on large ships is Phase 10. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.9.

---

## Stats

| Property | Value |
|---|---|
| HP | 260 (`heavy_emplacement_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 0 contact: `ContactProfile` NONE and **no `ContactHitBox`**. Beam 1.2 s lit and burst rounds (8 each) are the mounts' own numbers |
| Speed | none: no `EnemyMover`. In Assault an `AssaultDrift` child scrolls it down at `assault_drift_speed` 60 px/s |
| Body | one `CircleShape2D` r 64 shared by the body (layer 1) and the `HurtBox` (layer 512, mask 65) |
| Sprite | placeholder, code-drawn: a base disc on the root and a head disc plus barrel on each mount. The art task (t15) replaces it |
| Scene / config | `heavy_emplacement.tscn` / `heavy_emplacement_config.tres` (a `DefenseTurretConfig`; the scene's `config` export points at it) |
| Score | 150; **`counts_as_escape` false** |

---

## Behaviour

- **Same root script and brain as the standard turret** (`DefenseTurret`, `DefenseTurretBrain`, see [the turret's ENEMY.md](../defense_turret/ENEMY.md)).
  Perception, the Assault view gate, power-down, tow refusal and `is_laser_blocking() == false` are all inherited.
- **Two `TurretMountSlot`s under `MountSlots`.** `BeamSlot` holds a `BEAM_CANNON` at (0, −30); `BurstSlot` holds a `BURST_CANNON` at (0, 34). Each slot sets
  `turn_rate_override` 1.2, which the turret copies onto the mount before `setup()` (the standard 2.0 stays on a lone turret). The mounts are built at
  runtime, so the slot is the only authored place to retune one.
- **Independent aim.** Each mount aims from its own pivot at its own aim point and writes only its own `rotation`. A beam cannon freezes its bearing for its
  0.9 s telegraph while the burst cannon keeps turning toward the player.
- **One owner group.** Both mounts, and the turret itself, share the turret's owner group (a turret group's, else `turret_<id>`), so its beam never burns
  its own hull, its other cannon, or a group mate.
- **One `StateLight`**, driven by the brain over both mounts: CHARGING while either is in TELEGRAPH, ARMED while either is tracking or firing, OFF when
  unpowered. `set_powered(false)` (a power source dying) powers both mounts down: the beam is cancelled or fades, the burst stops, both droop to rest.
- **`rocket_clear_radius()`** reads the scene's body radius (64 + 4), so a future rocket mount on a heavy host clears its hull.
- **Not an escape, no wreck** (`counts_as_escape` false, `wreck_chance` 0).

## Spawning

```gdscript
b.heavy_emplacement().at(0, -120)
```

A turret group slot can use `heavy_emplacement.tscn` as a `member_scene`. **Never place it in an `ENEMIES_CLEARED` section** (persistent fire). Not placed in
level 1 or the hub yet (t18, t19).

## Tests

`tests/integration/test_defense_turret.gd` §19 (both harnesses): two mounts and r 64 body, `turn_rate` 1.2 on each, HP / score from its own `.tres`,
independent aim, both weapons firing in one engagement, the beam never hitting its own hull or owner group, `power_down` reaching both, the `WaveBuilder`
entry. Plus its dual-mode case in `test_enemy_dual_mode.gd` and the roster gates (hurtbox geometry, contact geometry, contact damage, `test_wreck.gd`,
`test_base_enemy.gd`).
