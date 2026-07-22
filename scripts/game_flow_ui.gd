class_name GameFlowUI
extends CanvasLayer

signal start_requested
signal restart_requested
signal menu_requested
signal quit_requested
signal pause_toggled
signal resume_requested
signal settings_visibility_changed(is_open: bool)
signal music_volume_changed(step: int)

enum SettingsOrigin { NONE, MAIN_MENU, PAUSE_MENU }

@onready var main_menu: Control = $MainMenu
@onready var menu_buttons: Control = $MainMenu/MenuButtons
@onready var pause_menu: Control = $PauseMenu
@onready var pause_card: Control = $PauseMenu/Card
@onready var game_over: Control = $GameOver
@onready var settings_panel: Control = $SettingsPanel
@onready var music_slider: HSlider = $SettingsPanel/Card/MusicSlider
@onready var music_value_label: Label = $SettingsPanel/Card/MusicValue
@onready var reason_label: Label = $GameOver/Card/ReasonLabel
@onready var result_label: Label = $GameOver/Card/ResultLabel

var settings_origin := SettingsOrigin.NONE

func _ready() -> void:
	$MainMenu/MenuButtons/StartButton.pressed.connect(start_requested.emit)
	$MainMenu/MenuButtons/SettingsButton.pressed.connect(_show_settings_from_main)
	$MainMenu/MenuButtons/QuitButton.pressed.connect(quit_requested.emit)
	$PauseMenu/Card/ResumeButton.pressed.connect(resume_requested.emit)
	$PauseMenu/Card/SettingsButton.pressed.connect(_show_settings_from_pause)
	$PauseMenu/Card/RestartButton.pressed.connect(restart_requested.emit)
	$PauseMenu/Card/MenuButton.pressed.connect(menu_requested.emit)
	$GameOver/Card/RestartButton.pressed.connect(restart_requested.emit)
	$GameOver/Card/MenuButton.pressed.connect(menu_requested.emit)
	$SettingsPanel/Card/BackButton.pressed.connect(_close_settings)
	music_slider.value_changed.connect(_on_music_slider_changed)
	set_music_volume_step(roundi(music_slider.value))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		if settings_panel.visible:
			_close_settings()
		else:
			pause_toggled.emit()
		get_viewport().set_input_as_handled()

func show_main_menu() -> void:
	show()
	_hide_settings_panel()
	main_menu.show()
	menu_buttons.show()
	pause_menu.hide()
	pause_card.show()
	game_over.hide()
	$MainMenu/MenuButtons/StartButton.grab_focus()

func show_game_over(reason: String, distance: float, deliveries: int) -> void:
	show()
	_hide_settings_panel()
	main_menu.hide()
	pause_menu.hide()
	pause_card.show()
	game_over.show()
	reason_label.text = reason
	result_label.text = "ПРОЙДЕНО  %.1f КМ    ПИСЕМ  %d" % [distance / 1000.0, deliveries]
	$GameOver/Card/RestartButton.grab_focus()

func hide_all() -> void:
	_hide_settings_panel()
	main_menu.hide()
	pause_menu.hide()
	pause_card.show()
	game_over.hide()
	hide()

func show_pause_menu() -> void:
	show()
	_hide_settings_panel()
	main_menu.hide()
	game_over.hide()
	pause_menu.show()
	pause_card.show()
	$PauseMenu/Card/ResumeButton.grab_focus()

func hide_pause_menu() -> void:
	_hide_settings_panel()
	pause_menu.hide()
	pause_card.show()
	hide()

func is_main_menu_visible() -> bool:
	return visible and main_menu.visible

func is_game_over_visible() -> bool:
	return visible and game_over.visible

func is_pause_menu_visible() -> bool:
	return visible and pause_menu.visible

func is_settings_stub_visible() -> bool:
	return is_settings_visible()

func is_settings_visible() -> bool:
	return visible and settings_panel.visible

func set_music_volume_step(step: int) -> void:
	var clamped_step := clampi(step, 0, 10)
	music_slider.set_value_no_signal(clamped_step)
	music_value_label.text = "%d / 10" % clamped_step

func _show_settings_from_main() -> void:
	settings_origin = SettingsOrigin.MAIN_MENU
	menu_buttons.hide()
	_show_settings_panel()

func _show_settings_from_pause() -> void:
	settings_origin = SettingsOrigin.PAUSE_MENU
	pause_card.hide()
	_show_settings_panel()

func _show_settings_panel() -> void:
	settings_panel.show()
	settings_visibility_changed.emit(true)
	music_slider.grab_focus()

func _close_settings() -> void:
	if not settings_panel.visible:
		return
	settings_panel.hide()
	settings_visibility_changed.emit(false)
	if settings_origin == SettingsOrigin.MAIN_MENU:
		menu_buttons.show()
		$MainMenu/MenuButtons/SettingsButton.grab_focus()
	elif settings_origin == SettingsOrigin.PAUSE_MENU:
		pause_card.show()
		$PauseMenu/Card/SettingsButton.grab_focus()
	settings_origin = SettingsOrigin.NONE

func _hide_settings_panel() -> void:
	if settings_panel.visible:
		settings_panel.hide()
		settings_visibility_changed.emit(false)
	settings_origin = SettingsOrigin.NONE

func _on_music_slider_changed(value: float) -> void:
	var step := roundi(value)
	set_music_volume_step(step)
	music_volume_changed.emit(step)
