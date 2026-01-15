extends Node2D

# ==============================================================================
# COMPONENTES
# ==============================================================================
@onready var route_manager = $RouteManager
@onready var nodes_container = $NodesContainer
@onready var background = $CanvasLayer/Background 
@onready var capture_frame = $CaptureFrame

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

# Array con las texturas de los jugadores
var player_textures = [
	preload("res://assets/players_icons/face_01.png"),
	preload("res://assets/players_icons/face_02.png"),
	preload("res://assets/players_icons/face_03.png"),
	preload("res://assets/players_icons/face_04.png"),
	preload("res://assets/players_icons/face_05.png"),
]
#roles
var qb_player_id: int = -1
var center_player_id: int = -1
#jjugador seleccionado
var selected_player_id: int = -1
# ESTADO LOCAL
var grid_points: Array[Vector2] = []
var spacing: int = 0

# --- Memoria Caché para posiciones ---
#  evita que los jugadores se reseteen al redimensionar la ventana
var _active_play_positions: Dictionary = {}

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================
func get_selected_player_id() -> int:
	return selected_player_id

func _ready():
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	# Esperamos dos frames para asegurar que el Layout de Godot se asentó
	await get_tree().process_frame
	await get_tree().process_frame
	
	if route_manager:
		var field = get_node_or_null("CanvasLayer/Background")
		
		if field:
			var rect = field.get_global_rect()
			
			# Si el rect sale en 0 o muy pequeño, intentamos forzarlo por su tamaño de textura
			if rect.size.x < 10:
				rect = Rect2(field.global_position, field.get_rect().size * field.global_scale)
			
			route_manager.limit_rect = rect
			print("Límites del campo verde (CORREGIDOS): ", route_manager.limit_rect)
		else:
			# Límites de emergencia 
			route_manager.limit_rect = Rect2(0, 0, 1280, 720)
			push_warning("Background no encontrado, usando límites por defecto")
		
		route_manager.route_modified.connect(_on_child_action_finished)
	
	rebuild_editor()

func _on_viewport_resized():
	rebuild_editor()

func rebuild_editor():
	var bounds = calculate_grid_bounds()
	var grid_data = GridService.calculate_grid(bounds, grid_size)
	
	grid_points = grid_data.points
	spacing = grid_data.spacing
	
	render_grid_visuals()
	render_formation() 
	
	# === CAPTURE FRAME ===
	if capture_frame:
		# Obtenemos el área exacta del nodo CaptureFrame
		var frame_rect = capture_frame.get_global_rect()
		route_manager.set_field_limits(frame_rect)
	
	# Setup normal para la grilla
	route_manager.setup(grid_points, spacing, background.get_global_rect())

# ==============================================================================
# RENDERIZADO (VISUALS)
# ==============================================================================
func calculate_grid_bounds() -> Rect2:
	var field_rect = background.get_global_rect()
	var x = field_rect.position.x + (field_rect.size.x * grid_margin_left)
	var y = field_rect.position.y + (field_rect.size.y * grid_margin_top)
	var width = field_rect.size.x * (1.0 - grid_margin_left - grid_margin_right)
	var height = field_rect.size.y * (1.0 - grid_margin_top - grid_margin_bottom)
	return Rect2(x, y, width, height)

func render_grid_visuals():
	for child in nodes_container.get_children():
		if not child.name.begins_with("PlayerStart"):
			child.queue_free()
			
	var marker_size = clamp(spacing * 0.12, 4, 12)
	for pos in grid_points:
		var marker = ColorRect.new()
		marker.size = Vector2(marker_size, marker_size)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.color = Color(1, 1, 1, 0.5)
		marker.position = pos - (marker.size / 2)
		nodes_container.add_child(marker)

