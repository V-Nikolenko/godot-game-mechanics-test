# tests/

GUT (Godot Unit Test) suite. Run it exactly the way the gate does:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

`bash /agent/verify.sh` runs this as its third step, after the headless import and the headless
project boot.

## Layout

| Path | Contents |
|---|---|
| `unit/` | One file per autoload or `global/components/` component. No scene loading. |
| `integration/` | Several systems wired together (the player damage chain), plus project-wide integrity checks over the resource files themselves. |
| `helpers/` | Shared fixtures. **Never** named `test_*`, or GUT tries to collect them as tests. |

## The exceptions: the integrity tests, the space-station tests, the module unlock gate, and the enemy contact-damage invariant

`integration/test_resource_uid_integrity.gd` is **not** characterization. It asserts invariants
that must hold, so a failure there is a regression to fix, not a quirk to document. It checks six:

| Check | What it catches |
|---|---|
| a reference's UID equals the UID its target declares | a UID left behind after its target was reassigned one |
| a reference's UID is declared by **some** file in the tree | a wholly invented UID whose target declares none of its own, which the pairwise check above skips |
| no two files declare the same UID | a `.tscn` or `.gd.uid` copied by hand; nothing on disk breaks the tie, so the reference loads whichever file was scanned last |
| the UID-only references in `project.godot` / `export_presets.cfg` resolve | `run/main_scene="uid://…"` has **no** `res://` beside it to fall back to — stale, the game does not boot |
| every UID we write is **canonical** — it survives `id_to_text(text_to_id(u))` | a hand-typed UID that is an *alias*: `uid://` is base-34 text for a 64-bit int, so `z`/`9` are outside the digit alphabet and text past ~13 chars wraps. `uid://braceasteroid01` really meant `uid://ctmejjlwnwajg` |
| no two files **decode** to the same UID | the collision the row above it cannot see, because that one compares text and this one compares the integer the engine actually matches on |

The last two exist because the first four all compare UID *strings*, and the string is not the
UID — the 64-bit integer it decodes to is. Two different spellings can be one UID, at which point
one resource loads in place of another and every text-level check stays green. `text_to_id()` and
`id_to_text()` are pure encoding functions and touch no cache, so using them does not violate the
read-from-disk rule below.

It reads declared UIDs **from disk** (the `.tscn`/`.tres` header line, the sibling `.gd.uid`, the
sibling `.import`) and never asks `ResourceUID` / `ResourceLoader`. Those consult
`.godot/uid_cache.bin`, which is gitignored *and* keeps stale UIDs registered as working aliases
once a warm project has loaded them — so the engine will happily report a broken reference as fine
on your machine and break on a fresh clone. Five of the eight mismatches this test first caught
behaved exactly that way: `ResourceLoader.get_resource_uid()` and `ResourceUID.has_id()` called
them valid, `--import` warned about nothing, and deleting `.godot/` produced
`ext_resource, invalid UID` immediately. If you extend it, keep it reading files.

**`bash /agent/verify.sh` always runs against a warm `.godot/`**, so its import and boot steps
cannot be trusted to surface any of this on their own — that is what these disk-only checks are
for. The declaration index they are built on walks the whole tree, `addons/` included, because our
scenes legitimately reference vendored resources by UID; only *reference scanning* skips
`addons/`.

Its last two tests are a different shape from the rest: **canaries against a mass strip**, not
pairwise checks. Every other test in the file `continue`s past a missing UID — a reference without
one falls back to its path, a target that declares none has nothing to disagree with — so deleting
*every* UID in the project passes all of them while destroying exactly what they protect. The
canaries assert that at least 250 of the 485 `[ext_resource]` references, and at least 75 of the
130 `.tscn`/`.tres` files, still carry a `uid://`. Today's real numbers are 332 and 98; the floors
are slack because plenty of hand-authored references legitimately have no UID. Raise them if they
ever look tight, and never lower one to make a red run green.

### Never run the Godot MCP `update_project_uids` tool

It does not do what its name says, in either of its two failure modes.

**As the MCP calls it, it is a silent no-op.** `handleUpdateProjectUids` passes the *absolute*
project path, `executeOperation` snake-cases it to `project_path`, and `godot_operations.gd`'s
`resave_resources` then does `project_path = "res://" + project_path` on anything not already
starting with `res://`. So it searches `res:///work/repo/`, finds nothing, and reports success:

```
Using project path: res:///work/repo/
Found 0 scenes
Found 0 scripts/shaders
Resave operation complete
```

Verified by md5summing every `.tscn`/`.tres` in a scratch clone before and after a run: **zero
files changed.** The bug is in the MCP server's own `godot_operations.gd`, not in this repo, so it
cannot be fixed here.

**Invoked "correctly" — with `project_path` set to `res://` — it is actively destructive.** It
resaves every scene through `load()` + `ResourceSaver.save()`, and a headless resave writes back a
scene that has lost:

- **every UID.** `[gd_scene load_steps=18 format=3 uid="uid://82pgd5bowmxe"]` comes back as
  `[gd_scene format=3]`, and every `[ext_resource … uid="uid://…" path="res://…"]` loses its
  `uid=`. A tool named *update project UIDs* deletes them.
- **every comment.** The `.tscn` files in this project carry load-bearing prose — why `BulletPool`
  must be a direct child of `SpaceStation`, why `node_paths=` is required — and a resave drops all
  of it with no diff to review beforehand.

On a scratch clone it rewrote 111 of 155 files that way, and it also could not compile scripts that
reference autoloads (`--script` mode registers no autoloads), so some scenes were mangled and
others skipped.

