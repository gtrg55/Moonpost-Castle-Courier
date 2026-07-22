class_name WorldStreamer
extends Node3D

signal castle_reached(chapter: int)
signal chunk_count_changed(active_count: int)
signal zone_changed(zone_name: String)

const CHUNK_LENGTH := 40.0
const ROAD_TILE_LENGTH := 4.0
const START_Z := 80.0
const REBASE_AMOUNT := 8192.0
const ZONE_LENGTH_CHUNKS := 8
const ZONE_NAMES := [
	"СУМЕРЕЧНОЕ ПРЕДМЕСТЬЕ",
	"ЗАМКОВЫЕ ЗАЛЫ",
	"КЛАДБИЩЕНСКИЙ ДВОР",
]
const LANE_X := [-3.5, 0.0, 3.5]
const LANE_Y := [4.6, 7.5, 10.4]
const COIN_SCENE := preload("res://scenes/items/coin_collectible.tscn")

const ASSETS := {
	"road_tile": "res://assets/blockbench/environment/roads/road_tile.glb",
	"road_edge": "res://assets/blockbench/environment/roads/road_edge.glb",
	"rock_cluster": "res://assets/blockbench/environment/nature/rock_cluster.glb",
	"torch": "res://assets/blockbench/items/level/torch.glb",
	"tree": "res://assets/blockbench/environment/nature/twilight_tree.glb",
	"gothic_weeping_tree": "res://assets/blockbench/environment/nature/gothic_weeping_tree.glb",
	"gothic_blossom_tree": "res://assets/blockbench/environment/nature/gothic_blossom_tree.glb",
	"gothic_crystal_tree": "res://assets/blockbench/environment/nature/gothic_crystal_tree.glb",
	"mist_watchtower": "res://assets/blockbench/environment/menu/menu_mist_watchtower.glb",
	"mist_ruin_tower": "res://assets/blockbench/environment/menu/menu_mist_ruin_tower.glb",
	"castle_gate": "res://assets/blockbench/environment/architecture/castle/castle_gate.glb",
	"gothic_pillar": "res://assets/blockbench/environment/architecture/castle/gothic_pillar.glb",
	"gothic_throne": "res://assets/blockbench/environment/architecture/castle/gothic_throne.glb",
	"castle_lord": "res://assets/blockbench/characters/npc/castle_lord.glb",
	"ruined_pillar": "res://assets/blockbench/environment/architecture/castle/ruined_pillar.glb",
	"delivery_marker": "res://assets/blockbench/items/level/delivery_marker.glb",
	"crooked_house": "res://assets/blockbench/environment/architecture/town/crooked_house.glb",
	"ruined_house_tall": "res://assets/blockbench/environment/architecture/town/ruined_house_tall.glb",
	"ruined_house_arch": "res://assets/blockbench/environment/architecture/town/ruined_house_arch.glb",
	"ruined_house_burned": "res://assets/blockbench/environment/architecture/town/ruined_house_burned.glb",
	"graveyard_crypt": "res://assets/blockbench/environment/architecture/cemetery/graveyard_crypt.glb",
	"gothic_gravestone": "res://assets/blockbench/environment/architecture/cemetery/gothic_gravestone.glb",
	"candle_chandelier": "res://assets/blockbench/items/obstacles/candle_chandelier.glb",
	"ground_gear": "res://assets/blockbench/items/obstacles/ground_gear.glb",
	"street_lantern": "res://assets/blockbench/items/obstacles/street_lantern.glb",
	"carved_pumpkin": "res://assets/blockbench/items/obstacles/carved_pumpkin.glb",
	"grave_hand": "res://assets/blockbench/items/obstacles/grave_hand.glb",
	"dead_branch": "res://assets/blockbench/items/obstacles/dead_branch.glb",
	"vampire_bat": "res://assets/blockbench/characters/enemies/vampire_bat.glb",
	"raven_crow": "res://assets/blockbench/characters/enemies/raven_crow.glb",
}

@export var world_seed := 74421
@export var chunks_behind := 1
@export var base_chunks_ahead := 5

var player: OwlController
var materials: Dictionary
var active_chunks: Dictionary = {}
var pending_chunk_jobs: Array[Dictionary] = []
var origin_start_z := START_Z
var delivered_chapters: Dictionary = {}
var current_zone := -1
var streaming_enabled := false
var world_dirty := false

func setup(target: OwlController, material_library: Dictionary) -> void:
	player = target
	materials = material_library
	if not player.forward_step.is_connected(_on_player_forward_step):
		player.forward_step.connect(_on_player_forward_step)
	_update_chunks(true)
	world_dirty = false

func set_streaming_enabled(value: bool) -> void:
	streaming_enabled = value

func reset_world() -> void:
	pending_chunk_jobs.clear()
	for chunk in active_chunks.values():
		chunk.queue_free()
	active_chunks.clear()
	position = Vector3.ZERO
	origin_start_z = START_Z
	delivered_chapters.clear()
	current_zone = -1
	reset_physics_interpolation()
	if is_instance_valid(player):
		_update_chunks(true)
	world_dirty = false

func reset_world_if_needed() -> void:
	if world_dirty or active_chunks.is_empty() or not position.is_zero_approx() or not pending_chunk_jobs.is_empty():
		reset_world()
		return
	delivered_chapters.clear()

func _on_player_forward_step(distance: float) -> void:
	if not streaming_enabled or not is_instance_valid(player):
		return
	if distance > 0.0:
		world_dirty = true
	position.z += distance
	_update_chunks(false)
	if position.z >= REBASE_AMOUNT:
		_rebase_world()

func _update_chunks(force: bool) -> void:
	var player_chunk := maxi(0, floori(player.total_distance / CHUNK_LENGTH))
	var speed_extra := ceili(maxf(0.0, player.current_speed - 25.0) / 20.0)
	var chunks_ahead := base_chunks_ahead + speed_extra
	var minimum_index := maxi(0, player_chunk - chunks_behind)
	var maximum_index := player_chunk + chunks_ahead
	var player_zone := floori(float(player_chunk) / float(ZONE_LENGTH_CHUNKS)) % ZONE_NAMES.size()
	if player_zone != current_zone:
		current_zone = player_zone
		zone_changed.emit(ZONE_NAMES[current_zone])

	for index in range(minimum_index, maximum_index + 1):
		if not active_chunks.has(index):
			if force:
				active_chunks[index] = _build_chunk(index)
			else:
				_queue_chunk_build(index)

	for index in active_chunks.keys():
		if index < minimum_index or index > maximum_index:
			_cancel_pending_chunk(index)
			active_chunks[index].queue_free()
			active_chunks.erase(index)

	if force or active_chunks.size() > 0:
		chunk_count_changed.emit(active_chunks.size())

func _process(_delta: float) -> void:
	if not streaming_enabled or pending_chunk_jobs.is_empty():
		return
	_build_next_chunk_phase()

func _queue_chunk_build(index: int) -> void:
	var root := Node3D.new()
	root.name = "Chunk_%05d" % index
	root.position.z = origin_start_z - index * CHUNK_LENGTH - CHUNK_LENGTH * 0.5
	add_child(root)
	active_chunks[index] = root

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + index * 7919
	pending_chunk_jobs.append({
		"index": index,
		"root": root,
		"rng": rng,
		"chapter": floori(float(index) / 12.0),
		"is_castle": index >= 5 and (index - 5) % 12 == 0,
		"zone_id": floori(float(index) / float(ZONE_LENGTH_CHUNKS)) % ZONE_NAMES.size(),
		"phase": 0,
	})

