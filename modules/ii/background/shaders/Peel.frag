#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
};

layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

void main()
{
    vec2 uv = qt_TexCoord0;
    float t = clamp(progress, 0.0, 1.0);

    if (t <= 0.0) {
        fragColor = texture(fromImage, uv) * qt_Opacity;
        return;
    }
    if (t >= 1.0) {
        fragColor = texture(toImage, uv) * qt_Opacity;
        return;
    }

    // Diagonal sweep. The reveal boundary alone carries the wipe; the layers do
    // not have to move, which is what keeps a lock/unlock from smearing.
    float diagonal = (uv.x + uv.y) * 0.5;
    float feather = 0.012;
    float reveal = 1.0 - smoothstep(t - feather, t + feather, diagonal);

    // Parallax: drift the two layers a little along the sweep axis so the fold
    // reads as a peel rather than a flat wipe. The outgoing layer trails behind
    // while the incoming layer settles into place as it is revealed. UVs are
    // clamped, so a small offset can never drag an out-of-range edge across the
    // screen the way the original unclamped 0.2 offset did.
    const vec2 axis = vec2(0.70710678, 0.70710678); // normalized (1, 1)
    float amount = 0.08;
    vec2 fromUv = clamp(uv - axis * (t * amount), 0.0, 1.0);
    vec2 toUv = clamp(uv + axis * ((1.0 - t) * amount), 0.0, 1.0);

    vec4 oldColor = texture(fromImage, fromUv);
    vec4 newColor = texture(toImage, toUv);

    // A restrained highlight along the fold preserves the Peel character without
    // distorting either wallpaper.
    float fold = 1.0 - smoothstep(0.0, feather * 2.5, abs(diagonal - t));
    vec3 color = mix(oldColor.rgb, newColor.rgb, reveal);
    color = mix(color, min(color * 1.08, vec3(1.0)), fold * 0.18);
    fragColor = vec4(color, mix(oldColor.a, newColor.a, reveal)) * qt_Opacity;
}
