shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Вода реки. Глубину читаем не из буфера глубины, а из развёртки ленты: UV.x
// идёт поперёк русла, поэтому у берега вода сама собой мельче и прозрачнее.
// Так шейдер не зависит от порядка отрисовки и работает предсказуемо.

uniform vec3 shallow_color : source_color = vec3(0.55, 0.70, 0.62);
uniform vec3 deep_color : source_color = vec3(0.24, 0.45, 0.46);
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.30;
uniform float wave_speed = 0.035;
uniform float shore_width : hint_range(0.02, 0.5) = 0.22;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Мелкая зыбь по вершинам: две волны с разным периодом не дают ряби
	// сложиться в правильную сетку.
	VERTEX.y += sin(world_pos.x * 0.8 + TIME * 1.4) * 0.030
		+ sin(world_pos.z * 1.1 - TIME * 1.1) * 0.025;
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	// Два слоя нормалей ползут в разные стороны — рябь перестаёт выглядеть
	// как одна ползущая текстура.
	vec3 a = texture(wave_normal, uv + vec2(TIME * wave_speed, TIME * wave_speed * 0.6)).rgb;
	vec3 b = texture(wave_normal, uv * 1.7 - vec2(TIME * wave_speed * 0.8, TIME * wave_speed * 0.2)).rgb;
	NORMAL_MAP = normalize(a + b);
	NORMAL_MAP_DEPTH = 0.55;

	float shore = smoothstep(0.0, shore_width, min(UV.x, 1.0 - UV.x));
	ALBEDO = mix(shallow_color, deep_color, shore);
	ALPHA = mix(0.45, 0.80, shore);
	// Гладкая поверхность с сильным бликом ловит отражение неба через IBL —
	// именно оно читается как вода, а не сам цвет.
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
