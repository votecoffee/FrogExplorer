shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec3 shallow_color : source_color = vec3(0.21, 0.46, 0.34);
uniform vec3 deep_color : source_color = vec3(0.045, 0.24, 0.23);
varying vec3 world_position;
void vertex() {
 VERTEX.y += sin(VERTEX.x * 4.3 + TIME * 1.1) * 0.007 + cos(VERTEX.z * 5.1 - TIME * 0.8) * 0.005;
 world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 NORMAL = normalize(vec3(-cos(VERTEX.x*4.3+TIME*1.1)*0.0301,1.0,sin(VERTEX.z*5.1-TIME*0.8)*0.0255));
}
void fragment() {
 float wave = sin(world_position.x * 13.0 + TIME) * cos(world_position.z * 9.0 - TIME * 0.7);
 float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
 ALBEDO = mix(deep_color, shallow_color, 0.63 + wave * 0.08 + fresnel * 0.25) + vec3(0.04,0.09,0.07)*smoothstep(0.94,1.0,wave);
 ROUGHNESS = 0.24;
 METALLIC = 0.1;
 ALPHA = 0.55 + fresnel * 0.15;
}
