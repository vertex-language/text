package regexp

import "unicode"

// Regular expressions as ECMAScript writes them, matched by backtracking
// over a string's Unicode scalars: alternation, groups (capturing, non-
// capturing and named), lookahead and lookbehind, backreferences,
// greedy and lazy quantifiers, character classes with ranges and
// escapes (\d \w \s and their negations, \p{...} by general category,
// script or binary property), anchors and word boundaries. Flags: i
// (case-insensitive, by simple case folding), m (^ and $ at lines), s
// (. matches newlines), u and v (Unicode mode, which this always is).
// What HTML's pattern attribute needs, and what a program reaches for.

/// How a piece of a pattern matches.
enum Kind: Equatable {
    case empty
    case char
    case any
    case set
    case seq
    case alt
    case group
    case quantified
    case start
    case end
    case boundary
    case notBoundary
    case lookahead
    case lookbehind
    case backref
}

/// A parsed piece of a pattern.
final class Node {
    let kind: Kind
    var children: [Node] = []
    var char: uint32 = 0
    var set: CharSet? = nil
    /// A group's capture number, or -1.
    var index: int = -1
    var min: int = 0
    var max: int = -1
    var greedy: bool = true
    /// A lookaround's sense: false for (?! and (?<!.
    var positive: bool = true

    init(kind: Kind) {
        self.kind = kind
    }
}

/// A character class: ranges, named classes, and whether it's negated.
final class CharSet {
    var ranges: [(uint32, uint32)] = []
    /// \d \w \s (and capitals, negated) and \p{...} tests inside it.
    var tests: [(uint32) -> bool] = []
    var negated: bool = false

    func contains(c: uint32, fold: bool) -> bool {
        var hit = has(c)
        if !hit && fold {
            let f = unicode.CaseFold(c)
            hit = has(f) || has(unicode.ToUpper(c)) || has(unicode.ToLower(c))
        }
        return hit != negated
    }

    func has(c: uint32) -> bool {
        for (lo, hi) in ranges where c >= lo && c <= hi { return true }
        for t in tests where t(c) { return true }
        return false
    }
}

/// A compiled regular expression.
public final class Regexp {
    let root: Node
    let groups: int
    let names: [string: int]
    let fold: bool
    let multiline: bool
    let dotAll: bool

    init(root: Node, groups: int, names: [string: int], flags: string) {
        self.root = root
        self.groups = groups
        self.names = names
        fold = flags.contains("i")
        multiline = flags.contains("m")
        dotAll = flags.contains("s")
    }

    /// Compile parses a pattern with flags ("i", "m", "s", "u", "v" in
    /// any mix), or answers nil where it isn't a valid pattern.
    public static func Compile(pattern: string, flags: string = "") -> Regexp? {
        for f in flags where !"imsuvgdy".contains(f) { return nil }
        var p = Parser(pattern)
        guard let root = p.alternation(), p.atEnd else { return nil }
        if p.failed { return nil }
        for r in p.backrefs where r > p.groupCount { return nil }
        return Regexp(root: root, groups: p.groupCount, names: p.names, flags: flags)
    }

    /// Whether the pattern matches somewhere in s.
    public func Matches(s: string) -> bool {
        return Find(s) != nil
    }

    /// Whether the pattern matches the whole of s, as HTML's pattern
    /// attribute asks (`^(?:pattern)$`).
    public func MatchesWhole(s: string) -> bool {
        let m = Matcher(self, scalars(s))
        return m.run(at: 0, whole: true) != nil
    }

    /// The first match in s: where it starts and ends, in scalars, and
    /// each group's text (nil for a group that didn't take part).
    public func Find(s: string) -> (start: int, end: int, groups: [string?])? {
        let text = scalars(s)
        let m = Matcher(self, text)
        var i = 0
        while i <= text.count {
            if let end = m.run(at: i, whole: false) {
                var out: [string?] = []
                var g = 1
                while g <= groups {
                    let (a, b) = m.captures[g]
                    out.append(a >= 0 && b >= a ? stringOf(text, a, b) : nil)
                    g += 1
                }
                return (start: i, end: end, groups: out)
            }
            i += 1
        }
        return nil
    }

    /// A named group's number, or nil.
    public func GroupIndex(name: string) -> int? {
        return names[name]
    }
}

func scalars(s: string) -> [uint32] {
    var out: [uint32] = []
    for u in s.unicodeScalars { out.append(u.value) }
    return out
}

