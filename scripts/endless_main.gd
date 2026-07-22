extends Node3D

@onready var owl: OwlController = $CourierOwl
@onready var streamer: WorldStreamer = $ProceduralWorldStreamer
@onready var flight_camera: FlightCamera = $FlightCamera
@onready var world_environment: WorldEnvironment = $Environment/WorldEnvironment
@onready var sunset_light: DirectionalLight3D = $Environment/SunsetLight
@onready var moon_light: DirectionalLight3D = $Environment/MoonLight
@onready var blur_material: ShaderMaterial = $SpeedBlur/BlurRect.material
@onready var speed_label: Label = $HUD/SpeedLabel
@onready var distance_label: Label = $HUD/DistanceLabel
@onready var coin_label: Label = $HUD/CoinLabel
@onready var message_label: Label = $HUD/MessageLabel
@onready var zone_label: Label = $HUD/ZoneLabel
@onready var fps_label: Label = $HUD/FPSLabel
@onready var hud: CanvasLayer = $HUD
@onready var game_flow: GameFlowUI = $GameFlow
@onready var menu_stage: Node3D = $MenuStage
@onready var music_controller: MusicController = $MusicController

var sky_material: ProceduralSkyMaterial
var sky_layers: Node3D
var deliveries := 0
var elapsed := 0.0
var materials := {}
var active_zone_name := ""
var coin_pop_tween: Tween
var coin_fade_tween: Tween

enum GameState { MENU, PLAYING, PAUSED, DEAD }
var game_state := GameState.MENU

func _ready() -> void:
	Engine.max_fps = 60
	_setup_materials()
	_setup_environment()
	_setup_sky_details()
	flight_camera.setup(owl, blur_material)
	streamer.zone_changed.connect(_on_zone_changed)
	streamer.setup(owl, materials)
	owl.died.connect(_on_owl_died)
	owl.coin_count_changed.connect(_on_coin_count_changed)
	game_flow.start_requested.connect(_start_run)
	game_flow.restart_requested.connect(_start_run)
	game_flow.menu_requested.connect(_show_main_menu)
	game_flow.quit_requested.connect(_quit_game)
	game_flow.pause_toggled.connect(_toggle_pause)
	game_flow.resume_requested.connect(_resume_run)
	game_flow.settings_visibility_changed.connect(music_controller.set_settings_ducked)
	game_flow.music_volume_changed.connect(music_controller.set_volume_step)
	music_controller.volume_step_changed.connect(game_flow.set_music_volume_step)
	game_flow.set_music_volume_step(music_controller.volume_step)
	coin_label.pivot_offset = coin_label.size * 0.5
	_show_main_menu()

func _process(delta: float) -> void:
	fps_label.text = "FPS  %d" % Engine.get_frames_per_second()
	if is_instance_valid(sky_layers) and is_instance_valid(flight_camera):
		sky_layers.global_position = flight_camera.global_position
		sky_layers.global_rotation = Vector3.ZERO
	if game_state != GameState.PLAYING:
		return
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
	materials.stone_dark = _make_material(Color("30323d"), 0.86)
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
	materials.iron = _make_material(Color("171a21"), 0.42, 0.72)
	materials.wood = _make_material(Color("4b2925"), 0.9)
	materials.pumpkin = _make_material(Color("d96a20"), 0.62, 0.02, Color("7a2608"), 1.1)
	materials.fog = _make_material(Color(0.31, 0.12, 0.38, 0.58), 0.18, 0.0, Color("43185e"), 1.8)
	materials.blood_cloth = _make_material(Color("6d1f35"), 0.78)
	materials.moss = _make_material(Color("2e4738"), 0.96)
	materials.polished_stone = _make_material(Color("55596b"), 0.08, 0.58, Color("171b2b"), 0.45)

func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.58
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment.glow_strength = 1.05
	environment.glow_bloom = 0.1
	environment.volumetric_fog_enabled = false
	environment.fog_enabled = true
	environment.fog_light_color = Color("b27882")
	environment.fog_light_energy = 0.52
	environment.fog_density = 0.008
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

func _setup_sky_details() -> void:
	sky_layers = Node3D.new()
	sky_layers.name = "НебесныеСлои"
	add_child(sky_layers)
	sky_layers.global_position = flight_camera.global_position

	var cloud_shader := Shader.new()
	cloud_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 cloud_color : source_color = vec4(0.45, 0.29, 0.42, 0.30);
