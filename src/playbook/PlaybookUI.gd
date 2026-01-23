extends CanvasLayer

# ==============================================================================
# CONFIGURACION DE ARCHIVOS
# ==============================================================================
const SAVE_DIR = "user://plays/"

# ==============================================================================
# DEPENDENCIAS Y ESTADO
# ==============================================================================
@export var editor: Node2D 
# Referencias UI nuevas 
@onready var btn_prev = %BtnPrev
@onready var btn_next = %BtnNext
@onready var preview_rect = %PreviewRect  
@onready var play_name_label = %PlayNameLabel 
@onready var btn_precision: Button = %BtnPrecision

@export_group("Assets UI")
@export var draft_icon_texture: Texture2D 

# Referencias Botones Laterales
@onready var btn_new: Button = %BtnNew
@onready var btn_save: Button = %BtnSave
@onready var save_popup: AcceptDialog = %SavePlayPopup
@onready var name_input: LineEdit = %PlayNameInput
@onready var delete_confirm_popup: ConfirmationDialog = %DeleteConfirmPopup
@onready var autosave_timer = $AutosaveTimer

var saved_plays: Array[Resource] = []
var current_play_index: int = 0
var _pending_play: Resource = null # Para guardar
var _selected_play: Resource = null # Jugada activa
var _is_shift_pressed: bool = false

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================
func _ready() -> void:
	# Asegurar carpeta
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
		
	# Configurar conexiones UI
	_setup_connections()
	
	await get_tree().process_frame
	
	# Conexión Editor -> UI 
	if is_instance_valid(editor):
		if editor.has_signal("precision_mode_changed"):
			editor.precision_mode_changed.connect(_on_editor_precision_changed)
	
	# Carga inicial
	_load_all_plays_from_disk()
	
	if not saved_plays.is_empty():
		_select_play_by_index(0)
	else:
		_update_selector_visuals()

# Función para recibir el cambio desde el código
func _on_editor_precision_changed(is_active: bool):
	if is_instance_valid(btn_precision):
		# Actualizamos el estado visual del botón sin disparar la señal de vuelta
		btn_precision.set_pressed_no_signal(is_active)
		# Actualizamos variables locales
		_is_shift_pressed = false # Reseteamos shift por seguridad
		# Feedback visual 
		btn_precision.modulate = Color.YELLOW if is_active else Color.WHITE

func _setup_connections() -> void:
	# 1. Botones del Carrusel 
	if is_instance_valid(btn_prev): btn_prev.pressed.connect(_on_prev_play)
	if is_instance_valid(btn_next): btn_next.pressed.connect(_on_next_play)

	# 2. Botones de Gestión
	if is_instance_valid(btn_new): btn_new.pressed.connect(_on_new_play_requested)
	if is_instance_valid(btn_save): btn_save.pressed.connect(_on_save_button_pressed)
	if is_instance_valid(save_popup): save_popup.confirmed.connect(_on_save_confirmed)
	if is_instance_valid(%BtnDelete): %BtnDelete.pressed.connect(_on_delete_button_pressed)
	if is_instance_valid(delete_confirm_popup): delete_confirm_popup.confirmed.connect(_on_delete_confirmed)
	if is_instance_valid(btn_precision):
		btn_precision.toggled.connect(_on_precision_button_toggled)
	
	# 3. Acciones de Juego
	if is_instance_valid(%BtnPlay): %BtnPlay.pressed.connect(_on_play_preview_pressed)
	if is_instance_valid(%BtnReset): %BtnReset.pressed.connect(_on_reset_button_pressed)
	
	# 5. Timer
	if autosave_timer: autosave_timer.timeout.connect(_on_autosave_timer_timeout)

# --- MANEJO DE INPUT  ---
func _input(event):
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		if _is_shift_pressed != event.pressed:
			_is_shift_pressed = event.pressed
			_update_editor_precision_state()

func _on_precision_button_toggled(_toggled_on: bool):
	_update_editor_precision_state()

func _update_editor_precision_state():
	# 1. Verificar si el editor está asignado
	if not is_instance_valid(editor):
		push_error("PlaybookUI: ¡ERROR! La variable 'editor' no está asignada en el Inspector.")
		return
	
	# 2. Calcular estado
	var button_active = btn_precision.button_pressed if is_instance_valid(btn_precision) else false
	var is_active = button_active or _is_shift_pressed
	
	print("PlaybookUI: Enviando estado precisión -> ", is_active) # <--- DEBUG
	
	# 3. Enviar al editor
	editor.set_visual_precision_mode(is_active)
	
	# Feedback Visual en el botón
	if is_instance_valid(btn_precision):
		# Cambiamos el color del texto o icono para que se note
		btn_precision.modulate = Color.YELLOW if is_active else Color.WHITE

