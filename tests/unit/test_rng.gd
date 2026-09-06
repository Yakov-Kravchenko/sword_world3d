extends TestCase

func suite_name() -> String:
	return "Детерминированный RNG"

func test_same_seed_same_sequence() -> void:
	var a := RngStream.new(1234, &"floor")
	var b := RngStream.new(1234, &"floor")
	for i: int in 50:
		assert_eq(a.randi_range(1, 1000), b.randi_range(1, 1000))

func test_different_streams_diverge() -> void:
	var a := RngStream.new(1234, &"floor")
	var b := RngStream.new(1234, &"loot")
	var same := 0
	for i: int in 50:
		if a.randi_range(1, 1000) == b.randi_range(1, 1000):
			same += 1
	assert_le(float(same), 10.0, "потоки не должны совпадать")

func test_state_roundtrip() -> void:
	var a := RngStream.new(99, &"combat")
	for i: int in 10:
		a.randi_range(1, 20)
	var snapshot := a.save_state()
	var expected: Array[int] = []
	for i: int in 5:
		expected.append(a.randi_range(1, 20))
	var b := RngStream.new(0, &"x")
	b.load_state(snapshot)
	for i: int in 5:
		assert_eq(b.randi_range(1, 20), expected[i], "состояние RNG должно восстанавливаться")

func test_weighted_pick_respects_weights() -> void:
	var rng := RngStream.new(5, &"w")
	var counts := {"a": 0, "b": 0}
	for i: int in 2000:
		counts[rng.pick_weighted(["a", "b"], [9.0, 1.0])] += 1
	assert_gt(float(counts["a"]), float(counts["b"]) * 4.0)
