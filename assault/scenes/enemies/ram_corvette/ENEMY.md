# Ram Corvette — armoured charger

**Role:** Heavy charger wearing three breakable armour plates. Bullets glance off it; rockets knock the plates off one at a time, and only then does the hull take damage.
**Fantasy / threat:** A battering ram you have to *open* before you can kill it. Touching it hurts and shoves you away.

> **Build state (Phase 4, t16 armour).** The armour, the ARMOR contact profile, the minimal brain (APPROACH, Assault
> budget, DISENGAGE) and the placeholder art are built. The predicted-intercept charge (LINE_UP / WIND_UP / CHARGE /
> WIDE_TURN), the plate glow, stagger and the faster exposed hull are t17; the real hull and plate sprites are t18.
> Plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` §2.6; task plan `docs/plans/cmuyk2qq8008xoa2xxoq1frgn/3-plan.md`.

---

## Stats

| Property | Value |
|---|---|
| Hull HP | 120 (`max_health`; takes damage only once all three plates are gone) |
| Plate HP | 50 each (`plate_health`): one rocket of either kind breaks one, two Sniper Shots (40) do |
| Contact | 50 armoured (`collision_damage`) with a 260 px/s shove (`armor_shove_speed`); 60 exposed (`exposed_collision_damage`), no shove |
| Speed | `cruise_speed` 280 (APPROACH); `exit_speed` 500 (Assault DISENGAGE) |
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

- **Brain:** `RamCorvetteBrain` (`Phase { APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE }`, `enter_phase()`
  seam, `phase_changed(new_phase: int)`). Today APPROACH is a plain intercept at `cruise_speed`; Assault: an
  `EngagementBudget` (`engage_seconds` 4.5) then DISENGAGE, which curves out of the world rect and frees.
- **Mover:** `EnemyMover` AUTO (`acceleration` 500, `max_turn_rate` 2.2). The script has no `_physics_process`.
- **Contact:** `ContactProfile` mode ARMOR — armed at setup and never detonates or hurts its owner.
- **Rails:** `suspend_ai()` keeps the ARMOR contact armed; the brain only switches its `StateLight` off. Nothing fires.
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
- `tests/integration/test_enemy_dual_mode.gd` — APPROACH identical in both modes; DISENGAGE frees it in Assault only.
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
