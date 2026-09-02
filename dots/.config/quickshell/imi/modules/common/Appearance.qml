import QtQuick
import Quickshell
import qs
import qs.modules.common.functions
import "interaction_motion.js" as InteractionMotion
import "motion_policy.js" as MotionPolicy
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    // The vendored expressive widget library's logical-pixel multiplier, and the
    // decision is that it stays 1.
    //
    // It is not dead: 629 call sites read it, and it multiplies real geometry -
    // `sizes.widgetGridSpanX/Y` and the drag lattice's gap go through it, so a
    // value other than 1 moves every desktop widget's box and every span the
    // store holds. It reads 1 because the shell already gets compositor/output
    // scaling for free: Quickshell hands each screen its device pixel ratio and
    // Qt lays the whole scene out in logical pixels, so a second multiplier here
    // is a second scaling of the same thing, applied to widget geometry only,
    // fighting the one the compositor already did.
    //
    // What it must NOT become is a hand-rolled zoom knob: the honest shape for
    // "make the shell bigger" is the compositor's scale, and the shape for "make
    // the corners rounder" is a rounding scale, which is its own decision
    // (docs/p3drovfx-animation-research-2026-08-16.md §3.7). Either would be a
    // declared setting with a migration, not this constant quietly leaving 1.
    // `tests/test_effective_scale_contract.py` fails on a second multiplier
    // declared beside it.
    readonly property real effectiveScale: 1.0
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    property QtObject interaction
    property QtObject colors
    property QtObject rounding
    property QtObject spacing
    property QtObject borderWidth
    property QtObject font
    property QtObject sizes
    property string syntaxHighlightingTheme
    readonly property int wallpaperTransitionDuration: 1200

    // Transparency. The quadratic functions were derived from analysis of hand-picked transparency values.
    ColorQuantizer {
        id: wallColorQuant
        property string wallpaperPath: (GlobalStates.lockLookActive && Config.options.background.lockWall !== "")
            ? Config.options.background.lockWall
            : Config.options.background.wallpaperPath
        property bool wallpaperIsVideo: wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm") || wallpaperPath.endsWith(".mkv") || wallpaperPath.endsWith(".avi") || wallpaperPath.endsWith(".mov")
        source: Qt.resolvedUrl(wallpaperIsVideo ? Config.options.background.thumbnailPath : wallpaperPath)
        depth: 0 // 2^0 = 1 color
        rescaleSize: 10
    }
    property real wallpaperVibrancy: (wallColorQuant.colors[0]?.hslSaturation + wallColorQuant.colors[0]?.hslLightness) / 2
    property real autoBackgroundTransparency: { // y = 0.5768x^2 - 0.759x + 0.2896
        let x = wallpaperVibrancy
        let y = 0.5768 * (x * x) - 0.759 * (x) + 0.2896
        return Math.max(0, Math.min(0.22, y)) - 0.12 * (m3colors.darkmode ? 0 : 1)
    }
    property real autoContentTransparency: 0.9
    property real backgroundTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoBackgroundTransparency : Config?.options.appearance.transparency.backgroundTransparency : 0
    property real contentTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoContentTransparency : Config?.options.appearance.transparency.contentTransparency : 0
    // The bar's own opacity is a third gated amount, declared here beside the
    // other two rather than inlined at colBarBackground: thinning an already
    // opaque colLayer0 by an ungated `bar.backgroundOpacity` left the bar, the
    // vertical bar, the pills and the hug corners see-through with transparency
    // *off* - for everyone who had ever moved that slider and for nobody else,
    // which is why a default of 1 hid it completely.
    property real barBackgroundTransparency: Config?.options.appearance.transparency.enable
        ? 1 - (Config?.options.bar.backgroundOpacity ?? 1) : 0

    m3colors: QtObject {
        property bool darkmode: true
        property bool transparent: false
        property color m3background: "#141313"
        property color m3onBackground: "#e6e1e1"
        property color m3surface: "#141313"
        property color m3surfaceDim: "#141313"
        property color m3surfaceBright: "#3a3939"
        property color m3surfaceContainerLowest: "#0f0e0e"
        property color m3surfaceContainerLow: "#1c1b1c"
        property color m3surfaceContainer: "#201f20"
        property color m3surfaceContainerHigh: "#2b2a2a"
        property color m3surfaceContainerHighest: "#363435"
        property color m3onSurface: "#e6e1e1"
        property color m3surfaceVariant: "#49464a"
        property color m3onSurfaceVariant: "#cbc5ca"
        property color m3inverseSurface: "#e6e1e1"
        property color m3inverseOnSurface: "#313030"
        property color m3outline: "#948f94"
        property color m3outlineVariant: "#49464a"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#cbc4cb"
        property color m3primary: "#cbc4cb"
        property color m3onPrimary: "#322f34"
        property color m3primaryContainer: "#2d2a2f"
        property color m3onPrimaryContainer: "#bcb6bc"
        property color m3inversePrimary: "#615d63"
        property color m3secondary: "#cac5c8"
        property color m3onSecondary: "#323032"
        property color m3secondaryContainer: "#4d4b4d"
        property color m3onSecondaryContainer: "#ece6e9"
        property color m3tertiary: "#d1c3c6"
        property color m3onTertiary: "#372e30"
        property color m3tertiaryContainer: "#31292b"
        property color m3onTertiaryContainer: "#c1b4b7"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3primaryFixed: "#e7e0e7"
        property color m3primaryFixedDim: "#cbc4cb"
        property color m3onPrimaryFixed: "#1d1b1f"
        property color m3onPrimaryFixedVariant: "#49454b"
        property color m3secondaryFixed: "#e6e1e4"
        property color m3secondaryFixedDim: "#cac5c8"
        property color m3onSecondaryFixed: "#1d1b1d"
        property color m3onSecondaryFixedVariant: "#484648"
        property color m3tertiaryFixed: "#eddfe1"
        property color m3tertiaryFixedDim: "#d1c3c6"
        property color m3onTertiaryFixed: "#211a1c"
        property color m3onTertiaryFixedVariant: "#4e4447"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color term0: "#EDE4E4"
        property color term1: "#B52755"
        property color term2: "#A97363"
        property color term3: "#AF535D"
        property color term4: "#A67F7C"
        property color term5: "#B2416B"
        property color term6: "#8D76AD"
        property color term7: "#272022"
        property color term8: "#0E0D0D"
        property color term9: "#B52755"
        property color term10: "#A97363"
        property color term11: "#AF535D"
        property color term12: "#A67F7C"
        property color term13: "#B2416B"
        property color term14: "#8D76AD"
        property color term15: "#221A1A"
    }

    colors: QtObject {
        property color colSubtext: m3colors.m3outline
        // Layer 0
        property color colLayer0Base: ColorUtils.mix(m3colors.m3background, m3colors.m3primary, Config.options.appearance.extraBackgroundTint ? 0.99 : 1)
        property color colLayer0: ColorUtils.transparentize(colLayer0Base, root.backgroundTransparency)
        property color colOnLayer0: m3colors.m3onBackground
        property color colLayer0Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.9, root.contentTransparency))
        property color colLayer0Active: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.8, root.contentTransparency))
        // Thinned by the same amount as colLayer0, not mixed with it: mixing an
        // opaque outline with a thinned fill left the border at 0.4 + 0.6 of the
        // fill's alpha, an opaque ring around a see-through plate as the shell
        // opacity slider went down.
        property color colLayer0Border: ColorUtils.transparentize(ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0Base, 0.4), root.backgroundTransparency)
        // The bar's own background chrome (bar/pill fills, hug corners) thins
        // colLayer0 by the user's bar opacity (Config.options.bar.backgroundOpacity,
        // 1 = fully opaque = unchanged). Kept separate from colLayer0 so only the
        // bar goes translucent. The amount comes from root.barBackgroundTransparency
        // rather than from the raw setting, so it genuinely composes with — instead
        // of reintroducing the translucency colLayer0 has just been made to drop.
        property color colBarBackground: ColorUtils.transparentize(colLayer0, root.barBackgroundTransparency)
        // Layer 1
        property color colLayer1Base: m3colors.m3surfaceContainerLow
        property color colLayer1: ColorUtils.solveOverlayColor(colLayer0Base, colLayer1Base, 1 - root.contentTransparency);
        property color colOnLayer1: m3colors.m3onSurfaceVariant;
        property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45);
        property color colLayer1Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.92), root.contentTransparency)
        property color colLayer1Active: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.85), root.contentTransparency);
        // Layer 2
        property color colLayer2Base: m3colors.m3surfaceContainer
        property color colLayer2: ColorUtils.solveOverlayColor(colLayer1Base, colLayer2Base, 1 - root.contentTransparency)
        property color colLayer2Hover: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.90), 1 - root.contentTransparency)
        property color colLayer2Active: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.80), 1 - root.contentTransparency);
        property color colLayer2Disabled: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, m3colors.m3background, 0.8), 1 - root.contentTransparency);
        property color colOnLayer2: m3colors.m3onSurface;
        property color colOnLayer2Disabled: ColorUtils.mix(colOnLayer2, m3colors.m3background, 0.4);
        // Layer 3
        property color colLayer3Base: m3colors.m3surfaceContainerHigh
        property color colLayer3: ColorUtils.solveOverlayColor(colLayer2Base, colLayer3Base, 1 - root.contentTransparency)
        property color colLayer3Hover: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.90), 1 - root.contentTransparency)
        property color colLayer3Active: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.80), 1 - root.contentTransparency);
        property color colOnLayer3: m3colors.m3onSurface;
        // Layer 4
        property color colLayer4Base: m3colors.m3surfaceContainerHighest
        property color colLayer4: ColorUtils.solveOverlayColor(colLayer3Base, colLayer4Base, 1 - root.contentTransparency)
        property color colLayer4Hover: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.90), 1 - root.contentTransparency)
        property color colLayer4Active: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.80), 1 - root.contentTransparency);
        property color colOnLayer4: m3colors.m3onSurface;
        // Primary
        property color colPrimary: m3colors.m3primary
        property color colOnPrimary: m3colors.m3onPrimary
        property color colPrimaryHover: ColorUtils.mix(colors.colPrimary, colLayer1Hover, 0.87)
        property color colPrimaryActive: ColorUtils.mix(colors.colPrimary, colLayer1Active, 0.7)
        property color colPrimaryContainer: m3colors.m3primaryContainer
        property color colPrimaryContainerHover: ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.9)
        property color colPrimaryContainerActive: ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.8)
        property color colOnPrimaryContainer: m3colors.m3onPrimaryContainer
        // Secondary
        property color colSecondary: m3colors.m3secondary
        property color colSecondaryHover: ColorUtils.mix(m3colors.m3secondary, colLayer1Hover, 0.85)
        property color colSecondaryActive: ColorUtils.mix(m3colors.m3secondary, colLayer1Active, 0.4)
        property color colOnSecondary: m3colors.m3onSecondary
        property color colSecondaryContainer: m3colors.m3secondaryContainer
        property color colSecondaryContainerHover: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.90)
        property color colSecondaryContainerActive: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.54)
        property color colOnSecondaryContainer: m3colors.m3onSecondaryContainer
        // Tertiary
        property color colTertiary: m3colors.m3tertiary
        property color colTertiaryHover: ColorUtils.mix(m3colors.m3tertiary, colLayer1Hover, 0.85)
        property color colTertiaryActive: ColorUtils.mix(m3colors.m3tertiary, colLayer1Active, 0.4)
        property color colTertiaryContainer: m3colors.m3tertiaryContainer
        property color colTertiaryContainerHover: ColorUtils.mix(m3colors.m3tertiaryContainer, m3colors.m3onTertiaryContainer, 0.90)
        property color colTertiaryContainerActive: ColorUtils.mix(m3colors.m3tertiaryContainer, colLayer1Active, 0.54)
        property color colOnTertiary: m3colors.m3onTertiary
        property color colOnTertiaryContainer: m3colors.m3onTertiaryContainer
        // Surface
        property color colBackgroundSurfaceContainer: ColorUtils.transparentize(m3colors.m3surfaceContainer, root.backgroundTransparency)
        property color colSurfaceContainerLow: ColorUtils.solveOverlayColor(m3colors.m3background, m3colors.m3surfaceContainerLow, 1 - root.contentTransparency)
        property color colSurfaceContainer: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerLow, m3colors.m3surfaceContainer, 1 - root.contentTransparency)
        property color colSurfaceContainerHigh: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainer, m3colors.m3surfaceContainerHigh, 1 - root.contentTransparency)
        property color colSurfaceContainerHighest: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerHigh, m3colors.m3surfaceContainerHighest, 1 - root.contentTransparency)
        property color colSurfaceContainerHighestHover: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.95)
        property color colSurfaceContainerHighestActive: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.85)
        property color colOnSurface: m3colors.m3onSurface
        property color colOnSurfaceVariant: m3colors.m3onSurfaceVariant
        // Misc
        property color colTooltip: m3colors.m3inverseSurface
        property color colOnTooltip: m3colors.m3inverseOnSurface
        property color colScrim: ColorUtils.transparentize(m3colors.m3scrim, 0.5)
        property color colShadow: ColorUtils.transparentize(m3colors.m3shadow, 0.7)
        // The tone a glass edge is drawn in, and the one colour in this file
        // deliberately NOT derived from the wallpaper. Everything above is
        // generated from the picture on screen, so an edge drawn in one of those
        // roles is guaranteed to be a colour that picture already contains -
        // which is precisely the edge that disappears against it. Measured on
        // this library's darkest wallpaper: Edit Mode's card reached 27/255 on
        // its colLayer0Border outline over a backdrop at 12, ten levels of
        // contrast for the whole boundary. Same reasoning as the depth picker's
        // hardcoded contour (refactor(background): one cutout for the layer and
        // the picker to draw).
        //
        // Opaque here - a call site picks its own weight with Qt.alpha, so one
        // tone appears at several strengths along the same edge without a token
        // per strength, which is what lets an edge be a catch along the top and
        // almost nothing along the flanks.
        //
        // It shipped as a PAIR, with a `colGlassShade` black beside it, on the
        // reasoning that a specular reads against a dark picture and a shade
        // band against a bright one. The shade band went with the thick border
        // it was half of: what darkens outside Edit Mode's card is `colShadow`
        // two lines up, already drawn there, from the same lamp, and softly
        // rather than as a hard 4px lip - so the shade band was a hard copy of
        // the soft darkening underneath it. Nothing else had ever read the
        // token. (fix(editMode): the card's edge becomes a catch, not a rim.)
        property color colGlassSpecular: "#ffffff"
        property color colOutline: m3colors.m3outline
        property color colOutlineVariant: m3colors.m3outlineVariant
        property color colError: m3colors.m3error
        property color colErrorHover: ColorUtils.mix(m3colors.m3error, colLayer1Hover, 0.85)
        property color colErrorActive: ColorUtils.mix(m3colors.m3error, colLayer1Active, 0.7)
        property color colOnError: m3colors.m3onError
        property color colErrorContainer: m3colors.m3errorContainer
        property color colErrorContainerHover: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.90)
        property color colErrorContainerActive: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.70)
        property color colOnErrorContainer: m3colors.m3onErrorContainer
    }

    rounding: QtObject {
        property int unsharpen: 2
        property int unsharpenslight: 4
        property int unsharpenmore: 6
        property int verysmall: 8
        property int small: 12
        property int normal: 17
        property int large: 23
        property int verylarge: 30
        property int full: 9999
        property int screenRounding: large
        property int windowRounding: 18

        // Material 3's own names for three tiers this ladder already has. The
        // vendored design system (modules/common/plugins/designsystem, whose
        // ExpressiveTokens exposes `Appearance.rounding` as `shape`) speaks the
        // M3 shape-scale dialect, so its call sites ask for `button`, `card` and
        // `extraLarge`; none of the three was ever ported with them. They are
        // aliases rather than new numbers on purpose - a tier with two values
        // is the drift AGENT.md's one-source rule exists to stop, while a tier
        // with two names cannot disagree with itself. `screenRounding: large`
        // is the same pattern.
        //
        // Which tier each one is, per docs/M3_GUIDELINES.md's ladder:
        //   button     -> small (12), "small chips, standard buttons". This is
        //                 also the default the *mainline* RippleButton already
        //                 carries (`Appearance?.rounding?.small ?? 4`), and the
        //                 design system's RippleButton is a fork of it; two
        //                 copies of one control must not disagree about the
        //                 shape they hand an un-overridden call site.
        //   card       -> normal (17), "standard cards, list items, menus".
        //                 ResourceCard and GroupedList.bigRadius - the shell's
        //                 own card primitives - are already this value.
        //   extraLarge -> verylarge (30), "prominent dialogs, major distinct UI
        //                 blocks". M3 calls its top non-`full` tier "extra
        //                 large"; this ladder calls that tier `verylarge`. The
        //                 surface reading it is a floating wallpaper carousel
        //                 container, and all three in-house hosts of that same
        //                 block (DesktopMenu, BackgroundConfig) round at
        //                 `verylarge` already.
        property int button: small
        property int card: normal
        property int extraLarge: verylarge
    }

    spacing: QtObject {
        // Material 3 system spacing tokens. space100 (8dp) is the base unit;
        // the primary rhythm uses multiples of 8dp, with recommended nested
        // values between them. Keep the numbered names aligned with M3.
        property int space0: 0
        property int space25: 2
        property int space50: 4
        property int space75: 6
        property int space100: 8
        property int space125: 10
        property int space150: 12
        property int space175: 14
        property int space200: 16
        property int space250: 20
        property int space300: 24
        property int space400: 32
        property int space450: 36
        property int space500: 40
        property int space600: 48
        property int space700: 56
        property int space800: 64
        property int space900: 72

    }

    borderWidth: QtObject {
        property int standard: 1
        property int emphasis: 2
        property int heavy: 4
    }

    font: QtObject {
        property QtObject family: QtObject {
            property string main: Config.options.appearance.fonts.main
            property string numbers: Config.options.appearance.fonts.numbers
            property string title: Config.options.appearance.fonts.title
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: Config.options.appearance.fonts.iconNerd
            property string monospace: Config.options.appearance.fonts.monospace
            property string reading: Config.options.appearance.fonts.reading
            property string expressive: Config.options.appearance.fonts.expressive
            property string desktopTimeFont: Config.options.appearance.clockFonts.desktopTimeFont
            property string lockscreenTimeFont: Config.options.appearance.clockFonts.lockscreenTimeFont
            property string desktopDateFont: Config.options.appearance.fonts.main
            property string lockscreenDateFont: Config.options.appearance.fonts.main
        }
        property QtObject variableAxes: QtObject {
            property var main: ({
                "wght": 450,
                "wdth": 100,
            })
            property var numbers: ({
                "wght": 450,
            })
            property var title: ({ // Slightly bold weight for title
                "wght": 550, // Weight (Lowered to compensate for increased grade)
            })
            property var expressive: main
        }
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            property int smaller: 12
            property int smallie: 13
            property int small: 15
            property int normal: 16
            property int large: 17
            property int larger: 19
            property int huge: 22
            property int hugeass: 23
            property int title: huge
        }
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
        readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1] // Default, 650ms
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1] // Default, 200ms
        readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        // What the compositor slid the sidebars on before the shell drew that
        // slide itself (`pc_decel` in shellOverrides/animations.lua): a decel
        // that settles through a 5% overshoot. Kept as its own curve rather
        // than rounded to a Material one so the panels move exactly as they
        // did when Hyprland moved them.
        readonly property list<real> panelSlideDecel: [0.05, 0.9, 0.1, 1.05, 1, 1]
        readonly property real expressiveFastSpatialDuration: 350
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveSlowSpatialDuration: 650
        readonly property real expressiveEffectsDuration: 200
    }

    // The motion vocabulary every interactive element passes through, in one
    // place, so five controls do not each invent their own hover. The states
    // and the transition between any two of them are decided by
    // interaction_motion.js (pure, and therefore tested); this object holds
    // the numbers and maps the tiers onto the shell's existing curves.
    //
    // Adopters read `state`, `targets` and `transition` - they do not hardcode
    // a duration. `InteractionMotion.qml` wires all three to a control.
    interaction: QtObject {
        id: interactionModel

        // Multipliers on whatever geometry the control already has.
        readonly property real hoverScale: 1.02
        readonly property real pressScale: 0.97
        readonly property real pressRadiusScale: 0.85
        readonly property real disabledOpacity: 0.4

        readonly property var tokens: ({
            hoverScale: interactionModel.hoverScale,
            pressScale: interactionModel.pressScale,
            pressRadiusScale: interactionModel.pressRadiusScale,
            disabledOpacity: interactionModel.disabledOpacity
        })

        // The tiers, on the shell's existing curves. The press tier is the
        // fastest one there is because a press must be acknowledged before
        // anything else; the release is longer AND lands on the spatial curve
        // whose control points leave the unit box, so it springs back rather
        // than deflating.
        //
        // These go through the same scale as the catalogued tiers, so the
        // speed slider and reduce motion reach hover and press feedback too. A
        // multiplier that slowed every panel but left every button's press
        // acknowledging at a fixed 150ms would be half a multiplier, and
        // reduce motion would leave the one class of motion that fires on
        // every single interaction untouched.
        readonly property var tiers: ({
            hoverIn: { duration: motion.scale(root.animationCurves.expressiveEffectsDuration),
                       curve: root.animationCurves.expressiveEffects },
            hoverOut: { duration: motion.scale(Math.round(root.animationCurves.expressiveEffectsDuration * 1.25)),
                        curve: root.animationCurves.expressiveEffects },
            press: { duration: motion.scale(150), curve: root.animationCurves.expressiveEffects },
            release: { duration: motion.scale(root.animationCurves.expressiveFastSpatialDuration),
                       curve: root.animationCurves.expressiveFastSpatial },
            instant: { duration: 0, curve: root.animationCurves.standard },
            hold: { duration: 0, curve: root.animationCurves.standard }
        })

        function state(flags) { return InteractionMotion.stateOf(flags); }
        function targets(state) { return InteractionMotion.targetsFor(state, interactionModel.tokens); }
        function transition(fromState, toState) {
            return InteractionMotion.transitionFor(fromState, toState, interactionModel.tiers);
        }
    }

    // The desktop card's elevation. Numbers picked on the real wallpaper with
    // ShadowTuningPlayground rather than argued about, the same way the
    // resize-tension constants were:
    //   blur 0.51 opacity 0.50 offset 4.0 scale 1.00 hover 1.94 drag 2.65
    //
    // hover/drag are multipliers on blur and offset, not separate shadows: a
    // card lifts further off the wallpaper the more directly it is being
    // handled, and one animated lift factor drives both.
    property QtObject elevation: QtObject {
        readonly property real blur: 0.51
        readonly property real shadowOpacity: 0.50
        readonly property real offsetY: 4.0
        readonly property real shadowScale: 1.00
        readonly property real hoverLift: 1.94
        readonly property real dragLift: 2.65
        readonly property color shadowColor: root.m3colors.m3shadow
    }

    animation: QtObject {
        id: motion

        // How fast this shell moves, and where the bottom of that scale is.
        //
        // The multiplier is worth having HERE and not in the fork this was
        // taken from, and the difference is not taste: roughly half of their
        // motion is a hardcoded millisecond literal, so their slider silently
        // does nothing for half the shell. Ours routes ~700 call sites through
        // the tiers below, so scaling the tiers is the whole job.
        //
        // `reduceMotion` is a SEPARATE declared state, never a value of the
        // multiplier. `multiplier` cannot reach `reduceMotionFloor` from
        // anywhere - the clamp holds for a hand-edited config.json too - which
        // is what keeps an accessibility choice from being something a user
        // can arrive at by dragging a speed slider one notch too far, or lose
        // by dragging it back.
        readonly property real multiplier: MotionPolicy.clampMultiplier(
            Config.options?.appearance?.motion?.multiplier ?? MotionPolicy.MULTIPLIER_DEFAULT)
        readonly property bool reduceMotion: Config.options?.appearance?.motion?.reduceMotion ?? false
        readonly property int reduceMotionFloor: MotionPolicy.REDUCE_MOTION_DURATION

        function scale(base: int): int {
            return MotionPolicy.scaleDuration(base, motion.multiplier, motion.reduceMotion);
        }
        function scaleVelocity(base: int): int {
            return MotionPolicy.scaleVelocity(base, motion.multiplier, motion.reduceMotion);
        }
        // One spelling of "these N things arrive in sequence". A cascade asks
        // for a step as a fraction of a catalogued duration, ranks its members
        // by VISIBLE position, and gets a clamped delay back - see
        // motion_policy.js for why each of the three is not the obvious
        // `index * literal`.
        // The shell's stagger step, in BASE milliseconds - a fraction of the
        // effects tier rather than a literal, so it moves with any retiming of
        // the catalogue. Unscaled on purpose: whatever consumes it scales it
        // once, and scaling here too would apply the multiplier twice.
        readonly property int staggerStep: MotionPolicy.staggerStep(animationCurves.expressiveEffectsDuration)
        // How far a container must have opened before its contents start
        // arriving, and the predicate that reads it. A wave with no gate races
        // the reveal it is meant to land in, which is what makes a staggered
        // group read as loose instead of composed. Unitless and unscaled - it
        // is a fraction of the container's OWN progress, so the speed slider
        // and the reduce-motion floor reach it through that scalar's tier
        // rather than through a second gate here.
        readonly property real contentGate: MotionPolicy.CONTAINER_CONTENT_GATE
        function contentsArrived(progress: real, opening: bool): bool {
            return MotionPolicy.contentsArrived(progress, opening);
        }
        function staggerRanks(included: var): var {
            return MotionPolicy.staggerRanks(included);
        }
        function staggerDelay(rank: int, step: int, leadIn: int): int {
            return MotionPolicy.staggerDelay(rank, step, leadIn);
        }
        // The three-channel member entrance's two terms, read by
        // StaggerEntrance (the one spelling of how a wave member arrives:
        // opacity, a scale and a small rise, all on one `appear` scalar).
        // The rise is a spacing token because it is a distance on the shell's
        // rhythm, not a duration; the scale START is derived from it by the
        // policy, floored at the survey's measured 0.85, so the scale's
        // excursion stays the rise's size at any member width.
        readonly property real entranceRise: root.spacing.space250
        function entranceScaleFrom(reference: real): real {
            return MotionPolicy.entranceScaleFrom(motion.entranceRise, reference);
        }

        // Convergent arrival: an object starts a short reach away from its
        // place on its own side of the container and settles with a slight
        // overshoot (motion_policy.js's converge block carries the measured
        // provenance). The reaches are DISTANCES, so they come off the
        // spacing ladder, not the duration policy; the settle shape is
        // unitless and rides whatever tier animates `appear`.
        readonly property real convergeReachX: root.spacing.space250
        readonly property real convergeReachY: root.spacing.space150
        readonly property real convergeScaleFrom: 0.92
        function convergeFrom(normX: real, rankParity: int): var {
            return MotionPolicy.convergeFrom(normX, rankParity);
        }
        function convergeSettle(appear: real): real {
            return MotionPolicy.convergeSettle(appear);
        }

        property QtObject elementMove: QtObject {
            property int duration: motion.scale(animationCurves.expressiveDefaultSpatialDuration)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveSmall: QtObject {
            property int duration: motion.scale(animationCurves.expressiveFastSpatialDuration)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveFastSpatial
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveSmall.duration
                    easing.type: root.animation.elementMoveSmall.type
                    easing.bezierCurve: root.animation.elementMoveSmall.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: motion.scale(400)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveExit: QtObject {
            property int duration: motion.scale(200)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: motion.scale(animationCurves.expressiveEffectsDuration)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: motion.scaleVelocity(850)
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
        }

        property QtObject elementMoveFaster: QtObject {
            property int duration: motion.scale(150)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: motion.scaleVelocity(850)
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFaster.duration
                easing.type: root.animation.elementMoveFaster.type
                easing.bezierCurve: root.animation.elementMoveFaster.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.elementMoveFaster.duration
                easing.type: root.animation.elementMoveFaster.type
                easing.bezierCurve: root.animation.elementMoveFaster.bezierCurve
            }}
        }

        property QtObject elementResize: QtObject {
            property int duration: motion.scale(300)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }

        property QtObject clickBounce: QtObject {
            property int duration: motion.scale(400)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: motion.scaleVelocity(850)
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.clickBounce.duration
                easing.type: root.animation.clickBounce.type
                easing.bezierCurve: root.animation.clickBounce.bezierCurve
            }}
        }
        
        property QtObject scroll: QtObject {
            property int duration: motion.scale(200)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: root.animationCurves.standardDecel
        }

        property QtObject menuDecel: QtObject {
            property int duration: motion.scale(350)
            property int type: Easing.OutExpo
        }

        // The two sidebar tiers are pinned to the compositor's `layersIn` /
        // `layersOut` (speed 4 = 400ms, on pc_decel / pc_accel), because that
        // is the motion the sidebars have always had and EdgeSlide now draws
        // it in QML instead. They were 300/250ms on the standard pair and
        // nothing took them, so nothing else moved.
        property QtObject sidebarSlideEnter: QtObject {
            property int duration: motion.scale(400)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.panelSlideDecel
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.sidebarSlideEnter.duration
                    easing.type: root.animation.sidebarSlideEnter.type
                    easing.bezierCurve: root.animation.sidebarSlideEnter.bezierCurve
                }
            }
        }

        property QtObject sidebarSlideExit: QtObject {
            property int duration: motion.scale(400)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: motion.scaleVelocity(650)
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.sidebarSlideExit.duration
                    easing.type: root.animation.sidebarSlideExit.type
                    easing.bezierCurve: root.animation.sidebarSlideExit.bezierCurve
                }
            }
        }
    }

    

    sizes: QtObject {
        property real baseBarHeight: 40
        // Float (1) and Float Islands (4) both hold their plates a gap off the
        // edge and the windows, inside the surface.
        property real barHeight: (Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 4) ?
            (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        // M3E bar widget-pill geometry: the pill is inset from the bar by
        // barPillMargin top and bottom, giving barPillHeight. Shared by BarGroup
        // and the standalone widget pills (Timer, Privacy) so they line up.
        property real barPillMargin: root.spacing.space50
        // The bar's body sits between these two, and all four styles derive from
        // them so the gaps stay consistent:
        //
        //   Hug (0) is flush against the monitor edge, so it has no margin on
        //   the edge side. Float (1), Islands (2), M3 (3) and Float Islands (4)
        //   are detached from the edge and share one. All four share the opposite-side margin -
        //   the gap between the bar and the windows next to it.
        //
        // The names say top/bottom because that is the default case, a
        // horizontal bar at the top. What they actually mean is edge side vs
        // window side: BarGroup maps them onto real anchors, and `bar.bottom`
        // flips which physical side each lands on - left vs right when the bar
        // is vertical. Do not read them as literal screen directions.
        //
        // Open-coding these per style is what let them drift apart, so nothing
        // below should reintroduce a style-specific margin of its own.
        property real barMarginTop: Config?.options.bar.cornerStyle === 0
            ? 0 : root.sizes.barPillMargin
        property real barMarginBottom: root.sizes.barPillMargin
        // Follows from the two margins rather than assuming a symmetric inset,
        // so Hug's body reclaims the space its missing top margin frees.
        property real barPillHeight: baseBarHeight - root.sizes.barMarginTop - root.sizes.barMarginBottom
        // Standalone widget pills (Timer, Privacy, Submap) read as compact
        // dynamic-island badges: a touch shorter than the group pill they sit
        // inside, inset from it evenly on every side.
        property real barStandalonePillMargin: root.spacing.space25
        property real barStandalonePillHeight: root.sizes.barPillHeight
            - root.sizes.barStandalonePillMargin * 2
        // The badges centre themselves in the whole bar, but the group pill they
        // sit inside is only centred there while its own two margins match -
        // which stopped being true when Hug dropped its edge-side one, leaving
        // the badge flush against the pill's window-side edge with all the slack
        // on the other. This is the group pill's centre relative to the bar's,
        // and it applies along whichever axis the bar's thickness runs:
        // vertically for a horizontal bar, horizontally for a vertical one.
        // `bar.bottom` puts the edge margin on the far side, so it mirrors.
        property real barStandalonePillOffset: Config?.options.bar.bottom
            ? (root.sizes.barMarginBottom - root.sizes.barMarginTop) / 2
            : (root.sizes.barMarginTop - root.sizes.barMarginBottom) / 2
        // The bar *surface's* own margins, as opposed to barMarginTop/Bottom
        // above, which inset its body. Two terms, and they are alternatives
        // rather than things to add up:
        //
        //   M3 (3) is the only style that detaches the whole surface from the
        //   monitor edge, by the same gap Hyprland leaves around windows.
        //
        //   Hyprland leaves one untouchable pixel row on the right and bottom
        //   screen edges. `interactions.deadPixelWorkaround` pulls the surface
        //   1px *past* the edge so that row falls outside it - which replaces
        //   the detach margin, since a surface already hanging over the edge
        //   has no gap left to keep.
        //
        // Both used to be open-coded in Bar.qml as
        //     (enable && anchors.bottom) * -1 || cornerStyle === 3 ? 5 : 0
        // `||` binds tighter than `?:`, so the entire left-hand side was only
        // the ternary's *condition*: with the workaround live that condition
        // was truthy and the margin came out +5 for every style, pushing the
        // bar away from the edge it was meant to overhang and making Hyprland
        // reserve 5px more with it. They live here so the arithmetic is one
        // expression a test can read rather than three inline ternaries.
        // The visual gap a detached bar style (cornerStyle 3) leaves against the
        // screen edge.
        property real barDetachGap: Config?.options.bar.cornerStyle === 3
            ? root.sizes.hyprlandGapsOut : 0
        // With auto-hide on, that gap cannot be left outside the surface: the
        // reveal strip lives inside the window, so a detached surface leaves a
        // band the pointer can never reach - hovering it reaches whatever is
        // behind the bar instead, and hiding looks wrong because the bar slides
        // up inside a surface that already starts below the edge. So the
        // surface takes the edge and the *content* carries the gap. Identical
        // to look at, and no surface reconfiguration to do it.
        property real barDetachInset: (Config?.options.bar.autoHide.enable ?? false)
            ? root.sizes.barDetachGap : 0
        property real barDetachMargin: root.sizes.barDetachGap - root.sizes.barDetachInset
        // One physical pixel, not a design token - it is the width of the row
        // the compositor leaves out, so it does not scale with anything.
        property real barDeadPixelOverhang: Config?.options.interactions.deadPixelWorkaround.enable
            ? -1 : 0
        property real barBottomMargin: (Config?.options.bar.bottom && root.sizes.barDeadPixelOverhang !== 0)
            ? root.sizes.barDeadPixelOverhang
            : root.sizes.barDetachMargin
        // The bar's layer SURFACE, as opposed to the body it paints: what
        // Bar.qml asks the compositor for, and how far that lands from the
        // screen edge. One expression each, because anything that has to keep
        // clear of the bar without editing it - Edit Mode's chrome is the first
        // - would otherwise carry its own copy of a four-term sum, and a copy
        // of that is a copy that drifts. Checked against the live compositor at
        // cornerStyle 3 with auto-hide off: `hyprctl layers` reports
        // `quickshell:bar` at y=5 h=63, which is these two.
        property real barSurfaceHeight: root.sizes.barHeight
            + root.rounding.screenRounding + root.sizes.barDetachInset
        property real barSurfaceMargin: Config?.options.bar.bottom
            ? root.sizes.barBottomMargin : root.sizes.barDetachMargin
        // A negative margin is the dead-pixel overhang, which pulls the surface
        // PAST the screen edge - it takes no room from anything inside.
        property real barSurfaceThickness: root.sizes.barSurfaceHeight
            + Math.max(0, root.sizes.barSurfaceMargin)
        // ...and the same for the vertical bar, which anchors flush to its edge
        // and so has no margin term.
        property real verticalBarSurfaceWidth: root.sizes.verticalBarWidth
            + root.rounding.screenRounding
            + (Config?.options.bar.cornerStyle === 3
                ? (Config?.options.hyprland.general.gapsOut || 5) : 0)
        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: root.spacing.space125
        property real fabShadowRadius: 5
        property real fabHoveredShadowRadius: 7
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real mediaControlsHeight: 160
        property real notificationPopupWidth: 410
        property real osdWidth: 180
        property real searchWidthCollapsed: 210
        property real searchWidth: 360
        property real sidebarWidth: 460
        property real sidebarWidthExtended: 750
        // The Phone tab's footer toolbar. Its two actions flank the count
        // pill, which is the row's only `Layout.fillWidth` item - so nothing
        // about an icon-only button's own content can decide how wide it is,
        // and left to size itself from a glyph plus an empty label each came
        // out 44x35, near enough square to read as a circle under
        // `rounding.full`. Both dimensions are stated here so the two buttons
        // and the pill between them cannot disagree about the row's height.
        // Edit Mode's viewport is inset by exactly what the drawer will need,
        // so the drawer opens into space that already exists rather than
        // covering the desktop or resizing it (spec §1.2). This is the one
        // number the inset, the drawer's own panel and its reveal all read -
        // a width restated in any of them would be two fields that must
        // agree.
        property real editModeDrawerWidth: 380
        // The gap outside the shrunk desktop on its three free sides, and
        // between it and the drawer's slot on the fourth.
        property real editModeMargin: root.spacing.space300
        // The gap between Edit Mode's own chrome - the toolbar, the tab bar and
        // the drawer - and the edge of the usable area. Half the desktop's,
        // because it is a floating surface's gap from the screen edge rather
        // than a gap between two pieces of content, and because on the vertical
        // axis it is the term that binds: every pixel here is one the shrunk
        // desktop does not get.
        property real editModeEdgeMargin: root.spacing.space150
        // M3's toolbar height (m3.material.io/components/toolbars). It is a
        // token rather than a literal inside Toolbar.qml because Edit Mode's
        // viewport reserves a band for the toolbar on the BACKGROUND surface,
        // where no toolbar exists to measure - so the reservation and the thing
        // reserved for have to read the same number or the chrome lands in a
        // band that is not its size.
        property real toolbarHeight: 56
        property real baseVerticalBarWidth: 46
        property real verticalBarWidth: (Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 4) ?
            (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
        property real wallpaperSelectorWidth: 1200
        property real wallpaperSelectorHeight: 690
        property real wallpaperSelectorItemMargins: root.spacing.space100
        property real wallpaperSelectorItemPadding: root.spacing.space75

        // Component grid for desktop-widget plugins. Matches the nandoroid
        // design-system grid the built-in widgets already use: a 132x108 cell
        // with a 12px gap, times effectiveScale. Cells are intentionally NOT
        // square (wider than tall). A widget spanning C cells across and R down
        // is widgetGridSpanX(C) x widgetGridSpanY(R) px, so tiles line up in the
        // bento layout with even gutters: media = 3x2 (420x228), a 2x2 tile is
        // 276x228, currency 2x1 is 276x108. See docs/widget-grid.md.
        property real widgetGridCellWidth: 132
        property real widgetGridCellHeight: 108
        property real widgetGridGap: 12
        function widgetGridSpanX(cols) {
            return (cols * root.sizes.widgetGridCellWidth + (cols - 1) * root.sizes.widgetGridGap) * root.effectiveScale;
        }
        function widgetGridSpanY(rows) {
            return (rows * root.sizes.widgetGridCellHeight + (rows - 1) * root.sizes.widgetGridGap) * root.effectiveScale;
        }
    }

    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
