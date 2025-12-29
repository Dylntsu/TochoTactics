extends Node2D

# ==============================================================================
# 1. CONFIGURACIÓN (DATA LAYER)
# ==============================================================================

@export_group("Grid Configuration")
@export var grid_size: Vector2 = Vector2(5, 8) 
@export var max_points: int = 6 
@export var snap_distance: float = 40.0 
# 3.0 significa que puede estirar la línea hasta 3 espacios de la rejilla, más allá no conecta.
@export var bridge_limit_multiplier: float = 3.0 

@export_group("Grid Precision Margins")

@export_range(0.0, 0.8) var grid_margin_top: float = 0.5    
@export_range(0.0, 0.5) var grid_margin_bottom: float = 0.02 
@export_range(0.0, 0.5) var grid_margin_left: float = 0.418   
@export_range(0.0, 0.5) var grid_margin_right: float = 0.417  

@export_group("Formation Configuration (Independent)")

@export_range(0.1, 1.0) var formation_spread_width: float = 0.169 
@export_range(0.0, 0.5) var formation_bottom_margin: float = 0.099
@export var player_count: int = 5 

# ==============================================================================
# 2. ESTADO (STATE LAYER)
# ==============================================================================
var grid_points: Array[Vector2] = []
var node_visuals: Dictionary = {} 
var current_route: Array[Vector2] = []
var spacing: int = 0
var is_editing: bool = false 
var dragged_player: Control = null 

# ==============================================================================
# 3. DEPENDENCIAS (UI LAYER)
# ==============================================================================
@onready var route_line = $RouteLine
@onready var preview_line = $PreviewLine
@onready var nodes_container = $NodesContainer
@onready var background = $CanvasLayer/Background 

# ==============================================================================
# 4. CICLO DE VIDA
# ==============================================================================
func _ready():
	get_viewport().size_changed.connect(_on_viewport_resized)
	await get_tree().process_frame
	rebuild_editor()

func _on_viewport_resized():
	rebuild_editor()

# ==============================================================================
# 5. LÓGICA CORE
# ==============================================================================
func rebuild_editor():
	clear_current_state()
	
	var bounds = calculate_grid_bounds()
	var grid_data = calculate_grid_positions(bounds)
	
	grid_points = grid_data.points
	spacing = grid_data.spacing
	snap_distance = spacing * 0.55 
	
	render_grid_visuals()
	render_formation() 

# ==============================================================================
# 6. CÁLCULOS MATEMÁTICOS
# ==============================================================================
func calculate_grid_bounds() -> Rect2:
	var field_rect = background.get_global_rect()
	
	var x = field_rect.position.x + (field_rect.size.x * grid_margin_left)
	var y = field_rect.position.y + (field_rect.size.y * grid_margin_top)
	var width = field_rect.size.x * (1.0 - grid_margin_left - grid_margin_right)
	var height = field_rect.size.y * (1.0 - grid_margin_top - grid_margin_bottom)
	
	return Rect2(x, y, width, height)

func calculate_grid_positions(bounds: Rect2) -> Dictionary:
	var calculated_points: Array[Vector2] = []
	
	var spacing_h = bounds.size.x / max(1, grid_size.x - 1)
	var spacing_v = bounds.size.y / max(1, grid_size.y - 1)
	
	var final_spacing_x = int(spacing_h)
	var final_spacing_y = int(spacing_v)
	var visual_spacing_ref = min(final_spacing_x, final_spacing_y)
	
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos_x = bounds.position.x + (x * final_spacing_x)
			var pos_y = bounds.position.y + (y * final_spacing_y)
			calculated_points.append(Vector2(pos_x, pos_y))
			
	return { "points": calculated_points, "spacing": int(visual_spacing_ref) }

func get_offensive_zone_limit_y() -> float:
	# Permite mover jugadores hasta la 3ra fila de nodos desde abajo
	if grid_points.is_empty(): return 0.0
	var limit_index = int(grid_size.y - 3) 
	if limit_index < 0: limit_index = 0
	return grid_points[limit_index].y

# ==============================================================================
# 7. RENDERIZADO (VISUALS)
# ==============================================================================
func clear_current_state():
	grid_points.clear()
	node_visuals.clear()
	preview_line.points = []
	for n in nodes_container.get_children():
		n.queue_free()

func render_grid_visuals():
	var marker_size = clamp(spacing * 0.12, 4, 12)
	for pos in grid_points:
		var marker = create_marker_node(marker_size)
		marker.position = pos - (marker.size / 2)
		nodes_container.add_child(marker)
		node_visuals[pos] = marker

