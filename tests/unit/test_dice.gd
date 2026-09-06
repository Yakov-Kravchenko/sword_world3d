extends TestCase

func suite_name() -> String:
	return "Кости"

func test_parse_simple() -> void:
	var f := Dice.parse("2d6+3")
	assert_eq(f.count, 2)
	assert_eq(f.sides, 6)
	assert_eq(f.flat, 3)
	assert_eq(f.maximum(), 15)
	assert_eq(f.average(), 10.0)

func test_parse_negative_and_bare() -> void:
	var f := Dice.parse("1d8-1")
	assert_eq(f.flat, -1)
	var g := Dice.parse("d20")
	assert_eq(g.count, 1)
	assert_eq(g.sides, 20)
	var h := Dice.parse("5")
	assert_eq(h.count, 0)
	assert_eq(h.flat, 5)

func test_roll_within_bounds() -> void:
	var rng := RngStream.new(42, &"test")
	for i: int in 200:
		var r := Dice.roll("3d6+2", rng)
		assert_between(float(r["total"]), 5.0, 20.0)

func test_crit_doubles_dice_not_flat() -> void:
	var rng := RngStream.new(7, &"test")
	for i: int in 100:
		var r := Dice.roll("2d6+4", rng, true)
		assert_between(float(r["total"]), 8.0, 28.0)
		assert_eq(int(r["rolls"].size()), 4)
