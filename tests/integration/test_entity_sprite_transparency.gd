## Invariant test: no sprite an assault entity draws over the game world is a solid rectangle.
##
## NOT characterization. A sprite with a painted-in background renders as an opaque card that cuts
## a hard rectangle out of the starfield and every parallax layer behind it. That is a defect, not
## a quirk to pin.
##
## ── Why this file exists ─────────────────────────────────────────────────────────────────────
##
## `assault/assets/sprites/enemies/station_core.png` — the level-1 mini-boss hull — shipped at
## **65536/65536 pixels at alpha 1.0**, corner alpha 1.00. Its own four turrets, generated in the
## same session, are 54.71% opaque with corner alpha 0.00, which is what a sprite should look
## like. The cause was a PixelLab default: `create_image_pixflux` treats `no_background` as unset
## unless you pass it, and paints a background; `create_map_object` (which made the turrets) is
## transparent by construction, which is why nobody had to ask for it.
##
## It survived two full cycles unnoticed, because **nothing in the pipeline renders the station**.
## The gate's `--import` step never loads a scene, its `--quit` step boots only `res://boot/…`,
## and the GUT suite asserts collision, damage and timing. A lone sprite viewed on a light backdrop
## looks the same either way. It was found only when the core and its turrets were composited by
## hand for the `pixel-art-generation` skill's mandatory visual check.
##
## `.claude/skills/pixel-art-generation/SKILL.md` now requires `no_background: true` on every
## `create_image_pixflux` / `create_image_pixen` / `create_image_pro` call for world art. This file
## is what catches it when that rule is ignored.
##
## ── What is actually enforced, precisely ─────────────────────────────────────────────────────
##
## Fully-opaque-pixel fraction < `MAX_OPAQUE_FRACTION` (0.90) per texture. Deliberately loose, not
## an art-direction rule: the sprite that is wrong measures 100.00%, and the highest legitimate
## value in the sweep is `ram_ship.png` at 67.19%, then `assault.png` at 58.03% — 23 points of
## headroom. This file has no opinion on any sprite between 68% and 90%.
##
## The four-corners-at-alpha-0 assertion is scoped to `station_core.png` **alone, deliberately.
## Do not generalise it into the sweep.** Corner alpha measured across the set this walk collects:
## 3 of 16 legitimate textures have fully opaque corners — `h_assault_fighter.png`,
## `Rocket_blue.png`, `rocket.png` — plus `drones.png` at 2 of 4, plus 2 more
## (`big_asteroid_tileset.png`, `small_asteroid_tileset.png`) among the atlas sheets this walk
## does not reach. They are atlas sheets whose cells butt against the sheet edge, and they are
## correct. A generalised corner rule would be a false-positive machine.
##
## ── What the walk reaches, and what it knowingly does not ────────────────────────────────────
##
## Scenes are read through `PackedScene.get_state()`, never instantiated: `space_station.tscn`'s
## `_ready()` alone builds a 48-bullet pool and four behaviour nodes. Three node shapes are
## resolved, because a `Sprite2D.texture`-only walk finds **9** textures and `player/`,
## `projectiles/`, `hazards/` and `allies/` contribute exactly **zero** to it — most entities here
## are `AnimatedSprite2D` + `SpriteFrames`, frequently over an `AtlasTexture`:
##
##   * `Sprite2D` → `texture`
##   * `AnimatedSprite2D` → `sprite_frames`, every animation x every frame
##   * either, yielding an `AtlasTexture` → its `.atlas`, measured over the **whole sheet** rather
##     than the region. Simpler, and a painted sheet background is a whole-sheet property.
##
## Instanced sub-scenes are not recursed into, and that is structurally enforced rather than
## merely intended: `SceneState.get_node_type()` returns `""` for an instanced node, so the walk
## *cannot* accidentally recurse into `Turret0`…`Turret3`. `station_turret.tscn` lives under a
## scope root and is walked in its own right.
##
## **Both asteroid hazards are uncovered, and the gap is not self-healing.**
## `big_asteroid.tscn:27` and `small_asteroid.tscn:30` each carry a bare `Sprite2D` with no stored
## `texture`; each sheet is assigned at runtime from the root's `tileset_texture` export, and
## `small_asteroid.tscn` points at `small_asteroid_tileset.png`, not the big one — so it is the
## same gap, not a mitigation for the other. The race scenes reference them but are out of scope.
## The two sheets measure 65.82% and 37.11% opaque today and are correct. Covering them would mean
## instantiating entities, which is the thing this walk exists to avoid.
##
## `assault/scenes/race/` and `assault/scenes/levels/` are out of scope on purpose: racers are
## drawn on an opaque track surface, and level scenes legitimately hold full-bleed backdrops —
## `stand.png`, referenced by `race_level_1.tscn`, is 512x512 at 100% opaque and correct.
##
## ── The aliasing trap, and why the helper duplicates ─────────────────────────────────────────
##
## `Texture2D.get_image()` on a `CompressedTexture2D` returns **the same `Image` instance on every
## call** — verified: `second get_image() is same instance: true`. Mutating it poisons every later
## reader in the same GUT process, including the second half of `test_the_check_rejects_a_sprite_
## with_a_painted_background`. So `_image_of()` duplicates, and every caller goes through it; the
## seam that takes a raw `Image` is `_opaque_fraction()`, which never mutates. Same class of trap
## as the shared `RectangleShape2D_ss` sub-resource documented at
## `test_enemy_hurtbox_geometry.gd:224-230`.
extends GutTest

