// Stylised water (docs/ENVIRONMENT.md section 5): flat surface below the ground, palette shallow/deep colours,
// gentle scrolling noise ripples and a foam line along shores (vertex COLOR.r = 1 at a shore).
// ice = frozen pool (cracked pale ice with dark open holes); murk = swamp water with drifting scum.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.4, 0.65, 0.75);
uniform vec3 deep : source_color = vec3(0.15, 0.3, 0.45);
uniform vec3 foam : source_color = vec3(0.92, 0.95, 0.97);
uniform float ice = 0.0;
uniform float murk = 0.0;
uniform float speed = 1.0;

varying vec3 v_world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float cells(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float d1 = 8.0, d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * speed * (1.0 - ice);
	float n = noise(v_world.xz * 1.3 + vec2(t * 0.12, t * 0.07)) * 0.65 + noise(v_world.xz * 3.1 - vec2(t * 0.1)) * 0.35;
	float shore = COLOR.r;
	vec3 c = mix(deep, shallow, clamp(shore * 0.55 + n * 0.45, 0.0, 1.0));
	float bands = step(0.5, fract(n * 3.0 + t * 0.05));
	c *= 0.95 + 0.07 * bands;
	float f = smoothstep(0.72, 0.95, shore + (n - 0.5) * 0.3);
	c = mix(c, foam, f * 0.75 * (1.0 - ice));
	if (murk > 0.0) {
		float scum = smoothstep(0.62, 0.68, noise(v_world.xz * 0.8 + vec2(t * 0.02, 0.0)));
		c = mix(c, shallow * 1.25, scum * murk * 0.6);
	}
	if (ice > 0.0) {
		vec3 ic = mix(shallow, foam, 0.35 + 0.25 * noise(v_world.xz * 2.0));
		float crack = 1.0 - smoothstep(0.0, 0.05, cells(v_world.xz * 1.6));
		ic = mix(ic, shallow * 0.6, crack * 0.8);
		float hole = smoothstep(0.78, 0.8, noise(v_world.xz * 0.9 + 3.7));
		c = mix(ic, deep, hole);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.25, 0.5, ice);
	SPECULAR = 0.45;
}