**Use `test_resource_uid_integrity.gd` instead.** It covers strictly more than the tool ever
claimed to — `.tres` resources and `.gd.uid` sidecars as well as scenes — it reports rather than
rewrites, and since the mass-strip canaries above it now fails on precisely the damage the `res://`
form would do.

**To mint a UID for a genuinely new file, never hand-type one and never copy a sibling's.** A
copied UID is a duplicate declaration, and a typed one is usually an alias for a UID some other
resource owns — both are silent, and both are why the last two checks in the table exist. Either
leave the reference UID-less (legal; Godot falls back to the path), or mint a real one headlessly:

```bash
cat > /tmp/mint_uid.gd <<'EOF'
extends SceneTree
func _init(): print(ResourceUID.id_to_text(ResourceUID.create_id())); quit()
EOF
godot --headless --path . -s /tmp/mint_uid.gd    # -> uid://bpc4ejmad3jcs
```

`-s` needs a real file — `/dev/stdin` fails with `Resource file not found`. `create_id()` is the
same call the editor makes, so the result is canonical and unique by construction.

`integration/test_suite_integrity.gd` is the other invariant test, and it polices this directory
rather than the game. **GUT fails open on a test script it cannot use:** `test_collector.gd:131`
drops it with nothing but a `[GUT WARNING]: Ignoring script … because it does not extend GutTest`
line, the summary reports a smaller `Scripts` count, and GUT still prints
`---- All tests passed! ----` and **exits 0**. The gate only reads the exit code and greps for a
failing-test count, so neither signal fires: a test file broken by a rename or a deleted symbol
used to vanish from the suite while the gate stayed green. That is what happened to
`test_space_station.gd` while it was being written — the red was read off stderr, not off GUT's
verdict.

The check therefore lives inside the suite, where every runner sees it rather than only the gate
script. It walks `res://tests` for `test_*.gd` and asserts each one compiles and reaches
`res://addons/gut/test.gd` through its base-script chain, so a script GUT would drop now fails a
real test and the exit code goes red. Two things to know before touching it:

- **A script with a parse error still `load()`s to a non-null `GDScript`.** The giveaways are
  `can_instantiate() == false`, an empty `get_base_script()` chain and an empty
  `get_instance_base_type()`. A null check would catch nothing.
- **Its walk mirrors GUT's own collection rules** — `test_` prefix, `.gd` suffix, per
  `gut_config.gd:45`, since the gate passes no `-gprefix`. If that ever changes, change both or
  the check quietly stops covering files.

`integration/test_module_unlock_sources.gd` is the third invariant test, and it polices game
content rather than the suite. It loads `sector_hub.tscn`, walks it for
`ShipModuleUnlockerPickup` nodes, and asserts every non-`&""` id in
`ShipModuleState.SLOT_MODULES` is granted by one of them. Since `equip()` gained its unlock gate,
a module with no unlocker is a row the player can see and can never install — so adding a module
to the catalogue without a source is a regression, and this is what says so. It also pins that no
unlocker grants a module belonging to a different slot: `ShipModuleUnlockerPickup.Module` is one
flat enum across all four slots, so a mismatched pair is expressible in the inspector and would
otherwise only `push_warning` at collect time. The hub is instantiated but never added to the
tree — `_ready()` is what spawns drones and builds the HUD, and walking the node list needs none
of it.

`integration/test_gut_local_patches.gd` is the fourth invariant test, and it polices the test
runner itself. GUT 9.7.1 does not load under Godot 4.6.3 without two hand-applied changes —
`godot_singletons.gd` drops the `AccessibilityServer` entry (the class does not exist in this
build, so the identifier fails to resolve) and `stub_params.gd` types `return_val` as an explicit
`Variant` (otherwise Godot infers `StringName` from `GutConstants.NOT_SET` and the getter's
`return null` branch will not parse). Both are written up in `addons/gut/LOCAL_PATCHES.md`, and
**re-vendoring GUT deletes them along with the doc.**

That failure is silent in exactly the way `test_suite_integrity.gd` describes: the parse errors go
to stderr, `gut_cmdln.gd` still runs the suite and exits 0, and the doubler is simply gone until
some later test reaches for it and fails for a reason that looks unrelated. So the test asserts
both patched files still parse — `can_instantiate()`, since a parse error still `load()`s to a
non-null `GDScript` — *and* that each patched path still behaves: `GutUtils.GodotSingletons.names`
is populated (proving `_static_init()` resolved every `class_ref` entry), an unset
`StubParams.return_val` reads back as `null` rather than leaking the `NOT_SET` sentinel, and a
stubbed one reads back unchanged. Every failure message names `LOCAL_PATCHES.md`, because the fix
is to re-apply the patches, not to relax the test. It also asserts the doc itself still exists.

`integration/test_project_load_integrity.gd` is the fifth invariant test, and it is the only one
that asks the **engine** to load the game rather than reading the files. It walks every `.tscn` /
`.tres` / `.gd` outside `addons/` (~130 resources, ~280 scripts), loads each one exactly once, and
asserts four things: nothing loads to `null`, every `PackedScene` can be instantiated, every
script compiles (`can_instantiate()`, since a parse error still `load()`s non-null), and **the
engine logged no errors at all during the pass**.

It exists because the gate's first two steps cover far less of the project than they look like
they do. `godot --headless --import` resolves *importable* assets — textures, fonts, audio — and
never loads a `.tscn`/`.tres`; `--quit` boots the autoloads and `res://boot/…` and nothing else.
Everything reachable only from an assault level, the race sub-mode, the open-space hub or
infiltration was therefore never loaded by any gate step. Three `ext_resource, invalid UID`
warnings were once live in the tree and `--import` surfaced exactly **one**; the other two only
appeared once every scene had actually been loaded. On its first run this test found two more
defects nothing else could see: `race_level_1.tscn` declared 212 atlas tiles beyond what its
256×256 texture can hold (636 engine errors per load), and `TestIsometricScene.tscn` pointed its
backdrop at a stale `res://.godot/imported/…ctex` hash, so the documented backdrop silently
rendered nothing on every clone.