func _build_next_chunk_phase() -> void:
	var job := pending_chunk_jobs[0]
	var index: int = job.index
	var root := job.root as Node3D
	if not active_chunks.has(index) or not is_instance_valid(root):
		pending_chunk_jobs.pop_front()
		return

	var rng := job.rng as RandomNumberGenerator
	var zone_id: int = job.zone_id
	var chapter: int = job.chapter
	var is_castle: bool = job.is_castle
	var phase: int = job.phase
	match phase:
		0:
			_build_world_bed(root, rng, zone_id, is_castle)
		1, 2, 3, 4, 5:
			_build_road_tiles(root, rng, index, (phase - 1) * 2, 2)
		6:
			_build_roadside_towers(root, rng, zone_id, index, is_castle)
		7:
			if not is_castle:
				_build_zone_landscape(root, rng, zone_id, chapter, index)
		8:
			if is_castle:
				_build_castle_landmark(root, rng, chapter + 1, index)
			else:
				_build_zone_details(root, rng, zone_id, chapter, index)
		9:
			if not is_castle:
				_build_coin_trail(root, rng, index)
				if zone_id != 1:
					_build_outer_horizon(root, rng, zone_id, index)
				if index < 4:
					_build_opening_route(root, index)

	job.phase = phase + 1
	if job.phase >= 10:
		pending_chunk_jobs.pop_front()
	else:
		pending_chunk_jobs[0] = job

func _cancel_pending_chunk(index: int) -> void:
	for job_index in range(pending_chunk_jobs.size() - 1, -1, -1):
		if int(pending_chunk_jobs[job_index].index) == index:
			pending_chunk_jobs.remove_at(job_index)

