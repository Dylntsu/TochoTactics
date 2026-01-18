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

# === BASE DE DATOS DE EQUIPO ===
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
		
		# 1. Selección visual en el campo
		deselect_all_players()
		selected_player_id = player_node.player_id
		player_node.set_selected(true)
		
		# 2. Actualizar el Panel Estático Lateral
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
	
	# CORRECCIÓN DE LÍMITES:
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
	# Limpieza de nodos anteriores
	for child in nodes_container.get_children():
		if child.name.begins_with("PlayerStart") or child is Area2D:
			child.queue_free()

	if player_count <= 0: return

	# 1. Definir el "Lienzo"
	var frame_rect = capture_frame.get_global_rect()
	var center_x = frame_rect.get_center().x
	
	# Margen de seguridad
	var available_width = frame_rect.size.x * 0.90 
	
	# 2. Lógica de Espaciado Adaptativo
	var ideal_separation = spacing * 1.5
	var final_separation = ideal_separation
	
	if player_count > 1:
		var total_ideal_width = (player_count - 1) * ideal_separation
		if total_ideal_width > available_width:
			final_separation = available_width / (player_count - 1)
	
	# Recalculamos el inicio
	var total_formation_width = (player_count - 1) * final_separation
	var start_x = center_x - (total_formation_width / 2.0)
	
	# Todos usarán esta misma altura base.
	var desired_y = frame_rect.end.y - (spacing * 1.5)
	var clamped_y = clamp(desired_y, frame_rect.position.y, frame_rect.end.y - (spacing * 0.5))
		
	for i in range(player_count):
		var player = player_scene.instantiate()
		player.player_id = i
		
		if team_database.size() > 0:
			player.data = team_database[i % team_database.size()]
		
		# --- POSICIONAMIENTO ---
		var pos_x = start_x + (i * final_separation)
		# CAMBIO PRINCIPAL: Todos usan exactamente la misma Y
		var pos_y = clamped_y 

		
		# Prioridad a la persistencia
		if _active_play_positions.has(i):
			var saved_pos_data = _active_play_positions[i]
			if saved_pos_data is Dictionary and saved_pos_data.has("position"):
				player.position = saved_pos_data.position
			elif saved_pos_data is Vector2:
				player.position = saved_pos_data
		else:
			player.position = Vector2(pos_x, pos_y)
		
		# --- LÍMITES FÍSICOS ---
		player.limit_rect = frame_rect 
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

	# ESTA SECCIÓN FUE RESTAURADA:
	elif event is InputEventMouseMotion:
		if route_manager.is_editing:
			# 1. Muestra la línea elástica (Preview)
			route_manager.update_preview(mouse_pos) 
			
			# 2. Permite dibujar arrastrando (si el click izquierdo está hundido)
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
	
	if route_manager.active_routes.has(pid):
		route_manager.resume_editing_route(pid)
		return 

	if route_manager.is_editing and route_manager.current_player_id != pid:
		route_manager.finish_route()
	
	route_manager.try_start_route(pid, player_node.get_route_anchor())

func _on_player_moved(player_node):
	var pos_data = {
		"position": player_node.position,
		"resource_path": player_node.data.resource_path if player_node.data else ""
	}
	_active_play_positions[player_node.player_id] = pos_data
	
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
	
	_active_play_positions = positions_data.duplicate()
	
	rebuild_editor()
	
	for child in nodes_container.get_children():
		if child is Area2D and "player_id" in child:
			var p_id = child.player_id
			if _active_play_positions.has(p_id):
				child.save_starting_position()
				if route_manager:
					route_manager.update_route_origin(p_id, child.get_route_anchor(), true)

	if route_manager:
		route_manager.load_routes_from_data(routes_data)
		
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
			formations[player.player_id] = {
				"position": player.starting_position,
				"resource_path": player.data.resource_path if player.data else ""
			}
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
				
				var pos_data = {
					"position": child.position,
					"resource_path": child.data.resource_path if child.data else ""
				}
				_active_play_positions[child.player_id] = pos_data
	content_changed.emit()
	
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