uniform float drift = 0.008;
uniform float offset = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * vec2(5.4, 2.2) + vec2(TIME * drift + offset, offset * 0.37);
	float shape = noise(p) * 0.62 + noise(p * 2.03 + 3.7) * 0.28 + noise(p * 4.1) * 0.10;
	float fade = smoothstep(0.02, 0.22, UV.y) * smoothstep(0.98, 0.68, UV.y);
	ALBEDO = cloud_color.rgb;
	EMISSION = cloud_color.rgb * 0.12;
	ALPHA = smoothstep(0.43, 0.72, shape) * fade * cloud_color.a;
}
"""
	var cloud_data := [
		["НижниеОблака", Vector3(0, 11, -96), Vector2(190, 42), Color(0.48, 0.30, 0.41, 0.34), 0.0, 0.008],
		["ВысокаяОблачнаяГряда", Vector3(-7, 19, -118), Vector2(220, 36), Color(0.31, 0.29, 0.46, 0.24), 4.2, -0.004],
	]
	for data in cloud_data:
		var cloud := MeshInstance3D.new()
		cloud.name = data[0]
		cloud.position = data[1]
		var quad := QuadMesh.new()
		quad.size = data[2]
		var cloud_material := ShaderMaterial.new()
		cloud_material.shader = cloud_shader
		cloud_material.set_shader_parameter("cloud_color", data[3])
		cloud_material.set_shader_parameter("offset", data[4])
		cloud_material.set_shader_parameter("drift", data[5])
		quad.material = cloud_material
		cloud.mesh = quad
		sky_layers.add_child(cloud)

	var moon := MeshInstance3D.new()
	moon.name = "ТуманнаяЛуна"
	moon.position = Vector3(30, 18, -92)
	var moon_quad := QuadMesh.new()
	moon_quad.size = Vector2(11.5, 11.5)
	var moon_shader := Shader.new()
	moon_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

void fragment() {
	float distance_to_center = length(UV - vec2(0.5));
	float disc = 1.0 - smoothstep(0.39, 0.46, distance_to_center);
	float halo = (1.0 - smoothstep(0.34, 0.5, distance_to_center)) * 0.28;
	vec3 moon_color = mix(vec3(1.0, 0.58, 0.34), vec3(1.0, 0.88, 0.69), disc);
	ALBEDO = moon_color;
	EMISSION = moon_color * (1.8 * disc + halo);
	ALPHA = max(disc * 0.78, halo);
}
"""
	var moon_material := ShaderMaterial.new()
	moon_material.shader = moon_shader
	moon_quad.material = moon_material
	moon.mesh = moon_quad
	sky_layers.add_child(moon)

func _register_zone_delivery(_zone_name: String) -> void:
	if game_state != GameState.PLAYING:
		return
	deliveries += 1
	message_label.modulate.a = 1.0
	message_label.text = "ПИСЬМО ДОСТАВЛЕНО"
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(message_label, "modulate:a", 0.0, 1.7)

func _on_zone_changed(zone_name: String) -> void:
	zone_label.text = zone_name
	if game_state != GameState.PLAYING:
		active_zone_name = zone_name
		return
	if active_zone_name.is_empty():
		active_zone_name = zone_name
		return
	if zone_name == active_zone_name:
		return
	active_zone_name = zone_name
	_register_zone_delivery(zone_name)

