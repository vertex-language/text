// Checks text/bidi: paragraph levels, the line rule and visual order,
// against cases worked by hand from UAX #9.
package main

import "text/bidi"

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func scalars(_ s: string) -> [uint32] {
    var out: [uint32] = []
    for u in s.unicodeScalars { out.append(u.value) }
    return out
}

func levels(_ s: string, _ base: bidi.Direction?) -> [uint8] {
    return bidi.Levels(scalars(s), base: base).levels
}

/// The levels as digits, one per character, for reading at a glance.
func digits(_ l: [uint8]) -> string {
    var out = ""
    for v in l { out += "\(v)" }
    return out
}

/// The levels at some positions, as digits.
func kept(_ l: [uint8], _ at: [int]) -> string {
    var out = ""
    for i in at { out += "\(l[i])" }
    return out
}

/// The text in the order it shows, after L1 over the whole as one line.
func visual(_ s: string, _ base: bidi.Direction?) -> string {
    let text = scalars(s)
    let p = bidi.Levels(text, base: base)
    let line = bidi.LineLevels(text, p.levels, base: p.base, from: 0, to: text.count)
    var out = ""
    for i in bidi.VisualOrder(line) {
        let cp = line[i] & 1 == 1 ? bidi.Mirror(text[i]) : text[i]
        out += string(Character(Unicode.Scalar(cp)!))
    }
    return out
}

func main() -> int32 {
    print("Paragraph levels")
    check(digits(levels("abc", .ltr)) == "000", "left-to-right text stays at 0")
    check(digits(levels("אבג", .ltr)) == "111", "Hebrew in a left-to-right paragraph is at 1")
    check(digits(levels("ab אב cd", .ltr)) == "00011000", "a Hebrew word among English: its spaces go with the English (got \(digits(levels("ab אב cd", .ltr))))")
    check(digits(levels("ab 12", .rtl)) == "22222", "English and its number in a right-to-left paragraph go up to 2 together (got \(digits(levels("ab 12", .rtl))))")
    check(digits(levels("אב 12", .rtl)) == "11122", "a number in Hebrew is raised to 2 (got \(digits(levels("אב 12", .rtl))))")
    check(digits(levels("سلام 12", .rtl)) == "1111122", "European digits after Arabic become Arabic numbers, at 2 (got \(digits(levels("سلام 12", .rtl))))")
    check(bidi.Levels(scalars("אבג abc"), base: nil).base == 1 && bidi.Levels(scalars("123 abc"), base: nil).base == 0,
          "with no base the first strong character decides, and numbers aren't strong")
    check(digits(levels("1+2=3", .rtl)) == "22212",
          "a + between digits joins them; the = between numbers goes with the paragraph (got \(digits(levels("1+2=3", .rtl))))")
    check(digits(levels("$12", .rtl)) == "222", "a currency sign before a number is part of it (got \(digits(levels("$12", .rtl))))")
    check(digits(levels("a\u{05B0}", .ltr)) == "00" && digits(levels("א\u{05B0}", .ltr)) == "11", "a non-spacing mark takes its base's level")

    print("Brackets")
    check(digits(levels("אב (cd) גד", .rtl)) == "1111221111", "brackets round English in Hebrew stay with the Hebrew (got \(digits(levels("אב (cd) גד", .rtl))))")
    check(digits(levels("ab (אב) cd", .ltr)) == "0000110000", "and brackets round Hebrew in English with the English (got \(digits(levels("ab (אב) cd", .ltr))))")
    check(digits(levels("אב (cd)", .ltr)) == "1100000",
          "brackets after Hebrew round English in an English paragraph (got \(digits(levels("אב (cd)", .ltr))))")

    print("Explicit embeddings and isolates")
    // The embedding marks themselves drop out (X9): only the text's levels are compared.
    check(kept(levels("a\u{202B}b\u{202C}c", .ltr), [0, 2, 4]) == "020", "RLE raises what it holds; L in an odd embedding is at 2 (got \(kept(levels("a\u{202B}b\u{202C}c", .ltr), [0, 2, 4])))")
    check(kept(levels("\u{202E}abc\u{202C}", .ltr), [1, 2, 3]) == "111", "RLO makes what it holds R (got \(kept(levels("\u{202E}abc\u{202C}", .ltr), [1, 2, 3])))")
    check(digits(levels("a \u{2067}b\u{2069} c", .ltr)) == "0002000", "an isolate's content is raised, the isolate marks stay outside (got \(digits(levels("a \u{2067}b\u{2069} c", .ltr))))")
    check(digits(levels("א \u{2066}b\u{2069} ג", .ltr)) == "1112111",
          "an isolate between Hebrew words keeps the words together (got \(digits(levels("א \u{2066}b\u{2069} ג", .ltr))))")
    check(digits(levels("\u{2068}אב\u{2069} c", .ltr)) == "011000", "FSI takes the direction of its first strong character (got \(digits(levels("\u{2068}אב\u{2069} c", .ltr))))")

    print("Lines and visual order")
    check(visual("ab אבג cd", .ltr) == "ab גבא cd", "Hebrew reads right to left inside English (got \(visual("ab אבג cd", .ltr)))")
    check(visual("אבג def", .rtl) == "def גבא", "English in a right-to-left paragraph shows on the left (got \(visual("אבג def", .rtl)))")
    check(visual("אב 123", .rtl) == "123 בא", "a number keeps its digits' order (got \(visual("אב 123", .rtl)))")
    check(visual("אב (cd)", .rtl) == "(cd) בא", "brackets mirror at an odd level (got \(visual("אב (cd)", .rtl)))")
    check(visual("אב.", .rtl) == ".בא", "a full stop at the end goes to the left (got \(visual("אב.", .rtl)))")
    let line = bidi.LineLevels(scalars("אב  "), levels("אב  ", .ltr), base: 0, from: 0, to: 4)
    check(digits(line) == "1100", "trailing spaces go to the paragraph's level (got \(digits(line)))")
    check(bidi.VisualOrder([0, 1, 1, 0, 2, 2, 1]) == [0, 2, 1, 3, 6, 4, 5],
          "VisualOrder reverses each run from the highest level down (got \(bidi.VisualOrder([0, 1, 1, 0, 2, 2, 1])))")
    check(bidi.VisualOrder([1, 2, 2, 1]) == [3, 1, 2, 0], "a raised run inside an odd one keeps its own order (got \(bidi.VisualOrder([1, 2, 2, 1])))")
    check(bidi.Mirror(0x28) == 0x29 && bidi.Mirror(0x5D) == 0x5B && bidi.Mirror(0x3C) == 0x3E && bidi.Mirror(0x41) == 0x41, "Mirror pairs brackets and leaves the rest")
    check(bidi.HasRightToLeft(scalars("hello")) == false && bidi.HasRightToLeft(scalars("hi שלום")) && bidi.HasRightToLeft(scalars("٣")),
          "HasRightToLeft finds Hebrew and Arabic numbers")

    if failures == 0 {
        print("ALL BIDI CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