func stringOf(text: [uint32], a: int, b: int) -> string {
    var out = ""
    var i = a
    while i < b {
        if let u = Unicode.Scalar(text[i]) { out += string(Character(u)) }
        i += 1
    }
    return out
}

// MARK: matching

final class Matcher {
    let re: Regexp
    let text: [uint32]
    var captures: [(int, int)]
    /// How many steps the match has taken: a pattern that backtracks
    /// without end gives up rather than hanging.
    var steps = 0
    let budget = 2_000_000

    init(re: Regexp, text: [uint32]) {
        self.re = re
        self.text = text
        captures = Array(repeating: (-1, -1), count: re.groups + 1)
    }

    func run(at i: int, whole: bool) -> int? {
        var i2 = 0
        while i2 < captures.count {
            captures[i2] = (-1, -1)
            i2 += 1
        }
        steps = 0
        var end = -1
        let ok = match(re.root, i, { j in
            if whole && j != self.text.count { return false }
            end = j
            return true
        })
        return ok ? end : nil
    }

    func isWord(c: uint32) -> bool {
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    func isLineEnd(c: uint32) -> bool {
        return c == 10 || c == 13 || c == 0x2028 || c == 0x2029
    }

    func same(a: uint32, b: uint32) -> bool {
        if a == b { return true }
        return re.fold && unicode.CaseFold(a) == unicode.CaseFold(b)
    }

    /// Whether node matches at i with what follows (k) matching after.
    func match(node: Node, i: int, k: (int) -> bool) -> bool {
        steps += 1
        if steps > budget { return false }
        switch node.kind {
        case .empty:
            return k(i)
        case .char:
            return i < text.count && same(text[i], node.char) && k(i + 1)
        case .any:
            return i < text.count && (re.dotAll || !isLineEnd(text[i])) && k(i + 1)
        case .set:
            return i < text.count && node.set!.contains(text[i], re.fold) && k(i + 1)
        case .seq:
            return seq(node.children, 0, i, k)
        case .alt:
            for c in node.children where match(c, i, k) { return true }
            return false
        case .group:
            if node.index < 0 { return match(node.children[0], i, k) }
            let saved = captures[node.index]
            if match(node.children[0], i, { j in
                let inner = self.captures[node.index]
                self.captures[node.index] = (i, j)
                if k(j) { return true }
                self.captures[node.index] = inner
                return false
            }) { return true }
            captures[node.index] = saved
            return false
        case .quantified:
            return repeatFrom(node, 0, i, -1, k)
        case .start:
            return (i == 0 || (re.multiline && isLineEnd(text[i - 1]))) && k(i)
        case .end:
            return (i == text.count || (re.multiline && isLineEnd(text[i]))) && k(i)
        case .boundary, .notBoundary:
            let before = i > 0 && isWord(text[i - 1])
            let after = i < text.count && isWord(text[i])
            let at = before != after
            return (node.kind == .boundary ? at : !at) && k(i)
        case .lookahead:
            let saved = captures
            let hit = match(node.children[0], i, { _ in true })
            if !node.positive { captures = saved }
            if hit != node.positive { captures = saved; return false }
            if k(i) { return true }
            captures = saved
            return false
        case .lookbehind:
            // Some start before i from which the body ends exactly at i.
            let saved = captures
            var hit = false
            var s = i
            while s >= 0 && !hit {
                if match(node.children[0], s, { j in j == i }) { hit = true }
                s -= 1
            }
            if !node.positive { captures = saved }
            if hit != node.positive { captures = saved; return false }
            if k(i) { return true }
            captures = saved
            return false
        case .backref:
            let (a, b) = captures[node.index]
            if a < 0 { return k(i) }
            let n = b - a
            if i + n > text.count { return false }
            var t = 0
            while t < n {
                if !same(text[i + t], text[a + t]) { return false }
                t += 1
            }
            return k(i + n)
        }
    }

    func seq(parts: [Node], at: int, i: int, k: (int) -> bool) -> bool {
        if at == parts.count { return k(i) }
        return match(parts[at], i, { j in self.seq(parts, at + 1, j, k) })
    }

    /// A quantifier after `count` turns, at i; last is where the turn
    /// before began, so an empty turn doesn't go round forever.
    func repeatFrom(node: Node, count: int, i: int, last: int, k: (int) -> bool) -> bool {
        let body = node.children[0]
        if count < node.min {
            return match(body, i, { j in self.repeatFrom(node, count + 1, j, i, k) })
        }
        if node.max >= 0 && count >= node.max { return k(i) }
        if i == last { return k(i) }
        if node.greedy {
            if match(body, i, { j in j != i && self.repeatFrom(node, count + 1, j, i, k) }) { return true }
            return k(i)
        }
        if k(i) { return true }
        return match(body, i, { j in j != i && self.repeatFrom(node, count + 1, j, i, k) })
    }
}

// MARK: parsing

struct Parser {
    let p: [uint32]
    var i = 0
    var groupCount = 0
    var names: [string: int] = [:]
    var backrefs: [int] = []
    var failed = false