func _build_chunk(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%05d" % index
	root.position.z = origin_start_z - index * CHUNK_LENGTH - CHUNK_LENGTH * 0.5
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + index * 7919
	var chapter := floori(float(index) / 12.0)
	var is_castle := index >= 5 and (index - 5) % 12 == 0
	var zone_id := floori(float(index) / float(ZONE_LENGTH_CHUNKS)) % ZONE_NAMES.size()

	_build_world_bed(root, rng, zone_id, is_castle)
	_build_road(root, rng, index)
	_build_roadside_towers(root, rng, zone_id, index, is_castle)
	if is_castle:
		_build_castle_landmark(root, rng, chapter + 1, index)
	else:
		_build_zone(root, rng, zone_id, chapter, index)
		_build_coin_trail(root, rng, index)
		if zone_id != 1:
			_build_outer_horizon(root, rng, zone_id, index)
		if index < 4:
			_build_opening_route(root, index)
	return root

func _build_coin_trail(root: Node3D, rng: RandomNumberGenerator, chunk_index: int) -> void:
	# A short trail every other chunk gives direction without turning the road into a coin carpet.
	if chunk_index == 0 or chunk_index % 2 != 0:
		return
	var pattern := floori(chunk_index / 2.0) % 3
	var start_lane := rng.randi_range(0, 2)
	var end_lane := start_lane
	if pattern == 2:
		end_lane = 2 if start_lane == 0 else 0 if start_lane == 2 else (0 if chunk_index % 4 == 0 else 2)
	for coin_index in range(5):
		var progress := coin_index / 4.0
		var x: float = LANE_X[start_lane]
		var y: float = LANE_Y[1] + 0.7
		if pattern == 1:
			y += sin(progress * PI) * 1.6
		elif pattern == 2:
			x = lerpf(LANE_X[start_lane], LANE_X[end_lane], progress)
		var coin := COIN_SCENE.instantiate() as Area3D
		coin.name = "Монетка_%02d" % coin_index
		coin.position = Vector3(x, y, 17.0 - coin_index * 4.0)
		coin.rotation.y = coin_index * 0.28
		root.add_child(coin)

func _build_world_bed(root: Node3D, rng: RandomNumberGenerator, zone_id: int, is_castle: bool) -> void:
	var ground_material: Material = materials.stone_dark if zone_id == 1 or is_castle else materials.grass
	_add_box(root, "ШирокаяЗемля", Vector3(0, -0.62, 0), Vector3(144.0, 0.9, CHUNK_LENGTH), ground_material)
	for side in [-1.0, 1.0]:
		_add_box(root, "ДальнийБерег", Vector3(side * 47.0, -0.02, 0), Vector3(48.0, 1.25, CHUNK_LENGTH), ground_material)
		_add_box(root, "ДальняяТерраса", Vector3(side * 66.0, 0.36, 0), Vector3(10.0, 1.9, CHUNK_LENGTH), materials.stone_dark)

	if zone_id != 1 and not is_castle:
		for side in [-1.0, 1.0]:
			for silhouette_index in range(3):
				var height := rng.randf_range(8.0, 16.0)
				var silhouette_position := Vector3(side * rng.randf_range(54.0, 66.0), height * 0.5 - 0.1, -14.0 + silhouette_index * 14.0)
				_add_box(root, "ДальнийСилуэт_%d_%d" % [int(side), silhouette_index], silhouette_position, Vector3(rng.randf_range(7.0, 12.0), height, rng.randf_range(7.0, 12.0)), materials.stone_dark)

func _build_outer_horizon(root: Node3D, rng: RandomNumberGenerator, zone_id: int, chunk_index: int) -> void:
	var town_assets := ["ruined_house_tall", "ruined_house_arch", "ruined_house_burned", "mist_watchtower"]
	var graveyard_assets := ["graveyard_crypt", "gothic_weeping_tree", "mist_ruin_tower", "gothic_crystal_tree"]
	var horizon_assets: Array = town_assets if zone_id == 0 else graveyard_assets
	for side_index in range(2):
		var side := -1.0 if side_index == 0 else 1.0
		var horizon_group := Node3D.new()
		horizon_group.name = "ДальнийГоризонт_%d" % int(side)
		root.add_child(horizon_group)
		for layer_index in range(3):
			var asset_id: String = horizon_assets[(chunk_index + side_index + layer_index) % horizon_assets.size()]
			var distance := 35.0 + layer_index * 10.5 + rng.randf_range(-1.5, 2.0)
			var local_z := -14.0 + layer_index * 14.0 + rng.randf_range(-2.5, 2.5)
			var scale_value := rng.randf_range(0.82, 1.08) + layer_index * 0.12
			_spawn_asset(horizon_group, asset_id, Vector3(side * distance, 0, local_z), Vector3(0, rng.randf_range(0, TAU), 0), Vector3.ONE * scale_value)

		var outer_fog := FogVolume.new()
		outer_fog.name = "ВнешнийТуман_%d" % int(side)
		outer_fog.position = Vector3(side * 49.0, 4.6, 0)
		outer_fog.size = Vector3(39.0, 12.0, CHUNK_LENGTH - 1.0)
		var fog_material := FogMaterial.new()
		fog_material.density = 0.038 if zone_id == 0 else 0.048
		fog_material.albedo = Color("75677d") if zone_id == 0 else Color("5f657c")
		fog_material.emission = Color("1c1828")
		fog_material.edge_fade = 0.9
		outer_fog.material = fog_material
		root.add_child(outer_fog)

		for light_index in range(2):
			var glow_position := Vector3(side * (39.0 + light_index * 13.0), 3.5 + light_index * 1.3, -10.0 + light_index * 20.0)
			var distant_light := OmniLight3D.new()
			distant_light.name = "ДальнийОгонь_%d_%d" % [int(side), light_index]
			distant_light.position = glow_position
			distant_light.light_color = Color("ff8550") if light_index == 0 else Color("8b8fd1")
			distant_light.light_energy = 2.7 if light_index == 0 else 1.8
			distant_light.omni_range = 19.0
			distant_light.shadow_enabled = false
			root.add_child(distant_light)
			_add_box(root, "ДальнийСвет_%d_%d" % [int(side), light_index], glow_position, Vector3(0.7, 1.2, 0.22), materials.fire)

func _build_zone(root: Node3D, rng: RandomNumberGenerator, zone_id: int, chapter: int, chunk_index: int) -> void:
	_build_zone_landscape(root, rng, zone_id, chapter, chunk_index)
	_build_zone_details(root, rng, zone_id, chapter, chunk_index)

func _build_zone_landscape(root: Node3D, rng: RandomNumberGenerator, zone_id: int, chapter: int, chunk_index: int) -> void:
	if zone_id == 0:
		_build_landscape(root, rng, 0, chapter, chunk_index)
	elif zone_id == 2:
		_build_landscape(root, rng, 3, chapter, chunk_index)

func _build_zone_details(root: Node3D, rng: RandomNumberGenerator, zone_id: int, chapter: int, chunk_index: int) -> void:
	match zone_id:
		0:
			_build_town_zone_details(root, rng, chapter, chunk_index)
		1:
			_build_castle_interior_zone(root, rng, chapter, chunk_index)
		2:
			_build_graveyard_zone_details(root, rng, chapter, chunk_index)

func _build_road(root: Node3D, rng: RandomNumberGenerator, index: int) -> void:
	_build_road_tiles(root, rng, index, 0, 10)

func _build_road_tiles(root: Node3D, rng: RandomNumberGenerator, index: int, start_tile: int, tile_count: int) -> void:
	var end_tile := mini(start_tile + tile_count, 10)
	for tile_index in range(start_tile, end_tile):
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
				var rock_position := Vector3(side * rng.randf_range(8.0, 12.0), rng.randf_range(0.1, 0.35), local_z + rng.randf_range(-1.4, 1.4))
				if not _spawn_asset(root, "rock_cluster", rock_position, Vector3(0, rng.randf_range(0, TAU), 0), Vector3.ONE * rng.randf_range(0.45, 0.82)):
					_add_rock(root, rock_position, rng.randf_range(0.45, 0.78))

func _build_roadside_towers(root: Node3D, rng: RandomNumberGenerator, zone_id: int, chunk_index: int, is_castle: bool) -> void:
	if is_castle or zone_id == 1:
		return
	if chunk_index == 0:
		for side_index in range(2):
			var side := -1.0 if side_index == 0 else 1.0
			var entrance := Node3D.new()
			entrance.name = "СтартоваяБашня_%02d" % side_index
			entrance.position = Vector3(side * 10.2, 0, 5.0)
			root.add_child(entrance)
			var asset_id := "mist_watchtower" if side_index == 0 else "mist_ruin_tower"
			_spawn_asset(entrance, asset_id, Vector3.ZERO, Vector3(0, side * PI * 0.5, 0), Vector3.ONE * 0.9)
			_add_torch(root, Vector3(side * 6.8, 1.5, 4.0))
		return
	if chunk_index % 2 != 0:
		return
	for side_index in range(2):
		var side := -1.0 if side_index == 0 else 1.0
		var tower_group := Node3D.new()
		tower_group.name = "ПридорожнаяБашня_%02d" % side_index
		tower_group.position = Vector3(side * rng.randf_range(10.5, 12.0), 0, -8.0 + rng.randf_range(-1.0, 1.0))
		root.add_child(tower_group)
		var asset_id := "mist_watchtower" if (chunk_index + side_index) % 4 == 0 else "mist_ruin_tower"
		var scale_value := rng.randf_range(0.78, 0.98)
		_spawn_asset(tower_group, asset_id, Vector3.ZERO, Vector3(0, side * PI * 0.5, 0), Vector3.ONE * scale_value)

func _build_landscape(root: Node3D, rng: RandomNumberGenerator, biome: int, chapter: int, chunk_index: int) -> void:
	var tree_assets := ["gothic_blossom_tree", "gothic_weeping_tree", "gothic_crystal_tree"]
	var tree_count := 3 + biome + mini(chapter, 3)
	for tree_index in range(tree_count):
		var side := -1.0 if tree_index % 2 == 0 else 1.0
		var tree_position := Vector3(side * rng.randf_range(19.0, 29.0), 0, rng.randf_range(-18.0, 10.0))
		var scale_value := rng.randf_range(0.52, 0.78)
		var asset_id: String = tree_assets[(chunk_index + tree_index + biome) % tree_assets.size()]
		var tree_rotation := rng.randf_range(0, TAU)
		if not _spawn_asset(root, asset_id, tree_position, Vector3(0, tree_rotation, 0), Vector3.ONE * scale_value):
			_add_tree(root, tree_position, scale_value, biome == 2)
		_add_tree_roots(root, tree_position, scale_value, tree_rotation)

	if biome == 1 or biome == 3:
		for ruin_index in range(2 + chapter % 3):
			var side := -1.0 if ruin_index % 2 == 0 else 1.0
			var ruin_position := Vector3(side * rng.randf_range(10.0, 17.0), 0, rng.randf_range(-17.0, 17.0))
			var ruin_scale := rng.randf_range(0.72, 1.18)
			if not _spawn_asset(root, "ruined_pillar", ruin_position, Vector3(0, rng.randf_range(0, TAU), 0), Vector3.ONE * ruin_scale):
				var fallback_height := rng.randf_range(3.0, 8.0)
				_add_box(root, "RuinedPillar", ruin_position + Vector3(0, fallback_height * 0.5, 0), Vector3(rng.randf_range(1.8, 3.2), fallback_height, rng.randf_range(1.8, 3.2)), materials.stone)

	if biome >= 2:
		for local_z in [-12.0, 10.0]:
			for side in [-1.0, 1.0]:
				_add_torch(root, Vector3(side * 5.8, 1.5, local_z))

func _build_town_zone_details(root: Node3D, rng: RandomNumberGenerator, _chapter: int, chunk_index: int) -> void:
	for side in [-1.0, 1.0]:
		var house_count := 2 if chunk_index == 0 else 3
		for house_index in range(house_count):
			var local_z := -14.0 + house_index * 14.0 + rng.randf_range(-1.2, 1.2)
			var style := (chunk_index * 3 + house_index + (0 if side < 0 else 1)) % 4
			_add_town_house(root, Vector3(side * rng.randf_range(16.0, 21.0), 0, local_z), side, rng, style)
		for local_z in [-12.0, 11.0]:
			_add_street_lantern(root, Vector3(side * 6.5, 10.5, local_z), side)
		for _pumpkin_index in range(3):
			_add_pumpkin(
				root,
				Vector3(side * rng.randf_range(10.0, 13.0), 0.4, rng.randf_range(-18.0, 18.0)),
				rng.randf_range(0.42, 0.66),
				rng.randf_range(-PI, PI)
			)
	if chunk_index < 2:
		return
	match chunk_index % 5:
		0:
			_add_vampire_fog(root, Vector3(LANE_X[1], LANE_Y[1], -2.0))
		1:
			var flock_wave := floori(float(chunk_index) / 5.0)
			_add_bird_flock(root, Vector3(LANE_X[1], LANE_Y[2], -4.0), flock_wave % 2 == 0)
		2:
			_add_deadly_branch(root, Vector3(LANE_X[1], LANE_Y[1], -3.0))
		3:
			_add_sign_or_balcony(root, Vector3(LANE_X[0], LANE_Y[1], -4.0), chunk_index % 2 == 0)
		4:
			var obstacle_x: float = LANE_X[rng.randi_range(0, 2)]
			if chunk_index % 2 == 0:
				_add_ground_pumpkin(root, Vector3(obstacle_x, 0.0, -3.0))
			else:
				_add_falling_debris(root, Vector3(obstacle_x, 14.0, -3.0))

func _build_opening_route(root: Node3D, chunk_index: int) -> void:
	for side in [-1.0, 1.0]:
		_add_box(root, "СтартоваяТерраса", Vector3(side * 17.0, -0.08, 0), Vector3(14.0, 0.55, CHUNK_LENGTH - 1.2), materials.stone_dark)
		for section_index in range(4):
			if (section_index + chunk_index) % 3 == 1:
				continue
			var local_z := -15.0 + section_index * 10.0
			_add_box(root, "НизкаяКаменнаяОграда", Vector3(side * 8.8, 0.72, local_z), Vector3(0.72, 1.44, 7.4), materials.stone)
			_add_box(root, "МшистыйЦокольОграды", Vector3(side * 8.8, 0.16, local_z), Vector3(1.15, 0.22, 7.8), materials.moss)
		for post_z in [-18.0, 18.0]:
			_add_box(root, "КрайнийСтолб", Vector3(side * 8.8, 1.55, post_z), Vector3(1.35, 3.1, 1.35), materials.stone_dark)
			_add_box(root, "НавершиеСтолба", Vector3(side * 8.8, 3.22, post_z), Vector3(1.75, 0.34, 1.75), materials.stone_light)
		var fog := FogVolume.new()
		fog.name = "БоковойТуман_%d_%d" % [chunk_index, int(side)]
		fog.position = Vector3(side * 25.0, 3.2, 0)
		fog.size = Vector3(24.0, 9.0, CHUNK_LENGTH - 2.0)
		var fog_material := FogMaterial.new()
		fog_material.density = 0.052
		fog_material.albedo = Color("806c82")
		fog_material.emission = Color("241b30")
		fog_material.edge_fade = 0.82
		fog.material = fog_material
		root.add_child(fog)
		for depth_index in range(2):
			var local_z := -11.0 + depth_index * 21.0
			var glow_position := Vector3(side * (20.5 + depth_index * 3.2), 3.2 + depth_index * 1.1, local_z)
			var glow := OmniLight3D.new()
			glow.name = "ОгоньВТумане_%d_%d_%d" % [chunk_index, int(side), depth_index]
			glow.position = glow_position
			glow.light_color = Color("ff8751") if depth_index == 0 else Color("8398d8")
			glow.light_energy = 3.6 if depth_index == 0 else 2.2
			glow.omni_range = 17.0
			glow.shadow_enabled = false
			root.add_child(glow)
			_add_box(root, "СветящеесяОкноВДымке", glow_position + Vector3(0, 0, -0.8), Vector3(1.15, 1.8, 0.18), materials.fire)

func _build_castle_interior_zone(root: Node3D, rng: RandomNumberGenerator, _chapter: int, chunk_index: int) -> void:
	_add_box(root, "ЗеркальныйКаменныйПол", Vector3(0, -0.08, 0), Vector3(28.0, 0.16, 39.0), materials.polished_stone)
	_add_box(root, "HallCarpet", Vector3(0, 0.08, 0), Vector3(5.2, 0.12, 39.0), materials.blood_cloth)
	_add_box(root, "HallCeiling", Vector3(0, 16.3, 0), Vector3(29.0, 1.0, 40.0), materials.stone_dark)
	for side in [-1.0, 1.0]:
		_add_box(root, "HallWall", Vector3(side * 13.5, 8.0, 0), Vector3(2.0, 16.0, 40.0), materials.stone_dark)
		_add_box(root, "ПолированнаяПанель", Vector3(side * 12.4, 2.2, 0), Vector3(0.18, 4.4, 39.0), materials.polished_stone)
		for local_z in [-15.0, -5.0, 5.0, 15.0]:
			_spawn_asset(root, "gothic_pillar", Vector3(side * 8.2, 0, local_z), Vector3.ZERO, Vector3.ONE * 0.82)
			_add_torch(root, Vector3(side * 10.8, 5.0, local_z + 2.0))
		for tapestry_z in [-11.0, 10.0]:
			_add_box(root, "Гобелен", Vector3(side * 12.42, 7.5, tapestry_z), Vector3(0.14, 5.2, 3.8), materials.blood_cloth)
	_add_castle_stairs(root, -1.0 if chunk_index % 2 == 0 else 1.0)
	_add_spiral_stairs(root, 1.0 if chunk_index % 2 == 0 else -1.0)
	var reflection := ReflectionProbe.new()
	reflection.name = "ОтраженияЗамковогоЗала"
	reflection.position = Vector3(0, 7.5, 0)
	reflection.size = Vector3(27.0, 15.0, 39.0)
	reflection.max_distance = 45.0
	reflection.intensity = 4.2
	reflection.blend_distance = 3.0
	reflection.box_projection = true
	reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	root.add_child(reflection)
	match chunk_index % 3:
		0:
			_add_chandelier(root, Vector3(rng.randf_range(-1.8, 1.8), 14.0, -3.0))
		1:
			_add_ground_gear(root, Vector3(0, 2.4, -4.0), 2.5)
		2:
			_add_pendulum(root, Vector3(rng.randf_range(-2.0, 2.0), 15.0, -4.0))

func _build_graveyard_zone_details(root: Node3D, rng: RandomNumberGenerator, _chapter: int, chunk_index: int) -> void:
	for side in [-1.0, 1.0]:
		_add_crypt(root, Vector3(side * rng.randf_range(13.0, 17.0), 0, rng.randf_range(-12.0, 12.0)), side)
		_add_dry_tree(root, Vector3(side * rng.randf_range(9.0, 15.0), 0, rng.randf_range(-18.0, 18.0)), side)
		_add_street_lantern(root, Vector3(side * 6.6, 10.8, 12.0), side)
	for grave_index in range(12):
		var side := -1.0 if grave_index % 2 == 0 else 1.0
		var grave_position := Vector3(side * rng.randf_range(7.2, 14.0), rng.randf_range(0.8, 1.3), rng.randf_range(-18.0, 18.0))
		_add_gravestone(root, grave_position, rng.randf_range(-18.0, 18.0), rng.randf_range(0.72, 1.12))
	for fog_index in range(5):
		_add_sphere(root, Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(0.5, 1.4), rng.randf_range(-18.0, 18.0)), Vector3(rng.randf_range(3.0, 6.0), 0.8, rng.randf_range(2.0, 4.5)), materials.fog)
	match chunk_index % 4:
		0:
			_add_vampire_fog(root, Vector3(LANE_X[1], LANE_Y[0], -3.0))
		1:
			_add_grave_hand(root, Vector3(LANE_X[rng.randi_range(0, 2)], 3.2, -3.0))
		2:
			_add_grave_hand(root, Vector3(LANE_X[rng.randi_range(0, 2)], 3.2, -3.0))
		3:
			_add_grave_pit(root, Vector3(0, 0.5, -3.0))

