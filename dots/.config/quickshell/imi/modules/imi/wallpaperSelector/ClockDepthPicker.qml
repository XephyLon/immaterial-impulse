import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.background

/**
 * Where the quality gate lives, and it is a human - so this is the instrument
 * it makes its decision with.
 *
 * There is no automatic check for whether a mask is good. Scoring the whole
 * library numerically ranked rectangular slabs of background ABOVE clean
 * cutouts, and even the right model produces an unusable mask about a third of
 * the time it produces one at all - so depth is not an automatic effect, it is a
 * per-wallpaper artifact the user accepts once, with segmentation proposing
 * candidates.
 *
 * Two detectors, because neither is a superset of the other: `isnet-anime`
 * carries most of this library and returns nothing at all on the
 * semi-photographic minority that `isnet-general-use` handles best. So a model
 * that finds nothing usually means the WRONG MODEL rather than no subject -
 * measured on `cat_upscayl_2x…png`, where the illustration model returns `none`
 * and the photographic one returns a foreground of 0.143 - and the two are
 * shown side by side, at the same size, for exactly that reason.
 *
 * A THIRD column, because on this library "the wrong model" is usually still
 * the answer after trying both: swept over the 94 wallpapers here, 45 return
 * nothing from either detector and 3 have never been run. Those are not empty pictures - they are
 * landscapes and full-bleed illustrations with plenty to stand in front of a
 * clock and no single salient object to find. That column is MobileSAM and it
 * answers a different question: not "what is the subject of this picture" but
 * "what is the thing at this point". So the user points at it.
 *
 * That column is NOT clicked here. The gesture used to live on this preview and
 * it was the wrong surface for it: the mask is judged at screen size against
 * real widgets and was being authored against a ~300px thumbnail, where a click
 * landing on a character's shoulder is several hundred pixels off by the time
 * anyone sees the result - and a mis-aimed click comes back as a perfectly good
 * mask of the wrong thing. Selecting happens on the desktop itself
 * (modules/imi/clockDepthSelect), on the wallpaper as it is actually drawn, and
 * this column is the way in and the record of what came back: the clicks are
 * drawn on as plus and minus discs, and the cutout they produced sits under
 * them.
 *
 * All three columns are the same width, which is the point of the layout: the
 * cutouts are being compared, and the clickable one is not more important than
 * the two it is being compared against.
 *
 * The preview is composited the way the desktop is - the wallpaper cropped as it
 * will be, with a clock over it and the cutout on top - rather than shown as a
 * bare mask. A bare cutout hides the failure that matters: the depth layer
 * paints the wallpaper's own pixels back over themselves, so a wrong mask costs
 * nothing where no widget sits, and the only question is whether it is right
 * where the clock is.
 *
 * INSPECT is the other half, and it is the half that was missing: at full
 * brightness a soft edge, a halo and a rectangular slab of background are all
 * invisible against the image they were cut from - that is §1.2's own finding,
 * which is why the feasibility survey judged every candidate as a cutout over a
 * flat field rather than over its wallpaper. Switching it on dims everything
 * the model did NOT claim and traces the silhouette, so the three questions a
 * verdict actually rests on - where is the edge, how soft is it, what did it
 * grab that it should not have - are answerable by looking. It draws over the
 * SAME registered mask surface the desktop layer masks with (see
 * ClockDepthCutout), so it cannot show a registration the desktop does not use.
 */
