extends Sprite2D # O AnimatedSprite2D, según lo que estés usando

func _ready():
	# 1. Desconectamos el sprite de la jerarquía física
	top_level = true 
	
	# 2. Desactivamos el filtro de textura por código por si acaso
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta):
	var parent = get_parent()
	if not parent: return
	
	# --- CORRECCIÓN DE POSICIÓN ---
	# Obtenemos la posición del padre y la redondeamos
	var target_pos = parent.global_position
	global_position = target_pos.round()
	
	# --- CORRECCIÓN DE ESCALA (LA NUEVA MAGIA) ---
	# Obtenemos la escala del padre
	var parent_scale = parent.global_scale
	
	# Forzamos la escala a ser el entero más cercano (1, 2, 3...)
	# Esto evita que una escala de 0.9 o 1.1 rompa los píxeles.
	# Si tu juego usa zoom, esto mantendrá el sprite nítido saltando de tamaño
	# en lugar de estirarse suavemente.
	var x_scale = max(1.0, round(parent_scale.x))
	var y_scale = max(1.0, round(parent_scale.y))
	
	# Si quieres que el sprite SIEMPRE sea tamaño 1 (ignorando zoom del editor), usa:
	# global_scale = Vector2(1, 1)
	
	# Si quieres que respete el zoom pero sin romper píxeles (Integer Scaling):
	global_scale = Vector2(x_scale, y_scale)