func _add_town_house(parent: Node3D, spawn_position: Vector3, side: float, rng: RandomNumberGenerator, style := 0) -> void:
	var house := Node3D.new()
	house.name = "СтарыйДом"
	house.position = spawn_position
	house.rotation.y = -side * PI * 0.5
	parent.add_child(house)
	_add_box(house, "КаменныйФундамент", Vector3(0, 0.34, 0), Vector3(8.6, 0.68, 7.6), materials.stone_dark)
	_add_box(house, "ВходнаяСтупень", Vector3(0, 0.38, -4.05), Vector3(3.0, 0.34, 1.0), materials.stone)
	var house_assets := ["crooked_house", "ruined_house_tall", "ruined_house_arch", "ruined_house_burned"]
	var house_asset: String = house_assets[style % house_assets.size()]
	var house_scale := rng.randf_range(0.48, 0.66) if house_asset == "crooked_house" else rng.randf_range(0.62, 0.82)
	if _spawn_asset(house, house_asset, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * house_scale):
		return
	var height := rng.randf_range(7.0, 12.0)
	_add_box(house, "Фасад", Vector3(0, height * 0.5, 0), Vector3(rng.randf_range(6.0, 9.0), height, 6.5), materials.stone_dark)
	var roof := _add_box(house, "Крыша", Vector3(0, height + 1.5, 0), Vector3(7.5, 2.4, 7.4), materials.roof)
	roof.rotation.z = 0.12 * side
	for floor_index in range(2):
		for window_index in [-1.0, 1.0]:
			_add_box(house, "СветящеесяОкно", Vector3(window_index * 1.7, 3.0 + floor_index * 3.2, -3.31), Vector3(1.0, 1.45, 0.12), materials.fire)

