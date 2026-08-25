pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * One group's arrival, as one cancellable thing.
 *
 * A member opts in by declaring `property real appear: 1` and folding it into
 * its own opacity - `RippleButton` already does, and so do the containers that
 * adopted this. The wave animates THAT, never `opacity` itself: an imperative
 * write to `opacity` destroys whatever binding the member had, and
 * `RippleButton` expresses its disabled state through exactly that binding, so
 * a wave written the obvious way leaves every disabled control looking enabled
 * for the rest of the session.
 *
 * `step` and `leadIn` arrive in BASE milliseconds and are scaled here, once -
 * which is what makes a wave collapse to nothing under reduce motion with no
 * second gate. Do not hand either of them an `Appearance.animation.*.duration`:
 * those are already scaled, and the multiplier would be applied twice.
 *
 * A QtObject rather than an Item on purpose: a wave declared inside the
 * container it walks must not become a member of it, and only Items land in
 * `children`.
 */
QtObject {
    id: root

    // The item whose children are the wave's members.
    property Item target: null

    // BASE milliseconds. The step is a fraction of a catalogued duration
    // rather than a literal, so it moves with any retiming of the tiers.
    property int step: Appearance.animation.staggerStep
    // The container's head start: the members land in space that already
    // exists rather than racing the surface they are arriving on.
    property int leadIn: 0

    // The wave, as a list rather than as loose animations. A trigger flipping
    // twice inside the first wave's own length used to leave it running: the
    // exit created a fade to 0 per member without stopping the entrances, so a
    // member still sitting in its PauseAnimation faded back IN onto a surface
    // that had already gone, and its spent object was never destroyed, because
    // `stop()` does not raise `finished`.
    property var active: []

    // An entrance asked for while the container is still off screen, held
    // until it is not.
    //
    // Ranking asks each member whether it is on screen, and `visible` is
    // EFFECTIVE visibility - so a container that is not yet mapped answers
    // `false` for every one of them, every rank comes back -1, and the wave is
    // empty. The members then keep whatever `appear` the last exit left them
    // at, which is zero: a permanently blank surface, with nothing in any log
    // and QML that reads correctly. Measured on the right sidebar, whose
    // trigger is `GlobalStates.sidebarRightOpen` - the state that ASKS for the
    // panel, a beat before the compositor maps its layer surface. Four
    // consecutive opens came up empty.
    //
    // So the wave waits for the container rather than trusting whatever
    // announced the open, and every adopter gets that without re-deriving it.
    property bool pendingEnter: false
    property Connections targetVisibility: Connections {
        target: root.target
        function onVisibleChanged() {
            if (root.pendingEnter && root.target?.visible)
                root.enter();
        }
    }

    // The members, when they are not one container's children. `GroupedList`
    // reparents each declared row into its own plate, so a wave over its rows
    // has no Item whose `children` are the group - the rows' shared origin is
    // the declared list, and the caller hands it in. The list REPLACES the
    // children walk; `target` stays what it is either way, the thing whose
    // being on screen the deferral below waits for.
    property list<Item> items

    function members(): var {
        if (root.items.length > 0)
            return root.items;
        return root.target ? root.target.children : [];
    }

    function stop() {
        for (let i = 0; i < root.active.length; i++) {
            const spent = root.active[i];
            if (!spent)
                continue;
            spent.stop();
            spent.destroy();
        }
        root.active = [];
    }

    // Every member where its entrance STARTS from, with nothing running. Two
    // callers: the deferral below, and a container that knows its gesture has
    // begun before it knows its container has arrived - Edit Mode's drawer
    // flips its intent at the click and gates the wave on the reveal's own
    // progress, so without this its rows are drawn at full strength for the
    // whole run up to the gate and then blink out to cascade back in.
    // Assigned rather than animated: a start value written through the same
    // animated property the end value goes through is swallowed by the
    // retarget, which is the defect that left the wallpaper selector with no
    // entrance at all.
    function park() {
        root.stop();
        // A deferral that was waiting on `visible` is cancelled by a new
        // gesture: the caller below re-arms it in the same breath, while a
        // caller parking for its own reason has just said the wave starts from
        // here, and leaving a stale pending flag lets a later `visibleChanged`
        // start the wave in front of whatever gate that caller is using.
        root.pendingEnter = false;
        const kids = root.members();
        for (let i = 0; i < kids.length; i++)
            if (kids[i].appear !== undefined)
                kids[i].appear = 0;
    }

    // Every member at rest and on screen, with nothing running - what a
    // surface that is not staggering at all should look like.
    function settle() {
        root.stop();
        root.pendingEnter = false;
        const kids = root.members();
        for (let i = 0; i < kids.length; i++)
            if (kids[i].appear !== undefined)
                kids[i].appear = 1;
    }

    function enter() {
        root.stop();
        const kids = root.members();

        if (!root.target?.visible) {
            // Park the members where the entrance will start from, so nothing
            // is on screen at full strength for the frame the container maps.
            root.park();
            root.pendingEnter = true;
            return;
        }
        root.pendingEnter = false;

        const wave = [];

        // Rank by VISIBLE position through the one policy, never by position
        // in `children`. A member that is not on screen must not spend a slot:
        // it leaves a hole one step wide in the middle of the cascade, and
        // nothing downstream compensates, because every later member is still
        // counted from its own index. The policy also clamps the rank -
        // `leadIn + index * step` is unbounded, so a twenty-member group's last
        // member arrives most of a second after the container has finished
        // opening, by which point the wave has stopped reading as one gesture.
        const included = [];
        for (let i = 0; i < kids.length; i++)
            included.push(kids[i].appear !== undefined && kids[i].visible);
        const ranks = Appearance.animation.staggerRanks(included);
        const step = Appearance.animation.scale(root.step);
        const leadIn = Appearance.animation.scale(root.leadIn);

        for (let i = 0; i < kids.length; i++) {
            if (ranks[i] < 0) {
                // A member that is not on screen takes no slot - but it must
                // not be LEFT at the 0 the park wrote, either. It is invisible
                // right now, so nothing shows; when whatever hides it lets it
                // back on screen it arrives at rest, which is what it did
                // before the wave existed. Leaving it parked is a member that
                // never comes back: the AI pane's suggestion row is hidden at
                // every open (the composer starts empty) and becomes visible
                // when the user types "/" - at the opacity the last park
                // wrote, for the rest of the open.
                if (kids[i].appear !== undefined)
                    kids[i].appear = 1;
                continue;
            }
            kids[i].appear = 0;
            wave.push(root.fade.createObject(root, {
                item: kids[i],
                to: 1,
                span: Appearance.animation.elementMoveFast.duration,
                delay: Appearance.animation.staggerDelay(ranks[i], step, leadIn)
            }));
        }

        root.active = wave;
        for (let i = 0; i < wave.length; i++)
            wave[i].start();
    }

    // No ranking on the way out: an exit is one gesture, and a member that has
    // since been hidden still needs its `appear` put back for the next
    // entrance to start from. Animated rather than assigned, so a group whose
    // container does not itself leave still reads as content leaving rather
    // than as content vanishing.
    function leave() {
        root.stop();
        root.pendingEnter = false;
        const kids = root.members();
        const wave = [];
        for (let i = 0; i < kids.length; i++) {
            if (kids[i].appear === undefined)
                continue;
            wave.push(root.fade.createObject(root, {
                item: kids[i],
                delay: 0,
                to: 0,
                span: Appearance.animation.elementMoveExit.duration
            }));
        }
        root.active = wave;
        for (let i = 0; i < wave.length; i++)
            wave[i].start();
    }

    function run(entering: bool) {
        if (entering)
            root.enter();
        else
            root.leave();
    }

    property Component fade: Component {
        SequentialAnimation {
            id: seq
            property Item item
            property int delay: 0
            property real to: 1
            property int span: 200
            PauseAnimation { duration: seq.delay }
            NumberAnimation {
                target: seq.item
                property: "appear"
                to: seq.to
                duration: seq.span
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            // Drops itself from the wave before destroying, or `stop()` would
            // later reach a destroyed object.
            onFinished: {
                root.active = root.active.filter(member => member !== seq);
                seq.destroy();
            }
        }
    }
}
