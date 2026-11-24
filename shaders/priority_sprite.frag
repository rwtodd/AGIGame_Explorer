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
    // Filter-proof texel-center snapping: texel SELECTION is done in shader
    // arithmetic (floor of continuous local coordinates) and the SAMPLER is
    // addressed at the selected texel's center. At a texel center, nearest
    // and linear filtering return the identical texel value, so the result
    // is the same under EITHER sampler filtering. That matters because
    // Impeller's runtime-effect image samplers may ignore the requested
    // FilterQuality.none and sample linearly; the previous continuous-UV
    // sampling then blended neighbouring texels, which is invisible for
    // SCI 1:1 cels at texel centers but destructive for AGI cels stretched
    // 2:1 horizontally (scaleX = 2), where sample points land at
    // quarter-texel positions and 1-texel details get washed out.
    // The shader now runs at native resolution in production (actors
    // layer), where fragment centers are exact half-integers, so the floor
    // selection is stable.
    //
    // One tie-break remains: at fractional scales a fragment center can
    // land EXACTLY on a playfield/texel boundary (e.g. scale 6.5: device
    // px 6 maps to playfield 1.0). Hardware NEAREST has no floor semantics
    // there -- the two neighbouring texels are equidistant from the sample
    // point and the sampler picks the lower one, which is the wrong texel
    // (and, for priority, the wrong side of the step, discarding the
    // sprite's first column). The floor convention this shader replaces
    // picks the upper/right texel, so nudge the continuous coordinate by
    // 1e-3 playfield units toward it. Genuine (non-tie) device-pixel
    // centers at scale <= 20 sit >= ~0.02 playfield units from any
    // boundary, and inverse-transform float error is far below 1e-3, so the
    // nudge only ever resolves exact ties. Applying it to fc (not to local
    // offsets) keeps the flipped mapping correct: there, a larger localPx
    // means a smaller texel index, and the nudge carries it across the same
    // boundaries the old floor did.
    vec2 fc = FlutterFragCoord().xy + vec2(1e-3);
    vec2 localPx = fc - uDstRect.xy;
    // Note: SkSL (Skia backend) has no `discard`; emit fully transparent
    // black instead. With src-over blending this leaves the background.
    if (localPx.x < 0.0 || localPx.y < 0.0 || localPx.x >= uDstRect.z || localPx.y >= uDstRect.w) {
        fragColor = vec4(0.0);
        return;
    }

    // Sprite texel selection + texel-center sampling (see header). floor()
    // here is now precision-safe: a coordinate a hair below an integer
    // boundary can only occur at an exact tie, where the 1e-3 nudge above
    // has already carried it across.
    vec2 texel = clamp(floor(localPx * (uSrcRectPx.zw / uDstRect.zw)), vec2(0.0), uSrcRectPx.zw - 1.0);
    if (uFlipX > 0.5) {
        texel.x = uSrcRectPx.z - 1.0 - texel.x;
    }
    vec4 sprite = texture(uSprite, (uSrcRectPx.xy + texel + 0.5) / uTexSize);
    if (sprite.a == 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 priTexel = clamp(floor(fc), vec2(0.0), uPlayfieldSize - 1.0);
    vec4 pri = texture(uPriority, (priTexel + 0.5) / uPlayfieldSize);
    float priAt = floor(pri.r * 15.0 + 0.5);
    if (priAt > uActorPri) {
        fragColor = vec4(0.0);
        return;
    }

    fragColor = sprite;
}
