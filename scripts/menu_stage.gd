extends Node3D

const ROAD_TILE := preload("res://assets/blockbench/environment/menu/menu_road_tile.glb")
const ROAD_EDGE := preload("res://assets/blockbench/environment/menu/menu_road_edge.glb")
const TWILIGHT_TREE := preload("res://assets/blockbench/environment/menu/menu_twilight_tree_v2.glb")
const BRAZIER := preload("res://assets/blockbench/environment/menu/menu_brazier.glb")
const MIST_WATCHTOWER := preload("res://assets/blockbench/environment/menu/menu_mist_watchtower.glb")
const MIST_RUIN_TOWER := preload("res://assets/blockbench/environment/menu/menu_mist_ruin_tower.glb")
const WEEPING_TREE := preload("res://assets/blockbench/environment/nature/gothic_weeping_tree.glb")
const BLOSSOM_TREE := preload("res://assets/blockbench/environment/nature/gothic_blossom_tree.glb")
const CRYSTAL_TREE := preload("res://assets/blockbench/environment/nature/gothic_crystal_tree.glb")
const RUINED_PILLAR := preload("res://assets/blockbench/environment/architecture/castle/ruined_pillar.glb")

@onready var road_backdrop: Node3D = $RoadBackdrop

var clock := 0.0
var flying_letters: Array[Node3D] = []
var brazier_lights: Array[OmniLight3D] = []

func _ready() -> void:
	_build_floating_island()
	for tile_index in range(21):
		var local_z := 62.0 - tile_index * 4.0
		var tile := ROAD_TILE.instantiate() as Node3D
		tile.position = Vector3(sin(tile_index * 0.63) * 0.12, -0.2, local_z)
		road_backdrop.add_child(tile)
		for side in [-1.0, 1.0]:
			var edge := ROAD_EDGE.instantiate() as Node3D
			edge.position = Vector3(side * 5.0, -0.05, local_z)
			road_backdrop.add_child(edge)
	_build_menu_forest()
	_build_distant_ruins()
	_build_braziers()
	_build_road_gate_towers()
	_build_mist_skyline()
	_build_abyss_fog()
	_build_cloud_layers()
	_build_flying_letters()
	_build_letter_sparkles()
	_build_hot_ash()

func _process(delta: float) -> void:
	if not visible:
		return
	clock += delta
	for index in range(brazier_lights.size()):
		brazier_lights[index].light_energy = 2.65 + sin(clock * (6.2 + index * 0.17) + index * 2.1) * 0.24
	for index in range(flying_letters.size()):
		var letter := flying_letters[index]
		letter.position.y = letter.get_meta("base_y") + sin(clock * (0.45 + index * 0.035) + index * 1.7) * (0.22 + index % 3 * 0.05)
		letter.rotation.z = letter.get_meta("base_roll") + sin(clock * 0.38 + index) * 0.12
		letter.rotation.y += delta * (0.08 if index % 2 == 0 else -0.06)

func _build_floating_island() -> void:
	var top_material := _surface_material(Color("625c4f"), 0.78)
	var moss_material := _surface_material(Color("4e5a42"), 0.9)
	var cliff_material := _surface_material(Color("39303a"), 0.94)
	var cliff_shadow := _surface_material(Color("211d28"), 1.0)
	_add_box("ЗамковаяПоляна", Vector3(0, -0.62, -2), Vector3(39, 1.0, 31), top_material)
	_add_box("ЗамковыйУтёс", Vector3(0, -2.8, -2), Vector3(36, 4.0, 28), cliff_material)
	_add_box("ТеньЗамковогоУтёса", Vector3(0, -6.0, -2), Vector3(30, 3.0, 23), cliff_shadow)
	_add_box("ЗемляПодДорогой", Vector3(0, -0.68, 30), Vector3(12.0, 0.9, 67), top_material)
	_add_box("СтенаДороги", Vector3(0, -3.1, 30), Vector3(11.1, 4.2, 66), cliff_material)
	_add_box("ТеньДороги", Vector3(0, -6.1, 30), Vector3(9.3, 2.2, 62), cliff_shadow)
	_add_box("ПолянаСовы", Vector3(8.5, -0.62, 66), Vector3(20.0, 1.0, 19.0), top_material)
	_add_box("УтёсСовы", Vector3(8.5, -3.1, 66), Vector3(18.0, 4.3, 17.0), cliff_material)
	_add_box("ТеньУтёсаСовы", Vector3(8.5, -6.25, 66), Vector3(14.5, 2.3, 13.5), cliff_shadow)
	for patch in [Vector4(-13, 0, -9, 5), Vector4(13, 0, 5, 4), Vector4(5.5, 0, 61, 3.2)]:
		_add_box("МшистыйКрай", Vector3(patch.x, -0.08, patch.z), Vector3(patch.w, 0.13, 2.2), moss_material)

