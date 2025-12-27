extends Node2D

# --- CONFIGURACIÓN TÉCNICA ---
@export var grid_size: Vector2 = Vector2(5, 11) # Basado en la imagen de referencia
@export var spacing: int = 50
@export var snap_distance: float = 40.0
@export var max_points: int = 15 # Límite de estamina por ruta

# --- VARIABLES DE ESTADO ---
var grid_points: Array[Vector2] = []
var node_visuals: Dictionary = {} 
var current_route: Array[Vector2] = []
var is_editing: bool = false 

# --- REFERENCIAS A NODOS ---
@onready var route_line = $RouteLine
@onready var preview_line = $PreviewLine
@onready var nodes_container = $NodesContainer

func _ready():
	# Alineación absoluta para evitar desvíos visuales
	nodes_container.position = Vector2.ZERO
	route_line.position = Vector2.ZERO
	preview_line.position = Vector2.ZERO
	
	generate_grid()
	preview_line.points = []

func generate_grid():
	# Cálculo para centrar la rejilla de 5x11 en la pantalla
	var grid_width_px = (grid_size.x - 1) * spacing
	var grid_height_px = (grid_size.y - 1) * spacing
	var screen_size = get_viewport_rect().size
	
	var start_offset = Vector2((screen_size.x - grid_width_px) / 2, (screen_size.y - grid_height_px) / 2)

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos = Vector2(x * spacing, y * spacing) + start_offset
			grid_points.append(pos)
			
			var marker = ColorRect.new()
			marker.size = Vector2(8, 8)
			marker.pivot_offset = Vector2(4, 4) 
			marker.position = pos - Vector2(4, 4) # Centrado perfecto
			marker.color = Color(1, 1, 1, 0.3) 
			
			nodes_container.add_child(marker)
			node_visuals[pos] = marker

func _input(event):
	var mouse_pos = get_local_mouse_position()
	
	# 1. CLIC IZQUIERDO (Selección y Dibujo)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			interact_with_node_at(mouse_pos)
	
	# 2. MOVIMIENTO (Preview Progresivo y Drag-to-Plot)
	elif event is InputEventMouseMotion:
		update_preview(mouse_pos)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			interact_with_node_at(mouse_pos)
	
	# 3. CLIC DERECHO (Finalizar Jugada)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		finish_route()

func interact_with_node_at(mouse_pos: Vector2):
	var closest = get_closest_node(mouse_pos)
	if closest == Vector2.INF: return

	if current_route.is_empty():
		start_new_route(closest)
		return

	# Lógica de Deselección (Retroceder en la ruta)
	if current_route.has(closest):
		var index = current_route.find(closest)
		current_route = current_route.slice(0, index + 1)
		update_visuals()
		animate_node_interaction(closest)
		return

	# Añadido Progresivo Inteligente
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
		
	var last_node = current_route.back()
	var step_vector = get_smart_step(last_node, mouse_pos)
	
	if step_vector == Vector2.ZERO:
		preview_line.points = []
		return

	var dist_to_mouse = last_node.distance_to(mouse_pos)
	var step_length = step_vector.length()
	var steps_wanted = clampi(int(round(dist_to_mouse / step_length)), 1, 3)
	
	var projected_points = [last_node]
	for i in range(1, steps_wanted + 1):
		var next_target = last_node + (step_vector * i)
		var real_node = get_closest_node(next_target)
		
		if real_node != Vector2.INF and not current_route.has(real_node):
			projected_points.append(real_node)
		else:
			break
			
	preview_line.points = projected_points if projected_points.size() > 1 else []
	preview_line.default_color = Color(1, 1, 1, 0.4)

# --- MATEMÁTICAS DE CONEXIÓN ---

func get_smart_step(from_pos: Vector2, mouse_pos: Vector2) -> Vector2:
	var dir = (mouse_pos - from_pos)
	if dir.length() < spacing * 0.5: return Vector2.ZERO
	
	# Detecta las 8 direcciones (Ortogonal y 45°)
	var step_direction = Vector2(round(dir.normalized().x), round(dir.normalized().y))
	return step_direction * spacing

func get_closest_node(pos: Vector2) -> Vector2:
	var closest = Vector2.INF
	var min_dist = snap_distance
	for point in grid_points:
		var dist = pos.distance_to(point)
		if dist < min_dist:
			min_dist = dist
			closest = point
	return closest

# --- FEEDBACK VISUAL ---

func update_visuals():
	route_line.points = current_route
	for pos in node_visuals:
		var node = node_visuals[pos]
		if not current_route.is_empty() and pos == current_route.back():
			node.color = Color.GREEN
			node.scale = Vector2(1.5, 1.5)
		else:
			node.color = Color(1, 1, 1, 0.3)
			node.scale = Vector2(1, 1)

	var stamina_percent = float(current_route.size()) / float(max_points)
	if stamina_percent < 0.5: route_line.default_color = Color.GREEN
	elif stamina_percent < 0.8: route_line.default_color = Color.YELLOW
	else: route_line.default_color = Color.RED

func animate_node_interaction(node_pos: Vector2):
	if node_visuals.has(node_pos):
		var tween = create_tween()
		tween.tween_property(node_visuals[node_pos], "scale", Vector2(2.0, 2.0), 0.1)
		tween.tween_property(node_visuals[node_pos], "scale", Vector2(1.0, 1.0), 0.1)

# --- FINALIZACIÓN Y GUARDADO ---

func start_new_route(start_pos: Vector2):
	is_editing = true
	current_route = [start_pos]
	update_visuals()
	animate_node_interaction(start_pos)

func finish_route():
	if current_route.size() >= 2:
		var new_route = PlayBookRoute.new()
		new_route.points = current_route.duplicate()
		bake_route_visuals()
	
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
