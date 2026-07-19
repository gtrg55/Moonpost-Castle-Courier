class_name WorldStreamer
extends Node3D

signal castle_reached(chapter: int)
signal chunk_count_changed(active_count: int)

const CHUNK_LENGTH := 40.0
const ROAD_TILE_LENGTH := 4.0
const START_Z := 80.0
const REBASE_THRESHOLD := -1200.0
const REBASE_AMOUNT := 800.0

const ASSETS := {
	"road_tile": "res://assets/blockbench/environment/roads/road_tile.glb",
	"road_edge": "res://assets/blockbench/environment/roads/road_edge.glb",
	"rock_cluster": "res://assets/blockbench/environment/nature/rock_cluster.glb",
	"torch": "res://assets/blockbench/items/level/torch.glb",
	"tree": "res://assets/blockbench/environment/nature/twilight_tree.glb",
	"castle_gate": "res://assets/blockbench/environment/architecture/castle/castle_gate.glb",
	"gothic_pillar": "res://assets/blockbench/environment/architecture/castle/gothic_pillar.glb",
	"gothic_throne": "res://assets/blockbench/environment/architecture/castle/gothic_throne.glb",
	"castle_lord": "res://assets/blockbench/characters/npc/castle_lord.glb",
	"ruined_pillar": "res://assets/blockbench/environment/architecture/castle/ruined_pillar.glb",
	"delivery_marker": "res://assets/blockbench/items/level/delivery_marker.glb",
}

@export var world_seed := 74421
@export var chunks_behind := 2
@export var base_chunks_ahead := 7

var player: OwlController
var materials: Dictionary
var active_chunks: Dictionary = {}
var origin_start_z := START_Z
var delivered_chapters: Dictionary = {}

func setup(target: OwlController, material_library: Dictionary) -> void:
	player = target
	materials = material_library
	_update_chunks(true)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	_update_chunks(false)
	if player.global_position.z < REBASE_THRESHOLD:
		_rebase_world()

func _update_chunks(force: bool) -> void:
	var player_chunk := maxi(0, floori(player.total_distance / CHUNK_LENGTH))
	var speed_extra := ceili(maxf(0.0, player.current_speed - 25.0) / 14.0)
	var chunks_ahead := base_chunks_ahead + speed_extra
	var minimum_index := maxi(0, player_chunk - chunks_behind)
	var maximum_index := player_chunk + chunks_ahead

	for index in range(minimum_index, maximum_index + 1):
		if not active_chunks.has(index):
			active_chunks[index] = _build_chunk(index)

	for index in active_chunks.keys():
		if index < minimum_index or index > maximum_index:
			active_chunks[index].queue_free()
			active_chunks.erase(index)

	if force or active_chunks.size() > 0:
		chunk_count_changed.emit(active_chunks.size())

