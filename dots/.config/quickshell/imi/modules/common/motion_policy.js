.pragma library

// The shell's motion policy, as arithmetic: how fast every catalogued duration
// runs, where the bottom of that scale is, and how a group of things arrives in
// sequence.
//
// It lives here rather than inside Appearance.qml for the same reason
// interaction_motion.js does: the DECISIONS are testable and the rendering is
// not. Whether a slider at 0.4 can reach the reduce-motion state, whether a
// twentieth item in a cascade waits forever, and whether a hidden row still
// costs its neighbours a slot are all answerable without a compositor.
//
// A .pragma library has no engine context, so nothing in here may touch Qt,
// Appearance or Config - every input arrives as an argument.

// ---------------------------------------------------------------------------
// The speed multiplier
// ---------------------------------------------------------------------------
//
// The slider's sanctioned range. Its bottom is deliberately WELL ABOVE zero,
// and that is the whole of what keeps reduce motion an accessibility state
// rather than the end of a slider: no value a user can choose, and no value a
// hand-edited config.json can smuggle in, produces REDUCE_MOTION_DURATION.
// The surveyed fork spells the same idea as `animationMultiplier <= 0.25`,
// re-derived by hand as a private `_animationsDisabled` at seven call sites -
// so "the user turned motion off" and "the user likes it snappy" are one
// number there, and every reader has to agree on where the line is.
var MULTIPLIER_MIN = 0.5;
var MULTIPLIER_MAX = 2.5;
var MULTIPLIER_DEFAULT = 1.0;

// ---------------------------------------------------------------------------
// The reduce-motion floor
// ---------------------------------------------------------------------------
//
// The floor of the motion scale: the duration every catalogued tier collapses
// to when the user asks for reduced motion. Named and declared once, because
// the alternative is a magic minimum inside a helper that no test can name and
// no reader can find.
//
// It is a DURATION rather than "switch the Behaviors off", and it is zero
// rather than a small positive number. Both halves were measured with a qml6
// probe rather than reasoned about:
//
//   - A `NumberAnimation` driven by a `Behavior` never emits `finished` at ANY
//     duration - it is run as an animation job rather than through `start()` -
//     while an animation the code STARTS emits `finished` even at duration 0.
//     Every cleanup in this shell that hangs off a completion (the bar popup
//     overlay releasing its outgoing content tree, ExpandablePanel destroying
//     a spent stagger animation) hangs off a started one, so a floor of 0
//     strands none of them. A floor implemented as "disable the Behavior"
//     would have reached only half of that and left the started animations
//     running at full length.
//   - Collapsing the DURATIONS also reaches the two places a Behavior does
//     not: a `Timer` whose interval is a tier duration, and a
//     `PauseAnimation` written as the difference of two tiers. Both go to
//     zero together, so a sequence built out of them keeps its order.
var REDUCE_MOTION_DURATION = 0;

// A velocity is the reciprocal axis: `SmoothedAnimation.velocity` is px/s, so
// a slower shell wants a SMALLER number. At the floor it wants an effectively
// infinite one - large enough that any travel this shell performs completes
// inside a frame, without being Infinity, which QQuickSmoothedAnimation would
// have to be trusted to handle.
var REDUCE_MOTION_VELOCITY = 100000;

function clampMultiplier(value) {
    var number = Number(value);
    if (!isFinite(number)) return MULTIPLIER_DEFAULT;
    if (number < MULTIPLIER_MIN) return MULTIPLIER_MIN;
    if (number > MULTIPLIER_MAX) return MULTIPLIER_MAX;
    return number;
}

// The ONE scaling rule. Every catalogued duration in Appearance.qml goes
// through this and nothing else does its own arithmetic on a multiplier.
function scaleDuration(base, multiplier, reduceMotion) {
    if (reduceMotion) return REDUCE_MOTION_DURATION;
    return Math.max(0, Math.round(Number(base) * clampMultiplier(multiplier)));
}

function scaleVelocity(base, multiplier, reduceMotion) {
    if (reduceMotion) return REDUCE_MOTION_VELOCITY;
    return Math.max(1, Math.round(Number(base) / clampMultiplier(multiplier)));
}

