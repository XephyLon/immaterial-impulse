import QtTest
import "../modules/common/functions/marquee.js" as Marquee

// Everything MarqueeText decides: whether the text overflows at all, how far
// it has to travel, how long that should take, and what the hold at each end
// is. The widget itself cannot be built here - it is a StyledText in a box,
// and `qmltestrunner` can lay out neither (see tst_placeholder_fit.qml) - so
// the decisions live in the library and this is where they are exercised.
TestCase {
    name: "MarqueeTest"

    // ---------------------------------------------------------------------
    // Does it overflow?
    // ---------------------------------------------------------------------

    function test_textWiderThanItsBoxOverflows() {
        verify(Marquee.overflows(300, 120));
        verify(!Marquee.overflows(80, 120));
    }

    // A text and its box are measured by different layout passes and settle a
    // fraction of a pixel apart routinely. Without slack that reads as a
    // permanent overflow, and a label that fits scrolls half a pixel forever.
    function test_aSubPixelOverrunIsNotAnOverflow() {
        verify(!Marquee.overflows(120.4, 120), "0.4px is measurement noise");
        verify(!Marquee.overflows(121, 120), "exactly the slack still fits");
        verify(Marquee.overflows(121.5, 120), "past the slack is a real overflow");
    }

    // The case that decides whether every marquee in the shell starts at full
    // travel on the frame its surface is built: a box with no width yet has
    // not been laid out, and is not "overflowing by the whole string".
    function test_anUnlaidOutBoxDoesNotOverflow() {
        verify(!Marquee.overflows(300, 0));
        verify(!Marquee.overflows(300, -1));
        verify(!Marquee.overflows(300, NaN));
        verify(!Marquee.overflows(300, undefined));
    }

    function test_anUnmeasuredTextDoesNotOverflow() {
        verify(!Marquee.overflows(0, 120));
        verify(!Marquee.overflows(NaN, 120));
        verify(!Marquee.overflows(undefined, 120));
    }

    // ---------------------------------------------------------------------
    // How far
    // ---------------------------------------------------------------------

    // The overflow, never the whole string: the marquee is a ping-pong over
    // what is hidden, so the first character is on screen at rest.
    function test_theTravelIsTheOverflowNotTheWholeString() {
        compare(Marquee.travelDistance(300, 120), 180);
        compare(Marquee.travelDistance(287.2, 120), 167.2);
    }

    function test_textThatFitsTravelsNowhere() {
        compare(Marquee.travelDistance(80, 120), 0);
        compare(Marquee.travelDistance(120.4, 120), 0, "inside the slack");
        compare(Marquee.travelDistance(300, 0), 0, "not laid out yet");
    }

    // ---------------------------------------------------------------------
    // How long
    // ---------------------------------------------------------------------

    // Proportional, because what has to be held constant is the speed the text
    // passes the eye. A catalogued tier would run a three-word overrun and a
    // whole sentence at the same clock, so one of the two is unreadable.
    function test_theDurationIsProportionalToTheDistance() {
        const near = Marquee.travelDuration(120 + 400, 120);
        const far = Marquee.travelDuration(120 + 800, 120);
        compare(near, 400 * Marquee.MS_PER_PIXEL);
        compare(far, 800 * Marquee.MS_PER_PIXEL);
        compare(far, near * 2, "twice the overflow is twice the time");
    }

    // The floor, from the other end: a label overflowing by six pixels would
    // otherwise twitch - a movement that resolves before it can be looked at,
    // which is worse than the truncation it replaces.
    function test_aShortOverflowStillTakesTheFloor() {
        compare(Marquee.travelDuration(126, 120), Marquee.MIN_TRAVEL_MS);
        const atFloor = Marquee.MIN_TRAVEL_MS / Marquee.MS_PER_PIXEL;
        compare(Marquee.travelDuration(120 + atFloor - 1, 120), Marquee.MIN_TRAVEL_MS,
            "one pixel short of the crossover is still the floor");
        verify(Marquee.travelDuration(120 + atFloor + 1, 120) > Marquee.MIN_TRAVEL_MS,
            "one pixel past it is proportional again");
    }

    function test_textThatFitsHasNoDuration() {
        compare(Marquee.travelDuration(80, 120), 0);
        compare(Marquee.travelDuration(300, 0), 0);
    }

    // ---------------------------------------------------------------------
    // The dwell
    // ---------------------------------------------------------------------

    // The whole reason this is a function of reduceMotion rather than one
    // constant. At the motion floor the traverse has no duration at all, so
    // the dwell IS the cycle: keeping the ordinary hold would swap the label's
    // two ends roughly once a second, for as long as it is on screen. The
    // accessibility state must not produce the fastest motion in the shell.
    function test_reduceMotionLengthensTheHoldRatherThanShorteningIt() {
        verify(Marquee.dwell(true) > Marquee.dwell(false));
        compare(Marquee.dwell(false), Marquee.DWELL_MS);
        compare(Marquee.dwell(true), Marquee.REDUCED_DWELL_MS);
    }

    // A dwell long enough to read a device name at. Measured against the
    // traverse it brackets rather than asserted as a number, so retiming one
    // without the other reddens.
    function test_theHoldIsAReadableFractionOfTheTraverse() {
        verify(Marquee.DWELL_MS >= 1000, "shorter than a second is a flash");
        verify(Marquee.DWELL_MS < Marquee.MIN_TRAVEL_MS,
            "a hold longer than the shortest traverse reads as a stall");
    }
}