func render_formation():
	for child in nodes_container.get_children():
		if child.name.begins_with("PlayerStart"):
			child.queue_free()

	var field_rect = background.get_global_rect()
	
	var total_formation_width = field_rect.size.x * formation_spread_width
	var formation_start_x = field_rect.position.x + (field_rect.size.x - total_formation_width) / 2
	var formation_y = (field_rect.position.y + field_rect.size.y) - (field_rect.size.y * formation_bottom_margin)
	
	var player_step = 0
	if player_count > 1:
		player_step = total_formation_width / (player_count - 1)
	
	var player_size = spacing * 0.4 
	var qb_index = int(player_count / 2) 
	
	for i in range(player_count):
		var player = create_player_node(player_size)
		player.name = "PlayerStart_" + str(i)
		
		var pos_x = 0
		if player_count > 1:
			pos_x = formation_start_x + (i * player_step)
		else:
			pos_x = field_rect.position.x + field_rect.size.x / 2
			
		var pos_y = formation_y
		if i == qb_index:
			pos_y += spacing * 0.8
			
		player.position = Vector2(pos_x - (player_size / 2), pos_y - (player_size / 2))
		nodes_container.add_child(player)

# --- FACTORY METHODS ---
func create_marker_node(size: float) -> Control:
	var marker = ColorRect.new()
	marker.size = Vector2(size, size)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.color = Color(1, 1, 1, 0.5) 
	return marker

func create_player_node(size: float) -> Panel:
	var node = Panel.new()
	node.size = Vector2(size, size)
	node.mouse_filter = Control.MOUSE_FILTER_PASS 
	node.z_index = 10
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.4, 0.8, 1.0) 
	style.set_corner_radius_all(int(size / 2)) 
	style.anti_aliasing = true 
	
	node.add_theme_stylebox_override("panel", style)
	return node

# ==============================================================================
# 8. INPUT E INTERACCIÓN
# ==============================================================================
func _input(event):
	var mouse_pos = get_local_mouse_position()
	
	# --- Click Derecho (Mover Jugadores) ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var clicked_player = get_player_at_pos(mouse_pos)
			if clicked_player: pick_up_player(clicked_player)
		else:
			if dragged_player: drop_player_freely(mouse_pos)

	# --- Click Izquierdo (Dibujar Rutas) ---
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var clicked_player = get_player_at_pos(mouse_pos)
			
			if clicked_player:
				if not current_route.is_empty() and is_point_near_player(current_route[0], clicked_player):
					finish_route() 
				else:
					start_new_route(clicked_player.position + (clicked_player.size/2))
			else:
				interact_with_node_at(mouse_pos)
	
	# --- Movimiento Mouse ---
	elif event is InputEventMouseMotion:
		if dragged_player != null:
			dragged_player.position = mouse_pos - (dragged_player.size / 2)
		else:
			update_preview(mouse_pos)
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				interact_with_node_at(mouse_pos)
	
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not dragged_player: finish_route()

# ==============================================================================
# 9. LÓGICA DE JUGADORES (DRAG & DROP)
# ==============================================================================
func get_player_at_pos(mouse_pos: Vector2) -> Control:
	for child in nodes_container.get_children():
		if child.name.begins_with("PlayerStart"):
			var rect = Rect2(child.position, child.size)
			if rect.has_point(mouse_pos): return child
	return null

func is_point_near_player(point: Vector2, player: Control) -> bool:
	var center = player.position + (player.size / 2)
	return point.distance_to(center) < player.size.x # Tolerancia simple

func pick_up_player(player: Control):
	dragged_player = player
	player.modulate.a = 0.7
	player.scale = Vector2(1.2, 1.2)
	player.z_index = 20 

func drop_player_freely(_mouse_pos: Vector2):
	var bounds = calculate_grid_bounds()
	var limit_top_y = get_offensive_zone_limit_y()
	var limit_bottom_y = bounds.end.y + (spacing * 5) 
	var limit_left = bounds.position.x
	var limit_right = bounds.end.x
	
	var final_center = dragged_player.position + (dragged_player.size / 2)
	final_center.x = clamp(final_center.x, limit_left, limit_right)
	final_center.y = clamp(final_center.y, limit_top_y, limit_bottom_y)
	
	dragged_player.position = final_center - (dragged_player.size / 2)
	dragged_player.modulate.a = 1.0
	dragged_player.scale = Vector2(1.0, 1.0)
	dragged_player.z_index = 10
	dragged_player = null

