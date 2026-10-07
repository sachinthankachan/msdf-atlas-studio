shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D msdf_texture : filter_linear;
uniform int field_type : hint_range(0, 3) = 2;
uniform float px_range = 4.0;

uniform bool is_shadow = false;

uniform vec4 text_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 1.0) = 0.0;
uniform bool outline_inward = true;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float shadow_softness : hint_range(0.001, 0.5) = 0.03;

float get_median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

float sample_field(vec4 tex, int type) {
    if (type == 0 || type == 1) {
        return tex.r;
    } else if (type == 2) {
        return get_median(tex.r, tex.g, tex.b);
    } else {
        float msd = get_median(tex.r, tex.g, tex.b);
        return min(msd, tex.a);
    }
}

void fragment() {
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    if (tex_size.x <= 1.0 || tex_size.y <= 1.0) {
        tex_size = vec2(1024.0, 1024.0);
    }

    vec2 unit_range = vec2(max(px_range, 1.0)) / tex_size;
    vec2 fw = max(fwidth(UV), vec2(0.00001));
    vec2 screen_tex_size = vec2(1.0) / fw;
    float screen_px_range = clamp(0.5 * dot(unit_range, screen_tex_size), 1.0, 100.0);

    vec4 tex = texture(TEXTURE, UV);
    float sd = sample_field(tex, field_type);

    if (is_shadow) {
        if (shadow_color.a <= 0.001) {
            discard;
        }
        float eff_out = clamp(outline_thickness * 0.48, 0.0, 0.48);
        float s_dist = sd - 0.5 + (outline_thickness > 0.001 ? eff_out : 0.0);
        float screen_dist = screen_px_range * s_dist;

        float soft_px = max(shadow_softness * screen_px_range * 6.0, 0.5);
        float shadow_alpha = smoothstep(-soft_px, soft_px, screen_dist) * shadow_color.a;

        // smoothly fade outer distance field boundary to avoid box clipping artifacts
        shadow_alpha *= smoothstep(0.01, 0.08, sd);

        if (shadow_alpha <= 0.001) {
            discard;
        }
        COLOR = vec4(shadow_color.rgb, shadow_alpha);
    } else {
        float outline_alpha = 0.0;
        float text_alpha = 0.0;

        if (outline_thickness > 0.001) {
            float eff_out = clamp(outline_thickness * 0.48, 0.0, 0.48);
            float eff_in = outline_inward ? clamp(outline_thickness * 0.28, 0.0, 0.28) : 0.0;

            float out_screen_dist = screen_px_range * (sd - (0.5 - eff_out));
            outline_alpha = clamp(out_screen_dist + 0.5, 0.0, 1.0);
            outline_alpha *= smoothstep(0.002, 0.03, sd);
            outline_alpha *= outline_color.a;

            float in_screen_dist = screen_px_range * (sd - (0.5 + eff_in));
            text_alpha = clamp(in_screen_dist + 0.5, 0.0, 1.0) * text_color.a;
        } else {
            float screen_px_dist = screen_px_range * (sd - 0.5);
            text_alpha = clamp(screen_px_dist + 0.5, 0.0, 1.0) * text_color.a;
        }

        vec4 col = vec4(0.0);
        if (outline_alpha > 0.0) {
            col = vec4(outline_color.rgb, outline_alpha);
        }
        col.rgb = mix(col.rgb, text_color.rgb, text_alpha);
        col.a = max(col.a, text_alpha);

        if (col.a <= 0.001) {
            discard;
        }
        COLOR = col;
    }
}
