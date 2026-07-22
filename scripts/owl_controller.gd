class_name OwlController
extends CharacterBody3D

signal speed_changed(speed_ratio: float, speed: float)
signal distance_changed(total_distance: float)
signal forward_step(distance: float)
signal coin_count_changed(total: int)
signal died(reason: String)

@export var base_forward_speed := 22.0
@export var maximum_forward_speed := 78.0
@export var forward_acceleration := 7.0
@export var speed_step_distance := 250.0
@export var speed_step_multiplier := 1.2
@export var base_flap_rate := 5.8
@export var starting_flap_rate_multiplier := 1.2
@export var flap_rate_step_multiplier := 1.1
@export var lateral_limit := 5.2
@export var minimum_height := 3.2
@export var maximum_height := 11.8
@export var keyboard_position_speed := 15.0
@export var plane_velocity_limit := 22.0
@export var mouse_position_sensitivity := 0.012
@export_range(0.016, 0.05, 0.001) var mouse_resample_window := 0.032
@export var mouse_braking := 18.0
@export var death_ground_height := 0.78

var current_speed := 22.0
var pitch := 0.0
var plane_position := Vector2(0.0, 7.0)
var plane_velocity := Vector2.ZERO
var pending_mouse_delta := Vector2.ZERO
var mouse_impulse_velocities: Array[Vector2] = []
var mouse_impulse_remaining: Array[float] = []
var mouse_inertia_velocity := Vector2.ZERO
var flight_z := 72.0
@onready var presentation_anchor: Node3D = $PresentationAnchor
@onready var visual_root: Node3D = $PresentationAnchor/OwlVisual
@onready var left_wing: Node3D = $PresentationAnchor/OwlVisual/LeftWingPivot
@onready var right_wing: Node3D = $PresentationAnchor/OwlVisual/RightWingPivot
var flap_time := 0.0
var total_distance := 0.0
var collected_coins := 0
var speed_bonus := 0.0
var flight_enabled := false
var alive := true
var death_clock := 0.0
var menu_pose_active := false

func _ready() -> void:
	process_priority = -20
	Input.use_accumulated_input = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if menu_pose_active and not flight_enabled and alive:
		_animate_menu_pose(delta)
	elif flight_enabled and alive:
		var stick := Input.get_vector("move_left", "move_right", "move_down", "move_up")
		var mouse_delta := _consume_mouse_delta()
		_run_arcade_frame(delta, stick, mouse_delta)
		_sync_presentation_from_arcade()
		_animate_flight_pose(delta)
	elif not alive:
		_sync_presentation_from_physics()

func _input(event: InputEvent) -> void:
	if not flight_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pending_mouse_delta += event.screen_relative

func _physics_process(delta: float) -> void:
	if not alive:
		_death_fall(delta)
		return
	if not flight_enabled:
		velocity = Vector3.ZERO
		return
	speed_bonus = get_speed_bonus()
	current_speed = move_toward(current_speed, get_auto_speed_target(), forward_acceleration * delta)

	# The CharacterBody is only a collision proxy. The visible owl is driven by
	# the render-clock arcade controller; physics follows it for Area3D hits.
	var collision_target := Vector3(plane_position.x, plane_position.y, flight_z)
	velocity = (collision_target - global_position) / maxf(delta, 0.0001)
	# Endless-runner movement: the owl never advances in world Z. The streamed
	# world consumes the forward step and moves toward the stationary player.
	velocity.z = 0.0
	move_and_slide()
	var travelled := current_speed * delta
	total_distance += travelled
	forward_step.emit(travelled)

	var ratio := get_speed_ratio()
	speed_changed.emit(ratio, current_speed)
	distance_changed.emit(total_distance)

func _consume_mouse_delta() -> Vector2:
	var mouse_delta := pending_mouse_delta
	pending_mouse_delta = Vector2.ZERO
	return mouse_delta

