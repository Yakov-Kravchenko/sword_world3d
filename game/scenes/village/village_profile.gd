class_name VillageProfile
extends RefCounted
## Описание одной деревни: рельеф, вода, палитра, свет и растительность.
##
## Четырём героям — четыре места. Отличаться они должны не оттенком травы, а
## силуэтом: равнина под хребтом, посёлок на воде, чаща и снега дают разный
## горизонт, разный свет и разный набор зелени. Поэтому в профиль вынесено всё,
## что задаёт характер места, а генератор стал общим.
##
## Почему это класс, а не JSON рядом с биомами подземелий: здесь не игровой
## баланс, а параметры генератора — кривые высот, оттенки шейдера, углы солнца.
## Их правят вместе с самим генератором, и держать их в отдельном файле данных
## значило бы разносить одно решение по двум местам.

var id: StringName
var title: String

# --- Рельеф ---
var mountain_height := 168.0
var mountain_start := 60.0
var mountain_fade := 185.0
var hill_height := 9.0
var yard_relief := 2.8
var yard_base := 1.1
var tree_line := 46.0

# --- Вода ---
var water_level := -0.3
var river: PackedVector2Array = PackedVector2Array()
var river_half := 6.0
var river_bank := 6.5
var river_depth := 1.2
## Мост строится только там, где улица действительно пересекает воду. У прочих
## деревень вода лежит за оградой, и мост через сушу выглядел бы нелепо.
var has_bridge := false
var bridge_a := Vector2.ZERO
var bridge_b := Vector2.ZERO

# --- Материалы земли ---
var ground_set := "forest_ground_04"
var dirt_set := "brown_mud_03"
var rock_set := "cliff_side"
var grass_tint := Color(0.62, 0.92, 0.45)
var dirt_tint := Color(0.85, 0.78, 0.66)
var rock_tint := Color(0.88, 0.88, 0.90)
var snow_line := 76.0
var snow_fade := 24.0

# --- Свет и небо ---
var sun_angle := Vector3(-47.0, 138.0, 0.0)
var sun_color := Color(1.0, 0.94, 0.85)
var sun_energy := 2.4
var ambient := 0.85
var fog_color := Color(0.55, 0.65, 0.79)
var fog_density := 0.00035
var saturation := 0.78
var sky_zenith := Color(0.10, 0.28, 0.58)
var sky_horizon := Color(0.66, 0.74, 0.79)
var cloud_cover := 0.44

# --- Планировка ---
## Где что стоит. Раскладка у каждой деревни своя: одинаковая расстановка при
## разном рельефе всё равно читается как одно место, перекрашенное четырежды.
var spawn := Vector2(0.0, 31.0)
var chapel := Vector2(16.0, -22.0)
var places := {}
## Достопримечательности: {"kind": &"tower", "at": Vector2, "yaw": float}.
## С ними не взаимодействуют — они нужны, чтобы по деревне было интересно ходить.
var landmarks: Array = []

# --- Растительность ---
var tree_count := 300
var tree_height := Vector2(8.0, 16.0)
var grass_count := 6000
var grass_colour := Color(0.32, 0.38, 0.17)
var needle_colour := Color(0.10, 0.16, 0.09)


## Профиль по герою. Порядок героев в проекте: hald, irma, vern, mara.
static func for_hero(hero_id: StringName) -> VillageProfile:
	match hero_id:
		&"irma":
			return _harbour()
		&"vern":
			return _woodland()
		&"mara":
			return _snowfield()
		_:
			return _plain()


static func all_ids() -> Array[StringName]:
	return [&"hald", &"irma", &"vern", &"mara"]


## Равнина под хребтом — родная деревня Хальда. Ближе всего к Вайтрану:
## открытое поле, река с мостом, снежные вершины по горизонту.
static func _plain() -> VillageProfile:
	var p := VillageProfile.new()
	p.id = &"hald"
	p.title = "Долина"
	# Улица с юга на север, река с мостом на въезде, башня над восточным краем.
	p.places = {
		&"garden": Vector2(-17.0, 4.0), &"storage": Vector2(16.0, 4.0),
		&"forge": Vector2(-14.0, -10.0), &"shop": Vector2(14.0, -10.0),
		&"training": Vector2(-12.0, -23.0), &"descend": Vector2(0.0, -29.0)}
	p.chapel = Vector2(16.0, -22.0)
	p.spawn = Vector2(0.0, 31.0)
	p.landmarks = [
		{"kind": &"tower", "at": Vector2(25.0, -3.0), "yaw": -1.4},
		{"kind": &"stones", "at": Vector2(-25.0, 19.0), "yaw": 0.0},
		{"kind": &"graveyard", "at": Vector2(25.0, 16.0), "yaw": 1.5},
		{"kind": &"campfire", "at": Vector2(-4.0, -3.0), "yaw": 0.0},
		{"kind": &"ruin", "at": Vector2(-26.0, -20.0), "yaw": 0.6}]
	p.has_bridge = true
	p.bridge_a = Vector2(0.0, 27.0)
	p.bridge_b = Vector2(0.0, 9.0)
	p.river = PackedVector2Array([
		Vector2(-90.0, 30.0), Vector2(-52.0, 24.0), Vector2(-24.0, 20.0),
		Vector2(0.0, 18.0), Vector2(24.0, 20.0), Vector2(52.0, 26.0),
		Vector2(92.0, 34.0)])
	return p


