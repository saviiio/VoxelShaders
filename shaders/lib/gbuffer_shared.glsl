#ifndef VOXEL_GBUFFER_SHARED_GLSL
#define VOXEL_GBUFFER_SHARED_GLSL

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;

#ifdef USE_ENTITY_COLOR
uniform vec4 entityColor;
#endif

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 worldNormal;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outLight;
layout(location = 2) out vec4 outNormal;

void writeGbufferOutputs() {
  vec4 albedo = texture(gtexture, texcoord) * glcolor;

#ifdef USE_ENTITY_COLOR
  albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
#endif

#ifdef ALPHA_TEST_REF
  if (albedo.a < ALPHA_TEST_REF) {
    discard;
  }
#endif

  outColor = albedo;

  float materialTag = 0.0;
#ifdef USE_ENTITY_COLOR
  materialTag = 1.0;
#endif

  outLight = vec4(lmcoord, materialTag, 1.0);
  outNormal = vec4(encodeNormalToColor(worldNormal), 1.0);
}

#endif
