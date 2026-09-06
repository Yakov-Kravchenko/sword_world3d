shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Трава: качание от ветра и цвет из вершин.
//
// Качается только верх стебля — смещение растёт как квадрат высоты, поэтому
// корень стоит на месте, а кончик гуляет. Фаза берётся из позиции пучка в мире:
// иначе всё поле качается синхронно и читается как анимация, а не как ветер.

uniform float sway : hint_range(0.0, 1.0) = 0.22;
uniform float speed : hint_range(0.1, 4.0) = 1.5;
uniform vec3 wind_dir = vec3(1.0, 0.0, 0.35);

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = origin.x * 0.35 + origin.z * 0.27;
	// Порыв: медленная волна поверх основного качания, чтобы движение не было
	// равномерным.
	float gust = 0.65 + 0.35 * sin(TIME * 0.4 + origin.x * 0.05 + origin.z * 0.04);
	float bend = VERTEX.y * VERTEX.y * sway * gust;
	VERTEX.x += sin(TIME * speed + phase) * bend * wind_dir.x;
	VERTEX.z += cos(TIME * speed * 0.85 + phase * 1.3) * bend * wind_dir.z;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	// Свет сквозь стебель: без подсветки на просвет трава выглядит пластиковой.
	BACKLIGHT = vec3(0.22, 0.30, 0.14);
}