// ---------------------------------------------------------------------------
// Stagger
// ---------------------------------------------------------------------------
//
// A cascade's rank ladder is clamped, because `index * step` is unbounded and
// the failure is silent: a twenty-row group whose panel finishes opening in
// 400ms would still be admitting rows most of a second later, and the wave
// stops reading as one gesture. Five ranks is the ladder the surveyed fork
// arrived at independently in two of its own files.
var STAGGER_MAX_RANK = 5;

// A step expressed as a fraction of a catalogued duration rather than as a
// literal, so it moves with the multiplier and with any future retiming of the
// tiers. 0.2 of the 200ms effects tier is 40ms, which is what the one call
// site in this tree had already written out by hand.
var STAGGER_FRACTION = 0.2;

// The step in BASE milliseconds - unscaled, because the one thing that scales
// it is whatever consumes it, and scaling here as well would apply the
// multiplier twice.
function staggerStep(baseDuration) {
    return Math.round(Number(baseDuration) * STAGGER_FRACTION);
}

// The delay for one member of a wave. `step` and `leadIn` arrive already
// scaled, so reduce motion collapses this to zero without a second gate.
function staggerDelay(rank, step, leadIn) {
    var base = Math.max(0, Number(leadIn) || 0);
    if (rank < 0) return base;
    return base + Math.min(rank, STAGGER_MAX_RANK) * Math.max(0, Number(step) || 0);
}

// ---------------------------------------------------------------------------
// The container-progress gate
// ---------------------------------------------------------------------------
//
// How far a container has to have opened before the things inside it start
// arriving. Without it a wave races the reveal it is meant to land in and the
// group reads as loose rather than composed - measured off the sibling fork's
// popups (docs/p3drovfx-motion-measured-2026-08-22.md §2.1), whose container is
// at 90% by 133ms while its first child does not reach 50% until 233ms. It is
// the one technique in that survey that is theirs rather than M3's: M3 says a
// group enters in sequence and says nothing about what the group's own
// container is doing while it happens.
//
// Declared here rather than written out as `> 0.6` wherever it is wanted, for
// the reason the step is: a number nobody can find is a number the next surface
// picks again.
var CONTAINER_CONTENT_GATE = 0.6;

// Whether a container's contents belong on screen, given the container's own
// progress and which way it is going.
//
// The two directions are deliberately different and the asymmetry IS the rule
// (§3, item 4): on the way IN the contents wait for the gate; on the way OUT
// they do not leave at all - they stay drawn and ride the container off, which
// is what makes an exit one rigid transform rather than a second, contradictory
// cascade. So the closing branch holds until the container has nothing left,
// and whatever reset the next entrance needs happens there, off screen.
//
// `opening` is the caller's own intent flag, never a direction inferred from
// the progress. An intent flips at the click and the progress follows, so the
// two branches are entered by different events and there is no ordering to get
// wrong; inferring the direction would need a previous value, which is state,
// which is the thing this module deliberately does not have.
// No isFinite guard, deliberately: every comparison against NaN is false, so an
// absent or unparseable progress already answers "not arrived" on both
// branches. A guard here would be a line no test could redden - the shape
// AGENT.md warns about from the other side, where `Number(null)` is 0 and
// `isFinite(0)` is true.
function contentsArrived(progress, opening) {
    var p = Number(progress);
    return opening ? p >= CONTAINER_CONTENT_GATE : p > 0;
}

// Rank by VISIBLE position, not by index in the list. A member that is not on
// screen must not spend a slot: it leaves a hole in the middle of the cascade
// that reads as the wave stalling, and it is not compensated for by anything
// downstream because every later member is still counted from its own index.
//
// `included` is a plain array of booleans - the caller decides what
// participation means (this shell's is "the child exposes an `appear` property
// and is visible"), and a .pragma library cannot look at an Item anyway.
// Excluded members get -1 rather than being dropped, so the result is
// index-aligned with the input and a caller can walk one list.
function staggerRanks(included) {
    var ranks = [];
    var rank = 0;
    for (var i = 0; i < included.length; i++) {
        if (included[i]) {
            ranks.push(rank);
            rank++;
        } else {
            ranks.push(-1);
        }
    }
    return ranks;
}
