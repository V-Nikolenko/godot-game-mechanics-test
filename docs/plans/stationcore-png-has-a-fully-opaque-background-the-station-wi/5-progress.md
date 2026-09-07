# Progress

- [x] Step 1 — failing test `tests/integration/test_entity_sprite_transparency.gd`.
      Fails on `station_core.png` (100.00% opaque, 4/4 opaque corners) and **nothing else**;
      the boundary case and the vacuity floor pass. Walk verified independently against the
      plan's numbers: **25 scenes walked, 16 distinct textures**, `ram_ship.png` 67.19% highest
      legitimate, `assault.png` 58.03% runner-up, 3 of 16 with 4/4 opaque corners
      (`h_assault_fighter`, `Rocket_blue`, `rocket`) plus `drones` at 2/4. Every figure in the
      file's header comment is reproducible by running the walk.
      One thing the plan did not foresee: `Image.duplicate()` returns `Resource`, not `Image`, so
      `var copy := img.duplicate()` is a parse error under GUT's stricter warning load. Three
      sites now say `as Image`.
- [x] Step 2 — `scripts/lib/strip_sprite_bg.gd` + `scripts/strip-sprite-bg.sh`.
      Dry run on the real sprite reproduces the plan's numbers exactly: background `#565657ff`
      34365 px (52.44%), erased from the border 34324 px, **41 px enclosed and kept**, opaque
      100.00% -> 47.63%, nothing written. All four refusal paths exercised and each exits 1 with
      no output file: mismatched corners, fill over the 95% guard, an already-transparent corner,
      and a missing input.
- [x] Step 3 — `/tmp/station_before.png`: core + four turrets at (±76, ±76) over a starfield,
      in `space_station.tscn`'s draw order (Sprite2D before Turrets, so turrets sit on top).
      Looked at: an unmistakable grey card punching a hard rectangle through the stars.
- [x] Step 4 — applied in place, then `godot --headless --path . --import`.
      Diffed against `git show HEAD:`: **34324 pixels changed alpha, 0 pixels changed RGB** —
      exactly the fill count, and the RGB is untouched as designed.
- [x] Step 5 — `/tmp/station_after.png`: the station now hangs in space with stars visible
      around and between its parts. Three checks, not one:
      * the composite at 1x — no grey card, no fringe;
      * a 4x zoom of the hull edge over a magenta checkerboard — hard pixel boundary, no halo,
        no partial alpha;
      * the **alpha silhouette** rendered as a black/white mask — a solid hole-free rounded
        square. Worth recording because the 4x zoom initially looked like the fill might have
        punched through a small dithered grille on the top-left panel; it had not. A
        connected-component map of the background colour settles it: **one** border-touching
        component of 34324 px, and 39 enclosed components totalling 41 px, none larger than 2 px.
        The grille's hatch is the artwork's own dither.
      Test re-run after the import: 4/4 passing, 12 asserts.
- [x] Step 6 — prevention + docs. Six files, not four: the plan's four plus two the plan did not
      name (`docs/architecture/PROJECT.md` and `docs/architecture/modules/assault.md` both
      enumerate the collision-geometry invariants and now carry the art one beside them).
      * `.claude/skills/pixel-art-generation/SKILL.md` — `no_background: true` is now mandatory
        for `create_image_pixflux`/`_pixen`/`_pro` on world art (§3), and `strip-sprite-bg.sh`
        is the named remedy when the transparency assertion fires (§5).
      * `assault/scenes/enemies/space_station/ENEMY.md` — the "still open" banner no longer
        lists the grey square; the sprite-provenance row records the keying with its numbers.
      * `CLAUDE.md` — the ordinal invariant list gains an eighth entry.
      * `tests/README.md` — "Coverage today", plus **two** new house rules: the
        `get_image()` aliasing trap (including that `Image.duplicate()` is typed `Resource`
        and needs `as Image`) and the stale-`.ctex` trap.
- [x] Step 7 — `bash /agent/verify.sh` -> **GATE PASS**, 38 scripts / 332 tests / 332 passing /
      1487 asserts. `bash scripts/check-test-leaks.sh` -> **LEAK CHECK PASS**.

**Resume at:** done.
**Deviations from plan:** the `as Image` cast noted above; nothing else.
