# Review — contact HitBox drops the CollisionShape2D transform

VERDICT: CHANGES_REQUESTED

The core diagnosis, the fix, the alternatives analysis and the test plan are all sound, and every
measured number in `1-context.md` reproduces exactly. Three things need correcting before
implementation, two of which can silently damage the result if an unattended run hits them.
None require re-planning; they are edits to the plan text plus one added constraint on the test
harness.

---

## Verification of the plan's factual claims — all confirmed

Everything below was read from the files, not taken from the plan.

**The four duplicate sites and their line ranges are exact.**
- `/work/repo/assault/scenes/enemies/base_enemy.gd:49-60` — `func _add_contact_hitbox()` at 49,
  `add_child(hb)` at 60; `shape_node.shape = col.shape` at 58, no transform copy.
- `/work/repo/assault/scenes/enemies/drone_interceptor/drone_interceptor.gd:141-153` — exact.
- `/work/repo/assault/scenes/enemies/kamikaze_drone/kamikaze_drone.gd:53-65` — exact.
- `/work/repo/assault/scenes/allies/ally_fighter/ally_fighter.gd:72-84` — exact.
- `/work/repo/assault/scenes/enemies/bonus_drone/bonus_drone.gd:29-30` — `pass`, as described.

**"Four sites" is the whole population.** `grep` for `CollisionShape2D.new()` / `.shape =` across
all non-addon `.gd` returns exactly these four copy-from-a-source sites. The other three hits
(`assault/scenes/hazards/laser_ray/laser_ray.gd:162`,
`assault/scenes/player/states/reflect_state.gd:42-45`,
`assault/scenes/race/core/sensors.gd:29-32`) build fresh shapes from nothing and are correctly out
of scope. `HitBox.new()` likewise appears in exactly those four files.

**Every scale, radius and sprite dimension in the context table is correct.** Body
`CollisionShape2D` blocks, read directly:

| Entity | file:line | scale | radius |
|---|---|---|---|
| drone_interceptor | `drone_interceptor.tscn:62` | 3.0799994 | 10 (`CircleShape2D_dri` at :15 has no `radius` line → default 10) |
| gunship | `gunship.tscn:64` | 2.3077412 | 18 (`gunship.tscn:16`) |
| light_assault_ship | `light_assault_ship.tscn:78` | 2.199998 | 13 (`:30`) |
| interceptor | `interceptor.tscn:63` | 1.8000002 | 14 (`:16`) |
| ally_fighter | `ally_fighter.tscn:37` | 1.83783 | 8 (`:24`) |
| sniper_enemy | `sniper_enemy.tscn:63` | 1.4400002 | 14 (`:16`) |
| bomber / ram_ship / kamikaze_drone / bonus_drone / space_station | — | no `scale` line at all | 22 / 36 / 10 / 12 / `size = Vector2(240,240)` |

I dumped every body `CollisionShape2D` property block in `assault/scenes/enemies/*/*.tscn` and
`ally_fighter.tscn`: **none carries `position` or `rotation`**, so the plan's "the loss today is
purely scale, on exactly six entities" is right, and the expected-red list
(gunship, interceptor, light_assault_ship, drone_interceptor, sniper_enemy, ally_fighter) is
exactly the set of scaled bodies. The four-green-after-step-3 prediction is also right: the
base-helper subset of the six is gunship + interceptor + light_assault_ship + sniper_enemy.

Sprite sizes read from the PNG IHDR chunks: `heave_gunship.png` 92×84, `interceptor.png` 64×74,
`drone_2.png` 64×64 — matching the context table. The `Sprite2D` nodes carry no scale
(`gunship.tscn:58-61`), so 41.5 px against a 92×84 hull really is the visually correct radius and
18 px really is ~38 % of it.

