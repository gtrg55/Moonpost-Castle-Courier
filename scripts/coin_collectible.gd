class_name CoinCollectible
extends Area3D

@export var spin_speed := 2.4
@export var bob_height := 0.22
@export var bob_speed := 2.6

var _clock := 0.0
var _rest_height := 0.0
var _collected := false

func _ready() -> void:
	_rest_height = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _collected:
		return
	_clock += delta
	rotation.y += spin_speed * delta
	position.y = _rest_height + sin(_clock * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if _collected or not body is OwlController:
		return
	if not (body as OwlController).collect_coin():
		return
	_collected = true
	set_deferred("monitoring", false)
	$CollisionShape3D.set_deferred("disabled", true)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property($Model, "scale", Vector3.ZERO, 0.18)
	tween.tween_property(self, "position:y", position.y + 0.8, 0.18)
	tween.finished.connect(queue_free)