func _add_castle_stairs(parent: Node3D, side: float) -> void:
	for step_index in range(9):
		var z := 14.0 - step_index * 1.45
		var y := 0.35 + step_index * 0.55
		_add_box(parent, "Ступень_%02d" % step_index, Vector3(side * 6.0, y, z), Vector3(5.2, 0.7, 1.55), materials.stone_light)

func _add_spiral_stairs(parent: Node3D, side: float) -> void:
	var center := Vector3(side * 8.7, 0, -8.0)
	_add_cylinder(parent, center + Vector3(0, 4.2, 0), 0.35, 8.4, materials.iron)
	for step_index in range(14):
		var angle := step_index * 0.62
		var step_position := center + Vector3(cos(angle) * 2.0, 0.4 + step_index * 0.48, sin(angle) * 2.0)
		var step := _add_box(parent, "ВинтоваяСтупень_%02d" % step_index, step_position, Vector3(3.2, 0.35, 1.05), materials.stone_light)
		step.rotation.y = -angle

func _add_gravestone(parent: Node3D, spawn_position: Vector3, yaw_degrees: float, scale_value: float) -> void:
	var grave := Node3D.new()
	grave.name = "Надгробие"
	grave.position = spawn_position - Vector3(0, spawn_position.y, 0)
	grave.rotation_degrees.y = yaw_degrees
	parent.add_child(grave)
	if _spawn_asset(grave, "gothic_gravestone", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * scale_value):
		return
	_add_box(grave, "КаменнаяПлита", Vector3(0, spawn_position.y, 0), Vector3(scale_value, spawn_position.y * 2.0, 0.45 * scale_value), materials.stone)

func _add_crypt(parent: Node3D, spawn_position: Vector3, side: float) -> void:
	var crypt := Node3D.new()
	crypt.name = "СтарыйСклеп"
	crypt.position = spawn_position
	crypt.rotation.y = side * 0.08
	parent.add_child(crypt)
	if _spawn_asset(crypt, "graveyard_crypt", Vector3.ZERO, Vector3.ZERO, Vector3.ONE):
		return
	_add_box(crypt, "СтеныСклепа", Vector3(0, 2.7, 0), Vector3(6.5, 5.4, 6.0), materials.stone_dark)
	_add_box(crypt, "ВходВСклеп", Vector3(0, 2.0, -3.05), Vector3(2.2, 3.8, 0.18), materials.iron)
	var roof := _add_box(crypt, "КрышаСклепа", Vector3(0, 6.0, 0), Vector3(7.2, 1.4, 6.8), materials.stone)
	roof.rotation.z = side * 0.08

func _add_dry_tree(parent: Node3D, spawn_position: Vector3, side: float) -> void:
	var tree := Node3D.new()
	tree.name = "СухоеДерево"
	tree.position = spawn_position
	parent.add_child(tree)
	var trunk := _add_box(tree, "СухойСтвол", Vector3(0, 4.0, 0), Vector3(0.9, 8.0, 0.9), materials.wood)
	trunk.rotation.z = side * 0.08
	for branch_index in range(5):
		var branch_side := -1.0 if branch_index % 2 == 0 else 1.0
		var branch := _add_box(tree, "СухаяВетка", Vector3(branch_side * 1.5, 5.3 + branch_index * 0.7, 0), Vector3(3.6, 0.38, 0.42), materials.wood)
		branch.rotation.z = branch_side * (0.32 + branch_index * 0.04)

func _add_pumpkin(parent: Node3D, spawn_position: Vector3, scale_value: float, yaw: float) -> void:
	var doubled_scale := scale_value * 2.0
	var pumpkin_anchor := Node3D.new()
	pumpkin_anchor.name = "ДекоративнаяТыква_%03d" % parent.get_child_count()
	pumpkin_anchor.position = spawn_position
	pumpkin_anchor.rotation.y = yaw
	parent.add_child(pumpkin_anchor)
	if _spawn_asset(pumpkin_anchor, "carved_pumpkin", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * doubled_scale):
		return
	var pumpkin := _add_sphere(pumpkin_anchor, Vector3.ZERO, Vector3(0.7, 0.58, 0.7) * doubled_scale, materials.pumpkin)
	pumpkin.name = "Тыква"
	_add_box(pumpkin_anchor, "СтебельТыквы", Vector3(0, 0.48 * doubled_scale, 0), Vector3(0.16, 0.35, 0.16) * doubled_scale, materials.moss)

func _create_deadly_area(parent: Node3D, node_name: String, spawn_position: Vector3, size: Vector3, collision_offset: Vector3, reason: String) -> DeadlyObstacle:
	var hazard := DeadlyObstacle.new()
	hazard.name = node_name
	hazard.position = spawn_position
	hazard.death_reason = reason
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = collision_offset
	hazard.add_child(collision)
	parent.add_child(hazard)
	return hazard

