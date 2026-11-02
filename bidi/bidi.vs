package bidi

import "unicode"

// The Unicode Bidirectional Algorithm (UAX #9): the embedding level of
// each character of a paragraph, then the order a line's characters
// show in. Levels gives the paragraph's levels (rules P2 to I2, with
// explicit embeddings, overrides and isolates, and bracket pairs);
// LineLevels applies L1 to a line of it; VisualOrder is L2.

/// A paragraph's or an embedding's direction.
public enum Direction: Equatable {
    case ltr
    case rtl
}

/// The deepest an embedding may go (BD2).
let maxDepth: uint8 = 125

/// Whether text holds anything that could put a character right to
/// left: a right-to-left letter, an Arabic number, or a right-to-left
/// embedding, override or isolate. Text without one in a left-to-right
/// paragraph needs no reordering.
public func HasRightToLeft(text: [uint32]) -> bool {
    for cp in text {
        switch unicode.BidiClassOf(cp) {
        case .R, .AL, .AN, .RLE, .RLO, .RLI, .FSI: return true
        default: break
        }
    }
    return false
}

/// The direction of the first strong character of text, skipping what
/// isolates hold (P2 and P3), or nil where it has none.
public func FirstStrong(text: [uint32]) -> Direction? {
    var classes: [unicode.BidiClass] = []
    for cp in text { classes.append(unicode.BidiClassOf(cp)) }
    return firstStrong(classes, 0, classes.count)
}

func firstStrong(classes: [unicode.BidiClass], from: int, to: int) -> Direction? {
    var depth = 0
    var i = from
    while i < to {
        switch classes[i] {
        case .L: if depth == 0 { return .ltr }
        case .R, .AL: if depth == 0 { return .rtl }
        case .LRI, .RLI, .FSI: depth += 1
        case .PDI:
            if depth == 0 { return nil }
            depth -= 1
        case .B: return nil
        default: break
        }
        i += 1
    }
    return nil
}

