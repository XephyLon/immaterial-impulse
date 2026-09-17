#version 440

// The split's neck as a distance field (docs/proposals/motion-split.md §1,
// §6): the pill's rounded box and the band's half-plane, joined by a
// polynomial smooth-minimum whose radius is the neck - the bridge, its two
// concave flanks and the corners rounding are all the one blend, covered
// once, so nothing is antialiased against anything else (a drawn path under
// the pill composited to a hairline). The blend radius falls off along the
// band from the waist's centre, so the neck NARROWS to nothing at the pinch
// rather than letting go all at once - a flat edge over a flat band is the
// same distance everywhere, which a uniform blend bridges whole or not at
// all. The construction follows Clavis's pill_morph.frag
// (https://github.com/StatIndet/quickshell, GPL-3, see licenses/README.md).
//
// Every coordinate is in the item's own pixels, the box that
// dock_geometry.js `blendBox` lays out: the pill, the lift down to the band,
// and the blend's spill along it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 fillColor;
    vec4 pillRadii;
    vec2 resolution;
    vec2 pillCenter;
    vec2 pillSize;
    vec2 bandNormal;
    float bandOrigin;
    float blend;
    float waistHalf;
    float waistCenter;
    float softness;
};

// A rounded box with a radius per corner: x top-left, y top-right,
// z bottom-right, w bottom-left, y down. Selected with steps rather than
// branches for the GLSL ES 1.00 profile.
float roundedBox(vec2 p, vec2 halfSize, vec4 radii)
{
    float right = step(0.0, p.x);
    float bottom = step(0.0, p.y);
    float top = mix(radii.x, radii.y, right);
    float low = mix(radii.w, radii.z, right);
    float r = mix(top, low, bottom);
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float smoothMinimum(float a, float b, float k)
{
    if (k <= 0.001)
        return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

void main()
{
    vec2 p = qt_TexCoord0 * resolution;
    float pill = roundedBox(p - pillCenter, pillSize * 0.5, pillRadii);
    // The band: everything past its inner edge, in the direction of its normal.
    float band = bandOrigin - dot(p, bandNormal);
    // The blend, tapering along the band from the waist's centre to its ends.
    float along = dot(p, abs(vec2(bandNormal.y, bandNormal.x)));
    float u = waistHalf > 0.0 ? (along - waistCenter) / waistHalf : 2.0;
    float k = blend * max(0.0, 1.0 - u * u);
    float d = smoothMinimum(pill, band, k);
    float alpha = 1.0 - smoothstep(-softness, softness, d);
    fragColor = fillColor * alpha * qt_Opacity;
}
