uniform mat4 gbufferModelViewInverse;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 worldNormal;

void main() {
  gl_Position = ftransform();
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
  lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
  lmcoord = lmcoord / (30.0 / 32.0) - (1.0 / 32.0);
  glcolor = gl_Color;

  vec3 viewNormal = gl_NormalMatrix * gl_Normal;
  worldNormal = mat3(gbufferModelViewInverse) * viewNormal;
}