/// The embedding levels of a paragraph's characters, and the
/// paragraph's own level. With no base direction the first strong
/// character chooses it (left to right where there is none).
public func Levels(text: [uint32], base: Direction?) -> (levels: [uint8], base: uint8) {
    let n = text.count
    var classes: [unicode.BidiClass] = []
    for cp in text { classes.append(unicode.BidiClassOf(cp)) }
    let original = classes
    var paragraph: uint8 = 0
    if let b = base {
        paragraph = b == .rtl ? 1 : 0
    } else if firstStrong(classes, 0, n) == .rtl {
        paragraph = 1
    }
    var levels = [uint8](repeating: paragraph, count: n)

    // X1 to X8: the explicit embeddings, overrides and isolates.
    struct Entry {
        var level: uint8
        var override: unicode.BidiClass?
        var isolate: bool
    }
    var stack: [Entry] = [Entry(level: paragraph, override: nil, isolate: false)]
    var overflowIsolates = 0
    var overflowEmbeddings = 0
    var validIsolates = 0
    let matches = matchIsolates(classes)
    var i = 0
    while i < n {
        let c = classes[i]
        let top = stack[stack.count - 1]
        switch c {
        case .RLE, .LRE, .RLO, .LRO:
            levels[i] = top.level
            let rtl = c == .RLE || c == .RLO
            let next = rtl ? (top.level + 1) | 1 : (top.level + 2) & 0xFE
            if next <= maxDepth && overflowIsolates == 0 && overflowEmbeddings == 0 {
                var o: unicode.BidiClass? = nil
                if c == .RLO { o = .R } else if c == .LRO { o = .L }
                stack.append(Entry(level: next, override: o, isolate: false))
            } else if overflowIsolates == 0 {
                overflowEmbeddings += 1
            }
        case .RLI, .LRI, .FSI:
            levels[i] = top.level
            if let o = top.override { classes[i] = o }
            var rtl = c == .RLI
            if c == .FSI {
                let end = matches[i] >= 0 ? matches[i] : n
                rtl = firstStrong(original, i + 1, end) == .rtl
            }
            let next = rtl ? (top.level + 1) | 1 : (top.level + 2) & 0xFE
            if next <= maxDepth && overflowIsolates == 0 && overflowEmbeddings == 0 {
                validIsolates += 1
                stack.append(Entry(level: next, override: nil, isolate: true))
            } else {
                overflowIsolates += 1
            }
        case .PDI:
            if overflowIsolates > 0 {
                overflowIsolates -= 1
            } else if validIsolates > 0 {
                overflowEmbeddings = 0
                while !stack[stack.count - 1].isolate { stack.removeLast() }
                stack.removeLast()
                validIsolates -= 1
            }
            let now = stack[stack.count - 1]
            levels[i] = now.level
            if let o = now.override { classes[i] = o }
        case .PDF:
            if overflowIsolates > 0 {
            } else if overflowEmbeddings > 0 {
                overflowEmbeddings -= 1
            } else if !top.isolate && stack.count >= 2 {
                stack.removeLast()
            }
            levels[i] = stack[stack.count - 1].level
        case .B:
            levels[i] = paragraph
        case .BN:
            levels[i] = top.level
        default:
            levels[i] = top.level
            if let o = top.override { classes[i] = o }
        }
        i += 1
    }

    // X9: the embedding characters and boundary neutrals drop out; what
    // follows sees past them.
    var kept: [int] = []
    i = 0
    while i < n {
        switch original[i] {
        case .RLE, .LRE, .RLO, .LRO, .PDF, .BN: break
        default: kept.append(i)
        }
        i += 1
    }

    // X10: level runs, chained across isolates into isolating run
    // sequences.
    var runs: [[int]] = []
    for k in kept {
        if let last = runs.last, levels[last[last.count - 1]] == levels[k] {
            runs[runs.count - 1].append(k)
        } else {
            runs.append([k])
        }
    }
    var runOf = [int](repeating: -1, count: n)
    var r = 0
    while r < runs.count {
        for k in runs[r] { runOf[k] = r }
        r += 1
    }
    var placed = [bool](repeating: false, count: runs.count)
    var sequences: [[int]] = []
    r = 0
    while r < runs.count {
        if placed[r] { r += 1; continue }
        var seq: [int] = []
        var cur = r
        while true {
            placed[cur] = true
            seq += runs[cur]
            let last = runs[cur][runs[cur].count - 1]
            let lc = original[last]
            if (lc == .LRI || lc == .RLI || lc == .FSI) && matches[last] >= 0 && runOf[matches[last]] >= 0 {
                cur = runOf[matches[last]]
                continue
            }
            break
        }
        sequences.append(seq)
        r += 1
    }

    // Where a removed character sits, the level of what is kept nearest
    // before it, for sos and eos.
    var keptIndex = [int](repeating: -1, count: n)
    var p = 0
    while p < kept.count {
        keptIndex[kept[p]] = p
        p += 1
    }

    for seq in sequences {
        let level = levels[seq[0]]
        let ki = keptIndex[seq[0]]
        let before = ki > 0 ? levels[kept[ki - 1]] : paragraph
        let sos: unicode.BidiClass = ((before > level ? before : level) & 1) == 1 ? .R : .L
        let lastIdx = seq[seq.count - 1]
        var after = paragraph
        let lastClass = original[lastIdx]
        if !(lastClass == .LRI || lastClass == .RLI || lastClass == .FSI) {
            let kj = keptIndex[lastIdx]
            if kj + 1 < kept.count { after = levels[kept[kj + 1]] }
        }
        let eos: unicode.BidiClass = ((after > level ? after : level) & 1) == 1 ? .R : .L
        resolveSequence(seq, &classes, original, text, level, sos, eos)
    }

    // I1 and I2: the implicit levels.
    for k in kept {
        let c = classes[k]
        if levels[k] & 1 == 0 {
            if c == .R { levels[k] += 1 } else if c == .AN || c == .EN { levels[k] += 2 }
        } else if c == .L || c == .EN || c == .AN {
            levels[k] += 1
        }
    }
    // The removed characters take the level before them.
    i = 0
    while i < n {
        if keptIndex[i] < 0 { levels[i] = i > 0 ? levels[i - 1] : paragraph }
        i += 1
    }
    return (levels: levels, base: paragraph)
}