**Player numbers check out.** `player_fighter.tscn:340-343` — `HurtBoxCollision`,
`position = Vector2(0, 1)`, `scale = Vector2(2.7, 2.7)`, shape `CircleShape2D_ctrog` with
`radius = 5.0` (`:286-287`) → 13.5 px, as claimed. `HurtBox` layer 128 / mask 1281 at `:335-336`.

**Nothing is being reinvented.** `/work/repo/global/components/` has no geometry helper of any
kind; `hitbox_component.gd` is 7 lines (`class_name HitBox extends Area2D`, `DamageType`, `damage`,
`damage_type`) and the only `static func`s anywhere in `global/` are
`upgrade_state.gd:43` and `ship_module_base.gd:11`. A static factory on `HitBox` is new surface,
not a duplicate.

**No `CLAUDE.md` convention is violated.** The sizes involved are scene data, not `.tres` data
(`ShipConfig` has no radius field), so config-driven stats are untouched — and
`tests/integration/test_enemy_contact_damage.gd` stays authoritative for `collision_damage`.
No design-space/`WORLD_SCALE` coordinates are involved. Putting shared construction on the shared
component rather than on `BaseEnemy` is the composition-over-inheritance call, and it is forced:
`ally_fighter.gd:1-2` is `class_name AllyFighter extends CharacterBody2D`.

**The test harness the plan wants to reuse exists as described.**
`tests/integration/test_enemy_contact_damage.gd:113-121` (`_spawn` into a throwaway container
`Node2D` via `add_child_autofree`), `:125-130` (`_contact_hitbox`, direct children only), and the
vacuity guard the plan cites at `:185-189` are all real and say what the plan says they say.

**The Godot docs quote is verbatim.** Fetched
`https://docs.godotengine.org/en/stable/tutorials/physics/troubleshooting_physics_issues.html`:
*"Godot does not currently support scaling of physics bodies or collision shapes. As a workaround,
change the collision shape's extents instead of changing its scale."* Present exactly.
(`shmup.fandom.com` returned HTTP 402 to my fetcher, so that one quote is unverified. The SLYNYRD
claim it backs is not load-bearing on its own.)

**I resolved research open question 2 empirically rather than by analogy — see finding 4 below.**

---

## Findings

### 1. (must fix) The balance rationale is factually wrong: allies are on layer 256's receiving end too

`3-plan.md:81-84` reason 3 concludes *"this change only affects **enemy-into-player**"*, and the
risk table at `3-plan.md:143` says the enemy contact `HitBox` stays *"layer 256, reachable only by
the player HurtBox (mask 1281)"*.

`/work/repo/assault/scenes/allies/ally_fighter/ally_fighter.tscn:41-42` is
`collision_layer = 128` / `collision_mask = 1281` — the **same** mask as the player's. Bit 256 is
set, so the ally fighter's `HurtBox` sees every enemy contact `HitBox`. Ally fighters are live
content, spawned from `/work/repo/assault/scenes/systems/wave_builder.gd:240` (`const ALLY`).
Consequences the plan does not state:

- All six enlarged enemy contact boxes also start killing **allied fighters** from further out.
- `drone_interceptor.gd:145-147` and `kamikaze_drone.gd:57-59` set `collision_mask = 128`, which is
  the ally's `HurtBox` layer as well as the player's — so those two now self-destruct on an ally
  from ~3.1×/1× further out, not just on the player.
- The plan's own site 4 grows the **ally's** contact hitbox 1.84× (`ally_fighter.gd:72-84`,
  layer 64). Enemy `HurtBox` masks 97 (`interceptor.tscn:68`, `sniper_enemy.tscn:71`,
  `drone_interceptor.tscn:67`) and 65 (`bomber`, `gunship`, `light_assault_ship`, `kamikaze_drone`,
  `bonus_drone`) both contain bit 64, so ally→enemy ram damage lands more often too.
  (`ram_ship.tscn:80` is mask 33 and immune; that is pre-existing.)

