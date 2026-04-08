#version 330 compatibility

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aUV;

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProj;

out VS_OUT {
    vec3 worldPos;
    vec3 worldNormal;
    vec2 uv;
} vs_out;

void main() {
    vec4 worldPos4 = uModel * vec4(aPos, 1.0);
    vs_out.worldPos = worldPos4.xyz;

    // Normal em world-space (independente da rotação da câmera)
    mat3 normalMatrix = transpose(inverse(mat3(uModel)));
    vs_out.worldNormal = normalize(normalMatrix * aNormal);

    vs_out.uv = aUV;

    gl_Position = uProj * uView * worldPos4;
}
