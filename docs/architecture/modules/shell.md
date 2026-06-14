# Shell Modules — `boot/`, `cutscenes/`, `dialog/`

> Cross-cutting context: [`global/` module](./global.md) (autoloads consumed here) and the [game structure overview](../../game-structure.md) (how scenes hand off to each other).

## 1. Overview

These three small directories form the **app shell** — the non-gameplay scaffolding
that frames a play session:

- **`boot/`** — the launch entry point. `project.godot`'s `run/main_scene` points at
  `boot/boot.tscn`. On every launch it routes the player to the right starting scene.
- **`cutscenes/`** — self-contained cinematic scenes (intro, level-exit) plus a small
  base class and subtitle UI. Each cutscene plays a scripted beat sequence, then
  transitions into the next gameplay scene.
- **`dialog/`** — the *data* for spoken lines: per-character speaker resources and the
  conversation scripts that cutscenes (and gameplay) feed to the `DialogPlayer` autoload.

The shell owns none of the gameplay logic. It decides *where you start*, *what plays
between levels*, and *who says what* — then hands control to the assault / race /
infiltration / hub scenes documented in [game-structure.md](../../game-structure.md).
The dialog **runtime** (the `DialogPlayer` singleton, dialog box UI, and the
`Speaker/Line/Script` resource classes) lives under `global/`; see
[`global/` module](./global.md). `dialog/` here is just the authored content.

---

## 2. `boot/` — launch router

```
boot/
├── boot.tscn   # main_scene (uid://bj5rbqgudkfsg → this scene); root node "Boot"
└── boot.gd     # router script, runs for a single frame
```

`boot.gd` (`extends Node`) is a single-frame router. In `_ready()` it asks
`MissionState.has_cutscene_been_seen("intro_to_assault")`:

- **first launch** → `change_scene_to_file()` to
  `res://cutscenes/intro/intro_cutscene.tscn`
- **every launch after** → to `res://open_space/scenes/levels/sector_hub.tscn` (the hub)

The transition is `call_deferred`, so Boot never renders gameplay itself — it is a
pure dispatch node. The header comment marks it as the intended home for future
pre-game hooks (save-slot picker, login, splash).

**Game-loop hook:** Boot is the *entry* of the loop. It reads the `MissionState`
autoload (see [`global/`](./global.md)) and feeds into the cutscene/hub scenes
described in [game-structure.md](../../game-structure.md). Cutscene-seen flags are
the seam between Boot and `cutscenes/`.

---

## 3. `cutscenes/` — cinematic playback

```
cutscenes/
├── assets/
│   └── portraits/edith.png        # portrait art referenced by dialog speakers
├── base/
│   ├── cutscene_base.gd           # CutsceneBase (Node2D) — skip / persistence / next-scene
│   ├── dialog_presenter.gd        # DialogPresenter (CanvasLayer) — minimal subtitle UI
│   └── dialog_presenter.tscn
├── intro/
│   ├── intro_cutscene.gd          # IntroCutscene extends CutsceneBase
│   └── intro_cutscene.tscn        # next_scene → assault level_1; persistence_id "intro_to_assault"
└── level_exit/
    ├── level_exit_cutscene.gd     # LevelExitCutscene extends CutsceneBase
    └── level_exit_cutscene.tscn
```

**`base/cutscene_base.gd` — `class_name CutsceneBase extends Node2D`.** The shared
skeleton every cutscene subclasses. It provides:

- **Beat authoring:** subclasses override `_run_cutscene()` (called from `_ready()`)
  and compose the sequence with `await` plus the awaitable helpers `wait_secs()`,
  `tween_property()`, and `parallel_tween()`.
- **Skip:** `_unhandled_input` listens for `skip_action` (default `"ui_cancel"`) and
  calls `skip()`. Subclasses poll `is_skipped()` between beats and `return` early.
- **Persistence:** if the exported `persistence_id` is non-empty, finishing the scene
  calls `MissionState.mark_cutscene_seen(persistence_id)` — this is what Boot later
  reads. Skipped and natural completion both count.
- **Hand-off:** if the exported `next_scene_path` is non-empty, `_on_finish()` calls
  `change_scene_to_file()` to the next scene, and emits the `finished` signal.

