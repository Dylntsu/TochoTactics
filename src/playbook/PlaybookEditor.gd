extends Node2D

# ==============================================================================
# COMPONENTES
# ==============================================================================
@onready var route_manager = $RouteManager
@onready var nodes_container = $NodesContainer
@onready var background = $CanvasLayer/Background 
@onready var capture_frame = $CaptureFrame

@onready var stats_panel = %StatsPanel 

signal content_changed # señal para avisar a la UI

# ==============================================================================
# VARIABLES PARA EL INSPECTOR
# ==============================================================================
@export_group("Ajuste Manual de Formacion")
@export_range(0.0, 3.0) var formation_y_offset: float = 0.8
@export_range(-2.0, 2.0) var qb_depth_offset: float = 0.7

@export_group("Posicionamiento de Jugadores")
@export_range(0.5, 4.0) var spawn_vertical_offset: float = 1.5
@export_range(0.0, 2.0) var qb_advance_offset: float = 0.5

@export_group("Limites de Jugada")
@export var offensive_limit_row_offset: int = 4

# ==============================================================================
# CONFIGURACION
# ==============================================================================
@export_group("Assets")
@export var player_scene: PackedScene = preload("res://src/playbook/player/Player.tscn")

@export_group("Grid Configuration")
@export var grid_size: Vector2 = Vector2(5, 8) 
@export var snap_distance: float = 40.0 

@export_group("Grid Precision Margins")
@export_range(0.0, 0.8) var grid_margin_top: float = 0.5    
@export_range(0.0, 0.5) var grid_margin_bottom: float = 0.02 
@export_range(0.0, 0.5) var grid_margin_left: float = 0.418   
@export_range(0.0, 0.5) var grid_margin_right: float = 0.417  

@export_group("Formation Configuration")
@export_range(0.0, 0.5) var formation_margin_left: float = 0.30
@export_range(0.0, 0.5) var formation_margin_right: float = 0.30
@export_range(0.0, 0.5) var formation_bottom_margin: float = 0.099
@export var player_count: int = 5 

# === BASE DE DATOS DEL EQUIPO ===
var team_database: Array[Resource] = []
const PLAYERS_DIR = "res://data/players/" 

# Roles
var qb_player_id: int = -1
var center_player_id: int = -1
# Jugador seleccionado
var selected_player_id: int = -1

# ESTADO LOCAL
var grid_points: Array[Vector2] = []
var spacing: int = 0
var _active_play_positions: Dictionary = {}
var is_precision_mode_active: bool = false

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================
func get_selected_player_id() -> int:
	return selected_player_id

func _ready():
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	# 1. Carga automática de jugadores
	_load_team_from_folder()
	
	await get_tree().process_frame
	
	# Configuración inicial del panel de stats 
	if stats_panel:
		# Aseguramos que se vea 
		stats_panel.visible = true
		
		# Conectamos señales del panel si tiene lógica interna de roles
		if stats_panel.has_signal("role_changed"):
			if not stats_panel.role_changed.is_connected(_on_menu_role_changed):
				stats_panel.role_changed.connect(_on_menu_role_changed)
	
	if route_manager:
		var field = get_node_or_null("CanvasLayer/Background")
		if field:
			var rect = field.get_global_rect()
			if rect.size.x < 10:
				rect = Rect2(field.global_position, field.get_rect().size * field.global_scale)
			route_manager.limit_rect = rect
			print("Límites del campo verde (CORREGIDOS): ", route_manager.limit_rect)
		else:
			route_manager.limit_rect = Rect2(0, 0, 1280, 720)
			push_warning("Background no encontrado, usando límites por defecto")
		
		route_manager.route_modified.connect(_on_child_action_finished)
	
	rebuild_editor()

# ==============================================================================
# GESTIÓN DE SELECCIÓN Y STATS (Lógica Estática)
# ==============================================================================

# Esta función se llama cuando se hace Click Derecho en un jugador
func _on_player_input_event(_viewport, event, _shape_idx, player_node):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		
		# Selección visual en el campo
		deselect_all_players()
		selected_player_id = player_node.player_id
		player_node.set_selected(true)
		
		# Actualizar el Panel Estático Lateral
		_update_stats_panel(player_node)

func _update_stats_panel(player_node):
	if is_instance_valid(stats_panel):
		stats_panel.setup(player_node)

func deselect_all_players():
	for child in nodes_container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(false)
	selected_player_id = -1

