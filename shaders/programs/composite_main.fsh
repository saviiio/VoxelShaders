#include "/lib/composite_shared.glsl"

void main() {
  vec4 albedo = texture(colortex0, texcoord);
  float depth = texture(depthtex0, texcoord).r;

  if (depth >= 1.0) {
    color = albedo;
    return;
  }

  vec3 packedLm = texture(colortex1, texcoord).xyz;
  vec3 encodedNormal = texture(colortex2, texcoord).xyz;

  vec3 lit = applyVoxelLighting(albedo.rgb, packedLm, encodedNormal, texcoord);
  color = vec4(lit, albedo.a);
}
