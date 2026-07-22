class_name DeadlyObstacle
extends Area3D

@export var death_reason := "СОВА СТОЛКНУЛАСЬ С ПРЕПЯТСТВИЕМ"
@export var spin_axis := Vector3.ZERO
@export var spin_speed := 0.0
@export var swing_axis := Vector3.ZERO
@export var swing_angle := 0.0
@export var swing_speed := 0.0
@export var drift := Vector3.ZERO
@export var drift_distance := 0.0
@export var drift_speed := 0.0
@export var fall_distance := 0.0
@export var fall_speed := 0.0
@export var light_pulse := 0.0
@export var animate_flock := false
@export var flock_flutter_speed := 5.5
@export var flock_flutter_amount := 0.18

var _clock := 0.0
var _start_position := Vector3.ZERO
var _start_rotation := Vector3.ZERO
var _lights: Array[Light3D] = []
var _base_light_energy: Array[float] = []
var _flock_members: Array[Node3D] = []
var _flock_positions: Array[Vector3] = []
var _flock_rotations: Array[Vector3] = []

func _ready() -> void:
	_start_position = position
	_start_rotation = rotation
	for node in find_children("*", "Light3D", true, false):
		var light := node as Light3D
		_lights.append(light)
		_base_light_energy.append(light.light_energy)
	for node in find_children("*", "Node3D", true, false):
		if node.has_meta("flock_member"):
			var member := node as Node3D
			_flock_members.append(member)
			_flock_positions.append(member.position)
			_flock_rotations.append(member.rotation)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_clock += delta
	if spin_axis.length_squared() > 0.0 and spin_speed != 0.0:
		rotate_object_local(spin_axis.normalized(), spin_speed * delta)
	if swing_axis.length_squared() > 0.0 and swing_angle != 0.0:
		rotation = _start_rotation + swing_axis.normalized() * sin(_clock * swing_speed) * swing_angle
	if drift.length_squared() > 0.0 and drift_distance != 0.0:
		position = _start_position + drift.normalized() * sin(_clock * drift_speed) * drift_distance
	if fall_distance > 0.0 and fall_speed > 0.0:
		position.y = _start_position.y - fmod(_clock * fall_speed, fall_distance)
	if light_pulse > 0.0:
		var flicker := sin(_clock * 9.0) * 0.55 + sin(_clock * 17.0) * 0.3 + sin(_clock * 31.0) * 0.15
		for light_index in range(_lights.size()):
			_lights[light_index].light_energy = _base_light_energy[light_index] * (1.0 + flicker * light_pulse)
	if animate_flock:
		for member_index in range(_flock_members.size()):
			var flutter := sin(_clock * flock_flutter_speed + member_index * 0.83)
			_flock_members[member_index].position = _flock_positions[member_index] + Vector3(0, flutter * flock_flutter_amount, 0)
			_flock_members[member_index].rotation = _flock_rotations[member_index] + Vector3(flutter * 0.05, 0, flutter * 0.12)

func _on_body_entered(body: Node3D) -> void:
	if body is OwlController:
		var owl := body as OwlController
		if owl.alive and owl.flight_enabled:
			owl.kill(death_reason)