func _build_menu_forest() -> void:
	var placements := [
		[BLOSSOM_TREE, Vector3(-15.8, 0, -8.0), 0.92, -0.2],
		[WEEPING_TREE, Vector3(15.6, 0, -7.0), 0.98, 0.35],
		[CRYSTAL_TREE, Vector3(-16.2, 0, 7.0), 0.88, 0.55],
		[BLOSSOM_TREE, Vector3(16.0, 0, 7.5), 0.86, -0.5],
		[WEEPING_TREE, Vector3(-19.5, -0.4, 21.0), 1.10, -0.35],
		[CRYSTAL_TREE, Vector3(20.5, -0.8, 23.0), 1.04, 0.24],
		[BLOSSOM_TREE, Vector3(-18.5, -0.6, 39.0), 0.96, 0.42],
		[WEEPING_TREE, Vector3(21.0, -1.0, 41.0), 1.02, -0.18],
		[CRYSTAL_TREE, Vector3(-26.0, -2.0, -18.0), 1.28, 0.12],
		[BLOSSOM_TREE, Vector3(27.0, -2.4, -22.0), 1.24, -0.4],
		[WEEPING_TREE, Vector3(-30.0, -3.0, 8.0), 1.18, 0.3],
		[CRYSTAL_TREE, Vector3(31.0, -3.2, 4.0), 1.16, -0.22],
	]
	for index in range(placements.size()):
		var packed: PackedScene = placements[index][0]
		var tree := packed.instantiate() as Node3D
		tree.name = "СумеречноеДерево_%02d" % index
		tree.position = placements[index][1]
		tree.scale = Vector3.ONE * placements[index][2]
		tree.rotation.y = placements[index][3]
		add_child(tree)
	var perch_material := _surface_material(Color("8b5a3e"), 0.88)
	var perch := _add_box("ВеткаПодСовой", Vector3(10.85, 6.72, 49.62), Vector3(6.2, 0.7, 1.0), perch_material)
	perch.rotation.z = 0.045
	_add_box("МохНаВетке", Vector3(10.6, 7.1, 49.6), Vector3(3.8, 0.13, 1.04), _surface_material(Color("59634b"), 0.96))

func _build_distant_ruins() -> void:
	var placements := [
		[Vector3(-22.0, -1.0, 31.0), 1.85, -0.16],
		[Vector3(23.5, -1.6, 29.0), 2.05, 0.22],
		[Vector3(-24.5, -2.4, 5.0), 2.35, 0.12],
		[Vector3(25.5, -2.8, 2.0), 2.55, -0.2],
		[Vector3(-34.0, -5.0, -28.0), 2.8, 0.08],
		[Vector3(35.0, -5.5, -34.0), 3.0, -0.1],
	]
	for index in range(placements.size()):
		var pillar := RUINED_PILLAR.instantiate() as Node3D
		pillar.name = "ДальняяКолонна_%02d" % index
		pillar.position = placements[index][0]
		pillar.scale = Vector3.ONE * placements[index][1]
		pillar.rotation.y = placements[index][2]
		add_child(pillar)

