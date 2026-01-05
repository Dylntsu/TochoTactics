extends Node2D

# ==============================================================================
# COMPONENTES
# ==============================================================================
@onready var route_manager = $RouteManager
@onready var nodes_container = $NodesContainer
@onready var background = $CanvasLayer/Background 
@onready var capture_frame = $CaptureFrame


# ==============================================================================
# VARIABLES PARA EL INSPECTOR
# ==============================================================================
@export_group("Ajuste Manual de Formacion")
## que tan abajo aparece la linea de jugadores 
@export_range(0.0, 3.0) var formation_y_offset: float = 0.8
## cuanto se atrasa el qb respecto a los demas (yardas/spacing)
@export_range(-2.0, 2.0) var qb_depth_offset: float = 0.7

@export_group("Posicionamiento de Jugadores")
## que tan cerca del borde inferior aparecen los jugadores (multiplicador de spacing)
@export_range(0.5, 4.0) var spawn_vertical_offset: float = 1.5
## que tanto se adelanta el qb respecto a la linea (multiplicador de spacing)
@export_range(0.0, 2.0) var qb_advance_offset: float = 0.5

@export_group("Limites de Jugada")
## fila de la grilla donde empieza la zona de anotacion/limite superior
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

# estado local (solo visuales estaticos)
var grid_points: Array[Vector2] = []
var spacing: int = 0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================
func _ready():
	get_viewport().size_changed.connect(_on_viewport_resized)
	await get_tree().process_frame
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
	
	# usamos 'background.get_global_rect()' para los limites totales de la cancha
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
	for child in nodes_container.get_children():
		if child.name.begins_with("PlayerStart"):
			child.queue_free()

	var field_rect = background.get_global_rect()
	
	var formation_start_x = field_rect.position.x + (field_rect.size.x * formation_margin_left)
	var formation_end_x = field_rect.position.x + field_rect.size.x * (1.0 - formation_margin_right)
	var formation_width = formation_end_x - formation_start_x
	
	var limit_top_y = get_offensive_zone_limit_y()
	# margen de seguridad para que no toquen el borde inferior del campo
	var limit_bottom_y = field_rect.end.y - (spacing * 0.2)
	
	var limit_rect = Rect2(formation_start_x, limit_top_y, formation_width, limit_bottom_y - limit_top_y)

	# calculamos la posicion y base usando el offset del inspector
	var formation_y = limit_rect.end.y - (spacing * formation_y_offset) 
	
	var player_step = 0
	if player_count > 1: 
		player_step = formation_width / (player_count - 1)
	
	var qb_index = int(player_count / 2)
	
	for i in range(player_count):
		var player = player_scene.instantiate()
		player.player_id = i
		# asignamos el rectangulo antes de la posicion para que el setter interno valide
		player.limit_rect = limit_rect 
		
		var pos_x = formation_start_x + (i * player_step) if player_count > 1 else limit_rect.get_center().x
		var final_y = formation_y
		
		# posicionamos al qb atras
		if i == qb_index:
			final_y += spacing * qb_depth_offset 
			
		# margen interno estricto para evitar que aparezcan tocando la linea
		var safety_margin = spacing * 0.4
		final_y = clamp(final_y, limit_rect.position.y + safety_margin, limit_rect.end.y - safety_margin)
		pos_x = clamp(pos_x, limit_rect.position.x + safety_margin, limit_rect.end.x - safety_margin)
		
		player.position = Vector2(pos_x, final_y)
		player.save_starting_position() 
		# conexiones
		player.start_route_requested.connect(_on_player_start_route_requested)
		player.moved.connect(_on_player_moved)
		
		nodes_container.add_child(player)

func get_offensive_zone_limit_y() -> float:
	if grid_points.is_empty(): 
		return 0.0
	var limit_index = int(grid_size.y - offensive_limit_row_offset)
	if limit_index < 0: 
		limit_index = 0
	return grid_points[limit_index].y
# ==============================================================================
# INPUT (DELEGADO AL ROUTEMANAGER)
# ==============================================================================

