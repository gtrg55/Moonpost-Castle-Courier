class_name MusicController
extends Node

signal volume_step_changed(step: int)

enum Track { NONE, MENU, GAME }

const SETTINGS_PATH := "user://moonpost_settings.cfg"
const MAX_VOLUME_STEP := 10
const DEFAULT_VOLUME_STEP := 8
const SILENCE_DB := -80.0

@export var menu_stream: AudioStream
@export var game_stream: AudioStream
@export var settings_duck_db := -12.0
@export var crossfade_duration := 0.7

@onready var menu_player: AudioStreamPlayer = $MenuPlayer
@onready var game_player: AudioStreamPlayer = $GamePlayer

var current_track := Track.NONE
var volume_step := DEFAULT_VOLUME_STEP
var settings_ducked := false
var active_player: AudioStreamPlayer
var transition_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_player.stream = menu_stream
	game_player.stream = game_stream
	_enable_loop(menu_stream)
	_enable_loop(game_stream)
	_load_volume_setting()
	menu_player.volume_db = SILENCE_DB
	game_player.volume_db = SILENCE_DB
	volume_step_changed.emit(volume_step)

func play_menu_music() -> void:
	_play_track(Track.MENU, menu_player)

func play_game_music() -> void:
	_play_track(Track.GAME, game_player)

func set_settings_ducked(value: bool) -> void:
	if settings_ducked == value:
		return
	settings_ducked = value
	_tween_active_volume(0.22)

func set_volume_step(value: int, persist := true) -> void:
	var clamped_step := clampi(value, 0, MAX_VOLUME_STEP)
	if volume_step == clamped_step:
		return
	volume_step = clamped_step
	if persist:
		_save_volume_setting()
	volume_step_changed.emit(volume_step)
	_tween_active_volume(0.12)

func get_target_volume_db() -> float:
	var base_db := _volume_step_to_db(volume_step)
	if base_db <= SILENCE_DB:
		return SILENCE_DB
	return maxf(base_db + (settings_duck_db if settings_ducked else 0.0), SILENCE_DB)

func is_menu_music_active() -> bool:
	return current_track == Track.MENU and active_player == menu_player

func is_game_music_active() -> bool:
	return current_track == Track.GAME and active_player == game_player

func _play_track(track: Track, next_player: AudioStreamPlayer) -> void:
	if current_track == track and active_player == next_player:
		if not next_player.playing:
			next_player.play()
		_tween_active_volume(0.18)
		return
	_stop_transition()
	var previous_player := active_player
	current_track = track
	active_player = next_player
	next_player.volume_db = SILENCE_DB
	if not next_player.playing:
		next_player.play()
	transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	transition_tween.tween_property(next_player, "volume_db", get_target_volume_db(), crossfade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(previous_player) and previous_player != next_player:
		transition_tween.tween_property(previous_player, "volume_db", SILENCE_DB, crossfade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		transition_tween.chain().tween_callback(func() -> void:
			if is_instance_valid(previous_player) and previous_player != active_player:
				previous_player.stop()
		)

func _tween_active_volume(duration: float) -> void:
	if not is_instance_valid(active_player):
		return
	_stop_transition()
	transition_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	transition_tween.tween_property(active_player, "volume_db", get_target_volume_db(), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _stop_transition() -> void:
	if transition_tween and transition_tween.is_valid():
		transition_tween.kill()

func _volume_step_to_db(step: int) -> float:
	if step <= 0:
		return SILENCE_DB
	return lerpf(-36.0, 0.0, float(step - 1) / float(MAX_VOLUME_STEP - 1))

func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

func _load_volume_setting() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume_step = clampi(int(config.get_value("audio", "music_volume", DEFAULT_VOLUME_STEP)), 0, MAX_VOLUME_STEP)

func _save_volume_setting() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "music_volume", volume_step)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Не удалось сохранить громкость музыки: %s" % error_string(error))
