class_name FlightCamera
extends Camera3D

@export var target: OwlController
@export var minimum_distance := 10.8
@export var maximum_distance := 16.5
@export var minimum_fov := 61.0
@export var maximum_fov := 75.0
@export var lateral_follow_ratio := 0.18
@export var vertical_follow_ratio := 0.14
@export var look_follow_ratio := 0.38

var speed_ratio := 0.0
var current_speed := 0.0
var shake_clock := 0.0
var blur_material: ShaderMaterial
var menu_view := false
var menu_clock := 0.0
var menu_position := Vector3(-10.0, 11.0, 86.0)
var menu_target := Vector3(1.8, 5.0, 8.0)
var longitudinal_follow_error := 0.0

func setup(player: OwlController, speed_blur_material: ShaderMaterial) -> void:
	target = player
	blur_material = speed_blur_material
	player.speed_changed.connect(_on_speed_changed)
	snap_to_target()

func snap_to_target() -> void:
	if not is_instance_valid(target):
		return
	if menu_view:
		global_position = menu_position
		look_at(menu_target, Vector3.UP)
		fov = 50.0
		return
	var target_transform := target.get_presentation_transform()
	global_position = target_transform.origin + Vector3.UP * 2.5 + target_transform.basis.z * minimum_distance
	look_at(target_transform.origin + Vector3.UP * 0.45, Vector3.UP)

func set_menu_view() -> void:
	menu_view = true
	menu_clock = 0.0
	snap_to_target()

func set_flight_view() -> void:
	menu_view = false
	if blur_material:
		blur_material.set_shader_parameter("intensity", 0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if menu_view:
		menu_clock += delta
		var drift := Vector3(sin(menu_clock * 0.22) * 0.22, sin(menu_clock * 0.31) * 0.1, 0)
		global_position = global_position.lerp(menu_position + drift, 1.0 - exp(-2.2 * delta))
		look_at(menu_target + Vector3(0, sin(menu_clock * 0.28) * 0.08, 0), Vector3.UP)
		fov = lerpf(fov, 50.0, 1.0 - exp(-3.0 * delta))
		if blur_material:
			blur_material.set_shader_parameter("intensity", 0.08)
		return
	# Follow the render-smoothed owl rather than the discrete physics body.
	var target_transform := target.get_presentation_transform()
	var target_position := target_transform.origin
	var target_forward := target_transform.basis.z
	shake_clock += delta * lerpf(7.0, 22.0, speed_ratio)
	var shaped_speed := smoothstep(0.12, 1.0, speed_ratio)
	var distance := lerpf(minimum_distance, maximum_distance, shaped_speed)
	var lift := lerpf(2.5, 3.8, shaped_speed)
	var shake_strength := pow(shaped_speed, 2.2) * 0.18
	var shake := Vector3(
		sin(shake_clock * 1.37),
		sin(shake_clock * 1.91 + 1.4),
		cos(shake_clock * 1.63)
	) * shake_strength
	# Forward shake reads as a speed-dependent hitch because the owl grows and
	# shrinks in frame. Keep shake only across and above the flight direction.
	shake -= target_forward * shake.dot(target_forward)
	# Arcade camera: a direct linear mapping from the render-space owl. There is
	# no second X/Y smoothing pass, so camera lag cannot turn input into jelly.
	var neutral_height := (target.minimum_height + target.maximum_height) * 0.5
	var height_offset := target_position.y - neutral_height
	var desired := Vector3(
		target_position.x * lateral_follow_ratio,
		neutral_height + lift + height_offset * vertical_follow_ratio,
		target_position.z
	) + target_forward * distance + shake
	global_position = desired
	longitudinal_follow_error = 0.0
	var look_target := Vector3(
		target_position.x * look_follow_ratio,
		neutral_height + 0.45 + height_offset * look_follow_ratio,
		target_position.z
	) - target_forward * lerpf(2.6, 5.8, shaped_speed)
	look_at(look_target, Vector3.UP)
	fov = lerpf(fov, lerpf(minimum_fov, maximum_fov, shaped_speed), 1.0 - exp(-5.0 * delta))
	if blur_material:
		blur_material.set_shader_parameter("intensity", smoothstep(0.62, 1.0, shaped_speed) * 0.72)

func _on_speed_changed(ratio: float, speed: float) -> void:
	speed_ratio = ratio
	current_speed = speed

func get_longitudinal_follow_error() -> float:
	return longitudinal_follow_error
