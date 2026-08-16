#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

float overlayOpacityForBrightness(float x) {
    // Note: range 0 to 1

    // This coefficient is the only thing that separates the two rungs, and that
    // is deliberate: it was also the only difference between the pair
    // dots-hyprland shipped (0.42 against 0.75, both in 2212c9b7e). The ratio
    // between those two - 0.56 - is what places this rung under the 0.42 one
    // this shell calls Strong, so the ladder keeps upstream's spacing without
    // moving the step anyone is already using.
    float y = x*0.235;
    return min(max(y, 0.001), 1.0);
}

void main() {
    // 1. Get the current pixel color
    vec4 pixColor = texture(tex, v_texcoord);

    // 2. Calculate average screen brightness
    vec3 totalRGB = vec3(0.0);
    float samples = 0.0;

    // We use a nested loop to create a 10x10 grid (100 samples)
    // This is dense enough to catch small icons/text but light enough to run fast.
    for(float x = 0.05; x < 1.0; x += 0.1) {
        for(float y = 0.05; y < 1.0; y += 0.1) {
            totalRGB += texture(tex, vec2(x, y)).rgb;
            samples++;
        }
    }

    vec3 avgColor = totalRGB / samples;
    float globalBrightness = dot(avgColor, vec3(0.2126, 0.7152, 0.0722));

    // 3. Get the specific opacity for this brightness level
    float opacity = overlayOpacityForBrightness(globalBrightness);

    // 4. Apply the "black overlay" effect
    vec3 outColor = mix(pixColor.rgb, vec3(0.0), opacity);

    fragColor = vec4(outColor, pixColor.a);
}