# ==============================================================================
# 10. LÓGICA DE RUTAS Y NODOS
# ==============================================================================
func interact_with_node_at(mouse_pos: Vector2):
	var closest = get_closest_node(mouse_pos)
	if closest == Vector2.INF: return
	if current_route.is_empty(): return

	if current_route.has(closest):
		var index = current_route.find(closest)
		current_route = current_route.slice(0, index + 1)
		update_visuals()
		animate_node_interaction(closest)
		return

	# Primer salto (Player -> Rejilla) 
	if current_route.size() == 1:
		var start_point = current_route[0]
		var dist = start_point.distance_to(closest)
		
		# VALIDACIÓN: Si está muy lejos, NO CONECTAR
		if dist > spacing * bridge_limit_multiplier:
			# futuros elementos
			return 
			
		current_route.append(closest)
		animate_node_interaction(closest)
		update_visuals()
		return

	# Caso: Ruta normal (Nodo -> Nodo)
	var last_node = current_route.back()
	var step_vector = get_smart_step(last_node, mouse_pos)
	
	if step_vector != Vector2.ZERO:
		var dist_to_mouse = last_node.distance_to(mouse_pos)
		var step_length = step_vector.length()
		var steps_wanted = clampi(int(round(dist_to_mouse / step_length)), 1, 3)
		
		for i in range(1, steps_wanted + 1):
			var next_target = last_node + (step_vector * i)
			var neighbor = get_closest_node(next_target)
			if neighbor != Vector2.INF and not current_route.has(neighbor):
				if current_route.size() < max_points:
					current_route.append(neighbor)
					animate_node_interaction(neighbor)
		update_visuals()

func update_preview(mouse_pos: Vector2):
	if not is_editing or current_route.is_empty():
		preview_line.points = []
		return
		
	var last_point = current_route.back()
	
	# Preview del Primer Salto (Player -> Rejilla)
	if current_route.size() == 1:
		var closest_grid_node = get_closest_node(mouse_pos)
		
		if closest_grid_node != Vector2.INF:
			# Verificamos distancia para color del preview
			var dist = last_point.distance_to(closest_grid_node)
			if dist > spacing * bridge_limit_multiplier:
				# Feedback visual de ERROR (Rojo)
				preview_line.points = [last_point, closest_grid_node]
				preview_line.default_color = Color(1, 0, 0, 0.5) 
			else:
				# Feedback visual de OK (Blanco)
				preview_line.points = [last_point, closest_grid_node]
				preview_line.default_color = Color(1, 1, 1, 0.5)
		else:
			# Línea elástica hacia el mouse (sin target)
			preview_line.points = [last_point, mouse_pos] 
			preview_line.default_color = Color(1, 1, 1, 0.2)
	else:
		# Preview Normal
		var step_vector = get_smart_step(last_point, mouse_pos)
		if step_vector == Vector2.ZERO:
			preview_line.points = []
			return
		
		var projected_points = [last_point]
		var next_target = last_point + step_vector
		var real_node = get_closest_node(next_target)
		if real_node != Vector2.INF and not current_route.has(real_node):
			projected_points.append(real_node)
			
		preview_line.points = projected_points if projected_points.size() > 1 else []
		preview_line.default_color = Color(1, 1, 1, 0.3)

# ==============================================================================
# 11. UTILIDADES Y VISUALES
# ==============================================================================
func get_smart_step(from_pos: Vector2, mouse_pos: Vector2) -> Vector2:
	var dir = (mouse_pos - from_pos)
	if dir.length() < spacing * 0.5: return Vector2.ZERO
	var step_direction = Vector2(round(dir.normalized().x), round(dir.normalized().y))
	return step_direction * spacing

func get_closest_node(pos: Vector2) -> Vector2:
	var closest = Vector2.INF
	var min_dist = snap_distance * 1.5 
	for point in grid_points:
		var dist = pos.distance_to(point)
		if dist < min_dist:
			min_dist = dist
			closest = point
	return closest

func update_visuals():
	route_line.points = current_route
	var connections_count = current_route.size() - 1
	var current_color = Color.GREEN 
	if connections_count <= 2: current_color = Color.GREEN
	elif connections_count == 3: current_color = Color.YELLOW
	else: current_color = Color.RED
	route_line.default_color = current_color
	for pos in node_visuals:
		var node = node_visuals[pos]
		if not current_route.is_empty() and pos == current_route.back():
			node.color = current_color
			node.scale = Vector2(1.4, 1.4) 
			node.z_index = 1 
		else:
			node.color = Color(1, 1, 1, 0.4)
			node.scale = Vector2(1, 1)
			node.z_index = 0

func animate_node_interaction(node_pos: Vector2):
	if node_visuals.has(node_pos):
		var tween = create_tween()
		tween.tween_property(node_visuals[node_pos], "scale", Vector2(1.8, 1.8), 0.1)
		tween.tween_property(node_visuals[node_pos], "scale", Vector2(1.0, 1.0), 0.1)

func start_new_route(start_pos: Vector2):
	is_editing = true
	current_route = [start_pos]
	update_visuals()

func finish_route():
	if current_route.size() >= 2: bake_route_visuals()
	is_editing = false
	current_route.clear()
	route_line.points = []
	preview_line.points = []
	update_visuals()

func bake_route_visuals():
	var permanent_line = Line2D.new()
	permanent_line.width = 4.0
	permanent_line.default_color = route_line.default_color
	permanent_line.points = current_route.duplicate()
	permanent_line.joint_mode = Line2D.LINE_JOINT_ROUND
	permanent_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(permanent_line)
	move_child(permanent_line, 0)
