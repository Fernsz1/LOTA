shader_type canvas_item;

// 7.4 — recolors a HUD fill bar to an arbitrary `tint`, reusing whatever
// pre-colored art asset is already assigned (health_fill_blue.png etc.).
// Strips the source pixel down to luminance (keeping its baked
// shading/gradient) then remultiplies by `tint`, so the same asset can show
// ANY color — a fighter's own signature color on the health bar, or a shared
// brand orange on the ult meter — without the "blue asset tinted red comes
// out a different hue than a red asset tinted red" inconsistency that a
// plain `modulate` multiply would produce against non-white source art.
// Ignores the node's own modulate entirely (this fully overwrites COLOR), so
// per-bar color is driven only by this `tint` uniform, set from script.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(lum * tint.rgb, tex.a * tint.a);
}