The fix itself is still right — the ally's contact box should match the ally's hull for the same
reason the enemy's should. What is wrong is the written justification for accepting the balance
change without compensation, and the "flag for a human to eyeball" row at `3-plan.md:145`, which
should name the ally cases too. **Rewrite reason 3 and the risk row to say enemy↔player *and*
enemy↔ally *and* ally→enemy.**

Two smaller corrections in the same area, both harmless to the conclusion: enemy `HurtBox` masks
are 97/65/**33**/**1121** (`ram_ship.tscn:80`, `space_station.tscn:76`,
`station_turret.tscn:19`), not just 97/65 — none contains 256, so "enemies still cannot ram each
other" holds. And the claim that the player body is stopped at hull contact holds for enemies
(root nodes have no `collision_layer` line → default layer 1, player `move_and_slide()` at
`player_fighter.gd:98` with default mask 1) but **not** for the space station, whose root is
`collision_layer = 0` / `collision_mask = 0` (`space_station.tscn:63-64`).

### 2. (must fix) The harness cannot be reused verbatim for the `ally_fighter` row

`3-plan.md:112-113` says the new test "reuses `test_enemy_contact_damage.gd`'s harness". That
harness is typed to enemies: `tests/integration/test_enemy_contact_damage.gd:113`
(`func _spawn(entry: Dictionary) -> BaseEnemy`), `:118-119`
(`scene.instantiate() as BaseEnemy` + `assert_not_null(enemy, "%s: root is not a BaseEnemy")`) and
`:125` (`func _contact_hitbox(enemy: BaseEnemy) -> HitBox`).

`AllyFighter` is not a `BaseEnemy` (`ally_fighter.gd:1-2`). Copied as-is, the ally row fails with
"root is not a `BaseEnemy`" — a failure that looks like the bug under test but is not. The danger
in an unattended run is that the cheapest way to make that stop is to drop `ally_fighter` from the
roster, which silently deletes one of the six red rows the change exists to fix.

**State explicitly in the build sequence that the copied `_spawn()` / `_contact_hitbox()` are typed
`Node2D`, not `BaseEnemy`, and that `ally_fighter` stays in the roster.**

### 3. (should fix) The build sequence has no docs step

`3-plan.md:96-107` ends at "run the full suite". Adding a public static factory to a shared
component changes documented shared API: `/work/repo/docs/architecture/modules/global.md:121`
describes `HitBox`'s surface (`damage`, `damage_type`) and `:125` describes the collision wiring
recipe — both are now incomplete. `CLAUDE.md` makes `updating-project-docs` mandatory after a
structural change. `STATUS.md` step 7 covers it at the pipeline level, so this is a nudge, not a
blocker: add it as step 7 of the build sequence so an unattended run does not stop at green tests.

### 4. (informational — resolves research open question 2, in the plan's favour)

`1-context.md`'s open question 2 asks whether Godot 4 honours a scaled `CollisionShape2D` under an
`Area2D`. `2-research.md` and `3-plan.md:142` answer it by analogy: the sibling `HurtBox` nodes are
scaled and "demonstrably register hits". That argument is weaker than it reads — hits registering
proves a hit registers *somewhere*, not that the scale reached the physics server. Given the
verbatim docs sentence says scaling is *not supported*, the whole fix would be a no-op if the docs
were literally true, and no step in the plan would catch that (the proposed test asserts node
transforms, not physics behaviour).

I settled it empirically against this machine's engine (Godot v4.6.3.stable, the same binary
`/agent/verify.sh` runs). Throwaway project outside the repo: an `Area2D` with a
`CircleShape2D(radius 10)` on a `CollisionShape2D` scaled `Vector2(3,3)`, probed by point areas at
x=20 and x=40.

```
RESULT overlapping_count=1
RESULT b_overlaps=true c_overlaps=false          # 20 px overlaps, 40 px does not -> effective radius 30
RESULT shape_owner_xform=[X: (3.0, 0.0), Y: (0.0, 3.0), O: (0.0, 0.0)]
```