func _add_street_lantern(parent: Node3D, spawn_position: Vector3, side: float) -> void:
	var lantern := _create_deadly_area(parent, "КачающийсяФонарь", spawn_position, Vector3(1.3, 2.2, 1.3), Vector3(0, -4.1, 0), "СОВА УДАРИЛАСЬ О КАЧАЮЩИЙСЯ ФОНАРЬ")
	lantern.swing_axis = Vector3(0, 0, 1)
	lantern.swing_angle = 0.34 * side
	lantern.swing_speed = 1.15
	lantern.light_pulse = 0.22
	_add_box(parent, "ФонарныйСтолб", spawn_position + Vector3(side * 2.4, -5.25, 0), Vector3(0.48, 10.5, 0.48), materials.wood)
	_add_box(parent, "КаменноеОснованиеФонаря", spawn_position + Vector3(side * 2.4, -10.15, 0), Vector3(1.35, 0.7, 1.35), materials.stone_dark)
	_add_box(parent, "КронштейнФонаря", spawn_position + Vector3(side * 1.2, -0.08, 0), Vector3(2.75, 0.34, 0.42), materials.iron)
	var brace := _add_box(parent, "ПодкосФонаря", spawn_position + Vector3(side * 1.72, -0.72, 0), Vector3(1.75, 0.24, 0.28), materials.iron)
	brace.rotation.z = side * 0.62
	if not _spawn_asset(lantern, "street_lantern", Vector3.ZERO, Vector3.ZERO, Vector3.ONE):
		_add_box(lantern, "Цепь", Vector3(0, -2.0, 0), Vector3(0.14, 4.0, 0.14), materials.iron)
		_add_box(lantern, "Корпус", Vector3(0, -4.1, 0), Vector3(1.15, 1.65, 1.15), materials.iron)
		_add_sphere(lantern, Vector3(0, -4.1, 0), Vector3(0.52, 0.7, 0.52), materials.fire)
	_add_flame_effect(lantern, "ПламяФонаря", Vector3(0, -4.55, 0), 0.8, 10)
	var light := OmniLight3D.new()
	light.position = Vector3(0, -4.1, 0)
	light.light_color = Color("ff8a4d")
	light.light_energy = 2.4
	light.omni_range = 8.0
	lantern.add_child(light)

func _add_tree_roots(parent: Node3D, spawn_position: Vector3, scale_value: float, yaw: float) -> void:
	var roots := Node3D.new()
	roots.name = "ОснованиеДерева"
	roots.position = spawn_position + Vector3(0, 0.16, 0)
	roots.rotation.y = yaw
	parent.add_child(roots)
	for root_index in range(4):
		var angle := root_index * PI * 0.5 + 0.28
		var length := (2.5 + root_index % 2 * 0.55) * scale_value
		var root_piece := _add_box(roots, "Корень", Vector3(cos(angle) * length * 0.34, 0, sin(angle) * length * 0.34), Vector3(length, 0.38 * scale_value, 0.62 * scale_value), materials.trunk)
		root_piece.rotation.y = -angle
	_add_box(roots, "МохУКорней", Vector3(0, -0.11, 0), Vector3(3.2, 0.18, 3.0) * scale_value, materials.moss)

func _add_vampire_fog(parent: Node3D, spawn_position: Vector3) -> void:
	var fog := _create_deadly_area(parent, "ОблакоВампирскогоТумана", spawn_position, Vector3(7.8, 4.2, 3.6), Vector3.ZERO, "СОВУ ПОГЛОТИЛ ВАМПИРСКИЙ ТУМАН")
	fog.drift = Vector3.RIGHT
	fog.drift_distance = 2.8
	fog.drift_speed = 0.72
	for cloud_index in range(7):
		var x := (cloud_index - 3) * 0.9
		var y := sin(cloud_index * 1.7) * 0.7
		var z := cos(cloud_index * 1.2) * 0.55
		_add_sphere(fog, Vector3(x, y, z), Vector3(2.1, 1.25, 1.45), materials.fog)
	var particles := GPUParticles3D.new()
	particles.name = "КлубящийсяТуман"
	particles.amount = 28
	particles.lifetime = 4.8
	particles.preprocess = 4.8
	particles.randomness = 0.75
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-6, -3, -4), Vector3(12, 6, 8))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(3.4, 1.25, 1.45)
	process.direction = Vector3(0.7, 0.25, 0.1)
	process.spread = 55.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.65
	process.gravity = Vector3(0, 0.08, 0)
	process.scale_min = 0.65
	process.scale_max = 1.55
	particles.process_material = process
	var mist_mesh := SphereMesh.new()
	mist_mesh.radius = 0.62
	mist_mesh.height = 1.2
	mist_mesh.radial_segments = 8
	mist_mesh.rings = 4
	mist_mesh.material = materials.fog
	particles.draw_pass_1 = mist_mesh
	fog.add_child(particles)

func _add_bird_flock(parent: Node3D, spawn_position: Vector3, crows: bool) -> void:
	var reason := "СТАЯ ВОРОНОВ СБИЛА СОВУ" if crows else "СТАЯ ЛЕТУЧИХ МЫШЕЙ СБИЛА СОВУ"
	var flock_name := "СтаяВоронов" if crows else "СтаяЛетучихМышей"
	var asset_id := "raven_crow" if crows else "vampire_bat"
	var flock := _create_deadly_area(parent, flock_name, spawn_position, Vector3(5.6, 2.6, 2.2), Vector3.ZERO, reason)
	flock.drift = Vector3.RIGHT
	flock.drift_distance = 4.0
	flock.drift_speed = 1.05
	flock.animate_flock = true
	for bird_index in range(9):
		var bird_root := Node3D.new()
		bird_root.name = "Ворон" if crows else "ЛетучаяМышь"
		bird_root.set_meta("flock_member", true)
		bird_root.position = Vector3((bird_index % 3 - 1) * 1.55, (floori(float(bird_index) / 3.0) - 1) * 0.72, (bird_index % 2) * 0.55)
		bird_root.rotation.y = PI if crows else 0.0
		flock.add_child(bird_root)
		var bird_scale := 0.29 + (bird_index % 3) * 0.035 if crows else 0.33 + (bird_index % 3) * 0.04
		if not _spawn_asset(bird_root, asset_id, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * bird_scale):
			var left := _add_box(bird_root, "ЛевоеКрыло", Vector3(-0.35, 0, 0), Vector3(0.75, 0.12, 0.42), materials.iron)
			left.rotation.z = 0.28
			var right := _add_box(bird_root, "ПравоеКрыло", Vector3(0.35, 0, 0), Vector3(0.75, 0.12, 0.42), materials.iron)
			right.rotation.z = -0.28
			_add_sphere(bird_root, Vector3.ZERO, Vector3(0.28, 0.32, 0.32), materials.iron)

