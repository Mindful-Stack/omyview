import QtQuick
import QtTest
import "../logic.js" as Logic

TestCase {
    name: "Find"

    function win(addr, cls, title) { return { address: addr, cls: cls, title: title } }
    function addrs(res) { return res.map(function (m) { return m.address }) }

    // Distinguishes: a substring matcher (would reject "slk") and a matcher that ignores order
    // (would accept "kcl").
    function test_subsequence_in_order() {
        var w = [win("a", "slack", "")]
        compare(addrs(Logic.findMatches("slk", w)), ["a"])
        compare(addrs(Logic.findMatches("kcl", w)), [])
        compare(addrs(Logic.findMatches("slz", w)), [])
    }
    // Distinguishes: case-sensitive comparison on either side.
    function test_case_insensitive() {
        var w = [win("a", "Slack", "")]
        compare(addrs(Logic.findMatches("SLACK", w)), ["a"])
        compare(addrs(Logic.findMatches("slack", w)), ["a"])
    }
    // Distinguishes: no consecutive-character bonus. The haystacks are equal length so the
    // length penalty cannot carry the test.
    function test_consecutive_beats_gapped() {
        var w = [win("gap", "axb", ""), win("run", "abx", "")]
        compare(addrs(Logic.findMatches("ab", w)), ["run", "gap"])
    }
    // Distinguishes: no word-start bonus ("foobar" is shorter, so it would win on length alone).
    function test_word_start_beats_mid_word() {
        var w = [win("mid", "foobar", ""), win("start", "foo bar", "")]
        compare(addrs(Logic.findMatches("bar", w)), ["start", "mid"])
    }
    // Distinguishes: scoring class and title the same (the title-only window would tie or win
    // because its haystack is just as short).
    function test_class_outranks_title() {
        var w = [win("tab", "chromium", "slack"), win("app", "slack", "chromium")]
        compare(addrs(Logic.findMatches("slack", w)), ["app", "tab"])
    }
    // Distinguishes: no length penalty (identical per-character scores would tie and fall
    // back to input order, putting "long" first).
    function test_shorter_haystack_wins_tie() {
        var w = [win("long", "", "slack - daniel"), win("short", "", "slack")]
        compare(addrs(Logic.findMatches("slack", w)), ["short", "long"])
    }
    // Distinguishes: an unstable sort or a hash-ordered result; equal scores must keep the
    // input order in both directions.
    function test_equal_scores_keep_input_order() {
        var w = [win("x", "term", ""), win("y", "term", ""), win("z", "term", "")]
        compare(addrs(Logic.findMatches("term", w)), ["x", "y", "z"])
        compare(addrs(Logic.findMatches("term", w.slice().reverse())), ["z", "y", "x"])
    }
    // Distinguishes: an empty query matching everything (a subsequence of length 0 is trivially
    // present in every string).
    function test_empty_query_matches_nothing() {
        var w = [win("a", "slack", "Slack")]
        compare(Logic.findMatches("", w).length, 0)
        compare(Logic.findMatches(undefined, w).length, 0)
    }
    // Distinguishes: a matcher that reads only class or only title.
    function test_matches_either_field() {
        var w = [win("byTitle", "chromium", "Daily standup"), win("byClass", "Slack", "")]
        compare(addrs(Logic.findMatches("standup", w)), ["byTitle"])
        compare(addrs(Logic.findMatches("slack", w)), ["byClass"])
    }
    // Distinguishes: greedy first-occurrence matching. For "ab", the isolated 'a' at index 1 of
    // "xax ab" would trap a greedy matcher (score 2: gapped, no word start) below "xxabxx"
    // (score 4); the best alignment is the whole word "ab" (7), which must win.
    function test_best_alignment_not_first_occurrence() {
        var w = [win("greedy", "xxabxx", ""), win("word", "xax ab", "")]
        compare(addrs(Logic.findMatches("ab", w)), ["word", "greedy"])
    }
    // Distinguishes: an alignment search that cannot skip a repeated character. "ss" against
    // "s xs ss": the best pairing is the two word-start s's (4 + 4 = 8); against "s xs xs" no
    // pairing beats 4 + 1 = 5. Greedy first-occurrence scores both 5 and cannot tell them apart.
    function test_repeated_characters_pick_best_pairing() {
        verify(Logic.fuzzyScore("ss", "s xs ss") > Logic.fuzzyScore("ss", "s xs xs"))
    }
    // Distinguishes: a result shape that leaks the sort key (`order`) or drops the score.
    function test_result_shape() {
        var res = Logic.findMatches("s", [win("a", "slack", "")])
        compare(Object.keys(res[0]).sort(), ["address", "score"])
        verify(res[0].score > 0)
    }
    // Distinguishes: an uncapped length penalty. A 1-character query against a 300-character
    // title with a single mid-word hit must still score above zero — without the cap the
    // penalty (300 * 0.01 = 3.0) would outweigh the match (1), giving a negative score.
    function test_long_title_still_scores_positive() {
        var title = "x".repeat(150) + "q" + "x".repeat(149)
        var res = Logic.findMatches("q", [win("a", "", title)])
        compare(addrs(res), ["a"])
        verify(res[0].score > 0)
    }
}
