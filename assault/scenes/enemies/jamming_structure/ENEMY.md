# Jamming Structure — the tower that switches the player's abilities off

**Role:** A static field structure. It never moves or fires; inside its visible static ring the player's **H abilities and K rockets are
refused** (the Phase 9 ability lock). Movement, Shift boost, dash, warp and the main gun are never affected.
**Fantasy / threat:** An interference tower on the enemy's ground. It is no threat in itself; the threat is fighting the ships around it with
half your kit gone. Enemy ships fly through its field as if it were empty space, and seeking rockets (yours and theirs) fly straight inside it.
**Counterplay:** shoot it (the main gun always works, even from inside), step out (the lock lifts 0.75 s after you leave), or step out and fire
EMP Blast, which switches the field off for 5 s (from inside the press is refused like every H press).

> **Build state (Phase 9, t7).** Three variants share these scripts: `jamming_structure/` (local), `sector_jammer/` and `pulsed_jammer/` (each a
> scene and a config only, the `heavy_emplacement/` precedent). **Art (t12):** `Hull` is a `Sprite2D` per variant (`jamming_structure.png` a triangular 3-emitter tower, `pulsed_jammer.png` a disc with a crown of vanes, `sector_jammer.png` a 4-boom star; 64 / 64 / 96 px), the amber lens is baked in and the `StateLight` sits on it; the field ring stays code-drawn. Gate `tests/integration/test_ph9_sprites.gd`.
> Placed in the hub (t13): a `SectorJammer` beside `HubDefenseSite` and a `PulsedJammer`, both under `EnemyContainer` and covered by sweep C of `test_sector_hub_patrol.gd`; not in level 1 yet (t14). Plan: `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.8 / §2.9; task plan
> `docs/plans/cmw5k4yk100aeqs2xwrdu7hwz/3-plan.md`.

---

## Variants

| Variant | Scene | HP | Field radius | Cycle T / A / Q | Stabilisation | Score | Body r | Modes |
|---|---|---|---|---|---|---|---|---|
| local | `jamming_structure/jamming_structure.tscn` | 140 | 240 | always on | 0.75 s | 60 | 28 | both |
| sector | `sector_jammer/sector_jammer.tscn` | 260 | 640 | always on | 1.25 s | 120 | 42 | Open Space only (never in an Assault wave: guard row in `test_engagement_deadline.gd`) |
| pulsed | `pulsed_jammer/pulsed_jammer.tscn` | 160 | 300 | 0.8 / 3.0 / 2.5 s | 0.75 s | 80 | 28 | both |

All three: `collision_damage` 0, `counts_as_escape` false, `wreck_chance` 0, `assault_drift_speed` 60.

---

## Stats

| Property | Value |
|---|---|
| Damage | 0: `ContactProfile` NONE and **no `ContactHitBox`** (the Ph8 structure precedent) |
| Speed | none: no brain, no `EnemyMover`. In Assault an `AssaultDrift` child scrolls it down at 60 px/s and frees it below the projectile world rect |
| Body | one `CircleShape2D` shared by the body (layer 1) and the `HurtBox` (layer 512, mask 65) |
| Field | child `Field`: a `HazardField`, kind `&"jammer"`, `avoid_weight` 0, `pull_force` 0, `movement_penalty` 0, `disables_abilities` true; `radius`, `stabilise_seconds` and the cycle are written from the config in `_ready()` (the scene authors the same values; a row pins that they match) |
| Scene / config | per variant (table above), one flat `JammingStructureConfig` `.tres` per directory |

---

## Behaviour

- **The field is a hazard sampled by the body** (the Ph6 rule). The player's ability lock reads `Hazards.jammer_at(position)`: a lit field
  (`disables_abilities` is written into the info **only while ACTIVE** and not suppressed) locks; leaving it, the field going QUIET, being
  suppressed or the tower dying starts the `stabilise_seconds` delay. Overlapping fields: the largest stabilisation wins.
- **Pulsed:** TELEGRAPH 0.8 s (the ring flickers, the light blinks yellow) -> ACTIVE 3.0 s (lit) -> QUIET 2.5 s (a faint outline, light dark),
  on a loop. TELEGRAPH and QUIET count as outside.
- **Enemies fight inside it:** `avoid_weight` 0, so `Steering.context_avoid` skips it and an enemy's path is unchanged by it. The spot
  selectors treat it as their own ground too: `SniperBrain._candidate()` / `_inside_other_hazard()` and `FighterBrain._inside_other_hazard()`
  skip a `&"jammer"` info (`JAMMER_KIND`), so a firing or cover point inside a field is kept. **Gap:** nothing keeps a sniper's firing point
  off the tower's own body (r 28 / 42); turrets and emplacements have the same gap today.
- **Seekers fly straight inside a lit field:** an `EnemyRocket` skips `_steer()` there (behind `Hazards.count() > 0`; its guidance clock keeps
  running, so it steers again if it leaves inside its window), and so does the player's homing missile. Only steering is skipped: a Cluster
  rocket's split still aims its fan at the predicted point inside a field. A Missile Corvette whose target stands in
  a lit field turns a Pursuit or Cluster roll into Dumb (`MissileCorvetteBrain._roll_kind`; `force_next_kind` still wins).
- **EMP:** `answers_emp()` is true. `apply_emp(seconds, source)` runs BaseEnemy's window (the blue-white `EmpStatic` overlay,
  `is_emp_disrupted()`) and calls `Field.suppress(seconds)`: the field is quiet for the window (longest wins), the tower stays in physics and
  shootable, and a pulsed field's cycle keeps running underneath. So the player's EMP Blast (5 s, scene-wide, but only pressable from outside a
  lit field), the hub EMP zone and a placed EMP mine switch a jammer off; they never make it untouchable.
- **Assault:** `AssaultDrift` 60 px/s; `world_anchored_x` (default true) removes the camera's pan from x once in `_ready()` (the `TurretGroup`
  rule), so `.at(x, y)` lands at world x `640 + 2·x`.
- **No behaviour beyond that.** Joins `enemies` in `_ready()`, refuses tows (no mover), `is_laser_blocking()` false. Death is BaseEnemy's; the
  `Field` child unregisters in `_exit_tree()`.

## Visuals

- `JammerFieldArt` (child of `Field`, code-drawn): 48 dashed arcs at the radius, 3 px, `Color(1.0, 0.85, 0.55)` alpha 0.35, crawling at
  0.4 rad/s, over a 0.05 alpha fill (LIT); TELEGRAPH flickers the ring between 0.35 and 0.1 every 0.1 s (FLICKER); QUIET or suppressed: a
  1 px outline at alpha 0.08. Never cyan (shield) or violet (boost disruption).
- `StateLight` on the emitter: ARMED (red) while lit, blinking CHARGING (yellow) in TELEGRAPH, OFF when QUIET or suppressed.

---

## Config exports (`JammingStructureConfig`)

| Export | Meaning |
|---|---|
| `max_health`, `score_value`, `counts_as_escape`, `collision_damage`, `wreck_chance` | `ShipConfig` base |
| `assault_drift_speed` | Assault scroll, px/s (copied onto `AssaultDrift`) |
| `field_radius` | Field radius, px |
| `stabilise_seconds` | Seconds the lock outlasts leaving (or the field going dark) |
| `cycle_telegraph` / `cycle_active` / `cycle_quiet` | The pulsed cycle; all 0 = always on |

---

## Spawn notes

- `WaveBuilder.jammer()` (local), `jammer(&"pulsed")`, `jammer(&"sector")` (Open Space only); `WaveBuilder.JAMMER` / `PULSED_JAMMER` /
  `SECTOR_JAMMER`.
- **Never in an `ENEMIES_CLEARED` section** (it never leaves on its own in Open Space and drifts slowly in Assault): guard row in
  `test_engagement_deadline.gd`.

---

## Files

```
jamming_structure/
├── ENEMY.md                          ← this file (all three variants)
├── jamming_structure.tscn / .gd      ← JammingStructure
├── jamming_structure_config.gd / .tres
└── jammer_field_art.gd               ← JammerFieldArt
sector_jammer/  sector_jammer.tscn + sector_jammer_config.tres
pulsed_jammer/  pulsed_jammer.tscn + pulsed_jammer_config.tres
```

Tests: `tests/integration/test_jamming_structure.gd`, the jammer rows of `test_emp_blast_module.gd`, `test_missile_corvette.gd` (the downgrade)
and `tests/unit/test_hazard_field.gd` (`suppress`).
