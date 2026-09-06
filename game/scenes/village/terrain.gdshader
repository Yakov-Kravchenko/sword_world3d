shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Ландшафт хаба: трава внизу, камень на склонах, снег на вершинах.
// Смешивание идёт по уклону и высоте, а UV берутся из мировых координат —
// одна текстура тянется на 760 метров, и без этого швы были бы видны.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.085;
uniform float snow_line = 62.0;
uniform float snow_fade = 30.0;
uniform float rock_slope : hint_range(0.05, 1.0) = 0.55;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz * uv_scale;
	// Разные масштабы у слоёв прячут повторение тайла на больших дистанциях.
	vec3 grass = texture(grass_albedo, uv).rgb;
	vec3 rock = texture(rock_albedo, uv * 0.55).rgb;
	vec3 snow = texture(snow_albedo, uv * 0.38).rgb;

	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_mix = smoothstep(rock_slope * 0.30, rock_slope, slope);
	vec3 col = mix(grass, rock, rock_mix);

	float snow_mix = smoothstep(snow_line, snow_line + snow_fade, world_pos.y);
	// На отвесных стенах снег не задерживается — без этого горы заливает белым
	// целиком и силуэт хребта пропадает.
	snow_mix *= 1.0 - smoothstep(0.50, 0.80, slope);
	col = mix(col, snow, snow_mix);

	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.62, snow_mix);
	SPECULAR = mix(0.35, 0.55, snow_mix);
	NORMAL_MAP = texture(detail_normal, uv * 1.1).rgb;
	NORMAL_MAP_DEPTH = mix(1.3, 0.45, snow_mix);
}