func _input(event):
	var mouse_pos = get_local_mouse_position()
	
	# 1. logica de dibujo standard
	if event is InputEventMouseButton:
		# clic izquierdo: agregar nodo
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if route_manager.is_editing:
				route_manager.handle_input(mouse_pos)
			else:
				# si no estamos editando, intentamos agarrar una ruta existente
				_try_click_existing_route_end(mouse_pos)
		
		# clic derecho: terminar ruta
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			route_manager.finish_route()
			
	elif event is InputEventMouseMotion:
		# movimiento: actualizar preview
		route_manager.update_preview(mouse_pos)
		# dibujo sosteniendo
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and route_manager.is_editing:
			route_manager.handle_input(mouse_pos)

# funcion auxiliar para detectar clics en las puntas de las rutas
func _try_click_existing_route_end(mouse_pos: Vector2):
	var snap_range = route_manager._snap_distance # usamos la misma distancia de iman
	
	for pid in route_manager.active_routes:
		var line = route_manager.active_routes[pid]
		if line.get_point_count() > 0:
			var end_point = line.points[line.get_point_count() - 1]
			
			# si hicimos clic cerca del final de esta ruta
			if mouse_pos.distance_to(end_point) < snap_range:
				route_manager.resume_editing_route(pid)
				return # encontramos una, dejamos de buscar

# --- callbacks de jugadores ---

# 1. cuando el jugador pide iniciar ruta:
func _on_player_start_route_requested(player_node):
	var pid = player_node.player_id
	
	# caso a: el jugador ya tiene una ruta
	if route_manager.active_routes.has(pid):
		# en lugar de borrar y salir, le decimos al manager que reanude la edicion.
		route_manager.resume_editing_route(pid)
		return 

	# caso b: el jugador no tiene ruta
	# si estabamos dibujando a otro, guardamos esa primero
	if route_manager.is_editing and route_manager.current_player_id != pid:
		route_manager.finish_route()
	
	# iniciamos nueva ruta desde cero
	route_manager.try_start_route(pid, player_node.get_route_anchor())

# 2. cuando el jugador se mueve:
func _on_player_moved(player_node):
	# avisamos al manager para que actualice el origen de la linea.
	route_manager.update_route_origin(player_node.player_id, player_node.get_route_anchor())
	

## Detiene todas las animaciones de los jugadores en el lienzo
func stop_all_animations():
	for child in nodes_container.get_children():
		if child is Area2D and child.has_method("stop_animation"):
			child.stop_animation()

## Actualizamos el reset para que sea más profundo
func reset_current_play():
	stop_all_animations() # Primero frenamos todo
	route_manager.clear_all_routes() # Limpiamos líneas
	rebuild_editor() # Reubicamos jugadores

func _clear_routes() -> void:
	if route_manager:
		route_manager.clear_all_routes()

func _restore_initial_formation() -> void:
	# reusamos la logica de reconstruccion existente
	rebuild_editor()

# ==============================================================================
# PERSISTENCIA Y MEMENTO (LOGICA PLAY DATA)
# ==============================================================================

## genera el recurso playdata con el estado actual y captura miniatura
func get_play_resource() -> PlayData:
	var new_play = PlayData.new()
	new_play.timestamp = Time.get_unix_time_from_system()
	
	# guardar posiciones de jugadores
	for player in nodes_container.get_children():
		if "player_id" in player:
			new_play.player_positions[player.player_id] = player.position
	
	# guardar puntos de rutas
	for pid in route_manager.active_routes:
		var line = route_manager.active_routes[pid]
		if is_instance_valid(line):
			new_play.routes[pid] = line.points
			
	# capturar imagen para caratula
	new_play.preview_texture = await get_play_preview_texture()
	
	return new_play

## captura el area delimitada manualmente por el cuadro rojo
func get_play_preview_texture() -> ImageTexture:
	# esperamos que se renderice el frame actual
	await get_tree().process_frame
	await get_tree().process_frame
	
	# capturamos la pantalla completa
	var screenshot: Image = get_viewport().get_texture().get_image()
	
	# obtenemos la posicion y tamaño del cuadro manual
	# get_global_rect nos da las coordenadas exactas de tu rectangulo rojo
	var frame_rect: Rect2 = capture_frame.get_global_rect()
	
	# recorte de seguridad basado en el viewport
	var viewport_size = get_viewport().get_visible_rect().size
	var x = clamp(frame_rect.position.x, 0, viewport_size.x)
	var y = clamp(frame_rect.position.y, 0, viewport_size.y)
	var w = min(frame_rect.size.x, viewport_size.x - x)
	var h = min(frame_rect.size.y, viewport_size.y - y)
	
	var final_region = Rect2(x, y, w, h)

	# procesar el recorte
	if w > 0 and h > 0:
		var cropped_img = screenshot.get_region(final_region)
		# redimensionamos a un tamaño estandar para la lista ui
		cropped_img.resize(200, 250, Image.INTERPOLATE_LANCZOS)
		return ImageTexture.create_from_image(cropped_img)
	
	return null

