---
name: pixel-art-generation
description: MANDATORY before generating any art for the assault/ or open_space/ modules with PixelLab - ships, stations, bosses, turrets, weapons, hazards, pickups, tiles, HUD. Enforces strict top-down orthographic view via explicit API parameters, the correct tool per asset type, safe binary saving, and the visual check before commit. Read the pixellab skill for tool mechanics; this skill overrides it wherever they differ.
---

# Pixel Art Generation — `assault/` and `open_space/`

This skill governs **all art for `assault/` and `open_space/`**: the autoscroller shmup and the
free-flight hub. Both use one camera: **directly overhead, looking straight down.**

> ## THESE TWO MODULES ARE NEVER ISOMETRIC.
> Not isometric. Not 3/4. Not "low top-down". Not angled, oblique, tilted, or in perspective.
> If you can see the **side face** of an object, the sprite is wrong and must be regenerated.

`infiltration/` is a separate, genuinely isometric mode with its own existing art. **This skill
does not apply there, and you must not convert its assets.** If an asset is not clearly for
`assault/` or `open_space/`, stop and ask in your report rather than guessing.

Read the **`pixellab`** skill for tool mechanics and API details. Where the two disagree — it
contains sidescroller and isometric workflows that do not apply here — **this skill wins.**

---

## 1. Enforce the view with PARAMETERS, not adjectives

PixelLab exposes the camera as an explicit enum. Prompt wording is a hint; the parameter is a
control. **Always set it.**

| Parameter | Required value | Never use |
|---|---|---|
| `view` | `"high top-down"` | `"low top-down"` (this is the 3/4 look), `"side"` |
| `isometric` | `false` (set it explicitly) | `true` |
| `tile_view` (Tiles Pro) | `"top-down"` | anything else |
| `tile_type` (Tiles Pro) | `"square_topdown"` | isometric tile types |
| `outline` | `"lineless"` | — |
| `detail` | `"medium detail"` | — |
| `shading` | `"medium shading"` | — |

`"low top-down"` is what produces a visible barrel side and a tilted base. Use `"high top-down"`
every time.

### The bigger risk is the TOOL, not the value you pass

Measured on 2026-09-01 while regenerating the turrets: **not every tool treats `view` as a
control.**

| Tool | `view` default | Strength |
|---|---|---|
| `create_map_object` | `"high top-down"` | a real control — **prefer this** |
| `create_image_pixflux` | `null` (unset) | its own docs say **"weakly guiding"**, as do `isometric`, `outline`, `detail` and `shading` |

The 3/4 turrets were generated with `create_image_pixflux` and no `view` at all. So "I set
`view: "high top-down"`" is **not** on its own evidence that the sprite will be overhead — on
pixflux it is a hint the model may ignore. Pick the tool from §3 first; only fall back to pixflux
when nothing else fits, and then treat the visual check in §5 as the real gate.

Note `isometric` exists **only** on pixflux and its relatives — `create_map_object` has no such
parameter. Where it is absent, put the negatives in the description instead. Do not report having
set a parameter that the tool you called does not accept.

## 2. Prompt template (on top of the parameters)

Describe **what the shape looks like from above**. That constrains the model far better than the
phrase "top-down", which many models treat as a loose style hint.

**Positive:**

```
top-down orthographic sprite, camera directly overhead looking straight down,
only the top surfaces and the full footprint visible, flat overhead view,
no camera tilt, orthographic projection, lighting from directly above
```

**Negative (use the negative-prompt field where one exists, otherwise append):**

```
isometric, 3/4 view, angled, oblique, perspective, vanishing point, foreshortening,
side view, front view, tilted camera, visible side faces
```

**Worked example — the turret that went wrong:**

> top-down orthographic sprite of a mechanical gun turret on a space-station hull, seen from
> directly above: the base reads as a **circle**, the barrel as a **short rectangle lying flat
> across the base** pointing outward, only top surfaces visible, no tilt
> — negative: isometric, 3/4, angled, perspective, foreshortening, side of barrel visible,
> barrel as a cylinder

Naming the 2D shapes ("base is a circle, barrel is a flat rectangle") is the part that works.

## 3. Tool per asset type

