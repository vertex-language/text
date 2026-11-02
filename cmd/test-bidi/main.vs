// Runs text/bidi against Unicode's conformance test, BidiCharacterTest.txt
// (17.0.0): for each paragraph, the resolved paragraph level, each
// character's level after L1 (x where X9 removes it), and the visual
// order of what is kept.
//
//     vsc run test-bidi
package main

import (
    "fs"
    "text/bidi"
    "unicode"
)

let dir = "cmd/test-bidi/"

func hex(s: Substring) -> uint32 {
    var v: uint32 = 0
    for c in s.utf8 {
        var d: uint32 = 0
        if c >= 48 && c <= 57 { d = uint32(c - 48) } else if c >= 65 && c <= 70 { d = uint32(c - 55) } else if c >= 97 && c <= 102 { d = uint32(c - 87) } else { continue }
        v = v * 16 + d
    }
    return v
}

func removedByX9(cp: uint32) -> bool {
    switch unicode.BidiClassOf(cp) {
    case .RLE, .LRE, .RLO, .LRO, .PDF, .BN: return true
    default: return false
    }
}

func main() -> int32 {
    guard let file = try? fs.ReadText(fs.Path(dir + "testdata/BidiCharacterTest.txt")) else {
        print("test-bidi: can't read \(dir)testdata/BidiCharacterTest.txt")
        return 1
    }
    var cases = 0
    var failed = 0
    var shown = 0
    for raw in file.split(separator: "\n") {
        if raw.isEmpty || raw.hasPrefix("#") { continue }
        let f = raw.split(separator: ";", omittingEmptySubsequences: false)
        if f.count < 5 { continue }
        var text: [uint32] = []
        for h in f[0].split(separator: " ") { text.append(hex(h)) }
        var base: bidi.Direction? = nil
        if f[1] == "0" { base = .ltr } else if f[1] == "1" { base = .rtl }
        let wantBase = uint8(hex(f[2]))
        let wantLevels = f[3].split(separator: " ")
        let wantOrder = f[4].split(separator: " ")
        cases += 1

        let p = bidi.Levels(text, base: base)
        let line = bidi.LineLevels(text, p.levels, base: p.base, from: 0, to: text.count)
        var ok = p.base == wantBase && wantLevels.count == text.count
        var got = ""
        var i = 0
        while i < text.count {
            if removedByX9(text[i]) {
                got += i == 0 ? "x" : " x"
            } else {
                got += i == 0 ? "\(line[i])" : " \(line[i])"
            }
            i += 1
        }
        var want = ""
        for w in wantLevels { want += want.isEmpty ? string(w) : " " + string(w) }
        if got != want { ok = false }
        // The visual order of the characters X9 keeps.
        var kept: [int] = []
        var keptLevels: [uint8] = []
        i = 0
        while i < text.count {
            if !removedByX9(text[i]) {
                kept.append(i)
                keptLevels.append(line[i])
            }
            i += 1
        }
        var order = ""
        for k in bidi.VisualOrder(keptLevels) { order += order.isEmpty ? "\(kept[k])" : " \(kept[k])" }
        var wantOrderText = ""
        for w in wantOrder { wantOrderText += wantOrderText.isEmpty ? string(w) : " " + string(w) }
        if order != wantOrderText { ok = false }
        if !ok {
            failed += 1
            if shown < 12 {
                shown += 1
                print("FAIL  \(f[0]) dir \(f[1])\n      base \(p.base) want \(wantBase)\n      levels \(got)\n      want   \(want)\n      order  \(order)\n      want   \(wantOrderText)")
            }
        }
    }
    print("\(cases - failed) of \(cases) passed")
    if failed == 0 && cases > 0 {
        print("ALL BIDI CONFORMANCE TESTS PASSED")
        return 0
    }
    return 1
}
