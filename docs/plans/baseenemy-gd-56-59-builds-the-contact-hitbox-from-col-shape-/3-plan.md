# Contact HitBox built from a shape resource, discarding the transform that sizes it

## Problem

When a gunship flies into you, its visible hull sweeps across your ship and nothing happens. Only
when its **centre** gets within about 32 px does the ram finally register. The heaviest ship in the
roster passes through the player like a ghost for most of its own width.

This is not tuning. `gunship.tscn` sizes the ship by scaling its body `CollisionShape2D` by
2.3077 over an 18 px circle — a 41.5 px hull, which matches the 92×84 sprite. The contact `HitBox`
is built in code from `col.shape` alone, and a `Shape2D` resource carries the radius but not the
node scale that multiplies it, so the ram box is built at 18 px: **38 % of the hull the player can
see**. Six entities are affected; the full measurements are in `1-context.md`.

Contact damage is meant to be the punishment for letting a ship reach you. Today it is a punishment
for letting a ship reach the middle of you.

## Design

### The fix

Copy the source node's `transform` (position, rotation, scale) onto the generated
`CollisionShape2D`, so the contact box is the same hull the scene author drew — the same
construction the sibling `HurtBox` collision node already uses in every one of these scenes.

### Where it lives

The five-line build is copy-pasted into **four** places (`1-context.md`), which is precisely why
one bug appears four times. Replace all four with a static factory on the shared component:

```gdscript
# global/components/hitbox_component.gd
## Builds a HitBox whose geometry mirrors `source` exactly: the same Shape2D resource AND the
## node transform that sizes and places it. Copying only `shape` silently drops the scale, which
## is how every contact hitbox in the game ended up smaller than the hull it belongs to.
static func matching_shape(source: CollisionShape2D, layer: int, mask: int, dmg: int) -> HitBox:
```

`HitBox` is the right home: `ally_fighter.gd` extends `CharacterBody2D`, not `BaseEnemy`, so a
`BaseEnemy` method cannot serve all four call sites, and `global/components/` is where shared
behaviour belongs under the composition convention.

The `Shape2D` resource stays **shared, not duplicated** — the hitbox and the body describe the same
hull, and nothing mutates it at runtime. This also keeps per-spawn allocations unchanged.

### Alternatives rejected

- **Add `shape_node.transform = col.transform` at each of the four sites.** Smallest possible
  diff and genuinely tempting. Rejected because it leaves the copy-paste that produced a
  four-way bug fully intact, and the fifth site written next month gets it wrong again. The
  factory makes the correct construction the only easy one.
