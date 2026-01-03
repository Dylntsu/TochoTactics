extends CanvasLayer

# ==============================================================================
# CONFIGURACION DE ARCHIVOS
# ==============================================================================
const SAVE_DIR = "user://plays/"

# ==============================================================================
# DEPENDENCIAS Y ESTADO
# ==============================================================================
@export var editor: Node2D 

@onready var plays_grid: GridContainer = %PlaysGrid
@onready var btn_new: Button = %BtnNew
@onready var btn_save: Button = %BtnSave
@onready var save_popup: AcceptDialog = %SavePlayPopup
@onready var name_input: LineEdit = %PlayNameInput

# memoria temporal para el proceso de guardado
var _pending_play: Resource = null
# lista de jugadas en memoria
var saved_plays: Array[Resource] = []
# variable para saber que jugada queremos borrar 
var _selected_play: Resource = null

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	# asegurar que existe la carpeta de guardado
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
		
	_load_all_plays_from_disk()
	_setup_connections()

func _setup_connections() -> void:
	if is_instance_valid(btn_new):
		btn_new.pressed.connect(_on_new_play_requested)
	
	if is_instance_valid(btn_save):
		btn_save.pressed.connect(_on_save_button_pressed)
		
	if is_instance_valid(save_popup):
		save_popup.confirmed.connect(_on_save_confirmed)
		
	# conexion con el boton de borrado
	if is_instance_valid(%BtnDelete):
		%BtnDelete.pressed.connect(_on_delete_button_pressed)

# ==============================================================================
# MANEJO DE EVENTOS (HANDLERS)
# ==============================================================================

func _on_new_play_requested() -> void:
	if _is_editor_ready():
		editor.reset_current_play()

func _on_save_button_pressed() -> void:
	if _is_editor_ready():
		# usamos get_play_resource y esperamos porque captura pantalla
		_pending_play = await editor.get_play_resource()
		_show_save_dialog()

func _on_save_confirmed() -> void:
	_finalize_save_process()

## al presionar el boton lo marcamos como seleccionado
func _on_load_play_requested(play_data: Resource) -> void:
	_selected_play = play_data
	if _is_editor_ready():
		editor.load_play_data(play_data)

## logica para borrar la jugada seleccionada del disco y la lista 
func _on_delete_button_pressed() -> void:
	if _selected_play == null:
		_log_error("selecciona una jugada de la lista antes de borrar.")
		return
		
	# 1. borrar el archivo fisico del disco
	var safe_name = _selected_play.name.validate_filename()
	var file_path = SAVE_DIR + safe_name + ".res"
	
	if FileAccess.file_exists(file_path):
		var error = DirAccess.remove_absolute(file_path)
		if error == OK:
			print("archivo eliminado exitosamente: ", file_path)
		else:
			_log_error("no se pudo borrar el archivo fisico.")
	
	# 2. quitar de la lista en memoria
	saved_plays.erase(_selected_play)
	_selected_play = null
	
	# 3. resetear editor y refrescar interfaz
	if _is_editor_ready():
		editor.reset_current_play()
	
	_update_plays_list_ui()

# ==============================================================================
# LOGICA DE SISTEMA DE ARCHIVOS Y UI
# ==============================================================================

func _load_all_plays_from_disk() -> void:
	saved_plays.clear()
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and (file_name.ends_with(".res") or file_name.ends_with(".tres")):
				var full_path = SAVE_DIR + file_name
				var resource = ResourceLoader.load(full_path)
				if resource is PlayData:
					saved_plays.append(resource)
			file_name = dir.get_next()
	
	_update_plays_list_ui()

func _show_save_dialog() -> void:
	if is_instance_valid(name_input):
		name_input.text = ""
		save_popup.popup_centered()
		name_input.grab_focus()

func _finalize_save_process() -> void:
	if not _pending_play:
		return

	var play_name = name_input.text.strip_edges()
	if play_name.is_empty():
		play_name = "jugada_%d" % (saved_plays.size() + 1)
	
	_pending_play.name = play_name
	
	var safe_filename = play_name.validate_filename()
	var save_path = SAVE_DIR + safe_filename + ".res"
	
	var error = ResourceSaver.save(_pending_play, save_path)
	if error == OK:
		print("guardado exitoso en: ", save_path)
		saved_plays.append(_pending_play)
		_update_plays_list_ui()
	else:
		_log_error("error al guardar en disco: " + str(error))
	
	_pending_play = null

func _update_plays_list_ui() -> void:
	_clear_plays_grid()
	_populate_plays_grid()

func _clear_plays_grid() -> void:
	for child in plays_grid.get_children():
		child.queue_free()

func _populate_plays_grid() -> void:
	for play_res in saved_plays:
		var play_button = _create_play_button(play_res)
		plays_grid.add_child(play_button)

func _create_play_button(data: Resource) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(140, 160)
	
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	if data.preview_texture:
		btn.icon = data.preview_texture
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	
	btn.text = data.name
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	btn.pressed.connect(_on_load_play_requested.bind(data))
	return btn

# ==============================================================================
# HELPERS
# ==============================================================================

func _is_editor_ready() -> bool:
	if not is_instance_valid(editor):
		_log_error("editor reference is missing")
		return false
	return true

func _log_error(message: String) -> void:
	push_error("[PlaybookUI Error]: %s" % message)
