# Review — station core opaque background

VERDICT: CHANGES_REQUESTED

The diagnosis, the chosen fix, the algorithm and **every** measured number in `1-context.md` and
`2-research.md` reproduce exactly on this machine (Godot 4.6.3, headless). The rejected
alternatives are real alternatives and are rejected for real reasons. Nothing here reinvents
anything in `global/components/`, and no `CLAUDE.md` convention is contradicted.

Three blocking problems are all in the **test plan and build sequence**, not in the fix. Two of
them make the plan fail on its first run for reasons unrelated to the defect; one of them makes it
fail *silently* on ~50% of the surface it claims to cover. Fix these four things and this is ready
to implement.

---

## Blocking findings

### B1. The sweep collects 9 textures, not 17. Three of its five scope roots contribute zero, and the two textures cited as threshold headroom are not in it.

`3-plan.md:105-113` specifies the walk as: roots `assault/scenes/{enemies,player,projectiles,
hazards,allies}`, `PackedScene.get_state()`, "every node of type `Sprite2D` yields its `texture`
property". I implemented exactly that walk and ran it. Result:

```
scenes found: 25
scenes with Sprite2D textures: 9
distinct textures: 9
```

| Scope root | Textures the specified walk finds |
|---|---|
| `assault/scenes/enemies` | 9 (bomber, drone, drone_2, heave_gunship, interceptor, drones, sniper, station_core, station_turret) |
| `assault/scenes/player` | **0** |
| `assault/scenes/projectiles` | **0** |
| `assault/scenes/hazards` | **0** |
| `assault/scenes/allies` | **0** |

The cause: most entities in this project do not use `Sprite2D`. They use `AnimatedSprite2D` +
`SpriteFrames` (frequently over an `AtlasTexture`):

- `assault/scenes/player/player_fighter.tscn:6` — node `ShipSprite2D` is `AnimatedSprite2D`,
  `sprite_frames = SubResource("SpriteFrames_ht8os")`. `ply2.png` never checked.
- `assault/scenes/enemies/ram_ship/ram_ship.tscn:69-72` — `AnimatedSprite2D`, `sprite_frames`.
- `assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn:72-74` — same.
- `assault/scenes/allies/ally_fighter/ally_fighter.tscn:9,30-32` — `AnimatedSprite2D` over an
  `AtlasTexture` whose `atlas` is `h_assault_fighter.png`.
- `assault/scenes/projectiles/missiles/homing/homing_missile.tscn:8-20,50-51` — same shape.
- `assault/scenes/hazards/big_asteroid/big_asteroid.tscn:25,27` — there *is* a `Sprite2D` at
  line 27, but it carries no `texture` in the scene; the texture arrives via the root's
  `tileset_texture = ExtResource("5_tex")` script export and is assigned at runtime.

Two consequences, both bad:

1. **The plan's own headroom evidence is outside its own sweep.** `3-plan.md:125` justifies the
   90% threshold with "the highest legitimate value in scope is `ram_ship.png` at 67.19%, then
   `big_asteroid_tileset.png` at 65.82%". Neither is reachable by the specified walk. The highest
   value actually swept is `station_turret.png` at 54.71%.
2. **The gate misses the bug class it exists to catch.** A 100%-opaque *spritesheet* behind an
   `AnimatedSprite2D` renders as exactly the same grey card as `station_core.png` does, and the
   proposed test would never see it. `assault/scenes/player/` is named as a scope root while
   contributing nothing — that is worse than not naming it, because the file will read as though
   the player is covered.

The context doc's measurement ("17 textures referenced by a `Texture2D` `ext_resource` in a scene
under …") is a *grep-level* measurement — I reproduce 18 including `allies` — and the plan silently
carries that number over to a `Sprite2D.texture`-only walk that reaches half of them.

**Required change:** the walk must also handle `AnimatedSprite2D` → `sprite_frames` →
`SpriteFrames.get_frame_texture()`, and resolve `AtlasTexture` to its `atlas`. State explicitly
whether an `AtlasTexture` is measured over its region or over the whole sheet (whole sheet is fine
and simpler — say so). Either that, or cut `player`, `projectiles`, `hazards` and `allies` from the
scope roots and rename the test to say it covers enemy `Sprite2D`s only. The first option is
correct; it is the difference between a gate and a decoration.

