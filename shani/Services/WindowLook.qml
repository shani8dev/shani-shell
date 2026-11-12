pragma Singleton
// How windows look and move under niri (Settings > Windows > Look and motion):
// how they open and close (a custom shader each: Glide, Pop or Dissolve, or
// niri's own), how fast everything moves, the shadow, the corners and how
// strong the frosted glass is. Written to ~/.config/niri/shani-look.kdl, which
// the desktop's niri config includes LAST, so these win over its defaults.
// Through NiriConfig: a file niri cannot read is put back.
//
// The shaders are niri's custom-shader interface (niri 26.04): open_color /
// close_color get the window's geometry coordinates ((0,0) top left, (1,1)
// bottom right) and sample niri_tex through niri_geo_to_tex. Textures are
// premultiplied, so fading is multiplying the whole colour.
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri/shani-look.kdl"
    readonly property var d: Settings.data

    // the accent as a GLSL vec3, for Dissolve's glowing edge
    readonly property string accentVec: {
        const c = Theme.accent;
        return "vec3(" + [c.r, c.g, c.b].map(x => x.toFixed(3)).join(", ") + ")";
    }

    readonly property var styles: ({
        // rises into place while it grows from a little smaller and fades in;
        // closes by sinking back and fading
        glide: {
            open: 'duration-ms 340\n        curve "ease-out-expo"',
            openShader: `
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float s = mix(0.88, 1.0, p);
    vec2 c = (coords_geo.xy - vec2(0.5)) / s + vec2(0.5);
    c.y -= (1.0 - p) * 0.035;
    if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0) return vec4(0.0);
    vec4 col = texture2D(niri_tex, (niri_geo_to_tex * vec3(c, 1.0)).st);
    return col * smoothstep(0.0, 0.55, p);
}`,
            close: 'duration-ms 220\n        curve "ease-out-quad"',
            closeShader: `
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float s = mix(1.0, 0.9, p);
    vec2 c = (coords_geo.xy - vec2(0.5)) / s + vec2(0.5);
    c.y -= p * 0.025;
    if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0) return vec4(0.0);
    vec4 col = texture2D(niri_tex, (niri_geo_to_tex * vec3(c, 1.0)).st);
    return col * (1.0 - smoothstep(0.0, 1.0, p));
}`
        },
        // springs open from small with a little bounce; shrinks away quickly
        pop: {
            open: 'spring damping-ratio=0.62 stiffness=650 epsilon=0.0001',
            openShader: `
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float s = mix(0.72, 1.0, niri_progress);
    vec2 c = (coords_geo.xy - vec2(0.5)) / s + vec2(0.5);
    if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0) return vec4(0.0);
    vec4 col = texture2D(niri_tex, (niri_geo_to_tex * vec3(c, 1.0)).st);
    return col * clamp(niri_clamped_progress * 2.5, 0.0, 1.0);
}`,
            close: 'duration-ms 170\n        curve "ease-out-quad"',
            closeShader: `
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float s = mix(1.0, 0.75, p);
    vec2 c = (coords_geo.xy - vec2(0.5)) / s + vec2(0.5);
    if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0) return vec4(0.0);
    vec4 col = texture2D(niri_tex, (niri_geo_to_tex * vec3(c, 1.0)).st);
    return col * (1.0 - p);
}`
        },
        // gathers from the top-left corner in small grains, with the accent
        // glowing along the edge that moves; leaves the same way
        dissolve: {
            open: 'duration-ms 560\n        curve "ease-out-cubic"',
            openShader: `
float grain(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + niri_random_seed * 91.7) * 43758.5453); }
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    if (coords_geo.x < 0.0 || coords_geo.x > 1.0 || coords_geo.y < 0.0 || coords_geo.y > 1.0) return vec4(0.0);
    float edge = 0.12;
    float v = mix(grain(floor(coords_geo.xy * size_geo.xy / 5.0)), (coords_geo.x + coords_geo.y) * 0.5, 0.55);
    float t = niri_clamped_progress * (1.0 + edge);
    if (v > t) return vec4(0.0);
    vec4 col = texture2D(niri_tex, (niri_geo_to_tex * coords_geo).st);
    float glow = 1.0 - smoothstep(0.0, edge, t - v);
    return vec4(mix(col.rgb, ACCENT * col.a, glow * 0.85), col.a);
}`,
            close: 'duration-ms 420\n        curve "ease-out-quad"',
            closeShader: `
float grain(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + niri_random_seed * 91.7) * 43758.5453); }
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    if (coords_geo.x < 0.0 || coords_geo.x > 1.0 || coords_geo.y < 0.0 || coords_geo.y > 1.0) return vec4(0.0);
    float edge = 0.12;
    float v = mix(grain(floor(coords_geo.xy * size_geo.xy / 5.0)), (coords_geo.x + coords_geo.y) * 0.5, 0.55);
    float t = niri_clamped_progress * (1.0 + edge);
    if (v < t - edge) return vec4(0.0);
    vec4 col = texture2D(niri_tex, (niri_geo_to_tex * coords_geo).st);
    float glow = 1.0 - smoothstep(0.0, edge, v - (t - edge));
    return vec4(mix(col.rgb, ACCENT * col.a, glow * 0.85), col.a);
}`
        }
    })

    readonly property var shadows: ({
        soft: ["softness 30", "spread 4", "offset x=0 y=6", "color \"#0006\"", "inactive-color \"#0004\""],
        deep: ["softness 55", "spread 6", "offset x=0 y=16", "color \"#000b\"", "inactive-color \"#0007\""]
    })
    readonly property var blurs: ({ light: [2, 2], medium: [3, 3], strong: [4, 4.5] })

    function shaderBlock(name, timing, shader) {
        return "    " + name + " {\n        " + timing + "\n        custom-shader r\"" + shader.replace(/ACCENT/g, root.accentVec) + "\n\"\n    }";
    }

    readonly property string kdl: {
        if (!Settings.loaded)
            return "";
        const moving = d.winAnimations && !d.reduceMotion;
        const st = root.styles[d.winMotion];
        const anim = !moving ? ["animations {", "    off", "}"]
            : ["animations {", "    slowdown " + Number(d.winSpeed || 1).toFixed(2)]
                .concat(st ? [root.shaderBlock("window-open", st.open, st.openShader), root.shaderBlock("window-close", st.close, st.closeShader)] : [])
                .concat(["}"]);
        const sh = root.shadows[d.winShadow];
        const bl = root.blurs[d.blurStrength] || root.blurs.medium;
        return [
            "// written by shani-shell: Settings > Windows > Look and motion. Edits here are replaced."
        ].concat(anim, [
            "layout {",
            "    shadow {",
            sh ? "        on\n        " + sh.join("\n        ") : "        off",
            "    }",
            "}",
            "window-rule {",
            "    geometry-corner-radius " + (d.winCorners | 0),
            "    clip-to-geometry " + (d.winCorners > 0 ? "true" : "false"),
            "}",
            // frosted glass a touch more saturated than what is behind it (as
            // macOS's), with a little noise so the gradients do not band
            "blur {",
            "    passes " + bl[0],
            "    offset " + bl[1],
            "    noise 0.02",
            "    saturation 1.25",
            "}",
            ""
        ]).join("\n");
    }

    onKdlChanged: if (kdl) write.restart()
    Timer {
        id: write
        interval: 300
        onTriggered: NiriConfig.write(root.path, root.kdl, Tr.t("how windows look and move"))
    }
}
