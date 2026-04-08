#ifndef VOXEL_SHADOW_SHARED_GLSL
#define VOXEL_SHADOW_SHARED_GLSL

#include "/lib/common.glsl"

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition;

// Iris tutorial-compatible shadow utilities.
const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = true;

// Mantém a sombra estável em world-space, no espírito do le-lite.
const float SHADOW_LOCK = VOXEL_SIZE;

vec3 distortShadowClipPos(vec3 shadowClipPos) {
  float distortionFactor = max(length(shadowClipPos.xy), 1e-6);
  shadowClipPos.xy /= distortionFactor;
  shadowClipPos.z *= 0.2;
  return shadowClipPos;
}

vec3 worldToShadowScreenPos(vec3 worldPos, vec3 normal) {
  vec3 n = normalize(normal);
  vec3 lightDir = normalize(-shadowLightPosition);
  float ndotl = max(dot(n, lightDir), 0.0);
  float bias = slopeScaledShadowBias(ndotl);

  vec3 biasedWorldPos = worldPos + n * bias;
  vec3 lockedWorldPos = lockSceneToVoxelWorld(biasedWorldPos, SHADOW_LOCK);

  vec4 shadowClipPos = shadowProjection * (shadowModelView * vec4(lockedWorldPos, 1.0));
  shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
  return shadowClipPos.xyz / max(abs(shadowClipPos.w), 1e-6) * 0.5 + 0.5;
}

float sampleShadowVisibility(vec3 worldPos, vec3 normal) {
  vec3 n = normalize(normal);
  vec3 lightDir = normalize(-shadowLightPosition);
  float ndotl = max(dot(n, lightDir), 0.0);

  // Quando o sol está raso/atrás da superfície, não há contribuição direta útil.
  // Evita cintilação de shadow map em vales e ângulos extremos.
  if (ndotl <= 0.015) {
    return 1.0;
  }

  vec3 shadowScreenPos = worldToShadowScreenPos(worldPos, normal);

  if (shadowScreenPos.x < 0.0 || shadowScreenPos.x > 1.0 ||
      shadowScreenPos.y < 0.0 || shadowScreenPos.y > 1.0 ||
      shadowScreenPos.z < 0.0 || shadowScreenPos.z > 1.0) {
    return 1.0;
  }

  vec2 texelSize = 1.0 / vec2(textureSize(shadowtex0, 0));
  float depthBias = mix(0.0012, 0.00035, ndotl);
  float compareDepth = shadowScreenPos.z - depthBias;

  // PCF 2x2 estável: reduz flicker sem desfocar demais o estilo voxel.
  vec2 pcfBase = shadowScreenPos.xy - texelSize * 0.5;
  float visibility = 0.0;
  visibility += step(compareDepth, texture(shadowtex0, pcfBase + texelSize * vec2(0.0, 0.0)).r);
  visibility += step(compareDepth, texture(shadowtex0, pcfBase + texelSize * vec2(1.0, 0.0)).r);
  visibility += step(compareDepth, texture(shadowtex0, pcfBase + texelSize * vec2(0.0, 1.0)).r);
  visibility += step(compareDepth, texture(shadowtex0, pcfBase + texelSize * vec2(1.0, 1.0)).r);

  return visibility * 0.25;
}

float sampleShadowVisibility(vec3 worldPos) {
  return sampleShadowVisibility(worldPos, vec3(0.0, 1.0, 0.0));
}

#endif