Item {
    id: root

    required property real screenAspect

    readonly property string wallpaper: ClockDepth.wallpaperPath
    readonly property bool busy: ClockDepth.running !== ""
    // Off by default and gated all the way down: with it off the picker draws
    // exactly what the desktop will draw, and the inspection layers - a second
    // pass over the mask surface and a glow - are not instantiated at all.
    property bool inspect: false

    // What this wallpaper's verdict currently is, said first. Both wrong
    // conclusions this feature produced on the way in - the user's "toggling it
    // on does nothing" and the review's "the layer is misaligned" - were the
    // same missing sentence: the wallpaper on screen simply had no accepted
    // cutout, and nothing anywhere said so.
    readonly property string verdictLine: {
        if (root.wallpaper === "")
            return Translation.tr("No wallpaper to work from.")
        switch (ClockDepth.state) {
        case "accepted":
            return Translation.tr("This wallpaper has a cutout, and the widgets are drawn behind it.")
        case "declined":
            return Translation.tr("This wallpaper is set to no depth. Accepting a cutout below undoes that.")
        case "none":
            // Not "there is no subject in this wallpaper" - that was a verdict
            // on the picture, and half this library reaches it while holding a
            // perfectly good thing to stand in front of the clock. It is a
            // verdict on the two models that answer on their own, and the
            // column that answers a click is what it points at.
            return Translation.tr("Neither detector found a subject. Pick the one you want on the desktop itself.")
        case "candidate":
            return Translation.tr("A cutout is ready to judge. Nothing is drawn until you keep one.")
        case "unreadable":
        case "error":
            return Translation.tr("Could not read this wallpaper's cache entry.")
        default:
            return Translation.tr("No cutout for this wallpaper yet. Run a detector or click the subject, then keep it only if the edge looks right where your widgets sit.")
        }
    }

    signal closeRequested()
    // The way into the desktop selector. Raised rather than acted on, because
    // getting there means closing this dialog AND the wallpaper selector around
    // it, and neither is this component's to close.
    signal selectOnDesktopRequested()

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
    }

    // The scrim swallows clicks aimed at the grid behind the picker. Everything
    // here is a real control, so unlike the depth layer itself this one WANTS
    // the input.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: {}
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space200
        spacing: Appearance.spacing.space150

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                text: "layers"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer0
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Depth for this wallpaper")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    // The first thing a person opening this needs is whether
                    // this wallpaper has a cutout at all - which is the
                    // question nobody could answer while the feature looked
                    // like it was doing nothing, when in fact it was correctly
                    // doing nothing for a wallpaper that has no mask.
                    text: ClockDepth.lastError !== ""
                        ? ClockDepth.lastError
                        : root.verdictLine
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockDepth.lastError !== ""
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    // Spec §8.4: a static silhouette over a moving scene is
                    // right exactly while the subject stands still, and no
                    // measurement can tell. It is judged the same way the
                    // mask's own quality is - said here, where the verdict is
                    // given, and only for a live scene.
                    visible: ClockDepth.askingWe
                    text: Translation.tr("This is a live scene, cut from a still of it. The silhouette stays put while the picture moves - keep it only if the subject does too. Turn on Inspect and let the scene run.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
            // A RippleButton rather than the IconToolbarButton this started as:
            // ToolbarButton carries `Layout.fillHeight: true` for the toolbars
            // it was written for, and IconToolbarButton derives its width from
            // its height - so in a header row it stretches to the row and comes
            // out as a circle a third of the dialog wide, which is also what
            // made the row that tall. It is the close button's twin now.
            RippleButton {
                id: inspectButton
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: height / 2
                toggled: root.inspect
                onClicked: root.inspect = !root.inspect
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "chrome_reader_mode"
                    iconSize: Appearance.font.pixelSize.larger
                    color: inspectButton.toggled
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer0
                }
                StyledToolTip {
                    text: Translation.tr("Dim everything the model did not pick, and trace its edge")
                }
            }
            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: height / 2
                onClicked: root.closeRequested()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.spacing.space150

            Repeater {
                model: ClockDepth.modelSpecs

                ColumnLayout {
                    id: candidate
                    required property var modelData

                    readonly property string modelName: candidate.modelData.name ?? ""
                    // The producer says which models answer a click and which
                    // answer the picture; this column is the same shape either
                    // way and differs only in how it is asked.
                    readonly property bool prompted: candidate.modelData.kind === "prompted"
                    readonly property var points: candidate.prompted ? (ClockDepth.points ?? []) : []

                    readonly property string maskPath: ClockDepth.candidates?.[candidate.modelName] ?? ""
                    // Absent from `candidates` and present-but-null in it are
                    // different things and must read differently: the first is a
                    // model nobody has run, the second is a model that ran and
                    // found nothing. Collapsing them is how a picker ends up
                    // inviting the user to spend 4.5 seconds re-learning that
                    // there is no one in the picture.
                    readonly property bool refused: candidate.modelName in (ClockDepth.candidates ?? ({}))
                        && candidate.maskPath === ""
                    readonly property bool thisRunning: ClockDepth.running === candidate.modelName
                    readonly property bool chosen: ClockDepth.state === "accepted"
                        && ClockDepth.acceptedModel === candidate.modelName
                    // Whether ANY other column found something. A model that
                    // returns nothing is usually the wrong model rather than an
                    // empty picture, so an empty result has to point at its
                    // neighbours instead of reading as a verdict on the image.
                    readonly property bool otherFound: {
                        const results = ClockDepth.candidates ?? ({})
                        for (const other in results) {
                            if (other !== candidate.modelName && (results[other] ?? "") !== "")
                                return true
                        }
                        return false
                    }
                    // Gated on the mask having DECODED, not merely on a path:
                    // the veil masks by the inverse of the mask surface, so an
                    // Image.Error or a not-yet-loaded mask is a transparent
                    // surface whose inverse covers the entire preview in black
                    // - a failure that reads as "the model claimed nothing"
                    // rather than as "there is nothing to inspect".
                    readonly property bool inspecting: root.inspect
                        && candidate.maskPath !== ""
                        && previewCutout.maskStatus === Image.Ready

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Every column takes an equal share of the row whatever
                    // its content is wider than. Without a preferred width a
                    // RowLayout hands fillWidth children their implicit widths
                    // first, so the column whose button labels are longer gets a
                    // bigger preview - and the cutouts are being compared.
                    Layout.preferredWidth: 1
                    spacing: Appearance.spacing.space100

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space50

                        StyledText {
                            text: candidate.prompted
                                ? Translation.tr("Click to select")
                                : candidate.modelName === "isnet-anime"
                                    ? Translation.tr("Illustration")
                                    : Translation.tr("Photographic")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                        }
                        // Which of the two the desktop is actually drawing.
                        // Without it the picker shows two cutouts and no
                        // indication of which one was ever accepted, so the
                        // question "what is on my screen right now" is
                        // unanswerable from the one surface built to answer it.
                        MaterialSymbol {
                            visible: candidate.chosen
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: candidate.modelName
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Item {
                        id: preview
                        Layout.fillWidth: true
                        Layout.preferredHeight: width / root.screenAspect
                        Layout.maximumHeight: 320
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                        }

                        // The picture as the desktop crops it. Drawn at full
                        // brightness, because with inspect off this preview's
                        // only job is to be honest about what the wallpaper
                        // will look like with the cutout on it - the diagnosis
                        // is the other mode's job, and a preview that is
                        // permanently half a diagnosis is neither.
                        Image {
                            id: previewWallpaper
                            anchors.fill: parent
                            source: root.wallpaper === "" ? "" : `file://${root.wallpaper}`
                            fillMode: Image.PreserveAspectCrop
                            cache: true
                            smooth: true
                            asynchronous: true
                        }

                        // INSPECT: everything the model did NOT claim, dimmed.
                        // A soft edge, a halo and a rectangular slab of
                        // background are all invisible against the image they
                        // were cut from - which is why the feasibility survey
                        // judged every candidate over a flat field - so the
                        // veil is what turns "it looks like the wallpaper" into
                        // a readable answer about what was picked.
                        //
                        // Masked by the INVERSE of the same registered surface
                        // the cutout is masked by, so the lit region and the
                        // drawn region cannot be off by a pixel from each other.
                        Rectangle {
                            id: veilSource
                            anchors.fill: parent
                            color: "black"
                            visible: false
                        }
                        Loader {
                            anchors.fill: parent
                            active: candidate.inspecting
                            visible: active
                            sourceComponent: OpacityMask {
                                source: veilSource
                                maskSource: previewCutout.maskSurface
                                invert: true
                                opacity: 0.66
                            }
                        }

                        StyledText {
                            id: previewClock
                            anchors.centerIn: parent
                            text: DateTime.time
                            font.pixelSize: Math.max(24, preview.height * 0.34)
                            font.family: Config.options.background.widgets.clock.digital.font.family
                            color: Appearance.colors.colOnLayer0
                        }

                        // INSPECT: the silhouette itself, traced. The veil says
                        // WHAT was claimed; this says WHERE the boundary runs
                        // and how hard it is - a mask that follows hair tufts
                        // draws a tight bright line, a mushy one draws a wide
                        // faint band, and a rectangular slab draws a rectangle.
                        // Drawn under the cutout so only its outer half shows,
                        // which keeps the subject's own pixels unpainted.
                        Loader {
                            anchors.fill: parent
                            active: candidate.inspecting
                            visible: active
                            sourceComponent: Glow {
                                source: previewCutout.maskSurface
                                // The one hardcoded colour in this file, and it
                                // has to be: every Appearance token is
                                // generated FROM this wallpaper, so a token
                                // here is guaranteed to be a colour the picture
                                // already contains. The feasibility survey
                                // judged its masks over flat magenta for the
                                // same reason.
                                color: "#ff00c8"
                                radius: 8
                                samples: 17
                                spread: 0.45
                                // Otherwise the blur clamps at the item's edges
                                // and a subject touching the bottom of the
                                // frame smears into a band across it, which
                                // reads as a mask claiming the whole edge.
                                transparentBorder: true
                            }
                        }

                        // The subject, cut out exactly the way the desktop cuts
                        // it out. Same component, so the preview cannot show a
                        // registration the desktop does not use.
                        ClockDepthCutout {
                            id: previewCutout
                            anchors.fill: parent
                            wallpaperSource: previewWallpaper.source
                            maskPath: candidate.maskPath
                            maskRevision: ClockDepth.revisions?.[candidate.modelName] ?? ""
                            visible: candidate.maskPath !== ""
                        }

                        // Where the clicks landed, drawn back onto the picture.
                        //
                        // Positioned through the cutout's OWN mask rectangle
                        // rather than from a second crop worked out here: that
                        // rect is where the whole wallpaper sits inside this
                        // box, so a normalised point in the picture is a
                        // fraction along it. Anything else would put the dot
                        // somewhere other than where the click was sent, which
                        // is the one thing that would make this gesture
                        // unteachable.
                        Repeater {
                            model: candidate.points

                            Item {
                                id: marker
                                required property var modelData
                                readonly property rect frame: previewCutout.maskRect
                                readonly property bool include: (marker.modelData.label ?? 1) === 1

                                width: 18
                                height: 18
                                x: marker.frame.x + marker.modelData.x * marker.frame.width
                                    - width / 2
                                y: marker.frame.y + marker.modelData.y * marker.frame.height
                                    - height / 2
                                visible: candidate.prompted

                                // Black and white, and hardcoded, for the same
                                // reason the inspect contour is: every
                                // Appearance colour is generated FROM this
                                // wallpaper, so a token here is a colour the
                                // picture is guaranteed to contain. A disc
                                // against its own outline reads on any image.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: marker.include ? "#ffffff" : "#101010"
                                    border.width: 2
                                    border.color: marker.include ? "#101010" : "#ffffff"

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        // The glyph is the whole explanation of
                                        // what a right-click did, on the object
                                        // it did it to.
                                        text: marker.include ? "add" : "remove"
                                        iconSize: 12
                                        color: marker.include ? "#101010" : "#ffffff"
                                    }
                                }
                            }
                        }

                        // Along the bottom edge rather than centred: the middle
                        // of the preview is where the clock is, and a status
                        // label printed across it is sitting on the one thing
                        // the user came here to look at.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            implicitHeight: statusLabel.implicitHeight + Appearance.spacing.space100
                            visible: statusLabel.text !== ""
                            color: Appearance.colors.colLayer0

                            StyledText {
                                id: statusLabel
                                anchors.centerIn: parent
                                width: parent.width - Appearance.spacing.space100
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                // "No subject found" was a verdict on the
                                // picture and it is usually a verdict on the
                                // model: measured, the illustration model
                                // returns nothing on photographic wallpapers
                                // the other model cuts out cleanly. A user who
                                // reads the first sentence stops; a user who
                                // reads this one runs the other column.
                                //
                                // The prompted column's line is the whole of
                                // its instructions, and it is on the surface
                                // the gesture is aimed at, because there is
                                // nowhere else a person would look for it.
                                text: {
                                    if (candidate.thisRunning)
                                        return candidate.prompted
                                            ? Translation.tr("Cutting…")
                                            : Translation.tr("Looking for a subject…")
                                    if (candidate.prompted) {
                                        if (ClockDepth.askingWe && !ClockDepth.stillAvailable)
                                            return Translation.tr("Waiting for the scene's first frame")
                                        if (!ClockDepth.selectable)
                                            return Translation.tr("Apply this wallpaper to pick on the desktop")
                                        if (candidate.points.length === 0)
                                            return Translation.tr("Pick the subject on the desktop")
                                        if (candidate.maskPath === "")
                                            return Translation.tr("Nothing found there yet")
                                        return Translation.tr("Refine it on the desktop")
                                    }
                                    if (candidate.maskPath !== "")
                                        return ""
                                    // A live project is segmented from its
                                    // still, which the shell grabs a moment
                                    // after the scene's first frame (spec
                                    // §8.5) - so there is nothing to run on
                                    // yet, rather than nothing found.
                                    if (ClockDepth.askingWe && !ClockDepth.stillAvailable)
                                        return Translation.tr("Waiting for the scene's first frame")
                                    return candidate.refused
                                        ? (candidate.otherFound
                                            ? Translation.tr("Nothing here — another column found something")
                                            : Translation.tr("Nothing here — try picking it on the desktop"))
                                        : Translation.tr("Not run yet")
                                }
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space100

                        DialogButton {
                            id: runButton
                            visible: !candidate.prompted
                            enabled: !root.busy && root.wallpaper !== "" && ClockDepth.stillAvailable
                            buttonText: candidate.maskPath !== "" || candidate.refused
                                ? Translation.tr("Run again")
                                : Translation.tr("Run")
                            onClicked: ClockDepth.runModel(candidate.modelName)
                        }
                        Item { Layout.fillWidth: true }
                        // The prompted column's one action, and it leaves this
                        // dialog: the clicking, the undo, the start-over and
                        // the verdict all live on the desktop now, where the
                        // cutout is the size it will be judged at and the
                        // widgets it has to hide behind are the real ones.
                        // Refusing when the desktop is showing something else -
                        // a preview this dialog's own grid is about to revert,
                        // a live Wallpaper Engine project - is the difference
                        // between selecting on the wallpaper and selecting on
                        // whatever happens to be there afterwards.
                        DialogButton {
                            id: selectOnDesktopButton
                            visible: candidate.prompted
                            enabled: !root.busy && ClockDepth.selectable
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colText: Appearance.colors.colOnPrimary
                            buttonText: candidate.points.length > 0
                                ? Translation.tr("Refine on desktop")
                                : Translation.tr("Pick on desktop")
                            onClicked: root.selectOnDesktopRequested()
                        }
                        DialogButton {
                            id: acceptButton
                            visible: !candidate.prompted
                            enabled: !root.busy && candidate.maskPath !== ""
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colText: Appearance.colors.colOnPrimary
                            buttonText: Translation.tr("Use this")
                            onClicked: {
                                ClockDepth.acceptModel(candidate.modelName)
                                // Accepting a mask while the feature is switched
                                // off would put the artifact on disk and change
                                // nothing on screen, which reads as the button
                                // not working. The acceptance IS the intent.
                                Config.options.background.clockDepth.enable = true
                                root.closeRequested()
                            }
                        }
                    }

                    // The preview's height is locked to the screen's aspect, so
                    // a tall dialog has height nothing wants. It falls here
                    // rather than being shared out above the label, which would
                    // float the two cutouts in the middle of the dialog away
                    // from the buttons that act on them.
                    Item { Layout.fillHeight: true }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            StyledText {
                Layout.fillWidth: true
                // The global switch, not this wallpaper's verdict - that is the
                // header's job now. Worth its own line because accepting a
                // cutout turns the switch on, so the two are easy to conflate
                // and only one of them is per-wallpaper.
                text: ClockDepth.enabled
                    ? Translation.tr("Depth is on. Wallpapers with no accepted cutout are unaffected.")
                    : Translation.tr("Depth is off. Keeping a cutout turns it on.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            DialogButton {
                id: declineButton
                enabled: !root.busy && root.wallpaper !== ""
                buttonText: Translation.tr("No depth for this wallpaper")
                onClicked: {
                    ClockDepth.declineWallpaper()
                    root.closeRequested()
                }
            }
        }
    }
}
