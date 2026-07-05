shader_type canvas_item;

// Horizontal shear in world space so every CanvasItem a card is made of (frame,
// art, labels, badges) leans by the same amount and reads as one parallelogram.
// `pivot_y` is the card's global vertical centre; rows above it slide one way,
// rows below the other, keeping the card centred while its left/right edges tilt.
uniform float shear = 0.11;
uniform float pivot_y = 0.0;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	world.x -= (world.y - pivot_y) * shear;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 0.0, 1.0)).xy;
}
