class_name SelectionTool
extends CanvasTool

# -------------------------------------------------------------------------------------------------
const BRUSH_STROKE = preload("res://BrushStroke/BrushStroke.tscn")
const CANVAS_IMAGE = preload("res://CanvasImage/CanvasImage.tscn")

const MAX_FLOAT := 2147483646.0
const MIN_FLOAT := -2147483646.0
const META_OFFSET := "offset"
const GROUP_SELECTED_ITEMS := "selected_items" # selected items
const GROUP_ITEMS_IN_SELECTION_RECTANGLE := "items_in_selection_rectangle" # items that are in selection rectangle but not commit (i.e. the user is still selecting)
const GROUP_MARKED_FOR_DESELECTION := "items_marked_for_deselection" # items that need to be deslected once LMB is released
const GROUP_COPIED_ITEMS := "items_copied"

# -------------------------------------------------------------------------------------------------
class SelectedItems:
	var images: Array[CanvasImage]
	var strokes: Array[BrushStroke]

# -------------------------------------------------------------------------------------------------
enum State {
	NONE,
	SELECTING,
	MOVING
}

# -------------------------------------------------------------------------------------------------
@export var selection_rectangle_path: NodePath
var _selection_rectangle: SelectionRectangle
var _state := State.NONE
var _selecting_start_pos: Vector2 = Vector2.ZERO
var _selecting_end_pos: Vector2 = Vector2.ZERO
var _multi_selecting: bool
var _mouse_moved_during_pressed := false
var _item_positions_before_move := {} # BrushStroke -> Vector2
var _bounding_box_cache := {} # BrushStroke -> Rect2

# ------------------------------------------------------------------------------------------------
func _ready() -> void:
	super()
	_selection_rectangle = get_node(selection_rectangle_path)
	_cursor.mode = SelectionCursor.Mode.SELECT

# ------------------------------------------------------------------------------------------------
func tool_event(event: InputEvent) -> void:
	var duplicate_pressed := Utils.is_action_pressed("duplicate_items", event)
	var copy_pressed := Utils.is_action_pressed("copy_items", event)
	var paste_pressed := Utils.is_action_pressed("paste_items", event)
	
	if copy_pressed || duplicate_pressed:
		var items := get_selected_items()
		if items.size() > 0:
			Utils.remove_group_from_all_nodes(GROUP_COPIED_ITEMS)
			for item: Node in items:
				item.add_to_group(GROUP_COPIED_ITEMS)
			print("Copied %d strokes" % items.size())
	
	if paste_pressed || duplicate_pressed:
		var items := get_tree().get_nodes_in_group(GROUP_COPIED_ITEMS)
		if !items.is_empty():
			deselect_all_items()
			_cursor.mode = SelectionCursor.Mode.MOVE
			var strokes: Array[BrushStroke]
			var images: Array[CanvasImage]
			for item: Node in items:
				if item is CanvasImage:
					images.append(item as CanvasImage)
				elif item is BrushStroke:
					strokes.append(item as BrushStroke)
			if !strokes.is_empty():
				_paste_strokes(strokes)
			if !images.is_empty():
				_paste_images(images)

	if event is InputEventMouseButton && !disable_stroke:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# LMB down - decide if we should select/multiselect or move the selection
			if event.pressed:
				_selecting_start_pos = _cursor.global_position
				if event.shift_pressed:
					_state = State.SELECTING
					_multi_selecting = true
					_build_bounding_boxes()
				elif get_selected_items().size() == 0:
					_state = State.SELECTING
					_multi_selecting = false
					_build_bounding_boxes()
				else:
					_state = State.MOVING
					_mouse_moved_during_pressed = false
					_offset_selected_items(_cursor.global_position)
					for s: Node in get_selected_items():
						_item_positions_before_move[s] = s.global_position
			# LMB up - stop selection or movement
			else:
				if _state == State.SELECTING:
					_state = State.NONE
					_selection_rectangle.reset()
					_selection_rectangle.queue_redraw()
					_commit_items_under_selection_rectangle()
					_deselect_marked_items()
					if get_selected_items().size() > 0:
						_cursor.mode = SelectionCursor.Mode.MOVE
				elif _state == State.MOVING:
					_state = State.NONE
					if _mouse_moved_during_pressed:
						_add_undoredo_action_for_moved_items()
						_item_positions_before_move.clear()
					else:
						deselect_all_items()
					_mouse_moved_during_pressed = false
						
		# RMB down - just deselect
		elif event.button_index == MOUSE_BUTTON_RIGHT && event.pressed && _state == State.NONE:
			deselect_all_items()
	
	# Mouse movement: move the selection
	elif event is InputEventMouseMotion:
		var event_pos := _cursor.global_position
		if _state == State.SELECTING:
			_selecting_end_pos = event_pos
			compute_selection(_selecting_start_pos, _selecting_end_pos)
			_selection_rectangle.start_position = _selecting_start_pos
			_selection_rectangle.end_position = _selecting_end_pos
			_selection_rectangle.queue_redraw()
		elif _state == State.MOVING:
			_mouse_moved_during_pressed = true
			_move_selected_items()
	
	# Shift click - switch between move/select cursor mode
	elif event is InputEventKey:
		if event.keycode == KEY_SHIFT:
			if event.pressed:
				_cursor.mode = SelectionCursor.Mode.SELECT
			elif get_selected_items().size() > 0:
				_cursor.mode = SelectionCursor.Mode.MOVE

