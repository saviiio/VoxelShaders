#version 330 compatibility
/* RENDERTARGETS: 0 */

const float GI_RAY_MAX_DIST = 48.0; // [16.0 24.0 32.0 48.0 64.0 96.0] Distância máxima de cálculo dos voxels.

#include "/programs/composite_main.fsh"
