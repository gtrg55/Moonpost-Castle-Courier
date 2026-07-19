class_name FlightCamera
extends Camera3D

@export var target: OwlController
@export var minimum_distance := 8.5
@export var maximum_distance := 17.0
@export var minimum_fov := 61.0
@export var maximum_fov := 80.0

var speed_ratio := 0.0
var current_speed := 0.0
var shake_clock := 0.0
var blur_material: ShaderMaterial

func setup(player: OwlController, speed_blur_material: ShaderMaterial) -> void:
	target = player
	blur_material = speed_blur_material
	player.speed_changed.connect(_on_speed_changed)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
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
	var desired := target.global_position + Vector3.UP * lift + target.global_basis.z * distance + shake
	global_position = global_position.lerp(desired, 1.0 - exp(-7.5 * delta))
	var look_target := target.global_position + Vector3.UP * 0.45 - target.global_basis.z * lerpf(2.6, 5.8, shaped_speed)
	look_at(look_target, Vector3.UP)
	fov = lerpf(fov, lerpf(minimum_fov, maximum_fov, shaped_speed), 1.0 - exp(-5.0 * delta))
	if blur_material:
		blur_material.set_shader_parameter("intensity", smoothstep(0.62, 1.0, shaped_speed) * 0.72)

func _on_speed_changed(ratio: float, speed: float) -> void:
	speed_ratio = ratio
	current_speed = speed
