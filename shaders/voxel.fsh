#version 330 compatibility

#include "/lib/common.glsl"
#include "/lib/shadow_shared.glsl"

in VS_OUT {
    vec3 worldPos;
    vec3 worldNormal;
    vec2 uv;
} fs_in;

out vec4 FragColor;

uniform vec3 uCameraWorldPos;
uniform vec3 uLightDirWorld; // Direção fixa em world-space
uniform vec3 uAlbedo = vec3(0.75, 0.85, 1.0);
uniform float uAmbientMin = 0.0;
uniform float uAmbientMax = 0.0;

// Coleta de luz/cor refletida em world-space (independente da câmera)
uniform vec3 uReflectorWorldPos = vec3(0.0, 64.0, 0.0);
uniform vec3 uReflectorColor = vec3(1.0, 0.9, 0.7);
uniform float uReflectorIntensity = 1.0;
uniform float uReflectorRange = 12.0;

// Controle de grade por voxel (estilo "lock" em world-space)
uniform float uVoxelSize = 1.0;
uniform bool uShadowLock = true;
uniform bool uWorldPosIsCameraRelative = false;
uniform bool uEnableWorldSpaceShadows = true;

void main() {
    // Reconstrói world-space absoluto quando a entrada vier relativa à câmera.
    vec3 worldSpacePos = fs_in.worldPos;
    if (uWorldPosIsCameraRelative) {
        worldSpacePos += uCameraWorldPos;
    }

    // Snap em grade world-space para estabilidade temporal por voxel.
    vec3 sampleWorldPos = worldSpacePos;
    if (uShadowLock) {
        sampleWorldPos = lockSceneToVoxelWorld(sampleWorldPos, max(uVoxelSize, 1e-4));
    }

    vec3 N = normalize(fs_in.worldNormal);
    vec3 L = normalize(-uLightDirWorld);
    float NdotL = max(dot(N, L), 0.0);
    float sunMask = sunParallelShadowMask(NdotL);
    float shadow = uEnableWorldSpaceShadows ? sampleShadowVisibility(sampleWorldPos, N) : 1.0;

    float ambientStrength = mix(uAmbientMin, uAmbientMax, clamp(NdotL, 0.0, 1.0));

    float reflectorDist = distance(sampleWorldPos, uReflectorWorldPos);
    float reflectorRange = max(uReflectorRange, 1e-4);
    float reflectorFalloff = clamp(1.0 - reflectorDist / reflectorRange, 0.0, 1.0);
    float reflectorBrightness = max(dot(uReflectorColor, vec3(0.299, 0.587, 0.114)), 0.0) * uReflectorIntensity;
    vec3 reflectorIndirect = uReflectorColor * reflectorBrightness * reflectorFalloff;

    vec3 indirectLight = vec3(ambientStrength) + reflectorIndirect;
    vec3 indirectColor = applyIndirectLightHSV(uAlbedo, indirectLight);

    float directStrength = NdotL * sunMask;
    float directBrightness = 1.48;
    float directSaturationBoost = 1.0 + directStrength * 0.38;
    vec3 directBase = uAlbedo * vec3(directStrength * directBrightness);
    vec3 directColor = applyShadowPreserveHueSaturation(directBase, shadow, directSaturationBoost);

    vec3 color = indirectColor + directColor;
    FragColor = vec4(max(color, vec3(0.0)), 1.0);
}