func _build_road_gate_towers() -> void:
	var placements := [
		[MIST_WATCHTOWER, Vector3(-11.5, -3.2, 57), 0.78, PI],
		[MIST_RUIN_TOWER, Vector3(13.0, -3.7, 53), 0.72, PI],
	]
	for index in range(placements.size()):
		var packed: PackedScene = placements[index][0]
		var tower := packed.instantiate() as Node3D
		tower.name = "БлижняяБашня_%02d" % index
		tower.position = placements[index][1]
		tower.scale = Vector3.ONE * placements[index][2]
		tower.rotation.y = placements[index][3]
		add_child(tower)
		_add_box("ОстровокБлижнейБашни_%02d" % index, tower.position + Vector3(0, 1.5, 0), Vector3(8.2, 2.0, 8.2), _surface_material(Color("40343d"), 0.92))

func _build_braziers() -> void:
	var positions := [
		Vector3(-5.35, 0, 53), Vector3(5.35, 0, 53),
		Vector3(-5.35, 0, 33), Vector3(5.35, 0, 33),
		Vector3(-5.35, 0, 13), Vector3(5.35, 0, 13),
		Vector3(-5.4, 0, -1.5), Vector3(5.4, 0, -1.5),
	]
	for index in range(positions.size()):
		var brazier := BRAZIER.instantiate() as Node3D
		brazier.name = "ДорожнаяЖаровня_%02d" % index
		brazier.position = positions[index]
		brazier.scale = Vector3.ONE * (0.86 if index < 6 else 1.05)
		add_child(brazier)
		var light := OmniLight3D.new()
		light.name = "СветЖаровни_%02d" % index
		light.position = positions[index] + Vector3(0, 3.45, 0)
		light.light_color = Color("ff9a52")
		light.light_energy = 2.65
		light.omni_range = 11.0
		light.shadow_enabled = index >= 6
		add_child(light)
		brazier_lights.append(light)
		_add_flame_particles(positions[index] + Vector3(0, 3.45, 0), index)
		var reflection := _add_box("ОтблескЖаровни_%02d" % index, positions[index] + Vector3(-positions[index].x * 0.32, 0.34, 0), Vector3(3.3, 0.025, 2.4), _glow_material(Color(1.0, 0.38, 0.12, 0.12), Color("ff6b32"), 0.65))
		reflection.rotation.y = positions[index].z * 0.017

func _add_flame_particles(spawn_position: Vector3, index: int) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "ПламяЖаровни_%02d" % index
	particles.position = spawn_position
	particles.amount = 12
	particles.lifetime = 0.72
	particles.preprocess = 0.72
	particles.randomness = 0.52
	particles.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 4, 2))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = Vector3.UP
	process.spread = 18.0
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0, 0.6, 0)
	process.scale_min = 0.45
	process.scale_max = 1.05
	process.color = Color("ff9845")
	particles.process_material = process
	var flame := SphereMesh.new()
	flame.radius = 0.12
	flame.height = 0.38
	flame.radial_segments = 6
	flame.rings = 3
	flame.material = _glow_material(Color("ffb052"), Color("ff5b24"), 2.4)
	particles.draw_pass_1 = flame
	add_child(particles)

func _build_abyss_fog() -> void:
	var volume := FogVolume.new()
	volume.name = "ТуманНадПропастью"
	volume.position = Vector3(0, -6.5, 8)
	volume.size = Vector3(150, 14, 185)
	var fog_material := FogMaterial.new()
	fog_material.density = 0.135
	fog_material.albedo = Color("a58a9c")
	fog_material.emission = Color("302337")
	fog_material.edge_fade = 0.72
	volume.material = fog_material
	add_child(volume)
	var haze := FogVolume.new()
	haze.name = "ВерхняяДымкаПропасти"
	haze.position = Vector3(0, -0.9, -18)
	haze.size = Vector3(132, 3.0, 125)
	var haze_material := FogMaterial.new()
	haze_material.density = 0.032
	haze_material.albedo = Color("bd9fa8")
	haze_material.emission = Color("3d2a39")
	haze_material.edge_fade = 0.88
	haze.material = haze_material
	add_child(haze)

