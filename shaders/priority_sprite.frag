#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

out vec4 fragColor;

uniform sampler2D uSprite;
uniform sampler2D uPriority;

uniform vec4 uDstRect;
uniform vec4 uSrcRectPx;
uniform vec2 uTexSize;
uniform vec2 uPlayfieldSize;
uniform float uActorPri;
uniform float uFlipX;

void main() {
    // Continuous sampling (the drawImage model): never floor the fragment
    // coordinate in shader arithmetic. Floored playfield/texture selection
    // is precision-fragile at large fractional-scale coordinates -- on
    // macOS/Impeller at scales ~3.25-3.42 (and similar) inverse-transform
    // float error can leave a coordinate a hair below an integer boundary,
    // so floor() picks the neighbouring playfield pixel / texel and a
    // 1-device-pixel vertical seam of wrong texel or discarded sprite
    // appears inside door sprites. Instead, pass continuous coordinates
    // to texture() and let the sampler's nearest filtering
    // (FilterQuality.none, set by the helper) select the texel whose
    // footprint contains the fragment center in hardware. For all
    // non-tie coordinates that decision equals the old floor() decision,
    // and it stays robust when the coordinate carries float error. All
    // coordinates here are in playfield
    // units: FlutterFragCoord() is the fragment center in canvas space,
    // whose +0.5 already centres it in its playfield pixel, so no +0.5
    // texel-center offset is added.
    //
    // One tie-break remains: at fractional scales a fragment center can
    // land EXACTLY on a playfield/texel boundary (e.g. scale 6.5: device
    // px 6 maps to playfield 1.0). Hardware NEAREST has no floor
    // semantics there -- the two neighbouring texels are equidistant
    // from the sample point and the sampler picks the lower one, which
    // is the wrong texel (and, for priority, the wrong side of the
    // step, discarding the sprite's first column). The floor convention
    // this shader replaces picks the upper/right texel, so nudge the
    // continuous coordinate by 1e-3 playfield units toward it. Genuine
    // (non-tie) device-pixel centers at scale <= 20 sit >= ~0.02
    // playfield units from any boundary, and inverse-transform float
    // error is far below 1e-3, so the nudge only ever resolves exact
    // ties. Applying it to fc (not to srcPx) keeps the flipped mapping
    // correct: there, a larger localPx means a smaller srcPx, and the
    // nudge carries it across the same boundaries the old floor did.
    vec2 fc = FlutterFragCoord().xy + vec2(1e-3);
    vec2 localPx = fc - uDstRect.xy;
    // Note: SkSL (Skia backend) has no `discard`; emit fully transparent
    // black instead. With src-over blending this leaves the background.
    if (localPx.x < 0.0 || localPx.y < 0.0 || localPx.x >= uDstRect.z || localPx.y >= uDstRect.w) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 srcPx = uSrcRectPx.xy + localPx * (uSrcRectPx.zw / uDstRect.zw);
    if (uFlipX > 0.5) {
        srcPx.x = uSrcRectPx.x + uSrcRectPx.z - (localPx.x * (uSrcRectPx.z / uDstRect.z));
    }
    // Clamp into the source rect before sampling. With continuous
    // coordinates the flipped left edge (localPx.x == 0) lands exactly on
    // the rect's right edge, where nearest sampling would take the texel
    // just OUTSIDE the rect; the same holds, by float error, for the
    // unflipped right edge. Pulling the upper bound in by 1e-4 keeps
    // nearest selection on the last texel inside the rect.
    srcPx = clamp(srcPx, uSrcRectPx.xy, uSrcRectPx.xy + uSrcRectPx.zw - vec2(1e-4));
    vec4 sprite = texture(uSprite, srcPx / uTexSize);
    if (sprite.a == 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 pri = texture(uPriority, fc / uPlayfieldSize);
    float priAt = floor(pri.r * 15.0 + 0.5);
    if (priAt > uActorPri) {
        fragColor = vec4(0.0);
        return;
    }

    fragColor = sprite;
}
