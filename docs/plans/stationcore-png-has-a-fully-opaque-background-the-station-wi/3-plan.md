# Station core sprite renders as an opaque grey square

## Problem

The level-1 mini-boss is meant to hang in space. Its sprite,
`assault/assets/sprites/enemies/station_core.png`, is **65536/65536 pixels at alpha 1.0** —
every pixel opaque, corner alpha 1.00. In the game it draws as a 256×256 flat grey card with a
station painted on it, with the starfield and every parallax layer behind it cut out in a hard
rectangle. Its own four turrets sit *on top* of that card at (±76, ±76), so the whole boss reads
as one grey block rather than a structure in space.

Nobody has seen it yet because no test and no gate step renders the station: `--import` never
loads a scene, `--quit` boots only `res://boot/…`, and the GUT suite asserts collision, damage
and timing. It surfaced only when the core and its turrets were composited by hand for the
`pixel-art-generation` skill's mandatory visual check.

After this change the station should read as a structure with sky behind and between its parts,
and nothing about its collision, damage, phases or timings should move at all.

## Design

### Chosen: alpha-key the existing artwork with a border flood fill, in-engine

`station_core.png` is clean flat pixel art — **20 distinct colours, no dithering, no
antialiasing**. The background is a single flat `#565657` making up 52.44% of the image. A
4-connected flood fill seeded from every border pixel, matching `#565657` **exactly**, reaches
34324 of the 34365 background-coloured pixels; the other 41 are enclosed by the hull and are
hull detail, not sky (research finding 1: this is precisely the case where a global colour key
punches holes and a flood fill does not).

Erased pixels keep their RGB and get `a = 0`. Research finding 2: `station_core.png.import`
already carries `process/fix_alpha_border=true`, which repaints invisible pixels with their
visible neighbours' colour at import time, and `mipmaps/generate=false`; `project.godot:175`
sets `default_texture_filter=0` (Nearest). Three independent reasons the classic grey-fringe
artefact cannot appear here, so zeroing RGB would buy nothing and would make the PNG diff
"everything changed" instead of "alpha changed".

**Alternatives rejected:**

| Alternative | Why not |
|---|---|
| Regenerate with `create_map_object` (transparent by construction) | Discards artwork the four already-regenerated turrets were designed to match, spends a capped and non-refundable monthly allowance (1956/2000 left, resets 2026-09-24), and cannot be undone if the new core is worse. The existing art is *correct* — top-down, right palette, right silhouette. Only its background is wrong, and that is mechanical to remove |
| Regenerate with `create_image_pixflux(..., no_background=True)` | Same objection. The flag is the right fix for *future* assets (see "Prevention" below), not for this one |
| PixelLab's own "Remove background" tool | Research finding 4: Aseprite/Pixelorama extensions only, not in the web API and not in this container's MCP tool list. There is no API call to make |
| Global colour key on `#565657` | Research finding 1 + the measurement: would punch 41 transparent holes through the hull |
| 8-connected flood fill | Research finding 5. Can leak through a one-pixel diagonal seam and eat the interior; buys at most 41 px here, all of which should stay anyway |
| A shader that discards a colour at runtime | Pays per-pixel every frame forever to avoid a one-time edit, and leaves the asset wrong for every other consumer |
| Hand-edit the PNG with the Write tool | `scripts/pixellab.sh`'s header: Write is UTF-8 only and silently corrupts PNG bytes. Also there is no image editor in this container (no `python3`, no ImageMagick, not even `file`) |

### The tool

The edit is performed by a small committed script rather than a throwaway one in `/tmp`, for the
same reason `scripts/pixellab.sh`, `scripts/fetch-page.sh` and `scripts/backlog-cli.js` exist:
the operation touches binary data, will recur (research finding 3 — every future
`create_image_pixflux` call that forgets `no_background` reproduces this exact defect), and a
committed script is reviewable while a `/tmp` heredoc is not.

- **`scripts/lib/strip_sprite_bg.gd`** — a `SceneTree` script. Godot is the only image library
  in this container, so `Image.load_from_file()` / `Image.save_png()` is the whole dependency
  list. Argument shape: `<in.png> <out.png> [--dry-run]` via `OS.get_cmdline_user_args()`.
  1. Load, `convert(Image.FORMAT_RGBA8)`.
  2. Read the four corner pixels. **Refuse to run unless all four are the same colour at alpha
     1.0** — the script never guesses which colour is the background.
  3. 4-connected BFS from every border pixel whose RGBA matches that colour exactly; set `a = 0`
     on each, leave RGB.
  4. **Refuse to write if the fill covers more than 95% of the image** — that means the "corner
     colour" is the subject, not the background, and the result would be an empty sprite.
  5. Print removed count, enclosed-and-kept count, and before/after opaque fraction. `--dry-run`
     stops before saving, so the numbers can be checked before anything is written.
