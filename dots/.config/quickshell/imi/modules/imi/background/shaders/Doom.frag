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

float hash(float n)
{
    return fract(sin(n * 12.9898) * 43758.5453);
}

// Value noise: smooth interpolation between hashed integer lattice points. This
// replaces the original 256-entry constant melt table, which SPIRV-Cross emitted
// as a `const int[256]` literal that the GLSL ES 1.00 profile rejects (issue #70,
// OpenGL 2.1-class backends), leaving the wallpaper blank. The noise reproduces
// the melt's locally-coherent-but-ragged per-column fall pattern closely rather
// than the exact Doom table values.
float valueNoise(float x)
{
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(hash(i), hash(i + 1.0), u);
}

// Per-column melt offset, normalized to [1.0, 2.0] to match the original
// (melt_height + 20) / 10.0 with melt_height in [-10, 0]. `mod(..., 256.0)`
// stands in for the original `& 255`, which needs GL_EXT_gpu_shader4 / #version
// 130 and is likewise unavailable on the ES 1.00 profile.
float getMeltTableValue(float x)
{
    float screenWidth = 360.0;
    float column = mod(floor(x * screenWidth), 256.0);
    return 1.0 + valueNoise(column * 0.125);
}

float melt_pattern(float x)
{
    return getMeltTableValue(x) * 2.0;
}

float inNormal(float x)
{
    return float((x >= 0.0) && (x <= 1.0));
}

void main()
{
    vec2 uv = qt_TexCoord0;
    float t = progress;
    float animationTime = clamp(t - 1.0, -1.0, 2.0);
    vec2 uv2 = uv;
    float acceleration = smoothstep(0.5, 1.0, t) * 0.5 + 1.0;
    float push = melt_pattern(uv.x) * 0.5 + animationTime * acceleration * 2.0;
    float maxPush = 2.0;
    push = clamp(push, 0.0, maxPush);
    uv2.y += push;
    vec4 topColor = texture(fromImage, uv2);
    vec4 bottomColor = texture(toImage, uv);
    vec4 mask = vec4(inNormal(uv2.y));
    fragColor = vec4(mask.xyz * topColor.xyz + bottomColor.xyz * (vec3(1.0) - mask.xyz), 1.0);
}
