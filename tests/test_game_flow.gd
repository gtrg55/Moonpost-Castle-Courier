extends SceneTree

class FlightProbe:
	extends Node

	var owl: OwlController
	var camera: Camera3D
	var enabled := false
	var world_samples: Array[Vector2] = []
	var screen_samples: Array[Vector2] = []
	var frame_deltas: Array[float] = []

	func _ready() -> void:
		process_priority = 100

	func _process(delta: float) -> void:
		if not enabled or not is_instance_valid(owl) or not is_instance_valid(camera):
			return
		var world_position := owl.presentation_anchor.global_position
		world_samples.append(Vector2(world_position.x, world_position.y))
		screen_samples.append(_project_manually(world_position))
		frame_deltas.append(delta)

	func _project_manually(world_position: Vector3) -> Vector2:
		var camera_space := camera.global_transform.affine_inverse() * world_position
		var viewport_size := Vector2(camera.get_viewport().get_visible_rect().size)
		var focal_length := viewport_size.y * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
		var safe_depth := maxf(-camera_space.z, 0.001)
		return Vector2(
			viewport_size.x * 0.5 + camera_space.x * focal_length / safe_depth,
			viewport_size.y * 0.5 - camera_space.y * focal_length / safe_depth
		)

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
	print("GAME_FLOW_CHECKPOINT scene_ready")

	var owl := main.get_node("CourierOwl") as OwlController
	var flow := main.get_node("GameFlow") as GameFlowUI
	var hud := main.get_node("HUD") as CanvasLayer
	var menu_stage := main.get_node("MenuStage") as Node3D
	var flight_camera := main.get_node("FlightCamera") as FlightCamera
	var streamer := main.get_node("ProceduralWorldStreamer") as WorldStreamer
	var music := main.get_node("MusicController") as MusicController
	if not _require(InputMap.has_action("pause_game") and _action_has_key("pause_game", KEY_ESCAPE), "ESC должен быть назначен на меню паузы"):
		return
	if not _require(_action_has_joypad_button("pause_game") and _action_has_joypad_motion("move_left") and _action_has_joypad_motion("move_right") and _action_has_joypad_motion("move_up") and _action_has_joypad_motion("move_down"), "Геймпад должен управлять полётом левым стиком и открывать паузу кнопкой START"):
		return
	if not _require(flow.process_mode == Node.PROCESS_MODE_ALWAYS and flow.get_node("PauseMenu/Card/ResumeButton") is Button and flow.get_node("PauseMenu/Card/SettingsButton") is Button and flow.get_node("PauseMenu/Card/RestartButton") is Button and flow.get_node("PauseMenu/Card/MenuButton") is Button, "Меню паузы и его настройки должны работать при остановленном дереве сцены"):
		return
	if not _require(music != null and music.menu_stream != null and music.game_stream != null and music.menu_player.stream == music.menu_stream and music.game_player.stream == music.game_stream, "Контроллер должен загрузить отдельную музыку главного меню и игры"):
		return
	if not _require((music.menu_stream as AudioStreamMP3).loop and (music.game_stream as AudioStreamMP3).loop, "Обе музыкальные композиции должны воспроизводиться по кругу"):
		return
	var music_slider := flow.get_node("SettingsPanel/Card/MusicSlider") as HSlider
	if not _require(music_slider != null and music_slider.min_value == 0.0 and music_slider.max_value == 10.0 and music_slider.step == 1.0 and music_slider.tick_count == 11, "Громкость музыки должна регулироваться десятью шагами"):
		return
	if not _require(Engine.max_fps == 60 and ProjectSettings.get_setting("application/run/max_fps") == 60, "Игра должна иметь верхний предел 60 кадров в секунду"):
		return
	if not _require(ProjectSettings.get_setting("physics/common/physics_interpolation") == true and owl.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "Падение физического корпуса должно интерполироваться между физическими кадрами"):
		return
	if not _require(owl.presentation_anchor.top_level and owl.presentation_anchor.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Визуальная сова должна двигаться независимо на render-clock"):
		return
	if not _require(owl.mouse_resample_window > 0.0 and owl.get_presentation_transform() == owl.presentation_anchor.global_transform, "Камера и модель должны получать одну render-позу нового аркадного контроллера"):
		return
	if not _require(owl.collision_layer == 1 and owl.collision_mask == 0 and owl.process_priority < flight_camera.process_priority and flight_camera.process_priority < main.process_priority, "Коллизии не должны выталкивать сову, а модель, камера и небо должны обновляться в строгом порядке"):
		return
	if not _require(hud.get_node("FPSLabel") is Label, "Справа сверху должен быть честный счётчик FPS"):
		return
	if not _require(hud.get_node("CoinLabel") is Label, "HUD должен иметь отдельный счётчик собранных монет"):
		return
	var coin_label := hud.get_node("CoinLabel") as Label
	if not _require(not hud.has_node("ObjectiveLabel") and coin_label.anchor_left == 0.5 and coin_label.anchor_top == 1.0 and coin_label.offset_bottom <= -70.0, "Слева не должно быть строки «Лунная почта», а монеты должны находиться снизу по центру"):
		return
	if not _require(not flow.get_node("MainMenu").has_node("Subtitle") and not flow.get_node("MainMenu").has_node("Tagline"), "Под заголовком не должно быть удалённых рекламных строк"):
		return
	if not _require(flow.is_main_menu_visible(), "При запуске должно быть открыто главное меню"):
		return
	if not _require(music.is_menu_music_active() and music.menu_player.playing and not music.game_player.playing, "В главном меню должна сразу играть музыка меню"):
		return
	if not _require(not owl.flight_enabled, "В главном меню управление совой должно быть выключено"):
		return
	if not _require(menu_stage.visible and flight_camera.menu_view, "Главное меню должно показывать отдельную кинематографичную сцену"):
		return
	if not _require(owl.left_wing.rotation.z > 1.1 and owl.right_wing.rotation.z < -1.1 and owl.left_wing.position.y > 0.25, "В меню крылья совы должны быть подняты и сложены вдоль туловища"):
		return
	if not _require(is_equal_approx(owl.visual_root.rotation.y, deg_to_rad(-30.0)), "В меню сова должна быть повёрнута к зрителю на 30 градусов"):
		return
	await create_timer(0.18).timeout
	if not _require(absf(owl.left_wing.rotation.z - 1.18) < 0.03 and absf(owl.right_wing.rotation.z + 1.18) < 0.03, "Сидящая сова должна держать крылья спокойно сложенными"):
		return
	if not _require(flow.get_node("MainMenu/Vignette") is ColorRect, "Главное меню должно иметь тёмную виньетку по краям"):
		return
	if not _require(menu_stage.find_child("ВеткаПодСовой", true, false) != null and owl.position.y > 8.5, "В главном меню сова должна сидеть лапами на ветке"):
		return
	if not _require(owl.position.z > 45.0 and owl.position.z < 55.0 and owl.position.x > 8.0, "Дерево с совой должно стоять рядом с первой правой башней моста"):
		return
	if not _require(menu_stage.find_children("СумеречноеДерево_*", "Node3D", true, false).size() >= 12, "Главное меню должно иметь плотное многоярусное окружение из деревьев"):
		return
	if not _require(menu_stage.find_children("ДальняяКолонна_*", "Node3D", true, false).size() >= 6, "Вдали должны читаться увеличенные руины и колонны"):
		return
	if not _require(menu_stage.find_child("ЛетающееПисьмо_00", true, false) != null, "В меню должны летать письма"):
		return
	if not _require(menu_stage.find_child("ИскрыЛуннойПочты", true, false) is GPUParticles3D, "Вокруг писем должны быть светящиеся искры"):
		return
	var hot_ash := menu_stage.find_child("ГорячийПепел", true, false) as GPUParticles3D
	if not _require(hot_ash != null and hot_ash.amount >= 450, "Главный экран должен иметь плотный слой горячего пепла"):
		return
	var sky_layers := main.find_child("НебесныеСлои", true, false) as Node3D
	if not _require(sky_layers != null and sky_layers.get_parent() == main and sky_layers.find_child("ТуманнаяЛуна", true, false) != null, "Небо должно быть отделено от вращения камеры и иметь туманную луну"):
		return
	if not _require(menu_stage.find_child("ЗамковаяПоляна", true, false) != null, "Замок должен стоять на отдельном парящем острове"):
		return
	if not _require(menu_stage.find_child("ТуманНадПропастью", true, false) is FogVolume, "Под островом должен быть локальный объёмный туман"):
		return
	if not _require(menu_stage.find_child("ВерхняяДымкаПропасти", true, false) is FogVolume, "Башни должны растворяться в верхнем слое тумана"):
		return
	if not _require(menu_stage.find_child("БашняВТумане_00", true, false) != null, "За замком должны быть дальние башни Blockbench"):
		return
	if not _require(menu_stage.find_child("БлижняяБашня_00", true, false) != null and menu_stage.find_child("БлижняяБашня_01", true, false) != null, "Начало дороги должны обрамлять ближние башни"):
		return
	if not _require(menu_stage.find_child("ДальниеОблака", true, false) is MeshInstance3D, "В небе должен быть процедурный слой облаков"):
		return
	if not _require(menu_stage.find_child("СумеречноеДерево_00", true, false) != null, "На острове должны быть деревья Blockbench"):
		return
	if not _require(menu_stage.find_child("ДорожнаяЖаровня_00", true, false) != null, "Вдоль дороги должны стоять жаровни Blockbench"):
		return
	if not _require(menu_stage.find_child("СветЖаровни_00", true, false) is OmniLight3D, "Жаровни должны освещать дорогу"):
		return
	print("GAME_FLOW_CHECKPOINT menu_ok")

	var settings_button := flow.get_node("MainMenu/MenuButtons/SettingsButton") as Button
	var original_music_step := music.volume_step
	var menu_playback_before_settings := music.menu_player.get_playback_position()
	settings_button.pressed.emit()
	await create_timer(0.28).timeout
	if not _require(flow.is_settings_visible(), "Кнопка настроек должна открывать общий экран громкости"):
		return
	if not _require(music.settings_ducked and music.is_menu_music_active() and music.menu_player.playing and music.menu_player.get_playback_position() > menu_playback_before_settings, "Настройки из главного меню должны приглушать продолжающуюся музыку меню, не перезапуская её"):
		return
	if not _require(absf(music.menu_player.volume_db - music.get_target_volume_db()) < 0.2, "При открытых настройках музыка меню должна дойти до приглушённой громкости"):
		return
	var alternate_music_step := 7 if original_music_step != 7 else 6
	music_slider.value = alternate_music_step
	await create_timer(0.16).timeout
	if not _require(music.volume_step == alternate_music_step and flow.get_node("SettingsPanel/Card/MusicValue").text == "%d / 10" % alternate_music_step, "Слайдер должен сразу менять музыку и показывать выбранный шаг"):
		return
	music_slider.value = original_music_step
	await create_timer(0.16).timeout
	if not _require(music.volume_step == original_music_step, "После проверки должна восстанавливаться исходная громкость"):
		return
	var back_button := flow.get_node("SettingsPanel/Card/BackButton") as Button
	back_button.pressed.emit()
	await create_timer(0.28).timeout
	if not _require(flow.is_main_menu_visible() and not flow.is_settings_visible(), "Из настроек должен работать возврат в главное меню"):
		return
	if not _require(not music.settings_ducked and music.is_menu_music_active() and absf(music.menu_player.volume_db - music.get_target_volume_db()) < 0.2, "После возврата музыка меню должна плавно восстановить громкость"):
		return

	var pristine_start_chunk_id := (streamer.active_chunks[0] as Node3D).get_instance_id()
	var start_button := flow.get_node("MainMenu/MenuButtons/StartButton") as Button
	start_button.pressed.emit()
	await create_timer(0.78).timeout
	if not _require(owl.alive and owl.flight_enabled, "Кнопка старта должна запускать управляемый полёт"):
		return
	if not _require(music.is_game_music_active() and music.game_player.playing and not music.menu_player.playing, "После старта музыка меню должна плавно смениться внутриигровой"):
		return
	if not _require(hud.visible and not flow.visible, "Во время полёта должен отображаться HUD"):
		return
	if not _require(not menu_stage.visible and not flight_camera.menu_view, "При старте меню-сцена должна скрываться"):
		return
	if not _require((streamer.active_chunks[0] as Node3D).get_instance_id() == pristine_start_chunk_id, "Первый старт не должен синхронно пересобирать уже готовые сотни узлов мира"):
		return
	if not _require(coin_label.modulate.a <= 0.01, "Счётчик монет должен быть скрыт, пока монеты недавно не собирались"):
		return
	var pause_event := InputEventAction.new()
	pause_event.action = "pause_game"
	pause_event.pressed = true
	Input.parse_input_event(pause_event)
	await process_frame
	if not _require(paused and flow.is_pause_menu_visible() and main.game_state == main.GameState.PAUSED and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "ESC или START должны останавливать игру и открывать меню паузы"):
		return
	var pause_settings_button := flow.get_node("PauseMenu/Card/SettingsButton") as Button
	var game_playback_before_settings := music.game_player.get_playback_position()
	pause_settings_button.pressed.emit()
	await create_timer(0.28).timeout
	if not _require(flow.is_settings_visible() and paused and music.settings_ducked, "Настройки из паузы должны оставлять игру остановленной и приглушать музыку"):
		return
	if not _require(music.is_game_music_active() and music.game_player.playing and music.game_player.get_playback_position() > game_playback_before_settings and not music.menu_player.playing, "Настройки из игры должны продолжать именно внутриигровую музыку, не включая музыку меню"):
		return
	back_button.pressed.emit()
	await create_timer(0.28).timeout
	if not _require(flow.is_pause_menu_visible() and not flow.is_settings_visible() and not music.settings_ducked and absf(music.game_player.volume_db - music.get_target_volume_db()) < 0.2, "Возврат из настроек игры должен восстановить меню паузы и громкость игровой музыки"):
		return
	var resume_button := flow.get_node("PauseMenu/Card/ResumeButton") as Button
	resume_button.pressed.emit()
	await process_frame
	if not _require(not paused and not flow.is_pause_menu_visible() and main.game_state == main.GameState.PLAYING, "Кнопка «Продолжить» должна возвращать в полёт"):
		return
	pause_event.pressed = false
	Input.parse_input_event(pause_event)
	var flight_probe := FlightProbe.new()
	flight_probe.owl = owl
	flight_probe.camera = flight_camera
	main.add_child(flight_probe)
	flight_probe.enabled = true
	var right_event := InputEventAction.new()
	right_event.action = "move_right"
	right_event.pressed = true
	Input.parse_input_event(right_event)
	for _lateral_frame in range(18):
		await process_frame
	# The held-input trajectory ends here. Do not include the intentional
	# one-frame stop below in the high-frequency steering measurement.
	flight_probe.enabled = false
	right_event.pressed = false
	Input.parse_input_event(right_event)
	await process_frame
	if not _require(flight_probe.world_samples.size() >= 12 and flight_probe.screen_samples.size() == flight_probe.world_samples.size(), "Проверка должна снять реальную render-траекторию после совы, камеры и неба"):
		return
	var minimum_world_velocity := INF
	var maximum_world_velocity := -INF
	var maximum_screen_residual := 0.0
	var screen_velocities: Array[float] = []
	# Skip the first render sample while the camera enters the gameplay pose;
	# all measured steps after it belong to the same continuously held input.
	for sample_index in range(2, flight_probe.world_samples.size() - 1):
		var frame_delta := maxf(flight_probe.frame_deltas[sample_index], 0.000001)
		var world_velocity := (flight_probe.world_samples[sample_index].x - flight_probe.world_samples[sample_index - 1].x) / frame_delta
		minimum_world_velocity = minf(minimum_world_velocity, world_velocity)
		maximum_world_velocity = maxf(maximum_world_velocity, world_velocity)
		var previous_screen_step := flight_probe.screen_samples[sample_index].x - flight_probe.screen_samples[sample_index - 1].x
		var next_screen_step := flight_probe.screen_samples[sample_index + 1].x - flight_probe.screen_samples[sample_index].x
		var previous_screen_velocity := previous_screen_step / frame_delta
		var next_screen_velocity := next_screen_step / maxf(flight_probe.frame_deltas[sample_index + 1], 0.000001)
		if screen_velocities.is_empty():
			screen_velocities.append(previous_screen_velocity)
		screen_velocities.append(next_screen_velocity)
	for velocity_index in range(2, screen_velocities.size()):
		var previous_change := screen_velocities[velocity_index - 1] - screen_velocities[velocity_index - 2]
		var next_change := screen_velocities[velocity_index] - screen_velocities[velocity_index - 1]
		if previous_change * next_change < 0.0:
			maximum_screen_residual = maxf(maximum_screen_residual, minf(absf(previous_change), absf(next_change)))
	if not _require(minimum_world_velocity >= owl.keyboard_position_speed - 0.15 and maximum_world_velocity <= owl.keyboard_position_speed + 0.15, "Реальный X/Y controller должен выдавать постоянную скорость без чередования коротких и длинных шагов"):
		return
	if not _require(maximum_screen_residual <= 2.0, "Экранная траектория совы вместе с камерой не должна иметь чередующихся высокочастотных рывков (импульс %.3f px/s)" % maximum_screen_residual):
		return
	var stopped_position := owl.plane_position
	await process_frame
	if not _require(owl.plane_position.distance_to(stopped_position) < 0.001 and owl.plane_velocity.is_zero_approx(), "После отпускания клавиши сова должна останавливаться сразу, без остаточного желейного движения"):
		return
	var fixed_flight_z := owl.global_position.z
	var initial_world_z := streamer.position.z
	var maximum_longitudinal_error := 0.0
	for _frame_index in range(12):
		await physics_frame
		maximum_longitudinal_error = maxf(maximum_longitudinal_error, flight_camera.get_longitudinal_follow_error())
	if not _require(is_equal_approx(owl.global_position.z, fixed_flight_z) and streamer.position.z > initial_world_z, "При полёте сова должна оставаться на фиксированной глубине, а мир — непрерывно двигаться ей навстречу"):
		return
	if not _require(maximum_longitudinal_error < 0.001, "Камера не должна догонять сову по направлению полёта и создавать продольные рывки"):
		return
	var test_coin := streamer.active_chunks[2].find_child("Монетка_00", true, false) as Area3D
	if not _require(test_coin != null, "После старта в мире должна быть доступна цепочка монет"):
		return
	test_coin.call("_on_body_entered", owl)
	await process_frame
	if not _require(owl.collected_coins == 1 and coin_label.text == "МОНЕТЫ  1" and coin_label.get_theme_font_size("font_size") == 36 and coin_label.modulate.a >= 0.99, "Подбор монеты должен показать обычное число без ведущих нулей шрифтом на 20% крупнее"):
		return
	await create_timer(0.12).timeout
	if not _require(coin_label.scale.x > 1.0, "При подборе монеты число должно мягко увеличиваться короткой pop-анимацией"):
		return
	streamer.set_streaming_enabled(false)
	await create_timer(2.45).timeout
	if not _require(coin_label.modulate.a <= 0.05 and is_equal_approx(coin_label.scale.x, 1.0), "Через две секунды без новых монет счётчик должен плавно исчезнуть"):
		return
	streamer.set_streaming_enabled(true)
	main.call("_on_zone_changed", "ЗАМКОВЫЕ ЗАЛЫ")
	var delivery_message := hud.get_node("MessageLabel") as Label
	if not _require(main.deliveries == 1 and delivery_message.text == "ПИСЬМО ДОСТАВЛЕНО" and delivery_message.anchor_top == 0.0 and delivery_message.offset_bottom <= 100.0, "Каждая смена локации должна доставлять одно письмо и показывать короткое сообщение сверху"):
		return
	print("GAME_FLOW_CHECKPOINT start_ok")

	var hazard := DeadlyObstacle.new()
	hazard.death_reason = "ПРОВЕРОЧНОЕ СТОЛКНОВЕНИЕ"
	hazard.position = owl.position
	var hazard_collision := CollisionShape3D.new()
	var hazard_shape := SphereShape3D.new()
	hazard_shape.radius = 1.2
	hazard_collision.shape = hazard_shape
	hazard.add_child(hazard_collision)
	main.add_child(hazard)
	var death_start_y := owl.global_position.y
	await physics_frame
	await physics_frame
	if not _require(not owl.alive, "Смертельное препятствие должно мгновенно убить сову"):
		return
	if not _require(owl.velocity.y < 0.0, "После столкновения сова должна начать падать"):
		return
	owl._death_fall(0.1)
	if not _require(owl.velocity.y < -2.5, "При падении на сову должна действовать гравитация"):
		return
	if not _require(owl.global_position.y < death_start_y or owl.visual_root.rotation.length() > 0.0, "Падение должно быть видно по движению или вращению совы"):
		return
	print("GAME_FLOW_CHECKPOINT death_ok")
	await create_timer(1.25).timeout
	print("GAME_FLOW_CHECKPOINT timer_ok")
	if not _require(owl.global_position.y >= owl.death_ground_height - 0.01 and owl.velocity.is_zero_approx(), "После смерти сова должна останавливаться на дороге, а не проваливаться под мир"):
		return
	if not _require(flow.is_game_over_visible(), "После падения должен появиться экран окончания игры"):
		return
	if not _require(flow.reason_label.text == "ПРОВЕРОЧНОЕ СТОЛКНОВЕНИЕ", "Экран должен показывать причину смерти"):
		return

	hazard.queue_free()
	await process_frame
	var restart_button := flow.get_node("GameOver/Card/RestartButton") as Button
	restart_button.pressed.emit()
	if not _require(owl.total_distance < 0.01, "Новый забег должен сразу сбрасывать дистанцию"):
		return
	if not _require(owl.collected_coins == 0 and coin_label.text == "МОНЕТЫ  0" and coin_label.modulate.a <= 0.01, "Новый забег должен сбрасывать и скрывать счётчик монет"):
		return
	await process_frame
	if not _require(owl.alive and owl.flight_enabled, "Кнопка «Начать снова» должна запускать новый забег"):
		return

	owl.kill("ПРОВЕРКА ВОЗВРАТА В МЕНЮ")
	await create_timer(1.25).timeout
	var menu_button := flow.get_node("GameOver/Card/MenuButton") as Button
	menu_button.pressed.emit()
	await process_frame
	if not _require(flow.is_main_menu_visible(), "Кнопка «В главное меню» должна открывать главное меню"):
		return
	if not _require(not owl.flight_enabled, "В меню управление должно снова отключаться"):
		return
	print("GAME_FLOW_OK menu=start death=instant game_over=visible restart=ok")
	quit(0)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GAME_FLOW_FAILED: " + message)
	quit(1)
	return false

func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false

func _action_has_joypad_button(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return true
	return false

func _action_has_joypad_motion(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return true
	return false
