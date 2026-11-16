# Carrier — an armoured capital ship you take apart

**Role:** A capital ship that does not chase the player; it controls space. In Open Space it holds the player at long range with a battery side
turned to them and never strays far from its anchor. In Assault it crosses the corridor top to bottom at a constant speed: a moving arena.
**Fantasy / threat:** The hull is armour that nothing hurts. You destroy it part by part: engines, gun batteries, hangars, and finally the core,
which opens only after three outer parts are wrecks. Losing engines makes it turn slowly and list. Wrecked parts stay on the hull, dark, so the
ship visibly comes apart.

Plan: `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.6 (Phase 10 t6); task plan `docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md`. The
weapons (side batteries, bow heavy cannon, missile bank, pulse ring) arrive in t7; the hangar doors and launches in t8; the real multi-part art in
t9 (the textures here are stand-ins); hub placement in t10; level 1 in t12.

---

## Stats

| Property | Value |
|---|---|
| Hull HP | 600 (`config.max_health`, equal to the core's). Damage never lowers it: it drops to 0 only when the core dies |
| Contact | 15, `ContactProfile` ARMOR with `shove_speed` 220 (one shove on touch) |
| Score | 600, `counts_as_escape` true, `wreck_chance` 0 |
| Body | one 176 × 280 `RectangleShape2D` shared by the body, the root `HurtBox` and the `ContactHitBox`; body layer 0 / mask 0 (it ploughs through, and the player can fly onto it) |
| Speed (Open Space) | `max_speed` 70, `acceleration` / `braking` 40, `max_turn_rate` 0.35 rad/s |
| Speed (Assault) | a constant `assault_cross_speed` 90 px/s down; `assault_max_speed` 110 on the mover |
| Hazards | avoidance 0.5, margin 120, resistance 1.0 (Assault writes the mover's avoidance to 0) |
| Scene / config | `carrier.tscn`, `carrier_config.tres` (`CarrierConfig`, flat) |

## Parts (`Modules/*`, `EnemyModule`s; `ModularHull` beside them)

Nose-down art: the nose is local +y, so **port (the hull's left) is local +x**, the stern local −y. Every part hurtbox stays within x ±100 px of the
centre (`module_x_extent`; level 1's lane maths relies on it). No two part hurtboxes overlap.

| Part | id | Role | HP | Centre, hurtbox | Starts |
|---|---|---|---|---|---|
| `EnginePort` / `EngineStarboard` | `engine_port` / `engine_starboard` | ENGINE | 180 | (±56, −116), 48 × 48 | open; `Light` = `CarrierEnginePlume` (code-drawn, goes out with the engine) |
| `GunPort` / `GunStarboard` | `gun_port` / `gun_starboard` | WEAPON | 160 | (±64, 40), 48 × 48 | open; empty `MountSlots` (t7 mounts the burst cannons) |
| `HangarPort` / `HangarStarboard` | `hangar_port` / `hangar_starboard` | HANGAR | 220 | (±60, −56), 64 × 56 | locked (t8 opens them with the doors) |
| `Core` | `core` | CORE | 600 | (0, 0), 56 × 56 | locked until exposure |

**The armoured hull.** `deflects_hit()` and `is_armored()` always answer true, so every player projectile crossing the hull overlaps it without
being consumed and reaches whichever part it meets. `_on_received_damage` refuses every hit (white flash, `armor_deflected(damage)`), so bullets,
rockets, the beam, the nova and a level laser never lower the hull bar. `homing_point(from)` is the nearest live *vulnerable* part's centre, else
the hull centre.

**The core.** When `core_exposure_count` (3) outer parts (any mix of engines, guns and hangars) are wrecks, the core's lock lifts, deferred, so the
next physics frame sees it open; its plating art opens (`core_open_texture`), `core_exposed` fires and the brain enters PANIC on its next tick.
Until then any hit on the core pings and does nothing. **The core's death is the carrier's:** it sets the hull bar to 0, which runs the normal
`BaseEnemy` death; every wreck goes with the hull.

---

## Behaviour (`CarrierBrain`, `enum Phase`, append-only)

```
Open Space hub: CRUISE ──perceive──▶ NOTICING ──▶ SCREEN   beyond lose_radius ──▶ RETURNING ──▶ CRUISE
Open Space engaged: SCREEN (IDLE while no player is in the tree)
Assault: CROSS (its whole life)
Core exposed (either mode, any phase): PANIC, for good
```

- **SCREEN:** holds the player in a band of 600–950 px. It closes only from beyond the band and opens only from inside it, by arriving at the band's
  middle on the line to the player. That point is clamped into the `leash_radius` 900 disc round `patrol_anchor`, so it never strays further.
  It turns the nearer live gun battery's side to the player, or its bow (t7's heavy cannon) with no battery left.
- **PANIC (Open Space):** backs away to the far side of its anchor from the player, on the leash circle: the leash wins. Same facing.
- **Engines (module death changes movement):** one engine lost: turn rate × 0.5, speed × 0.8, and the hull **lists**. While it holds a heading it
  sags toward the dead side at `list_rate` 0.06 rad/s until 10° off (`list_hold_deg`), then turns back at the scaled rate. Both lost: turn rate ×
  0.15, speed × 0.4, no list.
- **CROSS (Assault):** a constant `assault_cross_speed` 90 px/s straight down, nose-down and never rotated, whatever the engines, PANIC or a slow
  field (the mover's limits are keyed by the mode: `assault_max_speed` 110, acceleration / braking 0, avoidance 0). It sways sideways to keep the
  player inside a live battery's arc, at most `assault_sway_speed` 30 px/s × 1 / 0.5 / 0.1 for 2 / 1 / 0 engines, leashed to ±30 px of its
  spawn x. **An EMP does not stop it:** `on_emp_started()` commits a `mover.boost` down at the crossing speed for the window
  (`BaseEnemy.emp_seconds_left()`); a second EMP that extends the window re-commits it (`Carrier.apply_emp` → `on_emp_refreshed()`). The root
  frees the hull once its top edge is below the projectile world rect, so its Assault life is fixed by spawn y and speed: ≈ 20.6 s worst case
  from design y −260. **No budget, no DISENGAGE.**
- **Never towed** (`accepts_tow()` false), **never repaired**, **never warded** (`accepts_ward()` false: `SupportShipBrain.is_candidate()` skips
  it, since a shield on an armoured hull would never absorb). It answers EMP (AI-driven).

## Spawn notes

- `b.carrier().at(x, y)`. In Assault a wave spawn is **world-anchored in x** (`world_anchored_x`, the turret-group rule), so `.at(x, y)` lands at
  world x `640 + 2·x` whatever the camera's pan. Never give it a `.move()`.
- **Never in an `ENEMIES_CLEARED` section** (`test_engagement_deadline.gd`).

## Files

```
carrier/
├── ENEMY.md                    ← this file
├── carrier.tscn / .gd          (Carrier extends BaseEnemy)
├── carrier_brain.gd            (CarrierBrain)
├── carrier_engine_plume.gd     (CarrierEnginePlume: the code-drawn engine flame, each engine's Light)
└── carrier_config.gd / .tres   (CarrierConfig)
```

Gate: `tests/integration/test_carrier.gd`.
