extends Node

func _ready():
	# Detecta si es PC (Windows/Linux/macOS) o Web
	if OS.get_name() in ["Windows", "macOS", "Linux", "Web"]:
		set_pc_layout()
	else:
		set_mobile_layout()

func set_pc_layout():
	# Cambia la resolución a Horizontal para PC (1280x720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	
	# Lógica para centrar la ventana en el monitor
	var screen_size = DisplayServer.screen_get_size()
	var window_size = DisplayServer.window_get_size()
	var safe_pos = (screen_size / 2) - (window_size / 2)
	
	# Posición válida (Vector2i)
	DisplayServer.window_set_position(Vector2i(safe_pos.x, safe_pos.y))

func set_mobile_layout():
	# 1 equivale a SCREEN_ORIENTATION_PORTRAIT.
	DisplayServer.screen_set_orientation(1)
