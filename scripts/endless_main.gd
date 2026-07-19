extends Node3D

@onready var owl: OwlController = $CourierOwl
@onready var streamer: WorldStreamer = $ProceduralWorldStreamer
@onready var flight_camera: FlightCamera = $FlightCamera
@onready var world_environment: WorldEnvironment = $Environment/WorldEnvironment
@onready var sunset_light: DirectionalLight3D = $Environment/SunsetLight
@onready var moon_light: DirectionalLight3D = $Environment/MoonLight
@onready var blur_material: ShaderMaterial = $SpeedBlur/BlurRect.material
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var speed_label: Label = $HUD/SpeedLabel
@onready var distance_label: Label = $HUD/DistanceLabel
@onready var message_label: Label = $HUD/MessageLabel

var sky_material: ProceduralSkyMaterial
var deliveries := 0
var elapsed := 0.0
var materials := {}

func _ready() -> void:
	_setup_materials()
	_setup_environment()
	flight_camera.setup(owl, blur_material)
	streamer.castle_reached.connect(_on_castle_reached)
	streamer.setup(owl, materials)

func _process(delta: float) -> void:
	elapsed += delta
	var night_amount := smoothstep(0.0, 1.0, clampf(elapsed / 150.0, 0.0, 1.0))
	sky_material.sky_top_color = Color("9f4f78").lerp(Color("07122c"), night_amount)
	sky_material.sky_horizon_color = Color("f29a68").lerp(Color("2b345f"), night_amount)
	sky_material.ground_horizon_color = Color("8c5261").lerp(Color("11182d"), night_amount)
	sunset_light.light_energy = lerpf(1.75, 0.06, night_amount)
	moon_light.light_energy = lerpf(0.04, 0.82, night_amount)
	if is_instance_valid(owl):
		speed_label.text = "СКОРОСТЬ  %02d" % roundi(owl.current_speed)
		distance_label.text = "МАРШРУТ  %.1f км    ПИСЕМ  %d" % [owl.total_distance / 1000.0, deliveries]

func _setup_materials() -> void:
	materials.stone = _make_material(Color("555664"), 0.78)
	materials.stone_light = _make_material(Color("777480"), 0.7)
	materials.road = _make_material(Color("77717a"), 0.38, 0.08)
	materials.road_dark = _make_material(Color("57545d"), 0.46, 0.04)
	materials.grass = _make_material(Color("273f35"), 0.94)
	materials.trunk = _make_material(Color("3d2a2e"), 0.9)
	materials.leaves = _make_material(Color("253c42"), 0.86)
	materials.leaves_warm = _make_material(Color("55423e"), 0.84)
	materials.roof = _make_material(Color("272536"), 0.58, 0.12)
	materials.gold = _make_material(Color("c7863b"), 0.38, 0.58, Color("6f2d09"), 1.7)
	materials.fire = _make_material(Color("ff9a45"), 0.3, 0.0, Color("ff642e"), 3.5)

func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.58
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b27882")
	environment.fog_light_energy = 0.52
	environment.fog_density = 0.006
	environment.fog_sky_affect = 0.55
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("9f4f78")
	sky_material.sky_horizon_color = Color("f29a68")
	sky_material.ground_bottom_color = Color("151526")
	sky_material.ground_horizon_color = Color("8c5261")
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment

func _on_castle_reached(chapter: int) -> void:
	deliveries += 1
	objective_label.text = "ГЛАВА %d ЗАВЕРШЕНА  •  СЛЕДУЮЩЕЕ ПИСЬМО ПРИНЯТО" % chapter
	message_label.modulate.a = 1.0
	message_label.text = "ПИСЬМО №%d ДОСТАВЛЕНО\nМаршрут продолжается" % deliveries
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(message_label, "modulate:a", 0.0, 1.7)
	tween.tween_callback(func(): objective_label.text = "ЛУННАЯ ПОЧТА  •  СЛЕДУЮЩИЙ ЗАМОК ВПЕРЕДИ")

func _make_material(color: Color, roughness: float, metallic := 0.0, emission := Color.BLACK, emission_energy := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material
