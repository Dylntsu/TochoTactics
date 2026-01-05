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
@onready var delete_confirm_popup: ConfirmationDialog = %DeleteConfirmPopup

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
	#  Asegurar carpeta
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
		
	# configurar botones y señales
	_setup_connections()
	
		# ESPERA DE SEGURIDAD: 
	# se espera un frame para que el PlaybookEditor termine su propio _ready
	await get_tree().process_frame
	
	# escanear el disco para llenar el array 
	_load_all_plays_from_disk()
	# dibujar la lista y cargar la primera jugada automáticamente
	_update_plays_list_ui()

func _setup_connections() -> void:
	# 1. Botón Nueva Jugada
	if is_instance_valid(btn_new):
		if not btn_new.pressed.is_connected(_on_new_play_requested):
			btn_new.pressed.connect(_on_new_play_requested)
	
	# 2. Botón Guardar
	if is_instance_valid(btn_save):
		if not btn_save.pressed.is_connected(_on_save_button_pressed):
			btn_save.pressed.connect(_on_save_button_pressed)
		
	# 3. Popup de Guardado
	if is_instance_valid(save_popup):
		if not save_popup.confirmed.is_connected(_on_save_confirmed):
			save_popup.confirmed.connect(_on_save_confirmed)
			
	# 4. Botón Borrar (Aquí estaba tu error duplicado)
	if is_instance_valid(%BtnDelete):
		if not %BtnDelete.pressed.is_connected(_on_delete_button_pressed):
			%BtnDelete.pressed.connect(_on_delete_button_pressed)

	# 5. Popup de Confirmación de Borrado
	if is_instance_valid(delete_confirm_popup):
		if not delete_confirm_popup.confirmed.is_connected(_on_delete_confirmed):
			delete_confirm_popup.confirmed.connect(_on_delete_confirmed)

	# 6. Botón Play / Preview
	if is_instance_valid(%BtnPlay):
		if not %BtnPlay.pressed.is_connected(_on_play_preview_pressed):
			%BtnPlay.pressed.connect(_on_play_preview_pressed)
			
	# Conexión para el botón Reiniciar
	if is_instance_valid(%BtnReset):
		if not %BtnReset.pressed.is_connected(_on_reset_button_pressed):
			%BtnReset.pressed.connect(_on_reset_button_pressed)

# ==============================================================================
# MANEJO DE EVENTOS (HANDLERS)
# ==============================================================================

## Al presionar "+ Nueva"
func _on_new_play_requested() -> void:
	# Al pedir nueva jugada o cargar otra, desbloqueamos clics
	editor.unlock_all_players()
	if not _is_editor_ready(): return
	
	# 1. Resetear el lienzo físico
	editor.reset_current_play()
	
	# 2. Crear el recurso temporal (Placeholder)
	var placeholder = PlayData.new()
	placeholder.name = "Nueva Jugada..."
	# Le asignamos una textura por defecto o vacía si tienes una
	# placeholder.preview_texture = load("res://assets/ui/empty_slot.png") 
	
	# 3. Lo inyectamos al inicio de la lista de memoria (no al disco aún)
	# Primero verificamos si ya existe un placeholder para no llenar la lista de basura
	_remove_unused_placeholders()
	saved_plays.insert(0, placeholder)
	
	# 4. Seleccionarlo automáticamente
	_selected_play = placeholder
	
	# 5. Refrescar UI
	_update_plays_list_ui()
	_show_toast("Modo edición: Nueva Jugada", Color.CYAN)
	
## Limpia placeholders anteriores para que solo haya uno a la vez
func _remove_unused_placeholders() -> void:
	var to_remove = []
	for play in saved_plays:
		if play.name == "Nueva Jugada...":
			to_remove.append(play)
	for p in to_remove:
		saved_plays.erase(p)
		

func _on_save_button_pressed() -> void:
	if _is_editor_ready():
		# usamos get_play_resource y esperamos porque captura pantalla
		_pending_play = await editor.get_play_resource()
		_show_save_dialog()

func _on_save_confirmed() -> void:
	_finalize_save_process()

## al presionar el boton lo marcamos como seleccionado
func _on_load_play_requested(play_data: Resource) -> void:
	if not _is_editor_ready(): return
	
	# Antes de cargar la nueva, obligamos al editor a detener cualquier proceso previo
	editor.stop_all_animations()
	
	_selected_play = play_data
	editor.load_play_data(play_data)
	_update_selection_visuals()
	
	_show_toast("Cargado: " + play_data.name, Color.AQUA)

