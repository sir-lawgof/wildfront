// Shared environment material (docs/ENVIRONMENT.md section 3).
// - Colours from palette_env.png (16 x 16 swatch cells), multiplied by vertex colour (baked AO / ground jitter).
// - Per-placement brightness variation (+-variation) hashed from the object's world origin, so repeated
//   MultiMesh pieces don't look copy-pasted.
// - Occlusion cut-out: fragments between the camera and the local player (global player_pos), within a small
//   screen radius around them, are dither-discarded so walls never hide the player at low camera angles.
// - common.banner / banner_dark cells (row 9, cols 0-1) take the per-instance banner_color (friend/foe).
// - Ground mode draws faint tile edges (stronger when the tile-grid option is on).
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform sampler2D emission_mask : filter_nearest, repeat_disable;
uniform float emission_energy = 2.0;
uniform float variation = 0.05;
uniform float specular_amount = 0.12;
uniform float cutout_radius = 0.13;   // fraction of the screen height around the player
global uniform vec3 player_pos;        // y < -100 disables the cut-out

instance uniform vec4 banner_color : source_color = vec4(0.62, 0.62, 0.62, 1.0);
instance uniform float ground = 0.0;
instance uniform float grid_strength = 0.0;
instance uniform float cutout = 1.0;
instance uniform float vary = 1.0;     // 0 for merged chunks (variation baked into vertex colours)

varying float v_var;
varying vec3 v_world;

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = fract(sin(dot(floor(o.xz * 2.0) + 0.37, vec2(12.9898, 78.233))) * 43758.5453);
	v_var = 1.0 + (h * 2.0 - 1.0) * variation * vary;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec3 c = texture(palette, UV).rgb;
	ivec2 cell = ivec2(floor(clamp(UV, vec2(0.0), vec2(0.9999)) * 16.0));
	if (cell.y == 9 && cell.x <= 1) {
		c = banner_color.rgb * (cell.x == 0 ? 1.0 : 0.62);
	}
	c *= COLOR.rgb * (ground > 0.5 ? 1.0 : v_var);
	if (ground > 0.5) {
		vec2 f = fract(v_world.xz);
		float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		c *= mix(1.0, 0.93 - 0.1 * grid_strength, 1.0 - smoothstep(0.0, 0.03, e));
	}
	if (cutout > 0.5 && player_pos.y > -100.0) {
		vec4 pv = VIEW_MATRIX * vec4(player_pos + vec3(0.0, 0.9, 0.0), 1.0);
		if (VERTEX.z > pv.z + 0.6) {
			vec4 pc = PROJECTION_MATRIX * pv;
			vec4 fc = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
			vec2 d = fc.xy / fc.w - pc.xy / pc.w;
			d.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
			float dist = length(d) * 0.5;
			float k = 1.0 - dist / cutout_radius;
			if (k > 0.0 && bayer4(FRAGCOORD.xy) < k * 1.6) {
				discard;
			}
		}
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = specular_amount;
	EMISSION = c * texture(emission_mask, UV).r * emission_energy;
}