The scale reaches the physics server and the effective radius is 30, not 10. The design works, and
no engine warning was emitted (so the `test_project_load_integrity.gd` risk row at `3-plan.md:144`
is also fine). Worth folding this into `2-research.md` as the actual answer, replacing the
argument-by-analogy.

### 5. (nits, no action strictly required)

- `3-plan.md:79` cites `global/components/hurtbox_component.gd:17` for "fires on `area_entered`
  only". Line 17 is a `return` inside the `accepted_damage_types` filter; the connection is
  `hurtbox_component.gd:10`. The claim is correct, the citation is off by seven lines.
- `1-context.md`'s site table calls `ally_fighter`'s damage "hardcoded 25". It is hardcoded at
  `ally_fighter.gd:79` and then overwritten by `config.collision_damage` at
  `ally_fighter.gd:40-46`. Not load-bearing for this change.

---

## Things I checked that are *not* problems

- **Test plan can fail.** It reds on six named entities today, for a reason I independently
  measured. The vacuity guard mirrors a real precedent (`test_enemy_contact_damage.gd:185-189`) and
  is genuinely needed: four of the ten roster entries author at scale 1, so the sweep would pass on
  them unfixed. The non-uniform-scale guard protects the one case the design cannot represent.
  Skipping a unit test for `matching_shape()` is the right call — it would restate the
  implementation.
- **No simpler unexamined alternative.** All three obvious routes are examined at
  `3-plan.md:46-66`, including the minimal four-line fix, and the rejections are honest rather
  than rhetorical. (`duplicate()`-ing the source node instead of copying `transform` is a fourth
  route, but it is not *simpler* and would drag the source's `debug_color`/`disabled` along, so
  its absence is not a gap.)
- **Research has real tradeoffs** and its strongest source (the Godot docs) argues *against* the
  chosen design, which the plan states rather than hides.
- **Scope is one session**: one new static function, four call-site conversions of ~5 lines each,
  one new test file, one docs pass. Small.
- **Sharing the `Shape2D` resource rather than duplicating it** is unchanged from today's
  behaviour and correct — nothing mutates these shapes at runtime.

## What "changes requested" means here

Findings 1, 2 and 3 are edits to `3-plan.md` (and optionally `2-research.md` for finding 4). The
design, the file layout, the build sequence order and the test plan all stand as written. Once the
ally-side balance consequence is stated correctly and the harness typing is pinned in the build
sequence, this is ready to implement.

---

# Review round 2

VERDICT: APPROVED

All three round-1 findings are addressed, and the two informational items (4 and 5) are folded in.
I re-verified the revised claims against the files rather than against round 1's text, and also
swept for layer-256 consumers that neither round-1 nor the plan had looked at (`.gd`-set masks,
not just `.tscn`). Two small numeric imprecisions survive in the rewritten impact section; both
overstate the blast radius rather than understate it, neither touches the design, the build
sequence or the tests, so they are corrections to make while writing the report, not a fourth
round.

## Round-1 findings — status

**Finding 1 (must fix) — resolved, and the new table is correct.** `3-plan.md:88-119` replaces the
"only affects enemy-into-player" claim with an explicit four-row table and says outright that the
first draft was wrong. Every number in it reproduces:
- `/work/repo/assault/scenes/allies/ally_fighter/ally_fighter.tscn:41-42` — `collision_layer = 128`
  / `collision_mask = 1281`, identical to the player's `/work/repo/assault/scenes/player/player_fighter.tscn:335-336`.
  Bit 256 set in both, so the ally `HurtBox` does see enemy contact hitboxes.
- Ally is live content: `/work/repo/assault/scenes/systems/wave_builder.gd:240` (`const ALLY`).
- `drone_interceptor.gd:147` and `kamikaze_drone.gd:59` are `collision_mask = 128`, which is the
  ally `HurtBox` layer as well as the player's — confirmed.
