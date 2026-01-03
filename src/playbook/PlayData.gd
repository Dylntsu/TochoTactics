# PlayData.gd
extends Resource
class_name PlayData

@export var name: String = ""
@export var timestamp: float = 0.0
@export var player_positions: Dictionary = {}
@export var routes: Dictionary = {}
@export var preview_texture: Texture2D = null