    init(pattern: string) {
        p = scalars(pattern)
    }

    var atEnd: bool { return i >= p.count }

    func peek(k: int = 0) -> uint32 {
        return i + k < p.count ? p[i + k] : 0
    }

    mutating func eat(c: uint32) -> bool {
        if i < p.count && p[i] == c {
            i += 1
            return true
        }
        return false
    }

    mutating func alternation() -> Node? {
        var branches: [Node] = []
        guard let first = sequence() else { return nil }
        branches.append(first)
        while eat(124) {   // |
            guard let next = sequence() else { return nil }
            branches.append(next)
        }
        if branches.count == 1 { return branches[0] }
        let n = Node(.alt)
        n.children = branches
        return n
    }

    mutating func sequence() -> Node? {
        let n = Node(.seq)
        while i < p.count && p[i] != 124 && p[i] != 41 {   // | )
            guard var atom = atom() else { return nil }
            if let q = quantifier(atom) { atom = q } else if failed { return nil }
            n.children.append(atom)
        }
        return n
    }

    mutating func quantifier(atom: Node) -> Node? {
        var lo = 0
        var hi = -1
        let c = peek()
        if c == 42 { lo = 0; hi = -1; i += 1 }        // *
        else if c == 43 { lo = 1; hi = -1; i += 1 }   // +
        else if c == 63 { lo = 0; hi = 1; i += 1 }    // ?
        else if c == 123 {                            // {
            let save = i
            i += 1
            guard let a = number() else { i = save; return nil }
            lo = a
            hi = a
            if eat(44) { hi = number() ?? -1 }        // ,
            if !eat(125) { i = save; return nil }     // }
            if hi >= 0 && hi < lo { failed = true; return nil }
        } else {
            return nil
        }
        if atom.kind == .start || atom.kind == .end || atom.kind == .boundary || atom.kind == .notBoundary || atom.kind == .lookbehind {
            failed = true
            return nil
        }
        let n = Node(.quantified)
        n.children = [atom]
        n.min = lo
        n.max = hi
        n.greedy = !eat(63)
        return n
    }

    mutating func number() -> int? {
        var v = 0
        var any = false
        while i < p.count && p[i] >= 48 && p[i] <= 57 {
            v = v * 10 + int(p[i] - 48)
            i += 1
            any = true
        }
        return any ? v : nil
    }

    mutating func atom() -> Node? {
        let c = p[i]
        i += 1
        switch c {
        case 94: return Node(.start)            // ^
        case 36: return Node(.end)              // $
        case 46: return Node(.any)              // .
        case 40:                                // (
            var n = Node(.group)
            if eat(63) {                        // ?
                if eat(58) {                    // (?:
                } else if eat(61) || eat(33) {  // (?= (?!
                    n = Node(.lookahead)
                    n.positive = p[i - 1] == 61
                } else if peek() == 60 && (peek(1) == 61 || peek(1) == 33) {   // (?<= (?<!
                    i += 1
                    n = Node(.lookbehind)
                    n.positive = p[i] == 61
                    i += 1
                } else if eat(60) {             // (?<name>
                    var name = ""
                    while i < p.count && p[i] != 62 {
                        if let u = Unicode.Scalar(p[i]) { name += string(Character(u)) }
                        i += 1
                    }
                    if !eat(62) || name.isEmpty || names[name] != nil { return nil }
                    groupCount += 1
                    n.index = groupCount
                    names[name] = groupCount
                } else {
                    return nil
                }
            } else {
                groupCount += 1
                n.index = groupCount
            }
            guard let inner = alternation(), eat(41) else { return nil }
            n.children = [inner]
            return n
        case 41, 41: return nil                 // )
        case 91: return charClass()             // [
        case 92: return escape(inClass: false)  // \
        case 42, 43, 63: return nil             // a quantifier with nothing before it
        case 123:
            // A brace that isn't a quantifier is an error in Unicode mode.
            return nil
        case 93, 125: return nil                // ] } alone, in Unicode mode
        default:
            let n = Node(.char)
            n.char = c
            return n
        }
    }

