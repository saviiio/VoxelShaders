#version 330 compatibility
/* RENDERTARGETS: 0 */

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 c = texture(colortex0, uv).rgb;
    c = clamp(c, vec3(0.0), vec3(1.0e6));
    c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
    fragColor = vec4(c, 1.0);
}
