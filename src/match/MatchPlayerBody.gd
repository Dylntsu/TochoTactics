extends CharacterBody2D

# --- ESTADÍSTICAS PARA LA UI AZUL ---
@export_group("Atleta Stats")
@export var player_name: String = "Idabel"
@export var speed_stat: int = 8
@export var hands_stat: int = 5
@export var stamina_stat: int = 7
@export var arm_stat: int = 6
@export var agility_stat: int = 4
@export var game_sense_stat: int = 5

# --- LÓGICA DE PARTIDO ---
var active_route: Array = []
var target_index: int = 0
var is_running: bool = false

@onready var anim = $Visuals/AnimatedSprite2D

func _ready():
	# Aseguramos que el personaje sea clickeable para actualizar la UI
	input_pickable = true

func _physics_process(_delta):
	# Si no se ha dado la orden de correr o no hay ruta, no hace nada
	if not is_running or active_route.is_empty():
		return

	# Obtenemos el punto actual de la ruta
	var target_pos = active_route[target_index]
	var direction = global_position.direction_to(target_pos)
	
	# Usamos el atributo 'speed' multiplicado por un factor para el movimiento real
	velocity = direction * (speed_stat * 25) 
	move_and_slide()
	
	# Cambiamos la animación según el movimiento (puedes expandir esto después)
	_update_animation_logic(direction)

	# Si llegamos al punto actual, pasamos al siguiente
	if global_position.distance_to(target_pos) < 10.0:
		target_index += 1
		# Si terminó la ruta, se detiene
		if target_index >= active_route.size():
			is_running = false
			anim.stop()

func _update_animation_logic(dir: Vector2):
	# Lógica básica para elegir la animación de tu AnimatedSprite2D
	if abs(dir.x) > abs(dir.y):
		anim.play("idabel_running_90") # O la animación lateral
	elif dir.y > 0:
		anim.play("idabel_running_front")
	else:
		anim.play("idabel_running_back")

# --- CONEXIÓN CON LA UI ---
func _input_event(_viewport, event, _shape_idx):
	# Cuando haces clic en el jugador durante el partido
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_send_data_to_ui()

func _send_data_to_ui():
	# Buscamos el nodo MatchUI en la escena principal para pasarle los datos
	var match_ui = get_tree().current_scene.find_child("MatchUI", true, false)
	if match_ui:
		# Llamamos a la función que actualiza tu panel azul
		match_ui.update_player_stats({
			"name": player_name,
			"speed": speed_stat,
			"hands": hands_stat,
			"stamina": stamina_stat,
			"arm": arm_stat,
			"agility": agility_stat,
			"game_sense": game_sense_stat
		})