## Посёлок на воде — деревня Ирмы. Река разлита широко и мелко, суши мало,
## горы отодвинуты: горизонт держит вода, а не камень.
static func _harbour() -> VillageProfile:
	var p := VillageProfile.new()
	p.id = &"irma"
	p.title = "Затон"
	# Улица вдоль берега с востока на запад, пристань уходит в залив на север.
	p.places = {
		&"forge": Vector2(-19.0, -5.0), &"shop": Vector2(-5.0, -15.0),
		&"storage": Vector2(11.0, -13.0), &"garden": Vector2(21.0, -1.0),
		&"training": Vector2(-22.0, 8.0), &"descend": Vector2(2.0, -29.0)}
	p.chapel = Vector2(17.0, 12.0)
	p.spawn = Vector2(-2.0, 29.0)
	p.landmarks = [
		{"kind": &"pier", "at": Vector2(0.0, -36.0), "yaw": PI},
		{"kind": &"pier", "at": Vector2(-19.0, -34.0), "yaw": PI},
		{"kind": &"fish", "at": Vector2(-11.0, -27.0), "yaw": 0.3},
		{"kind": &"fish", "at": Vector2(8.0, -25.0), "yaw": -0.4},
		{"kind": &"sawmill", "at": Vector2(24.0, 17.0), "yaw": 2.2},
		{"kind": &"campfire", "at": Vector2(-3.0, -2.0), "yaw": 0.0},
		{"kind": &"tower", "at": Vector2(26.0, -22.0), "yaw": 0.8}]
	p.river = PackedVector2Array([
		# Залив идёт за северной оградой: русло полуширины 15 м, проведённое через
		# двор, прорезало рельеф ниже уровня воды и топило улицы.
		Vector2(-96.0, -78.0), Vector2(-48.0, -66.0), Vector2(-10.0, -62.0),
		Vector2(30.0, -63.0), Vector2(66.0, -70.0), Vector2(104.0, -82.0)])
	# Русло вчетверо шире обычного и почти вровень с берегом — получается
	# разлив, а не канава.
	p.river_half = 15.0
	p.river_bank = 12.0
	p.river_depth = 1.6
	p.water_level = -0.5
	p.yard_relief = 1.6
	p.yard_base = 0.9
	p.mountain_height = 92.0
	p.mountain_start = 105.0
	p.hill_height = 5.0
	p.snow_line = 62.0
	p.ground_set = "brown_mud_03"
	p.dirt_set = "brown_mud_03"
	p.grass_tint = Color(0.58, 0.82, 0.52)
	p.dirt_tint = Color(0.78, 0.74, 0.66)
	# Свет ниже и холоднее, дымки больше: над водой всегда стоит марево.
	p.sun_angle = Vector3(-34.0, 118.0, 0.0)
	p.sun_color = Color(0.98, 0.93, 0.90)
	p.sun_energy = 2.0
	p.ambient = 1.05
	p.fog_color = Color(0.62, 0.70, 0.78)
	p.fog_density = 0.0011
	p.sky_zenith = Color(0.16, 0.32, 0.55)
	p.sky_horizon = Color(0.74, 0.79, 0.82)
	p.cloud_cover = 0.36
	p.tree_count = 150
	p.tree_height = Vector2(6.0, 12.0)
	p.grass_count = 4000
	p.grass_colour = Color(0.30, 0.40, 0.20)
	return p


