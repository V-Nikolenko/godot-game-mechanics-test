## Erase a sprite's painted-in background by flood-filling inward from the image border.
##
## Called through `scripts/strip-sprite-bg.sh`, never directly — the wrapper is what verifies the
## result is still a real PNG afterwards.
##
##     godot --headless --path . -s res://scripts/lib/strip_sprite_bg.gd -- <in.png> <out.png> [--dry-run]
##
## ── Why this exists ──────────────────────────────────────────────────────────────────────────
##
## PixelLab's `create_image_pixflux` / `_pixen` / `_pro` paint a background unless you pass
## `no_background: true`, and the result renders in-game as an opaque card that cuts a hard
## rectangle out of the starfield. `assault/assets/sprites/enemies/station_core.png` shipped that
## way — 65536/65536 pixels at alpha 1.0 — and survived two cycles because nothing in the gate
## renders a scene. `.claude/skills/pixel-art-generation/SKILL.md` now requires the flag, and
## `tests/integration/test_entity_sprite_transparency.gd` fails the gate when it is forgotten.
## This script is the **recovery path** for art that is already generated and already
## art-directed: regenerating spends a capped, non-refundable monthly allowance and cannot be
## undone if the new sprite is worse.
##
## Godot is the whole dependency list on purpose. This container has no `python3`, no ImageMagick,
## and no `file` — only `od` and the engine.
##
## ── Why a border flood fill and not a colour key ─────────────────────────────────────────────
##
## A global colour key removes *every* pixel of the background colour, including the ones the
## artwork encloses, and punches holes through the subject. A fill seeded from the border removes
## only pixels connected to the outside. On `station_core.png` that distinction is 41 pixels of
## interior hull detail that share the background colour and must stay.
##
## The fill is **4-connected**, not 8-connected, deliberately. 8-connected can leak through a
## single-pixel diagonal seam in the subject and eat the interior; 4-connected can only
## under-remove, which is visible and fixable. On the sprite this was written for, 4-connected
## already reaches 34324 of 34365 background pixels, so the safer algorithm costs nothing.
##
## ── The two guards ───────────────────────────────────────────────────────────────────────────
##
## The script never guesses which colour is the background. It refuses unless **all four corners
## are the same fully-opaque colour**, and it refuses to write if the fill covers more than
## `MAX_FILL_FRACTION` of the image — which means the corner colour was the subject, and the
## result would be an empty sprite. Both are hard failures, not warnings.
##
## Erased pixels keep their RGB and get alpha 0. Godot's importer sets
## `process/fix_alpha_border=true`, which repaints invisible pixels with their visible neighbours'
## colour anyway, so zeroing RGB would buy nothing and would turn the PNG diff into "every byte
## changed" instead of "alpha changed".
extends SceneTree

## Above this, the "background" is the subject and the result would be a blank sprite.
const MAX_FILL_FRACTION := 0.95


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dry_run := args.has("--dry-run")
	var paths: Array[String] = []
	for a: String in args:
		if not a.begins_with("--"):
			paths.append(a)
	if paths.size() != 2:
		_die("usage: strip_sprite_bg.gd <in.png> <out.png> [--dry-run]")
		return
	_run(paths[0], paths[1], dry_run)


func _die(message: String) -> void:
	printerr("strip_sprite_bg: %s" % message)
	quit(1)


func _run(in_path: String, out_path: String, dry_run: bool) -> void:
	var img := Image.load_from_file(in_path)
	if img == null:
		_die("cannot load %s" % in_path)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var total := w * h

	# One flat RGBA8 buffer. Comparing bytes rather than `Color` keeps the match exact - a float
	# comparison on a colour that round-tripped through sRGB is not something to bet a sprite on.
	var bytes := img.get_data()

	var corners: Array[int] = [
		0,
		(w - 1) * 4,
		(h - 1) * w * 4,
		((h - 1) * w + (w - 1)) * 4,
	]
	var bg := bytes.slice(corners[0], corners[0] + 4)
	if bg[3] != 255:
		_die("corner pixel is not opaque (alpha %d) - nothing to strip" % bg[3])
		return
	for c: int in corners:
		var here := bytes.slice(c, c + 4)
		if here != bg:
			_die(
				"the four corners are not one colour (%s vs %s) - refusing to guess which is "
				% [_hex(bg), _hex(here)]
				+ "the background. Strip this sprite by hand, or crop it first."
			)
			return

	var matching := 0
	for i in range(0, bytes.size(), 4):
		if bytes.slice(i, i + 4) == bg:
			matching += 1

	var removed := _flood(bytes, w, h, bg)
	var fraction := float(removed) / float(total)
	if fraction > MAX_FILL_FRACTION:
		_die(
			"the fill covered %.2f%% of the image, over the %.0f%% guard - %s is the subject, "
			% [fraction * 100.0, MAX_FILL_FRACTION * 100.0, _hex(bg)]
			+ "not the background. Nothing written."
		)
		return

	var opaque_before := 0
	var opaque_after := 0
	var original := img.get_data()
	for i in range(3, original.size(), 4):
		if original[i] == 255:
			opaque_before += 1
		if bytes[i] == 255:
			opaque_after += 1

	print("strip_sprite_bg: %s  %dx%d" % [in_path, w, h])
	print("  background %s: %d px (%.2f%%)" % [_hex(bg), matching, 100.0 * matching / total])
	print("  erased from the border: %d px (%.2f%%)" % [removed, 100.0 * removed / total])
	print("  enclosed by the artwork, kept: %d px" % [matching - removed])
	print(
		"  fully opaque: %.2f%% -> %.2f%%"
		% [100.0 * opaque_before / total, 100.0 * opaque_after / total]
	)

	if dry_run:
		print("  --dry-run: nothing written")
		quit(0)
		return

	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	var err := out.save_png(out_path)
	if err != OK:
		_die("save_png(%s) failed with error %d" % [out_path, err])
		return
	print("  wrote %s" % out_path)
	quit(0)


## 4-connected flood fill seeded from every border pixel, in place on `bytes`. Sets alpha 0 and
## leaves RGB. Returns the number of pixels erased.
func _flood(bytes: PackedByteArray, w: int, h: int, bg: PackedByteArray) -> int:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for x in range(w):
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in range(h):
		stack.append(y * w)
		stack.append(y * w + (w - 1))

	var removed := 0
	while stack.size() > 0:
		var p := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if seen[p] == 1:
			continue
		var b := p * 4
		if bytes.slice(b, b + 4) != bg:
			continue
		seen[p] = 1
		bytes[b + 3] = 0
		removed += 1
		var x := p % w
		var y := p / w
		if x > 0:
			stack.append(p - 1)
		if x < w - 1:
			stack.append(p + 1)
		if y > 0:
			stack.append(p - w)
		if y < h - 1:
			stack.append(p + w)
	return removed


func _hex(rgba: PackedByteArray) -> String:
	return "#%02x%02x%02x%02x" % [rgba[0], rgba[1], rgba[2], rgba[3]]