# ==============================================================================
# CARGA Y RENDERIZADO
# ==============================================================================
func _load_team_from_folder():
	team_database.clear()
	var dir = DirAccess.open(PLAYERS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var full_path = PLAYERS_DIR + file_name
				var res = load(full_path)
				if res is PlayerStats:
					team_database.append(res)
					print("Jugador cargado: ", res.full_name)
			file_name = dir.get_next()
		team_database.sort_custom(func(a, b): return a.full_name < b.full_name)
	else:
		push_error("PlaybookEditor: No se pudo abrir la carpeta: " + PLAYERS_DIR)

func _on_menu_role_changed(new_role: String):
	if selected_player_id != -1:
		assign_role_to_player(selected_player_id, new_role)
		_show_toast_in_editor("Posición actualizada: " + new_role)

func _on_viewport_resized():
	rebuild_editor()

func rebuild_editor():
	# Obtener el rect global del CaptureFrame directamente
	var frame_rect = capture_frame.get_global_rect()
	
	var bounds = calculate_grid_bounds()
	var grid_data = GridService.calculate_grid(bounds, grid_size)
	grid_points = grid_data.points
	spacing = grid_data.spacing
	
	render_grid_visuals()
	render_formation() 
	
	if route_manager:
		# Forzamos al manager a usar el CaptureFrame como límite de dibujo
		route_manager.limit_rect = frame_rect
		route_manager.setup(grid_points, spacing, frame_rect)

func calculate_grid_bounds() -> Rect2:
	var field_rect = background.get_global_rect()
	var x = field_rect.position.x + (field_rect.size.x * grid_margin_left)
	var y = field_rect.position.y + (field_rect.size.y * grid_margin_top)
	var width = field_rect.size.x * (1.0 - grid_margin_left - grid_margin_right)
	var height = field_rect.size.y * (1.0 - grid_margin_top - grid_margin_bottom)
	return Rect2(x, y, width, height)

func render_grid_visuals():
	# Limpieza previa
	for child in nodes_container.get_children():
		if not child.name.begins_with("PlayerStart") and not child is Area2D:
			child.queue_free()
			
	var marker_size = clamp(spacing * 0.12, 4, 12)
	for pos in grid_points:
		var marker = ColorRect.new()
		marker.size = Vector2(marker_size, marker_size)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.color = Color(1, 1, 1, 0.5)
		marker.position = pos - (marker.size / 2)
		
		# Agregamos al grupo
		marker.add_to_group("GridMarkers") 
		
		# --- CORRECCIÓN DE BLINDAJE ---
		# Aplicamos la visibilidad ANTES de añadirlo al árbol
		marker.visible = not is_precision_mode_active
		# ------------------------------
		
		nodes_container.add_child(marker)

func render_formation():
	# Limpieza de nodos anteriores
	for child in nodes_container.get_children():
		if child.name.begins_with("PlayerStart") or child is Area2D:
			child.queue_free()

	if player_count <= 0: return

	# 1. Definir el "Lienzo"
	var frame_rect = capture_frame.get_global_rect()
	var center_x = frame_rect.get_center().x
	var available_width = frame_rect.size.x * 0.90 
	
	# 2. Lógica de Espaciado Adaptativo
	var ideal_separation = spacing * 1.5
	var final_separation = ideal_separation
	
	if player_count > 1:
		var total_ideal_width = (player_count - 1) * ideal_separation
		if total_ideal_width > available_width:
			final_separation = available_width / (player_count - 1)
	
	var total_formation_width = (player_count - 1) * final_separation
	var start_x = center_x - (total_formation_width / 2.0)
	
	# 3. Definir Altura Base (Punto de Instanciación)
	var desired_y = frame_rect.end.y - (spacing * 1.5)
	var clamped_y = clamp(desired_y, frame_rect.position.y, frame_rect.end.y - (spacing * 0.5))
	
	# Usamos round() aquí también para que el límite sea un entero
	var scrimmage_line_y = round(clamped_y) 
	
	# Definimos el rectángulo de restricción
	var scrimmage_limit_rect = Rect2(
		frame_rect.position.x, 
		scrimmage_line_y, 
		frame_rect.size.x, 
		frame_rect.end.y - scrimmage_line_y
	)
	
	for i in range(player_count):
		var player = player_scene.instantiate()
		player.player_id = i
		
		if team_database.size() > 0:
			player.data = team_database[i % team_database.size()]
		
		# Calculamos en float, pero redondeamos inmediatamente al entero más cercano
		var raw_x = start_x + (i * final_separation)
		var pos_x = round(raw_x)
		var pos_y = round(clamped_y) 
		
		# Prioridad a la persistencia
		if _active_play_positions.has(i):
			var saved_pos_data = _active_play_positions[i]
			if saved_pos_data is Dictionary and saved_pos_data.has("position"):
				player.position = saved_pos_data.position.round()
			elif saved_pos_data is Vector2:
				player.position = saved_pos_data.round()
		else:
			# Usamos las coordenadas redondeadas calculadas arriba
			player.position = Vector2(pos_x, pos_y)
		
		# --- APLICACIÓN DEL LÍMITE ---
		player.limit_rect = scrimmage_limit_rect 
		player.save_starting_position()
		
		if player.data and player.data.portrait:
			player.setup_player_visual(player.data.portrait, i)
		
		# Conexiones
		if not player.input_event.is_connected(_on_player_input_event):
			player.input_event.connect(_on_player_input_event.bind(player))
		player.start_route_requested.connect(_on_player_start_route_requested)
		player.moved.connect(_on_player_moved)
		if not player.interaction_ended.is_connected(_on_child_action_finished):
			player.interaction_ended.connect(_on_child_action_finished)
		
		nodes_container.add_child(player)

func _force_visual_sync():
	# 1. Forzamos el redibujado de la rejilla final
	queue_redraw()
	
	# 2. Forzamos la visibilidad de los nodos grandes (GridMarkers)
	# Usamos set_visible explícitamente en el grupo
	if is_precision_mode_active:
		get_tree().call_group("GridMarkers", "hide")
	else:
		get_tree().call_group("GridMarkers", "show")

func _get_player_by_id(id: int):
	for child in nodes_container.get_children():
		if "player_id" in child and child.player_id == id:
			return child
	return null

func get_offensive_zone_limit_y() -> float:
	if grid_points.is_empty(): 
		return 0.0
	var limit_index = int(grid_size.y - offensive_limit_row_offset)
	if limit_index < 0: 
		limit_index = 0
	return grid_points[limit_index].y

# ==============================================================================
# INPUT
# ==============================================================================
func _input(event):
	var mouse_pos = get_local_mouse_position()
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if route_manager.is_editing:
					route_manager.handle_input(mouse_pos)
				else:
					_try_click_existing_route_end(mouse_pos)
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if route_manager.is_editing:
				route_manager.finish_route()

	elif event is InputEventMouseMotion:
		if route_manager.is_editing:
			# Muestrael Preview
			route_manager.update_preview(mouse_pos) 
			
			# Permite dibujar arrastrando 
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				route_manager.handle_input(mouse_pos)

func _try_click_existing_route_end(mouse_pos: Vector2):
	var snap_range = route_manager._snap_distance 
	
	for pid in route_manager.active_routes:
		var line = route_manager.active_routes[pid]
		if line.get_point_count() > 0:
			var end_point = line.points[line.get_point_count() - 1]
			if mouse_pos.distance_to(end_point) < snap_range:
				route_manager.resume_editing_route(pid)
				return 

# ==============================================================================
# CALLBACKS Y LÓGICA DE JUGADA
# ==============================================================================
func _on_player_start_route_requested(player_node):
	var pid = player_node.player_id
	
	#Si ya tiene una ruta a medias, la retomamos
	if route_manager.active_routes.has(pid):
		route_manager.resume_editing_route(pid)
		return 

	# Si estábamos editando a otro jugador, cerramos esa edición anterior
	if route_manager.is_editing and route_manager.current_player_id != pid:
		route_manager.finish_route()
	
	# Iniciamos la nueva ruta 
	route_manager.try_start_route(pid, player_node.get_route_anchor())

# Calcula la posición ideal en el Grid para un rol específico
#refactorizacion de posiciones ajustado a los nuevos limites
func _get_role_target_position(role_name: String) -> Vector2:
	# Validación de seguridad
	if not is_instance_valid(capture_frame) or spacing == 0:
		return Vector2.ZERO

	var frame_rect = capture_frame.get_global_rect()
	var center_x = frame_rect.get_center().x
	
	var desired_y = frame_rect.end.y - (spacing * 1.5)
	var scrimmage_y = clamp(desired_y, frame_rect.position.y, frame_rect.end.y - (spacing * 0.5))
	
	match role_name:
		"CENTER":
			return Vector2(center_x, scrimmage_y)
			
		"QB":
			return Vector2(center_x, scrimmage_y + (spacing * 0.5))
			
		_:
			return Vector2.ZERO

func _on_player_moved(player_node):
	# Actualizar memoria de posiciones
	var pos_data = {
		"position": player_node.position,
		"resource_path": player_node.data.resource_path if player_node.data else ""
	}
	_active_play_positions[player_node.player_id] = pos_data
	
	# Actualizar visualmente la línea de la ruta
	if route_manager:
		route_manager.update_route_origin(player_node.player_id, player_node.get_route_anchor())
func stop_all_animations():
	for child in nodes_container.get_children():
		if child is Area2D and child.has_method("stop_animation"):
			child.stop_animation()

func reset_current_play():
	stop_all_animations()
	route_manager.clear_all_routes()
	_active_play_positions.clear()
	rebuild_editor()

func _clear_routes() -> void:
	if route_manager:
		route_manager.clear_all_routes()

func _restore_initial_formation() -> void:
	rebuild_editor()

# ==============================================================================
# PERSISTENCIA Y MEMENTO (LOGICA PLAY DATA)
# ==============================================================================
func get_play_resource() -> PlayData:
	var new_play = PlayData.new()
	new_play.timestamp = Time.get_unix_time_from_system()
	
	if "is_precision" in new_play:
		new_play.is_precision = is_precision_mode_active 
	else:
		new_play.meta_data = {"precision": is_precision_mode_active}
	for player in nodes_container.get_children():
		if "player_id" in player:
			var player_entry = {
				"position": player.position,
				"resource_path": player.data.resource_path if player.data else ""
			}
			new_play.formations[player.player_id] = player_entry 
	
	for pid in route_manager.active_routes:
		var line = route_manager.active_routes[pid]
		if is_instance_valid(line):
			new_play.routes[pid] = line.points
			
	new_play.preview_texture = await get_play_preview_texture()
	return new_play

func get_play_preview_texture() -> ImageTexture:
	# Esperamos al final del frame para que todo esté dibujado
	await get_tree().process_frame
	await get_tree().process_frame
	
	# obtener la imagen completa de lo que ve la cámara
	var viewport = get_viewport()
	var screenshot: Image = viewport.get_texture().get_image()
	
	var canvas_transform = get_canvas_transform()
	var viewport_transform = viewport.get_final_transform() # Transformación global de la ventana
	var global_rect = capture_frame.get_global_rect()

	# Aproximación segura usando transformaciones de viewport:
	var screen_rect_pos = (viewport_transform * canvas_transform) * global_rect.position
	var screen_rect_end = (viewport_transform * canvas_transform) * global_rect.end
	var screen_size = screen_rect_end - screen_rect_pos
	
	# Definir la región final asegurando que sea números enteros
	var crop_region = Rect2(screen_rect_pos, screen_size).abs()
	
	# Validación de seguridad para no salirnos de la imagen
	var img_size = Vector2(screenshot.get_width(), screenshot.get_height())
	
	# Ajustamos para que la región no sea negativa ni se salga
	crop_region.position.x = clamp(crop_region.position.x, 0, img_size.x)
	crop_region.position.y = clamp(crop_region.position.y, 0, img_size.y)
	
	# Ajustamos el ancho/alto si se sale por la derecha/abajo
	if crop_region.position.x + crop_region.size.x > img_size.x:
		crop_region.size.x = img_size.x - crop_region.position.x
	if crop_region.position.y + crop_region.size.y > img_size.y:
		crop_region.size.y = img_size.y - crop_region.position.y
		
	# 4. Recortar
	if crop_region.size.x > 0 and crop_region.size.y > 0:
		var cropped_img = screenshot.get_region(crop_region)
		
		cropped_img.resize(200, 300, Image.INTERPOLATE_LANCZOS)
		
		return ImageTexture.create_from_image(cropped_img)
	
	return null

func load_play_data(play_data) -> void:
	print("--- INICIANDO CARGA DE JUGADA ---")
	
	unlock_editor_for_editing() 
	stop_all_animations()
	if route_manager:
		route_manager.clear_all_routes()
	
	# 1. LEER EL MODO 
	var saved_precision = false
	if play_data is Resource:
		if "is_precision" in play_data:
			saved_precision = play_data.is_precision
		elif "meta_data" in play_data and play_data.meta_data.has("precision"):
			saved_precision = play_data.meta_data["precision"]
	elif play_data is Dictionary:
		saved_precision = play_data.get("is_precision", false)
	
	# 2. ESTABLECER LA VARIABLE INTERNA
	is_precision_mode_active = saved_precision
	
	# Sincronizamos managers
	if route_manager:
		route_manager.set_precision_mode(saved_precision)
	
	# Avisamos a la UI
	if has_signal("precision_mode_changed"):
		emit_signal("precision_mode_changed", saved_precision)
	
	# 3. LEER DATOS RESTANTES
	var positions_data = {}
	var routes_data = {}
	if play_data is Resource:
		if "formations" in play_data: positions_data = play_data.formations
		if "routes" in play_data: routes_data = play_data.routes
	elif play_data is Dictionary:
		positions_data = play_data.get("formations", {})
		routes_data = play_data.get("routes", {})
	
	_active_play_positions = positions_data.duplicate()
	
	# 4. RECONSTRUIR EL EDITOR
	rebuild_editor()
	
	# 5. CARGAR RUTAS
	if route_manager:
		route_manager.load_routes_from_data(routes_data)
	
	for child in nodes_container.get_children():
		if child is Area2D and "player_id" in child:
			var p_id = child.player_id
			if routes_data.has(p_id):
				child.current_route = routes_data[p_id]
				if route_manager:
					route_manager.update_route_origin(p_id, child.get_route_anchor(), true)
	
	# Esperamos un frame para que Godot termine de calcular tamaños
	await get_tree().process_frame
	# Forzamos la sincronización visual final
	_force_visual_sync()

func play_current_play():
	var all_routes = route_manager.get_all_routes() 
	
	for player in nodes_container.get_children():
		if player is Area2D and player.has_method("play_route"):
			player.current_route = all_routes.get(player.player_id, PackedVector2Array())
			player.play_route()

func prepare_preview():
	rebuild_editor()
	await get_tree().process_frame
	
func unlock_all_players():
	for child in nodes_container.get_children():
		if child is Area2D:
			child.input_pickable = true
			if child.has_method("stop_animation"):
				child.stop_animation()

func reset_formation_state():
	stop_all_animations()
	
	for child in nodes_container.get_children():
		if child is Area2D and child.has_method("reset_to_start"):
			child.reset_to_start()
			if route_manager:
				route_manager.update_route_origin(child.player_id, child.get_route_anchor())
	
	unlock_editor_for_editing()

func lock_editor_for_play():
	route_manager.set_locked(true)
	for child in nodes_container.get_children():
		if child is Area2D:
			child.input_pickable = false 
			if child.has_method("stop_animation"):
				child.is_playing = true

func unlock_editor_for_editing():
	route_manager.set_locked(false)
	for child in nodes_container.get_children():
		if child is Area2D:
			child.input_pickable = true
			if child.has_method("reset_to_start"):
				child.reset_to_start()

func get_current_state_as_data() -> PlayData:
	var data = PlayData.new()
	
	# Guardar Formaciones
	var formations = {}
	for player in nodes_container.get_children():
		if player is Area2D:
			formations[player.player_id] = {
				"position": player.starting_position,
				"resource_path": player.data.resource_path if player.data else ""
			}
	data.formations = formations
	
	# Guardar Rutas
	data.routes = route_manager.get_all_routes()
	
	# --- GUARDAR MODO DE DIBUJO ---
	# Asignamos directamente. Si PlayData tiene la variable, funciona.
	# Si no, usamos set() para intentar asignación dinámica.
	data.set("is_precision", is_precision_mode_active)
	
	# Backup en metadata por seguridad
	data.set("meta_data", {"precision": is_precision_mode_active})
		
	return data

func _on_child_action_finished(_node = null):
	content_changed.emit()
	
func assign_role_to_player(source_pid: int, new_role: String):
	if grid_points.is_empty(): return
	
	# 1. Identificar nodos y estado actual
	var source_player = _get_player_by_id(source_pid)
	if not source_player: return
	
	# Guardamos la posición original del jugador que estamos moviendo
	# para mandarle ahí al jugador que sea desalojado 
	var source_original_pos = source_player.position
	
	# Calcular dónde debe ir el nuevo rol
	var target_pos = _get_role_target_position(new_role)
	if target_pos == Vector2.ZERO: return # Si el rol no tiene posición fija, no hacemos nada automático
	
	var incumbent_pid = -1
	
	# definimos quién es el dueño actual del puesto
	match new_role:
		"CENTER": incumbent_pid = center_player_id
		"QB": incumbent_pid = qb_player_id
	
	# A. Movemos al jugador seleccionado a su nuevo puesto
	source_player.position = target_pos
	source_player.set_role(new_role)
	# Actualizamos sus datos en memoria
	_update_player_data_position(source_player)
	
	# B. Si había alguien en ese puesto lo mandamos al origen 
	if incumbent_pid != -1 and incumbent_pid != source_pid:
		var incumbent_player = _get_player_by_id(incumbent_pid)
		
		if incumbent_player:
			# intercambio
			incumbent_player.position = source_original_pos
			
			# Le quitamos el rol especial visualmente 
			incumbent_player.set_role("WR") 
			
			# Actualizamos sus datos en memoria
			_update_player_data_position(incumbent_player)
			
			print("Swap realizado: Jugador ", source_pid, " reemplazó a ", incumbent_pid)
	
	# 5. Actualizar las variables de estado global
	match new_role:
		"CENTER": center_player_id = source_pid
		"QB": qb_player_id = source_pid
	
	# Si el jugador venía de OTRO rol especial, liberamos ese rol antiguo
	if source_pid == center_player_id and new_role != "CENTER":
		center_player_id = -1
	if source_pid == qb_player_id and new_role != "QB":
		qb_player_id = -1

	content_changed.emit()
	
func _update_player_data_position(player_node):
	var pos_data = {
		"position": player_node.position,
		"resource_path": player_node.data.resource_path if player_node.data else ""
	}
	_active_play_positions[player_node.player_id] = pos_data
	
	# Si tiene rutas, actualizamos el origen de la ruta también
	if route_manager:
		route_manager.update_route_origin(player_node.player_id, player_node.get_route_anchor())
	
func _auto_position_special_roles():
	var bounds = calculate_grid_bounds()
	var center_x = bounds.get_center().x
	var scrimmage_y = get_offensive_zone_limit_y()
	
	for child in nodes_container.get_children():
		if child is Area2D and "player_id" in child:
			if child.player_id == center_player_id:
				child.position = Vector2(center_x, scrimmage_y + (spacing * 0.2))
				child.set_role("CENTER")
			elif child.player_id == qb_player_id:
				child.position = Vector2(center_x, scrimmage_y + (spacing * qb_depth_offset))
				child.set_role("QB")
			
			var pos_data = {
				"position": child.position,
				"resource_path": child.data.resource_path if child.data else ""
			}
			_active_play_positions[child.player_id] = pos_data

func _show_toast_in_editor(message: String):
	print("[Editor]: ", message)
	if has_signal("content_changed"):
		content_changed.emit()

func set_visual_precision_mode(active: bool):
	if is_precision_mode_active != active:
		is_precision_mode_active = active
		
		# 1. Comunicar al cerebro matemático
		if route_manager:
			route_manager.set_precision_mode(active)
			
		#Rejilla Fina
		queue_redraw() 
		# Si es Preciso -> Ocultamos nodos grandes
		# Si es Simple -> Mostramos nodos grandes
		get_tree().call_group("GridMarkers", "set_visible", not active)
		
		if active:
			_show_toast_in_editor("Modo Precisión: ON")
		else:
			_show_toast_in_editor("Modo Precisión: OFF")

# --- DIBUJADO (View Logic) ---
func _draw():
	
	if is_precision_mode_active:
		_draw_precision_grid()

func _draw_precision_grid():
	# Dibujamos sobre el capture_frame
	if not capture_frame: return
	
	var rect = capture_frame.get_global_rect()
	# Convertimos coordenadas globales a locales para draw_line
	var local_rect = Rect2(to_local(rect.position), rect.size)
	
	var step = 10.0 
	var grid_color = Color(1, 1, 1, 0.15) # Blanco tenue transparente
	
	# Dibujar Verticales
	var x = local_rect.position.x
	while x <= local_rect.end.x:
		draw_line(Vector2(x, local_rect.position.y), Vector2(x, local_rect.end.y), grid_color, 1.0)
		x += step
		
	# Dibujar Horizontales
	var y = local_rect.position.y
	while y <= local_rect.end.y:
		draw_line(Vector2(local_rect.position.x, y), Vector2(local_rect.end.x, y), grid_color, 1.0)
		y += step
