#version 440

// The split's neck as a distance field (docs/proposals/motion-split.md §1,
// §6): the pill's rounded box and the band's half-plane, joined by a
// polynomial smooth-minimum whose radius is the neck - the bridge, its two
// concave flanks and the corners rounding are all the one blend, covered
// once, so nothing is antialiased against anything else (a drawn path under
// the pill composited to a hairline). The blend radius falls off along the
// band from the waist's centre, so the neck narrows in width to nothing at
// the pinch rather than letting go all at once - a flat edge over a flat band
// is the same distance everywhere, which a uniform blend bridges whole or not
// at all.
// Adapted from Clavis's assets/shaders/keystone/frag/pill_morph.frag
// https://github.com/StatIndet/quickshell (at 5183553)
// License: GPL-3.0 | upstream by StatIndet, which carries no copyright line
// and is GPL-3.0-or-later per its packaging; this adaptation is distributed
// under this repository's GPL-3.0 (licenses/GPL-3.0.txt). The rounded box
// and the smooth minimum are Inigo Quilez's published formulas. Details in
// licenses/README.md.
//
// Every coordinate is in the item's own pixels, the box that
// dock_geometry.js `splitBox` lays out for the whole motion: the pill at
// every lift and the lift down to the band.

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
    float pixelRatio;
    float reach;
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

// The joined field at a point, in item pixels.
float field(vec2 p)
{
    // The pill as the field sees it, reaching `reach` into the band so the
    // lift's first pixels, before the blend can bridge them, stay seamless.
    vec2 toward = bandNormal * (reach * 0.5);
    vec2 grow = abs(bandNormal) * (reach * 0.5);
    float pill = roundedBox(p - (pillCenter + toward), pillSize * 0.5 + grow, pillRadii);
    // The band: everything past its inner edge, in the direction of its
    // normal - with its zero-crossing one ramp INSIDE the band, so the ramp
    // never reaches the gap side of the edge (it tinted the gap's last row
    // along the whole box while the field painted, and the row stepped back
    // at the hand-over); inside the band the band's own surface covers it.
    float band = bandOrigin - dot(p, bandNormal) + softness;
    // The blend, tapering along the band from the waist's centre to its ends.
    float along = dot(p, abs(vec2(bandNormal.y, bandNormal.x)));
    float u = waistHalf > 0.0 ? (along - waistCenter) / waistHalf : 2.0;
    float k = blend * max(0.0, 1.0 - u * u);
    return smoothMinimum(pill, band, k);
}

void main()
{
    vec2 p = qt_TexCoord0 * resolution;
    float d = field(p);
    float px = softness / max(pixelRatio, 0.25);
    // Away from the outline the coverage is 0 or 1 whatever the gradient: the
    // ramp's half-width is the gradient (at most about 1.7 in this norm)
    // times one device pixel's softness, so four of those is clear of it.
    // Only the pixels on the edge pay for the four extra field evaluations -
    // the interior is most of the box, and on a software rasteriser the
    // per-pixel cost is the whole frame.
    if (abs(d) > 4.0 * px) {
        fragColor = d < 0.0 ? fillColor * qt_Opacity : vec4(0.0);
        return;
    }
    // Coverage over one DEVICE pixel of the field's own gradient: between
    // the pill's flat edge and the flat band the two fields' gradients
    // cancel and the blended field goes flat, so a ramp in field units
    // smeared over several pixels there (measured: a soft grey flank). The
    // gradient is taken by central differences rather than `fwidth`, which
    // the GLSL ES 1.00 profile only has behind GL_OES_standard_derivatives -
    // the profile an OpenGL 2.1-class backend gets (issue #70) - and floored
    // so the saddle between the flanks, where it goes to nothing, does not
    // alias.
    const float h = 0.5;
    float gx = field(p + vec2(h, 0.0)) - field(p - vec2(h, 0.0));
    float gy = field(p + vec2(0.0, h)) - field(p - vec2(0.0, h));
    float g = max((abs(gx) + abs(gy)) / (2.0 * h), 0.5);
    float w = g * px;
    float alpha = 1.0 - smoothstep(-w, w, d);
    fragColor = fillColor * alpha * qt_Opacity;
}