## Чаща — деревня Верна. Лес подступает вплотную, свет пробивается пятнами,
## горизонта почти нет: его закрывают стволы.
static func _woodland() -> VillageProfile:
	var p := VillageProfile.new()
	p.id = &"vern"
	p.title = "Чаща"
	# Поляна среди леса: постройки разбросаны по прогалинам, в центре круг камней.
	p.places = {
		&"forge": Vector2(-20.0, 7.0), &"shop": Vector2(-4.0, -16.0),
		&"storage": Vector2(18.0, -6.0), &"garden": Vector2(7.0, 18.0),
		&"training": Vector2(-16.0, -15.0), &"descend": Vector2(0.0, -30.0)}
	p.chapel = Vector2(22.0, 14.0)
	p.spawn = Vector2(4.0, 30.0)
	p.landmarks = [
		{"kind": &"stones", "at": Vector2(-1.0, 3.0), "yaw": 0.0},
		{"kind": &"ruin", "at": Vector2(-25.0, -23.0), "yaw": 1.1},
		{"kind": &"sawmill", "at": Vector2(21.0, 23.0), "yaw": -0.7},
		{"kind": &"paddock", "at": Vector2(-25.0, 19.0), "yaw": 0.2},
		{"kind": &"graveyard", "at": Vector2(25.0, -21.0), "yaw": -1.2},
		{"kind": &"campfire", "at": Vector2(9.0, -2.0), "yaw": 0.0}]
	p.river = PackedVector2Array([
		Vector2(-80.0, 52.0), Vector2(-40.0, 47.0), Vector2(-6.0, 45.0),
		Vector2(30.0, 46.0), Vector2(72.0, 52.0)])
	p.river_half = 3.4
	p.river_bank = 4.0
	p.river_depth = 1.0
	p.mountain_height = 110.0
	p.mountain_start = 95.0
	p.hill_height = 14.0
	p.yard_relief = 3.6
	p.tree_line = 70.0
	p.snow_line = 88.0
	p.ground_set = "forest_ground_04"
	p.grass_tint = Color(0.48, 0.78, 0.38)
	p.dirt_tint = Color(0.72, 0.66, 0.55)
	p.rock_tint = Color(0.74, 0.78, 0.72)
	# Солнце низкое и тёплое, насыщенность выше: под пологом цвет глубже.
	p.sun_angle = Vector3(-28.0, 156.0, 0.0)
	p.sun_color = Color(1.0, 0.90, 0.72)
	p.sun_energy = 2.6
	p.ambient = 0.62
	p.fog_color = Color(0.46, 0.56, 0.48)
	p.fog_density = 0.0016
	p.saturation = 0.86
	p.sky_zenith = Color(0.12, 0.26, 0.46)
	p.sky_horizon = Color(0.70, 0.74, 0.66)
	p.cloud_cover = 0.52
	# Втрое гуще леса и вдвое выше деревья — именно это делает место чащей.
	p.tree_count = 900
	p.tree_height = Vector2(12.0, 24.0)
	p.grass_count = 8000
	p.grass_colour = Color(0.24, 0.34, 0.14)
	p.needle_colour = Color(0.07, 0.13, 0.07)
	return p


## Снега — деревня Мары. Земля белая до самого двора, лес редкий и низкий,
## свет плоский и холодный, как в пасмурный зимний день.
static func _snowfield() -> VillageProfile:
	var p := VillageProfile.new()
	p.id = &"mara"
	p.title = "Стужа"
	# Тесный круг вокруг общего костра: в стужу жмутся друг к другу, а не тянутся
	# вдоль улицы.
	p.places = {
		&"forge": Vector2(-12.0, -7.0), &"shop": Vector2(13.0, -6.0),
		&"storage": Vector2(-13.0, 10.0), &"garden": Vector2(13.0, 11.0),
		&"training": Vector2(0.0, -20.0), &"descend": Vector2(0.0, -30.0)}
	p.chapel = Vector2(-21.0, -18.0)
	p.spawn = Vector2(0.0, 28.0)
	p.landmarks = [
		{"kind": &"campfire", "at": Vector2(0.0, 1.0), "yaw": 0.0},
		{"kind": &"tower", "at": Vector2(23.0, -18.0), "yaw": 0.9},
		{"kind": &"graveyard", "at": Vector2(-23.0, 17.0), "yaw": 0.4},
		{"kind": &"fish", "at": Vector2(21.0, 19.0), "yaw": -0.5},
		{"kind": &"ruin", "at": Vector2(-25.0, -4.0), "yaw": 1.6},
		{"kind": &"stones", "at": Vector2(25.0, 4.0), "yaw": 0.0}]
	p.river = PackedVector2Array([
		Vector2(-88.0, -56.0), Vector2(-44.0, -50.0), Vector2(-8.0, -47.0),
		Vector2(28.0, -49.0), Vector2(70.0, -56.0)])
	p.river_half = 5.0
	p.river_bank = 7.0
	p.river_depth = 1.4
	p.water_level = -0.6
	p.mountain_height = 190.0
	p.mountain_start = 52.0
	p.hill_height = 12.0
	p.yard_relief = 3.2
	p.tree_line = 30.0
	# Снеговая линия ниже уровня двора: белым становится всё, включая улицы
	# между домами.
	p.snow_line = -2.0
	p.snow_fade = 6.0
	p.ground_set = "snow_02"
	p.dirt_set = "brown_mud_03"
	p.grass_tint = Color(0.86, 0.90, 0.96)
	p.dirt_tint = Color(0.70, 0.70, 0.72)
	p.rock_tint = Color(0.80, 0.83, 0.88)
	# Плоский холодный свет: резкие тени в снегах выглядят неправдоподобно.
	p.sun_angle = Vector3(-24.0, 96.0, 0.0)
	p.sun_color = Color(0.86, 0.90, 1.0)
	p.sun_energy = 1.7
	p.ambient = 1.35
	p.fog_color = Color(0.78, 0.83, 0.90)
	p.fog_density = 0.0018
	p.saturation = 0.55
	p.sky_zenith = Color(0.28, 0.40, 0.58)
	p.sky_horizon = Color(0.84, 0.87, 0.90)
	p.cloud_cover = 0.62
	p.tree_count = 120
	p.tree_height = Vector2(5.0, 10.0)
	p.grass_count = 900
	p.grass_colour = Color(0.30, 0.32, 0.30)
	p.needle_colour = Color(0.10, 0.15, 0.13)
	return p