func _build_mist_skyline() -> void:
	var placements := [
		[MIST_WATCHTOWER, Vector3(-27, -7.4, -24), 1.28, -0.12],
		[MIST_RUIN_TOWER, Vector3(-40, -9.0, -48), 1.16, 0.18],
		[MIST_WATCHTOWER, Vector3(27, -8.2, -36), 1.18, 0.14],
		[MIST_RUIN_TOWER, Vector3(43, -10.5, -63), 1.02, -0.2],
		[MIST_WATCHTOWER, Vector3(-55, -11.5, -76), 0.94, 0.08],
		[MIST_RUIN_TOWER, Vector3(55, -11.0, -72), 0.98, -0.12],
	]
	for index in range(placements.size()):
		var packed: PackedScene = placements[index][0]
		var tower := packed.instantiate() as Node3D
		tower.name = "БашняВТумане_%02d" % index
		tower.position = placements[index][1]
		tower.scale = Vector3.ONE * placements[index][2]
		tower.rotation.y = placements[index][3]
		add_child(tower)
		if index == 0 or index == 2:
			var window_light := OmniLight3D.new()
			window_light.name = "ОгонёкДальнейБашни_%02d" % index
			window_light.position = tower.position + Vector3(0, 8.7 * placements[index][2], -2.8 * placements[index][2])
			window_light.light_color = Color("eaa06b")
			window_light.light_energy = 0.75 if index == 0 else 0.42
			window_light.omni_range = 7.0
			add_child(window_light)

func _build_cloud_layers() -> void:
	var cloud_shader := Shader.new()
	cloud_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 cloud_color : source_color = vec4(0.92, 0.72, 0.72, 0.28);
uniform float layer_offset = 0.0;
uniform float drift_speed = 0.012;
uniform float cloud_scale = 3.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(4.7, 2.3);
		amplitude *= 0.48;
	}
	return value;
}