    mutating func charClass() -> Node? {
        let set = CharSet()
        if eat(94) { set.negated = true }       // ^
        var first = true
        while i < p.count && (p[i] != 93 || false) {   // ]
            if p[i] == 93 && !first { break }
            if p[i] == 93 { break }
            first = false
            // A nested class (v mode): its members join this one.
            if p[i] == 91 {
                i += 1
                guard let inner = charClass(), let s = inner.set else { return nil }
                set.tests.append({ c in s.contains(c, false) })
                continue
            }
            guard let lo = classAtom(set) else { if failed { return nil }; continue }
            if peek() == 45 && peek(1) != 93 && i + 1 < p.count {   // a-z
                i += 1
                guard let hi = classAtom(set) else { return nil }
                if hi < lo { return nil }
                set.ranges.append((lo, hi))
            } else {
                set.ranges.append((lo, lo))
            }
        }
        if !eat(93) { return nil }
        let n = Node(.set)
        n.set = set
        return n
    }

    /// One member of a class: a character (answered), or a named class
    /// (added to set, answered nil).
    mutating func classAtom(set: CharSet) -> uint32? {
        let c = p[i]
        i += 1
        if c != 92 { return c }
        guard let e = escape(inClass: true) else { failed = true; return nil }
        if e.kind == .char { return e.char }
        if let s = e.set { set.tests.append({ ch in s.contains(ch, false) }) }
        return nil
    }

