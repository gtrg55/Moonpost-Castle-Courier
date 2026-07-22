extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _require(packed != null, "Главная сцена должна загружаться"):
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var streamer := main.get_node("ProceduralWorldStreamer") as WorldStreamer
	var starting_chunk: Node3D = streamer.active_chunks[0]

	var town: Node3D = streamer.active_chunks[2]
	var town_with_pumpkin: Node3D = streamer.active_chunks[4]
	var town_with_flock := streamer._build_chunk(6)
	var town_with_fog := streamer._build_chunk(25)
	var town_with_tiles := streamer._build_chunk(49)
	var town_with_crows := streamer._build_chunk(31)
	var town_with_balcony := streamer._build_chunk(28)
	var castle := streamer._build_chunk(8)
	var castle_with_chandelier := streamer._build_chunk(9)
	var castle_with_gear := streamer._build_chunk(10)
	var graveyard := streamer._build_chunk(16)
	var graveyard_variant := streamer._build_chunk(21)
	var graveyard_with_hand := streamer._build_chunk(18)
	var graveyard_with_pit := streamer._build_chunk(19)
	if not _require(town.find_child("СтарыйДом", true, false) != null, "В предместье должны быть дома"):
		return
	if not _require(town.find_children("Монетка_*", "Area3D", true, false).size() == 5, "В предместье должны появляться короткие цепочки из пяти монет"):
		return
	if not _require(castle.find_children("Монетка_*", "Area3D", true, false).size() == 5 and graveyard.find_children("Монетка_*", "Area3D", true, false).size() == 5, "Монетные цепочки должны работать в замковых и кладбищенских зонах"):
		return
	var sample_coin := town.find_child("Монетка_00", true, false) as Area3D
	if not _require(sample_coin != null and sample_coin.find_child("Model", true, false) != null and sample_coin.find_child("CollisionShape3D", true, false) is CollisionShape3D, "Монетка должна использовать GLB-модель Blockbench и область подбора"):
		return
	var coin_model := sample_coin.get_node("Model") as Node3D
	var coin_collision := sample_coin.get_node("CollisionShape3D") as CollisionShape3D
	if not _require(coin_model.scale.x >= 3.1 and coin_collision.shape is SphereShape3D and (coin_collision.shape as SphereShape3D).radius >= 2.0, "Монетка должна быть хорошо видна, а область подбора — прощать небольшое отклонение совы"):
		return
	if not _require(starting_chunk.find_child("СтартоваяБашня_00", true, false) != null and starting_chunk.find_child("СтартоваяБашня_01", true, false) != null, "У начала игрового маршрута должны стоять две башни"):
		return
	if not _require(town.find_child("ПридорожнаяБашня_00", true, false) != null, "Башни должны регулярно появляться по бокам игрового маршрута"):
		return
	if not _require(town.find_child("GothicWeepingTree", true, false) != null, "В мире должно встречаться плакучее дерево Blockbench"):
		return
	if not _require(town.find_child("GothicBlossomTree", true, false) != null, "В мире должно встречаться цветущее готическое дерево Blockbench"):
		return
	if not _require(town.find_child("GothicCrystalTree", true, false) != null, "В мире должно встречаться кристальное дерево Blockbench"):
		return
	if not _require(town.find_child("ШирокаяЗемля", true, false) != null and town.find_child("ДальнийБерег", true, false) != null, "Окружение должно заполнять широкие боковые зоны"):
		return
	var wide_ground := town.find_child("ШирокаяЗемля", true, false) as MeshInstance3D
	if not _require((wide_ground.mesh as BoxMesh).size.x >= 140.0, "Земля должна продолжаться далеко за ближними рядами деревьев"):
		return
	if not _require(town.find_children("ДальнийГоризонт_*", "Node3D", true, false).size() == 2 and graveyard.find_children("ДальнийГоризонт_*", "Node3D", true, false).size() == 2, "Предместье и кладбище должны иметь третий и четвёртый планы окружения"):
		return
	if not _require(town.find_children("ВнешнийТуман_*", "FogVolume", true, false).size() == 2 and graveyard.find_children("ВнешнийТуман_*", "FogVolume", true, false).size() == 2, "Дальние края внешних зон должны растворяться в тумане"):
		return
	if not _require(town.find_children("ДальнийОгонь_*", "OmniLight3D", true, false).size() >= 4 and graveyard.find_children("ДальнийОгонь_*", "OmniLight3D", true, false).size() >= 4, "В дальнем окружении должны читаться редкие огни"):
		return
	if not _require(town.find_child("CrookedHouse", true, false) != null, "Дома должны использовать детальные GLB-модели"):
		return
	if not _require(town.find_child("RuinedHouseTall", true, false) != null and town.find_child("RuinedHouseArch", true, false) != null and town.find_child("RuinedHouseBurned", true, false) != null, "Стартовое предместье должно использовать три разных разрушенных дома Blockbench"):
		return
	if not _require(town.find_child("КачающийсяФонарь", true, false) != null, "В предместье должны быть уличные фонари"):
		return
	if not _require(town.find_child("ФонарныйСтолб", true, false) != null and town.find_child("КронштейнФонаря", true, false) != null, "Подвесные фонари должны быть закреплены на наземных стойках"):
		return
	if not _require(town.find_child("КаменныйФундамент", true, false) != null, "Дома должны стоять на видимых каменных фундаментах"):
		return
	if not _require(town.find_child("ОснованиеДерева", true, false) != null, "Деревья должны быть соединены с землёй видимыми корнями"):
		return
	if not _require(starting_chunk.find_child("НизкаяКаменнаяОграда", true, false) != null and starting_chunk.find_child("СтартоваяТерраса", true, false) != null, "Первые секунды маршрута должны иметь цельное наземное окружение"):
		return
	if not _require(starting_chunk.find_child("БоковойТуман_0_-1", true, false) is FogVolume and starting_chunk.find_child("БоковойТуман_0_1", true, false) is FogVolume, "По краям стартовой зоны должны быть объёмы тумана"):
		return
	if not _require(starting_chunk.find_children("ОгоньВТумане_*", "OmniLight3D", true, false).size() >= 4, "Туман стартовой зоны должен иметь несколько источников света для глубины"):
		return
	if not _require(town.find_child("ВыступающаяВетка", true, false) != null, "В предместье должны быть смертельные ветки"):
		return
	if not _require(town.find_child("DeadBranch", true, false) != null, "Ветка должна использовать детальную GLB-модель"):
		return
	var branch := town.find_child("ВыступающаяВетка", true, false) as DeadlyObstacle
	var branch_collision := branch.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	if not _require((branch_collision.shape as BoxShape3D).size.y >= 2.3, "Хитбокс ветки должен охватывать видимые сучья"):
		return
	if not _require(town.find_child("StreetLantern", true, false) != null, "Фонарь должен использовать детальную GLB-модель"):
		return
	if not _require(town.find_child("ПламяФонаря", true, false) is GPUParticles3D, "В уличном фонаре должен гореть эффект пламени"):
		return
	if not _require(town.find_child("CarvedPumpkin", true, false) != null, "Тыква должна использовать детальную GLB-модель"):
		return
	var decorative_pumpkin_anchors := town.find_children("ДекоративнаяТыква_*", "Node3D", true, false)
	var decorative_pumpkin_anchor := decorative_pumpkin_anchors[0] as Node3D
	var decorative_pumpkin := decorative_pumpkin_anchor.find_child("CarvedPumpkin", true, false) as Node3D
	var decorative_angles_differ := false
	for pumpkin_node in decorative_pumpkin_anchors:
		var other_pumpkin_anchor := pumpkin_node as Node3D
		if not is_equal_approx(other_pumpkin_anchor.rotation.y, decorative_pumpkin_anchor.rotation.y):
			decorative_angles_differ = true
			break
	if not _require(decorative_pumpkin_anchors.size() == 6 and decorative_pumpkin.scale.x >= 0.8 and decorative_angles_differ, "Декоративные тыквы должны быть вдвое крупнее и иметь разные случайные углы поворота"):
		return
	if not _require(town_with_balcony.find_child("ВыступающийБалкон", true, false) != null, "В предместье должны встречаться выступающие балконы"):
		return
	var lantern := town.find_child("КачающийсяФонарь", true, false) as DeadlyObstacle
	if not _require(lantern.swing_angle != 0.0 and lantern.swing_speed > 0.0, "Уличный фонарь должен качаться"):
		return
	var vampire_fog := town_with_fog.find_child("ОблакоВампирскогоТумана", true, false) as DeadlyObstacle
	if not _require(vampire_fog.drift_distance > 0.0, "Вампирский туман должен двигаться между домами"):
		return
	var vampire_particles := vampire_fog.find_child("КлубящийсяТуман", true, false) as GPUParticles3D
	if not _require(vampire_particles != null and vampire_particles.local_coords, "Вампирский туман должен двигаться вместе с источником без длинного следа"):
		return
	var ground_pumpkin := town_with_pumpkin.find_child("БольшаяТыква", true, false) as DeadlyObstacle
	if not _require(ground_pumpkin != null and ground_pumpkin.fall_distance == 0.0 and ground_pumpkin.position.y <= 0.01 and "ТЫКВУ" in ground_pumpkin.death_reason, "Большая тыква должна неподвижно стоять на земле как препятствие"):
		return
	var pumpkin_collision := ground_pumpkin.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	var expected_road_hitbox := Vector3(6.2, 9.0, 6.0) / 1.5 * 0.75
	if not _require((pumpkin_collision.shape as BoxShape3D).size.is_equal_approx(expected_road_hitbox), "Хитбокс дорожной тыквы должен занимать 75% её нового уменьшенного габарита"):
		return
	var obstacle_pumpkin_model := ground_pumpkin.find_child("CarvedPumpkin", true, false) as Node3D
	if not _require(obstacle_pumpkin_model != null and is_equal_approx(obstacle_pumpkin_model.scale.x, 3.1 / 1.5) and is_equal_approx(absf(obstacle_pumpkin_model.rotation.y), PI), "Дорожная тыква должна стать в 1.5 раза меньше и смотреть вырезанным лицом навстречу сове"):
		return
	var falling_tile := town_with_tiles.find_child("ПадающийПредмет", true, false) as DeadlyObstacle
	if not _require(falling_tile.fall_distance > 0.0 and "ЧЕРЕПИЦА" in falling_tile.death_reason, "С крыш должна падать черепица"):
		return

	if not _require(castle.find_child("Гобелен", true, false) != null, "В замке должны быть гобелены"):
		return
	if not _require(castle.find_child("HallCeiling", true, false) != null, "Замковый маршрут должен иметь видимый потолок и понятную высотную границу"):
		return
	var hall_reflection := castle.find_child("ОтраженияЗамковогоЗала", true, false) as ReflectionProbe
	if not _require(hall_reflection != null and hall_reflection.intensity >= 4.0 and castle.find_child("ЗеркальныйКаменныйПол", true, false) != null, "В замковых залах должны быть сильные локальные отражения и полированный пол"):
		return
	if not _require(castle.find_child("ВинтоваяСтупень_00", true, false) != null, "В замке должна быть винтовая лестница"):
		return
	if not _require(castle.find_child("ЗамковыйМаятник", true, false) != null, "В замке должны быть маятники"):
		return
	if not _require(castle_with_chandelier.find_child("CandleChandelier", true, false) != null, "Люстра должна использовать детальную GLB-модель"):
		return
	if not _require(castle_with_chandelier.find_child("ПламяСвечи_00", true, false) is GPUParticles3D, "У свечей люстры должен быть живой эффект пламени"):
		return
	var torch_flame := castle_with_chandelier.find_child("ПламяФакела", true, false) as GPUParticles3D
	if not _require(torch_flame != null and torch_flame.local_coords, "Пламя факелов должно двигаться вместе со свечой и не оставлять след через весь мир"):
		return
	if not _require(castle_with_gear.find_child("GroundGear", true, false) != null, "Шестерня должна использовать детальную GLB-модель"):
		return
	var chandelier := castle_with_chandelier.find_child("КачающаясяЛюстра", true, false) as DeadlyObstacle
	if not _require(chandelier.swing_angle != 0.0 and chandelier.swing_speed > 0.0, "Замковая люстра должна качаться"):
		return
	var gear := castle_with_gear.find_child("ЕдущаяШестерня", true, false) as DeadlyObstacle
	if not _require(gear.spin_speed != 0.0 and gear.drift_distance > 0.0, "Большая шестерня должна вращаться и ехать по земле"):
		return
	var pendulum := castle.find_child("ЗамковыйМаятник", true, false) as DeadlyObstacle
	if not _require(pendulum.swing_angle != 0.0 and pendulum.swing_speed > 0.0, "Замковый маятник должен качаться"):
		return

	if not _require(graveyard.find_child("Надгробие", true, false) != null, "На кладбище должны быть надгробия"):
		return
	if not _require(graveyard.find_child("СтарыйСклеп", true, false) != null, "На кладбище должны быть склепы"):
		return
	if not _require(graveyard.find_child("GraveyardCrypt", true, false) != null, "Склепы должны использовать детальные GLB-модели"):
		return
	if not _require(graveyard.find_child("GothicGravestone", true, false) != null, "Надгробия должны использовать детальные GLB-модели"):
		return
	if not _require(graveyard.find_child("СухоеДерево", true, false) != null, "На кладбище должны быть сухие деревья"):
		return
	if not _require(graveyard.find_child("ОблакоВампирскогоТумана", true, false) != null, "На кладбище должен быть опасный туман"):
		return
	if not _require(graveyard.find_child("КлубящийсяТуман", true, false) != null, "Вампирский туман должен иметь движущийся объёмный эффект"):
		return
	if not _require(town_with_flock.find_child("VampireBat", true, false) != null, "Стая должна использовать детальные GLB-модели летучих мышей"):
		return
	var bat_flock := town_with_flock.find_child("СтаяЛетучихМышей", true, false) as DeadlyObstacle
	if not _require(bat_flock.animate_flock and bat_flock.drift_distance > 0.0, "Летучие мыши должны двигаться стаей и покачиваться по отдельности"):
		return
	if not _require(town_with_crows.find_child("СтаяВоронов", true, false) != null, "В предместье должны встречаться стаи воронов"):
		return
	if not _require(town_with_crows.find_child("RavenCrow", true, false) != null, "Вороны должны использовать отдельную детальную GLB-модель"):
		return
	var crow_flock := town_with_crows.find_child("СтаяВоронов", true, false) as DeadlyObstacle
	if not _require(crow_flock.animate_flock and crow_flock.drift_distance > 0.0, "Вороны должны двигаться стаей и покачиваться по отдельности"):
		return
	if not _require(graveyard_with_hand.find_child("GraveHand", true, false) != null, "Рука из могилы должна использовать детальную GLB-модель"):
		return
	if not _require(graveyard_variant.find_child("ЛетящиеДуши", true, false) == null, "Беспокойные синие души должны быть полностью убраны из игры"):
		return
	if not _require(graveyard_with_pit.find_child("ПровалВЗемле", true, false) is DeadlyObstacle, "На кладбище должны встречаться смертельные провалы"):
		return

	var hazard_count := 0
	var inspected_chunks := [town, town_with_pumpkin, town_with_flock, town_with_fog, town_with_tiles, town_with_crows, town_with_balcony, castle, castle_with_chandelier, castle_with_gear, graveyard, graveyard_variant, graveyard_with_hand, graveyard_with_pit]
	for node in _all_descendants_of_many(inspected_chunks):
		if node is DeadlyObstacle:
			hazard_count += 1
			if not _require(node.find_children("*", "CollisionShape3D", true, false).size() > 0, "У каждого смертельного препятствия должна быть физическая коллизия"):
				return
	if not _require(hazard_count >= 20, "В трёх зонах должно быть достаточно смертельных препятствий"):
		return
	print("ZONE_CONTENT_OK town=houses castle=stairs graveyard=crypts hazards=%d" % hazard_count)
	quit(0)

func _all_descendants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		result.append(child)
		result.append_array(_all_descendants(child))
	return result

func _all_descendants_of_many(parents: Array) -> Array[Node]:
	var result: Array[Node] = []
	for parent in parents:
		result.append_array(_all_descendants(parent))
	return result

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("ZONE_CONTENT_FAILED: " + message)
	quit(1)
	return false