# ==============================================================================
# LÓGICA DEL CARRUSEL (SELECTOR)
# ==============================================================================
func _on_prev_play():
	if saved_plays.is_empty(): return
	
	# Si (index >= 0) guardamos cambios
	if current_play_index != -1:
		_perform_silent_save()
	else:
		# (-1) al cambiar simplemente se descarta
		_show_toast("Borrador descartado", Color.ORANGE)

	# Cálculo de índice seguro
	if current_play_index == -1:
		# Si venimos de un borrador, vamos a la última jugada guardada
		current_play_index = saved_plays.size() - 1
	else:
		current_play_index = (current_play_index - 1 + saved_plays.size()) % saved_plays.size()
		
	_select_play_by_index(current_play_index)

func _on_next_play():
	if saved_plays.is_empty(): return
	
	if current_play_index != -1:
		_perform_silent_save()
	else:
		_show_toast("Borrador descartado", Color.ORANGE)
	
	if current_play_index == -1:
		# Si venimos de un borrador, vamos a la primera jugada guardada
		current_play_index = 0
	else:
		current_play_index = (current_play_index + 1) % saved_plays.size()
		
	_select_play_by_index(current_play_index)

func _select_play_by_index(index: int):
	current_play_index = index
	var play_data = saved_plays[index]
	_selected_play = play_data
	
	if editor:
		# 1. Forzamos detener cualquier animación en curso
		editor.stop_all_animations()
		
		# 2.Desbloqueamos explícitamente el RouteManager
		editor.unlock_editor_for_editing()
		
		# 3. Limpiamos rutas fantasmas visuales antes de cargar las nuevas
		if editor.route_manager:
			editor.route_manager.clear_all_routes()
			
		# 4. cargamos la data limpia
		editor.load_play_data(play_data)
	
	_update_selector_visuals()

func _update_selector_visuals():
	#Verificamos si es null antes de intentar leer nada.
	if _selected_play == null:
		play_name_label.text = "Sin Jugadas"
		if preview_rect: preview_rect.texture = null
		return

	# MODO BORRADOR (Index -1 pero con objeto activo)
	if current_play_index == -1:
		play_name_label.text = _selected_play.name 
		
		# Icono de Draft
		if preview_rect:
			if draft_icon_texture:
				preview_rect.texture = draft_icon_texture
			else:
				preview_rect.texture = null 
		return

	#JUGADA GUARDADA
	# Verificación extra de seguridad para índices fuera de rango
	if saved_plays.is_empty() or current_play_index >= saved_plays.size():
		play_name_label.text = "Error de Índice"
		return

	var play = saved_plays[current_play_index]
	play_name_label.text = play.name
	
	if preview_rect:
		if play.preview_texture:
			preview_rect.texture = play.preview_texture
		else:
			preview_rect.texture = null

# ==============================================================================
# GESTIÓN DE ARCHIVOS
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
	
	# Si no hay jugadas, creamos una por defecto vacía para no romper el carrusel
	if saved_plays.is_empty():
			current_play_index = -1
			_selected_play = null

func _on_new_play_requested() -> void:
	if not _is_editor_ready(): return
	
	# 1. Gestión del estado anterior
	if current_play_index != -1:
		_perform_silent_save()
	
	editor.unlock_editor_for_editing() 
	
	# 3. Limpieza de la jugada visual
	editor.reset_current_play()
	
	# 4. Creación del Borrador en Memoria Volátil
	var new_draft = PlayData.new()
	new_draft.name = "Nueva Jugada (Borrador)"
	
	current_play_index = -1 
	_selected_play = new_draft
	
	_update_selector_visuals()
	_show_toast("Modo Borrador: Edición Habilitada", Color.YELLOW)

func _on_save_button_pressed() -> void:
	if _is_editor_ready():
		# 1. Capturamos la foto y datos actuales del editor
		var current_res = await editor.get_play_resource()
		
		if _selected_play == null:
			_selected_play = current_res # Usamos el recurso fresco como base
			_selected_play.name = "Nueva Jugada"
			current_play_index = -1 
		# -------------------------------------
		
		# 2. Actualizamos los datos del objeto en memoria
		_selected_play.preview_texture = current_res.preview_texture
		_selected_play.formations = current_res.formations
		_selected_play.routes = current_res.routes
		
		# Transferimos el modo precisión
		if "is_precision" in current_res:
			_selected_play.set("is_precision", current_res.is_precision)
		if "meta_data" in current_res:
			_selected_play.set("meta_data", current_res.meta_data)
			
		_pending_play = _selected_play
		_show_save_dialog()
