extends TestCase

var grid: CombatGrid

func suite_name() -> String:
	return "Сетка и видимость"

func before_each() -> void:
	grid = CombatGrid.new(20, 20)
	for y: int in 20:
		for x: int in 20:
			grid.set_flags(Vector2i(x, y), 0)

func test_chebyshev_distance() -> void:
	assert_eq(CombatGrid.distance(Vector2i(0, 0), Vector2i(3, 3)), 3, "диагональ считается за 1")
	assert_eq(CombatGrid.distance(Vector2i(0, 0), Vector2i(5, 2)), 5)

func test_wall_blocks_line_of_sight() -> void:
	assert_true(grid.has_line_of_sight(Vector2i(1, 5), Vector2i(9, 5)))
	for y: int in 20:
		grid.add_flag(Vector2i(5, y), CombatGrid.FLAG_WALL)
	assert_false(grid.has_line_of_sight(Vector2i(1, 5), Vector2i(9, 5)))

func test_cover_bonus() -> void:
	grid.add_flag(Vector2i(5, 5), CombatGrid.FLAG_COVER_HALF)
	assert_eq(grid.cover_bonus(Vector2i(1, 5), Vector2i(9, 5), 2, 5), 2)
	grid.add_flag(Vector2i(6, 5), CombatGrid.FLAG_COVER_THREE_QUARTER)
	assert_eq(grid.cover_bonus(Vector2i(1, 5), Vector2i(9, 5), 2, 5), 5)

func test_difficult_terrain_costs_two() -> void:
	var plain := grid.reachable(Vector2i(10, 10), 4, {})
	for y: int in 20:
		for x: int in 20:
			grid.add_flag(Vector2i(x, y), CombatGrid.FLAG_DIFFICULT)
	var rough := grid.reachable(Vector2i(10, 10), 4, {})
	assert_eq(grid.move_cost(Vector2i(10, 11)), 2)
	assert_gt(float(plain.size()), float(rough.size()), "труднопроходимость сокращает охват")
	assert_eq(rough.size(), 25, "бюджет 4 по цене 2 = радиус 2")

func test_reachable_respects_budget_and_blockers() -> void:
	var reach := grid.reachable(Vector2i(10, 10), 2, {})
	assert_eq(reach.size(), 25, "квадрат 5x5 вокруг старта")
	var blocked := {Vector2i(11, 10): true}
	var reach2 := grid.reachable(Vector2i(10, 10), 1, blocked)
	assert_false(reach2.has(Vector2i(11, 10)))

func test_path_avoids_walls() -> void:
	for y: int in range(0, 19):
		grid.add_flag(Vector2i(10, y), CombatGrid.FLAG_WALL)
	var path := grid.find_path(Vector2i(5, 5), Vector2i(15, 5), {})
	assert_gt(float(path.size()), 10.0, "путь должен обходить стену")
	for c: Vector2i in path:
		assert_false(grid.is_wall(c))
