extends Resource
class_name PlayerAttributes

@export_group("Movimiento")
@export var speed: float = 100.0 # Coeficiente de desplazamiento 
@export var agility: float = 1.0 # Factor de desaceleración post-giro 

@export_group("Habilidades")
@export var hands: float = 0.5  # Varianza estadística (RNG) para atrapes 
@export var arm_strength: float = 50.0 # Límites de fuerza máxima de pase 
@export var game_sense: float = 1.0 # Variable de umbral para evitar tropiezos 

@export_group("Estado")
@export var stamina_max: float = 100.0 # Rendimiento sostenido
