# Context — ExplosionEffect particle ownership

## The shape of the problem

`ExplosionEffect.explode()` resolves where its `CPUParticles2D` goes with a **fixed two-hop
walk**:

```gdscript
var actor := get_parent() as Node2D      # explosion_effect.gd:40
var container := actor.get_parent()      # explosion_effect.gd:43
```

That encodes an unwritten contract: *the `ExplosionEffect` must sit exactly one hop below a
`Node2D` entity, which must itself sit exactly one hop below the node that should own the FX.*
Nothing enforces it, nothing reports a violation, and **3 of the 10 construction sites break
it** — two of them silently. The component's own docstring (`:34-38`) spends five lines warning
about the failure mode, which is the tell that the contract is in the wrong place.

Separately, and independently of where the FX are parented, the component sets the particles'
position **before** it parents them, so the coordinate is applied as a local one (defect 3
below).

## Construction sites (all 10)

**Corrected after review round 1** — the first version of this table had a duplicate row
(`space_station.gd`, which has no `ExplosionEffect.new()` of its own; it inherits
`base_enemy.gd:54`), omitted `station_death_sequence.gd:179` entirely, and marked two sites "OK"
that are not. `grep -rn "ExplosionEffect.new()"` returns exactly these ten.

| Site | Parent of the effect | `actor` resolves to | Verdict |
|---|---|---|---|
| `assault/scenes/enemies/base_enemy.gd:54` | the enemy | the enemy | OK |
| `assault/scenes/player/player_fighter.gd:46` | the player | the player | OK |
| `assault/scenes/allies/ally_fighter/ally_fighter.gd:50` | the ally | the ally | OK |
| `open_space/scenes/entities/player/player_ship.gd:71` | the ship | the ship | OK |
| `assault/scenes/enemies/space_station/station_death_sequence.gd:179` | the station | the station | OK — the only caller that passes `at` |
| `assault/scenes/hazards/asteroid_base.gd:35` | the asteroid | the asteroid | **blast offset** — a `RaceAsteroid` sits under `Track` (`race_level_1.tscn:79-80`, `position = (0, -777)`) |
| `assault/scenes/race/track/race_wall.gd:24` | the wall | the wall | **blast offset** — same `Track` parent, 777 px up-track |
| `assault/scenes/enemies/space_station/station_turret.gd:79` | the turret | the turret | **blast offset** by the station's own transform, *and* FX land in `$Turrets`, inside the hull that is freed with the wreck |
| `global/components/damage_reaction.gd:24` | the `DamageReaction` **`Node`** | `null` | **no FX at all** |
| `assault/scenes/race/core/race_ship.gd:97` | the ship's *container* | the container | **FX at world origin** |

## Three confirmed defects, all verified empirically

Probes run headless against the real component and the real scenes (`godot --headless -s`).

1. **Every `DamageReaction` death explosion is silently dead.** `damage_reaction.gd:4` is
   `extends Node`, so `get_parent() as Node2D` at `explosion_effect.gd:40` yields `null` and
   `explode()` takes the early return at `:41-42`. No particle node is ever created.

   ```
   DamageReaction-shape: world children=1  ship children=1  dr children=1
   ```

   This affects **all six AI racers** — `bogomol:50`, `booster_gold:193`, `pacer:48`, `isac:49`,
   `fang:49`, `reacher:50` all carry `[node name="DamageReaction" type="Node" parent="."]` and
   route death through `damage_reaction.gd:42`. Confirmed on a real `pacer.tscn` killed with
   `Health.decrease(99999)`: the ship frees and its `Racers` container is left with **zero**
   children. Racers currently vanish with no blast.

2. **`RaceShip.apply_lethal_hazard()` blasts at the wrong place.** `race_ship.gd:98` parents the
   effect into `get_parent()` (the `Racers` `Node2D`), so `actor` is `Racers` and the particles
   are positioned at `Racers.global_position` — `(0, 0)`.

   ```
   race-shape: particles landed on ROOT at (0.0, 0.0)  (ship was at (700.0, 500.0))
   ```

   The `boom.global_position = global_position` on `:99` sets the *effect's* transform, which
   `explode()` never reads.

3. **Every blast inside a transformed container is offset by that container's transform.**
   `explosion_effect.gd:51-55` assigns `p.global_position` while `p` is still **out of the
   tree**. A parentless `Node2D` has no parent `CanvasItem`, so `global_position` is just
   `position` — the intended *world* coordinate is stored as a *local* one. Only at `:70` does
   `container.add_child(p)` run, at which point the effective world position becomes
   `container.global_transform * intended`. Found by the stage-4 reviewer and reproduced
   independently:

   ```
   entity global_position = (320.0, -4977.0)
   particles: position=(320.0, -4977.0) global_position=(320.0, -5754.0)
   ```

   Every site is correct today only because its container happens to be at identity. Two are
   not: `RaceWall` and `RaceAsteroid` live under `Track` at `position = Vector2(0, -777)`
   (`race_level_1.tscn:79-80`), so they explode 777 px up-track and drift further as the track
   scrolls; and a `StationTurret`'s FX go into `$Turrets` inside the moving hull, so a turret
   blast fires off roughly a screen away. This is the **most player-visible** of the three and
   the one a naive test suite cannot see, because fixtures are built at identity.