func _add_deadly_branch(parent: Node3D, spawn_position: Vector3) -> void:
	var branch := _create_deadly_area(parent, "ВыступающаяВетка", spawn_position, Vector3(7.6, 2.4, 1.35), Vector3.ZERO, "СОВА НАЛЕТЕЛА НА ВЕТКУ")
	branch.rotation.z = 0.24
	if _spawn_asset(branch, "dead_branch", Vector3.ZERO, Vector3.ZERO, Vector3.ONE):
		return
	_add_box(branch, "ТолстаяВетка", Vector3.ZERO, Vector3(7.2, 0.65, 0.9), materials.wood)
	for twig_index in range(4):
		var twig := _add_box(branch, "Сучок", Vector3(-2.3 + twig_index * 1.5, 0.55, 0), Vector3(0.3, 1.5, 0.3), materials.wood)
		twig.rotation.z = -0.48 + twig_index * 0.12

func _add_sign_or_balcony(parent: Node3D, spawn_position: Vector3, balcony: bool) -> void:
	if balcony:
		var balcony_hazard := _create_deadly_area(parent, "ВыступающийБалкон", spawn_position, Vector3(5.6, 2.7, 3.0), Vector3.ZERO, "СОВА ВРЕЗАЛАСЬ В СТАРЫЙ БАЛКОН")
		_add_box(balcony_hazard, "КаменноеОснование", Vector3(0, -0.8, 0), Vector3(5.6, 0.65, 3.0), materials.stone)
		for rail_x in [-2.45, -1.2, 0.0, 1.2, 2.45]:
			_add_box(balcony_hazard, "СтойкаОграждения", Vector3(rail_x, 0.55, -1.15), Vector3(0.18, 2.2, 0.18), materials.iron)
		_add_box(balcony_hazard, "Перила", Vector3(0, 1.6, -1.15), Vector3(5.5, 0.22, 0.22), materials.iron)
		for support_x in [-1.9, 1.9]:
			var support := _add_box(balcony_hazard, "ПодкосБалкона", Vector3(support_x, -1.55, 0.5), Vector3(0.3, 2.6, 0.3), materials.iron)
			support.rotation.x = 0.48
		return
	var sign_hazard := _create_deadly_area(parent, "ВыступающаяВывеска", spawn_position, Vector3(4.8, 1.4, 1.2), Vector3.ZERO, "СОВА ВРЕЗАЛАСЬ В СТАРУЮ ВЫВЕСКУ")
	_add_box(sign_hazard, "ДоскаВывески", Vector3.ZERO, Vector3(4.8, 1.25, 0.55), materials.wood)
	_add_box(sign_hazard, "ЖелезныйКронштейн", Vector3(-2.8, 1.1, 0), Vector3(1.8, 0.18, 0.18), materials.iron)

func _add_ground_pumpkin(parent: Node3D, spawn_position: Vector3) -> void:
	var road_pumpkin_scale := 3.1 / 1.5
	var resized_visual_bounds := Vector3(6.2, 9.0, 6.0) / 1.5
	var hitbox_size := resized_visual_bounds * 0.75
	var hitbox_offset := Vector3(0, hitbox_size.y * 0.5, 0)
	var pumpkin := _create_deadly_area(parent, "БольшаяТыква", spawn_position, hitbox_size, hitbox_offset, "СОВА ВРЕЗАЛАСЬ В ОГРОМНУЮ ТЫКВУ")
	if not _spawn_asset(pumpkin, "carved_pumpkin", Vector3.ZERO, Vector3(0, PI, 0), Vector3.ONE * road_pumpkin_scale):
		_add_sphere(pumpkin, Vector3(0, 4.0, 0) / 1.5, Vector3(3.0, 3.8, 3.0) / 1.5, materials.pumpkin)
		_add_box(pumpkin, "Стебель", Vector3(0, 8.0, 0) / 1.5, Vector3(0.65, 1.2, 0.65) / 1.5, materials.moss)

func _add_falling_debris(parent: Node3D, spawn_position: Vector3) -> void:
	var debris := _create_deadly_area(parent, "ПадающийПредмет", spawn_position, Vector3(2.0, 0.8, 1.5), Vector3.ZERO, "СОВУ СБИЛА ПАДАЮЩАЯ ЧЕРЕПИЦА")
	debris.fall_distance = 13.0
	debris.fall_speed = 5.0
	var tile := _add_box(debris, "Черепица", Vector3.ZERO, Vector3(2.0, 0.35, 1.4), materials.roof)
	tile.rotation_degrees = Vector3(14, 18, 9)

func _add_chandelier(parent: Node3D, spawn_position: Vector3) -> void:
	var chandelier := _create_deadly_area(parent, "КачающаясяЛюстра", spawn_position, Vector3(5.2, 2.2, 5.2), Vector3(0, -5.0, 0), "СОВА УДАРИЛАСЬ О КАЧАЮЩУЮСЯ ЛЮСТРУ")
	chandelier.swing_axis = Vector3(0, 0, 1)
	chandelier.swing_angle = 0.42
	chandelier.swing_speed = 1.22
	chandelier.light_pulse = 0.35
	if not _spawn_asset(chandelier, "candle_chandelier", Vector3.ZERO, Vector3.ZERO, Vector3.ONE):
		_add_box(chandelier, "Цепь", Vector3(0, -2.3, 0), Vector3(0.18, 4.6, 0.18), materials.iron)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.55
		torus.outer_radius = 2.15
		ring.mesh = torus
		ring.position = Vector3(0, -5.0, 0)
		ring.material_override = materials.iron
		chandelier.add_child(ring)
		for candle_index in range(8):
			var angle := candle_index * TAU / 8.0
			var candle_position := Vector3(cos(angle) * 1.85, -4.45, sin(angle) * 1.85)
			_add_cylinder(chandelier, candle_position, 0.12, 0.8, materials.stone_light)
			_add_sphere(chandelier, candle_position + Vector3(0, 0.56, 0), Vector3(0.16, 0.34, 0.16), materials.fire)
	for flame_index in range(8):
		var flame_angle := flame_index * TAU / 8.0
		var flame_position := Vector3(cos(flame_angle) * 1.75, -3.35, sin(flame_angle) * 1.75)
		_add_flame_effect(chandelier, "ПламяСвечи_%02d" % flame_index, flame_position, 0.72, 7)
	var light := OmniLight3D.new()
	light.position = Vector3(0, -4.2, 0)
	light.light_color = Color("ff8a55")
	light.light_energy = 4.2
	light.omni_range = 13.0
	light.shadow_enabled = true
	chandelier.add_child(light)

func _add_ground_gear(parent: Node3D, spawn_position: Vector3, radius: float) -> void:
	var gear := _create_deadly_area(parent, "ЕдущаяШестерня", spawn_position, Vector3(radius * 2.0, radius * 2.0, 1.6), Vector3.ZERO, "СОВУ ПЕРЕМОЛОЛА ОГРОМНАЯ ШЕСТЕРНЯ")
	gear.spin_axis = Vector3(0, 0, 1)
	gear.spin_speed = 2.4
	gear.drift = Vector3.RIGHT
	gear.drift_distance = 3.2
	gear.drift_speed = 0.78
	if not _spawn_asset(gear, "ground_gear", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (radius / 2.9)):
		_add_cylinder(gear, Vector3.ZERO, radius, 1.35, materials.iron, Vector3(PI * 0.5, 0, 0))
		for tooth_index in range(12):
			var angle := tooth_index * TAU / 12.0
			var tooth := _add_box(gear, "ЗубШестерни", Vector3(cos(angle) * radius, sin(angle) * radius, 0), Vector3(0.72, 1.0, 1.55), materials.iron)
			tooth.rotation.z = angle