It complements `test_resource_uid_integrity.gd` rather than overlapping it. That test reads files
and never asks the engine, because a warm `.godot/uid_cache.bin` reports stale UIDs as fine; this
one asks the engine, because a reference that resolves by neither UID nor path, a resource the
engine rejects, and a script that does not compile are all invisible to a text scan. Four things
to know before touching it:

- **The load pass is lazy, runs once, and keeps every result.** Godot's resource cache holds no
  strong reference, so dropping them would make each test re-read from disk and re-emit the same
  errors. `_load_everything()` is idempotent, so it does not matter which test runs first or
  whether only one is run.
- **It claims the engine errors itself** (`GutTrackedError.handled = true`). GUT 9.7 fails any
  test during which the engine logged an error, with a bare `Unexpected Errors:` that names none
  of the 130 resources; taking ownership is what lets the failure message name the file.
- **Engine *warnings* reach the same tracker**, which is precisely why `ext_resource, invalid UID`
  — a warning, not an error — fails this suite instead of scrolling past in the gate log.
- **A scene whose attached script fails to compile still loads non-null and still reports
  `can_instantiate() == true`.** That is why the scripts are walked separately rather than being
  taken on trust from the scenes that reference them.

Its failure modes were checked by breaking things on purpose and reverting: an invented
`uid://` in `laser_ray.tscn` fails the no-errors test naming the file and line, appending a call
to a nonexistent function fails the compile test, and pointing an `ext_resource` at a missing
`.png` fails the load test. Keep that habit if you extend it — an integrity test that cannot be
made to fail is worse than none.

`integration/test_enemy_contact_damage.gd` is the sixth invariant test, and the only one that
polices **balance data** rather than the files or the engine. It asserts that every assault
enemy's contact `HitBox` deals the damage its `*_config.tres` declares — the `CLAUDE.md`
convention that enemy stats live in the `.tres` and are applied in `_ready()`.

It exists because every `BaseEnemy` subclass's `.tscn` authors a `ContactHitBox` node with a
hardcoded `damage = 20` and no way to read `config` — that only exists at runtime — so every
enemy that wants its configured `collision_damage` has to re-apply it in `_ready()` off
`contact_hit_box` — `bomber.gd`, `light_assault_ship.gd`, `ram_ship.gd`, `gunship.gd` and
`space_station.gd` all do this, and `drone_interceptor.tscn`/`kamikaze_drone.tscn` author a
different scene default (30) instead. Miss the re-apply and the `.tres` field is simply dead: it
parses, the enemy works, and the only symptom is a number nobody can see. The `Gunship` shipped
that way — `collision_damage = 30` ignored, so the heaviest ship in the roster rammed for 20 —
and nothing else in the suite could reach it, because no other test reads a HitBox.

Three things to know before extending it:

- **The two config-less entries are still assertable.** `interceptor_config.tres` has no
  `collision_damage` line and `sniper_enemy` has no config at all, so both inherit `ShipConfig`'s
  default of 20 (`ship_config.gd:8`) — which happens to equal the scene's hardcoded 20. They
  are listed so that if either value ever moves independently, the mismatch surfaces here.
- **`bonus_drone` is the one deliberate exception**, asserted from both sides: `bonus_drone.tscn`
  authors no `ContactHitBox` node at all, *and* its config asks for 0. Flipping the `.tres` to a
  non-zero value without touching the scene fails the test rather than silently doing nothing.
- **Only DIRECT children are searched for the HitBox.** Bullets carry their own, but they live
  under the enemy's `BulletPool`, and the station's turrets live under `Turrets`.

`integration/test_contact_hitbox_geometry.gd` is the seventh invariant test, and the companion to
the one above: that file polices what a contact `HitBox` *deals*, this one polices what it
*covers*. For every entity that has one, the generated `CollisionShape2D` must carry both the body
`CollisionShape2D`'s `shape` **and** its `transform`.

A `Shape2D` is a resource: it holds the radius, not the `CollisionShape2D.scale` that multiplies
it at runtime. Copying `col.shape` alone used to be how these hitboxes were built in code, so
every entity that sizes its hull by scaling its collision shape — six of them — got a contact box
at the *unscaled* radius. The gunship scales an 18 px circle by 2.31 to match its 92x84 sprite, so
it rammed with a box 38% of the hull the player can see; the drone interceptor was 3.08x off. The
fix, and now the only way these are built, is scene-authored: every `ContactHitBox` node's
`CollisionShape2D` references the exact same `SubResource` shape id as the body's and copies its
`scale`, next to the body it has to match instead of reconstructed from it at runtime.

Two things to know before extending it:

- **`_spawn()` and `_contact_hitbox()` are typed `Node2D`, not `BaseEnemy`.** `AllyFighter` is
  `class_name AllyFighter extends CharacterBody2D` (`ally_fighter.gd:1-2`), so the enemy-typed
  harness next door fails its row with "root is not a BaseEnemy" — a failure that reads exactly
  like the bug under test but is not one. Do not "fix" that by dropping `ally_fighter`: it is the
  only coverage of the fourth build site.
