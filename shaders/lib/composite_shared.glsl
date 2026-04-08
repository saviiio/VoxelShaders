#ifndef VOXEL_COMPOSITE_SHARED_GLSL
#define VOXEL_COMPOSITE_SHARED_GLSL

#include "/lib/shadow_shared.glsl"

in vec2 texcoord;
layout(location = 0) out vec4 color;

const float GI_VOXEL_SIZE = 1.0;
const float GI_RAY_START = 0.15;
const float GI_RAY_BIAS = 0.01;
const float GI_SURFACE_EPSILON = 0.08;

float saturate(float v) {
  return clamp(v, 0.0, 1.0);
}

float luminance(vec3 c) {
  return max(dot(c, vec3(0.299, 0.587, 0.114)), 0.0);
}

vec3 voxelCenterFromWorld(vec3 worldPos) {
  return lockSceneToVoxelWorld(worldPos, GI_VOXEL_SIZE);
}

vec3 voxelIndexFromWorld(vec3 worldPos) {
  vec3 cameraPositionBestFract = getCameraPositionBestFract();
  return floor((worldPos + cameraPositionBestFract) / GI_VOXEL_SIZE);
}

vec3 voxelCenterFromIndex(vec3 voxelIndex) {
  vec3 cameraPositionBestFract = getCameraPositionBestFract();
  return (voxelIndex + vec3(0.5)) * GI_VOXEL_SIZE - cameraPositionBestFract;
}

bool projectWorldToUv(vec3 worldPos, out vec2 uv, out float viewDepth) {
  uv = worldToScreen(worldPos, viewDepth);
  if (viewDepth <= 0.0) return false;
  return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

bool sampleVoxelAtCenter(vec3 voxelCenter, out vec3 voxelColor) {
  vec2 uv;
  float viewDepth;
  voxelColor = vec3(0.0);

  if (!projectWorldToUv(voxelCenter, uv, viewDepth)) {
    return false;
  }

  vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
  float halfDiag = 0.5 * GI_VOXEL_SIZE * 1.7321;
  float acceptance = halfDiag + GI_SURFACE_EPSILON + texel.x * 6.0;
  float bestDist = 1e9;
  bool found = false;

  for (int oy = -1; oy <= 1; ++oy) {
    for (int ox = -1; ox <= 1; ++ox) {
      vec2 suv = uv + vec2(float(ox), float(oy)) * texel;
      if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
        continue;
      }

      float z = texture(depthtex0, suv).r;
      if (z >= 0.999999) {
        continue;
      }

      vec3 sceneWorld = screenToWorld(suv, z);
      float d = distance(sceneWorld, voxelCenter);
      if (d > acceptance || d >= bestDist) {
        continue;
      }

      vec4 albedo = texture(colortex0, suv);
      if (albedo.a < 0.01) {
        continue;
      }

      bestDist = d;
      voxelColor = albedo.rgb;
      found = true;
    }
  }

  return found;
}

bool voxelOccupiedAtIndex(vec3 voxelIndex, out vec3 voxelColor) {
  vec3 center = voxelCenterFromIndex(voxelIndex);
  return sampleVoxelAtCenter(center, voxelColor);
}

bool voxelOccupied(vec3 worldPos, out vec3 voxelColor) {
  vec3 center = voxelCenterFromWorld(worldPos);
  return sampleVoxelAtCenter(center, voxelColor);
}

float traceVoxelRay(vec3 origin, vec3 rayDir, float maxDist, out vec3 hitColor) {
  vec3 dir = normalize(rayDir);
  vec3 ignoredVoxel = voxelIndexFromWorld(origin);
  vec3 pos = origin + dir * GI_RAY_START;
  vec3 voxel = voxelIndexFromWorld(pos);

  vec3 stepSign = sign(dir);
  stepSign = mix(vec3(1.0), stepSign, greaterThan(abs(dir), vec3(1e-5)));

  vec3 voxelMin = voxel * GI_VOXEL_SIZE;
  vec3 nextBoundary = voxelMin + (stepSign * 0.5 + 0.5) * GI_VOXEL_SIZE;

  vec3 invDir = 1.0 / max(abs(dir), vec3(1e-5));
  vec3 tMax = (nextBoundary - pos) * invDir;
  vec3 tDelta = GI_VOXEL_SIZE * invDir;

  float traveled = 0.0;
  hitColor = vec3(0.0);

  bool prevOccupied = false;
  bool prevValid = any(notEqual(voxel, ignoredVoxel));
  if (prevValid) {
    vec3 previousColor;
    prevOccupied = voxelOccupiedAtIndex(voxel, previousColor);
  }

  for (int i = 0; i < 96; ++i) {
    if (traveled > maxDist) {
      break;
    }

    if (tMax.x < tMax.y && tMax.x < tMax.z) {
      traveled = tMax.x;
      tMax.x += tDelta.x;
      voxel.x += stepSign.x;
    } else if (tMax.y < tMax.z) {
      traveled = tMax.y;
      tMax.y += tDelta.y;
      voxel.y += stepSign.y;
    } else {
      traveled = tMax.z;
      tMax.z += tDelta.z;
      voxel.z += stepSign.z;
    }

    if (all(equal(voxel, ignoredVoxel))) {
      prevValid = false;
      prevOccupied = false;
      continue;
    }

    vec3 currentColor;
    bool currentOccupied = voxelOccupiedAtIndex(voxel, currentColor);

    bool touchedAirFace = !prevValid || (!prevOccupied && currentOccupied);
    if (touchedAirFace && currentOccupied) {
      hitColor = currentColor;
      return traveled;
    }

    prevValid = true;
    prevOccupied = currentOccupied;
  }

  return maxDist + 1.0;
}

