extends Node2D
class_name CanvasImage


# ------------------------------------------------------------------------------------------------

const GROUP_ONSCREEN := "onscreen_image"

# ------------------------------------------------------------------------------------------------

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _visibility_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

# ------------------------------------------------------------------------------------------------
var width: int
var height: int
var _cache_image: Image

# ------------------------------------------------------------------------------------------------
func _ready() -> void:
	if _cache_image != null:
		_sprite.texture = ImageTexture.create_from_image(_cache_image)
		_cache_image = null
	_visibility_notifier.rect = _sprite.get_rect()
	_visibility_notifier.screen_entered.connect(func() -> void: add_to_group(GROUP_ONSCREEN))
	_visibility_notifier.screen_exited.connect(func() -> void: remove_from_group(GROUP_ONSCREEN))

# ------------------------------------------------------------------------------------------------
func get_buffer() -> PackedByteArray:
	return _sprite.texture.get_image().save_png_to_buffer()


# ------------------------------------------------------------------------------------------------
func load_from_buffer(buff: PackedByteArray) -> void:
	var img := Image.new()
	var err := img.load_png_from_buffer(buff)
	if err != OK:
		return
	
	if is_node_ready():
		_sprite.texture = ImageTexture.create_from_image(img)
	else:
		_cache_image = img

# ------------------------------------------------------------------------------------------------
func load_from_image(img: Image) -> void:
	if is_node_ready():
		_sprite.texture = ImageTexture.create_from_image(img)
	else:
		_cache_image = img

# ------------------------------------------------------------------------------------------------
func get_bounding_box() -> Rect2:
	var local_rect: Rect2 = _sprite.get_rect()
	var global_size := local_rect.size * scale
	var global_pos := global_position + (local_rect.position * scale)
	return Rect2(global_pos, global_size).abs()