- Ally contact box is layer 64 (`ally_fighter.gd:78`); enemy `HurtBox` masks 97
  (`interceptor.tscn:68`, `sniper_enemy.tscn:71`, `drone_interceptor.tscn:67`) and 65
  (`bomber.tscn:68`, `gunship.tscn:69`, `light_assault_ship.tscn:83`, `kamikaze_drone.tscn:36`,
  `bonus_drone.tscn:37`) both contain bit 64; `ram_ship.tscn:80` is 33 and does not.
- "No enemy mask contains bit 256" (`3-plan.md:103-104`) holds: 97, 65, 33 and 1121
  (`space_station.tscn:76`, `station_turret.tscn:19`) — none has bit 256.
- The space-station carve-out at `3-plan.md:111-116` is right: `space_station.tscn:63-64` is
  `collision_layer = 0` / `collision_mask = 0`, while enemy roots carry no `collision_layer` line
  (e.g. `gunship.tscn:55`) and the player body masks the default 1 (`player_fighter.gd:98`).

**Finding 2 (must fix) — resolved.** `3-plan.md:144-156` is a dedicated section pinning the
harness typing. `/work/repo/tests/integration/test_enemy_contact_damage.gd:113` is
`func _spawn(entry: Dictionary) -> BaseEnemy`, `:118-119` casts and asserts, `:125` takes a
`BaseEnemy`; `/work/repo/assault/scenes/allies/ally_fighter/ally_fighter.gd:1-2` is
`class_name AllyFighter extends CharacterBody2D`. The plan now names `Node2D` as the required
type and says `ally_fighter` must stay in the roster and why. That closes the drop-the-row failure
mode.

**Finding 3 (should fix) — resolved.** `3-plan.md:139-142` adds step 7 (`updating-project-docs`)
with the right targets: `/work/repo/docs/architecture/modules/global.md:121` is the `HitBox`
surface paragraph (`damage`, `damage_type`) and `:125` is the collision-wiring recipe. Both line
citations are exact.

**Findings 4 and 5 — folded in.** `2-research.md:46-88` now answers open question 2 by measurement
instead of by analogy and records the `shmup.fandom.com` non-verification. `3-plan.md:78-79` now
cites `hurtbox_component.gd:10` for the connection and `:12-18` for the handler — correct against
the 18-line file.

## New findings

### 6. (correct before writing the report; not a re-review) "six enemy boxes" is five

`3-plan.md:98` ("six enemy boxes grow"), `:99` ("same six boxes") and the risk row at `:197`
("The same six enlarged enemy boxes reach them too") count the ally's own box among the enemy
ones. Six *entities* grow (`3-plan.md:70` is right), but only **five** are enemies — gunship,
interceptor, light_assault_ship, drone_interceptor, sniper_enemy — because the sixth is
`ally_fighter` itself, and its box is layer 64 (`ally_fighter.gd:78`), which no ally `HurtBox`
mask sees (`ally_fighter.tscn:42` = 1281, no bit 64). The build sequence's expected-red list at
`3-plan.md:132` is the correct six-entity set, so nothing downstream is affected.

### 7. (correct before writing the report; not a re-review) `kamikaze_drone`'s box does not grow

`3-plan.md:100` says the `drone_interceptor` / `kamikaze_drone` self-destruct "both now trigger on
an ally from further out", and the risk row at `:197` says both "now suicide into an ally from
further out". `kamikaze_drone` authors its body `CollisionShape2D` at
`/work/repo/assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn:31-32` — `shape` only, **no
`scale` line** — so its contact box is unchanged by this fix (it is on the plan's own scale-1 list
at `3-plan.md:175-176` and correctly absent from the expected-red list at `:132`). Only
`drone_interceptor` (3.08×) changes. Round 1's own text said "~3.1×/1×"; the revision dropped the
1×. The effect is to put a non-change on the human-eyeball list, which is harmless but should not
ship in the report.

### 8. (informational — I checked it, it is not a problem) Layer 256 has three more subscribers, all set in code

