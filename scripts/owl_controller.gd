class_name OwlController
extends CharacterBody3D

signal speed_changed(speed_ratio: float, speed: float)
signal distance_changed(total_distance: float)

@export var minimum_speed := 7.0
@export var cruising_speed := 15.0
@export var maximum_speed := 30.0
@export var acceleration := 13.0
@export var braking := 18.0
@export var yaw_rate := 1.45
@export var vertical_speed := 10.0
@export var mouse_sensitivity := 0.0022
@export var speed_growth_per_meter := 0.0022
@export var maximum_speed_bonus := 38.0

var current_speed := 10.0
var pitch := 0.0
var mouse_pitch_delta := 0.0
@onready var visual_root: Node3D = $OwlVisual
@onready var left_wing: Node3D = $OwlVisual/LeftWingPivot
@onready var right_wing: Node3D = $OwlVisual/RightWingPivot
var flap_time := 0.0
var total_distance := 0.0
var speed_bonus := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		mouse_pitch_delta = clampf(mouse_pitch_delta - event.relative.y * mouse_sensitivity, -0.65, 0.65)

func _physics_process(delta: float) -> void:
	var previous_position := global_position
	speed_bonus = get_speed_bonus()
	var throttle := Input.get_action_strength("accelerate")
	var brake_input := Input.get_action_strength("brake")
	var target_speed := get_cruise_target()
	if throttle > 0.01:
		target_speed = get_speed_cap()
	elif brake_input > 0.01:
		target_speed = minimum_speed + speed_bonus * 0.28
	var rate := braking if target_speed < current_speed else acceleration
	current_speed = move_toward(current_speed, target_speed, rate * delta)

	var yaw_input := Input.get_axis("turn_left", "turn_right")
	rotate_y(-yaw_input * yaw_rate * delta)
	var keyboard_pitch := Input.get_axis("descend", "ascend")
	pitch = lerpf(pitch, clampf(mouse_pitch_delta + keyboard_pitch * 0.38, -0.58, 0.58), 1.0 - exp(-5.0 * delta))

	var local_forward := Vector3(0.0, sin(pitch), -cos(pitch))
	var flight_direction := (global_basis * local_forward).normalized()
	velocity = flight_direction * current_speed
	move_and_slide()
	global_position.y = clampf(global_position.y, 2.0, 44.0)
	var travelled := Vector2(global_position.x - previous_position.x, global_position.z - previous_position.z).length()
	total_distance += travelled

	var ratio := inverse_lerp(minimum_speed, maximum_speed + speed_bonus, current_speed)
	flap_time += delta * lerpf(5.0, 11.0, ratio)
	var flap := sin(flap_time) * lerpf(0.38, 0.68, ratio)
	left_wing.rotation.z = flap + 0.18
	right_wing.rotation.z = -flap - 0.18
	visual_root.rotation.x = lerpf(visual_root.rotation.x, -pitch * 0.75, 1.0 - exp(-6.0 * delta))
	visual_root.rotation.z = lerpf(visual_root.rotation.z, -yaw_input * 0.42, 1.0 - exp(-7.0 * delta))
	speed_changed.emit(ratio, current_speed)
	distance_changed.emit(total_distance)

func get_speed_bonus() -> float:
	return minf(total_distance * speed_growth_per_meter, maximum_speed_bonus)

func get_speed_cap() -> float:
	return maximum_speed + get_speed_bonus()

func get_cruise_target() -> float:
	return cruising_speed + get_speed_bonus() * 0.72