func _on_coin_count_changed(total: int) -> void:
	coin_label.text = "МОНЕТЫ  %d" % total
	_stop_coin_feedback()
	coin_label.pivot_offset = coin_label.size * 0.5
	coin_label.scale = Vector2.ONE
	if total <= 0:
		coin_label.modulate.a = 0.0
		return
	coin_label.modulate.a = 1.0
	coin_label.scale = Vector2.ONE * 0.78
	coin_pop_tween = create_tween()
	coin_pop_tween.tween_property(coin_label, "scale", Vector2.ONE * 1.2, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coin_pop_tween.tween_property(coin_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	coin_fade_tween = create_tween()
	coin_fade_tween.tween_interval(2.0)
	coin_fade_tween.tween_property(coin_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _stop_coin_feedback() -> void:
	if coin_pop_tween and coin_pop_tween.is_valid():
		coin_pop_tween.kill()
	if coin_fade_tween and coin_fade_tween.is_valid():
		coin_fade_tween.kill()

func _start_run() -> void:
	get_tree().paused = false
	game_state = GameState.PLAYING
	menu_stage.hide()
	streamer.show()
	deliveries = 0
	elapsed = 0.0
	active_zone_name = ""
	message_label.text = ""
	message_label.modulate.a = 1.0
	owl.reset_flight(Vector3(0, 7, 72))
	streamer.reset_world_if_needed()
	if active_zone_name.is_empty() and streamer.current_zone >= 0:
		active_zone_name = WorldStreamer.ZONE_NAMES[streamer.current_zone]
		zone_label.text = active_zone_name
	streamer.set_streaming_enabled(true)
	flight_camera.set_flight_view()
	flight_camera.snap_to_target()
	world_environment.environment.fog_density = 0.0105
	world_environment.environment.fog_light_color = Color("b27882")
	world_environment.environment.fog_light_energy = 0.52
	world_environment.environment.ambient_light_energy = 0.58
	world_environment.environment.tonemap_exposure = 1.0
	world_environment.environment.glow_intensity = 1.0
	world_environment.environment.glow_bloom = 0.1
	world_environment.environment.volumetric_fog_enabled = false
	sunset_light.light_energy = 1.75
	moon_light.light_energy = 0.04
	sky_material.sky_top_color = Color("9f4f78")
	sky_material.sky_horizon_color = Color("f29a68")
	sky_material.ground_horizon_color = Color("8c5261")
	hud.show()
	game_flow.hide_all()
	music_controller.play_game_music()
	owl.set_flight_enabled(true)

func _show_main_menu() -> void:
	get_tree().paused = false
	game_state = GameState.MENU
	menu_stage.show()
	owl.reset_flight(Vector3(10.3, 9.1, 49.0))
	owl.rotation.y = PI
	owl.set_flight_enabled(false)
	owl.set_menu_hero_pose()
	streamer.reset_world_if_needed()
	streamer.set_streaming_enabled(false)
	streamer.hide()
	flight_camera.set_menu_view()
	flight_camera.snap_to_target()
	world_environment.environment.fog_density = 0.002
	world_environment.environment.fog_light_color = Color("756478")
	world_environment.environment.fog_light_energy = 0.32
	world_environment.environment.ambient_light_energy = 0.58
	world_environment.environment.tonemap_exposure = 1.02
	world_environment.environment.glow_intensity = 1.15
	world_environment.environment.glow_bloom = 0.08
	world_environment.environment.volumetric_fog_enabled = true
	world_environment.environment.volumetric_fog_density = 0.0055
	world_environment.environment.volumetric_fog_albedo = Color("766879")
	world_environment.environment.volumetric_fog_emission = Color("241b2b")
	world_environment.environment.volumetric_fog_emission_energy = 0.03
	world_environment.environment.volumetric_fog_length = 120.0
	world_environment.environment.volumetric_fog_detail_spread = 1.8
	world_environment.environment.volumetric_fog_ambient_inject = 0.45
	sunset_light.light_energy = 1.8
	moon_light.light_energy = 0.55
	sky_material.sky_top_color = Color("56485f")
	sky_material.sky_horizon_color = Color("d58d79")
	sky_material.ground_horizon_color = Color("d58d79")
	hud.hide()
	game_flow.show_main_menu()
	music_controller.play_menu_music()

func _toggle_pause() -> void:
	if game_state == GameState.PLAYING:
		_pause_run()
	elif game_state == GameState.PAUSED:
		_resume_run()

func _pause_run() -> void:
	if game_state != GameState.PLAYING:
		return
	game_state = GameState.PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_flow.show_pause_menu()
	get_tree().paused = true

func _resume_run() -> void:
	if game_state != GameState.PAUSED:
		return
	get_tree().paused = false
	game_state = GameState.PLAYING
	game_flow.hide_pause_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_owl_died(reason: String) -> void:
	if game_state != GameState.PLAYING:
		return
	game_state = GameState.DEAD
	streamer.set_streaming_enabled(false)
	hud.hide()
	await get_tree().create_timer(1.15).timeout
	game_flow.show_game_over(reason, owl.total_distance, deliveries)

func _quit_game() -> void:
	get_tree().quit()

func _make_material(color: Color, roughness: float, metallic := 0.0, emission := Color.BLACK, emission_energy := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material
