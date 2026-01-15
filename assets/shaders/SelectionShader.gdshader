shader_type canvas_item;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_thickness : hint_range(0, 10) = 1.0;
uniform float speed : hint_range(0, 10) = 2.0;
uniform bool is_selected = false;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	
	if (is_selected) {
		vec2 size = TEXTURE_PIXEL_SIZE * line_thickness;
		float outline = 0.0;
		
		// Detectar bordes del sprite
		for (float x = -1.0; x <= 1.0; x += 1.0) {
			for (float y = -1.0; y <= 1.0; y += 1.0) {
				if (x == 0.0 && y == 0.0) continue;
				outline += texture(TEXTURE, UV + vec2(x * size.x, y * size.y)).a;
			}
		}
		outline = sign(outline) * (1.0 - col.a);
		
		// Crear el efecto de línea punteada animada
		float pos = (UV.x + UV.y) * 10.0 + TIME * speed;
		float pattern = step(0.5, fract(pos * 0.5));
		
		vec4 final_color = mix(col, line_color, outline * pattern);
		COLOR = final_color;
	} else {
		COLOR = col;
	}
}