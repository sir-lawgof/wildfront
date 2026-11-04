// Painted-look sky (docs/ENVIRONMENT.md section 5): gradient, soft sun disc and drifting flat-shaded clouds.
// All colours come from the map's theme block.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.5, 0.62, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.83, 0.88);
uniform vec3 ground_color : source_color = vec3(0.45, 0.48, 0.5);
uniform vec3 cloud_color : source_color = vec3(0.93, 0.95, 0.97);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float cloud_cover = 0.4;
uniform float sun_size = 0.035;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 c;
	if (d.y >= 0.0) {
		c = mix(horizon_color, top_color, pow(d.y, 0.55));
		vec2 uv = d.xz / (d.y + 0.12);
		float n = fbm(uv * 0.9 + vec2(TIME * 0.004, TIME * 0.002));
		float steps = floor(n * 5.0) / 5.0;
		float cl = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover, steps) * smoothstep(0.0, 0.18, d.y);
		c = mix(c, cloud_color * (0.9 + 0.1 * steps), cl * 0.9);
	} else {
		c = mix(horizon_color, ground_color, pow(-d.y, 0.4));
	}
	float s = dot(d, normalize(LIGHT0_DIRECTION));
	c += sun_color * smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.7, s) * 0.8;
	c += sun_color * pow(max(s, 0.0), 24.0) * 0.18;
	COLOR = c;
}
