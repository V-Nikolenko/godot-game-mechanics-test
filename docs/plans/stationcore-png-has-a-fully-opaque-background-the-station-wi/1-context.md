# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/assets/sprites/enemies/station_core.png` | 256×256 sprite for the mini-boss hull | **The defect.** 65536/65536 px at alpha 1.0; corner alpha 1.00 |
| `assault/assets/sprites/enemies/station_core.png.import` | Godot texture import settings | `process/fix_alpha_border=true`, `compress/mode=0` (lossless), `mipmaps/generate=false` |
| `assault/scenes/enemies/space_station/space_station.tscn` | The boss scene | `Sprite2D` (no `scale`, no `region`) draws the texture 1:1 at the `CharacterBody2D` origin |
| `assault/scenes/enemies/space_station/station_turret.tscn` | The four turrets | 64×64 `station_turret.png`, instanced at `(±76, ±76)` inside `Turrets` |
| `project.godot:175` | `textures/canvas_textures/default_texture_filter=0` | **Nearest** filtering project-wide — no bilinear bleed of transparent-pixel RGB |
| `scripts/pixellab.sh` | Safe binary save/verify for PixelLab output | Existing "give the agent a script" precedent; has `sniff_magic()` for this minimal container |
| `tests/integration/` | Where the project's invariant tests live | Where the regression gate for this class of bug belongs |

## Measured facts (all measured this run, headless Godot 4.6.3, not inferred)

`station_core.png`:

- 256×256, **20 distinct colours** — flat pixel art, no dithering and no antialiasing.
- Background colour is `#565657`, **34365 px (52.44%)**.
- A 4-connected flood fill seeded from every border pixel, matching `#565657` **exactly**,
  reaches **34324** of those 34365 px. The remaining **41** px are enclosed by the artwork
  (interior detail) and would survive the fill untouched.
- So an exact-colour border flood fill removes 52.37% of the image and cannot punch a hole in
  the hull. There is no tolerance parameter to tune and no judgement in the threshold.

Project-wide PNG opacity sweep (176 files under `assault/`, `open_space/`, `global/`,
`infiltration/`, `boot/`, `cutscenes/`) — **of the 17 textures referenced by a `Texture2D`
`ext_resource` in a scene under `assault/scenes/{enemies,player,projectiles,hazards}`,
`station_core.png` is the only one at 100.00% opaque.** The next highest is `ram_ship.png` at
67.19%, then `big_asteroid_tileset.png` at 65.82%. Fully-opaque PNGs *are* common and correct
elsewhere in the project (mission-select thumbnails, menu backgrounds, `isometric_green.png`),
so any gate must be scoped to entity sprites, not to every `.png`.

Four racer sprites are also 100% opaque (`garuga`, `green_day`, `normandy`, `road_hog`) but
`grep` finds **no `.tscn`/`.tres` referencing any of them** — spare art, out of scope.

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `scripts/pixellab.sh` | The shape to copy for a new repo script: `set -euo pipefail`, `die()`, a verb argument, verify-before-success. Also proves `od` is the only binary-inspection tool here |
| `godot --headless -s <script.gd>` (a `SceneTree`) | Enough to load, edit and save an `Image` with no editor and no GUI — used for all four measurements above |
| `Image.load_from_file()` / `Image.save_png()` | Godot's own PNG round-trip; keeps the pipeline inside the engine rather than adding a dependency this container does not have (no `python3`, no ImageMagick, no `file`) |
| `tests/integration/test_enemy_hurtbox_geometry.gd` | The template for a project invariant test: enumerate real scenes, assert a property of each, plus one boundary case that proves the assertion can fail |
| `tests/integration/test_resource_uid_integrity.gd` | The template for a test that reads files off disk rather than through the resource cache |

## Conventions that constrain this

- **`assault/` is strict top-down orthographic** (`pixel-art-generation` skill). Any regenerated
  art must be `view: "high top-down"`, `isometric: false`.
- **A generated image must be opened and looked at before it is committed** — mandatory, and the
  reason this defect was found in the first place.
- The PixelLab allowance is capped and monthly (1956/2000 generations left, resets 2026-09-24).
  Spending is not free, and a regeneration is not reversible.
- `CLAUDE.md`: never hand-edit structured data; give the agent a script instead
  (`scripts/pixellab.sh`, `scripts/fetch-page.sh`, `scripts/backlog-cli.js` are the precedents).
- Tests are GUT under `tests/`; invariant tests assert intent, characterization tests pin
  today's behaviour.
- Never hand-type a `uid://`. Editing the PNG in place keeps `uid://dkimdnfmfcosy` and every
  `.import` file untouched, so `test_resource_uid_integrity.gd` is unaffected.

## Open questions for research

1. Alpha-key the existing art, or regenerate with `create_map_object`? The backlog note leaves
   both open. Which risks less, and what does the existing art actually look like?
2. When you zero the alpha of a pixel but leave its RGB, does anything downstream bleed the old
   background colour back into the sprite edge (texture filtering, mipmaps, premultiplied alpha)?
3. Is exact-colour flood fill the right algorithm for AI-generated pixel art, or is a tolerance
   needed?
4. Should the erased pixels' RGB be cleared to transparent black, or left as-is?