#carga datos desde un recurso (disco) o snapshot (memoria)
func load_play_data(play_data) -> void:
	# limpiar el campo antes de cargar
	if route_manager:
		route_manager.clear_for_load()
	
	# manejo polimorfico para recursos o diccionarios
	var positions = play_data.get("player_positions") if play_data is Dictionary else play_data.player_positions
	var routes = play_data.get("routes") if play_data is Dictionary else play_data.routes
	
	for player in nodes_container.get_children():
		if player is Area2D: # y player.has_method("execute_route")
			# Buscamos la ruta guardada, si no existe devolvemos un array vacío
			var saved_route = play_data.routes.get(player.player_id, PackedVector2Array())
			
			# Asignación segura
			if "current_route" in player:
				player.current_route = saved_route
			
	# restaurar posiciones de jugadores
	_restore_player_positions(positions)
	# restaurar rutas
	_restore_routes(routes)

func _restore_player_positions(positions: Dictionary) -> void:
	for player in nodes_container.get_children():
		if "player_id" in player:
			var id = player.player_id
			if positions.has(id):
				player.position = positions[id]
				# emitimos la señal para que si hay una ruta iniciada, se mueva
				player.moved.emit(player)

func _restore_routes(routes: Dictionary) -> void:
	if route_manager:
		route_manager.load_routes_from_data(routes)

func play_current_play():
	# Obtenemos todas las rutas dibujadas actualmente
	# RouteManager tiene un método para devolver las rutas por ID
	var all_routes = route_manager.get_all_routes() 
	
	for player in nodes_container.get_children():
		if player is Area2D and player.has_method("play_route"):
			# Asignamos la ruta correspondiente al jugador según su ID
			# Si no tiene ruta dibujada, le pasamos un array vacío
			player.current_route = all_routes.get(player.player_id, PackedVector2Array())
			
			player.play_route()

## limpia y reinicia la formación antes de un nuevo preview
func prepare_preview():
	# Guardamos el estado actual para poder volver si fuera necesario
	# Reconstruimos para asegurar que todos inicien en el origen
	rebuild_editor()
	await get_tree().process_frame
	
## Desbloquea a todos los jugadores para que vuelvan a ser editables
func unlock_all_players():
	for child in nodes_container.get_children():
		if child is Area2D:
			child.input_pickable = true
			if child.has_method("stop_animation"):
				child.stop_animation()

## Restablece todo el lienzo al estado inicial de formación
func reset_formation_state():
	# detenemos cualquier animación activa antes de mover nada
	stop_all_animations()
	
	for child in nodes_container.get_children():
		if child is Area2D and child.has_method("reset_to_start"):
			# el jugador vuelve a su posición inicial guardada
			child.reset_to_start()
			
			# se fuerza al RouteManager a que mueva el 
			# inicio de la línea a la posición reseteada del jugador.
			if route_manager:
				route_manager.update_route_origin(child.player_id, child.get_route_anchor())
	
	# desbloqueamos el editor para permitir nuevas ediciones
	unlock_editor_for_editing()

## bloquea todo el sistema para la ejecución
func lock_editor_for_play():
	route_manager.set_locked(true)
	for child in nodes_container.get_children():
		if child is Area2D:
			child.input_pickable = false # evita que el mouse los detecte
			if child.has_method("stop_animation"):
				child.is_playing = true

## desbloquea todo para volver a editar
func unlock_editor_for_editing():
	route_manager.set_locked(false)
	for child in nodes_container.get_children():
		if child is Area2D:
			child.input_pickable = true
			if child.has_method("reset_to_start"):
				child.reset_to_start()