/// Each isolate initiator's matching PDI and each PDI's initiator
/// (BD9), or -1.
func matchIsolates(classes: [unicode.BidiClass]) -> [int] {
    var out = [int](repeating: -1, count: classes.count)
    var open: [int] = []
    var i = 0
    while i < classes.count {
        switch classes[i] {
        case .LRI, .RLI, .FSI: open.append(i)
        case .PDI:
            if let o = open.popLast() {
                out[o] = i
                out[i] = o
            }
        case .B: open = []
        default: break
        }
        i += 1
    }
    return out
}

func isNeutralOrIsolate(c: unicode.BidiClass) -> bool {
    switch c {
    case .B, .S, .WS, .ON, .LRI, .RLI, .FSI, .PDI: return true
    default: return false
    }
}

/// W1 to W7, N0 to N2 over one isolating run sequence.
func resolveSequence(seq: [int], classes: inout [unicode.BidiClass], original: [unicode.BidiClass], text: [uint32],
                     level: uint8, sos: unicode.BidiClass, eos: unicode.BidiClass) {
    let m = seq.count
    // W1: a non-spacing mark takes the class before it.
    var j = 0
    while j < m {
        if classes[seq[j]] == .NSM {
            if j == 0 {
                classes[seq[j]] = sos
            } else {
                let prev = classes[seq[j - 1]]
                classes[seq[j]] = (prev == .LRI || prev == .RLI || prev == .FSI || prev == .PDI) ? .ON : prev
            }
        }
        j += 1
    }
    // W2 and W3: European numbers after an Arabic letter are Arabic
    // numbers; Arabic letters are R.
    var lastStrong = sos
    j = 0
    while j < m {
        let c = classes[seq[j]]
        if c == .L || c == .R || c == .AL { lastStrong = c }
        if c == .EN && lastStrong == .AL { classes[seq[j]] = .AN }
        j += 1
    }
    j = 0
    while j < m {
        if classes[seq[j]] == .AL { classes[seq[j]] = .R }
        j += 1
    }
    // W4: one separator between two numbers of a kind joins them.
    j = 1
    while j + 1 < m {
        let c = classes[seq[j]]
        let a = classes[seq[j - 1]]
        let b = classes[seq[j + 1]]
        if c == .ES && a == .EN && b == .EN { classes[seq[j]] = .EN }
        if c == .CS && a == .EN && b == .EN { classes[seq[j]] = .EN }
        if c == .CS && a == .AN && b == .AN { classes[seq[j]] = .AN }
        j += 1
    }
    // W5: terminators next to a European number are part of it.
    j = 0
    while j < m {
        if classes[seq[j]] == .ET {
            var e = j
            while e < m && classes[seq[e]] == .ET { e += 1 }
            let touches = (j > 0 && classes[seq[j - 1]] == .EN) || (e < m && classes[seq[e]] == .EN)
            if touches {
                var k = j
                while k < e { classes[seq[k]] = .EN; k += 1 }
            }
            j = e
        } else {
            j += 1
        }
    }
    // W6: the separators and terminators left are neutral.
    j = 0
    while j < m {
        let c = classes[seq[j]]
        if c == .ES || c == .ET || c == .CS { classes[seq[j]] = .ON }
        j += 1
    }
    // W7: European numbers after left-to-right text are L.
    lastStrong = sos
    j = 0
    while j < m {
        let c = classes[seq[j]]
        if c == .L || c == .R { lastStrong = c }
        if c == .EN && lastStrong == .L { classes[seq[j]] = .L }
        j += 1
    }

    let embedding: unicode.BidiClass = level & 1 == 1 ? .R : .L
    // The strong direction a class gives the neutral rules: numbers
    // count as R.
    func strong(c: unicode.BidiClass) -> unicode.BidiClass? {
        switch c {
        case .L: return .L
        case .R, .EN, .AN: return .R
        default: return nil
        }
    }

    // N0: paired brackets take the direction of what they hold.
    var pairs: [(int, int)] = []
    var openers: [(int, uint32)] = []
    j = 0
    while j < m && openers.count <= 63 {
        let k = seq[j]
        if classes[k] == .ON {
            let cp = canonicalBracket(text[k])
            if let close = closingBracket(cp) {
                if openers.count == 63 { break }
                openers.append((j, close))
            } else if isClosingBracket(cp) {
                var s = openers.count - 1
                while s >= 0 {
                    if openers[s].1 == cp {
                        pairs.append((openers[s].0, j))
                        openers.removeLast(openers.count - s)
                        break
                    }
                    s -= 1
                }
            }
        }
        j += 1
    }
    pairs.sort { $0.0 < $1.0 }
    for (o, c) in pairs {
        var sawEmbedding = false
        var sawOpposite = false
        var q = o + 1
        while q < c {
            if let d = strong(classes[seq[q]]) {
                if d == embedding { sawEmbedding = true } else { sawOpposite = true }
            }
            q += 1
        }
        var set: unicode.BidiClass? = nil
        if sawEmbedding {
            set = embedding
        } else if sawOpposite {
            // What comes before the opening bracket decides.
            var context = sos
            var b = o - 1
            while b >= 0 {
                if let d = strong(classes[seq[b]]) { context = d; break }
                b -= 1
            }
            set = context != embedding ? context : embedding
        }
        if let d = set {
            for at in [o, c] {
                classes[seq[at]] = d
                // Marks on the bracket follow it.
                var t = at + 1
                while t < m && original[seq[t]] == .NSM {
                    classes[seq[t]] = d
                    t += 1
                }
            }
        }
    }

    // N1 and N2: a run of neutrals between two strong sides of one
    // direction takes it, and otherwise the embedding's.
    j = 0
    while j < m {
        if !isNeutralOrIsolate(classes[seq[j]]) { j += 1; continue }
        var e = j
        while e < m && isNeutralOrIsolate(classes[seq[e]]) { e += 1 }
        var before = sos
        if j > 0, let d = strong(classes[seq[j - 1]]) { before = d }
        var after = eos
        if e < m, let d = strong(classes[seq[e]]) { after = d }
        let d = before == after ? before : embedding
        var k = j
        while k < e { classes[seq[k]] = d; k += 1 }
        j = e
    }
}