- **`scripts/strip-sprite-bg.sh`** — the wrapper the agent and a human actually call, in the
  `scripts/pixellab.sh` house style (`set -euo pipefail`, `die()`, verify before reporting
  success). Runs the `.gd` under `godot --headless`, then calls `scripts/pixellab.sh verify` on
  the output so the PNG is magic-byte-checked by the existing code rather than a second copy of
  it. Writing in place (`out` defaults to `in`) is the normal case.

### Prevention

`.claude/skills/pixel-art-generation/SKILL.md` gains a rule that `create_image_pixflux` /
`create_image_pixen` / `create_image_pro` **must** pass `no_background: true` for anything drawn
over the game world, with the measured symptom named. That is what stops the next asset landing
with the same defect; the test below is what catches it if the rule is ignored.


The same skill section gains `strip-sprite-bg.sh` as the **named remedy when the transparency
assertion fires** (review N2). Without that, "Prevention" and "the tool will recur" argue against
each other: if every future call passes the flag, the tool never runs again. Its real job is
recovery for art that is already generated and already art-directed — which is exactly the case
here — so it belongs next to the assertion that detects that case, not in a drawer.

## Build sequence

1. **Write the failing test** `tests/integration/test_entity_sprite_transparency.gd` (shape below)
   and watch it fail on `station_core.png` and nothing else.
2. **Write `scripts/lib/strip_sprite_bg.gd` + `scripts/strip-sprite-bg.sh`.** Exercise both
   guards by hand (a sprite with mismatched corners must be refused; `--dry-run` must not write).
3. **Visual check, before.** Composite the core with its four turrets at (±76, ±76) over a dark
   backdrop into `/tmp/station_before.png` and look at it — this is the picture the bug report
   describes, and the baseline for step 5. The compositor reads the source PNGs with
   `Image.load_from_file()`, not through `res://`, so no import is needed for it.
4. **Apply the fix** in place to `assault/assets/sprites/enemies/station_core.png`, then
   **`godot --headless --path . --import`** before re-running anything (review B4). A non-editor
   run resolves the texture through the `[remap] path` in the `.import` file to
   `.godot/imported/station_core.png-c74e5cbcc2c1eae671965ff086481b5a.ctex` and never re-imports;
   the staleness check lives in a `.md5` sidecar that run does not consult. Without the explicit
   import the test reads the old 100%-opaque `.ctex`, still fails, and the failure looks like a
   bug in a correct flood fill. Re-run the test; it must now pass.
5. **Visual check, after.** Same composite into `/tmp/station_after.png`, opened and looked at.
   Mandatory per `CLAUDE.md`. If the hull has holes or a grey fringe, the fix is wrong and step 4
   is reverted (`git checkout` the PNG) rather than shipped.