## Scene roots holding entities drawn over the game world. Every one of these contributes at least
## one texture; if a future edit makes one decorative, say so here rather than leaving it listed.
const SCOPE_ROOTS: Array[String] = [
	"res://assault/scenes/enemies",
	"res://assault/scenes/player",
	"res://assault/scenes/projectiles",
	"res://assault/scenes/hazards",
	"res://assault/scenes/allies",
]

## A sprite over 90% fully-opaque almost certainly has a painted background. See the header for
## why the bound is this loose.
const MAX_OPAQUE_FRACTION := 0.90

const STATION_CORE := "res://assault/assets/sprites/enemies/station_core.png"
const STATION_TURRET := "res://assault/assets/sprites/enemies/station_turret.png"

## Vacuity floors, `assert_gt` (strictly greater), modelled on `test_project_load_integrity.gd:63-67`.
## Measured today: 25 scenes walked, 16 yielding a texture, 16 distinct textures. These carry that
## file's 25-30% slack rather than sitting one above the real value. **If the texture count drops
## to 9, the walk broke and lost every non-`Sprite2D` entity — fix the walk, do not lower the floor.**
const MIN_SCENES := 12
const MIN_TEXTURES := 12

var _scenes: Array[String] = []
## `resource_path` -> `Texture2D`. De-duplicated, so a sheet shared by ten frames is measured once.
var _textures: Dictionary = {}
var _walk_done := false


func before_each() -> void:
	_walk()


## Collect every `.tscn` under the scope roots and every texture reachable from a sprite node in
## it. Idempotent: only the first caller pays for it.
func _walk() -> void:
	if _walk_done:
		return
	_walk_done = true
	for root: String in SCOPE_ROOTS:
		_collect_scenes(root)
	for path: String in _scenes:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		_collect_textures(packed.get_state())


func _collect_scenes(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_scenes(full)
		elif entry.ends_with(".tscn"):
			_scenes.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


## Read a scene's node table without instantiating it. `get_node_type()` is `""` for an instanced
## sub-scene node, so neither branch below can fire on one — the walk cannot recurse by accident.
func _collect_textures(state: SceneState) -> void:
	for i in range(state.get_node_count()):
		var type := state.get_node_type(i)
		if type != "Sprite2D" and type != "AnimatedSprite2D":
			continue
		for p in range(state.get_node_property_count(i)):
			var prop_name := state.get_node_property_name(i, p)
			var value: Variant = state.get_node_property_value(i, p)
			if type == "Sprite2D" and prop_name == "texture":
				_register(value)
			elif type == "AnimatedSprite2D" and prop_name == "sprite_frames":
				_register_frames(value)


func _register_frames(value: Variant) -> void:
	var frames := value as SpriteFrames
	if frames == null:
		return
	for anim: StringName in frames.get_animation_names():
		for f in range(frames.get_frame_count(anim)):
			_register(frames.get_frame_texture(anim, f))


## Resolve an `AtlasTexture` to its whole sheet, then key by `resource_path`.
func _register(value: Variant) -> void:
	var texture := value as Texture2D
	if texture == null:
		return
	var atlas := texture as AtlasTexture
	if atlas != null:
		_register(atlas.atlas)
		return
	if texture.resource_path.is_empty():
		return
	_textures[texture.resource_path] = texture


## A private copy of a texture's pixels. NEVER hand a caller `texture.get_image()` directly — see
## the header's aliasing note.
func _image_of(texture: Texture2D) -> Image:
	var img := texture.get_image()
	if img == null:
		return null
	return img.duplicate() as Image


## Fraction of pixels at alpha 255, read by stepping `get_data()` rather than with one
## `get_pixel()` call per pixel — the largest sheet in scope is 1408x384.
func _opaque_fraction(img: Image) -> float:
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8)
	var bytes := copy.get_data()
	var total := bytes.size() / 4
	if total == 0:
		return 0.0
	var opaque := 0
	for i in range(3, bytes.size(), 4):
		if bytes[i] == 255:
			opaque += 1
	return float(opaque) / float(total)


