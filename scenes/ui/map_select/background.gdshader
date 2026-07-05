shader_type canvas_item;
// Dusk-ocean backdrop for Map Select. Reproduces the handoff Layer-1 stack in a
// single fragment pass over UV (0..1). No textures, no uniforms — pure gradient art.

// linear-gradient(180deg) stops from the handoff, top(0)->bottom(1).
vec3 sky_ocean(float y) {
	vec3 c;
	if (y < 0.15)      c = mix(vec3(0.109,0.074,0.051), vec3(0.498,0.258,0.109), y / 0.15);
	else if (y < 0.27) c = mix(vec3(0.498,0.258,0.109), vec3(0.752,0.439,0.121), (y - 0.15) / 0.12);
	else if (y < 0.37) c = mix(vec3(0.752,0.439,0.121), vec3(0.690,0.407,0.164), (y - 0.27) / 0.10);
	else if (y < 0.49) c = mix(vec3(0.690,0.407,0.164), vec3(0.360,0.356,0.235), (y - 0.37) / 0.12);
	else if (y < 0.60) c = mix(vec3(0.360,0.356,0.235), vec3(0.133,0.321,0.360), (y - 0.49) / 0.11);
	else if (y < 0.74) c = mix(vec3(0.133,0.321,0.360), vec3(0.074,0.223,0.278), (y - 0.60) / 0.14);
	else if (y < 0.90) c = mix(vec3(0.074,0.223,0.278), vec3(0.039,0.109,0.149), (y - 0.74) / 0.16);
	else               c = mix(vec3(0.039,0.109,0.149), vec3(0.027,0.066,0.094), (y - 0.90) / 0.10);
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = sky_ocean(uv.y);

	// warm sun glow ellipse at (50%, 30%) — radial-gradient(120% 78%).
	vec2 gp = (uv - vec2(0.5, 0.30)) / vec2(0.60, 0.39);
	float glow = clamp(1.0 - length(gp), 0.0, 1.0);
	col += vec3(1.0, 0.690, 0.329) * glow * glow * 0.55;

	// faint water sheen streaks (screen-ish) from ~46% down.
	if (uv.y > 0.46) {
		float streak = step(0.5, fract(uv.y * 720.0 / 40.0)) * 0.03;
		col += vec3(1.0, 0.768, 0.470) * streak * (uv.y - 0.46);
	}

	// vignette: transparent centre -> dark edges (radial 130% 100% at 50% 46%).
	vec2 vp = (uv - vec2(0.5, 0.46)) / vec2(0.65, 0.5);
	float vig = smoothstep(0.55, 1.0, length(vp));
	col = mix(col, vec3(0.015, 0.039, 0.054), vig * 0.72);

	COLOR = vec4(col, 1.0);
}
