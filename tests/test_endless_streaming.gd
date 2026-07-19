extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	assert(packed != null, "Main scene must load")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var owl := main.get_node("CourierOwl") as OwlController
	var streamer := main.get_node("ProceduralWorldStreamer") as WorldStreamer
	assert(owl != null, "Courier owl must exist")
	assert(streamer != null, "World streamer must exist")
	assert(streamer.active_chunks.size() >= 8, "Initial look-ahead chunks must exist")

	var initial_cap := owl.get_speed_cap()
	owl.total_distance = 10_000.0
	var grown_cap := owl.get_speed_cap()
	assert(grown_cap > initial_cap, "Speed cap must grow with distance")
	owl.total_distance = 1_000_000.0
	assert(is_equal_approx(owl.get_speed_cap(), owl.maximum_speed + owl.maximum_speed_bonus), "Speed growth must converge to the designed cap")

	var maximum_active := 0
	for step in range(1, 81):
		owl.total_distance = step * 125.0
		owl.current_speed = minf(owl.get_speed_cap(), 40.0 + step * 0.25)
		streamer._update_chunks(false)
		maximum_active = maxi(maximum_active, streamer.active_chunks.size())
		assert(streamer.active_chunks.size() <= 16, "Chunk count must remain bounded")
		await process_frame

	var old_origin := streamer.origin_start_z
	owl.global_position.z = -1300.0
	streamer._process(0.016)
	assert(streamer.origin_start_z > old_origin, "Long runs must rebase the world origin")
	print("ENDLESS_STREAMING_OK active_max=%d speed_cap=%.1f chunks=%d" % [maximum_active, owl.get_speed_cap(), streamer.active_chunks.size()])
	quit(0)