func _build_chunk(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%05d" % index
	root.position.z = origin_start_z - index * CHUNK_LENGTH - CHUNK_LENGTH * 0.5
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + index * 7919
	var chapter := index / 12
	var is_castle := index >= 5 and (index - 5) % 12 == 0
	var biome := index % 4

	_build_road(root, rng, index)
	if is_castle:
		_build_castle_landmark(root, rng, chapter + 1, index)
	else:
		_build_landscape(root, rng, biome, chapter)
	return root

func _build_road(root: Node3D, rng: RandomNumberGenerator, index: int) -> void:
	for tile_index in range(10):
		var local_z := CHUNK_LENGTH * 0.5 - ROAD_TILE_LENGTH * 0.5 - tile_index * ROAD_TILE_LENGTH
		var lateral := sin((index * 10 + tile_index) * 0.63) * 0.16
		var yaw := sin((index * 10 + tile_index) * 0.37) * 0.014
		if not _spawn_asset(root, "road_tile", Vector3(lateral, -0.2, local_z), Vector3(0, yaw, 0), Vector3.ONE):
			var tile := _add_box(root, "RoadTile", Vector3(lateral, -0.2, local_z), Vector3(8.8, 0.34, 3.72), materials.road if tile_index % 3 else materials.road_dark)
			tile.rotation.y = yaw
		for side in [-1.0, 1.0]:
			if not _spawn_asset(root, "road_edge", Vector3(side * 5.0, -0.05, local_z), Vector3(0, yaw, 0), Vector3.ONE):
				_add_box(root, "RoadEdge", Vector3(side * 5.0, -0.05, local_z), Vector3(1.0, 0.55, 3.85), materials.stone)
			if tile_index % 2 == 0 and rng.randf() > 0.32:
				var rock_position := Vector3(side * rng.randf_range(6.3, 9.2), rng.randf_range(0.1, 0.35), local_z + rng.randf_range(-1.4, 1.4))
				if not _spawn_asset(root, "rock_cluster", rock_position, Vector3(0, rng.randf_range(0, TAU), 0), Vector3.ONE * rng.randf_range(0.7, 1.35)):
					_add_rock(root, rock_position, rng.randf_range(0.65, 1.2))

func _build_landscape(root: Node3D, rng: RandomNumberGenerator, biome: int, chapter: int) -> void:
	var tree_count := 5 + biome + mini(chapter, 4)
	for tree_index in range(tree_count):
		var side := -1.0 if tree_index % 2 == 0 else 1.0
		var position := Vector3(side * rng.randf_range(11.0, 24.0), 0, rng.randf_range(-18.0, 18.0))
		var scale_value := rng.randf_range(0.8, 1.45)
		if not _spawn_asset(root, "tree", position, Vector3(0, rng.randf_range(0, TAU), 0), Vector3.ONE * scale_value):
			_add_tree(root, position, scale_value, biome == 2)

	if biome == 1 or biome == 3:
		for ruin_index in range(2 + chapter % 3):
			var side := -1.0 if ruin_index % 2 == 0 else 1.0
			var position := Vector3(side * rng.randf_range(10.0, 17.0), 0, rng.randf_range(-17.0, 17.0))
			var ruin_scale := rng.randf_range(0.72, 1.18)
			if not _spawn_asset(root, "ruined_pillar", position, Vector3(0, rng.randf_range(0, TAU), 0), Vector3.ONE * ruin_scale):
				var fallback_height := rng.randf_range(3.0, 8.0)
				_add_box(root, "RuinedPillar", position + Vector3(0, fallback_height * 0.5, 0), Vector3(rng.randf_range(1.8, 3.2), fallback_height, rng.randf_range(1.8, 3.2)), materials.stone)

	if biome >= 2:
		for local_z in [-12.0, 10.0]:
			for side in [-1.0, 1.0]:
				_add_torch(root, Vector3(side * 5.8, 1.5, local_z))

func _build_castle_landmark(root: Node3D, _rng: RandomNumberGenerator, chapter: int, chunk_index: int) -> void:
	if not _spawn_asset(root, "castle_gate", Vector3(0, 0, -2), Vector3.ZERO, Vector3.ONE):
		_add_box(root, "CastleLeftWall", Vector3(-14.5, 9, -2), Vector3(21, 18, 7), materials.stone)
		_add_box(root, "CastleRightWall", Vector3(14.5, 9, -2), Vector3(21, 18, 7), materials.stone)
		_add_box(root, "GateLintel", Vector3(0, 15.5, -2), Vector3(8.2, 5, 7), materials.stone_light)
		_add_tower(root, Vector3(-22, 0, -2), 6.7, 27)
		_add_tower(root, Vector3(22, 0, -2), 6.7, 27)

	for side in [-1.0, 1.0]:
		_add_torch(root, Vector3(side * 5.5, 5.2, 0.5))
		for local_z in [-8.5, -16.0]:
			_spawn_asset(root, "gothic_pillar", Vector3(side * 7.2, 0, local_z), Vector3.ZERO, Vector3.ONE)

	# The delivery destination is a compact open throne hall behind the gate.
	_spawn_asset(root, "gothic_throne", Vector3(0, 0, -18.0), Vector3(0, PI, 0), Vector3(0.82, 0.82, 0.82))
	_spawn_asset(root, "castle_lord", Vector3(0, 0.75, -14.5), Vector3(0, PI, 0), Vector3.ONE)
	for side in [-1.0, 1.0]:
		_add_torch(root, Vector3(side * 4.2, 3.4, -13.0))

	if not _spawn_asset(root, "delivery_marker", Vector3(0, 5.1, -11.0), Vector3(0, PI, 0), Vector3.ONE * 0.82):
		var seal := MeshInstance3D.new()
		seal.name = "ChapterSeal"
		var seal_mesh := SphereMesh.new()
		seal_mesh.radius = 0.9
		seal_mesh.height = 1.8
		seal_mesh.radial_segments = 12
		seal.mesh = seal_mesh
		seal.position = Vector3(0, 6.2, -11.0)
		seal.material_override = materials.gold
		root.add_child(seal)

	var area := Area3D.new()
	area.name = "DeliveryZone_Chapter_%d" % chapter
	area.position = Vector3(0, 5.5, -11.0)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 5.0
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_castle_area_entered.bind(chapter, chunk_index))
	root.add_child(area)