func render_formation():
	# Limpieza de jugadores previos
	for child in nodes_container.get_children():
		if child.name.begins_with("PlayerStart") or child is Area2D:
			child.queue_free()

	var field_rect = background.get_global_rect()
	
	# Cálculos de límites y áreas de formación
	var formation_start_x = field_rect.position.x + (field_rect.size.x * formation_margin_left)
	var formation_end_x = field_rect.position.x + field_rect.size.x * (1.0 - formation_margin_right)
	var formation_width = formation_end_x - formation_start_x
	
	var limit_top_y = get_offensive_zone_limit_y() # La línea de No Running Zone
	var limit_bottom_y = field_rect.end.y - (spacing * 0.2)
	
	var limit_rect = Rect2(formation_start_x, limit_top_y, formation_width, limit_bottom_y - limit_top_y)
	var formation_y = limit_rect.end.y - (spacing * formation_y_offset) 
	
	var player_step = 0
	if player_count > 1: 
		player_step = formation_width / (player_count - 1)
	
	# El índice central que por defecto solía ser el QB
	var qb_index = int(player_count / 2)
	
	# Creación y configuración de jugadores
	for i in range(player_count):
		var player = player_scene.instantiate()
		player.player_id = i
		
		# --- LÓGICA DE IDENTIDAD VISUAL ---
		if player_textures.size() > 0:
			var tex = player_textures[i % player_textures.size()]
			player.setup_player_visual(tex, i)
		
		# --- POSICIONAMIENTO ---
		var pos_x = formation_start_x + (i * player_step) if player_count > 1 else limit_rect.get_center().x
		var final_y = formation_y
		
		# Aplicamos el desplazamiento de profundidad si es el índice central por defecto
		if i == qb_index:
			final_y += spacing * qb_depth_offset 
			
		var safety_margin = spacing * 0.4
		final_y = clamp(final_y, limit_rect.position.y + safety_margin, limit_rect.end.y - safety_margin)
		pos_x = clamp(pos_x, limit_rect.position.x + safety_margin, limit_rect.end.x - safety_margin)
		
		# Memoria de posición: Respetamos roles de Centro/QB guardados previamente
		if _active_play_positions.has(i):
			player.position = _active_play_positions[i]
		else:
			player.position = Vector2(pos_x, final_y)
		
		# --- CONFIGURACIÓN Y SEÑALES ---
		player.limit_rect = limit_rect 
		player.save_starting_position() 
		
		# Para detectar a qué jugador hacemos clic para designar roles
		if not player.input_event.is_connected(_on_player_input_event):
			player.input_event.connect(_on_player_input_event.bind(player))
		
		player.start_route_requested.connect(_on_player_start_route_requested)
		player.moved.connect(_on_player_moved)
		
		if not player.interaction_ended.is_connected(_on_child_action_finished):
			player.interaction_ended.connect(_on_child_action_finished)
		
		# Agregamos al contenedor
		nodes_container.add_child(player)
	
	if has_method("draw_snap_line"):
		draw_snap_line()

func draw_snap_line():
	if center_player_id != -1 and qb_player_id != -1:
		var center_node = _get_player_by_id(center_player_id)
		var qb_node = _get_player_by_id(qb_player_id)
		
		if center_node and qb_node:
			# Usamos el route_manager para dibujar una ruta fija naranja
			var points = PackedVector2Array([center_node.position, qb_node.position])
			route_manager.create_fixed_route(center_player_id, points, Color.ORANGE)

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
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if route_manager.is_editing:
				route_manager.handle_input(mouse_pos)
			else:
				_try_click_existing_route_end(mouse_pos)
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			route_manager.finish_route()
			
	elif event is InputEventMouseMotion:
		route_manager.update_preview(mouse_pos)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and route_manager.is_editing:
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

# --- callbacks de jugadores ---

func _on_player_start_route_requested(player_node):
	var pid = player_node.player_id
	
	if route_manager.active_routes.has(pid):
		route_manager.resume_editing_route(pid)
		return 

	if route_manager.is_editing and route_manager.current_player_id != pid:
		route_manager.finish_route()
	
	route_manager.try_start_route(pid, player_node.get_route_anchor())

func _on_player_moved(player_node):
	#guardamos donde quedó el jugador
	_active_play_positions[player_node.player_id] = player_node.position
	
	if route_manager:
		route_manager.update_route_origin(player_node.player_id, player_node.get_route_anchor())
	
func stop_all_animations():
	for child in nodes_container.get_children():
		if child is Area2D and child.has_method("stop_animation"):
			child.stop_animation()

func reset_current_play():
	stop_all_animations()
	route_manager.clear_all_routes()
	# Para que la nueva jugada use defaults
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
	
	# se usa formations consistentemente
	for player in nodes_container.get_children():
		if "player_id" in player:
			new_play.formations[player.player_id] = player.position 
	
	for pid in route_manager.active_routes:
		var line = route_manager.active_routes[pid]
		if is_instance_valid(line):
			new_play.routes[pid] = line.points
			
	new_play.preview_texture = await get_play_preview_texture()
	
	return new_play

func get_play_preview_texture() -> ImageTexture:
	await get_tree().process_frame
	await get_tree().process_frame
	
	var screenshot: Image = get_viewport().get_texture().get_image()
	var frame_rect: Rect2 = capture_frame.get_global_rect()
	var viewport_size = get_viewport().get_visible_rect().size
	
	var x = clamp(frame_rect.position.x, 0, viewport_size.x)
	var y = clamp(frame_rect.position.y, 0, viewport_size.y)
	var w = min(frame_rect.size.x, viewport_size.x - x)
	var h = min(frame_rect.size.y, viewport_size.y - y)
	
	var final_region = Rect2(x, y, w, h)

	if w > 0 and h > 0:
		var cropped_img = screenshot.get_region(final_region)
		cropped_img.resize(200, 250, Image.INTERPOLATE_LANCZOS)
		return ImageTexture.create_from_image(cropped_img)
	
	return null

