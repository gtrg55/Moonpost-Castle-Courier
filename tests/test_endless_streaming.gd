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
	assert(streamer.active_chunks.size() >= 6, "Initial look-ahead chunks must cover at least 240 meters")
	assert(streamer.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "The moving world root must interpolate between physics ticks")
	streamer.set_process(false)
	streamer.set_streaming_enabled(true)
	owl.total_distance = WorldStreamer.CHUNK_LENGTH
	streamer._update_chunks(false)
	var queued_chunk_index := streamer.base_chunks_ahead + 1
	assert(streamer.pending_chunk_jobs.size() == 1 and (streamer.active_chunks[queued_chunk_index] as Node3D).get_child_count() == 0, "A runtime chunk must be queued without building hundreds of nodes in one frame")
	for _chunk_phase in range(10):
		streamer._build_next_chunk_phase()
	var phased_chunk := streamer.active_chunks[queued_chunk_index] as Node3D
	assert(streamer.pending_chunk_jobs.is_empty() and phased_chunk.get_child_count() > 0, "A queued chunk must finish after ten small render phases")
	var synchronous_chunk := streamer._build_chunk(queued_chunk_index)
	assert(phased_chunk.get_child_count() == synchronous_chunk.get_child_count(), "Time-sliced and synchronous chunk builds must remain deterministic")
	synchronous_chunk.queue_free()
	streamer.set_streaming_enabled(false)
	streamer.set_process(true)
	owl.total_distance = 0.0

	assert(not InputMap.has_action("accelerate") and not InputMap.has_action("brake"), "Manual acceleration and braking must be removed")
	var initial_target := owl.get_auto_speed_target()
	assert(is_equal_approx(initial_target, 22.0), "Base automatic speed must be 22")
	owl.total_distance = 249.9
	assert(is_equal_approx(owl.get_auto_speed_target(), initial_target), "Speed must remain stable until the next 250 meter mark")
	owl.total_distance = 250.0
	assert(is_equal_approx(owl.get_auto_speed_target(), initial_target * 1.2), "Every 250 meters must multiply target speed by 1.2")
	owl.total_distance = 500.0
	assert(is_equal_approx(owl.get_auto_speed_target(), initial_target * 1.44), "Speed multipliers must accumulate by distance")
	owl.total_distance = 1_000_000.0
	assert(is_equal_approx(owl.get_auto_speed_target(), owl.maximum_forward_speed), "Automatic speed growth must converge to the designed cap")
	owl.current_speed = owl.base_forward_speed
	var starting_flap_rate := owl.get_flap_rate()
	assert(is_equal_approx(starting_flap_rate, owl.base_flap_rate * 1.2), "Starting flight must flap 1.2 times faster than the original base animation")
	owl.current_speed = owl.base_forward_speed * owl.speed_step_multiplier
	assert(is_equal_approx(owl.get_flap_rate(), starting_flap_rate * 1.1), "Every 1.2 flight-speed increase must multiply wing flap rate by 1.1")
	owl.current_speed = owl.base_forward_speed * pow(owl.speed_step_multiplier, 2.0)
	assert(is_equal_approx(owl.get_flap_rate(), starting_flap_rate * pow(1.1, 2.0)), "Wing flap multipliers must accumulate with flight speed")
	owl.set_process(false)
	owl.set_physics_process(false)
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	owl.set_flight_enabled(true)
	assert(owl.mouse_position_sensitivity >= 0.012 and owl.mouse_resample_window <= 0.04 and owl.plane_velocity_limit >= 22.0, "Mouse and X/Y steering must be responsive with only a short finite packet-smoothing window")
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	var diagonal_input := Vector2(0.6, 0.8)
	var start_plane := owl.plane_position
	owl._run_arcade_frame(1.0 / 60.0, diagonal_input, Vector2.ZERO)
	var first_plane := owl.plane_position
	owl._run_arcade_frame(1.0 / 60.0, diagonal_input, Vector2.ZERO)
	var second_plane := owl.plane_position
	assert(first_plane.x > start_plane.x and second_plane.x > first_plane.x, "Arcade X steering must move on the first rendered frame")
	assert(first_plane.y > start_plane.y and second_plane.y > first_plane.y, "Arcade Y steering must move on the first rendered frame")
	assert(absf(second_plane.distance_to(start_plane) - owl.keyboard_position_speed * 2.0 / 60.0) < 0.0001, "Two held-input frames must produce exactly two direct arcade steps")
	assert(owl.plane_velocity.x > 0.0 and owl.plane_velocity.y > 0.0 and absf(owl.plane_velocity.length() - owl.keyboard_position_speed) < 0.01, "Arcade steering must expose the requested direct render velocity")
	owl._sync_presentation_from_arcade()
	owl._animate_flight_pose(0.1)
	assert(owl.visual_root.rotation.z < 0.0 and owl.visual_root.rotation.y < 0.0 and owl.visual_root.rotation.x > 0.0, "Owl body must bank, turn, and raise its beak during a climbing maneuver")
	assert(absf(owl.visual_root.position.y) < 0.001, "Flight pose must not add rubbery body bobbing")
	var previous_plane := owl.plane_position
	var previous_step_distance := second_plane.distance_to(first_plane)
	for _direct_step in range(10):
		owl._run_arcade_frame(1.0 / 60.0, diagonal_input, Vector2.ZERO)
		assert(owl.plane_position.x > previous_plane.x and owl.plane_position.y > previous_plane.y, "Held X/Y steering must keep one direction without a reversal pulse")
		var step_distance := owl.plane_position.distance_to(previous_plane)
		assert(absf(step_distance - previous_step_distance) < 0.0001, "Fixed-delta arcade steps must never alternate between shorter and longer movement")
		previous_plane = owl.plane_position
		previous_step_distance = step_distance

	# Held keyboard input used to move a target which the owl then chased. That
	# path was frame-rate dependent and created alternating short/long X/Y steps.
	for checkpoint in [0.10, 0.25, 0.50]:
		var held_30 := _simulate_held_input(owl, 30, checkpoint, Vector2.RIGHT)
		var held_60 := _simulate_held_input(owl, 60, checkpoint, Vector2.RIGHT)
		var held_120 := _simulate_held_input(owl, 120, checkpoint, Vector2.RIGHT)
		assert(absf(held_30.x - held_60.x) < 0.03 and absf(held_60.x - held_120.x) < 0.03, "Held X/Y input must follow the same checkpoints at 30, 60, and 120 rendered FPS")

	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	for _held_frame in range(15):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.RIGHT, Vector2.ZERO)
	var release_position := owl.plane_position
	owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
	assert(owl.plane_position.distance_to(release_position) < 0.0001 and owl.plane_velocity.is_zero_approx(), "Keyboard release must stop immediately without a jelly-like tail")
	owl._run_arcade_frame(1.0 / 60.0, Vector2.LEFT, Vector2.ZERO)
	assert(owl.plane_velocity.x < 0.0, "Keyboard reversal must take effect on the next rendered frame")

	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		owl.reset_flight(Vector3(0.0, 7.0, 72.0))
		for _boundary_frame in range(240):
			owl._run_arcade_frame(1.0 / 120.0, direction, Vector2.ZERO)
		var boundary_position := owl.plane_position
		for _boundary_settle_frame in range(20):
			owl._run_arcade_frame(1.0 / 120.0, direction, Vector2.ZERO)
		assert(owl.plane_position.distance_to(boundary_position) < 0.0001 and absf(owl.plane_position.x) <= owl.lateral_limit + 0.0001 and owl.plane_position.y >= owl.minimum_height - 0.0001 and owl.plane_position.y <= owl.maximum_height + 0.0001, "Holding any direction at a corridor edge must stay completely stable")
		owl._run_arcade_frame(1.0 / 120.0, -direction, Vector2.ZERO)
		assert(owl.plane_velocity.dot(-direction) > 0.0, "The owl must leave a corridor edge on the first opposite-input frame")

	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	owl.set_flight_enabled(true)
	owl.pending_mouse_delta = Vector2(24.0, -12.0)
	var consumed_mouse := owl._consume_mouse_delta()
	assert(consumed_mouse == Vector2(24.0, -12.0) and owl.pending_mouse_delta.is_zero_approx(), "Mouse steering must be consumed once on the render clock")
	var mouse_start_position := owl.plane_position
	owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, consumed_mouse)
	assert(owl.plane_position.x > mouse_start_position.x and owl.plane_position.y > mouse_start_position.y, "A mouse packet must move both requested axes on the first rendered frame")
	owl.pending_mouse_delta = Vector2(18.0, 9.0)
	owl.set_flight_enabled(false)
	assert(owl.pending_mouse_delta.is_zero_approx() and owl.mouse_impulse_velocities.is_empty() and owl.mouse_impulse_remaining.is_empty() and owl.mouse_inertia_velocity.is_zero_approx() and owl.plane_velocity.is_zero_approx(), "Pausing flight must clear every mouse impulse so resume cannot produce a ghost X/Y jerk")
	owl.set_flight_enabled(true)
	owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2(-48.0, 0.0))
	assert(owl.plane_velocity.x < 0.0, "Arcade reversal must take effect on the next rendered frame")
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2(-36.0, 0.0))
	owl._run_arcade_frame(1.0 / 60.0, Vector2.RIGHT, Vector2(-72.0, -72.0))
	assert(absf(owl.plane_velocity.x - owl.keyboard_position_speed) < 0.01, "Held keyboard input must own its axis and cannot be reversed or slowed by a mouse packet")
	assert(owl.plane_velocity.length() <= owl.plane_velocity_limit + 0.01, "Keyboard and mouse together must never create one oversized X/Y step")

	# Constant physical mouse speed must remain constant even when render frames
	# alternate between short and long durations.
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	for _fixed_mouse_frame in range(60):
		var fixed_delta := 1.0 / 60.0
		owl._run_arcade_frame(fixed_delta, Vector2.ZERO, Vector2(100.0 * fixed_delta, 0.0))
	var fixed_mouse_result := owl.plane_position
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	var paced_velocity_min := INF
	var paced_velocity_max := -INF
	for paced_pair in range(30):
		for paced_delta in [1.0 / 120.0, 1.0 / 40.0]:
			owl._run_arcade_frame(paced_delta, Vector2.ZERO, Vector2(100.0 * paced_delta, 0.0))
			if paced_pair >= 20:
				paced_velocity_min = minf(paced_velocity_min, owl.plane_velocity.x)
				paced_velocity_max = maxf(paced_velocity_max, owl.plane_velocity.x)
	assert(owl.plane_position.distance_to(fixed_mouse_result) < 0.01, "Mouse steering must reach the same position under uneven render pacing")
	var paced_velocity_span := paced_velocity_max - paced_velocity_min
	assert(paced_velocity_span < 0.15, "Uneven render pacing must keep mouse steering variation below a visible pulse (span %.3f)" % paced_velocity_span)

	# The OS may batch two render frames of equal physical mouse travel into one
	# packet. The finite time kernel must preserve total travel and keep the
	# resulting visible velocity pulse below a small fraction of mouse speed.
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	for _uniform_packet_frame in range(60):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2(2.0, 0.0))
	for _uniform_tail_frame in range(2):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
	var uniform_packet_position := owl.plane_position
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	var packet_velocity_min := INF
	var packet_velocity_max := -INF
	var previous_packet_position := owl.plane_position
	for packet_frame in range(60):
		var packet_delta := Vector2(4.0, 0.0) if packet_frame % 2 == 1 else Vector2.ZERO
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, packet_delta)
		var visible_packet_velocity := (owl.plane_position.x - previous_packet_position.x) * 60.0
		if packet_frame >= 12:
			packet_velocity_min = minf(packet_velocity_min, visible_packet_velocity)
			packet_velocity_max = maxf(packet_velocity_max, visible_packet_velocity)
		previous_packet_position = owl.plane_position
	for _packet_tail_frame in range(2):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
	var packet_endpoint_difference := owl.plane_position.distance_to(uniform_packet_position)
	assert(packet_endpoint_difference < 0.05, "Packet batching must preserve nearly the same overall X/Y travel (difference %.4f)" % packet_endpoint_difference)
	var packet_velocity_span := packet_velocity_max - packet_velocity_min
	assert(packet_velocity_span < 0.15, "Irregular mouse packets must not create a visible alternating X/Y velocity pulse (span %.3f)" % packet_velocity_span)

	# Mouse release keeps velocity rather than chasing a position target. The
	# linear brake creates weight, while monotonic speed guarantees there is no
	# spring-like overshoot, reversal, or jelly motion.
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	for _inertia_drive_frame in range(12):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2(8.0, 0.0))
	var release_start := owl.plane_position
	var previous_inertia_speed := owl.mouse_inertia_velocity.x
	var previous_inertia_position := owl.plane_position.x
	var inertia_stop_frame := -1
	for inertia_frame in range(40):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
		assert(owl.plane_position.x >= previous_inertia_position - 0.00001, "Mouse inertia must never reverse after release")
		assert(owl.mouse_inertia_velocity.x >= -0.00001, "Linear mouse braking must not overshoot through zero")
		if owl.mouse_impulse_velocities.is_empty():
			assert(owl.mouse_inertia_velocity.x <= previous_inertia_speed + 0.00001, "Released mouse speed must decrease monotonically without pulsing")
		previous_inertia_speed = owl.mouse_inertia_velocity.x
		previous_inertia_position = owl.plane_position.x
		if owl.mouse_inertia_velocity.is_zero_approx():
			inertia_stop_frame = inertia_frame
			break
	assert(owl.plane_position.x - release_start.x > 0.15, "Released mouse steering must visibly coast instead of stopping instantly")
	assert(inertia_stop_frame >= 2 and inertia_stop_frame < 30, "Mouse inertia must end in a short finite interval rather than leaving a jelly tail")
	var settled_inertia_position := owl.plane_position
	for _settled_inertia_frame in range(10):
		owl._run_arcade_frame(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
	assert(owl.plane_position.distance_to(settled_inertia_position) < 0.0001, "Once linear inertia reaches zero the owl must remain completely still")

	owl._run_arcade_frame(0.1, Vector2.UP, Vector2.ZERO)
	owl._animate_flight_pose(0.1)
	assert(owl.plane_velocity.y < 0.0 and owl.visual_root.rotation.x < 0.0, "Owl must lower its beak while descending")

	var maximum_active := 0
	for step in range(1, 81):
		owl.total_distance = step * 125.0
		owl.current_speed = minf(owl.maximum_forward_speed, 40.0 + step * 0.25)
		streamer._update_chunks(false)
		maximum_active = maxi(maximum_active, streamer.active_chunks.size())
		assert(streamer.active_chunks.size() <= 16, "Chunk count must remain bounded")
		await process_frame

	streamer.set_streaming_enabled(true)
	owl.alive = true
	owl.set_flight_enabled(true)
	owl.total_distance = 1_000_000.0
	owl.current_speed = owl.maximum_forward_speed
	owl.flight_z = owl.global_position.z
	var high_speed_owl_z := owl.global_position.z
	var high_speed_world_z := streamer.position.z
	for _physics_step in range(60):
		owl._physics_process(1.0 / 60.0)
	assert(is_equal_approx(owl.global_position.z, high_speed_owl_z), "Even at maximum speed the owl must have zero longitudinal displacement")
	assert(streamer.position.z - high_speed_world_z > 77.0, "At maximum speed the world must consume the full forward distance instead")

	var old_origin := streamer.origin_start_z
	streamer.position.z = WorldStreamer.REBASE_AMOUNT + 1.0
	streamer._rebase_world()
	assert(streamer.origin_start_z > old_origin and streamer.position.z < 2.0, "Long runs must rebase the moving world without relocating the owl")
	print("ENDLESS_STREAMING_OK active_max=%d speed_cap=%.1f chunks=%d" % [maximum_active, owl.maximum_forward_speed, streamer.active_chunks.size()])
	quit(0)

func _simulate_held_input(owl: OwlController, fps: int, seconds: float, direction: Vector2) -> Vector2:
	owl.reset_flight(Vector3(0.0, 7.0, 72.0))
	var frame_delta := 1.0 / float(fps)
	var frame_count := floori(seconds * float(fps))
	for _frame in range(frame_count):
		owl._run_arcade_frame(frame_delta, direction, Vector2.ZERO)
	var remainder := seconds - float(frame_count) * frame_delta
	if remainder > 0.000001:
		owl._run_arcade_frame(remainder, direction, Vector2.ZERO)
	return owl.plane_position