    mutating func escape(inClass: bool) -> Node? {
        if i >= p.count { return nil }
        let c = p[i]
        i += 1
        let digit: (uint32) -> bool = { ch in ch >= 48 && ch <= 57 }
        let word: (uint32) -> bool = { ch in (ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 }
        let space: (uint32) -> bool = { ch in ch == 9 || ch == 10 || ch == 11 || ch == 12 || ch == 13 || ch == 0xFEFF || unicode.IsWhitespace(ch) }
        switch c {
        case 100: return set(digit, false)     // d
        case 68: return set(digit, true)       // D
        case 119: return set(word, false)      // w
        case 87: return set(word, true)        // W
        case 115: return set(space, false)     // s
        case 83: return set(space, true)       // S
        case 98: return inClass ? char(8) : Node(.boundary)      // b
        case 66: return inClass ? nil : Node(.notBoundary)       // B
        case 110: return char(10)              // n
        case 116: return char(9)               // t
        case 114: return char(13)              // r
        case 102: return char(12)              // f
        case 118: return char(11)              // v
        case 48: return char(0)                // 0
        case 99:                               // cX
            if i < p.count && ((p[i] >= 65 && p[i] <= 90) || (p[i] >= 97 && p[i] <= 122)) {
                i += 1
                return char(p[i - 1] % 32)
            }
            return nil
        case 120:                              // xHH
            guard let v = hex(2) else { return nil }
            return char(v)
        case 117:                              // uHHHH, u{H...}
            if eat(123) {
                var v: uint32 = 0
                var any = false
                while i < p.count && p[i] != 125 {
                    guard let d = hexValue(p[i]) else { return nil }
                    v = v * 16 + d
                    any = true
                    i += 1
                }
                if !eat(125) || !any || v > 0x10FFFF { return nil }
                return char(v)
            }
            guard let v = hex(4) else { return nil }
            return char(v)
        case 112, 80:                          // p{...} P{...}
            guard eat(123) else { return nil }
            var name = ""
            while i < p.count && p[i] != 125 {
                if let u = Unicode.Scalar(p[i]) { name += string(Character(u)) }
                i += 1
            }
            guard eat(125), let test = propertyTest(name) else { return nil }
            return set(test, c == 80)
        case 107:                              // k<name>
            guard eat(60) else { return nil }
            var name = ""
            while i < p.count && p[i] != 62 {
                if let u = Unicode.Scalar(p[i]) { name += string(Character(u)) }
                i += 1
            }
            guard eat(62), let g = names[name] else { return nil }
            let n = Node(.backref)
            n.index = g
            return n
        default:
            if c >= 49 && c <= 57 && !inClass {    // \1 .. \9...
                var v = int(c - 48)
                while i < p.count && p[i] >= 48 && p[i] <= 57 {
                    v = v * 10 + int(p[i] - 48)
                    i += 1
                }
                backrefs.append(v)
                let n = Node(.backref)
                n.index = v
                return n
            }
            // An escaped syntax character stands for itself; other
            // escapes are errors in Unicode mode.
            let syntax: [uint32] = [94, 36, 92, 46, 42, 43, 63, 40, 41, 91, 93, 123, 125, 124, 47, 45, 38, 33, 35, 37, 44, 58, 59, 60, 61, 62, 64, 96, 126]
            if syntax.contains(c) { return char(c) }
            return nil
        }
    }

    mutating func hex(n: int) -> uint32? {
        var v: uint32 = 0
        var k = 0
        while k < n {
            guard i < p.count, let d = hexValue(p[i]) else { return nil }
            v = v * 16 + d
            i += 1
            k += 1
        }
        return v
    }
}

func char(v: uint32) -> Node {
    let n = Node(.char)
    n.char = v
    return n
}

func set(test: @escaping (uint32) -> bool, negated: bool) -> Node {
    let s = CharSet()
    s.tests.append(test)
    s.negated = negated
    let n = Node(.set)
    n.set = s
    return n
}

func hexValue(c: uint32) -> uint32? {
    if c >= 48 && c <= 57 { return c - 48 }
    if c >= 65 && c <= 70 { return c - 55 }
    if c >= 97 && c <= 102 { return c - 87 }
    return nil
}

/// \p{...}: a general category (L, Lu, Letter, ...), Script= or
/// Script_Extensions= a script, or a binary property (Alphabetic,
/// White_Space, Emoji, ...).
func propertyTest(name: string) -> ((uint32) -> bool)? {
    var key = name
    var value = ""
    if let eq = name.firstIndex(of: "=") {
        key = string(name[name.startIndex..<eq])
        value = string(name[name.index(after: eq)...])
    }
    if !value.isEmpty {
        switch key {
        case "General_Category", "gc": return categoryTest(value)
        case "Script", "sc", "Script_Extensions", "scx":
            guard let script = unicode.ScriptName(value) else { return nil }
            if key.hasPrefix("Script_E") || key == "scx" {
                return { c in unicode.ScriptExtensions(c).contains(script) }
            }
            return { c in unicode.Script(c) == script }
        default: return nil
        }
    }
    if let t = categoryTest(key) { return t }
    if key == "Any" { return { _ in true } }
    if key == "ASCII" { return { c in c < 128 } }
    if key == "Assigned" { return { c in unicode.IsAssigned(c) } }
    guard let set = unicode.Property(key) else { return nil }
    return { c in set.Contains(c) }
}

/// A general category by its short name or long one, single letter for
/// the group (L is every letter).
func categoryTest(name: string) -> ((uint32) -> bool)? {
    let long: [string: string] = [
        "Letter": "L", "Cased_Letter": "LC", "Uppercase_Letter": "Lu", "Lowercase_Letter": "Ll", "Titlecase_Letter": "Lt",
        "Modifier_Letter": "Lm", "Other_Letter": "Lo", "Mark": "M", "Nonspacing_Mark": "Mn", "Spacing_Mark": "Mc",
        "Enclosing_Mark": "Me", "Number": "N", "Decimal_Number": "Nd", "digit": "Nd", "Letter_Number": "Nl", "Other_Number": "No",
        "Punctuation": "P", "punct": "P", "Connector_Punctuation": "Pc", "Dash_Punctuation": "Pd", "Open_Punctuation": "Ps",
        "Close_Punctuation": "Pe", "Initial_Punctuation": "Pi", "Final_Punctuation": "Pf", "Other_Punctuation": "Po",
        "Symbol": "S", "Math_Symbol": "Sm", "Currency_Symbol": "Sc", "Modifier_Symbol": "Sk", "Other_Symbol": "So",
        "Separator": "Z", "Space_Separator": "Zs", "Line_Separator": "Zl", "Paragraph_Separator": "Zp",
        "Other": "C", "Control": "Cc", "cntrl": "Cc", "Format": "Cf", "Surrogate": "Cs", "Private_Use": "Co", "Unassigned": "Cn",
    ]
    let short = long[name] ?? name
    let all = ["Cn", "Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
               "Sm", "Sc", "Sk", "So", "Zs", "Zl", "Zp", "Cc", "Cf", "Cs", "Co"]
    if short == "LC" { return { c in let a = unicode.Category(c).Abbreviation; return a == "Lu" || a == "Ll" || a == "Lt" } }
    if short.count == 1 && "LMNPSZC".contains(short) {
        return { c in unicode.Category(c).Abbreviation.hasPrefix(short) }
    }
    if all.contains(short) { return { c in unicode.Category(c).Abbreviation == short } }
    return nil
}
