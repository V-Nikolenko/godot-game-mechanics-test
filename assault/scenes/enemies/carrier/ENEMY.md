# Carrier — an armoured capital ship you take apart

**Role:** A capital ship that does not chase the player; it controls space. In Open Space it holds the player at long range with a battery side
turned to them and never strays far from its anchor. In Assault it crosses the corridor top to bottom at a constant speed: a moving arena.
**Fantasy / threat:** The hull is armour that nothing hurts. You destroy it part by part: engines, gun batteries, hangars, and finally the core,
which opens only after three outer parts are wrecks. Losing engines makes it turn slowly and list. Wrecked parts stay on the hull, dark, so the
ship visibly comes apart.

Plan: `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.6 (Phase 10 t6) and §2.7 (t7, weapons); task plans `docs/plans/cmwafsrb700afqs2yd3qqvvrb/`
(t6), `docs/plans/cmwafsrb900ajqs2yb5jcl5ij/` (t7) and `docs/plans/cmwafsrbc00anqs2y9y0ovll4/` (t8, hangars, §2.8). The multi-part art is in
(t9, see Art below); hub placement in t10 (draw 20, 3400 ring at -112.5 degrees, anchor about (-1301, -3141), footprint = `idle_radius` + `leash_radius`; unengaged it launches nothing, engaged its escorts land in `EnemyContainer`); level 1 in t12.

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
| `GunPort` / `GunStarboard` | `gun_port` / `gun_starboard` | WEAPON | 160 | (±64, 40), 48 × 48 | open; one BURST_CANNON each (`MountSlots/Slot0`, rest 0° / 180°, traverse 150° to its own side) |
| `HangarPort` / `HangarStarboard` | `hangar_port` / `hangar_starboard` | HANGAR | 220 | (±60, −56), 64 × 56 | locked: hittable only while its doors are open (t8, below) |
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
  It turns the nearer live gun battery's side to the player, or its bow (the heavy cannon) with no battery left.
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

## Weapons (t7, §2.7)

The brain ticks every weapon after its movement, in every phase that fights (Open Space SCREEN / PANIC, Assault always). **In Assault nothing
fires, and no pulse starts, while the hull centre is outside the view** (the Ph8 turret rule). Guns need line of sight (on the physics step); the
bank fires past cover.

| Weapon | Where | Mount | Rule |
|---|---|---|---|
| Side batteries | `Modules/GunPort` / `GunStarboard` `MountSlots/Slot0` | BURST_CANNON (`burst_cannon_mount.tscn`: 4 Pulse rounds, cooldown 2.2 s, range 700) | traverse **150°** centred on its own side: **a dead battery leaves its side safe** (the other can never aim across) |
| Bow heavy cannon | `HullMounts/Bow` (0, 116) | HEAVY_CANNON (2 Heavy Shells, 220 px/s, charge 0.7 s, cooldown 3.2 s, range 900) | traverse **70°** forward; a hull system, silent only when the carrier dies |
| Missile bank | `HullMounts/Dorsal` (0, 64) | ROCKET_BATTERY, written by the root: `cooldown_seconds` = `missile_cooldown` 7.0, `pursuit_chance` = `missile_pursuit_chance` 1.0 (PURSUIT only) | 360°; only at a player beyond `missile_min_range` **450** px of the hull centre. Its rockets persist after the carrier |
| Anti-approach pulse | `AntiApproachRing` (`carrier_pulse_ring.tscn`, inherited `energy_ring.tscn`) at the hull centre | owned and ticked by `CarrierBrain` | starts when the player is strictly inside `pulse_trigger_range` **340** px, at most every `pulse_cooldown` **5.0** s counted from each start. Ring: telegraph 1.0 s, 360 px/s to `max_radius` 420, band 24, two 50° gaps turning 30°/s, 14 damage |

Pools are root children built by `ModularHull.build_mounts()` (module slots: `PulsePool_0` / `_1`) and then `TurretMountBuilder.build()` over
`HullMounts` with the running index (`PulsePool_2`, `DumbPool_3` / `PursuitPool_3`).

**The ring's victims** are `EnergyHitScan`'s: the player, allies, and enemies and asteroids **outside** the carrier's owner group
(`owner_group()`, which the launched children join, so it passes them). It never reaches a part (enemy energy weapons never target
`enemy_parts`), so it cannot hurt its own hull or parts; it **does** hurt another enemy it sweeps (Ph8 friendly fire, owner choice 8).

**PANIC** (core exposed), on entry, once: each side battery's `cooldown_seconds` × `panic_battery_factor` 0.7 (2.2 → 1.54 s; the bow and the bank
keep theirs), the pulse cooldown × `panic_pulse_factor` 0.5 (2.5 s; a ring lasts 2.32 s), and the emergency deployment
(every live hangar that may still launch empties at once, below). Assault: the crossing is unchanged.

**Lights (§2.9):** the hull `StateLight` is CHARGING (yellow) while any mount or the ring telegraphs, ARMED (red) while a mount tracks, fires or
cools down or the band expands, else OFF; in PANIC it strobes (0.25 s, ARMED / OFF) but never hides a telegraph. `Modules/Core/Light` (a
`StateLight`) flashes red on the same strobe in PANIC.

**An EMP or a rail** silences everything at once: every mount `scan(0.0)` (a telegraph never lands), the ring ends (a telegraph goes OFF, an
expanding band is cancelled and its fade finished on the spot, since the brain is not ticked through the window), lights OFF. **Death** ends the
ring in the same call (`died` → `cancel_pulse()`).

## Art (t9, §2.10)

Top-down, nose-down, no side faces; faction palette (dark navy hull, maroon / red trim, cool blue edge lights). Source:
`assault/assets/sprites/enemies/carrier/`, natural size (every `Sprite` has scale 1). The hull has empty sockets for every part, the bow cannon housing and
the dorsal missile bank, so a wreck reads as damage to a part.

| Texture | Size | Used by |
|---|---|---|
| `hull.png` | 192 × 288 | root `Sprite2D` (covers the 176 × 280 body); chamfered stern, flank notches, tapering bow |
| `engine.png` / `engine_wreck.png` | 48 × 48 | `EnginePort` / `EngineStarboard` (nozzle on the stern edge, where the code-drawn plume starts) |
| `gun.png` / `gun_wreck.png` | 48 × 48 | `GunPort` / `GunStarboard` (octagonal housing; the turret head is code-drawn) |
| `hangar_closed.png` | 64 × 56 | `HangarPort` / `HangarStarboard` `intact_texture`: two door leaves shut on a seam. The starboard module has `Sprite.flip_h` |
| `hangar_open.png` | 64 × 56 | `Doors.open_texture`: the bay open, leaves retracted, launch slot on the outer flank. Drawn over the closed art with alpha = `open_amount`; the starboard `Doors` has `scale.x` −1 |
| `hangar_wreck.png` | 64 × 56 | `wreck_texture`: torn, skewed doors hanging open over a burnt bay |
| `core_plated.png` / `core_exposed.png` / `core_wreck.png` | 64 × 64 | `Core` `intact_texture`; `Carrier.core_open_texture` (the plating peeled open on a glowing reactor); `wreck_texture` |

So a hangar has three door states (closed / open / wreck) and the core three plating states (plated / exposed / wreck), all as textures. Every part texture is
≤ 90 % fully opaque and has transparent corners: `tests/integration/test_ph10_sprites.gd`, and `test_entity_sprite_transparency.gd` (widened in t9 to every
`Texture2D`-valued node property, so module, door and core exports are measured too). No shape, part position or `HomingPoint` changed.

## Hangars (t8, §2.8)

`CarrierHangars` (`carrier_hangars.gd`, a `RefCounted` built by the root, held and ticked by the brain after the weapons) drives the two HANGAR
parts. Each hangar module carries `Doors` (`CarrierHangarDoors`: its `open_texture` is the open-bay art over the closed hangar sprite; code-drawn leaves when it is null), `Light` (a `StateLight`) and
`Mouth` (a `Marker2D` 48 px outboard: hull x ±108).

**The door cycle** (`CarrierHangars.Door { CLOSED, OPENING, LAUNCH, OPEN }`, append-only): CLOSED → OPENING (`door_open_seconds` 0.8: the doors slide
apart, the light turns CHARGING yellow and **the hangar becomes hittable**, owner choice 4) → LAUNCH (the children come out, inside one tick) →
OPEN (`door_hold_seconds` 2.0, still hittable) → CLOSED (sealed, light OFF). A shot at a closed hangar flies on and pings it.

| | Open Space | Assault |
|---|---|---|
| Schedule clock | runs while fighting (SCREEN / PANIC with a player) | runs from the hull centre's first tick inside the view |
| First OPENING | port at `first_launch_delay` 3.0 s, starboard `starboard_launch_delay` 4.0 s later (7.0 s) | the same |
| Then | each hangar every `launch_period` 9.0 s from its previous OPENING, **only with room**: fewer than `hangar_live_cap` 3 live children of its own and `carrier_live_cap` 6 of the carrier. A hangar at its cap keeps its doors shut until a child is gone | **one launch per hangar per life** |
| Payload | `launch_count` 2 (clamped to the room): port `hangar_port_scene` swarm drones, starboard `hangar_starboard_scene` fighters | `assault_launch_count` 2 swarm drones (`assault_hangar_scene`) from each: 4 in all |

**Children** are spawned synchronously from the brain's tick (the `LaserTender.launch_pair()` rule) at the hangar's `Mouth`, 28 px apart along the
hull axis: brain `rng_seed` from the carrier brain's rng, `start_engaged` true, one `SquadController` per payload scene (held by the hangars), a
collision exception both ways, added as a **sibling** of the carrier, put in its owner group (the pulse ring passes them), pushed outward by
`mover.boost(outward, launch_boost_speed 300, launch_boost_seconds 0.4)` and announced once with `EventBus.enemy_spawned_orphan`. They keep their
own config (score, escape flag, Assault budget), never dock, and **outlive the carrier**. "Live" = valid and not queued for deletion.

**A destroyed hangar never launches again:** its cycle stops where it was, its doors hang open and broken, its light stays OFF. Killed
mid-OPENING, nothing comes out.

**Emergency deployment** (PANIC entry, once): every live hangar that may still launch (Open Space: room under the caps; Assault: not launched yet)
launches at once from whatever door state it is in, without the telegraph, then holds OPEN (hittable). A wrecked hangar, or an Assault hangar
that already launched, deploys nothing; one caught mid-OPENING launches now and not again.

An EMP freezes the hangars with the brain (an open door stays open and hittable through the window).

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
├── carrier_pulse_ring.tscn     (the anti-approach ring: an inherited energy_ring.tscn, exports only)
├── carrier_hangars.gd          (CarrierHangars: doors, launches, caps, emergency deployment)
├── carrier_hangar_doors.gd     (CarrierHangarDoors: the doors, the open-bay art crossfaded over the closed sprite)
└── carrier_config.gd / .tres   (CarrierConfig)
```

Gates: `tests/integration/test_carrier.gd`, `tests/integration/test_carrier_hangars.gd` (the hangars).