/// The levels of a line of a paragraph, from..<to of its text: L1 sends
/// segment and paragraph separators, and the whitespace and isolate
/// formatters before them or at the line's end, to the paragraph's
/// level.
public func LineLevels(text: [uint32], levels: [uint8], base: uint8, from: int, to: int) -> [uint8] {
    var out: [uint8] = []
    var i = from
    while i < to {
        out.append(levels[i])
        i += 1
    }
    func trailing(c: unicode.BidiClass) -> bool {
        switch c {
        case .WS, .LRI, .RLI, .FSI, .PDI, .BN, .LRE, .RLE, .LRO, .RLO, .PDF: return true
        default: return false
        }
    }
    var j = out.count - 1
    // From the end back, and back from each separator.
    var resetting = true
    while j >= 0 {
        let c = unicode.BidiClassOf(text[from + j])
        if c == .S || c == .B {
            out[j] = base
            resetting = true
        } else if resetting && trailing(c) {
            out[j] = base
        } else {
            resetting = false
        }
        j -= 1
    }
    return out
}

/// The order a line's characters show in, left to right, as indexes
/// into levels (L2): from the highest level down to the lowest odd one,
/// every run at that level or above is reversed.
public func VisualOrder(levels: [uint8]) -> [int] {
    var order: [int] = []
    var i = 0
    while i < levels.count {
        order.append(i)
        i += 1
    }
    if levels.isEmpty { return order }
    var highest: uint8 = 0
    var lowestOdd: uint8 = 255
    for l in levels {
        if l > highest { highest = l }
        if l & 1 == 1 && l < lowestOdd { lowestOdd = l }
    }
    if lowestOdd == 255 { return order }
    var level = highest
    while level >= lowestOdd {
        var j = 0
        while j < levels.count {
            if levels[order[j]] >= level {
                var e = j
                while e < levels.count && levels[order[e]] >= level { e += 1 }
                var a = j
                var b = e - 1
                while a < b {
                    let t = order[a]
                    order[a] = order[b]
                    order[b] = t
                    a += 1
                    b -= 1
                }
                j = e
            } else {
                j += 1
            }
        }
        if level == 0 { break }
        level -= 1
    }
    return order
}