**`base/dialog_presenter.gd` — `class_name DialogPresenter extends CanvasLayer`.** A
minimal, self-contained subtitle panel (`present(speaker, text, duration)` fades a
panel in, holds, fades out; awaitable). It is *independent* of the richer
`DialogPlayer` system — a lightweight fallback for cutscene captions. (Note: the intro
cutscene below actually drives full dialog through `DialogPlayer`; `DialogPresenter`
remains available for simpler captions.)

**`intro/intro_cutscene.gd` — `IntroCutscene`.** First-launch cinematic. Five beats:
setup → ship flies in while the camera zooms/recenters → a mission-briefing exchange
(`await DialogPlayer.play(preload("res://dialog/scripts/intro_briefing.tres"))`) →
camera/ship rotate to top-down → ship drifts forward, then `_on_finish()`. Its `.tscn`
sets `next_scene_path = assault/.../level_1.tscn` and `persistence_id =
"intro_to_assault"` — the exact id Boot checks. All distances/durations are exported
for designer re-timing.

**`level_exit/level_exit_cutscene.gd` — `LevelExitCutscene`.** Plays after Assault
Level 1 waves complete: a brief thruster warm-up, then ship boosts upward while the
screen fades to black, then `_on_finish()`. Routing is decided at runtime via a
`static var go_to_hub` flag set by the caller (`level_1_waves.gd`) *before* the
transition: first clear → infiltration scene, replay → hub. The flag resets to `false`
after it is read.

**Game-loop hook:** cutscenes sit *between* gameplay scenes. Boot launches the intro;
the intro transitions into assault; the level-exit cutscene transitions out of assault
into infiltration or the hub. They consume the `MissionState` and `DialogPlayer`
autoloads from [`global/`](./global.md) and slot into the scene flow in
[game-structure.md](../../game-structure.md).

---

## 4. `dialog/` — authored speaker & script data

```
dialog/
└── scripts/
    ├── intro_briefing.tres        # DialogScriptResource — played in the intro cutscene
    ├── level1_debrief.tres        # DialogScriptResource — post-Level-1 debrief
    └── speakers/
        ├── control.tres           # SpeakerResource "Control" (gold name, no portrait)
        └── edith.tres             # SpeakerResource "Edith" (portrait → cutscenes/assets/portraits/edith.png)
```

`dialog/` holds only **authored content** — `.tres` resources, no scripts of its own.
The resource *classes* (`SpeakerResource`, `DialogLineResource`, `DialogScriptResource`)
and the runtime that plays them live under `global/ui/dialog_system/` and the
`DialogPlayer` autoload; see [`global/` module](./global.md).

- **`scripts/speakers/*.tres` — `SpeakerResource`.** One file per character so a single
  edit propagates to every line they speak. Fields: `display_name`, `portrait`
  (optional `Texture2D`), `name_color`. `control.tres` is a portrait-less radio voice
  with a gold `name_color`; `edith.tres` is the protagonist with the Edith portrait.
- **`scripts/*.tres` — `DialogScriptResource`.** An ordered conversation: a `script_id`
  (for "seen this?" tracking), a `lines` array of inline `DialogLineResource`
  sub-resources (each referencing a speaker `.tres` + `text` + `side` + timing), and a
  `pause_gameplay` flag. `intro_briefing.tres` is the two-line Control/Edith exchange
  the intro cutscene plays with `pause_gameplay = false` (so the fly-in keeps moving);
  `level1_debrief.tres` is the matching post-mission exchange.

**Game-loop hook:** these resources are passed to `DialogPlayer.play(script)` (see
[`global/`](./global.md)), which is awaitable and resolves on `dialog_finished`.
Cutscenes `await` it mid-sequence; gameplay scenes can do the same. The speaker `.tres`
files are the shared character identities reused across every script — the content
layer feeding the runtime described in [game-structure.md](../../game-structure.md).

---

## 5. Links

- [`global/` module](./global.md) — the `DialogPlayer` and `MissionState` autoloads,
  the dialog runtime, and the `Speaker/Line/Script` resource classes these modules
  consume.
- [Game structure overview](../../game-structure.md) — the overall scene flow that
  Boot dispatches into and that cutscenes transition between.
