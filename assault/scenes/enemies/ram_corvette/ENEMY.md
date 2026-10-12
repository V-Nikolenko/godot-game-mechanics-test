# Ram Corvette — armoured charger

**Role:** Heavy charger wearing three breakable armour plates. Bullets glance off it; rockets knock the plates off one at a time, and only then does the hull take damage.
**Fantasy / threat:** A battering ram you have to *open* before you can kill it. Touching it hurts and shoves you away.

> **Build state (Phase 4, t16 armour + t17 charge).** The armour, the ARMOR contact profile, the predicted-intercept
> charge (LINE_UP / WIND_UP / CHARGE / WIDE_TURN), the plate glow, the stagger, the faster exposed hull and the Assault
> budget rules are built; the real hull and plate sprites are t18, the hub idle t19, level 1 off rails t21/t22.
> Plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` §2.6; task plans `docs/plans/cmuyk2qq8008xoa2xxoq1frgn/3-plan.md`
> (armour) and `docs/plans/cmuyk2qqb0091oa2xy7yn9sxa/3-plan.md` (charge).

---

## Stats

| Property | Value |
|---|---|
| Hull HP | 120 (`max_health`; takes damage only once all three plates are gone) |
| Plate HP | 50 each (`plate_health`): one rocket of either kind breaks one, two Sniper Shots (40) do |
| Contact | 50 armoured (`collision_damage`), any phase, with a 260 px/s shove (`armor_shove_speed`); 60 exposed (`exposed_collision_damage`), during CHARGE only, no shove |
| Speed | `cruise_speed` 280 (exposed 340), `acceleration` 500, `charge_speed` 620 (exposed 700), `exit_speed` 500 (Assault DISENGAGE) |
| Body | `CircleShape2D` r 34, shared by the body, the root `HurtBox` (default `DefenseProfile`, mask 1121) and `ContactHitBox`; the plates reach 42 px (an 84 px ship) |
| Sprite | placeholder `ram_ship.png` (`Sprite2D`, `rotation = PI`, scale 2.6); plates are placeholder `Polygon2D`s under each plate's `Sprite` |
| Scene / config | `ram_corvette.tscn` / `ram_corvette_config.tres` (flat `RamCorvetteConfig`) |

---

## Armour

Armour is a **deflection rule on a full-size hurtbox**, never a narrowed mask (the hurtbox-geometry gate; the space
station's precedent).

- **Plates:** `Plates/PlateFront` (on the nose, local +y), `Plates/PlateLeft` (the ship's left = local +x) and
  `Plates/PlateRight`, at 0° / ±100° from the nose, each an `ArmorPlate` (`global/components/armor_plate.gd`) with its
  own capsule `HurtBox` (layer 512, mask 96), `Health` and `Sprite`. A rocket (or a projectile that answers
  `is_high_impact()`, i.e. the Sniper Shot) damages a plate; anything else glances off (`deflected`, a flash). Each
  plate resolves a hit once (`ArmorPlate._resolve`), so a volley's later rockets pass a plate the first one broke.
- **Hull while any plate lives:** `is_armored()` / `deflects_hit()` are true, so every player projectile crossing it
  is *not* consumed (rockets fly on to a plate); `_on_received_damage` refuses every hit with a flash and
  `armor_deflected(damage)` — which also covers the direct emitters (beam, engine boost, nova, dash);
  `is_laser_blocking()` is true, so the beam stops at it.
- **Exposure is deferred** to the end of the physics step the last plate breaks in (`call_deferred("_expose")`), so a
  rocket that breaks the last plate while overlapping the hull cannot also land on it. Then `armor_broken` fires,
  contact damage becomes 60 and the shove stops.
- **Homing rockets** steer at `homing_point(from)`: the live plate nearest the rocket, else the hull centre. One
  homing volley (3 rockets) strips all three plates of a lone Corvette; a frontal warhead volley strips only the front
  plate (the side plates' inner edge, ~27 px, clears the outer warheads' 23 px reach).
- **Ship modules:** EMP skips it (`_IMMUNE_CLASSES`); engine boost is not on its immune list any more — the hull rule
  deflects the boost while armoured and takes it once exposed.

Signals: `armor_deflected(damage: int)`, `plate_broken(plate_name: StringName)`, `armor_broken`.

---

## Behaviour

- **Brain:** `RamCorvetteBrain`, `Phase { APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE, STAGGER }`
  (STAGGER appended so t16's values hold; t19's hub phases go after it), `enter_phase()` seam,
  `phase_changed(new_phase: int)`.
  - **APPROACH** at `cruise_speed` until within `engage_range` (420). Open Space: an intercept 0.5 s ahead. Assault: the
    same intercept point offset `assault_side_offset` (240) beside the player (the side it is on; a centred spawn
    takes the roomier corridor half, then a seeded coin) and above/below it, so the charge is diagonal (level-1
    spawns: 28-43° off vertical).
  - **Attack gate:** LINE_UP only with `budget.remaining() >= line_up_cap + ATTACK_GATE_MARGIN` (0.5 + 0.05 s; INF
    in Open Space), so a line-up always becomes a wind-up before the budget expires.
  - **LINE_UP** (≤ `line_up_cap` 0.5 s): brakes hard (`braking` 1600, written to the mover only in LINE_UP / WIND_UP
    / STAGGER) and turns its nose onto the aim, P̂ = the player `clamped_lead_time(d, charge speed, 0.15, 0.6)` ahead,
    clamped to the corridor. Ends early once within 8° and at a crawl.
  - **WIND_UP** (0.65 s): a 20 px/s creep along the aim, every live plate's glow ramps to 1, `StateLight` CHARGING.
    The aim tracks P̂ at ≤ 0.8 rad/s for the first 60 %, then freezes (`charge_dir`, `charge_point`).
  - **CHARGE:** `mover.boost` along the frozen aim to `overshoot` (220 px) past the point, never longer than
    `charge_max_time` (1.45 s). `StateLight` COMMIT. Never re-aimed.
  - **WIDE_TURN:** the heading turns toward the player at `wide_turn_rate` (1.4 rad/s) at cruise; the glow fades over
    0.3 s. Within 30° of the player (or after 4 s) → LINE_UP if in range and the gate is open, else APPROACH. A miss
    never hurts it.
  - **STAGGER** (0.4 s): a plate broken in LINE_UP or WIND_UP cancels the charge; it stops, the light blinks, then
    lines up again. A plate broken in CHARGE (or STAGGER) changes nothing.
  - **Exposed** (`armor_broken`): cruise 340, charge 700, contact armed only during CHARGE; in APPROACH / WIDE_TURN,
    while the player's nose is within 20° of it and inside 600 px, it strafes out of the aim line at 180 px/s
    (`evade_nudge`). The light blinks once.
  - **Assault expiry:** in APPROACH / LINE_UP / WIDE_TURN it disengages that tick (nearest edge); in WIND_UP /
    CHARGE / STAGGER it waits (`disengage_pending`, at most 0.65 + 1.45 = 2.1 s) - after a charge it flies straight
    on along the charge heading at `exit_speed` until out of the world rect; after a stagger it takes the nearest edge.
- **Mover:** `EnemyMover` AUTO (`acceleration` 500, `max_turn_rate` 2.2). The script has no `_physics_process`.
- **Contact:** `ContactProfile` mode ARMOR — armed at setup and never detonates or hurts its owner. Armoured it stays
  armed in every phase; exposed, the brain arms it only during CHARGE.
- **Rails:** `suspend_ai()` keeps the ARMOR contact armed for life; the brain switches its `StateLight` off and latches
  `suspended`, so a plate break or exposure on a rail changes no phase and never disarms it. Nothing fires.
- **Group:** `enemies` (homing locks, beam, boost, EMP checks). The legacy `ram_ships` group is gone, and with it
  `bullet.gd`'s rule that stopped the Sniper Shot on a ram.
- **Death / scoring:** `BaseEnemy` emits `died`, awards `score_value` 35.

---

## Spawn notes

- WaveBuilder method: `b.ram()` — see `docs/enemy-roster.md`. Level 1 still spawns it on a rail
  (`.move(b.straight(...))`) until the migration tasks.

## Tests

- `tests/integration/test_ram_corvette.gd` — plate-by-plate vulnerability with real bullets, warheads, homing and
  warhead volleys through a real `RocketState`, the Sniper Shot, the beam, engine boost / EMP, contact, deferred
  exposure, `homing_point`, rails; real-projectile rows in both harnesses.
  The t17 rows (both harnesses unless noted): charge direction against the frozen P̂, wind-up length / crawl / glow,
  overshoot, the boost and LINE_UP caps, the miss and wide turn, contact and braking by phase, stagger, exposed stats
  and evasion, the Assault diagonal, the gate margin, expiry by state, Open Space repeat charges, and the
  attack-in-budget row over every level-1 ram offset through a real `WaveManager` (times printed) with its
  cruise-160 boundary.
- `tests/integration/test_enemy_dual_mode.gd` — APPROACH identical in both modes (Assault side offset zeroed); DISENGAGE frees it in Assault only.
- `tests/integration/test_player_bullet_lifetime.gd` — a launched bullet is not consumed by a live plate, is by an
  exposed hull; an armoured Corvette no longer stops a Sniper Shot.

---

## Files

```
ram_corvette/
├── ENEMY.md            ← this file
├── ram_corvette.tscn
├── ram_corvette.gd
├── ram_corvette_brain.gd
└── ram_corvette_config.gd / .tres
```
