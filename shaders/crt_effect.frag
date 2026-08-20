#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

out vec4 fragColor;

uniform vec2 uResolution;
uniform float uScanlineIntensity;
uniform float uVignetteIntensity;
uniform float uCurvature;
uniform float uPhosphorIntensity;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;

    // 1. CRT Barrel Curvature
    vec2 centeredUV = uv * 2.0 - 1.0;
    vec2 uvOffset = centeredUV.yx / vec2(6.0, 4.0);
    centeredUV += centeredUV * uvOffset * uvOffset * uCurvature;
    vec2 warpedUV = centeredUV * 0.5 + 0.5;

    // Outside distorted screen border -> darkened bezel
    if (warpedUV.x < 0.0 || warpedUV.x > 1.0 || warpedUV.y < 0.0 || warpedUV.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 0.9);
        return;
    }

    // 2. Analytical Horizontal Scanline Modulation
    float scanlineVal = sin(warpedUV.y * uResolution.y * 3.14159265);
    float scanlineDarkness = (1.0 - scanlineVal * scanlineVal) * uScanlineIntensity * 0.65;

    // 3. Phosphor Aperture Grille Micro-Tint
    float colPhase = mod(fragCoord.x, 3.0);
    vec3 phosphorTint = vec3(0.0);
    if (colPhase < 1.0) {
        phosphorTint = vec3(0.0, 0.05, 0.02) * uPhosphorIntensity;
    } else if (colPhase < 2.0) {
        phosphorTint = vec3(0.03, 0.0, 0.03) * uPhosphorIntensity;
    } else {
        phosphorTint = vec3(0.01, 0.01, 0.04) * uPhosphorIntensity;
    }

    // 4. Radial Vignette & Tube Corner Darkening
    vec2 vigCoord = (warpedUV - 0.5) * vec2(uResolution.x / uResolution.y, 1.0);
    float dist = length(vigCoord);
    float vignetteDarkness = smoothstep(0.4, 0.85, dist * (0.9 + uVignetteIntensity * 0.5)) * uVignetteIntensity;

    // 5. Total Darkening Alpha & Phosphor Emittance
    float totalAlpha = clamp(scanlineDarkness + vignetteDarkness, 0.0, 1.0);
    vec3 outRgb = phosphorTint * (1.0 - totalAlpha);

    fragColor = vec4(outRgb, totalAlpha);
}