// MARK: brackets and mirroring

/// The paired brackets (BidiBrackets.txt), opening then closing, and
/// other common mirrored pairs (BidiMirroring.txt).
let bracketPairs: [(uint32, uint32)] = [
    (0x28, 0x29), (0x5B, 0x5D), (0x7B, 0x7D), (0xF3A, 0xF3B), (0xF3C, 0xF3D), (0x169B, 0x169C),
    (0x2045, 0x2046), (0x207D, 0x207E), (0x208D, 0x208E), (0x2308, 0x2309), (0x230A, 0x230B),
    (0x2329, 0x232A), (0x2768, 0x2769), (0x276A, 0x276B), (0x276C, 0x276D), (0x276E, 0x276F),
    (0x2770, 0x2771), (0x2772, 0x2773), (0x2774, 0x2775), (0x27C5, 0x27C6), (0x27E6, 0x27E7),
    (0x27E8, 0x27E9), (0x27EA, 0x27EB), (0x27EC, 0x27ED), (0x27EE, 0x27EF), (0x2983, 0x2984),
    (0x2985, 0x2986), (0x2987, 0x2988), (0x2989, 0x298A), (0x298B, 0x298C), (0x2991, 0x2992),
    (0x2993, 0x2994), (0x2995, 0x2996), (0x2997, 0x2998), (0x29D8, 0x29D9), (0x29DA, 0x29DB),
    (0x29FC, 0x29FD), (0x2E22, 0x2E23), (0x2E24, 0x2E25), (0x2E26, 0x2E27), (0x2E28, 0x2E29),
    (0x3008, 0x3009), (0x300A, 0x300B), (0x300C, 0x300D), (0x300E, 0x300F), (0x3010, 0x3011),
    (0x3014, 0x3015), (0x3016, 0x3017), (0x3018, 0x3019), (0x301A, 0x301B), (0xFE59, 0xFE5A),
    (0xFE5B, 0xFE5C), (0xFE5D, 0xFE5E), (0xFF08, 0xFF09), (0xFF3B, 0xFF3D), (0xFF5B, 0xFF5D),
    (0xFF5F, 0xFF60), (0xFF62, 0xFF63),
]

let otherMirrors: [(uint32, uint32)] = [
    (0x3C, 0x3E), (0xAB, 0xBB), (0x2039, 0x203A), (0x2264, 0x2265), (0x2266, 0x2267),
    (0x226A, 0x226B), (0x2282, 0x2283), (0x2286, 0x2287), (0x22D6, 0x22D7),
]

/// U+2329 and U+232A are canonically U+3008 and U+3009, and pair with
/// them.
func canonicalBracket(cp: uint32) -> uint32 {
    if cp == 0x2329 { return 0x3008 }
    if cp == 0x232A { return 0x3009 }
    return cp
}

func closingBracket(cp: uint32) -> uint32? {
    for (o, c) in bracketPairs where o == cp { return canonicalBracket(c) }
    return nil
}

func isClosingBracket(cp: uint32) -> bool {
    for (_, c) in bracketPairs where canonicalBracket(c) == cp { return true }
    return false
}

/// The character that shows in cp's place at an odd level: a bracket
/// or other mirrored character's pair, or cp itself.
public func Mirror(cp: uint32) -> uint32 {
    for (a, b) in bracketPairs {
        if a == cp { return b }
        if b == cp { return a }
    }
    for (a, b) in otherMirrors {
        if a == cp { return b }
        if b == cp { return a }
    }
    return cp
}
