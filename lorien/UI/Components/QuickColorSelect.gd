class_name QuickColorSelect
extends HBoxContainer

const PALETTE_BUTTON = preload("res://UI/Components/PaletteButton.tscn")

signal color_changed(color: Color)
signal color_index_changed(index: int)


var _active_palette_button: PaletteButton
var _active_color_index := -1
var _active_palette : Palette

@onready var _color_palette_picker : ColorPalettePicker = get_node("/root/Main/BrushColorPicker")


func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	update_palettes()
	_color_palette_picker.color_index_changed.connect(_activate_palette_button_at_index)

func update_palettes(color_index: int = 0) -> void:
	# Load the active palette
	var active_palette := PaletteManager.get_active_palette()
	_create_buttons(active_palette)
	_activate_palette_button(get_child(color_index), color_index)


func _create_buttons(palette: Palette) -> void:
	# Remove old buttons
	for c in get_children():
		remove_child(c)
		c.queue_free()
	
	# Add new ones
	var index := 0
	for color in palette.colors:
		var button: PaletteButton = PALETTE_BUTTON.instantiate()
		add_child(button)
		button.color = color
		button.pressed.connect(_on_platte_button_pressed.bind(button, index))
		index += 1

func _activate_palette_button(button: PaletteButton, color_index: int) -> void:
	if _active_palette_button != null:
		_active_palette_button.selected = false
	_active_palette_button = button
	_active_color_index = color_index
	_active_palette_button.selected = true

func _on_platte_button_pressed(button: PaletteButton, index: int) -> void:
	_activate_palette_button(button, index)
	color_changed.emit(button.color)
	color_index_changed.emit(index)

func _activate_palette_button_at_index(index: int) -> void:
	var button : PaletteButton = get_child(index)
	_activate_palette_button(button, index)
	