func _add_pendulum(parent: Node3D, spawn_position: Vector3) -> void:
	var pendulum := _create_deadly_area(parent, "ЗамковыйМаятник", spawn_position, Vector3(2.4, 2.4, 2.4), Vector3(0, -6.2, 0), "СОВУ СБИЛ ЗАМКОВЫЙ МАЯТНИК")
	pendulum.swing_axis = Vector3(0, 0, 1)
	pendulum.swing_angle = 0.72
	pendulum.swing_speed = 1.35
	_add_box(pendulum, "ЦепьМаятника", Vector3(0, -3.0, 0), Vector3(0.22, 6.0, 0.22), materials.iron)
	_add_sphere(pendulum, Vector3(0, -6.2, 0), Vector3(1.25, 1.25, 1.25), materials.iron)

func _add_grave_hand(parent: Node3D, spawn_position: Vector3) -> void:
	var hand := _create_deadly_area(parent, "РукаИзМогилы", spawn_position, Vector3(2.2, 5.5, 2.0), Vector3.ZERO, "РУКА ИЗ МОГИЛЫ СХВАТИЛА СОВУ")
	hand.swing_axis = Vector3(0, 0, 1)
	hand.swing_angle = 0.2
	hand.swing_speed = 1.4
	if _spawn_asset(hand, "grave_hand", Vector3.ZERO, Vector3.ZERO, Vector3.ONE):
		return
	_add_box(hand, "Предплечье", Vector3(0, -1.2, 0), Vector3(0.72, 4.2, 0.72), materials.stone_light)
	_add_box(hand, "Ладонь", Vector3(0, 1.05, 0), Vector3(1.6, 1.1, 0.7), materials.stone_light)
	for finger_index in range(4):
		var finger := _add_box(hand, "Палец", Vector3(-0.62 + finger_index * 0.42, 2.0, 0), Vector3(0.24, 1.35, 0.25), materials.stone_light)
		finger.rotation.z = (finger_index - 1.5) * 0.11

func _add_grave_pit(parent: Node3D, spawn_position: Vector3) -> void:
	var pit := _create_deadly_area(parent, "ПровалВЗемле", spawn_position, Vector3(5.8, 2.4, 5.2), Vector3.ZERO, "СОВА ПРОВАЛИЛАСЬ В МОГИЛЬНУЮ БЕЗДНУ")
	_add_box(pit, "ТемнотаПровала", Vector3(0, -0.55, 0), Vector3(5.8, 0.18, 5.2), materials.iron)
	for edge_index in range(8):
		var angle := edge_index * TAU / 8.0
		var rock := _add_box(pit, "КрайПровала", Vector3(cos(angle) * 2.7, 0, sin(angle) * 2.35), Vector3(1.2, 0.55, 0.8), materials.stone_dark)
		rock.rotation.y = -angle

func _add_cylinder(parent: Node3D, spawn_position: Vector3, radius: float, height: float, material: Material, rotation_value := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.position = spawn_position
	instance.rotation = rotation_value
	instance.material_override = material
	parent.add_child(instance)
	return instance

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
	origin_start_z += REBASE_AMOUNT
	position.z -= REBASE_AMOUNT
	for chunk in active_chunks.values():
		chunk.position.z += REBASE_AMOUNT
	reset_physics_interpolation()

func _spawn_asset(parent: Node3D, asset_id: String, spawn_position: Vector3, spawn_rotation: Vector3, scale_value: Vector3) -> bool:
	var path: String = ASSETS[asset_id]
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if not packed:
		return false
	var instance := packed.instantiate() as Node3D
	instance.name = asset_id.to_pascal_case()
	instance.position = spawn_position
	instance.rotation = spawn_rotation
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
		"road_tile", "road_edge", "tree", "gothic_weeping_tree", "gothic_blossom_tree", "gothic_crystal_tree", "ruined_pillar", "gothic_pillar":
			return 240.0
		"mist_watchtower", "mist_ruin_tower":
			return 360.0
		_:
			return 480.0

func _add_tower(parent: Node3D, spawn_position: Vector3, radius: float, height: float) -> void:
	var tower := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.86
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	tower.mesh = mesh
	tower.position = spawn_position + Vector3(0, height * 0.5, 0)
	tower.material_override = materials.stone
	parent.add_child(tower)
	_add_box(parent, "TowerRoof", spawn_position + Vector3(0, height + 1.2, 0), Vector3(radius * 1.75, 2.4, radius * 1.75), materials.roof)

func _add_tree(parent: Node3D, spawn_position: Vector3, scale_value: float, warm: bool) -> void:
	var root := Node3D.new()
	root.name = "TwilightTree"
	root.position = spawn_position
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

func _add_rock(parent: Node3D, spawn_position: Vector3, scale_value: float) -> void:
	var rock := _add_box(parent, "RoadsideRock", spawn_position, Vector3(1.5, 1.05, 1.25) * scale_value, materials.stone_light)
	rock.rotation_degrees = Vector3(8, fmod(spawn_position.z * 17.0, 45.0), 11)

func _add_torch(parent: Node3D, spawn_position: Vector3) -> void:
	var imported := _spawn_asset(parent, "torch", spawn_position, Vector3.ZERO, Vector3.ONE)
	var flame_height := 3.45 if imported else 1.85
	if not imported:
		_add_box(parent, "TorchPost", spawn_position, Vector3(0.25, 3.0, 0.25), materials.trunk)
		var flame := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.25
		mesh.height = 0.7
		mesh.radial_segments = 8
		mesh.rings = 4
		flame.mesh = mesh
		flame.position = spawn_position + Vector3(0, flame_height, 0)
		flame.material_override = materials.fire
		parent.add_child(flame)
	_add_flame_effect(parent, "ПламяФакела", spawn_position + Vector3(0, flame_height, -0.45 if imported else 0.0), 0.72, 8)
	var light := OmniLight3D.new()
	light.position = spawn_position + Vector3(0, flame_height, -0.45 if imported else 0.0)
	light.light_color = Color("ff8b52")
	light.light_energy = 3.4
	light.omni_range = 10.0
	light.shadow_enabled = false
	parent.add_child(light)

func _add_flame_effect(parent: Node3D, node_name: String, spawn_position: Vector3, size: float, amount: int) -> void:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = spawn_position
	particles.amount = amount
	particles.lifetime = 0.62
	particles.preprocess = 0.62
	particles.randomness = 0.55
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-1.2, -1.0, -1.2), Vector3(2.4, 3.0, 2.4))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.07 * size
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = 0.3 * size
	process.initial_velocity_max = 0.9 * size
	process.gravity = Vector3(0, 0.45, 0)
	process.scale_min = 0.45
	process.scale_max = 1.0
	process.color = Color("ff8a42")
	particles.process_material = process
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.11 * size
	flame_mesh.height = 0.34 * size
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	flame_mesh.material = materials.fire
	particles.draw_pass_1 = flame_mesh
	parent.add_child(particles)

func _add_box(parent: Node3D, node_name: String, spawn_position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = spawn_position
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node3D, spawn_position: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	instance.mesh = mesh
	instance.position = spawn_position
	instance.scale = scale_value
	instance.material_override = material
	parent.add_child(instance)
	return instance