6. **Prevention + docs.** Named targets, because `updating-project-docs` will not prompt for the
   last two (review N3):
   - `.claude/skills/pixel-art-generation/SKILL.md` — the `no_background: true` rule and the
     `strip-sprite-bg.sh` remedy, both in §5 beside the existing transparency assertion.
   - `assault/scenes/enemies/space_station/ENEMY.md` — the sprite is now keyed, with the numbers.
   - `CLAUDE.md` — its tests bullet enumerates the invariant tests **ordinally** ("a second
     invariant check", … "a seventh"); this is the eighth and the list is wrong without it.
   - `tests/README.md` — the "Coverage today" list, plus the `get_image()` aliasing trap (B3).
7. Gate (`bash /agent/verify.sh`), backlog, report. Commit the engine-minted
   `scripts/lib/strip_sprite_bg.gd.uid` sidecar rather than leaving it untracked (review N4); it
   is minted by the `--import` in step 4, never hand-typed.

## Test plan

`tests/integration/test_entity_sprite_transparency.gd` — an **invariant** test (asserts intent,
not today's behaviour), in the family of `test_enemy_hurtbox_geometry.gd`.

### What it walks, and why that shape

Roots `assault/scenes/{enemies,player,projectiles,hazards,allies}`. Each `.tscn` is `load()`ed as
a `PackedScene` and inspected through **`PackedScene.get_state()`** — a `SceneState` read, so
nothing is instantiated and no `_ready()` runs (`space_station.tscn`'s `_ready()` builds a bullet
pool and four behaviour nodes).

**A `Sprite2D.texture`-only walk is not enough and the reviewer proved it: it finds 9 textures,
and `player/`, `projectiles/`, `hazards/` and `allies/` contribute exactly zero** (review B1).
Most entities here are `AnimatedSprite2D` + `SpriteFrames`, often over an `AtlasTexture`:
`player_fighter.tscn:6`, `ram_ship.tscn:69`, `light_assault_ship.tscn:72`, `ally_fighter.tscn:30`,
`homing_missile.tscn:50`. Naming a root that contributes nothing is worse than omitting it,
because the file then reads as though the player is covered. So the collector handles three cases:

| Node type | Property | Resolution |
|---|---|---|
| `Sprite2D` | `texture` | direct |
| `AnimatedSprite2D` | `sprite_frames` | every animation × every frame via `SpriteFrames.get_animation_names()` / `get_frame_count()` / `get_frame_texture()` |
| either, yielding an `AtlasTexture` | — | measured over **the whole atlas sheet** (`.atlas`), not the region. Simpler, and the defect being guarded against is a painted sheet background, which is a whole-sheet property |

Textures are de-duplicated by `resource_path`, so a sheet shared by ten frames is measured once.

**Both asteroid hazards are uncovered, and the gap is not self-healing** (review R2-1).
`big_asteroid.tscn:27` and `small_asteroid.tscn:30` each have a bare `Sprite2D` with **no**
stored `texture`; each sheet arrives at runtime from the root's `tileset_texture` export
(`:24` — and note `small_asteroid.tscn` points at `small_asteroid_tileset.png`, not the big
one, so it is the same gap rather than a mitigation). Race scenes reference them too but are out
of scope below, so they give the gate nothing either. The two sheets measure **65.82%** and
**37.11%** opaque today and are correct. This is accepted and stated plainly in the test file
rather than worked around: covering them would mean instantiating entities, which is the thing
this walk exists to avoid.

Instanced sub-scenes are **not** recursed into, and the reviewer confirmed this is structurally
enforced rather than merely intended: `SceneState.get_node_type()` returns `""` for an instanced
node (`Turret0`…`Turret3`), so the walk *cannot* accidentally recurse. `station_turret.tscn` lives
under a root and is walked in its own right.

`assault/scenes/race/` and `assault/scenes/levels/` are **out of scope and the file says why**:
racers are drawn on an opaque track surface and level scenes legitimately hold full-bleed
backdrops (`stand.png`, referenced by `race_level_1.tscn`, is 512×512 at 100% opaque and correct).

**Opacity is measured from `Image.get_data()`** after `convert(FORMAT_RGBA8)`, stepping every 4th
byte, not with 65536 `get_pixel()` calls per texture.

**Every `get_image()` result is `duplicate()`d inside the helper, and the file carries a header
note saying why** (review B3). `CompressedTexture2D` caches its decoded `Image` and returns *the
same object* on every call — verified: `second get_image() is same instance: true`. Mutating it
poisons every later reader in the same GUT process, including the second half of the boundary test
itself. This is the same aliasing trap `test_enemy_hurtbox_geometry.gd:224-230` documents for the
shared `RectangleShape2D_ss`. Duplicating in the helper rather than at the call site means no
future caller can get it wrong.

### The tests

| Test | Asserts | Why it can fail |
|---|---|---|
| `test_no_entity_sprite_is_a_solid_rectangle` | every in-scope texture is < 90% fully-opaque pixels, reporting each violator with its percentage | Fails today on `station_core.png` at 100.00%. Under the widened walk the highest legitimate value is `ram_ship.png` at **67.19%**, then `assault.png` at 58.03% — 23 points of headroom, and the one wrong sprite is at 100.00%, not at 89% |
| `test_the_station_core_has_sky_around_it` | `station_core.png` specifically: all four corner pixels at alpha 0, and opaque fraction below 0.60 (measured post-fix: 47.63%) | Names the boss, so a regression points at the asset instead of at a generic sweep. Fails today on both halves |
| `test_the_check_rejects_a_sprite_with_a_painted_background` (**boundary**) | takes a **`duplicate()`** of the known-good `station_turret.png` image, forces every pixel to alpha 1, asserts the helper reports a violation — and that the original texture, re-read afterwards, is still not a violation | The test that proves the sweep can fail at all. Without it, a helper returning 0.0 for everything passes silently. The second half additionally proves the duplication actually worked |
| `test_the_walk_found_the_entity_scenes` (**vacuity floor**) | more than 12 scenes and more than 12 distinct textures | `test_project_load_integrity.gd:152-157`'s pattern (`assert_gt`, strictly greater). The reviewer built the widened collector and measured **25 scenes walked, 16 yielding a texture, 16 distinct textures** — so the floor carries the 25-30% slack that file's 100/200-against-130/280 floors do, not the 6% that a floor of 15 against 16 would. **Not** the 9 the narrow walk found: if a future change drops it to 9, fix the walk, do not lower the floor (review B2, R2-2) |

### One thing the file must record so it is not "improved" later (review N1)

The four-corners-at-alpha-0 assertion is scoped to `station_core.png` **alone**, deliberately.
The reviewer measured corner alpha over the set the walk actually collects: **3 of the 16
textures this walk collects have fully opaque corners** — `h_assault_fighter`, `Rocket_blue`,
`rocket` — plus `drones` at 2 of 4, plus 2 more (`big_asteroid_tileset`,
`small_asteroid_tileset`) among the atlas sheets the walk does not reach. They are atlas sheets
whose cells butt against the sheet edge. The comment must be stated over the **walk** set, not a
grep set, because that is the number a future reader can reproduce by running the test
(review R2-4). Generalising the corner rule into the sweep
would be a false-positive machine. Those numbers go in the file as a comment, the way
`test_enemy_hurtbox_geometry.gd:9-20` records the rejected 88×240 proposal, so the decision is a
gate rather than prose someone re-litigates.

## Risks

| Risk | Check |
|---|---|
| The fill leaks through a gap and eats hull interior | Measured: 4-connected reaches 34324 px and no more, 41 enclosed px survive, post-fill opaque fraction 47.63% — independently reproduced by the reviewer. Step 5's visual check is the real proof. Revert is one `git checkout` of a single PNG |
| A grey fringe appears around the hull | Nearest filtering (`project.godot:175`) + `fix_alpha_border=true` + no mipmaps. Confirmed by looking at step 5's composite |
| The hit-flash shader re-opaques the background | `hit_flash_vs.tres` is a `VisualShader` whose `If` node feeds fragment output **port 0 only** (`COLOR.rgb`); port 1 (`COLOR.a`) is unconnected. Reviewer decoded `nodes/fragment/connections` independently and agrees. Transparent stays transparent while flashing |
| The 240×240 `HurtBox`/`CollisionShape2D` no longer matches what is visible | Neither shape is touched. `test_enemy_hurtbox_geometry.gd` compares the hurtbox to the *body collision shape*, not to the sprite, and its own header says "do not mistake this sweep for an art check". Sprite pixels have never fed collision here |
| The test reads a stale `.ctex` and fails on a correct fix | Step 4's explicit `--import`. The `.ctex` filename hash derives from the *source path*, not its contents, so the `.import` sidecar itself does not change |
| UID churn | Only PNG bytes change. No `.import`, no `.tscn`, no existing `uid://` is edited. One new `.gd.uid` is minted by the engine and committed |
| A new `.gd` under `scripts/` breaks the load-integrity sweep | It walks `res://` for `.gd` with `SKIPPED_DIRS = ["addons", ".godot", ".git", ".import"]`, so `scripts/lib/strip_sprite_bg.gd` **will** be compiled by it — `scripts/` holds no `.gd` today, so this is a first. The reviewer dropped a stub `extends SceneTree` there and confirmed `can_instantiate() == true`. Risk closed, not merely flagged |
| The new test is slow | ~18 textures, largest 1408×384. Byte-stepping `get_data()` rather than `get_pixel()` keeps it well under a second |

## Out of scope

- Regenerating any art. No PixelLab generation happens in this change.
- The four unreferenced 100%-opaque racer sprites (`garuga`, `green_day`, `normandy`,
  `road_hog`). No `.tscn`/`.tres` references any of them; they are spare art, and deleting or
  fixing dead assets is a separate call for the user.
- `assault/scenes/race/` and `assault/scenes/levels/` sprite hygiene.
- Any change to the station's collision, health, phases, timings or turret layout.
- Re-cropping the sprite or shrinking it to its new visible bounds.
- The tracked editor-scratch `.tscn*.tmp` files (review N5). Already covered by the existing
  backlog task `two-committed-tscn-tmp-files-duplicate-lightassaultship-s-ui` — though note for
  the report that there are **five** tracked, not two: the two under `light_assault_ship/` plus
  `assault/scenes/player/player_fighter.tscn6026545143.tmp` and two under
  `infiltration/scenes/entities/player/`.