func _on_save_confirmed() -> void:
	if not _pending_play: return

	var new_name = name_input.text.strip_edges()
	var is_new_save = (current_play_index == -1) # Detectamos si venimos de borrador
	
	if not new_name.is_empty():
		# Lógica para renombrar archivo si ya existía
		_pending_play.name = new_name

	var safe_filename = _pending_play.name.validate_filename()
	# Validar que no sobrescriba algo existente si es nuevo
	var save_path = SAVE_DIR + safe_filename + ".res"
	
	var error = ResourceSaver.save(_pending_play, save_path)
	
	if error == OK:
		if is_new_save:
			saved_plays.append(_pending_play)
			current_play_index = saved_plays.size() - 1
			_show_toast("¡Borrador Guardado!", Color.GREEN)
		else:
			_show_toast("Cambios Guardados", Color.GREEN)
			
		_update_selector_visuals()
	else:
		_show_toast("Error al guardar", Color.RED)

func _on_delete_button_pressed() -> void:
	if saved_plays.is_empty(): return
	delete_confirm_popup.popup_centered()

func _on_delete_confirmed() -> void:
	if saved_plays.is_empty(): return
	
	var play_to_delete = saved_plays[current_play_index]
	var safe_name = play_to_delete.name.validate_filename()
	var file_path = SAVE_DIR + safe_name + ".res"
	
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	
	saved_plays.remove_at(current_play_index)
	
	# Ajustar índice si borramos el último
	if current_play_index >= saved_plays.size():
		current_play_index = max(0, saved_plays.size() - 1)
	
	if saved_plays.is_empty():
		# Resetear editor si no queda nada
		editor.reset_current_play()
		_update_selector_visuals()
	else:
		_select_play_by_index(current_play_index)
		
	_show_toast("Eliminado", Color.ORANGE)

# ==============================================================================
# AUTOGUARDADO & HELPERS
# ==============================================================================
func _on_editor_content_changed() -> void:
	if _selected_play:
		autosave_timer.start() # Debounce

func _on_autosave_timer_timeout() -> void:
	_perform_silent_save()

func _perform_silent_save() -> void:
	# Si no hay jugada o esta en MODO BORRADOR no guardamos automáticamente
	if _selected_play == null or current_play_index == -1: 
		return
		
	if not _is_editor_ready(): return
	
	# Obtenemos la data fresca del editor 
	var fresh_data = editor.get_current_state_as_data()
	
	_selected_play.formations = fresh_data.formations
	_selected_play.routes = fresh_data.routes
	
	if "is_precision" in fresh_data:
		_selected_play.set("is_precision", fresh_data.is_precision)
	
	# Copiamos metadata por si acaso usas fallback
	if "meta_data" in fresh_data:
		_selected_play.set("meta_data", fresh_data.meta_data)
	
	var safe_name = _selected_play.name.validate_filename()
	var save_path = SAVE_DIR + safe_name + ".res"
	
	# Guardamos en disco 
	var err = ResourceSaver.save(_selected_play, save_path)
	if err != OK:
		print("Error guardando jugada: ", err)

func _show_save_dialog() -> void:
	if is_instance_valid(name_input):
		name_input.text = _selected_play.name if _selected_play else ""
		save_popup.popup_centered()
		name_input.grab_focus()

func _is_editor_ready() -> bool:
	return is_instance_valid(editor)

func _show_toast(message: String, color: Color = Color.WHITE) -> void:
	var label = %StatusLabel
	if not label: return
	
	if label.has_meta("tween"):
		var t = label.get_meta("tween")
		if t and t.is_valid(): t.kill()
	
	label.text = message
	label.modulate = color
	label.modulate.a = 1.0
	
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(1.0)
	label.set_meta("tween", tween)

# Botones extra
func _on_play_preview_pressed():
	if _is_editor_ready():
		_perform_silent_save()
		editor.lock_editor_for_play()
		# Resetear posiciones antes de correr
		for child in editor.nodes_container.get_children():
			if child.has_method("reset_to_start"): child.reset_to_start()
		await get_tree().process_frame
		editor.play_current_play()

func _on_reset_button_pressed():
	if _is_editor_ready():
		editor.unlock_editor_for_editing()
		editor.reset_formation_state()

func _on_set_qb_pressed():
	pass

func _on_set_center_pressed():
	pass