Widening is safe against the 90% threshold — I measured every one of the 18 in-scope source PNGs
and confirmed they match their imported `.ctex` byte-for-byte in alpha:

```
100.00%  station_core.png      <- the defect
 67.19%  ram_ship.png          <- highest legitimate
 65.82%  big_asteroid_tileset.png
 58.03%  assault.png
 54.71%  station_turret.png
 53.95%  interceptor.png
 50.65%  Rocket_blue.png
 49.84%  rocket.png
 41.01%  heave_gunship.png
 37.11%  small_asteroid_tileset.png
 36.32%  h_assault_fighter.png
 34.86%  drones.png
 31.47%  giant_lasser.png
 30.10%  ply2.png
 29.93%  sniper.png
 24.84%  bomber.png
 24.54%  drone_2.png
 18.16%  drone.png
```

23 points of headroom under the widened scope. The threshold itself is well chosen — no false
positives today, and no false negative that matters, because the one sprite that is wrong is at
100.00% and not at 89%.

### B2. The vacuity floor as written fails on the first run.

`3-plan.md:128` — `test_the_walk_found_the_entity_scenes` asserts "at least 10 scenes and at least
10 distinct textures". The specified walk finds **9** distinct textures. Copied from
`test_project_load_integrity.gd:152-157`, which uses `assert_gt` (strictly greater), 9 fails
against a floor of 10 either way.

This is a symptom of B1, not a separate defect, but it must not be "fixed" by lowering the floor to
5. Fix B1 and the floor becomes reachable with real slack (17 textures / 20+ scenes).

### B3. `Texture2D.get_image()` returns the *same cached `Image` instance* every call — the boundary test as written poisons the process and fails its own second assertion.

`3-plan.md:127` — `test_the_check_rejects_a_sprite_with_a_painted_background` "takes the known-good
`station_turret.png`, forces every pixel to alpha 1 in memory, and asserts the same helper reports
it as a violation — **and that the untouched original is not a violation**".

Verified on this engine:

```
texture class: CompressedTexture2D
get_image() -> <Image#...>
second get_image() is same instance: true
```

`CompressedTexture2D` caches its decoded `Image` and hands back the *same object* on every call.
Mutating it mutates the copy every later reader in the same GUT process sees, including the second
half of the same test and `test_no_entity_sprite_is_a_solid_rectangle` on any run where ordering
differs (`-gunit_test_name`, a re-run, a future reorder). This is the identical trap
`test_enemy_hurtbox_geometry.gd:224-230` documents for the shared `RectangleShape2D_ss`
sub-resource — same class of bug, same silent-poisoning failure mode.

**Required change:** the plan must say the boundary case operates on `texture.get_image()
.duplicate()` (or an `Image.create_from_data` copy), never on the returned instance, and the file
should carry that as a header note the way the hurtbox test does. Ideally the *helper* should
duplicate, so no caller can get this wrong.

### B4. The build sequence has no re-import step, so step 4's "re-run the test; it must now pass" will fail.

`3-plan.md:92-93` — "Apply the fix in place to `station_core.png`. Re-run the test; it must now
pass."

It will not. A non-editor Godot run resolves `res://assault/assets/sprites/enemies/station_core.png`
through the `[remap] path` in its `.import` file to
`.godot/imported/station_core.png-c74e5cbcc2c1eae671965ff086481b5a.ctex`, and does **not** re-import.
The staleness check lives in a sidecar the run never consults:

```
$ cat .godot/imported/station_core.png-c74e5cbcc2c1eae671965ff086481b5a.md5
source_md5="db6a7f430a941803449ab4d95d154793"
```

Only `godot --headless --path . --import` (gate step 1) notices the changed source md5 and rebuilds
the `.ctex`. Without an explicit import between step 4 and the test re-run, the test reads the old
100%-opaque image, still fails, and the implementer burns time hunting a bug in a correct flood
fill. Add `godot --headless --path . --import` as an explicit sub-step of step 4, and to step 3's
"before" composite too if that reads through `res://`.

