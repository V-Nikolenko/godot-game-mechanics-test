// open_space/scenes/mission_select_ui/planet_motion_blur.gdshader
// Directional motion blur for the planet sprite during mission-point navigation.
// blur_amount_px : blur radius in texture pixels (0 = passthrough).
// blur_dir       : normalised movement direction in UV/screen space.
shader_type canvas_item;

uniform float blur_amount_px : hint_range(0.0, 12.0) = 0.0;
uniform vec2  blur_dir = vec2(1.0, 0.0);

void fragment() {
	if (blur_amount_px < 0.01) {
		// Passthrough — no blur active.
		COLOR = texture(TEXTURE, UV);
	} else {
		// Nine-tap weighted blur along blur_dir.
		// Weights fall off linearly from centre to tips (softer than a box blur).
		vec4  sum   = vec4(0.0);
		float total = 0.0;
		for (int i = 0; i < 9; i++) {
			float t      = float(i) / 8.0 - 0.5;        // -0.5 to +0.5
			float weight = 1.0 - abs(t) * 1.6;           // 1.0 at centre, ~0.2 at tips
			weight       = max(weight, 0.0);
			vec2  off    = blur_dir * t * blur_amount_px * TEXTURE_PIXEL_SIZE;
			sum   += texture(TEXTURE, UV + off) * weight;
			total += weight;
		}
		COLOR = sum / total;
	}
}
