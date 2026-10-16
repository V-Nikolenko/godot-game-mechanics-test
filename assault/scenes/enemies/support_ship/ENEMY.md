# Support Ship — unarmed healer / shield projector

**Role:** Shadows the most dangerous ally, repairs it, shields its player-facing side, and drags it away when it is badly hurt.
**Fantasy / threat:** A fragile, evasive hull with a dish projector. It deals no damage itself; it makes the enemies around it harder to kill, so the player has to decide whether to chase it.

> **Build state (Phase 5, in progress).** t10 built the **shell** only: scene, flat config with every §2.11 field, contact
> profile NONE, `can_be_repaired()` false, and a minimal brain that holds near the nearest live ally and leaves on its Assault
> budget. Still to come: the ward choice and follow (t11), repair and shield (t12), the escort (t13), the real art with the
> unfolding projector (t14), the hub idle (t15), the hub patrol (t16) and level 1 (t17).
> Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.11–§2.15. Decisions: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` ("t10 as built").

---

## Stats

| Property | Value |
|---|---|
| HP | 55 (`support_ship_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | none: `ContactProfile` mode NONE, `ContactHitBox` closed and `damage` 0 |
| Speed | `max_speed` 270, `acceleration` 700, `max_turn_rate` 4.0 |
| Body | one `CircleShape2D` r 34 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | **placeholder** (`sniper.png`, `Projector` uses `sniper_barrel.png`) until t14; `sprite_forward_angle = PI / 2` |
| Scene / config | `support_ship.tscn` / `support_ship_config.tres` (flat `SupportShipConfig`) |
| Score | 60 |

---

## Behaviour

- **Brain:** `SupportShipBrain` (`Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }`, append-only; `enter_phase()` seam).
  t10 plays SEEK_WARD and DISENGAGE only.
- **SEEK_WARD (t10):** `nearest_ally()` is the nearest live `BaseEnemy` in group `enemies`, never another `SupportShip`. The ship
  `arrive()`s at the point `follow_distance` from it along the line from the ally to itself and stops inside 12 px of it. With no
  ally it requests zero velocity and drifts in place. `brain.ward` mirrors the ally it holds.
- **DISENGAGE:** Assault only. When the `EngagementBudget` (`engage_seconds` 9.0) expires it releases the corridor, raises the
  mover cap to `exit_speed` 300, curves to the nearest edge of the projectile world rect and frees itself outside it (the Bomber's
  exit). It has no telegraphed attack, so nothing defers the exit. Open Space never expires.
- **Scene nodes:** `Projector` (`Sprite2D`, `scale.y` 0 = folded; Godot clamps a zero scale to an epsilon), `Tether` (`Line2D`,
  `top_level`, drawn in world space, hidden). No pool, weapon or `StateLight`: its state is the projector and the tether.
- **Repair:** `can_be_repaired()` is false, so supports never repair each other.
- **Rails:** `on_suspended()` drops the ward, folds the projector and hides the tether. There is no weapon, so no rail fallback.
- **Death / scoring:** a normal `BaseEnemy` death; score 60.

---

## Config exports

`SupportShipConfig` carries the whole plan §2.11 table in groups: Base (`max_health` 55, `collision_damage` 0, `score_value` 60),
Movement, Follow, Ward (`ward_min_score` 20, `ward_search_radius` 900, `ward_keep_radius` 1100, `min_ward_seconds` 2.0,
`ward_switch_margin` 1.3, `no_ward_grace` 1.5), Repair, Shield, Escort and Assault. t10 reads Movement, `follow_distance` and the
Assault group's `engage_seconds` / `exit_speed`; the rest is read by t11-t13. See `support_ship_config.gd` for the meaning of each.

---

## Spawn notes

- WaveBuilder method: `b.support_ship()` — see `docs/enemy-roster.md`. Not yet placed in any level (t16, t17).

---

## Files

```
support_ship/
├── ENEMY.md
├── support_ship.tscn
├── support_ship.gd              ← SupportShip: config, can_be_repaired() false, fold_projector()
├── support_ship_brain.gd        ← SupportShipBrain
└── support_ship_config.gd / .tres
```

Tests: `tests/integration/test_support_ship.gd` (structure, config, contact 0 in both harnesses, holds near an ally, DISENGAGE,
suspend) plus the roster rows in `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
`test_base_enemy.gd` and a case in `test_enemy_dual_mode.gd`.
