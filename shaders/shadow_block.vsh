#version 330 compatibility

const float shadowDistanceRenderMul = 1.0; // [0.5 1.0 1.5 2.0 3.0 4.0] Distância de sombras configurável.

#include "/lib/shadow_shared.glsl"

out vec2 texcoord;
out vec4 glcolor;

void main() {
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
  glcolor = gl_Color;
  gl_Position = ftransform();
  gl_Position.xyz = distortShadowClipPos(gl_Position.xyz);
}
