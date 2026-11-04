// The one shared material for every generated model (ASSETS.md section 7).
// Colours come from palette.png (16 x 16 swatch cells); UVs sit at cell centres.
// Per-instance parameters (no material duplication per player):
//   team_color - replaces the three team.* swatch cells (row 8, cols 0-2): base, dark, light
//   recolor    - ornament-kit recolour of tier-material cells (rows 0-6), alpha = strength
//   flash      - brief white flash (hit feedback), 0..1
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform sampler2D emission_mask : filter_nearest, repeat_disable;
uniform float emission_energy = 2.2;
uniform float specular_amount = 0.15;

instance uniform vec4 team_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
instance uniform vec4 recolor : source_color = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float flash = 0.0;

void fragment() {
	vec3 c = texture(palette, UV).rgb;
	ivec2 cell = ivec2(floor(clamp(UV, vec2(0.0), vec2(0.9999)) * 16.0));
	if (cell.y == 8 && cell.x <= 2) {
		float k = cell.x == 0 ? 1.0 : (cell.x == 1 ? 0.62 : 1.35);
		c = clamp(team_color.rgb * k, vec3(0.0), vec3(1.0));
	}
	if (recolor.a > 0.0 && cell.y <= 6 && cell.x != 4 && cell.x != 9 && cell.x != 14) {
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(c, clamp(recolor.rgb * (0.45 + lum * 1.1), vec3(0.0), vec3(1.0)), recolor.a);
	}
	c = mix(c, vec3(1.0), flash);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = specular_amount;
	EMISSION = c * texture(emission_mask, UV).r * emission_energy;
}