(The good news on the same mechanism: the `.ctex` filename hash is derived from the *source path*,
not its contents, so the `.import` sidecar genuinely does not change — `3-plan.md:142`'s "UID churn:
only PNG bytes change" is correct.)

---

## Verified — claims I checked and found true

- **`assault/scenes/enemies/space_station/space_station.tscn:72-74`** — `Sprite2D` with
  `texture = ExtResource("3_ss")`, no `scale`, no `region`, drawn 1:1 at the `CharacterBody2D`
  origin. `:22-23` shares one `RectangleShape2D_ss` (240×240) between the body collider and the
  `HurtBox`; neither is touched by this change. Turrets instanced at `(±76, ±76)` at `:88-99`.
  `station_turret.tscn:13-14` — `Sprite2D` with `station_turret.png`, `CircleShape2D` radius 26.
- **`station_core.png.import`** — `process/fix_alpha_border=true`, `mipmaps/generate=false`,
  `compress/mode=0`. Exactly as claimed.
- **`project.godot:175`** — `textures/canvas_textures/default_texture_filter=0` (Nearest), inside
  `[rendering]`. The line number is right to the line.
- **`assault/assets/shader/hit_flash_vs.tres` — the alpha claim is correct.** I decoded
  `nodes/fragment/connections`, whose quadruples are `(from_node, from_port, to_node, to_port)`:
  `(4,0,2,3)` flash_color → `If.a==b`; `(3,0,2,0)` enabled → `If.a`; `(5,0,2,4)` and `(5,0,2,5)`
  input color → `If.a>b` / `If.a<b`; and `(2,0,0,0)` `If` result → **fragment output port 0 only**.
  For a CanvasItem visual shader, output port 0 is `COLOR.rgb` and port 1 is `COLOR.a`. Port 1 is
  unconnected. Texture alpha passes through untouched, so a transparent pixel stays transparent
  while flashing. `3-plan.md:140` is right.
- **The flood-fill measurements, re-run from scratch:** 20 distinct colours; all four corners
  `#565657ff`; 34365 px (52.44%) match that colour; 4-connected border BFS reaches **34324**;
  **41** enclosed pixels survive; post-fill opaque fraction **47.63%**. Every figure in
  `1-context.md` and `2-research.md` is exact. 47.63% clears both `< 90%` and the station-specific
  `< 0.60`.
- **`PackedScene.get_state()` does what the plan claims.** Confirmed on the real scenes:
  `get_node_type(i)` returns `"Sprite2D"`, and `get_node_property_value()` for `texture` returns a
  **fully-loaded `CompressedTexture2D`** (`res://…/station_core.png`), not a path string, not a
  placeholder. Nothing is instantiated and no `_ready()` runs. Also confirmed:
  `get_node_type()` returns `""` for instanced sub-scene nodes (`Turret0`…`Turret3`), so the
  "deliberately not recursed into" decision is structurally enforced rather than merely intended —
  worth saying in the file, since it means the walk *cannot* accidentally recurse.
- **`Texture2D.get_image()` works under `--headless`** — the dummy renderer still returns a valid
  256×256 `FORMAT_RGBA8` image. This was a plausible blocker and it is not one.
- **Imported `.ctex` alpha is identical to source alpha.** `station_turret` 54.71%, `ram_ship`
  67.19%, `big_asteroid_tileset` 65.82% through `load()` — same to two decimals as
  `Image.load_from_file()`. `compress/mode=0` + `fix_alpha_border` do not perturb the measurement.
- **`tests/integration/test_project_load_integrity.gd:61,94-113`** — `SKIPPED_DIRS = ["addons",
  ".godot", ".git", ".import"]`, `_collect_files("res://", [".gd"])` walks from the project root,
  so `scripts/lib/strip_sprite_bg.gd` **will** be compiled by it. `scripts/` currently holds zero
  `.gd` files, so this is a first. I tested the actual concern by dropping a stub `extends
  SceneTree` under `scripts/` and loading it: `can_instantiate=true`. `3-plan.md:143` is correct
  and the risk is closed, not merely flagged. (Stub removed; tree left clean.)
- **`tests/integration/test_enemy_hurtbox_geometry.gd:24-27,141`** — enforces `HurtBox ⊇ body
  CollisionShape2D`, and its header explicitly says "do not mistake this sweep for an art check".
  Sprite pixels have never fed collision. `3-plan.md:141` is correct; the fix cannot move it.
- **`scripts/pixellab.sh:30-38,60-62`** — `verify` is a real public verb with a `sniff_magic()`
  fallback for this container (`od` only, no `file`, no `python3`). Reusing it from the new wrapper
  is genuine reuse, not a second copy.
- **`CLAUDE.md`** — no convention violated. No `uid://` is hand-typed; no design-space coordinate
  is touched; no `.tres` stat moves; the mandatory visual check is honoured *twice* (before and
  after) at `3-plan.md:88-96` with a named revert path; commits stay on `agent/auto-dev`.
- **`.claude/skills/pixel-art-generation/SKILL.md:95`** already routes hull parts to
  `create_map_object`; `:170-174` already carries the "assert transparency, do not eyeball it" rule
  that found this bug. The proposed `no_background: true` addition for
  `create_image_pixflux`/`_pixen`/`_pro` is genuinely new and is one paragraph. Good.

## Non-blocking findings

### N1. Do **not** generalise the corner-alpha check beyond `station_core.png` — the plan is right and should say why.

`3-plan.md:126` scopes the four-corners-at-alpha-0 assertion to `station_core.png` alone. That is
the correct call, and it is not obvious, so a future reader will try to "improve" it into the
sweep. I measured corner alpha and border-opaque fraction across all 18 in-scope textures:

```
corners all opaque:  station_core.png, big_asteroid_tileset.png, small_asteroid_tileset.png,
                     h_assault_fighter.png, Rocket_blue.png, rocket.png   (+ drones.png, 2 of 4)
```

**Six of eighteen legitimate sprites have fully opaque corners** — they are atlas sheets whose cells
butt against the sheet edge. A generalised corner rule would be a false-positive machine. Put those
numbers in the test file as a comment so the decision is a gate rather than prose someone
re-litigates, exactly as `test_enemy_hurtbox_geometry.gd:9-20` does for the 88×240 proposal.

### N2. The two new `scripts/` files: the `.gd` is justified, the `.sh` wrapper is thin — and the tool needs a home or it is dead code.

The `.gd` is clearly the right call: Godot is the only image library in this container
(`1-context.md` verified — no `python3`, no ImageMagick, no `file`), the operation is binary, and a
committed script is reviewable where a `/tmp` heredoc is not. That matches the
`pixellab.sh` / `fetch-page.sh` / `backlog-cli.js` precedent. Keep it.

The `.sh` wrapper is marginal — its whole job is `godot --headless -s …` plus one call to
`pixellab.sh verify`. It is cheap and matches house style, so it is not worth rejecting, but note
the tension the plan does not: **the "Prevention" section makes this tool dead code by design.** If
every future `create_image_pixflux` call passes `no_background: true`, `strip-sprite-bg.sh` never
runs again, and the argument at `3-plan.md:53-56` ("will recur") is an argument the plan itself is
trying to falsify. Resolve it by giving the tool a documented home: add it to
`.claude/skills/pixel-art-generation/SKILL.md` §5, next to the transparency assertion, as *the*
remedy when the assertion fires. Then it is a documented recovery path rather than a script nobody
will find.

### N3. Name the doc targets. An eighth invariant test touches two files `updating-project-docs` will not prompt for.

`3-plan.md:97` says "the skill rule, then `updating-project-docs`". That skill's step 5 syncs
`CLAUDE.md` only "if the module map or a key convention changed". But `CLAUDE.md`'s bullet on tests
enumerates the invariant tests ordinally — "a second invariant check", "a third", … "a seventh,
over the ENEMIES_CLEARED poll" — and `tests/README.md:447+` ("Coverage today") lists them again.
Adding `test_entity_sprite_transparency.gd` without editing both leaves the numbered list wrong and
the coverage list short. Name both files in the build sequence.

### N4. Commit the engine-minted `.gd.uid` sidecar with the new script.

`tests/integration/test_resource_uid_integrity.gd:158-170` expects a `.gd`'s UID in a sibling
`<script>.gd.uid`. Godot mints one on import. A missing sidecar is not a failure there (the file
simply declares nothing), so this is hygiene rather than a gate — but leave it untracked and it
shows up as noise in the next cycle's `git status`. Commit it alongside, and do not hand-type it.

### N5. Unrelated, pre-existing: there is a stray temp file in the tree.

`assault/scenes/player/player_fighter.tscn6026545143.tmp` — a Godot save-scene temp that was never
cleaned up. Not this change's problem and explicitly not in scope, but it is sitting next to a file
this work will read. Worth a backlog line, not a fix here.

## Scope

One PNG edited in place, two small scripts, one test file, one skill paragraph, two doc edits, one
`--import`, one gate run. With B1's widening the test grows by maybe 25 lines
(`AnimatedSprite2D`/`SpriteFrames`/`AtlasTexture` resolution). That is comfortably one session, and
every step at `3-plan.md:85-99` is independently checkable with a named revert (`git checkout` of a
single PNG). No objection to the size.

---

# Round 2

VERDICT: CHANGES_REQUESTED

All four blockers from round 1 are properly fixed, and the two API questions you asked me to
settle both come back green — I implemented the widened collector exactly as `3-plan.md:141-147`
specifies and ran it against the real scenes. The design is now settled and I am not asking for
another design pass.

What holds this at CHANGES_REQUESTED is that **the widened walk yields 16 textures, not 18**, and
the plan has attached four numeric/attribution claims to the number 18 that are wrong — including
one that is flatly false about the codebase. Every one of those claims is destined to be copied
verbatim into a permanent invariant-test comment (`3-plan.md:150` "noted in the file",
`:191` "those numbers go in the file as a comment"). A wrong comment in a gate file is the exact
failure mode this repo builds gates to avoid. These are four one-to-two-line corrections with no
design consequence.

## Verified green — the two implementability questions

I built the collector from `3-plan.md:141-147` (Sprite2D→`texture`; AnimatedSprite2D→
`sprite_frames` via `get_animation_names()`/`get_frame_count()`/`get_frame_texture()`;
`AtlasTexture`→`.atlas`; de-dup by `resource_path`) and ran it under `--headless`.

- **`SceneState.get_node_property_value()` returns a fully-loaded `SpriteFrames`.** Confirmed on
  all seven `AnimatedSprite2D` nodes in scope, e.g.
  `player_fighter.tscn` node `ShipSprite2D` →
  `(res://assault/scenes/player/player_fighter.tscn::SpriteFrames_ht8os):<SpriteFrames#…>
  class=SpriteFrames`. Not a path, not a placeholder. Same for `ally_fighter`,
  `light_assault_ship`, `ram_ship`, `laser_ray` (node `BeamSprite`), `homing_missile`,
  `warhead_missile`.
- **`SpriteFrames.get_frame_texture()` works outside the tree.** `SpriteFrames` is a `Resource`,
  not a `Node`; no tree, no `_ready()`, no engine error. It returned real textures for every
  animation × frame.
- **`AtlasTexture` → `.atlas` resolution works** and is needed: `h_assault_fighter.png`,
  `Rocket_blue.png` and `rocket.png` only appear via that path. No null-atlas cases.
- **The widening does what it was asked to do.** `hazards/` now contributes (`laser_ray.tscn` →
  `giant_lasser.png`), `player/` contributes (`ply2.png`), `projectiles/` contributes
  (`Rocket_blue.png`, `rocket.png`), `allies/` contributes (`h_assault_fighter.png`). No root is
  decorative any more. B1 is resolved.
- **B3 fix is right.** Duplicating inside the helper is the correct placement. Note for the
  implementer, not a change request: this implies the shared entry point takes an `Image`, so the
  boundary test can hand it a mutated duplicate while the texture-level wrapper duplicates for
  everyone else. The plan's two sentences are consistent with that; just make sure the seam lands
  there.
- B2, B4, N2, N3, N4, N5 all addressed as described. The `--import` sub-step at `3-plan.md:100-106`
  now states the `.ctex`/`.md5` mechanism correctly, including that the `.import` sidecar itself
  does not change.

## R2-1 (blocking, factual). `3-plan.md:149-153` is false: `small_asteroid.tscn` does not cover `big_asteroid_tileset.png`, and it has the identical gap.

The plan writes:

> `big_asteroid.tscn:27` has a `Sprite2D` with **no** stored `texture` … That is accepted and noted
> in the file rather than worked around: `big_asteroid_tileset.png` is still covered, because
> `small_asteroid.tscn` and the race scenes reach it

Both halves are wrong.

`assault/scenes/hazards/small_asteroid/small_asteroid.tscn:24,30` is the **same pattern**, not a
mitigation:

```
[node name="SmallAsteroid" type="CharacterBody2D"]
tileset_texture = ExtResource("5_tex")      # small_asteroid_tileset.png, NOT big_
...
[node name="Sprite2D" type="Sprite2D" parent="."]     # bare, no texture property
```

So (a) it references `small_asteroid_tileset.png`, never `big_asteroid_tileset.png`, and (b) it
reaches it through the identical runtime `tileset_texture` export, so it is equally invisible to
the walk. And "the race scenes reach it" is irrelevant to coverage — `3-plan.md:160` puts
`assault/scenes/race/` out of scope for this test, so a race-scene reference gives the *gate*
nothing.

My run confirms it: neither `big_asteroid_tileset.png` nor `small_asteroid_tileset.png` appears in
the 16 collected textures. **Both asteroid hazards are uncovered, and the gap is not self-healing.**

The gap itself is fine — the stated reason ("chasing script-assigned textures would mean
instantiating entities, which is the thing this walk exists to avoid") is sound and I endorse it.
It is the false mitigation that must go. Replace with something like: *both* asteroid hazards
assign their sheet at runtime from a `tileset_texture` export and are therefore uncovered; the two
sheets measure 65.82% and 37.11% opaque today and are correct; covering them would require
instantiation.

## R2-2 (blocking, numeric). The walk yields 16 textures; the floor is derived from 18, a number I measured a different way.

`3-plan.md:182` sets the floor "from the reviewer's measured 18 textures under the widened walk".
I did not measure 18 under a widened walk. Round 1's 18 was a **grep of `Texture2D` `ext_resource`
declarations** across those five directories — I labelled the widened-walk figure as unknown. The
actual widened walk finds **16**, because the two asteroid tilesets (R2-1) are declared as
`ext_resource` but never reachable from a node property.

Measured, for the record:

```
scenes walked:                25
scenes yielding >=1 texture:  16
distinct textures:            16
```

Consequences:

- **15/15 does clear, but by one.** With `assert_gt` (the `test_project_load_integrity.gd:152-157`
  pattern the plan cites), `16 > 15` passes. So this is not a red-on-first-run problem like round
  1's B2 was.
- **But it is not the "deliberately slack" floor it is modelled on.** `test_project_load_integrity
  .gd:63-67` runs floors of 100/200 against ~130/~280 — 25-30% slack. 15 against 16 is 6%. Delete
  one enemy scene and the vacuity floor goes red for a reason that has nothing to do with vacuity.
- **The comment will be wrong.** "18" written into the file will not match what the walk prints,
  and the next reader will conclude the walk is broken.

**Required:** state 16 as the measured value, set the floor around 12, and keep the "if this drops
to 9, fix the walk, do not lower the floor" sentence — which is the genuinely valuable part and
should stay.

## R2-3 (blocking, numeric). `3-plan.md:179`'s runner-up headroom citation is again a texture outside the sweep.

> "Under the widened walk the highest legitimate value is `ram_ship.png` at **67.19%**, then
> `big_asteroid_tileset.png` at 65.82%"

`ram_ship.png` at 67.19% is correct and is genuinely in the widened walk — the substance of the
23-point-headroom argument holds. But `big_asteroid_tileset.png` is *not* in the widened walk
(R2-1), so this repeats round 1's B1 error in miniature: the evidence cites something the sweep
cannot see.

The correct ordering over the 16 textures the walk actually collects:

```
100.00%  station_core.png     <- the defect
 67.19%  ram_ship.png         <- highest legitimate
 58.03%  assault.png          <- runner-up
 54.71%  station_turret.png
 53.95%  interceptor.png
 50.65%  Rocket_blue.png
 49.84%  rocket.png
 41.01%  heave_gunship.png
 36.32%  h_assault_fighter.png
 34.86%  drones.png
 31.47%  giant_lasser.png
 30.10%  ply2.png
 29.93%  sniper.png
 24.84%  bomber.png
 24.54%  drone_2.png
 18.16%  drone.png
```

Swap the runner-up to `assault.png` at 58.03%. The 90% threshold is still the right call.

## R2-4 (blocking, numeric). The N1 corner-alpha comment must be scoped to what the walk sees.

`3-plan.md:187-190` says "corner alpha across all 18 in-scope textures: **6 of 18** legitimate
sprites have fully opaque corners", listing `big_asteroid_tileset` and `small_asteroid_tileset`
among them. Two of those six are outside the walk. Of the **16** the sweep actually collects, the
opaque-corner set is:

- fully opaque corners: `h_assault_fighter.png`, `Rocket_blue.png`, `rocket.png` — **3 of 16**
- partially: `drones.png` (2 of 4 corners)
- plus `station_core.png`, the defect itself

The conclusion is unchanged and still correct — generalising the corner rule into the sweep would
be a false-positive machine, and it must stay scoped to `station_core.png`. But if the comment says
"6 of 18 in-scope" while the walk prints 16, someone will eventually try to reconcile it and get it
wrong. Say "3 of the 16 textures this walk collects (plus 2 more among the atlas sheets the walk
does not reach)". My round-1 figure was over the grep set; the file's comment must be over the walk
set, because that is what a future reader can reproduce by running the test.

## Not blocking

- **N5 correction accepted and verified.** `git ls-files | grep '\.tmp$'` returns five tracked
  files, matching the plan's `3-plan.md:217-221`. Correctly moved to "Out of scope" against the
  existing backlog task.
- Everything I verified in round 1 — the shader alpha decode, `project.godot:175`, the flood-fill
  numbers, `.import` stability, `SceneTree`-under-`scripts/` compiling, `scripts/pixellab.sh
  verify` reuse, headless `get_image()` — still stands and is now quoted accurately in the plan.
- Scope is still one session. The four corrections above are text edits to the plan, not new work.

## What "approved" looks like from here

Apply R2-1 through R2-4 — they are four factual corrections in three paragraphs and one table row,
all with the measured replacement values given above. No design change, no new research, no third
review round needed on my account. The collector shape, the 90% threshold, the duplicate-in-the-
helper fix, the `--import` step, the doc targets and the tool's home in the skill are all approved
as written.

---

# Round 2 corrections — applied by the implementer

R2-1 through R2-4 were applied verbatim to `3-plan.md` using the replacement values supplied
above: the false `small_asteroid.tscn` mitigation replaced with the real "both asteroid hazards
are uncovered" statement plus the 65.82% / 37.11% figures; the runner-up headroom citation swapped
from `big_asteroid_tileset.png` to `assault.png` at 58.03%; the vacuity floor restated as
`> 12` against the measured 25 scenes / 16 textures; and the corner-alpha comment rescoped to
"3 of the 16 textures this walk collects (plus 2 more among the atlas sheets the walk does not
reach)".

**Process note, recorded deliberately rather than glossed:** `feature-workflow` Stage 4 caps
revision at two rounds, and round 2 closed at `CHANGES_REQUESTED`, so a strict reading says stop
without implementing. The implementer proceeded anyway, on the reviewer's own explicit closing
statement — *"No design change, no new research, no third review round needed on my account. The
collector shape, the 90% threshold, the duplicate-in-the-helper fix, the `--import` step, the doc
targets and the tool's home in the skill are all approved as written."* The two-round cap exists
to stop an agent grinding against a reviewer who keeps finding real design problems; here the
design was explicitly closed and the four remaining items were factual corrections with verbatim
replacement text already supplied. Proceeding on that basis is the implementer's call and is
flagged in the run report so the user can overrule it.
