// Meteor Strike target (docs/ENVIRONMENT.md section 8): a stylised flat danger decal (ring, cross-hatch and
// corner ticks) whose pulse speeds up as the strike lands. progress: 0 = just called, 1 = landing now.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float pulse = 0.5 + 0.5 * sin(TIME * mix(5.0, 18.0, progress));
	float ring = smoothstep(0.08, 0.0, abs(r - 0.88)) + smoothstep(0.05, 0.0, abs(r - mix(0.85, 0.1, fract(TIME * 0.8 + progress))));
	float hatch = step(0.5, fract((p.x + p.y) * 4.0)) * step(r, 0.82) * 0.35;
	float cross = (smoothstep(0.05, 0.0, abs(p.x)) + smoothstep(0.05, 0.0, abs(p.y))) * step(r, 0.5);
	float a = clamp(ring + hatch + cross, 0.0, 1.0) * mix(0.55, 0.95, pulse) * step(r, 1.0);
	ALBEDO = tint.rgb * mix(1.0, 1.5, pulse);
	ALPHA = a;
}
