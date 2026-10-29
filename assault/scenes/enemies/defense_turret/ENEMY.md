# Stationary Defense Turret — fixed gun emplacement

**Role:** A static point that scans, notices the player, swings its head round at a readable turn rate and fires led bursts. It is the first
consumer of the Phase 8 weapon mounts.
**Fantasy / threat:** A fixed gun covering a lane. The danger is where its fire lanes cross, not the gun chasing you: you can see it turning
and you can out-strafe its partial lead.

> **Build state (Phase 8, t8).** Shell, `TurretMount` cycle, all six mounts (BURST_CANNON, SWEEP_BEAM, ROCKET_BATTERY, PULSE_RING, LANCE, BEAM_CANNON) and `AssaultDrift` are
> built, and so are turret groups and the power source (t9, `assault/scenes/structures/turret_group/`). Still to come in Phase 8: the shield
> generator (t9s), the heavy emplacement (t11), the art (t15) and placement in the hub and level 1 (t18, t19). Mounting on large ships is
> Phase 10. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.7; the task plan is `docs/plans/cmvqw0vnb017rqs2xsyursu5d/3-plan.md`.

---

## Stats

| Property | Value |
|---|---|
| HP | 90 (`defense_turret_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 0 contact: `ContactProfile` NONE and **no `ContactHitBox`** (the Bonus Drone precedent). Each burst-cannon round deals 8, the Pulse round's own damage |
| Speed | none: it has no `EnemyMover`. In Assault an `AssaultDrift` child scrolls it down at `assault_drift_speed` 60 px/s |
| Body | one `CircleShape2D` r 28 shared by the body (layer 1) and the `HurtBox` (layer 512, mask 65) |
| Sprite | placeholder, code-drawn: a base disc (r 30) on the root and a head disc plus barrel on the mount. The art task (t15) replaces it |
| Scene / config | `defense_turret.tscn` / `defense_turret_config.tres` (flat `DefenseTurretConfig`) |
| Score | 60; **`counts_as_escape` false**, so a turret that drifts off the bottom never breaks the combo |

---

## Behaviour

- **Root (`DefenseTurret`).** It never rotates (`rotation` stays 0) and never moves itself.
  - `is_ai_driven()` is false and `accept_tow()` is false.
  - `is_laser_blocking()` is false, so the player's mining beam passes over the root and burns it.
  - It joins group `enemies` in `_ready()`.
  - `variant` (≥ 0) overrides the first slot's mount variant. A wave sets it with `.prop("variant", TurretMount.Variant.X)`.
- **Mounts.** `MountSlots` holds one `TurretMountSlot` marker per mount. It has `variant`, `rest_bearing_deg`, and `turn_rate_override`
  (−1 keeps the mount scene's `turn_rate`; ≥ 0 is copied onto the mount before `setup()`). In `_ready()` the turret does the following for
  each slot:
  - instantiates `TurretMountScenes.scene_for(variant)` under the slot (an unbuilt variant gives a warning and an empty slot);
  - builds every pool in `pool_specs()` as a **root child** named `<name>_<slot index>`, so the rounds land in the turret's own container;
  - calls `mount.setup(self, pools, owner_group)`.
- **Owner group.** It is `set_turret_group(group)`'s `owner_group`, read duck-typed and called before `add_child`, or `&"turret_<instance id>"`
  when there is no group. Phase 8's beams and rings exempt this set.
- **Power.** `set_powered(false)` powers every mount down and turns the light OFF:
  - a telegraph never lands;
  - a burst stops with no further `acquire()`;
  - rounds already in flight live on in their pool;
  - the head eases to `rest_bearing_deg` and stays there ("droop").
  - Re-powering is ignored in this phase.
- **Groups (t9).** A `TurretGroup` spawns turrets from `TurretGroupSlot`s: the slot's `variant` and `rest_bearing_deg` (-> `rest_bearing_override`, the first
  slot's scan centre) are set before `add_child`, the turret joins the group's owner group, and its mounts' `telegraph_gate` becomes the group's
  `request_telegraph()` (TELEGRAPH starts at least 0.3 s apart across the group). The group's power source dying calls `set_powered(false)`.
- **Brain (`DefenseTurretBrain`, `Phase { SCAN, NOTICING, ENGAGED, UNPOWERED }`).** It runs one tick per physics frame through
  `BaseEnemy._physics_process`.
  - Perception in Open Space: the player within `perceive_radius` 900 px, kept until beyond `lose_radius` 1100.
  - Perception in Assault: the turret's centre inside `EnemyWorld.view_rect()`. It never fires from off-screen.
  - SCAN → NOTICING (one `StateLight.blink_once()`) → ENGAGED after `notice_time` 0.3 s. Losing the player drops it back to SCAN.
  - In ENGAGED each mount gets `tick(delta, target, can_fire)`, with `can_fire = can_see_player() or mount.fires_past_cover()`. A wreck or an
    asteroid between turret and player holds the burst cannon's fire. The ray runs only on the physics step.
  - Light: CHARGING while a mount is in TELEGRAPH, COMMIT while one `is_committed()`, ARMED in TRACK / FIRE / COOLDOWN with `can_fire`, OFF
    otherwise.
- **`TurretMount` cycle** (`mounts/turret_mount.gd`, `Phase { SCAN, TRACK, TELEGRAPH, FIRE, COOLDOWN, UNPOWERED }`). The mount writes **only its
  own `rotation`**, turn-rate limited.
  - SCAN is a triangle sweep of `scan_arc_deg` 90° about `rest_bearing_deg` at `scan_speed` 0.4 rad/s. Its start offset comes from the brain's
    rng.
  - TRACK aims at `P.lerp(intercept, lead_blend 0.6)`, a partial lead.
  - TRACK → TELEGRAPH needs all of these: the cooldown over, the target inside `fire_range` 700, `aim_error() ≤ fire_cone_deg / 2` (4°), and
    the optional `telegraph_gate` (a group's stagger, t8).
  - The cooldown is its own clock. Any exit from FIRE except a power-down sets it, so a flickering perception never fires faster than the
    exports.
- **Burst cannon** (`mounts/burst_cannon_mount.tscn`). In order:
  - `charge_seconds` 0.4 (light CHARGING, no line);
  - `burst_count` 4 Pulse rounds, `burst_gap` 0.12 s apart at `round_speed` 300, from a `BurstClock`;
  - `cooldown_seconds` 2.2.
  - A due round outside the cone is held (`shots_held`), never fired wide.
  - Pool `PulsePool_0`: size `EnemyRounds.pool_size_for(4, 8 s, 2.96 s)` = 12.
- **Beam mounts** (`mounts/beam_turret_mount.gd`, `sweep_beam_mount.gd`; scenes `sweep_beam_mount`, `lance_mount`, `beam_cannon_mount`). Each fires one `EnemyBeam`
  that is a **mount child at the muzzle**, set up with the turret as host and its owner group (a turret group never burns its own members; killing the turret
  frees the beam). The mount ticks the beam from `_pre_tick`, **before** the phase step, so the mount and the host's light change on the beam's own tick.
  **The shown line is the line that fires:** the mount stops turning (and its aim point freezes) when TELEGRAPH starts, or - the lance - at the last
  `commit_seconds`. Aim is `P + v * telegraph_seconds * lead_blend`; no fire without line of sight.
  - **BEAM_CANNON** - `beam.tscn`, range 700, cooldown 3.0: bearing frozen at TELEGRAPH start; 0.9 s warning, 1.2 s lit.
  - **LANCE** - `lance.tscn`, range 1100, cooldown 4.0: tracks for the first 0.5 s of its 1.0 s TELEGRAPH, frozen for the last 0.5 s (light COMMIT, white line), then one 24-damage hit.
  - **SWEEP_BEAM** - `sweep_beam.tscn`, range 400, cooldown 3.5: the mount aims at the **start bearing** `aim - s * 50`° (`s` = sign of the player's angular velocity about the
    turret; a still player draws `s` from the brain's rng once per shot), shows the line there, then ACTIVE turns the mount `s * sweep_rate` (0.8727 rad/s, 100° in 2.0 s)
    toward and through the player. **No turn-rate cap during ACTIVE** - the sweep rate is the weapon's, read from the beam scene.
  - `power_down()` cancels a telegraph (never lethal) or fades a lit beam within the tick; it never restarts. The light: CHARGING in TELEGRAPH, COMMIT beats CHARGING in a lance's commit, ARMED while lit.
- **ROCKET_BATTERY** (`mounts/rocket_battery_mount.gd`, `rocket_battery_mount.tscn`). TRACK -> 0.5 s tube glow (light CHARGING, a lamp swells at the muzzle) -> a salvo of 2 Phase 5
  `EnemyRocket`s 0.35 s apart (`BurstClock`) -> 5.5 s cooldown; range 900. Each rocket is PURSUIT with probability 1/3 (`pick_kind()`, one draw from the brain's rng), else DUMB, launched along
  the barrel with the mount's predicted aim point. **Fires without line of sight** (`fires_past_cover()`, the Missile Corvette rule); never from off-screen in Assault. Two pools,
  `DumbPool_0` / `PursuitPool_0`, root children of the turret with `persist_after_owner_death` (a rocket outlives its turret and frees itself on `expired`), each
  `EnemyRocketScenes.pool_size_for()` over a stand-in (`salvo_count`, period = glow + salvo + cooldown) = 2. The turret answers the launcher contract: `launch_velocity()` ZERO and
  `rocket_clear_radius()` = body radius 28 + 4, so a rocket opens its impact box only once clear and never hits its own turret.
- **PULSE_RING** (`mounts/pulse_ring_mount.gd`, `pulse_ring_mount.tscn`). Idle until the player is within `trigger_range` 300 of the mount, then one `EnergyRing` (a mount child centred on the
  mount, owner-ticked from `_pre_tick`, gaps from the rng): 0.8 s TELEGRAPH, expansion to 280, FADE, then 3.5 s cooldown counted from the end of the expansion. The mount does not aim
  (`_tracks()` false, `fire_cone` ignored) and, like every non-rocket mount, holds fire without line of sight. The ring never hurts the turret or its group. `power_down()` cancels a
  telegraph and fades an expanding band.
- **Assault.** `AssaultDrift` moves it down 60 px/s and frees it below `EnemyWorld.projectile_world_rect()`. It does nothing in Open Space.
- **Death / scoring:** standard `BaseEnemy` death, score 60, `wreck_chance` 0 (destroyed structures as wreckage is Phase 19).

---

## Config exports (`DefenseTurretConfig`)

| Export | Default | Meaning |
|---|---|---|
| `max_health` / `collision_damage` / `score_value` | 90 / 0 / 60 | Defence and scoring |
| `counts_as_escape` | false | Drifting out of Assault never breaks the combo |
| `perceive_radius` / `lose_radius` / `notice_time` | 900 / 1100 / 0.3 | Open Space perception |
| `assault_drift_speed` | 60 | Copied onto the `AssaultDrift` child |
| `hazard_avoidance` / `hazard_margin` / `wreck_chance` | 0 / 0 / 0 | No mover; no wreck |

Weapon tuning is **not** in the config. It lives in the mount scenes' exports (`turn_rate`, `fire_range`, `lead_blend`, `fire_cone_deg`,
`scan_arc_deg`, `scan_speed`, `cooldown_seconds`, plus the burst's `charge_seconds`, `burst_count`, `burst_gap`, `round_speed`,
`round_scene`; the rocket battery's `charge_seconds`, `salvo_count`, `salvo_gap`, `pursuit_chance`; the pulse ring's `trigger_range`, `ring_scene`), so a mount behaves the same on any host (Phase 10). Gates read them through `TurretMountScenes.export_of()`.

---

## Spawn notes

- WaveBuilder method: `b.defense_turret()` (const `DEFENSE_TURRET`); `.prop("variant", TurretMount.Variant.BURST_CANNON)` picks the weapon.
- **Never in an `ENEMIES_CLEARED` section** (persistent fire; the phase rule). It is not placed in level 1 or the hub yet (t18, t19).

---

## Files

```
defense_turret/
├── ENEMY.md
├── defense_turret.tscn / .gd             DefenseTurret (mount building, set_powered, set_turret_group)
├── defense_turret_brain.gd               DefenseTurretBrain (SCAN, NOTICING, ENGAGED, UNPOWERED)
├── defense_turret_config.gd / .tres      DefenseTurretConfig
├── turret_mount_slot.gd                  TurretMountSlot (Marker2D)
└── mounts/
    ├── turret_mount.gd                   TurretMount (Variant, Phase, the cycle and its hooks)
    ├── turret_mount_scenes.gd            TurretMountScenes (scene_for, export_of)
    ├── beam_turret_mount.gd              BeamTurretMount (lance + beam cannon; the beam child, freeze rule)
    ├── sweep_beam_mount.gd               SweepBeamMount (start-bearing aim, sweep rotation)
    ├── rocket_battery_mount.gd / .tscn   RocketBatteryMount (salvo of 2, root pools, fires past cover)
    ├── pulse_ring_mount.gd / .tscn       PulseRingMount (EnergyRing child, trigger_range)
    ├── sweep_beam_mount.tscn / lance_mount.tscn / beam_cannon_mount.tscn
    └── burst_cannon_mount.gd / .tscn     BurstCannonMount
```

Shared: `global/components/assault_drift.gd` (`AssaultDrift`).
Tests: `tests/integration/test_defense_turret.gd` (both harnesses), the turret case in `test_enemy_dual_mode.gd`, the tow row in
`test_base_enemy.gd`, the burst speed in `test_enemy_bullet_lifetime.gd`, and the roster rows in `test_enemy_contact_damage.gd`,
`test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` and `test_wreck.gd`. Fixture: `tests/helpers/fixture_turret_mount.gd`.

---

## Design checklist (ideas §43)

| Question | Answer |
|---|---|
| Silhouette | Round base with a turning head and barrel; the art task (t15) gives it its own sprite |
| Preferred distance | Fires inside `fire_range` 700 px; it does not move, so the player picks the distance |
| Movement signature | None: the head turns at 2.0 rad/s and scans 90° when idle |
| Attack | Charged 4-round burst with partial lead (0.6) |
| Player behind it | There is no "behind": the head turns, but a half turn takes about 1.6 s, so circling it is the counterplay |
| Player boosts away | It loses the player beyond 1100 px (Open Space) or when it leaves the view (Assault) |
| Off-screen | Never: Assault gates on the view rect, Open Space on perception, and it holds fire without line of sight |
| Retreat / reposition | None (static). In Assault it scrolls past |
| Telegraph | Head turning onto you, CHARGING light for 0.4 s before each burst; NOTICING blink |
| Destroying it changes the encounter | Opens its fire lane; groups and power sources (t8) make that a choice of order |
| Open Space without camera coordinates | Yes: perception is distance-based |
| Assault with movement constrained | Yes: it drifts with the corridor and fires only on-screen |
| Sprite shows attack / defence state | `StateLight` and the head's aim; unpowered heads droop and dim |
| Armour / shields / weak points | None alone; the shield generator (t9s) can protect a group |
| Alone / combined | Alone: a lane to avoid. In a group with overlapping lanes and a power source (t8), it becomes a puzzle |
| Deterministic tests | Yes: hand-ticked in both harnesses, seeded rng, one real-physics row at 8× |