func _run_arcade_frame(delta: float, stick: Vector2, mouse_delta: Vector2) -> void:
	if delta <= 0.0:
		plane_velocity = Vector2.ZERO
		return
	var previous_position := plane_position
	var raw_mouse_step := Vector2(
		mouse_delta.x * mouse_position_sensitivity,
		-mouse_delta.y * mouse_position_sensitivity
	)
	_prepare_mouse_reversal(raw_mouse_step)
	_queue_mouse_step(raw_mouse_step)
	var mouse_step := _integrate_mouse_steps(delta)
	var keyboard_velocity := stick.limit_length(1.0) * keyboard_position_speed

	# Digital/gamepad input owns every axis on which it is active. Previously a
	# harmless mouse packet could reverse a held key for one render frame, which
	# was the main source of the reported X/Y jerks.
	if absf(stick.x) > 0.0001:
		mouse_step.x = 0.0
		_clear_mouse_history_axis(true)
		mouse_inertia_velocity.x = 0.0
	if absf(stick.y) > 0.0001:
		mouse_step.y = 0.0
		_clear_mouse_history_axis(false)
		mouse_inertia_velocity.y = 0.0

	# This is velocity inertia, not a position spring. Active mouse input remains
	# exact and responsive; after the final packet the current velocity loses a
	# fixed amount per second until it reaches zero, so it cannot oscillate or
	# rubber-band. Reserve keyboard speed before applying mouse momentum.
	var requested_mouse_velocity := mouse_step / delta
	var remaining_mouse_speed := sqrt(maxf(
		plane_velocity_limit * plane_velocity_limit - keyboard_velocity.length_squared(),
		0.0
	))
	requested_mouse_velocity = requested_mouse_velocity.limit_length(remaining_mouse_speed)
	_update_mouse_inertia(requested_mouse_velocity, raw_mouse_step, delta)
	mouse_inertia_velocity = mouse_inertia_velocity.limit_length(remaining_mouse_speed)
	var combined_step := (keyboard_velocity + mouse_inertia_velocity) * delta
	var intended_position := previous_position + combined_step
	plane_position = _clamp_plane_position(intended_position)
	_stop_inertia_at_corridor_edge(intended_position)
	plane_velocity = (plane_position - previous_position) / delta

func _update_mouse_inertia(requested_velocity: Vector2, fresh_mouse_step: Vector2, delta: float) -> void:
	mouse_inertia_velocity.x = _update_mouse_inertia_axis(
		mouse_inertia_velocity.x,
		requested_velocity.x,
		absf(fresh_mouse_step.x) > 0.00001,
		absf(requested_velocity.x) > 0.00001 or _has_mouse_impulse_axis(true),
		delta
	)
	mouse_inertia_velocity.y = _update_mouse_inertia_axis(
		mouse_inertia_velocity.y,
		requested_velocity.y,
		absf(fresh_mouse_step.y) > 0.00001,
		absf(requested_velocity.y) > 0.00001 or _has_mouse_impulse_axis(false),
		delta
	)

func _update_mouse_inertia_axis(current: float, requested: float, has_fresh_input: bool, has_buffered_input: bool, delta: float) -> float:
	if has_fresh_input:
		return requested
	if has_buffered_input:
		return current
	return move_toward(current, 0.0, mouse_braking * delta)

func _has_mouse_impulse_axis(horizontal: bool) -> bool:
	for impulse_velocity in mouse_impulse_velocities:
		var axis_velocity := impulse_velocity.x if horizontal else impulse_velocity.y
		if absf(axis_velocity) > 0.00001:
			return true
	return false

func _stop_inertia_at_corridor_edge(intended_position: Vector2) -> void:
	if not is_equal_approx(intended_position.x, plane_position.x):
		mouse_inertia_velocity.x = 0.0
	if not is_equal_approx(intended_position.y, plane_position.y):
		mouse_inertia_velocity.y = 0.0

func _prepare_mouse_reversal(raw_step: Vector2) -> void:
	var history_sum := Vector2.ZERO
	for historical_velocity in mouse_impulse_velocities:
		history_sum += historical_velocity
	if absf(raw_step.x) > 0.00001 and raw_step.x * history_sum.x < 0.0:
		_clear_mouse_history_axis(true)
	if absf(raw_step.y) > 0.00001 and raw_step.y * history_sum.y < 0.0:
		_clear_mouse_history_axis(false)

func _queue_mouse_step(raw_step: Vector2) -> void:
	if raw_step.is_zero_approx():
		return
	var safe_window := maxf(mouse_resample_window, 0.001)
	mouse_impulse_velocities.append(raw_step / safe_window)
	mouse_impulse_remaining.append(safe_window)

