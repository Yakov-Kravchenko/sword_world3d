shader_type sky;
// Небо хаба: градиент, солнечный диск и слой облаков на шуме.
// Готовые материалы Godot (ProceduralSkyMaterial, PhysicalSkyMaterial) облаков
// не умеют, а именно облака дают небу глубину и читаемое время суток.

uniform vec3 zenith_color : source_color = vec3(0.10, 0.28, 0.58);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.74, 0.79);
uniform vec3 ground_color : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 cloud_lit : source_color = vec3(1.00, 0.98, 0.94);
uniform vec3 cloud_shadow : source_color = vec3(0.36, 0.41, 0.50);
uniform vec3 sun_tint : source_color = vec3(1.00, 0.92, 0.76);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.44;
uniform float cloud_sharpness : hint_range(0.02, 0.60) = 0.28;
uniform float cloud_scale = 1.7;
uniform float cloud_speed = 0.006;
uniform float sun_glow_power = 44.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * value_noise(p);
		p = p * 2.07 + vec2(13.7, 41.3);
		amp *= 0.5;
	}
	return sum;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;

	// Степень 0.42 поднимает светлую полосу у горизонта выше, чем линейный
	// градиент: так небо не выглядит нарисованным в две краски.
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 0.42));
	col = mix(col, ground_color, clamp(-up * 5.0, 0.0, 1.0));

	float sun_dot = 0.0;
	if (LIGHT0_ENABLED) {
		sun_dot = clamp(dot(dir, LIGHT0_DIRECTION), 0.0, 1.0);
		col += sun_tint * LIGHT0_COLOR * pow(sun_dot, sun_glow_power) * 0.5;
		col += sun_tint * LIGHT0_COLOR * pow(sun_dot, 6.0) * 0.08;
		float disk = smoothstep(0.9993, 0.9998, sun_dot);
		col = mix(col, sun_tint * LIGHT0_ENERGY * 7.0, disk);
	}

	// Луч взгляда проецируется на горизонтальный слой: у горизонта проекция
	// растягивается, и облака сами уходят в перспективу.
	float layer = max(up, 0.035);
	vec2 uv = dir.xz / layer * cloud_scale + TIME * cloud_speed * vec2(1.0, 0.35);
	// В кубмапу светимости хватает трёх октав — она мелкая и размывается.
	int octaves = AT_CUBEMAP_PASS ? 3 : 5;
	float density = fbm(uv, octaves);
	float cover = smoothstep(cloud_cover, cloud_cover + cloud_sharpness, density);
	// У самого горизонта слой вырождается в кашу — гасим его.
	cover *= smoothstep(0.0, 0.20, up);

	// Второй сэмпл со сдвигом играет роль освещённой стороны облака.
	float lit = fbm(uv + vec2(0.55, 0.18), 3);
	vec3 cloud_col = mix(cloud_shadow, cloud_lit, clamp(lit * 1.7, 0.0, 1.0));
	cloud_col += sun_tint * pow(sun_dot, 10.0) * 0.4;

	COLOR = mix(col, cloud_col, cover * 0.94);
}
