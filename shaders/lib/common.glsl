#ifndef VOXEL_COMMON_GLSL
#define VOXEL_COMMON_GLSL

vec3 encodeNormalToColor(vec3 n) {
  return n * 0.5 + 0.5;
}

vec3 decodeNormalFromColor(vec3 c) {
  return normalize(c * 2.0 - 1.0);
}

#define VOXEL_SIZE 1.0
#define SHADOW_STEPS 24
#define SKY_STEPS 32

// Iris / OptiFine: 0.0 desativa a oclusão ambiente vanilla.
const float ambientOcclusionLevel = 0.0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;

vec3 getCameraPositionBestFract() {
#ifdef CAMERA_POSITION_FRACT
    return cameraPositionFract;
#else
    // Arredonda para a grade de voxel mais próxima para maior estabilidade
    vec3 gridAligned = floor(cameraPosition / VOXEL_SIZE) * VOXEL_SIZE;
    return cameraPosition - gridAligned;
#endif
}

vec3 lockSceneToVoxelWorld(vec3 scenePos, float voxelSize) {
    float vs = max(voxelSize, 1e-4);
    vec3 cameraPositionBestFract = getCameraPositionBestFract();
    
    // Adiciona um pequeno offset para evitar flickering nas bordas dos voxels
    vec3 offsetPos = scenePos + cameraPositionBestFract + vec3(0.0001);
    vec3 voxelPos = offsetPos / vs;
    
    // Usa floor ao invés de round para comportamento mais previsível
    vec3 snapped = (floor(voxelPos + 0.5)) * vs - cameraPositionBestFract;
    return snapped;
}

float hash2(vec2 p) {
    return abs(sin(p.x * 12.7 + p.y * 31.1));
}

float linearizeDepth(float d) {
    float z = d * 2.0 - 1.0;
    return (2.0 * near * far) / (far + near - z * (far - near));
}

vec3 screenToView(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / max(view.w, 1e-6);
}

vec3 screenToWorld(vec2 uv, float depth) {
    vec4 world = gbufferModelViewInverse * vec4(screenToView(uv, depth), 1.0);
    return world.xyz;
}

vec2 worldToScreen(vec3 worldPos, out float viewDepth) {
    vec4 view = gbufferModelView * vec4(worldPos, 1.0);
    viewDepth = -view.z;
    vec4 clip = gbufferProjection * view;
    return clip.xy / max(clip.w, 1e-6) * 0.5 + 0.5;
}


vec3 rgbToHsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsvToRgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// HSL para manter o desenho de sombra sem mudar o estilo cromático do pacote.
vec3 rgbToHsl(vec3 c) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float h = 0.0;
    float s = 0.0;
    float l = 0.5 * (maxC + minC);
    float d = maxC - minC;

    if (d > 1e-6) {
        s = d / max(1.0 - abs(2.0 * l - 1.0), 1e-6);
        if (maxC == c.r) {
            h = mod((c.g - c.b) / d, 6.0);
        } else if (maxC == c.g) {
            h = ((c.b - c.r) / d) + 2.0;
        } else {
            h = ((c.r - c.g) / d) + 4.0;
        }
        h /= 6.0;
        if (h < 0.0) h += 1.0;
    }

    return vec3(h, s, l);
}

float hueToRgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0/2.0) return q;
    if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
    return p;
}

vec3 hslToRgb(vec3 c) {
    float h = c.x;
    float s = clamp(c.y, 0.0, 1.0);
    float l = clamp(c.z, 0.0, 1.0);

    if (s <= 1e-6) {
        return vec3(l);
    }

    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    return vec3(
        hueToRgb(p, q, h + 1.0/3.0),
        hueToRgb(p, q, h),
        hueToRgb(p, q, h - 1.0/3.0)
    );
}

vec3 applyIndirectLightHSV(vec3 albedo, vec3 indirectLight) {
    vec3 baseHsv = rgbToHsv(max(albedo, vec3(0.0)));
    vec3 lightHsv = rgbToHsv(max(indirectLight, vec3(0.0)));

    float lightValue = max(dot(indirectLight, vec3(0.299, 0.587, 0.114)), 0.0);
    baseHsv.z *= clamp(lightValue, 0.0, 8.0);
    baseHsv.s = clamp(mix(baseHsv.s, lightHsv.y, 0.22), 0.0, 1.0);
    baseHsv.x = mix(baseHsv.x, lightHsv.x, 0.08);

    return hsvToRgb(baseHsv);
}

vec3 applyShadowPreserveHueSaturation(vec3 color, float shadow, float saturationBoost) {
    vec3 hsl = rgbToHsl(max(color, vec3(0.0)));
    float s = clamp(shadow, 0.0, 1.0);

    // Mantém H/S e derruba apenas a Lightness.
    hsl.z *= s;
    hsl.y = clamp(hsl.y * saturationBoost, 0.0, 1.0);
    return hslToRgb(hsl);
}


float sunParallelShadowMask(float ndotl) {
    // Faces quase paralelas ao sol recebem zero de luz direta.
    // Isso evita listras e artefatos de shadow map em ângulos rasos.
    return smoothstep(0.22, 0.38, clamp(ndotl, 0.0, 1.0));
}

float slopeScaledShadowBias(float ndotl) {
    // Bias maior em ângulos rasos reduz acne/banding sem lavar sombras frontais.
    // Aumentado ligeiramente para maior estabilidade
    return mix(0.0065, 0.0018, clamp(ndotl, 0.0, 1.0));
}

float depthOccupancy(vec3 worldPos) {
    float sampleDepth;
    vec2 uv = worldToScreen(worldPos, sampleDepth);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    float sceneDepth = linearizeDepth(texture(depthtex0, uv).r);
    return sampleDepth > sceneDepth + 0.05 ? 1.0 : 0.0;
}

#endif