# ------------------------------------------------------------------------------------------------
func compute_selection(start_pos: Vector2, end_pos: Vector2) -> void:
	var selection_rect : Rect2 = Utils.calculate_rect(start_pos, end_pos)
	for image: CanvasImage in _canvas.get_images_in_camera_frustrum():
		var bounding_box: Rect2 = _bounding_box_cache[image]
		if selection_rect.intersects(bounding_box):
			_set_image_selected(image)
	for stroke: BrushStroke in _canvas.get_strokes_in_camera_frustrum():
		var bounding_box: Rect2 = _bounding_box_cache[stroke]
		if selection_rect.intersects(bounding_box):
			for point: Vector2 in stroke.points:
				var abs_point: Vector2 = stroke.position + point
				if selection_rect.has_point(abs_point):
					_set_stroke_selected(stroke)
					break
	_canvas.info.selected_lines = get_selected_strokes().size()

# ------------------------------------------------------------------------------------------------
func _paste_images(images) -> void:
	pass

# ------------------------------------------------------------------------------------------------
func _paste_strokes(strokes: Array) -> void:
	# Calculate offset at center
	var top_left := Vector2(MAX_FLOAT, MAX_FLOAT)
	var bottom_right := Vector2(MIN_FLOAT, MIN_FLOAT)
	
	for stroke: BrushStroke in strokes:
		top_left.x = min(top_left.x, stroke.top_left_pos.x + stroke.position.x)
		top_left.y = min(top_left.y, stroke.top_left_pos.y + stroke.position.y)
		bottom_right.x = max(bottom_right.x, stroke.bottom_right_pos.x + stroke.position.x)
		bottom_right.y = max(bottom_right.y, stroke.bottom_right_pos.y + stroke.position.y)
	var offset := _cursor.global_position - (top_left + (bottom_right - top_left) / 2.0)
	
	# Duplicate the strokes 
	var duplicates := []
	for stroke: BrushStroke in strokes:
		var dup := _duplicate_stroke(stroke, offset)
		dup.add_to_group(GROUP_SELECTED_ITEMS)
		dup.modulate = Config.DEFAULT_SELECTION_COLOR
		duplicates.append(dup)
	
	_canvas.add_strokes(duplicates)
	print("Pasted %d strokes (offset: %s)" % [strokes.size(), offset])

# ------------------------------------------------------------------------------------------------
func _duplicate_stroke(stroke: BrushStroke, offset: Vector2) -> BrushStroke:	
	var dup: BrushStroke = BRUSH_STROKE.instantiate()
	dup.global_position = stroke.global_position
	dup.size = stroke.size
	dup.color = stroke.color
	dup.pressures = stroke.pressures.duplicate()
	for point: Vector2 in stroke.points:
		dup.points.append(point + offset)
	return dup

# ------------------------------------------------------------------------------------------------
func _modify_strokes_colors(strokes: Array[BrushStroke], color: Color) -> void:	
	for stroke: BrushStroke in strokes:
		stroke.color = color

# ------------------------------------------------------------------------------------------------
func _build_bounding_boxes() -> void:
	_bounding_box_cache.clear()
	_bounding_box_cache = Utils.calculte_bounding_boxes(_canvas.get_all_strokes(), _canvas.get_all_images())
	#$"../Viewport/DebugDraw".set_bounding_boxes(_bounding_box_cache.values())
	
# ------------------------------------------------------------------------------------------------
func _set_stroke_selected(stroke: BrushStroke) -> void:
	if stroke.is_in_group(GROUP_SELECTED_ITEMS):
		stroke.modulate = Color.WHITE
		stroke.add_to_group(GROUP_MARKED_FOR_DESELECTION)
	else:
		stroke.modulate = Config.DEFAULT_SELECTION_COLOR
		stroke.add_to_group(GROUP_ITEMS_IN_SELECTION_RECTANGLE)

