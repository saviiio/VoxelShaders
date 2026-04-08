#version 330 compatibility

#define ALPHA_TEST_REF 0.1

uniform sampler2D gtexture;

#ifdef USE_ENTITY_COLOR
uniform vec4 entityColor;
#endif

in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 color;

void main() {
  vec4 albedo = texture(gtexture, texcoord) * glcolor;
#ifdef USE_ENTITY_COLOR
  albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
#endif
#ifdef ALPHA_TEST_REF
  if (albedo.a < ALPHA_TEST_REF) {
    discard;
  }
#endif
  color = albedo;
}