func _integrate_mouse_steps(delta: float) -> Vector2:
	var integrated_step := Vector2.ZERO
	for impulse_index in range(mouse_impulse_remaining.size() - 1, -1, -1):
		var active_time := minf(delta, mouse_impulse_remaining[impulse_index])
		integrated_step += mouse_impulse_velocities[impulse_index] * active_time
		mouse_impulse_remaining[impulse_index] -= active_time
		if mouse_impulse_remaining[impulse_index] <= 0.000001:
			mouse_impulse_remaining.remove_at(impulse_index)
			mouse_impulse_velocities.remove_at(impulse_index)
	return integrated_step

func _clear_mouse_history_axis(horizontal: bool) -> void:
	for history_index in range(mouse_impulse_velocities.size()):
		if horizontal:
			mouse_impulse_velocities[history_index].x = 0.0
		else:
			mouse_impulse_velocities[history_index].y = 0.0

func _clamp_plane_position(value: Vector2) -> Vector2:
	return Vector2(
		clampf(value.x, -lateral_limit, lateral_limit),
		clampf(value.y, minimum_height, maximum_height)
	)

func _sync_presentation_from_arcade() -> void:
	presentation_anchor.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(plane_position.x, plane_position.y, flight_z)
	)

func _sync_presentation_from_physics() -> void:
	presentation_anchor.global_transform = get_global_transform_interpolated()

func _animate_flight_pose(delta: float) -> void:
	var ratio := get_speed_ratio()
	var lift_effort := clampf(absf(plane_velocity.y) / plane_velocity_limit, 0.0, 1.0)
	flap_time += delta * (get_flap_rate() + lift_effort * 2.2)
	var flap := sin(flap_time) * (lerpf(0.4, 0.7, ratio) + lift_effort * 0.12)
	left_wing.rotation.z = flap + 0.18
	right_wing.rotation.z = -flap - 0.18
	# Forward is -Z in Godot, so positive X rotation raises the beak.
	pitch = clampf(plane_velocity.y / plane_velocity_limit, -0.65, 0.65)
	var turn_ratio := plane_velocity.x / plane_velocity_limit
	var pose_blend := 1.0 - exp(-11.0 * delta)
	visual_root.rotation.x = lerpf(visual_root.rotation.x, pitch * 0.75, pose_blend)
	visual_root.rotation.y = lerpf(visual_root.rotation.y, -turn_ratio * 0.08, pose_blend)
	visual_root.rotation.z = lerpf(visual_root.rotation.z, -turn_ratio * 0.34, pose_blend)
	visual_root.position = Vector3.ZERO

func get_speed_bonus() -> float:
	return get_auto_speed_target() - base_forward_speed

func get_speed_cap() -> float:
	return maximum_forward_speed

func get_cruise_target() -> float:
	return get_auto_speed_target()

func get_auto_speed_target() -> float:
	var completed_steps := floori(maxf(total_distance, 0.0) / speed_step_distance)
	return minf(base_forward_speed * pow(speed_step_multiplier, completed_steps), maximum_forward_speed)

func get_speed_ratio() -> float:
	return inverse_lerp(base_forward_speed, maximum_forward_speed, current_speed)

func get_flap_rate() -> float:
	var speed_steps := 0.0
	if speed_step_multiplier > 1.0001 and base_forward_speed > 0.0:
		var safe_speed := maxf(current_speed, base_forward_speed)
		speed_steps = log(safe_speed / base_forward_speed) / log(speed_step_multiplier)
	return base_flap_rate * starting_flap_rate_multiplier * pow(flap_rate_step_multiplier, speed_steps)

func collect_coin() -> bool:
	if not alive or not flight_enabled:
		return false
	collected_coins += 1
	coin_count_changed.emit(collected_coins)
	return true

func set_flight_enabled(value: bool) -> void:
	var should_fly := value and alive
	_clear_mouse_input()
	plane_velocity = Vector2.ZERO
	if should_fly:
		menu_pose_active = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		flight_enabled = true
	else:
		flight_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _clear_mouse_input() -> void:
	pending_mouse_delta = Vector2.ZERO
	mouse_impulse_velocities.clear()
	mouse_impulse_remaining.clear()
	mouse_inertia_velocity = Vector2.ZERO