func _corner_alphas(img: Image) -> Array[float]:
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8)
	var w := copy.get_width()
	var h := copy.get_height()
	return [
		copy.get_pixel(0, 0).a,
		copy.get_pixel(w - 1, 0).a,
		copy.get_pixel(0, h - 1).a,
		copy.get_pixel(w - 1, h - 1).a,
	]


# ─────────────────────────────────────────────────────────────────────────────────────────────
# The sweep
# ─────────────────────────────────────────────────────────────────────────────────────────────

func test_no_entity_sprite_is_a_solid_rectangle() -> void:
	var violations: Array[String] = []
	for path: String in _textures:
		var img := _image_of(_textures[path])
		if img == null:
			violations.append("%s -> get_image() returned null" % path)
			continue
		var fraction := _opaque_fraction(img)
		if fraction >= MAX_OPAQUE_FRACTION:
			violations.append("%s -> %.2f%% fully opaque" % [path, fraction * 100.0])
	assert_eq(
		violations,
		([] as Array[String]),
		(
			"These sprites are drawn over the game world but are near-solid rectangles, so they "
			+ "cut a hard hole in the starfield behind them. A world sprite must be generated "
			+ "with a transparent background (`create_map_object`, or `no_background: true`); if "
			+ "it already exists, run `./scripts/strip-sprite-bg.sh <png>`. Violations: %s"
		) % [violations]
	)


func test_the_station_core_has_sky_around_it() -> void:
	var texture := _textures.get(STATION_CORE) as Texture2D
	assert_not_null(texture, "station_core.png is not reachable from any scene in scope")
	if texture == null:
		return
	var img := _image_of(texture)
	assert_not_null(img, "station_core.png: get_image() returned null")
	if img == null:
		return
	assert_eq(
		_corner_alphas(img),
		([0.0, 0.0, 0.0, 0.0] as Array[float]),
		"station_core.png: every corner must be transparent sky, not painted background"
	)
	assert_lt(
		_opaque_fraction(img),
		0.60,
		(
			"station_core.png must be a station with sky around and between its parts, not a "
			+ "256x256 card. Measured after the background was keyed out: 47.63%"
		)
	)


## The boundary case, and the reason this file is not a formality: a sprite WITH a painted
## background must fail the predicate above. Without it, a `_opaque_fraction()` that returned 0.0
## for everything would pass the sweep silently.
##
## Operates on a `duplicate()` (via `_image_of`), never on `get_image()`'s cached instance. The
## second half re-reads the real texture afterwards and asserts it is still clean — that is what
## proves the duplication actually worked, rather than merely being written down.
func test_the_check_rejects_a_sprite_with_a_painted_background() -> void:
	var texture := _textures.get(STATION_TURRET) as Texture2D
	assert_not_null(texture, "station_turret.png is not reachable from any scene in scope")
	if texture == null:
		return

	var clean := _image_of(texture)
	assert_lt(
		_opaque_fraction(clean),
		MAX_OPAQUE_FRACTION,
		"station_turret.png is the known-good control and must pass before it is corrupted"
	)

	var painted := _image_of(texture)
	painted.convert(Image.FORMAT_RGBA8)
	for y in range(painted.get_height()):
		for x in range(painted.get_width()):
			var c := painted.get_pixel(x, y)
			c.a = 1.0
			painted.set_pixel(x, y, c)
	assert_eq(
		_opaque_fraction(painted),
		1.0,
		"the corrupted control must be 100% opaque, or the sweep is not being given a real violation"
	)
	assert_gt(
		_opaque_fraction(painted),
		MAX_OPAQUE_FRACTION,
		"the sweep's predicate must reject a sprite whose background has been painted in"
	)

	assert_lt(
		_opaque_fraction(_image_of(texture)),
		MAX_OPAQUE_FRACTION,
		(
			"mutating one caller's image must not reach the texture's cached Image. If this "
			+ "fails, `_image_of()` stopped duplicating and every later test in this process is "
			+ "now reading corrupted pixels."
		)
	)


func test_the_walk_found_the_entity_scenes() -> void:
	assert_gt(
		_scenes.size(),
		MIN_SCENES,
		"the scene walk collapsed; every assertion above would be vacuously true"
	)
	assert_gt(
		_textures.size(),
		MIN_TEXTURES,
		(
			"the texture walk collapsed. If this reports ~9, the AnimatedSprite2D/SpriteFrames "
			+ "branch broke and player/, projectiles/, hazards/ and allies/ now contribute "
			+ "nothing — fix the walk, do not lower the floor."
		)
	)