func load_play_data(play_data) -> void:
	print("--- INICIANDO CARGA DE JUGADA ---")
	
	if has_method("reset_current_play"):
		# Hacemos limpieza manual segura para carga
		stop_all_animations()
		route_manager.clear_all_routes()
	
	var positions_data = {}
	var routes_data = {}
	
	if play_data is Resource:
		if "formations" in play_data:
			positions_data = play_data.formations
		if "routes" in play_data:
			routes_data = play_data.routes
			
	elif play_data is Dictionary:
		positions_data = play_data.get("formations", {})
		routes_data = play_data.get("routes", {})
	
	# Llenamos el caché con los datos del disco
	_active_play_positions = positions_data.duplicate()
	
	# Forzamos la reconstrucción para que render_formation use la memoria nueva
	rebuild_editor()
	
	# Sincronizamos rutas y detalles extra
	for child in nodes_container.get_children():
		if child is Area2D and "player_id" in child:
			var p_id = child.player_id
			if _active_play_positions.has(p_id):
				# Actualizamos casa para el reset
				child.save_starting_position()
				if route_manager:
					route_manager.update_route_origin(p_id, child.get_route_anchor(), true)

	# Restaurar rutas visuales
	if route_manager:
		route_manager.load_routes_from_data(routes_data)
		
	# Asignar rutas lógicas
	for player in nodes_container.get_children():
		if player is Area2D:
			var p_id = player.player_id
			var saved_route = routes_data.get(p_id, PackedVector2Array())
			if "current_route" in player:
				player.current_route = saved_route

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
	
	var formations = {}
	for player in nodes_container.get_children():
		if player is Area2D:
			formations[player.player_id] = player.starting_position
	data.formations = formations
	
	data.routes = route_manager.get_all_routes()
	
	return data

func _on_child_action_finished(_node = null):
	content_changed.emit()
	
func assign_role_to_player(p_id: int, new_role: String):
	if grid_points.is_empty(): return
	
	var bounds = calculate_grid_bounds()
	var center_x = bounds.get_center().x
	
	var base_limit_index = int(grid_size.y - offensive_limit_row_offset)
	
	var center_row_index = base_limit_index + 1
	var qb_row_index = base_limit_index + 2
	
	var center_y = grid_points[center_row_index].y
	var qb_y = grid_points[qb_row_index].y
	
	for child in nodes_container.get_children():
		if child is Area2D and "player_id" in child:
			if child.player_id == p_id:
				if new_role == "CENTER":
					child.position = Vector2(center_x, center_y)
					center_player_id = p_id
				elif new_role == "QB":
					child.position = Vector2(center_x, qb_y)
					qb_player_id = p_id
				
				# Guardamos para que el autoguardado lo procese
				_active_play_positions[child.player_id] = child.position
	
	draw_snap_line()
	content_changed.emit()
	
func _auto_position_special_roles():
	var bounds = calculate_grid_bounds()
	var center_x = bounds.get_center().x
	var scrimmage_y = get_offensive_zone_limit_y() # La línea de No Running
	
	for child in nodes_container.get_children():
		if child is Area2D and "player_id" in child:
			if child.player_id == center_player_id:
				# justo en la línea
				child.position = Vector2(center_x, scrimmage_y + (spacing * 0.2))
				child.set_role("CENTER")
			elif child.player_id == qb_player_id:
				# QB una yarda y media atrás
				child.position = Vector2(center_x, scrimmage_y + (spacing * qb_depth_offset))
				child.set_role("QB")
			
			# Guardar en memoria para que el autoguardado lo detecte
			_active_play_positions[child.player_id] = child.position

func _show_toast_in_editor(message: String):
	print("[Editor]: ", message)
	# Emitimos la señal para que la UI también pueda reaccionar si quiere
	if has_signal("content_changed"):
		content_changed.emit()

func _on_player_input_event(_viewport, event, _shape_idx, player_node):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Deseleccionamos visualmente a todos los jugadores previos
		for child in nodes_container.get_children():
			if child.has_method("set_selected"):
				child.set_selected(false)
		
		# Seleccionamos al nuevo jugador
		selected_player_id = player_node.player_id
		player_node.set_selected(true) # Activamos el shader
		
		_show_toast_in_editor("Jugador " + str(selected_player_id) + " seleccionado")

func deselect_all_players():
	for child in nodes_container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(false)
	selected_player_id = -1
