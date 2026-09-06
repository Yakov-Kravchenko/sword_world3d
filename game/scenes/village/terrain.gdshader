shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Ландшафт на фотосканных материалах (Poly Haven, CC0): трава внизу, скала на
// склонах, снег на вершинах, грязь в низинах у воды.
//
// Три вещи, без которых большой ландшафт разваливается:
//   1. Скала берётся трипланарной проекцией. Плоская UV по XZ на обрыве
//      растягивается в полосы — именно так и выглядели «шумные» горы раньше.
//   2. Крупномасштабный шум сбивает повторение тайла: один и тот же метровый
//      кусок травы, повторённый триста раз, читается как решётка.
//   3. Границы слоёв размываются тем же шумом. Чистый smoothstep по высоте
//      даёт ровную горизонталь снега, какой в природе не бывает.

uniform sampler2D grass_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_norm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_norm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D snow_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_norm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D dirt_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_norm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float ground_scale = 0.075;      // тайл травы и грязи, метров^-1
uniform float rock_scale = 0.075;       // скала крупнее: мелкий камень рябит
uniform float snow_scale = 0.10;
uniform float snow_line = 92.0;
uniform float snow_fade = 34.0;
uniform float rock_slope : hint_range(0.05, 1.0) = 0.42;
uniform float dirt_level = 1.4;         // ниже этой высоты трава сходит на грязь
uniform float macro_strength : hint_range(0.0, 1.0) = 0.35;
// Сканы подстилки и грязи сняты сухими и коричневыми. Оттенок задаётся явно:
// северная долина должна быть зелёной, а не песчаной.
uniform vec3 grass_tint : source_color = vec3(0.62, 0.92, 0.45);
uniform vec3 dirt_tint : source_color = vec3(0.85, 0.78, 0.66);
uniform vec3 rock_tint : source_color = vec3(0.88, 0.88, 0.90);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Трипланар: три проекции, вес по квадрату нормали. Показатель 4 делает переход
// между гранями узким — иначе на пологих местах смешиваются все три и картинка
// мылится.
vec3 triplanar(sampler2D tex, vec3 pos, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 x = texture(tex, pos.zy * scale).rgb;
	vec3 y = texture(tex, pos.xz * scale).rgb;
	vec3 z = texture(tex, pos.xy * scale).rgb;
	return x * w.x + y * w.y + z * w.z;
}

// Два масштаба, один развёрнут по осям: слоистая скала при простом тайлинге
// даёт горизонтальную полосатость на весь хребет — видно за километр.
vec3 rock_layers(sampler2D tex, vec3 pos, vec3 n, float scale) {
	vec3 coarse = triplanar(tex, pos, n, scale * 0.31);
	vec3 fine = triplanar(tex, pos.zyx, n.zyx, scale * 1.6);
	return mix(coarse, fine, 0.45);
}

void fragment() {
	vec2 uv_ground = world_pos.xz * ground_scale;
	vec2 uv_snow = world_pos.xz * snow_scale;

	// Крупный шум: сбивает повторение тайла и заодно рвёт границы слоёв.
	float macro = value_noise(world_pos.xz * 0.013);
	float jitter = (macro - 0.5) * 2.0;

	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	vec3 grass_c = texture(grass_diff, uv_ground).rgb * grass_tint;
	vec3 dirt_c = texture(dirt_diff, uv_ground * 1.3).rgb * dirt_tint;
	vec3 rock_c = rock_layers(rock_diff, world_pos, world_normal, rock_scale) * rock_tint;
	vec3 snow_c = texture(snow_diff, uv_snow).rgb;

	vec3 grass_n = texture(grass_norm, uv_ground).rgb;
	vec3 dirt_n = texture(dirt_norm, uv_ground * 1.3).rgb;
	vec3 rock_n = rock_layers(rock_norm, world_pos, world_normal, rock_scale);
	vec3 snow_n = texture(snow_norm, uv_snow).rgb;

	float grass_r = texture(grass_rough, uv_ground).r;
	float dirt_r = texture(dirt_rough, uv_ground * 1.3).r;
	float rock_r = rock_layers(rock_rough, world_pos, world_normal, rock_scale).r;
	float snow_r = texture(snow_rough, uv_snow).r;

	// Низины у воды — сырая земля, а не газон до самого уреза.
	float dirt_mix = smoothstep(dirt_level + 0.9, dirt_level - 0.3, world_pos.y + jitter * 0.6);
	vec3 col = mix(grass_c, dirt_c, dirt_mix);
	vec3 nrm = mix(grass_n, dirt_n, dirt_mix);
	float rgh = mix(grass_r, dirt_r, dirt_mix);

	// Скала на склонах: порог сдвинут шумом, поэтому граница рваная.
	float rock_mix = smoothstep(rock_slope * 0.45, rock_slope, slope + jitter * 0.10);
	col = mix(col, rock_c, rock_mix);
	nrm = mix(nrm, rock_n, rock_mix);
	rgh = mix(rgh, rock_r, rock_mix);

	// Снег: выше линии и только там, где он способен удержаться.
	float snow_mix = smoothstep(snow_line, snow_line + snow_fade, world_pos.y + jitter * 12.0);
	snow_mix *= 1.0 - smoothstep(0.55, 0.85, slope);
	col = mix(col, snow_c, snow_mix);
	nrm = mix(nrm, snow_n, snow_mix);
	rgh = mix(rgh, snow_r, snow_mix);

	// Макро-пятна яркости: тот же приём, что и на границах, но по альбедо.
	col *= mix(1.0 - macro_strength * 0.5, 1.0 + macro_strength * 0.35, macro);

	ALBEDO = col;
	ROUGHNESS = clamp(rgh, 0.15, 1.0);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = mix(1.0, 1.6, rock_mix);
	SPECULAR = 0.4;
}
