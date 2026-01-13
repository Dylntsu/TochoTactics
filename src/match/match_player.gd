extends Node2D

# Arrastra tu escena match_player_body.tscn a esta variable en el Inspector
@export var player_scene: PackedScene 

@onready var container = %NodesContainer

func _ready():
	# Solo para probar hoy, vamos a spawnear uno manualmente
	test_spawn()

func test_spawn():
	var new_player = player_scene.instantiate()
	container.add_child(new_player)
	
	# Lo posicionamos en el centro del campo
	new_player.global_position = Vector2(960, 800) 
	
	# Le damos una ruta de prueba (una "L")
	var test_route = [
		Vector2(960, 500), # Sube
		Vector2(1200, 500) # Dobla a la derecha
	]
	new_player.active_route = test_route

# Conecta la señal 'pressed' de tu botón de "Play" a esta función
func _on_play_button_pressed():
	for player in container.get_children():
		if player.has_method("run_play"):
			player.is_running = true