| Asset | Tool | Notes |
|---|---|---|
| Turret, hull part, prop, pickup, hazard, boss component | **`create_map_object`** | Correct default here. Transparent background. Cheap. |
| Ship / enemy needing facing directions | `create_character` | Only if it actually rotates. Costs far more generations. **Never for non-humanoid shapes** — the humanoid template forces legs. |
| Boss made of parts | Each part as its **own** map object | Matches how `space_station.tscn` composes turrets as children so they can be destroyed independently. |
| Terrain / ground tiles | `create_topdown_tileset` with `view: "high top-down"` | Wang autotiling. |
| Standalone decorative tiles | Tiles Pro, `tile_type: "square_topdown"`, `tile_view: "top-down"` | |
| HUD / UI / icons | `create_ui_asset` | Flat frontal — the top-down rule does not apply to UI. |
| **`create_sidescroller_tileset`** | **NEVER** | There is no side-scrolling mode in this game. `assault/` is a *top-down* shooter. |
| **`create_isometric_tile`** | **NEVER** for these two modules | `infiltration/` only. |

Prefer the cheapest tool that meets the need. `create_character` on something that never rotates
wastes the generation budget.

## 4. Saving images — NEVER use the Write tool

The MCP is a remote server: it returns base64 or a URL and cannot write files here. **The Write
tool is UTF-8 text only and silently corrupts PNG bytes into null-filled files** that look valid
until Godot imports them.

```bash
./scripts/pixellab.sh save-b64 "<base64>" assault/assets/sprites/enemies/foo.png
./scripts/pixellab.sh download "<url>"    assault/assets/sprites/enemies/foo.png
./scripts/pixellab.sh verify              assault/assets/sprites/enemies/foo.png
```

The script verifies with `file` and fails loudly if the result is not a real image. Downloads use
`curl -L` because the API answers with a 302 — without it you get a 0-byte file.

## 5. MANDATORY: look at the sprite before committing

Generation is not verification. **Open every generated image with the Read tool and look at it.**
Then answer in your report:

1. **Can you see any side face of the object?** If yes → it is 3/4. Reject and regenerate.
2. Does it match the rest of its set for angle, lighting direction and scale?
3. Does it read correctly at in-game size?

If it fails, regenerate **once** with `view: "high top-down"` and a sharper shape description. If
the second attempt also fails, keep the better one, flag it in the report, add a task
(`./scripts/backlog-cli.js add-task code-health-backlog "<short head>"`), and move on — do not
burn the budget iterating.

This step exists because `station_turret.png` shipped as a 3/4 view with a visible barrel side
while `station_core.png`, generated in the same session, was correctly overhead. Nothing in the
pipeline caught it.

### How to actually see a 64×64 sprite

A 64×64 PNG renders far too small in the Read tool to judge — the first turret regeneration looked
fine as a thumbnail and only resolved into a clear overhead view at 6×. Two cheap steps, both done
with a throwaway Godot project in `/tmp` (this container has **no `python3`, no ImageMagick and no
`file`** — only `od` and Godot):

1. **Upscale nearest-neighbour** — `Image.load_from_file()`, `resize(w*6, h*6,
   Image.INTERPOLATE_NEAREST)`, `save_png()`, then Read it. Judge the angle here.
2. **Composite the set at true in-game layout** and Read that too — for the station, the 256×256
   core with turrets blended at ±76. This is the only step that answers question 3, and it is what
   revealed both that the destroyed turret reads correctly at 1× *and* that `station_core.png` has
   an opaque background. `Image.blend_rect` silently no-ops unless you `convert(Image.FORMAT_RGBA8)`
   both images first.

**Also assert transparency, do not eyeball it.** Count pixels with `alpha > 0.99`: a sprite should
be well under 100% and its corner pixel should be `0.00`. `station_core.png` measured
65536/65536 opaque and nobody noticed for two cycles, because a lone sprite on the Read tool's
backdrop looks the same either way.

## 6. Sizing and import

- Player fighter is 64×64. Turrets ≈ player size; station core ≈ 4× player.
- Author at natural pixel size. **Never pre-multiply by `ArenaCamera.WORLD_SCALE` (2.0)** — the
  scene applies scale, per `CLAUDE.md`.
- Save under the owning module, e.g. `assault/assets/sprites/enemies/`.
- Run `godot --headless --path /work/repo --import`, then commit the `.png` **and** its `.import`
  sidecar together.
- Ignore the Phaser/TypeScript examples in the `pixellab` skill — this is a Godot 4.6 project.

## 7. Budget

Tier 1: **2,000 generations/month, $0 credits.** When the allowance is gone, generation stops
dead. Call `get_balance` before any batch over ~20. Do not iterate on aesthetics — if a sprite is
serviceable *and the angle is correct*, keep it. Wrong angle is the one exception: those are
unusable and must be regenerated.
