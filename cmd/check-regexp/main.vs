// Checks text/regexp: ECMAScript patterns, as HTML's pattern attribute
// and programs write them.
package main

import "text/regexp"

var failures = 0

func check(ok: bool, what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func whole(p: string, s: string, flags: string = "v") -> bool {
    guard let re = regexp.Regexp.Compile(p, flags: flags) else { return false }
    return re.MatchesWhole(s)
}

func main() -> int32 {
    print("Form patterns")
    check(whole("[0-9]{3}-[0-9]{4}", "555-1234") && !whole("[0-9]{3}-[0-9]{4}", "555-12345"), "a phone number, the whole value")
    check(whole("\\d{5}(-\\d{4})?", "12345") && whole("\\d{5}(-\\d{4})?", "12345-6789") && !whole("\\d{5}(-\\d{4})?", "1234"), "a zip code with an optional part")
    check(whole("[A-Za-z]+", "Hello") && !whole("[A-Za-z]+", "Hello!"), "letters only")
    check(whole("[^@\\s]+@[^@\\s]+\\.[a-z]{2,}", "a.b@example.com") && !whole("[^@\\s]+@[^@\\s]+\\.[a-z]{2,}", "a b@x.com"), "an e-mail address")
    check(whole("cat|dog", "dog") && !whole("cat|dog", "catdog"), "alternation, anchored as a whole")
    check(whole("(?:ab)+", "ababab") && !whole("(?:ab)+", "ababa"), "a non-capturing group repeated")
    check(whole("a{2,3}", "aa") && whole("a{2,3}", "aaa") && !whole("a{2,3}", "aaaa") && whole("a{2,}", "aaaaa"), "counted repeats")

    print("Syntax")
    let lazy = regexp.Regexp.Compile("<.+?>", flags: "v")!.Find("<a><b>")!
    check(lazy.start == 0 && lazy.end == 3, "a lazy quantifier takes the least (got \(lazy.start) \(lazy.end))")
    let greedy = regexp.Regexp.Compile("<.+>", flags: "v")!.Find("<a><b>")!
    check(greedy.end == 6, "a greedy one the most")
    check(whole("(\\w)\\1", "aa") && !whole("(\\w)\\1", "ab"), "a backreference")
    check(whole("(?<x>\\d)-\\k<x>", "4-4") && regexp.Regexp.Compile("(?<year>\\d{4})", flags: "v")!.GroupIndex("year") == 1, "named groups and \\k")
    check(whole("\\d+(?=px)px", "12px") && !whole("\\d+(?!px)px", "12px") && whole("\\d+(?!px)\\w+", "12px"), "lookahead, positive and negative")
    check(regexp.Regexp.Compile("(?<=\\$)\\d+", flags: "v")!.Find("cost $42")?.start == 6, "lookbehind")
    check(whole("HELLO", "hello", "vi") && !whole("HELLO", "hello"), "case-insensitive with i")
    check(whole("\\p{L}+", "Grüße") && !whole("\\p{L}+", "abc1") && whole("\\p{Lu}\\p{Ll}*", "Élan"), "\\p{...} by general category")
    check(whole("\\p{Script=Greek}+", "αβγ") && !whole("\\p{Script=Greek}+", "abc"), "and by script")
    check(regexp.Regexp.Compile("\\bcat\\b", flags: "v")!.Matches("a cat sat") && !regexp.Regexp.Compile("\\bcat\\b", flags: "v")!.Matches("concatenate"), "word boundaries")
    check(whole(".", "\n") == false && whole(".", "\n", "vs"), "dot and the s flag")
    check(regexp.Regexp.Compile("^b", flags: "vm")!.Matches("a\nb") && !regexp.Regexp.Compile("^b", flags: "v")!.Matches("a\nb"), "^ at lines with m")
    check(whole("[\\d-]+", "1-2-3") && whole("[a\\-z]+", "a-z") && !whole("[a\\-z]+", "b"), "classes with escapes")
    check(whole("\\u{1F600}", "😀") && whole("\\x41\\u0042", "AB"), "\\u{...}, \\uHHHH and \\xHH")
    let groups = regexp.Regexp.Compile("(\\d+)-(x)?(\\d+)", flags: "v")!.Find("a 12-34 b")!
    check(groups.groups[0] == "12" && groups.groups[1] == nil && groups.groups[2] == "34", "captures, and nil for a group that took no part")

    print("Errors and limits")
    check(regexp.Regexp.Compile("(", flags: "v") == nil && regexp.Regexp.Compile("a{3,1}", flags: "v") == nil && regexp.Regexp.Compile("*a", flags: "v") == nil,
          "an invalid pattern doesn't compile")
    check(regexp.Regexp.Compile("\\q", flags: "v") == nil && regexp.Regexp.Compile("(a)\\2", flags: "v") == nil, "nor an unknown escape, or a reference to no group")
    check(regexp.Regexp.Compile("a", flags: "x") == nil, "nor an unknown flag")
    check(!whole("(a+)+b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaac"), "a pattern that backtracks without end gives up, unmatched")

    if failures == 0 {
        print("ALL REGEXP CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