None of the three is caught by anything today: there is no test over `ExplosionEffect`, and no
gate step renders a scene.

## The fourth symptom — FX in a gameplay container

Where the parenting contract *is* honoured, the FX still land in a container that gameplay code
iterates:

- `level_director.gd:131` advances `ENEMIES_CLEARED` on `while container.get_child_count() > 0`,
  and `container` is `WaveManager.enemy_container` — the same node death particles are added to.
  A section therefore cannot advance until every death blast self-frees.
- `$Turrets.get_children()` on a `SpaceStation` returns `CPUParticles2D` mixed in with turrets
  from the first turret kill onward. Production code is *not* affected —
  `space_station.gd:137-143` filters with `child as StationTurret`, and the gunnery goes through
  `_station.turrets()` — but this cost a full gate cycle in a **test helper** that did a raw
  `get_children()`, cast a particle to `StationTurret`, got `null`, and died with
  `Invalid call. Nonexistent function 'is_alive' in base 'Nil'` — an *Unexpected Error* GUT reds
  with no failing assertion to point at (`tests/README.md:558-566`).
- In tests, particles outlive the test body and produce
  `GUT WARNING: Test script has 2 unfreed children` (`addons/gut/gut.gd:390`). Worked around in
  `test_station_laser_phase.gd` by interposing a container `Node2D`
  (`tests/README.md:551-557`).

Three separate workarounds for one component is the argument for fixing the component.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/components/explosion_effect.gd` | the component; 71 lines | the thing being changed |
| `global/components/damage_reaction.gd:24,42` | composes an `ExplosionEffect` onto racers | broken site #1 |
| `assault/scenes/race/core/race_ship.gd:97-100` | racer hazard elimination | broken site #2 |
| `assault/scenes/race/track/race_wall.gd:24`, `assault/scenes/hazards/asteroid_base.gd:35` | race-track hazards under `Track` | broken site #3 (offset blasts) |
| `assault/scenes/enemies/space_station/station_turret.gd:79-81` | turret death | offset blast + FX freed with the hull |
| `assault/scenes/enemies/space_station/station_death_sequence.gd:167-181` | boss blast chain | 15 lines of comment explaining the two-hop rule, already citing stale line numbers (`:28`/`:31`, really `:40`/`:43`) |
| `assault/scenes/systems/level_director/level_director.gd:121-133` | `ENEMIES_CLEARED` poll | counts FX as live enemies |
| `assault/scenes/levels/**/*.tscn` | `EnemyContainer` is a plain identity `Node2D` (`level_1.tscn:22`, `level_2.tscn:13`, `race_level_1.tscn:77`) | which is exactly why defect 3 has stayed invisible |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/components/hit_effect.gd:21-38` | sibling one-shot particle component — keeps its `CPUParticles2D` as its **own** child and only `restart()`s it, so it has no ownership problem and stays out of scope |
| `tests/integration/test_player_bullet_lifetime.gd` | the template for an **ownership invariant** test that enumerates its roster from the project class list rather than a hand-written one |
| `tests/integration/test_config_instance_isolation.gd` | template for a directory-sweep roster + a boundary case that fails on the rejected design |
| `addons/gut/test.gd:2405,2416` | `assert_push_warning_count()` / `assert_push_warning()` — so a "fails loudly" test can assert the warning, not just the absence of particles |
| `HitBox.matching_shape()` | precedent for "the component owns the tricky construction rule, not the caller" |

## Conventions that constrain this

- **Composition over inheritance** — the fix belongs in the component, not in a base class.
- **Every projectile has exactly one owner** (`CLAUDE.md`) — this is the same principle applied
  to particles, and the reason the task exists.
- **Signal arity & verbose-gated logging** — a new `push_warning` fires per *death*, not per
  frame, so it is exempt from the `OS.is_stdout_verbose()` rule. Note
  `station_death_sequence.gd:196` can call `explode()` up to `_blast_count` (~7) times per death,
  so a mis-parented sequence would warn ~7 times — still not per-frame.
- `EnemyContainer` in every level is an **identity-transform `Node2D`**, so re-homing FX between
  those containers is visually neutral. `Track` is **not**, which is defect 3.
- Design-unit coordinates are a spawn-time concern only; FX are positioned in world space.

## Open questions for research / plan

1. Should the default container change, or only become *correctly resolved*? Moving FX out of
   `enemy_container` changes `ENEMIES_CLEARED` timing (a section would advance up to ~1 s
   sooner). `test_level_1_sequence.gd` asserts the boss section "does not advance while the
   wreck is present" — need to confirm that assertion keys on the wreck, not on FX.
2. Explicit `container` argument, ancestor walk, or a designated FX-host group? An argument
   fixes nothing by default; a walk fixes every site with no caller changes; a group is the
   cleanest separation but needs scene wiring in every level.
3. Is the `as Node2D` early return worth keeping at all? It is currently a silent failure path —
   the exact thing that hid defect #1.
