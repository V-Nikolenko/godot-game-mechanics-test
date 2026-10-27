# Mines — the Phase 7 mine family

**Role:** persistent area denial. A mine sits where it was laid (or drifts / creeps slowly), arms, and detonates when a ship enters its trigger radius; enemies steer round
it through the Phase 6 hazard registry. Laid by the Mine Layer (`assault/scenes/enemies/mine_layer/`) and the Bomber, or placed in a `Minefield`
(`assault/scenes/hazards/minefield/`). Conventions: `docs/architecture/PROJECT.md` → *Mines, minefields and the Mine Layer*; module notes:
`docs/architecture/modules/assault.md` → *Mines and the Mine Layer*.

## Files

```
mines/
├── MINES.md                 ← this file
├── enemy_mine.gd            EnemyMine extends EnemyOrdnance (all variants)
├── enemy_mine_scenes.gd     EnemyMineScenes: scene_for / pool_size_for / export_of
├── drifting_mine.tscn  homing_mine.tscn  chain_mine.tscn  pulse_mine.tscn  emp_mine.tscn
├── pulse_ring.gd            PulseRing  (violet expanding Line2D, self-freeing)
└── emp_ring.gd              EmpRing    (blue-white jagged Line2D, self-freeing)
../mine.tscn                 the PROXIMITY variant (the Bomber's mine; same path, no UID)
```

Sprites: `assault/assets/sprites/projectiles/mines/mine_{proximity,drifting,homing,chain,pulse,emp}.png` (24 × 24), `mine_homing_eye.png` (16 × 16), `minefield_beacon.png` (32 × 32);
PixelLab `create_image_pixen`, `view: "high top-down"`. No glow is painted in; the armed blink, warning blink, effect ring and chain links are code-drawn over the `Sprite`.

## Variants

| Variant | Scene | Trigger | Own behaviour | Effect |
|---|---|---|---|---|
| PROXIMITY | `../mine.tscn` | 80 | none | blast 48 / 30 |
| DRIFTING | `drifting_mine.tscn` | 80 | `drift_speed` 35 along `drift_direction` (`drift_max_distance` 1400, or a `drift_leash` ping-pong when placed); `mine_life` 0, backstop 60 s | blast 48 / 30 |
| HOMING | `homing_mine.tscn` | 80 | notices within `notice_radius` 260, creeps at `home_speed` 60 (`home_turn_rate` 2.0), keeps the player until 380, holds at `home_max_distance` 900; `Eye` sprite while noticing | blast 48 / 30 |
| CHAIN | `chain_mine.tscn` | 80 | `chain_trigger(chain_delay 0.2)` on every live mine within `chain_radius` 150; skips its own warning when chained; `shot_detonates`; dashed fuse links, refreshed every 0.5 s | blast 48 / 30 |
| PULSE | `pulse_mine.tscn` | 80 | on detonation `apply_boost_disruption(0.6, 2.5)` on players within `pulse_radius` 170; `PulseRing` | blast 48 / **8** |
| EMP | `emp_mine.tscn` | 80 | on detonation `EmpPulse.emit(…, emp_radius 190, emp_seconds 2.0, self)`; `EmpRing`; the warning shows the radius | **no blast** |

Shared: `arm_delay` 0.5 s, `warning_time` 0.25 s, `hazard_pad` 60, `body_radius` 11. **Warning rule** (asserted from scene exports for every scene, with a synthetic boundary):
`(trigger_radius + effect_radius) / warning_time >= 440 + own_speed` — 512 ≥ 500 for HOMING, 512 ≥ 475 for DRIFTING, 1080 ≥ 440 for EMP.

## Rules every mine follows

- **Contract:** `signal expired` once per life, `reset()`, `launch(dir, speed, target_point)`; a pooled mine never frees itself; never in `enemies`, never scored; any player bullet or rocket
  defuses it (a pop, no blast) except a CHAIN mine, which detonates.
- **Hostility:** PLAYER (laid mines) — layer-128 hurtboxes only, `ContactBlast`. ALL (placed mines) — also a layer-512 area whose `get_parent()` is in group `enemies`, and
  `Hazards.pulse_damage` for the blast (it hurts both sides).
- **Hazard:** `kind = &"mine"`, `radius = trigger_radius + hazard_pad` 60 (140), `avoid_weight` 1.0, registered on `launch()`, unregistered in `_mark_done()` / `_exit_tree()` / `retire()` /
  when a fizzle starts, re-registered after a `reparent()`. `registers_hazard = false` and `hazard_pad = 0` are the pre-approved levers (neither was needed). No pull, slow or LOS.
- **Lifetime:** `mine_life` 0 = never fizzles; `retire()` fades without a blast and emits `expired`. `placed = true` → self-owned, no backstop, `mine_life = placed_life` (0), set up by a
  deferred `_start_if_placed()`; the `ProximityArea` mask is set in `launch()`. `carry_velocity` is added to the reported hazard velocity only.
- **Trap:** `enemy_mine.gd` must not name its own `class_name` (`as EnemyMine`, `Array[EnemyMine]`): the self-reference leaks at exit and fails `verify.sh` with every test green.
- **The Bomber** drops PROXIMITY mines with its Ph4 overrides (`arm_delay`, `eject_time`, `mine_life` 8 s); they are hazards now, and no Bomber or level-1 gate needed a lever.

## Tests

`tests/integration/test_enemy_mines.gd` (every variant's trigger, scene numbers, the warning rule, art, chain ripple and boundaries, pulse and EMP application, real-physics rows; both harnesses),
`tests/integration/test_enemy_ordnance.gd` (the unchanged bomb and PROXIMITY paths), `tests/unit/test_emp_pulse.gd`, `tests/integration/test_player_boost_disruption.gd`,
`tests/unit/test_hazards.gd`, `tests/integration/test_minefield.gd`.
