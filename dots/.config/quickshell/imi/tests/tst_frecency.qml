import QtTest
import "../services/frecency.js" as Frecency

// Launch-history ranking for the app search.
//
// Two properties carry the feature and both are tested against the store
// rather than against the arithmetic: repeatedly launching an app moves it up
// the results, and a store that is missing, empty or corrupt leaves the order
// exactly as textual matching produced it. The second is the one that decides
// whether a bad file breaks search or is merely forgotten.
TestCase {
    name: "FrecencyTest"

    readonly property real minute: 60 * 1000
    readonly property real hour: 60 * minute
    readonly property real day: 24 * hour
    readonly property real week: 7 * day
    readonly property real now: 1755000000000

    function launchedTimes(store, id, count, at) {
        let next = store;
        for (let i = 0; i < count; i++)
            next = Frecency.recordLaunch(next, id, at);
        return next;
    }

    // The bug this feature exists for: the launcher keeps offering the app the
    // user never picks. Two apps whose names match a query about equally well
    // must end up ordered by which one is actually launched.
    function test_frecency_reorders_two_equally_good_matches() {
        let store = Frecency.emptyStore();
        store = launchedTimes(store, "discord.desktop", 12, now - 20 * minute);

        const match = 0.8;
        const discord = Frecency.boost(match, Frecency.scoreFor(store, "discord.desktop", now));
        const discordPtb = Frecency.boost(match, Frecency.scoreFor(store, "discord-ptb.desktop", now));
        verify(discord > discordPtb, "the launched one outranks the one that never is");
    }

    // ...and it must not be able to overturn a match that is much better.
    function test_frecency_cannot_promote_a_much_worse_match() {
        let store = Frecency.emptyStore();
        store = launchedTimes(store, "firefox.desktop", 500, now - minute);

        const firefox = Frecency.boost(0.30, Frecency.scoreFor(store, "firefox.desktop", now));
        const chromium = Frecency.boost(0.95, Frecency.scoreFor(store, "chromium.desktop", now));
        verify(chromium > firefox,
               "typing a name still wins over launching a different app a lot");
    }

    function test_recency_outranks_a_bigger_but_older_count() {
        let store = Frecency.emptyStore();
        store = launchedTimes(store, "today.desktop", 3, now - 10 * minute);
        store = launchedTimes(store, "lastmonth.desktop", 8, now - 3 * week);
        verify(Frecency.scoreFor(store, "today.desktop", now)
               > Frecency.scoreFor(store, "lastmonth.desktop", now),
               "three launches this morning beat eight from three weeks ago");
    }

    function test_a_score_grows_with_every_launch() {
        let store = Frecency.emptyStore();
        let previous = 0;
        for (let i = 1; i <= 5; i++) {
            store = Frecency.recordLaunch(store, "app.desktop", now);
            const score = Frecency.scoreFor(store, "app.desktop", now);
            verify(score > previous, `launch ${i} raised the score`);
            previous = score;
        }
    }

    function test_a_launch_ages_out_of_its_window() {
        const store = Frecency.recordLaunch(Frecency.emptyStore(), "app.desktop", now);
        const fresh = Frecency.scoreFor(store, "app.desktop", now);
        const aged = Frecency.scoreFor(store, "app.desktop", now + 2 * day);
        const ancient = Frecency.scoreFor(store, "app.desktop", now + 60 * day);
        verify(fresh > aged, "an hour-old launch outweighs a two-day-old one");
        verify(aged > ancient, "and a two-day-old one outweighs a two-month-old one");
        verify(ancient > 0, "but it never stops counting entirely");
    }

    function test_recording_returns_a_new_store() {
        // A store mutated in place is a store nothing announces, so the
        // consumers that re-rank on it would never hear.
        const before = Frecency.emptyStore();
        const after = Frecency.recordLaunch(before, "app.desktop", now);
        verify(before !== after);
        compare(Frecency.scoreFor(before, "app.desktop", now), 0);
        verify(Frecency.scoreFor(after, "app.desktop", now) > 0);
    }

    function test_the_store_is_bounded() {
        let store = Frecency.emptyStore();
        store = launchedTimes(store, "app.desktop", 200, now);
        compare(JSON.parse(Frecency.serializeStore(store)).apps["app.desktop"].launches.length, 32,
                "the retained timestamps are capped");
        compare(JSON.parse(Frecency.serializeStore(store)).apps["app.desktop"].total, 200,
                "and the ones that fell off are still counted");

        let many = Frecency.emptyStore();
        for (let i = 0; i < 400; i++)
            many = Frecency.recordLaunch(many, `app${i}.desktop`, now - i * hour);
        verify(Object.keys(many.apps).length <= 256, "the app count is capped too");
        // Pruning takes the least used, so the most recent survivors are there.
        verify(Frecency.scoreFor(many, "app0.desktop", now) > 0, "the newest entry survived");
    }

    // ---- the degradation cases ----

    function test_a_missing_store_ranks_on_the_match_alone() {
        // No file at all: the caller falls back to an empty store, and an
        // empty store makes the boost the identity.
        compare(Frecency.parseStore(""), null);
        compare(Frecency.parseStore(undefined), null);
        compare(Frecency.parseStore(null), null);
        const empty = Frecency.emptyStore();
        for (const match of [0.1, 0.5, 0.95, 1.0])
            compare(Frecency.boost(match, Frecency.scoreFor(empty, "anything", now)), match,
                    "an unknown app's rank is exactly its match score");
    }

    function test_a_corrupt_store_is_refused_rather_than_guessed_at() {
        for (const text of ["{", "not json at all", "[]", "[1,2,3]", "null",
                            '"a string"', '{"apps": []}', '{"apps": "nope"}',
                            '{"version": 1}']) {
            compare(Frecency.parseStore(text), null, `refused: ${text}`);
        }
    }

    function test_a_half_written_entry_does_not_take_the_whole_store_with_it() {
        // The realistic corruption is not a mangled file, it is one entry that
        // does not look like the others - a hand edit, or a future version's
        // shape. Everything readable is kept.
        const store = Frecency.parseStore(JSON.stringify({
            version: 1,
            apps: {
                "good.desktop": { launches: [now - minute], total: 1 },
                "junk.desktop": "not an object",
                "empty.desktop": { launches: [], total: 0 },
                "partial.desktop": { launches: [now - minute, "nonsense", null] },
                "counted.desktop": { total: 9 }
            }
        }));
        verify(store !== null);
        verify(Frecency.scoreFor(store, "good.desktop", now) > 0);
        compare(Frecency.scoreFor(store, "junk.desktop", now), 0);
        compare(Frecency.scoreFor(store, "empty.desktop", now), 0);
        verify(Frecency.scoreFor(store, "partial.desktop", now) > 0,
               "the one usable timestamp survives its neighbours");
        verify(Frecency.scoreFor(store, "counted.desktop", now) > 0,
               "a total with no timestamps still counts as habit");
    }

    function test_a_round_trip_preserves_the_ranking() {
        let store = Frecency.emptyStore();
        store = launchedTimes(store, "a.desktop", 5, now - minute);
        store = launchedTimes(store, "b.desktop", 2, now - 2 * day);
        const reloaded = Frecency.parseStore(Frecency.serializeStore(store));
        compare(Frecency.scoreFor(reloaded, "a.desktop", now), Frecency.scoreFor(store, "a.desktop", now));
        compare(Frecency.scoreFor(reloaded, "b.desktop", now), Frecency.scoreFor(store, "b.desktop", now));
    }

    function test_a_clock_that_moved_backwards_is_not_a_launch_from_the_future() {
        // NTP correcting a boot-time clock leaves timestamps ahead of `now`. A
        // negative age must not fall through every window to the flattest
        // weight, which would make the most recent launch the least valuable.
        const future = Frecency.recordLaunch(Frecency.emptyStore(), "app.desktop", now + week);
        const present = Frecency.recordLaunch(Frecency.emptyStore(), "app.desktop", now);
        compare(Frecency.scoreFor(future, "app.desktop", now),
                Frecency.scoreFor(present, "app.desktop", now));
    }

    function test_an_empty_id_is_not_recorded() {
        const store = Frecency.recordLaunch(Frecency.emptyStore(), "", now);
        compare(Object.keys(store.apps).length, 0);
        compare(Object.keys(Frecency.recordLaunch(store, null, now).apps).length, 0);
        compare(Object.keys(Frecency.recordLaunch(store, undefined, now).apps).length, 0);
    }

    function test_the_boost_is_monotone_and_bounded() {
        const match = 0.5;
        let previous = Frecency.boost(match, 0);
        compare(previous, match);
        for (const score of [1, 10, 100, 1000, 100000]) {
            const boosted = Frecency.boost(match, score);
            verify(boosted > previous, `${score} boosts more than the score below it`);
            verify(boosted < match * 2, "and never past twice the match score");
            previous = boosted;
        }
        // Junk in, match order out.
        compare(Frecency.boost(match, NaN), match);
        compare(Frecency.boost(match, -5), match);
        compare(Frecency.boost(match, undefined), match);
    }
}