func reset_flight(spawn_position: Vector3) -> void:
	global_position = spawn_position
	flight_z = spawn_position.z
	global_rotation = Vector3.ZERO
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	current_speed = base_forward_speed
	pitch = 0.0
	plane_position = Vector2(
		clampf(spawn_position.x, -lateral_limit, lateral_limit),
		clampf(spawn_position.y, minimum_height, maximum_height)
	)
	plane_velocity = Vector2.ZERO
	_clear_mouse_input()
	flap_time = 0.0
	total_distance = 0.0
	collected_coins = 0
	coin_count_changed.emit(collected_coins)
	speed_bonus = 0.0
	death_clock = 0.0
	menu_pose_active = false
	alive = true
	visual_root.rotation = Vector3.ZERO
	visual_root.position = Vector3.ZERO
	visual_root.scale = Vector3.ONE
	left_wing.position = Vector3(-0.48, 0.08, 0.0)
	right_wing.position = Vector3(0.48, 0.08, 0.0)
	left_wing.scale = Vector3.ONE
	right_wing.scale = Vector3.ONE
	left_wing.rotation = Vector3.ZERO
	right_wing.rotation = Vector3.ZERO
	show()
	presentation_anchor.global_transform = global_transform

func set_perched_pose() -> void:
	flight_enabled = false
	menu_pose_active = false
	velocity = Vector3.ZERO
	presentation_anchor.global_transform = global_transform
	visual_root.rotation = Vector3(0.08, 0, 0)
	visual_root.scale = Vector3.ONE * 1.35
	left_wing.position = Vector3(-0.30, 0.32, 0.05)
	right_wing.position = Vector3(0.30, 0.32, 0.05)
	left_wing.scale = Vector3.ONE * 0.92
	right_wing.scale = Vector3.ONE * 0.92
	left_wing.rotation = Vector3(0.02, 0.08, 1.18)
	right_wing.rotation = Vector3(0.02, -0.08, -1.18)

func set_menu_hero_pose() -> void:
	flight_enabled = false
	menu_pose_active = true
	velocity = Vector3.ZERO
	presentation_anchor.global_transform = global_transform
	flap_time = 0.0
	visual_root.rotation = Vector3(-0.08, deg_to_rad(-30.0), -0.04)
	visual_root.scale = Vector3.ONE * 2.35
	left_wing.position = Vector3(-0.30, 0.32, 0.05)
	right_wing.position = Vector3(0.30, 0.32, 0.05)
	left_wing.scale = Vector3.ONE * 0.92
	right_wing.scale = Vector3.ONE * 0.92
	left_wing.rotation = Vector3(0.02, 0.08, 1.18)
	right_wing.rotation = Vector3(0.02, -0.08, -1.18)

func _animate_menu_pose(delta: float) -> void:
	flap_time += delta * 1.7
	var feather_breath := sin(flap_time) * 0.018
	left_wing.rotation.z = 1.18 + feather_breath
	right_wing.rotation.z = -1.18 - feather_breath
	left_wing.rotation.y = 0.08 + sin(flap_time * 0.5) * 0.012
	right_wing.rotation.y = -left_wing.rotation.y

func kill(reason: String) -> void:
	if not alive:
		return
	alive = false
	flight_enabled = false
	menu_pose_active = false
	death_clock = 0.0
	global_position = Vector3(plane_position.x, plane_position.y, flight_z)
	reset_physics_interpolation()
	presentation_anchor.global_transform = global_transform
	velocity = Vector3(0, -2.5, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	died.emit(reason)

func _death_fall(delta: float) -> void:
	if global_position.y <= death_ground_height:
		_land_after_death()
		return
	death_clock += delta
	velocity.y -= 18.0 * delta
	velocity.x = move_toward(velocity.x, 0.0, 1.8 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 1.2 * delta)
	move_and_slide()
	if global_position.y <= death_ground_height:
		_land_after_death()
		return
	visual_root.rotate_z(2.6 * delta)
	visual_root.rotate_x(1.35 * delta)

func get_presentation_transform() -> Transform3D:
	return presentation_anchor.global_transform

func _land_after_death() -> void:
	var landed_position := global_position
	landed_position.y = death_ground_height
	global_position = landed_position
	velocity = Vector3.ZERO