The round-1 and round-2 impact analyses both enumerated masks from `.tscn` only. Grepping
`collision_mask` across non-addon `.gd` finds three more masks containing bit 256, i.e. three more
things that can see an enlarged enemy contact `HitBox`:

- `/work/repo/assault/scenes/player/states/reflect_state.gd:41` — the reflect window's `Area2D` is
  `collision_mask = 256`. Its handler (`:64-72`) walks parents looking for an `EnemyBullet` and
  returns silently otherwise, so an enemy contact `HitBox` entering it is a no-op. Enlarging the
  box only makes that no-op fire slightly earlier. **No behaviour change.**
- `/work/repo/assault/scenes/race/core/race_ship.gd:46` — `hurt_box.collision_mask = 64 | 256 | 1024`.
- `/work/repo/assault/scenes/race/core/sensors.gd:10` — `@export var bullet_mask: int = 64 | 256`
  for the racer threat area.
  Both are race sub-mode; grepping `assault/scenes/race/` for `enemies/` / `wave_builder` returns
  nothing, so no assault enemy with a contact `HitBox` ever coexists with a `RaceShip`. **Out of
  reach in practice.**
- `/work/repo/open_space/scenes/entities/player/player_ship.tscn:257` is also mask 1281, but it is
  a different module with no assault enemies in it.

So the plan's conclusion (player + ally are the affected receivers) survives the wider sweep. I am
recording it so the next person does not have to redo the grep.

## Standard bar — checked independently

- **No reinvention.** `/work/repo/global/components/hitbox_component.gd` is 7 lines with no
  geometry logic; nothing in `global/components/` builds a shape from another node. A static
  factory there is new surface.
- **No convention contradicted.** Sizes are scene data, not `.tres` data; `collision_damage` is
  untouched, so `tests/integration/test_enemy_contact_damage.gd` stays authoritative. `HitBox`
  rather than `BaseEnemy` is forced by `ally_fighter.gd:1-2` and is the composition-conforming
  home. The docs step is now present, satisfying `CLAUDE.md`'s `updating-project-docs` rule.
- **The test can fail, and has real edge cases.** Six named entities red today; the vacuity guard
  mirrors the real precedent at `test_enemy_contact_damage.gd:185-189` and is needed because four
  of the ten hitbox-carrying roster entries author at scale 1; the non-uniform guard covers the one
  case the transform-copy design genuinely cannot represent. Skipping a unit test for
  `matching_shape()` is the right call.
- **Harness reuse is proven safe.** The existing `ROSTER` (`test_enemy_contact_damage.gd:55-101`)
  already spawns all ten enemies including `space_station` through `_spawn`, so adding an
  eleventh `Node2D`-typed row is not new territory.
- **Nothing downstream reads contact-hitbox geometry.** Every `is HitBox` / `as HitBox` consumer in
  `assault/` and `global/` touches only `damage` or `collision_layer`
  (`bomber.gd:24-25`, `gunship.gd:51-52`, `light_assault_ship.gd:22-23`, `ram_ship.gd:21-23`,
  `space_station.gd:121-122` and `:232-233`, `ally_fighter.gd:45-46`). The ally's config-overwrite
  loop runs at `ally_fighter.gd:43-46`, after `_add_contact_hitbox()` at `:19`, so ordering still
  holds after the conversion.
- **Simpler alternatives examined** (`3-plan.md:46-66`), research carries real tradeoffs and its
  strongest source argues against the chosen design, and scope is one session: one static function,
  four ~5-line call-site conversions, one test file, one docs pass.

## What "approved" means here

Implement as written. While doing so, fix the two counts in findings 6 and 7 in `3-plan.md` (and do
not carry them into `5-progress.md` or the final report): five enemy boxes grow, not six, and
`kamikaze_drone`'s box does not grow at all. The human-eyeball list is therefore
`drone_interceptor` self-destruct range, ally fragility against the five enlarged enemy boxes, and
ally ram frequency.