func _on_castle_area_entered(body: Node3D, chapter: int, chunk_index: int) -> void:
	if body != player or delivered_chapters.has(chunk_index):
		return
	delivered_chapters[chunk_index] = true
	castle_reached.emit(chapter)

func _rebase_world() -> void:
	player.global_position.z += REBASE_AMOUNT
	origin_start_z += REBASE_AMOUNT
	for chunk in active_chunks.values():
		chunk.position.z += REBASE_AMOUNT

func _spawn_asset(parent: Node3D, asset_id: String, position: Vector3, rotation: Vector3, scale_value: Vector3) -> bool:
	var path: String = ASSETS[asset_id]
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if not packed:
		return false
	var instance := packed.instantiate() as Node3D
	instance.name = asset_id.to_pascal_case()
	instance.position = position
	instance.rotation = rotation
	instance.scale = scale_value
	parent.add_child(instance)
	var visibility_end := _asset_visibility_end(asset_id)
	for geometry in instance.find_children("*", "GeometryInstance3D", true, false):
		(geometry as GeometryInstance3D).visibility_range_end = visibility_end
	return true

func _asset_visibility_end(asset_id: String) -> float:
	match asset_id:
		"rock_cluster":
			return 150.0
		"torch":
			return 180.0
		"road_tile", "road_edge", "tree", "ruined_pillar", "gothic_pillar":
			return 240.0
		_:
			return 480.0

func _add_tower(parent: Node3D, position: Vector3, radius: float, height: float) -> void:
	var tower := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.86
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	tower.mesh = mesh
	tower.position = position + Vector3(0, height * 0.5, 0)
	tower.material_override = materials.stone
	parent.add_child(tower)
	_add_box(parent, "TowerRoof", position + Vector3(0, height + 1.2, 0), Vector3(radius * 1.75, 2.4, radius * 1.75), materials.roof)

func _add_tree(parent: Node3D, position: Vector3, scale_value: float, warm: bool) -> void:
	var root := Node3D.new()
	root.name = "TwilightTree"
	root.position = position
	root.scale = Vector3.ONE * scale_value
	parent.add_child(root)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.45
	trunk_mesh.bottom_radius = 0.72
	trunk_mesh.height = 6.5
	trunk_mesh.radial_segments = 7
	trunk.mesh = trunk_mesh
	trunk.position.y = 3.25
	trunk.material_override = materials.trunk
	root.add_child(trunk)
	_add_sphere(root, Vector3(0, 7.0, 0), Vector3(3.1, 3.6, 3.1), materials.leaves_warm if warm else materials.leaves)
	_add_sphere(root, Vector3(-1.8, 6.0, 0.5), Vector3(2.2, 2.6, 2.2), materials.leaves)
	_add_sphere(root, Vector3(1.7, 6.4, -0.6), Vector3(2.0, 2.7, 2.0), materials.leaves)

func _add_rock(parent: Node3D, position: Vector3, scale_value: float) -> void:
	var rock := _add_box(parent, "RoadsideRock", position, Vector3(1.5, 1.05, 1.25) * scale_value, materials.stone_light)
	rock.rotation_degrees = Vector3(8, fmod(position.z * 17.0, 45.0), 11)

func _add_torch(parent: Node3D, position: Vector3) -> void:
	if _spawn_asset(parent, "torch", position, Vector3.ZERO, Vector3.ONE):
		return
	_add_box(parent, "TorchPost", position, Vector3(0.25, 3.0, 0.25), materials.trunk)
	var flame := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.7
	mesh.radial_segments = 8
	mesh.rings = 4
	flame.mesh = mesh
	flame.position = position + Vector3(0, 1.85, 0)
	flame.material_override = materials.fire
	parent.add_child(flame)
	var light := OmniLight3D.new()
	light.position = position + Vector3(0, 1.8, 0)
	light.light_color = Color("ff8b52")
	light.light_energy = 3.4
	light.omni_range = 10.0
	light.shadow_enabled = false
	parent.add_child(light)

func _add_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node3D, position: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale_value
	instance.material_override = material
	parent.add_child(instance)
	return instance