## logica para borrar la jugada seleccionada del disco y la lista 
func _on_delete_button_pressed() -> void:
	if _selected_play == null:
		_log_error("selecciona una jugada de la lista antes de borrar.")
		return
	
	# simplemente mostramos el dialogo de confirmacion
	delete_confirm_popup.popup_centered()

## esta funcion solo se ejecuta si el usuario presiona "Borrar" en el popup
func _on_delete_confirmed() -> void:
	if _selected_play == null: return
	
	var safe_name = _selected_play.name.validate_filename()
	var file_path = SAVE_DIR + safe_name + ".res"
	
	# Borrado físico
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	
	# Feedback y limpieza
	var deleted_name = _selected_play.name
	saved_plays.erase(_selected_play)
	_selected_play = null
	
	if _is_editor_ready():
		editor.reset_current_play()
	
	_update_plays_list_ui()
	_show_toast("Eliminado: " + deleted_name, Color.ORANGE)

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

## Modificamos el guardado para que reemplace el placeholder
func _finalize_save_process() -> void:
	if not _pending_play: return

	var play_name = name_input.text.strip_edges()
	if play_name.is_empty():
		play_name = "jugada_%d" % (saved_plays.size() + 1)
	
	_pending_play.name = play_name
	var safe_filename = play_name.validate_filename()
	var save_path = SAVE_DIR + safe_filename + ".res"
	
	var error = ResourceSaver.save(_pending_play, save_path)
	if error == OK:
		# REEMPLAZO: Si la jugada actual era el placeholder, lo quitamos
		_remove_unused_placeholders()
		
		# Añadimos la nueva jugada real
		saved_plays.append(_pending_play)
		_selected_play = _pending_play
		
		_update_plays_list_ui()
		_show_toast("¡Guardado exitoso!", Color.GREEN)
	else:
		_show_toast("Error al guardar", Color.RED)

func _update_plays_list_ui() -> void:
	_clear_plays_grid()
	_populate_plays_grid()
	
	# selección automática al inicio
	if _selected_play == null and not saved_plays.is_empty():
		# obtenemos la primera jugada de la lista cargada
		var first_play = saved_plays[0]
		# forzamos la carga de esta jugada en el editor
		_on_load_play_requested(first_play)
	else:
		# Si no hay jugadas o ya hay una seleccionada, solo refrescamos lo visual
		_update_selection_visuals()

## indicador de jugada seleccionada
func _update_selection_visuals() -> void:
	# definimos el color de seleccion
	var selected_color = Color(0.2, 0.8, 0.2)
	
	for btn in plays_grid.get_children():
		if btn is Button:
			if _selected_play != null and btn.text == _selected_play.name:
				# forzamos el color en todos los estados para que no cambie al mover el mouse
				btn.add_theme_color_override("font_color", selected_color)
				btn.add_theme_color_override("font_hover_color", selected_color)
				btn.add_theme_color_override("font_pressed_color", selected_color)
				btn.add_theme_color_override("font_focus_color", selected_color)
			else:
				# limpiamos los overrides para volver al tema original
				btn.remove_theme_color_override("font_color")
				btn.remove_theme_color_override("font_hover_color")
				btn.remove_theme_color_override("font_pressed_color")
				btn.remove_theme_color_override("font_focus_color")

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

func _on_play_preview_pressed() -> void:
	if not _is_editor_ready(): return
	
	editor.lock_editor_for_play()# bloqueo
	# Mandamos a todos al inicio antes de correr
	for player in editor.nodes_container.get_children():
		if player.has_method("reset_to_start"):
			player.reset_to_start()
	
	await get_tree().process_frame
	editor.play_current_play()

## Muestra un mensaje temporal en pantalla (Toast)
func _show_toast(message: String, color: Color = Color.WHITE) -> void:
	var label = %StatusLabel
	if not label: return
	
	label.text = message
	label.modulate = color
	label.modulate.a = 1.0 # Opaco
	
	# Animación: aparece y se desvanece
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.5).set_delay(1.0)

## Manejador del botón Reiniciar
func _on_reset_button_pressed() -> void:
	if _is_editor_ready():
		editor.reset_formation_state()
		editor.unlock_editor_for_editing() #desbloqeo
		_show_toast("Posiciones restablecidas", Color.LIGHT_BLUE)