- **Both guards are load-bearing.** Four of the eleven roster entities author their body at
  `scale = 1`, where the main assertion passes even unfixed — so a vacuity guard asserts at least
  one entity still has a non-identity transform. The other guard rejects a *non-uniform* scale,
  the one case a copied transform genuinely cannot reproduce on every `Shape2D` type (the Godot
  docs' "scaling of collision shapes is not supported" bites here and nowhere else). A uniform
  scale does reach the physics server on 4.6.3 — measured, not assumed; see
  `docs/plans/baseenemy-gd-56-59-builds-the-contact-hitbox-from-col-shape-/2-research.md`.

`integration/test_enemy_hurtbox_geometry.gd` is the eighth invariant test, and the other side of
that same collision pair. The two files above police the box an enemy hits the player *with*; this
one polices the box the player hits the enemy *on*. For all eleven roster entities the `HurtBox`'s
entity-local rect must **cover** the body `CollisionShape2D`'s, within 1.0 px per edge.

The rule it states: **armour is a damage rule on a full-size hurtbox, never an absent hurtbox.** A
shrunken hurtbox leaves visible hull that swallows shots and reports nothing — which the player
reads as a broken gun, not as armour. It came out of the question of whether the space station's
core hurtbox should narrow from 240 to 88 px wide; that was rejected (25 % of the boss's visible
width dead in phase 1, 66 % in phase 2, on a rotating hull), and
`test_the_88x240_proposal_fails_this_sweep` applies the exact proposal to a live station instance
and asserts it fails, so the decision is a gate rather than a paragraph someone re-litigates.

Four things to know before extending it:

- **Enforced relation is `HurtBox ⊇ body CollisionShape2D`, not `HurtBox ⊇ sprite`.** The station's
  body collider is 240x240 under a 256x256 sprite, so 8 px per edge of visible hull is outside
  *both*. Do not mistake this for an art check.
- **The 1.0 px tolerance is load-bearing from the first line**, not a patch applied after a red
  run: three of the eleven fail a bare `Rect2.encloses()`, two by ~1e-5 px of float noise. It is
  bounded by the smallest projectile *half-width* in the game (2.0 px), so a tolerated gap can
  never be one a projectile fits through.
- **The vacuity guard here is not the same shape as the sibling file's, deliberately.** This sweep
  compares two rects that are *both* built by `_local_rect()`, so dropping the transform
  composition cancels out and the sweep silently degrades to comparing raw `Shape2D` sizes while
  staying green — measured. So the guard asserts the composition **changes at least one rect**,
  not merely that some transform is non-identity. Copying `test_contact_hitbox_geometry.gd`'s
  guard verbatim would not catch it.
- **The roster has a completeness guard**, which the two older files still lack: a `DirAccess`
  pass over the top level of `assault/scenes/enemies/` and `assault/scenes/allies/` fails if a
  `<dir>/<dir>.tscn` exists that the roster does not list. Top level only — the enemies directory
  also holds loose scripts, and subdirectories hold non-entity scenes (`bomber/bomb.tscn`,
  `light_assault_ship/states/`).

The whole **space-station family** — `integration/test_space_station.gd`,
`test_station_assault_section.gd`, `test_station_laser_phase.gd`, `test_laser_ray_hit_mask.gd`,
`test_station_gunnery.gd`, `test_station_reinforcements.gd`, `test_station_death_sequence.gd`,
`test_station_incoming_damage_paths.gd`,
`test_level_1_sequence.gd` and `test_radial_attack_pattern.gd` — are the other exceptions, for a
different reason: the `space_station` entity, the `station_assault` section, the laser phase, the
gunnery, the reinforcement spawner, the death sequence and `RadialAttackPattern` are all **new code**, so their tests assert intended behaviour
rather than pinning existing quirks.
`test_space_station.gd` carried a documented coverage gap — most of it drives damage by emitting
`HurtBox.received_damage` directly, so it proved nothing about collision layers, and the section
tests did not close that. Its last two tests now do, for the bullet path: they instance a real
`bullet.tscn` and step physics, so the layer/mask chain has to work for them to pass. The first of
the two is also the load-bearing guard on the station's core-hurtbox decision — it pins that a
player bullet crosses the armoured core and still kills the turret behind it, so if the still-open
backlog item about whether the default gun should stop on its first damaging hit
(`decide-whether-the-player-s-default-gun-should-stop-on-its-f`) is ever actioned, the gate says
"the station's turrets just became unkillable" at the point of the change.

`integration/test_station_incoming_damage_paths.gd` closes the rest of that gap — the rocket (32)
and asteroid (1024) mask bits and the incoming mining-laser ray — with the same technique: real
scenes, stepped physics, and no `received_damage` emit anywhere in the damage path. A real
`homing_missile.tscn` and `warhead_missile.tscn` take 100 and 50 off the unarmoured core; a real
`big_asteroid.tscn` parked inside the hull takes 40; the mining laser runs its full 1200 px
*through* the station and burns it. All four were checked by mutation — setting
`base_enemy.gd:25`'s `97 | 1024` to the gunship's raw `65` reds five of the nine tests with
messages that name the missing bit — and the mask values live in code, not in the scene, so
mutating the `.tscn` proves nothing.

Four things to know before extending it:

- **`beam_dps = 12` is 0.2 damage per physics frame** and `beam_behavior.gd`'s
  `_accumulate_and_apply` only forwards whole numbers, so the first `armor_deflected` from the
  mining laser lands around frame **30**. A 4-frame budget passes the beam-endpoint assertion and
  silently drops the one that proves the beam found the core; that is how the test first ran.
- **`direct_space_state` may only be queried from a physics frame**, so the beam tests drive
  `BeamBehavior.tick()` from a small `BeamDriver extends Node2D` that ticks it in its own
  `_physics_process`. The driver doubles as the behaviour's `state` and as its `actor`; the inner
  class is deliberately not named `Test*`, or GUT would collect it as an inner test suite.
- **The laser row's boundary test is the load-bearing one.** `SpaceStation`'s root is layer 0 *on
  purpose*, and the mask bits are irrelevant to the beam, so
  `test_a_station_on_the_default_body_layer_would_block_its_own_fight` puts a live station on
  layer 1 and asserts the beam stops dead at `y = +120` and damages nothing — the rejected
  configuration applied to a real instance, in the same shape as
  `test_enemy_hurtbox_geometry.gd::test_the_88x240_proposal_fails_this_sweep`.
- **A rocket IS consumed by the first hurtbox it overlaps**, unlike a bullet:
  `homing_missile.gd:47-48` and `warhead_missile.gd:22-23` `queue_free()` on any `area_entered`.
  On this boss that means a missile fired up a turret lane dies on the armoured core two frames
  early and no turret ever takes rocket damage. That one test is marked CHARACTERIZED and filed as
  `rockets-cannot-damage-the-space-station-s-turrets-they-deton`; it also asserts
  `armor_deflected` fired, because otherwise it would pass just as happily on a station no rocket
  can reach at all.

`integration/test_player_bullet_lifetime.gd` is intent as well, and it is the *other* end of that
station dependency. It states the two projectile-lifetime rules directly rather than leaving them
implied by the boss fight: **(1)** a player bullet is consumed by the first hit that actually
deals damage, but NOT by a *deflected* one (`bullet.gd::_hit_is_deflected()` duck-types a query
for `is_armored()` on the hit target) — the premise the station's armoured core rests on, and the
reason `PierceModule` is finally an upgrade rather than a downgrade — and **(2)** an unpooled
player bullet frees itself when it leaves the screen, which nothing did before. Its invariant test
enumerates `WeaponBehavior` subclasses from `ProjectSettings.get_global_class_list()` rather than a
hand-written list, so a *sixth* behaviour added later is covered on the day it lands.

Three traps it hit, all worth knowing:

- `assert_signal_emitted_with_parameters(obj, signal, params, index)` takes an emission **index**
  as its fourth argument, **not a message**. Passing a string there makes GUT compare a `String`
  to an `int`, and the test fails with `Invalid operands 'String' and 'int'` — which looks
  nothing like the real cause.
- **A stub `state` must carry a script.** Behaviours resolve their actor with
  `state.get("actor")`, and `set("actor", x)` on a *scriptless* `Node` is a silent no-op, so
  `fire()` early-returns and a "spawn a bullet and check it" test passes having spawned nothing.
  Assert a lower bound on the spawn count, not just a property of whatever was spawned.
- **The stub actor needs a real `velocity` property.** Four behaviours read `actor.velocity`
  directly rather than through `get()`, so a bare `Node2D` reds the test on setup.

`integration/test_level_director_polling.gd` is intent too, and of a different kind again: it pins
that `LevelDirector`'s ENEMIES_CLEARED poll ends on `child_exiting_tree`, honours its fallback
window, and — the reason it exists — leaves nothing alive behind an early return. See the leak
trap below.

One trap `test_station_assault_section.gd` had to work around, worth knowing before you add
a `LevelDirector` test:

- **`_wait_enemies_cleared()` polls once per second.** Its deadline is only re-checked *after*
  `_wait_for_child_exit_or_timeout(container, 1.0)` returns, so a 0.3 s timeout really fires at
  ~1.0 s, plus a 0.2 s settle. Budget off the poll, not the nominal timeout.

A test that ends while that coroutine is suspended used to leak the suspended
`GDScriptFunctionState`, which holds `level_director.gd` open — freeing the director out from under
its own coroutine stranded the state forever, since Godot has no way to resume a function bound to
a deallocated object. `LevelDirector` now carries a cancel seam for this: a private `_wait_tick`
signal, fed once per frame while the node is in the tree, that every wait helper awaits instead of
`get_tree().process_frame`. `_exit_tree()` sets a `_cancelled` flag and emits `_wait_tick` once more,
synchronously, *before* the node is deallocated, so every suspended wait resumes right there, sees
`_cancelled`, and returns — releasing its function state instead of leaking it. A test no longer
*needs* to manually drain a wait before tearing the director down; doing so (as
`test_station_assault_section.gd` still does) remains harmless, just no longer load-bearing.
`integration/test_level_director_polling.gd` tests 4-6 are the regression coverage, freeing the
director mid-wait and asserting the coroutine actually returns.

Separately, `_wait_for_child_exit_or_timeout()` used to race a `SceneTree.create_timer(poll_seconds)`
against `child_exiting_tree`, so **every** early return — not only an abandoned one — left a timer
ticking for the rest of the poll window, reported only at process exit as `ObjectDB instances
leaked` / `resources still in use` (neither line matches the gate's fatal-error regex, so **the gate
stays green while leaking** — run [`scripts/check-test-leaks.sh`](../scripts/check-test-leaks.sh) to
see it). It now measures its deadline with `Time.get_ticks_msec()` and creates no timer at all.
`integration/test_level_director_polling.gd` test 3 is the regression test for that; it amplifies to
100 polls because a single stranded timer is one object against the engine's own drift.

## These are characterization tests

They pin down what the code does **today**, bugs included. A test that documents surprising
behaviour is marked `CHARACTERIZED` in a comment, and the suspicion is filed as a task via
`./scripts/backlog-cli.js add-task code-health-backlog "<short head>"`. Do not "fix" the code to
make one of these read better without first deciding that the behaviour itself is wrong — the
point of the suite is that a behaviour change is a *visible* change.

## House rules learned the hard way

- **Never let a test touch the real save files.** Every persistent autoload writes to a fixed
  `user://*.cfg`, and the live autoload reads it at boot, so an unsandboxed test leaks into the
  player's profile and into the next run of the suite. Use `helpers/save_sandbox.gd`:

  ```gdscript
  const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
  var _sandbox := SaveSandbox.new()
  func before_all() -> void: _sandbox.capture()
  func after_all() -> void:  _sandbox.restore()
  ```

- **`Texture2D.get_image()` returns the same `Image` instance on every call**, so mutating it
  poisons every later reader in the same GUT process — including later assertions in the test that
  mutated it. Verified on `CompressedTexture2D`: `second get_image() is same instance: true`.
  `duplicate()` it, and duplicate **inside the helper** so no caller can forget
  (`integration/test_entity_sprite_transparency.gd` does this, and its boundary case re-reads the
  original afterwards to prove the duplication worked). Same class of trap as a shared `Shape2D`
  sub-resource — see `integration/test_enemy_hurtbox_geometry.gd`'s note on `RectangleShape2D_ss`.
  Note also that `Image.duplicate()` is typed `Resource`, so `var copy := img.duplicate()` is a
  **parse error** under GUT's warning load; write `img.duplicate() as Image`.

- **An edited image file is invisible until you re-import.** A non-editor run resolves a texture
  through the `[remap] path` in its `.import` file to `.godot/imported/*.ctex` and never checks
  the source; the staleness check lives in a `.md5` sidecar it does not consult. Change a `.png`
  and the suite keeps reading the old pixels until `godot --headless --path . --import` runs.

- **Prefer a tree-less `Script.new()` instance to the live autoload.** Outside the tree
  `_ready()` never fires, so `_load()` never runs and the object starts from a known-empty
  state. Use the real singleton only when the code under test needs `get_tree()`.

- **Keep `_process` / `_physics_process` out of the tree and call them by hand** when timing
  matters (see `unit/test_overheat_component.gd`, `unit/test_camera_shake.gd`). Real frame
  timing makes assertions approximate for no benefit.

- **GUT fails a test on any unexpected engine error**, including one raised inside a signal
  callback. Connect a callable whose arity matches the signal exactly: `Health.amount_changed`
  and `State.state_transition` each carry one argument, so a **zero-argument** handler raises
  `Method expected 0 argument(s), but called with 1` and reds the test. Both were declared with
  zero parameters until 2026-09-03 while being emitted with one; the declarations are now honest,
  which makes the mismatch visible in the source, but it does not make a zero-arg handler legal.
  `push_warning` is *not* treated as a failure. **Declaring a signal's parameters does not stop
  this on its own** — `emit()` never checks a declaration against its call sites, so the honesty
  above only helps a reader, not the engine. `integration/test_signal_emit_arity.gd` is the actual
  enforcement: a project-wide sweep asserting every self-emitted signal's call sites match its
  declared arity (member-access emits, e.g. `hb.received_damage.emit(...)`, are out of its scope
  — see the file's header). Its first run caught a live instance of the same drift in
  `MovementController.action_single_press`/`action_double_press`, fixed alongside it.

- Components that need a `_ready()` pass (`Health` builds its i-frame `Timer` there; `Shield`
  builds its regen `Timer` there) must actually be in the tree. Add the host to the tree *first*,
  then add the component to the host. `Health` no longer needs a parent to take damage — its
  `get_parent().name` log line is now behind `OS.is_stdout_verbose()` and has a fallback.

## Coverage today

Autoloads: `MissionState`, `UpgradeState`, `ShipModuleState`, `ShipProgressionState`,
`SessionState`, `EventBus`, `DialogPlayer`, `CameraShake`.
Components: `Health`, `HitBox`/`HurtBox`, `Shield`, `TempHealth`, `Overheat`, `DamageReaction`.
Plus `global/statemachine/` and the `PlayerBase` damage chain.
Project-wide: `[ext_resource]` UID integrity across every `.tscn`/`.tres` — pairwise agreement,
dangling UIDs, duplicate declarations, non-canonical (aliasing) UID text, collisions found by
decoding rather than by string match, and the UID-only references in `project.godot` /
`export_presets.cfg` — plus two canaries against a wholesale UID strip; and
(`integration/test_project_load_integrity.gd`) an engine-side load of every `.tscn`/`.tres`/`.gd`
outside `addons/`, asserting nothing loads to `null`, every scene instantiates, every script
compiles, and the engine logs no error or warning along the way; and
(`integration/test_signal_emit_arity.gd`) every self-emitted signal's declared parameter list
against its actual `.emit()` call sites, project-wide.
Tooling: the two local patches the vendored GUT addon needs under Godot 4.6.3
(`integration/test_gut_local_patches.gd`).
Art: entity sprite transparency (`integration/test_entity_sprite_transparency.gd`) — no texture an
entity under `assault/scenes/{enemies,player,projectiles,hazards,allies}` draws over the game world
may be 90%+ fully opaque. Reads scenes via `PackedScene.get_state()` (never instantiated) and
resolves `Sprite2D.texture`, `AnimatedSprite2D.sprite_frames` and `AtlasTexture.atlas`; walks 25
scenes to 16 distinct textures. Two knowingly uncovered: both asteroid hazards assign their sheet
at runtime from a `tileset_texture` export, so no node property holds it.
Entities: the `space_station` mini-boss (`integration/test_space_station.gd`) — armour rule, turret
lifecycle, and the config-driven stats.
Entities, the layers: every way damage reaches that boss
(`integration/test_station_incoming_damage_paths.gd`) — real missiles for `HurtBox.collision_mask`
bit 32, a real asteroid for bit 1024, and a `BeamBehavior` driven from a real `_physics_process`
for the incoming mining laser, whose boundary test puts the station on the default body layer 1
and asserts it then blocks its own fight. Plus the CHARACTERIZED pin that a rocket, unlike a
bullet, is consumed by the first hurtbox it overlaps and so can never reach a turret.
Levels: the `station_assault` section (`integration/test_station_assault_section.gd`) — the
`ENEMIES_CLEARED` gate, the per-section timeout and its free-on-expiry path, and Level 1's
section order and station wave.
Projectiles: player-bullet lifetime (`integration/test_player_bullet_lifetime.gd`) — the
pass-through rule the station boss depends on, the off-screen self-free every `WeaponBehavior`
must hand its bullets, the boundary case that the same free must **not** reach a pooled bullet
(asserted on `BulletPool.acquire()`, never on `_idle.size()`, which reads healthy even on the
broken build), and a characterization pin on what `PierceModule` does today.
Hazards: `LaserRay.hit_mask_override` (`integration/test_laser_ray_hit_mask.gd`) — pins the shared
default mask `128 | 256 | 512` so the race hazards and Level 1's laser columns cannot be silently
narrowed, and pins that `0` means "use the default" rather than "collide with nothing".
Entities, phase 2: the station laser phase (`integration/test_station_laser_phase.gd`) — the
`armor_broken` trigger and its once-only guard, the telegraph window (a beam damages a real
layer-128 probe HurtBox only after it arms, never during the warning), the self-damage regression,
the rotation rate, volley determinism, teardown on boss death, and the config copy.
Entities, the guns: `StationGunnery` (`integration/test_station_gunnery.gd`) — that the `BulletPool`
is a direct child of the station, both phases and the handover between them, per-turret aim and
barrel rotation, dead turrets dropping out of the volley, ring precession, the `core_ring_step`
design lock, teardown, and the config copy. Plus the shared pattern resource it drives
(`integration/test_radial_attack_pattern.gd`) — ring vs fan spacing, aiming, `spawn_radius`, that
it ignores `ship.rotation`, and that `bullet_count <= 0` fires nothing.
Entities, the adds: `StationReinforcements` (`integration/test_station_reinforcements.gd`) — the
config copy, four-edge coverage, that every squad entry starts off screen and clears the measured
spawn margin, deterministic `LEFT→RIGHT→BOTTOM→TOP` cycling, that ships are spawned as *siblings*
of the station with an `EnemyPathMover`, that every movement points into the screen, the
`FREE_ON_DURATION` guarantee, `enemy_spawned_orphan` registration, both stop signals, the
whole-squad population cap, the one-shot-timer split, that every ship the table can spawn is
killable by the player's primary weapon, and the two-ship escape-combo cost.

Two things that file had to work around, both worth knowing:

- **`died` cannot be tested without unhooking `armor_broken` first.** The station refuses all core
  damage while a turret lives, so the only route to `died` runs through `armor_broken` — which
  already stops the spawner. Without the disconnect, the case passes even if the `died` connection
  is deleted.
- **`ScoreTracker._process` resets any forced combo to 1.0 on the first frame** when
  `_combo_decay_remaining` is 0, and `start_tracking()` turns `_process` on. Call
  `tracker.set_process(false)` and assert on `tracker.get("_combo")`, as
  `integration/test_station_assault_section.gd` already does.

### Three traps `test_station_laser_phase.gd` had to work around

- **`entity.config` is private per instance; the object `load()`/`preload()` returns is not.**
  This trap used to read "`SpaceStation.config` is a single process-wide object", and it was true:
  `ResourceLoader` caches by path, so every station shared one config and writing to it rewrote the
  shipped values for every later test in the run. `ShipConfig.privatise()` — called from
  `BaseEnemy._init()` / `_enter_tree()` and from `AllyFighter` — now gives every entity its own
  `duplicate()`, and `integration/test_config_instance_isolation.gd` holds that shut for all ten
  entities.

  What still bites: **the resource a test `preload()`s or `load()`s is the shared, cached one.**
  `const STATION_CONFIG := preload(".../space_station_config.tres")` is process-wide balance data —
  read it, never write to it. Two windows also remain open, both unreachable from non-addon code
  today and both written up in `test_config_instance_isolation.gd`'s header: `Node.duplicate()`
  hands two nodes one private copy, and assigning `entity.config = load(...)` after the entity is
  already in the tree fires neither hook.

  Overriding the **`LaserPhase` node's** own fields is still the recommended way to shorten the
  laser timings — not for safety now, but because those fields are the node's tunable surface and
  its no-config fallback.
- **`ExplosionEffect.explode()` parents its `CPUParticles2D` to the actor's parent by default**
  (`global/components/explosion_effect.gd`) and lets it self-free on `finished` ~1 s later. A
  station added straight to the test script therefore leaves particles behind as unfreed children
  when the test that kills the core returns (`GUT WARNING: Test script has 2 unfreed children`).
  Parent entities that will die to a container `Node2D` that `add_child_autofree` owns — which is
  also how they are really parented, under `WaveManager.enemy_container`.

  **The same rule used to bite one level down, and cost a whole gate cycle** (fixed by
  `docs/plans/explosioneffect-orphans-its-particles-onto-whatever-the-dyin/`). A `StationTurret`
  used to leave the default in place, so the "parent" `ExplosionEffect` wrote into was the
  station's `$Turrets` node, and from the first turret kill onward `$Turrets.get_children()` also
  contained `CPUParticles2D`. A test helper doing a raw `get_children()` then handed back a
  particle node, `child as StationTurret` yielded `null`, and the next method call failed with
  `Invalid call. Nonexistent function 'is_alive' in base 'Nil'` — an *Unexpected Error*, so GUT
  reds the test with no failed assertion to point at. `station_turret.gd`'s `_destroy()` now
  passes the station's own parent as an **explicit `container`** argument, so a destroyed turret's
  blast survives outside the hull and never lands in `$Turrets` in the first place — but
  **always filter a container's children by type before casting** regardless.
  `SpaceStation._turrets()` does, which is why production code never hit this even before the fix.
- **A beam's full lifetime is longer than it looks.** At `warn 0.2 / active 0.3` it is ~1.9 s, not
  0.5: `warn` + a ~0.56 s `laser_increase` charge-up + `active` + a 0.84 s dissolve. Any test
  volley interval must exceed it, or a second volley spawns while the first is still dissolving and
  the child-count assertions become false rather than merely flaky.

Entities, the death: `StationDeathSequence` (`integration/test_station_death_sequence.gd`) — that
the wreck stays in the tree after HP hits 0, that `died`/`was_killed` still fire at that instant
(the `ScoreTracker` kill-vs-escape contract), the `_dying` latch against `Health`'s 0 → 0 re-emit,
the disarmed corpse, the free-after-duration path and the `death_duration = 0.0` boundary that
proves the new path is additive, the blast chain rolling across the hull, deterministic
`blast_offset(i)`, the decaying spin and darkening, and the config copy. Plus
`BulletPool.cancel_active()` in `test_station_gunnery.gd`.
Levels, end to end: `integration/test_level_1_sequence.gd` — Level 1's real five-section sequence
(`deep_space → asteroid_belt → station_assault → planet_approach → cloud_descent`) with a real
`SpaceStation` killed in the middle, asserting it reaches `level_complete`, that the boss section
does not advance while the wreck is present, and that the run finishes well inside the timeouts.

### The leak trap has a second half — zero `stagger_delay`, not just `spawn_delay`

`test_level_1_sequence.gd` compresses the real Level 1 sections to run in seconds. Zeroing every
`WaveResource.trigger_time` and `SpawnEntryResource.spawn_delay` is **not enough**:
`wave_manager.gd:143` expands a formation as `base_delay + slot.delay`, and every formation type
(v, wedge, line, diagonal, cluster) staggers its own slots. Level 1 uses formations heavily, so
~30 `_spawn_with_delay()` coroutines were left suspended holding `SceneTreeTimer`s after
`level_complete`.

That prints `ObjectDB instances leaked` at exit, which **does not match the gate's fatal-error
regex** — so the suite stayed green while leaking, exactly as the trap above describes. The fix is
`entry.formation.set(&"stagger_delay", 0.0)` alongside the other two. Safe for the same reason:
`wave_builder.gd:154-192` builds every formation with `.new()` per call, so nothing shipped is
shared.

⚠️ Separately, the `ObjectDB instances leaked` line the **gate** prints comes from step 1, the
headless `--import`, and predates this suite. Verified against a stashed working tree: baseline
and current both emit exactly one. Do not go hunting for it in the tests.

### Checking for leaks: `scripts/check-test-leaks.sh`

The gate cannot catch any of the above. Godot prints the leak lines *after* the main loop is gone,
so they arrive after GUT has already set the process exit code, and they match none of
`/agent/verify.sh`'s `FATAL` patterns. `scripts/check-test-leaks.sh` runs the suite with the gate's
exact arguments and additionally greps the output for
`ObjectDB instances leaked|resources still in use|Resource still in use`, exiting 1 on a hit. Run
it after touching anything that awaits.

It is a separate script rather than an edit to the gate because **`/agent` is mounted read-only**
inside the dev container — the agent cannot change `verify.sh`. Folding it in is a one-line
addition to step 3 and is worth doing; until then the script is the check.

To find out *what* leaked, re-run with `--verbose`:

```bash
godot --headless --verbose --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | grep -E "Leaked instance|still in use"
```

### The ship module unlock gate

`unit/test_ship_module_state.gd` is still mostly characterization, but five of its tests assert
**intent** and say so in a comment: `equip()` now refuses a module that is not unlocked,
unlocking makes it installable, `&""` (unequip) is exempt so a slot can always be cleared, and
`_load()` grandfathers a module that is equipped but not unlocked rather than confiscating it.
One of those, `test_load_grandfathers_a_module_equipped_before_the_gate`, asserts the *exact*
unlocked array and loads twice on purpose. Both matter: `&""` passes the `if id in valid` check
in `_load()` because `SLOT_MODULES` lists it first for every slot, so an unguarded grandfather
append would pollute all four slots with the sentinel; and without the `not in list` guard the
list grows by one duplicate entry per boot, forever. `is_unlocked()` stays `true` under both
bugs, so a weaker assertion catches neither.

`integration/test_module_list_lock.gd` covers the menu side — that locked rows are shown greyed
rather than filtered out, that confirming one is a defined no-op, and (the boundary that matters)
that row 0, the "None"/unequip row, is **never** locked. `is_unlocked(slot, &"")` is always
`false`, so a naive per-row lock check greys out the unequip row and traps the player's module in
its slot; `player_menu.gd:180-184` is the game's only `equip()` caller, so there would be no
workaround. `test_confirming_an_unlocked_row_still_emits` is the deliberate control, so the
locked-confirm test cannot pass by `confirm()` being broken outright.

It reads and restores the **live `ShipModuleState` singleton** (`_unlocked` / `_equipped`) in
`before_all`/`after_all`, on top of `SaveSandbox` — `ModuleList` talks to the autoload, not to a
fresh instance, and the whole suite shares it. Setup mutates those arrays directly rather than
calling `unlock()`, so the fixture does not depend on the very gate under test.

⚠️ `test_reopening_rebuilds_the_lock_flags` reports **24 orphans**. They are the first `open()`'s
rows: `ModuleList._clear()` `remove_child()`s and `queue_free()`s them, and the delete queue does
not flush before the test ends. Pre-existing `ModuleList` behaviour, harmless in play (menu opens
are frames apart), and awaiting `process_frame` does not change the count. Not worth contorting
the test over — but do not read it as a leak you introduced.