void fragment() {
	vec2 p = UV * vec2(cloud_scale, cloud_scale * 0.48);
	p += vec2(TIME * drift_speed + layer_offset, layer_offset * 0.37);
	float shape = smoothstep(0.40, 0.71, fbm(p));
	float vertical_fade = smoothstep(0.02, 0.25, UV.y) * smoothstep(0.98, 0.58, UV.y);
	float horizontal_fade = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	ALBEDO = cloud_color.rgb;
	EMISSION = cloud_color.rgb * 0.08;
	ALPHA = shape * vertical_fade * horizontal_fade * cloud_color.a;
}
"""
	var layers := [
		["ДальниеОблака", Vector3(1, 29, -58), Vector2(132, 34), Color(0.98, 0.77, 0.73, 0.34), 0.0, 0.010, 4.0],
		["ВысокиеОблака", Vector3(-8, 35, -82), Vector2(158, 30), Color(0.77, 0.63, 0.73, 0.22), 3.7, -0.006, 5.2],
	]
	for data in layers:
		var clouds := MeshInstance3D.new()
		clouds.name = data[0]
		clouds.position = data[1]
		var quad := QuadMesh.new()
		quad.size = data[2]
		var material := ShaderMaterial.new()
		material.shader = cloud_shader
		material.set_shader_parameter("cloud_color", data[3])
		material.set_shader_parameter("layer_offset", data[4])
		material.set_shader_parameter("drift_speed", data[5])
		material.set_shader_parameter("cloud_scale", data[6])
		material.render_priority = -10
		quad.material = material
		clouds.mesh = quad
		add_child(clouds)

func _add_box(node_name: String, spawn_position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = spawn_position
	instance.material_override = material
	add_child(instance)
	return instance

func _surface_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _build_flying_letters() -> void:
	var placements := [
		Vector4(9.7, 8.1, 51.15, 0.78),
		Vector4(-3.8, 11.8, 45.0, 1.02), Vector4(3.1, 14.0, 34.0, 0.94),
		Vector4(9.2, 11.2, 28.0, 1.08), Vector4(11.5, 5.0, 43.0, 0.92),
		Vector4(-8.5, 5.2, 29.0, 0.9), Vector4(7.6, 3.4, 18.0, 0.82),
		Vector4(-1.0, 8.8, 16.0, 0.72),
	]
	for index in range(placements.size()):
		var data: Vector4 = placements[index]
		var letter := _create_letter(data.w, index == 0)
		letter.name = "ЛетающееПисьмо_%02d" % index
		letter.position = Vector3(data.x, data.y, data.z)
		letter.rotation = Vector3(-0.08 + index * 0.025, -0.18 + index * 0.055, -0.18 + index * 0.13)
		letter.set_meta("base_y", data.y)
		letter.set_meta("base_roll", letter.rotation.z)
		add_child(letter)
		flying_letters.append(letter)

func _create_letter(scale_value: float, hero: bool) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * scale_value
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("ffe7ae") if hero else Color("d8c9bc")
	paper.roughness = 0.72
	if hero:
		paper.emission_enabled = true
		paper.emission = Color("ffb84f")
		paper.emission_energy_multiplier = 1.15
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.55, 0.94, 0.09)
	body.mesh = body_mesh
	body.material_override = paper
	root.add_child(body)
	var seam_material := StandardMaterial3D.new()
	seam_material.albedo_color = Color("aa7957")
	seam_material.roughness = 0.85
	for side in [-1.0, 1.0]:
		var seam := MeshInstance3D.new()
		var seam_mesh := BoxMesh.new()
		seam_mesh.size = Vector3(0.055, 0.82, 0.035)
		seam.mesh = seam_mesh
		seam.position = Vector3(side * 0.35, -0.02, 0.065)
		seam.rotation.z = side * 0.9
		seam.material_override = seam_material
		root.add_child(seam)
	var seal := MeshInstance3D.new()
	var seal_mesh := SphereMesh.new()
	seal_mesh.radius = 0.11
	seal_mesh.height = 0.13
	seal_mesh.radial_segments = 8
	seal_mesh.rings = 4
	seal.mesh = seal_mesh
	seal.position = Vector3(0, -0.12, 0.13)
	seal.material_override = _emissive_material(Color("b94236"), Color("ff6b3d"), 2.0)
	root.add_child(seal)
	if hero:
		var light := OmniLight3D.new()
		light.light_color = Color("ffc56b")
		light.light_energy = 2.2
		light.omni_range = 8.0
		root.add_child(light)
	return root

func _build_letter_sparkles() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "ИскрыЛуннойПочты"
	particles.position = Vector3(4.5, 8.0, 48.0)
	particles.amount = 110
	particles.lifetime = 5.5
	particles.preprocess = 5.5
	particles.randomness = 0.86
	particles.visibility_aabb = AABB(Vector3(-18, -10, -28), Vector3(36, 22, 56))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(11.0, 7.0, 20.0)
	process.direction = Vector3(0.05, 1.0, 0.1)
	process.spread = 35.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.42
	process.gravity = Vector3(0, 0.05, 0)
	process.scale_min = 0.3
	process.scale_max = 1.1
	process.color = Color("ffd27c")
	particles.process_material = process
	var sparkle_mesh := SphereMesh.new()
	sparkle_mesh.radius = 0.035
	sparkle_mesh.height = 0.07
	sparkle_mesh.radial_segments = 5
	sparkle_mesh.rings = 3
	sparkle_mesh.material = _emissive_material(Color("ffe8ae"), Color("ffbe54"), 4.0)
	particles.draw_pass_1 = sparkle_mesh
	add_child(particles)

func _build_hot_ash() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "ГорячийПепел"
	particles.position = Vector3(0, 8.0, 24.0)
	particles.amount = 480
	particles.lifetime = 8.0
	particles.preprocess = 8.0
	particles.randomness = 0.92
	particles.visibility_aabb = AABB(Vector3(-46, -14, -62), Vector3(92, 34, 124))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(32.0, 11.0, 42.0)
	process.direction = Vector3(0.16, 1.0, -0.08)
	process.spread = 68.0
	process.initial_velocity_min = 0.12
	process.initial_velocity_max = 0.82
	process.gravity = Vector3(0.0, 0.10, 0.0)
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	process.scale_min = 0.22
	process.scale_max = 1.0
	process.color = Color("ff8a42")
	particles.process_material = process
	var ash_mesh := BoxMesh.new()
	ash_mesh.size = Vector3(0.055, 0.13, 0.035)
	ash_mesh.material = _glow_material(Color("ff7b35"), Color("ff401f"), 3.4)
	particles.draw_pass_1 = ash_mesh
	add_child(particles)

func _emissive_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.45
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material

func _glow_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := _emissive_material(albedo, emission, energy)
	if albedo.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