float traceShadow(vec3 origin, vec3 rayDir) {
  vec3 hitColor;
  float t = traceVoxelRay(origin, normalize(rayDir), GI_RAY_MAX_DIST, hitColor);
  return (t > GI_RAY_MAX_DIST) ? 1.0 : 0.0;
}

float traceSkyVisibility(vec3 origin) {
  vec3 skyDirs[5];
  skyDirs[0] = vec3(0.0, 1.0, 0.0);
  skyDirs[1] = normalize(vec3(0.8, 1.0, 0.0));
  skyDirs[2] = normalize(vec3(-0.8, 1.0, 0.0));
  skyDirs[3] = normalize(vec3(0.0, 1.0, 0.8));
  skyDirs[4] = normalize(vec3(0.0, 1.0, -0.8));

  float vis = 0.0;
  for (int i = 0; i < 5; ++i) {
    vec3 hitColor;
    float t = traceVoxelRay(origin, skyDirs[i], GI_RAY_MAX_DIST, hitColor);
    vis += (t > GI_RAY_MAX_DIST) ? 1.0 : 0.0;
  }
  return vis / 5.0;
}

vec3 traceVoxelBounce(vec3 origin, vec3 normal, float skyVis, vec3 selfAlbedo) {
  vec3 n = normalize(normal);

  vec3 rays[6];
  rays[0] = vec3(1.0, 0.0, 0.0);
  rays[1] = vec3(-1.0, 0.0, 0.0);
  rays[2] = vec3(0.0, 1.0, 0.0);
  rays[3] = vec3(0.0, -1.0, 0.0);
  rays[4] = vec3(0.0, 0.0, 1.0);
  rays[5] = vec3(0.0, 0.0, -1.0);

  vec3 accum = vec3(0.0);
  float wsum = 0.0;

  for (int r = 0; r < 6; ++r) {
    vec3 hit;
    float hitT = traceVoxelRay(origin, rays[r], GI_RAY_MAX_DIST, hit);
    float w = max(dot(n, rays[r]), 0.0);

    // Evita que a cor do próprio bloco volte como bounce indireto.
    // Isso reduz o efeito de auto-iluminação por GI.
    bool sameAsSelf = distance(hit, selfAlbedo) < 0.03;

    if (hitT <= GI_RAY_MAX_DIST && !sameAsSelf) {
      float hitBrightness = luminance(hit);
      accum += hit * hitBrightness * w;
      wsum += w * hitBrightness;
    } else {
      accum += vec3(0.0) * skyVis * w;
      wsum += w;
    }
  }

  return accum / max(wsum, 1e-4);
}

vec3 nearestVoxelColor(vec3 worldPos) {
  vec3 bestColor = vec3(1.0);
  float bestDist = 1e9;

  for (int x = -2; x <= 2; ++x) {
    for (int y = -2; y <= 2; ++y) {
      for (int z = -2; z <= 2; ++z) {
        vec3 p = worldPos + vec3(float(x), float(y), float(z)) * GI_VOXEL_SIZE;
        vec3 c;
        if (voxelOccupied(p, c)) {
          float d = distance(worldPos, voxelCenterFromWorld(p));
          if (d < bestDist) {
            bestDist = d;
            bestColor = c;
          }
        }
      }
    }
  }

  return bestColor;
}

vec3 applyVoxelLighting(vec3 albedo, vec3 packedLm, vec3 encodedNormal, vec2 uv) {
  vec3 n = decodeNormalFromColor(encodedNormal);
  float depth = texture(depthtex0, uv).r;

  if (depth >= 0.999999) {
    return albedo;
  }

  vec3 worldPos = screenToWorld(uv, depth);
  vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
  vec3 origin = worldPos + n * GI_RAY_BIAS;

  // Mantém a sombra exatamente no caminho original.
  float ndl = saturate(dot(n, sunDir));
  float sunMask = sunParallelShadowMask(ndl);
  float shadow = clamp(sampleShadowVisibility(worldPos, n), 0.0, 1.0);
  // Sombra aplicada em HSV: preserva a saturação e leva o Value a preto.
  float directStrength = ndl * sunMask;
  float directBrightness = 1.42;
  float directSaturationBoost = 1.0 + directStrength * 0.30;
  vec3 directBase = albedo * vec3(1.65, 1.52, 1.30) * directStrength * directBrightness;
  vec3 directColor = applyShadowPreserveHueSaturation(directBase, shadow, directSaturationBoost);

  // O pacote calcula a iluminação indireta após criar as sombras.
  float skyVis = saturate(traceSkyVisibility(origin + vec3(0.0, GI_RAY_BIAS * 2.0, 0.0)));
  vec3 bounce = traceVoxelBounce(origin, n, skyVis, albedo);

  float blockLight = saturate(max(packedLm.x, packedLm.y));
  vec3 torchLight = vec3(blockLight) * vec3(0.34, 0.31, 0.27);

  vec3 skyAmbient = vec3(0.0) * skyVis * saturate(n.y * 0.5 + 0.5);
  vec3 bounceLight = bounce * vec3(0.9, 0.95, 1.0) * skyVis;
  vec3 indirectLight = skyAmbient + bounceLight + torchLight;
  vec3 indirectColor = applyIndirectLightHSV(albedo, indirectLight);

  vec3 shaded = indirectColor + directColor;
  shaded = max(shaded, vec3(0.0));
  return shaded;
}

#endif
