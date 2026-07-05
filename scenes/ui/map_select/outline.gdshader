shader_type canvas_item;
// Graphic-novel outer stroke for textured CanvasItem fills. Samples TEXTURE alpha
// in a ring at outline_width; where this pixel is transparent but a neighbor is
// opaque, output a hard, un-blurred outline_color. Requires a texture with alpha.

uniform float outline_width = 6.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.5) {
		COLOR = tex;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		float hit = 0.0;
		// 8-direction ring sample
		hit = max(hit, texture(TEXTURE, UV + vec2( px.x, 0.0)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(0.0,  px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2( px.x,  px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(-px.x,  px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2( px.x, -px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);
		// hard step: no blur, no gradient
		COLOR = (hit > 0.5) ? outline_color : vec4(0.0);
	}
}
