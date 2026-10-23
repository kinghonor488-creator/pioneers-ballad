// 逐格光照：把光照图（每个图块一个像素）按世界坐标采样，乘到画面颜色上。
// 光照图用线性过滤，所以格子之间的明暗是平滑过渡的。
shader_type canvas_item;

uniform sampler2D lightmap : filter_linear, repeat_disable;
uniform vec2 lm_origin = vec2(0.0);   // 光照图左上角的世界坐标（像素）
uniform vec2 lm_size = vec2(1.0);     // 光照图覆盖的世界范围（像素）
uniform bool enabled = true;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (enabled) {
		COLOR.rgb *= texture(lightmap, (world_pos - lm_origin) / lm_size).rgb;
	}
}