# ------------------------------------------------------------------------------------------------
# TODO : show selection visually with boxes
func _set_image_selected(image: CanvasImage) -> void:
	if image.is_in_group(GROUP_SELECTED_ITEMS):
		image.modulate = Color.WHITE
		image.add_to_group(GROUP_MARKED_FOR_DESELECTION)
	else:
		image.modulate = Config.DEFAULT_SELECTION_COLOR
		image.add_to_group(GROUP_ITEMS_IN_SELECTION_RECTANGLE)

# ------------------------------------------------------------------------------------------------
func _add_undoredo_action_for_moved_items() -> void:
	var project: Project = ProjectManager.get_active_project()
	project.undo_redo.create_action("Move Items")
	for item: Node in _item_positions_before_move.keys():
		project.undo_redo.add_do_property(item, "global_position", item.global_position)
		project.undo_redo.add_undo_property(item, "global_position", _item_positions_before_move[item])
	project.undo_redo.commit_action()
	project.dirty = true

# -------------------------------------------------------------------------------------------------
func _offset_selected_items(offset: Vector2) -> void:
	for item: Node in get_selected_items():
		item.set_meta(META_OFFSET, item.position - offset)

# -------------------------------------------------------------------------------------------------
func _move_selected_items() -> void:
	for item: Node in get_selected_items():
		item.global_position = item.get_meta(META_OFFSET) + _cursor.global_position

# ------------------------------------------------------------------------------------------------
func _commit_items_under_selection_rectangle() -> void:
	for item: Node2D in get_tree().get_nodes_in_group(GROUP_ITEMS_IN_SELECTION_RECTANGLE):
		item.remove_from_group(GROUP_ITEMS_IN_SELECTION_RECTANGLE)
		item.add_to_group(GROUP_SELECTED_ITEMS)

# ------------------------------------------------------------------------------------------------
func _deselect_marked_items() -> void:
	for item: Node in get_tree().get_nodes_in_group(GROUP_MARKED_FOR_DESELECTION):
		item.remove_from_group(GROUP_MARKED_FOR_DESELECTION)
		item.remove_from_group(GROUP_SELECTED_ITEMS)
		item.modulate = Color.WHITE

# ------------------------------------------------------------------------------------------------
func deselect_all_items() -> void:
	var items: Array = get_selected_items()
	if items.size():
		get_tree().set_group(GROUP_SELECTED_ITEMS, "modulate", Color.WHITE)
		get_tree().set_group(GROUP_ITEMS_IN_SELECTION_RECTANGLE, "modulate", Color.WHITE)
		Utils.remove_group_from_all_nodes(GROUP_SELECTED_ITEMS)
		Utils.remove_group_from_all_nodes(GROUP_MARKED_FOR_DESELECTION)
		Utils.remove_group_from_all_nodes(GROUP_ITEMS_IN_SELECTION_RECTANGLE)
		
	_canvas.info.selected_lines = 0
	_cursor.mode = SelectionCursor.Mode.SELECT

# ------------------------------------------------------------------------------------------------
func is_selecting() -> bool:
	return _state == State.SELECTING

# ------------------------------------------------------------------------------------------------
func get_selected_strokes() -> Array[BrushStroke]:
	var strokes: Array[BrushStroke]
	for stroke in get_tree().get_nodes_in_group(GROUP_SELECTED_ITEMS):
		if stroke is BrushStroke:
			strokes.append(stroke as BrushStroke)
	
	return strokes

# ------------------------------------------------------------------------------------------------
func get_selected_items() -> Array[Node]:
	return get_tree().get_nodes_in_group(GROUP_SELECTED_ITEMS)

# ------------------------------------------------------------------------------------------------
func get_selected_items_separated() -> SelectedItems:
	var selected := SelectedItems.new()
	for item: Node in get_tree().get_nodes_in_group(GROUP_COPIED_ITEMS):
		if item is CanvasImage:
			selected.images.append(item as CanvasImage)
		elif item is BrushStroke:
			selected.strokes.append(item as BrushStroke)
	return selected

# ------------------------------------------------------------------------------------------------
func _on_brush_color_changed(color: Color) -> void:
	var strokes := get_selected_strokes()
	_modify_strokes_colors(strokes, color)

# ------------------------------------------------------------------------------------------------
func reset() -> void:
	_state = State.NONE
	_selection_rectangle.reset()
	_selection_rectangle.queue_redraw()
	_commit_items_under_selection_rectangle()
	deselect_all_items()
