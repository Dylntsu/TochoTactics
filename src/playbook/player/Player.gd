extends Area2D

# ==============================================================================
# SEÑALES
# ==============================================================================
signal start_route_requested(player_node)
signal moved(player_node)
signal interaction_ended 

# ==============================================================================
# PROPIEDADES EXPORTADAS Y VARIABLES
# ==============================================================================
@export var player_id: int = 0
@onready var sprite = $Sprite2D 
@onready var label = $Label 
## Tamaño objetivo en píxeles que queremos que ocupen las cabezas
@export var target_head_size: float = 80.0

# Variable para guardar la ruta que se cargó desde el archivo
var current_route: PackedVector2Array = []
var starting_position: Vector2 # Para memorizar el origen

# Variables de estado para el arrastre manual
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var limit_rect: Rect2 = Rect2()

# Variable interna para controlar la animación activa
var _active_tween: Tween
var is_playing: bool = false

# Referencia al nodo visual
@onready var visual_panel = $Panel

# ==============================================================================
# CICLO DE VIDA (ESTILO Y MOVIMIENTO MANUAL)
# ==============================================================================
func _ready():
	if visual_panel:
		visual_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.4, 0.8, 1.0) # Azul
		style.set_corner_radius_all(20) # Redondo
		style.anti_aliasing = true
		visual_panel.add_theme_stylebox_override("panel", style)

func _process(_delta):
	if is_dragging:
		var target_pos = get_global_mouse_position() - drag_offset
		
		if limit_rect.has_area():
			var size_x = visual_panel.size.x if visual_panel else 64.0
			var size_y = visual_panel.size.y if visual_panel else 64.0
				
			var radius_x = (size_x * scale.x) / 2.0
			var radius_y = (size_y * scale.y) / 2.0
			
			var min_x = limit_rect.position.x + radius_x
			var max_x = limit_rect.end.x - radius_x
			var min_y = limit_rect.position.y + radius_y
			var max_y = limit_rect.end.y - radius_y
			
			if min_x > max_x: target_pos.x = limit_rect.get_center().x
			else: target_pos.x = clamp(target_pos.x, min_x, max_x)
				
			if min_y > max_y: target_pos.y = limit_rect.get_center().y
			else: target_pos.y = clamp(target_pos.y, min_y, max_y)
		
		global_position = target_pos
		moved.emit(self)

# ==============================================================================
# LÓGICA DE ANIMACIÓN (CONTROL PROFESIONAL)
# ==============================================================================

## Ejecuta la trayectoria guardada. Mata cualquier animación previa.
func play_route():
	if current_route.is_empty():
		return
		
	# Limpiamos cualquier animación que esté corriendo actualmente
	stop_animation()
		
	if is_dragging:
		stop_dragging()
		
	input_pickable = false # Bloquea clics mientras corre
	is_playing = true
	_active_tween = create_tween()
	
	var duration_per_point = 0.2
	
	for point in current_route:
		var center_offset = (visual_panel.size / 2.0) if visual_panel else Vector2.ZERO
		var target_pos = point - center_offset
		
		_active_tween.tween_property(self, "position", target_pos, duration_per_point)\
			.set_trans(Tween.TRANS_LINEAR)
	
	# Al finalizar, marcamos que ya no está reproduciendo
	_active_tween.finished.connect(func(): is_playing = false)

## Detiene el movimiento inmediatamente (Freno de mano)
func stop_animation():
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill() # Detiene el Tween en seco
	is_playing = false

## Devuelve el centro visual del jugador
func get_route_anchor() -> Vector2:
	var center_offset = (visual_panel.size / 2.0) if visual_panel else Vector2.ZERO
	return position + center_offset * scale

# ==============================================================================
# MANEJO DE ENTRADA
# ==============================================================================
func _input_event(_viewport, event, _shape_idx):
	# Si la jugada se está ejecutando, ignoramos cualquier clic
	if is_playing: 
		return
		
	#Solo permitimos dibujar si no estamos jugando
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_route_requested.emit(self)
		
	# igual solo permitimos arrastrar si no estamos jugando
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		start_dragging()

func _input(event):
	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		stop_dragging()

func start_dragging():
	is_dragging = true
	drag_offset = get_global_mouse_position() - global_position
	modulate.a = 0.7
	scale = Vector2(1.2, 1.2)
	z_index = 50

func stop_dragging():
	is_dragging = false
	modulate.a = 1.0
	scale = Vector2(1.0, 1.0)
	z_index = 20
	
	save_starting_position() 
	
	# avisamos que terminamos de interactuar
	interaction_ended.emit()

## Guarda la posición actual como el punto de inicio oficial
func save_starting_position():
	starting_position = position

## Regresa al jugador a su origen y permite volver a moverlo
func reset_to_start():
	stop_animation() # Detiene cualquier tween activo
	position = starting_position # Vuelve al inicio de la formación
	input_pickable = true # Permite clics de nuevo
	is_playing = false
	modulate.a = 1.0 # Restaura opacidad por si acaso

## Cambia la imagen del jugador y su número visual
func setup_player_visual(texture: Texture2D, id: int):
	# Asegurar referencias (Safe Access)
	if sprite == null: sprite = $Sprite2D
	if label == null: label = $Label
	
	if sprite and texture:
		sprite.texture = texture
		
		# --- LÓGICA DE ESCALADO AUTOMÁTICO ---
		var original_size = texture.get_size()
		# Evitamos división por cero si la textura está vacía
		if original_size.x > 0 and original_size.y > 0:
			# Buscamos el lado más largo (ancho o alto)
			var max_side = max(original_size.x, original_size.y)
			# Calculamos la escala necesaria para llegar al tamaño objetivo
			var scale_factor = target_head_size / max_side
			sprite.scale = Vector2(scale_factor, scale_factor)
			
			# Opcional: Centrar el sprite si no lo está en el editor
			sprite.centered = true
	
	if label:
		# Sincronizamos el número con el ID (ID 0 = Jugador 1)
		label.text = str(id + 1)
		# Posicionamos el label un poco arriba de la cabeza dinámicamente
		label.position.y = -(target_head_size / 2.0) - 15