- **Bake the scale into a duplicated `Shape2D` (`radius *= scale`), which is what the Godot docs
  recommend** — *"change the collision shape's extents instead of changing its scale"*
  ([troubleshooting physics issues](https://docs.godotengine.org/en/stable/tutorials/physics/troubleshooting_physics_issues.html)).
  Rejected for three reasons: it needs a branch per `Shape2D` subclass and silently does nothing
  for a type nobody thought of; it cannot represent a non-uniform scale on a circle at all; and it
  would leave the enemy's **hurtbox scaled** (as authored in every scene, including the player's
  own `player_fighter.tscn:342`) while its **hitbox baked extents** — two constructions for one
  hull, easy to drift. Every scale in play is uniform, where a transformed circle or rect is
  exactly representable. Mitigated by a test guard against non-uniform scale (below).
- **Author the contact `HitBox` in each scene, as `big_asteroid.tscn`/`small_asteroid.tscn` do
  (`asteroid_base.gd:41-42` only sets `damage`/`damage_type` on a `$ContactHitBox` that already
  exists in the scene).** This is the cleanest end state and the pattern already proven in the
  repo. Rejected as out of scope for a bug fix: nine scene edits with UID risk, and it would have
  to relocate the per-subclass layer/mask logic that `drone_interceptor.gd:147` and
  `kamikaze_drone.gd:59` depend on. Worth a follow-up task, not this one.

### The balance decision, stated explicitly

Six entities' contact boxes grow, worst case 3.08× (`drone_interceptor`). **No compensating nerf.**
Three reasons:

1. The genre convention is a small player box against generous enemy bounds
   ([SLYNYRD](https://www.slynyrd.com/blog/2026/7/26/pixelblog-63-horizontal-shmup),
   [Shmup Wiki](https://shmup.fandom.com/wiki/Hitbox)). This project already has the small player
   box — 13.5 px (`player_fighter.tscn:340-343`). Shrinking the enemy side too, as the bug does,
   makes the pairing small-vs-small.
2. `HurtBox._on_area_entered` fires on `area_entered` only
   (`global/components/hurtbox_component.gd:10` connects it; `:12-18` is the handler) — one-shot
   per entry, no per-frame tick. A larger box changes **where** a ram registers, not damage per
   second.
3. Contact damage stays a *body-to-body* affair; no new category of collision is created. What
   changes is only the radius at which the existing ones fire. Player-into-enemy in particular is
   unaffected either way: the player's body (mask 1) collides with enemy bodies (layer 1) and is
   physically stopped at hull contact, while enemies (mask 1) do not see the player's layer 4 and
   pass through freely.

#### Exactly who is affected — corrected after review

The first draft of this section claimed the change "only affects enemy-into-player", on the
grounds that layer 256 is reachable only by the player's `HurtBox` (mask 1281). **That is wrong.**
`assault/scenes/allies/ally_fighter/ally_fighter.tscn:41-42` is `collision_layer = 128` /
`collision_mask = 1281` — the *same* mask as the player's — so bit 256 is set there too, and ally
fighters are live content spawned via `wave_builder.gd:240`. The full set of affected interactions:

| Interaction | Why it changes | Direction |
|---|---|---|
| enemy contact → **player** `HurtBox` (layer 128, mask 1281) | six enemy boxes grow | rams register from further out |
| enemy contact → **ally fighter** `HurtBox` (layer 128, mask 1281) | same six boxes | allies die to rams from further out |
| `drone_interceptor` / `kamikaze_drone` self-destruct (`mask = 128`) | 128 is the player's *and* the ally's `HurtBox` layer | both now trigger on an ally from further out too — 3.08× for the interceptor |
| **ally** contact (layer 64) → enemy `HurtBox` | site 4 grows the ally's own box 1.84× | ally→enemy ram damage lands more often. Enemy masks 97 (`interceptor`, `sniper_enemy`, `drone_interceptor`) and 65 (`bomber`, `gunship`, `light_assault_ship`, `kamikaze_drone`, `bonus_drone`) both contain bit 64. `ram_ship.tscn:80` is mask 33 and stays immune — pre-existing, not changed here |

Enemy-into-enemy remains impossible: enemy `HurtBox` masks are 97, 65, 33 (`ram_ship.tscn:80`),
and 1121 (`space_station.tscn:76`, `station_turret.tscn:19`) — **none contains bit 256.**

The three reasons above still hold for every row of that table: the ally is a small-box
combatant facing the same generous enemy bounds, and the ally's own hull is what its contact box
is supposed to describe. Accepting the change uncompensated is still the call — but it is a
four-way balance change, not a one-way one, and the report must say so.

One further correction while in this area: "the player's body is stopped at hull contact" holds
for every enemy (root nodes carry no `collision_layer` line, so they default to layer 1, and
`player_fighter.gd:98` calls `move_and_slide()` with the default mask 1) but **not** for the
space station, whose root is `collision_layer = 0` / `collision_mask = 0`
(`space_station.tscn:63-64`). The station is unaffected by this change regardless — it authors at
`scale = 1`.

`.tres` `collision_damage` values are untouched — this is a geometry fix, and the damage numbers
were settled by `test_enemy_contact_damage.gd`.

### Out of scope, recorded as follow-ups

- Every code-built contact `HitBox` leaves `damage_type` at the `LASER` default;
  `asteroid_base.gd:42` is the only one that sets `CONTACT`. Harmless today (the player `HurtBox`
  has no `accepted_damage_types` filter), but a latent trap. → new task.
- Migrating contact hitboxes into the scenes, per rejected alternative 3. → new task.

## Build sequence

1. **Write the failing tests first** (`tests/integration/test_contact_hitbox_geometry.gd`), run
   them, and record the actual failure list. Expected red: `gunship`, `interceptor`,
   `light_assault_ship`, `drone_interceptor`, `sniper_enemy`, `ally_fighter`.
2. Add `HitBox.matching_shape()` to `global/components/hitbox_component.gd`.
3. Convert `base_enemy.gd:49-60` to use it. Re-run — four of the six should go green.
4. Convert `drone_interceptor.gd:141-153` and `kamikaze_drone.gd:53-65`. Both keep their
   `hb.area_entered.connect(_on_contact_hit)` after construction.
5. Convert `ally_fighter.gd:72-84`.
6. Run the full suite; confirm `test_enemy_contact_damage.gd` is still green (damage untouched).
7. Run `updating-project-docs`. `docs/architecture/modules/global.md:121` documents `HitBox`'s
   surface (`damage`, `damage_type`) and `:125` the collision-wiring recipe; both are incomplete
   once `HitBox` gains a public static factory. Adding shared API to a shared component is a
   structural change, so `CLAUDE.md` makes this mandatory — the build is not done at green tests.

### A harness constraint that must not be discovered mid-build

Step 1 copies the roster harness out of `test_enemy_contact_damage.gd`. That harness is **typed to
enemies**: `_spawn()` is declared `-> BaseEnemy` (`:113`), it does
`scene.instantiate() as BaseEnemy` and asserts the cast (`:118-119`), and `_contact_hitbox()`
takes a `BaseEnemy` (`:125`). `AllyFighter` is `class_name AllyFighter extends CharacterBody2D`
(`ally_fighter.gd:1-2`) and is **not** a `BaseEnemy`.

So in the new file, `_spawn()` and `_contact_hitbox()` must be typed **`Node2D`**, not `BaseEnemy`.
Copied verbatim, the `ally_fighter` row fails with "root is not a BaseEnemy" — a failure that
looks exactly like the bug under test but is not one. **`ally_fighter` stays in the roster**;
dropping it to clear that error would silently delete one of the six rows this change exists to
fix, and it is the only site-4 coverage in the suite.

## Test plan

New file `tests/integration/test_contact_hitbox_geometry.gd` — an **invariant** test, not
characterization: the contact box describing a different hull than the body is a defect, not a
quirk to pin. It reuses `test_enemy_contact_damage.gd`'s harness (throwaway container `Node2D`
parent, add to tree so `_ready()` runs, direct-children-only `HitBox` search) — **retyped to
`Node2D`**, for the reason spelled out under "A harness constraint" in the build sequence.

| Test | Asserts | Fails today on |
|---|---|---|
| `test_every_contact_hitbox_matches_its_body_shape` | For each entity: the contact `HitBox` has exactly one `CollisionShape2D` child, its `shape` is the same resource as the body's, and its `transform` equals the body's `transform`. | gunship, interceptor, light_assault_ship, drone_interceptor, sniper_enemy, ally_fighter |
| `test_the_roster_contains_a_scaled_body_or_this_file_is_vacuous` | At least one roster entry has a body `CollisionShape2D` with a non-identity `transform`. | — (guard) |
| `test_no_body_collision_shape_uses_non_uniform_scale` | Every roster body shape has `scale.x == scale.y`. | — (guard) |
| `test_bonus_drone_still_has_no_contact_hitbox` | The deliberate exception survives the refactor. | — |

**Boundary cases.** Two are deliberate and both are real, not filler:

- The **vacuity guard**. Four of the ten entities (`bomber`, `ram_ship`, `kamikaze_drone`,
  `space_station`) author at `scale = 1`, so the main assertion passes on them even unfixed. If
  someone later re-authors the scaled scenes at true size, the sweep would silently become a test
  of nothing. This mirrors the `assert_ne` vacuity guard already in
  `test_enemy_contact_damage.gd:185-189`.
- The **non-uniform scale guard**. This is the case the Godot docs' warning actually bites on: a
  `Vector2(2, 3)` on a circle cannot be represented by the physics server, and the transform-copy
  design would silently produce a wrong hull. No scene uses one today; the guard is what makes
  that a gate failure rather than a mystery.

A unit test for `HitBox.matching_shape()` is deliberately **not** added: the integration sweep
exercises it against every real caller, and a unit test asserting `transform == transform` on a
hand-built node would restate the implementation rather than test it.

## Risks

| Risk | Check |
|---|---|
| Scaled `CollisionShape2D` under an `Area2D` is ignored by the physics server, making the whole fix a silent no-op — which is what the Godot docs' "scaling of collision shapes is not supported" would mean taken literally. | **Settled empirically, not by analogy** — see `2-research.md` → "Open question 2, answered by measurement". On this machine's Godot 4.6.3, the same binary `/agent/verify.sh` runs, a `CircleShape2D(radius 10)` under a `scale = (3,3)` `CollisionShape2D` on an `Area2D` overlaps a probe at 20 px and not at 40 px: effective radius 30, no engine warning. Plus the non-uniform guard for the case that genuinely cannot be represented. |
| Enlarged boxes overlap something they should not. | Layers unchanged: enemy contact `HitBox` stays layer 256. Reachable by the player `HurtBox` **and the ally fighter's** — both mask 1281, see "Exactly who is affected". Enemy `HurtBox` masks 97/65/33/1121 contain no bit 256, so enemies still cannot ram each other. |
| `test_project_load_integrity.gd` trips on a new engine warning from setting scale in code. | It runs in the gate; the existing scenes already carry scaled collision shapes and pass. |
| `drone_interceptor` now self-destructs on contact from ~3× further out, which is a real feel change. | Intended — it is a kamikaze. Flagged in the report for a human to eyeball; headless tests cannot judge feel. |
| **Ally fighters get noticeably more fragile.** The same six enlarged enemy boxes reach them too (`ally_fighter.tscn:41-42`, mask 1281), and `drone_interceptor`/`kamikaze_drone` (`mask = 128`) now suicide into an ally from further out. | No test can judge whether allies now die too fast — survival time is a feel question. Named explicitly in the report as the second thing a human must eyeball. |
| **Ally rams land more often.** Site 4 grows the ally's own contact box 1.84×, and enemy `HurtBox` masks 97/65 both contain bit 64. | Correct in the same sense the enemy half is — the box now describes the ally's real hull — but it is an unrequested buff to allied damage output. Third item on the eyeball list. |

## Out of scope

Retuning any `collision_damage`; the `damage_type` default; moving hitboxes into scenes; the
asteroid family (already correct); anything in `infiltration/` or `open_space/`.
