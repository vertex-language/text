package selector

import "text/html"
import "text/css"

public enum Combinator: Equatable {
    case none
    case descendant      // " "
    case child           // ">"
    case adjacentSibling // "+"
    case generalSibling  // "~"
}

public enum AttrMatchOp: Equatable {
    case exists          // [attr]
    case exact           // [attr=val]
    case prefix          // [attr^=val]
    case suffix          // [attr$=val]
    case contains        // [attr*=val]
}

public struct AttrSelector: Equatable {
    public var Name: string
    public var Value: string
    public var Op: AttrMatchOp

    public init(name: string, value: string = "", op: AttrMatchOp = .exists) {
        self.Name = name
        self.Value = value
        self.Op = op
    }
}

public struct SelectorPart {
    public var Tag: string?
    public var Id: string?
    public var Classes: [string]
    public var Attributes: [AttrSelector]
    public var PseudoClasses: [string]

    public init() {
        self.Tag = nil
        self.Id = nil
        self.Classes = []
        self.Attributes = []
        self.PseudoClasses = []
    }
}

public struct CompoundSelector {
    public var Part: SelectorPart
    public var CombinatorWithNext: Combinator // Relationship to the NEXT compound to the right

    public init(part: SelectorPart, combinator: Combinator = .none) {
        self.Part = part
        self.CombinatorWithNext = combinator
    }
}

public struct ComplexSelector {
    public var Compounds: [CompoundSelector] // Left to right, e.g. ["div", ">", "p"]

    public init(compounds: [CompoundSelector] = []) {
        self.Compounds = compounds
    }

    /// Specificity tuple: (ID count, Class/Attribute/Pseudo count, Tag count)
    public func Specificity() -> (int, int, int) {
        var ids = 0
        var classes = 0
        var tags = 0

        var i = 0
        while i < Compounds.count {
            let p = Compounds[i].Part
            if p.Id != nil { ids += 1 }
            classes += p.Classes.count + p.Attributes.count + p.PseudoClasses.count
            if let t = p.Tag {
                if t != "*" { tags += 1 }
            }
            i += 1
        }
        return (ids, classes, tags)
    }
}

/// Parses a selector string like "div.container > h1#title, a[href^='https']"
public func ParseSelectors(_ selectorString: string) -> [ComplexSelector] {
    let rawList = splitByComma(selectorString)
    var selectors: [ComplexSelector] = []

    var i = 0
    while i < rawList.count {
        let trimmed = trim(rawList[i])
        if !trimmed.isEmpty {
            if let complex = parseComplexSelector(trimmed) {
                selectors.append(complex)
            }
        }
        i += 1
    }
    return selectors
}

func parseComplexSelector(_ selStr: string) -> ComplexSelector? {
    let bytes = bytesFrom(selStr)
    var pos = 0
    let len = bytes.count
    var compounds: [CompoundSelector] = []

    while pos < len {
        // Skip whitespace
        while pos < len && isSpace(bytes[pos]) {
            pos += 1
        }
        if pos >= len { break }

        // Check for combinator
        if bytes[pos] == 62 { // '>'
            if !compounds.isEmpty {
                compounds[compounds.count - 1].CombinatorWithNext = Combinator.child
            }
            pos += 1
            continue
        }
        if bytes[pos] == 43 { // '+'
            if !compounds.isEmpty {
                compounds[compounds.count - 1].CombinatorWithNext = Combinator.adjacentSibling
            }
            pos += 1
            continue
        }
        if bytes[pos] == 126 { // '~'
            if !compounds.isEmpty {
                compounds[compounds.count - 1].CombinatorWithNext = Combinator.generalSibling
            }
            pos += 1
            continue
        }

        // Parse compound part
        var part = SelectorPart()
        var readAny = false

        while pos < len && !isSpace(bytes[pos]) && bytes[pos] != 62 && bytes[pos] != 43 && bytes[pos] != 126 && bytes[pos] != 44 {
            let b = bytes[pos]

            if b == 35 { // '#' ID
                pos += 1
                let start = pos
                while pos < len && isIdent(bytes[pos]) { pos += 1 }
                part.Id = strFrom(bytes, start, pos)
                readAny = true
            } else if b == 46 { // '.' Class
                pos += 1
                let start = pos
                while pos < len && isIdent(bytes[pos]) { pos += 1 }
                part.Classes.append(strFrom(bytes, start, pos))
                readAny = true
            } else if b == 58 { // ':' Pseudo
                pos += 1
                let start = pos
                while pos < len && isIdent(bytes[pos]) { pos += 1 }
                part.PseudoClasses.append(strFrom(bytes, start, pos))
                readAny = true
            } else if b == 91 { // '[' Attribute
                pos += 1
                let attr = parseAttrSelector(bytes, &pos)
                part.Attributes.append(attr)
                readAny = true
            } else if isIdent(b) || b == 42 { // Tag name or '*'
                let start = pos
                while pos < len && (isIdent(bytes[pos]) || bytes[pos] == 42) { pos += 1 }
                part.Tag = strFrom(bytes, start, pos)
                readAny = true
            } else {
                pos += 1
            }
        }

        if readAny {
            compounds.append(CompoundSelector(part: part, combinator: Combinator.descendant))
        }
    }

    if compounds.isEmpty {
        return nil
    }

    // The last compound has no next compound
    compounds[compounds.count - 1].CombinatorWithNext = Combinator.none

    return ComplexSelector(compounds: compounds)
}

func parseAttrSelector(_ bytes: [uint8], _ pos: inout int) -> AttrSelector {
    let len = bytes.count
    // Skip spaces
    while pos < len && isSpace(bytes[pos]) { pos += 1 }
    let nameStart = pos
    while pos < len && isIdent(bytes[pos]) { pos += 1 }
    let attrName = strFrom(bytes, nameStart, pos)

    while pos < len && isSpace(bytes[pos]) { pos += 1 }

    if pos >= len || bytes[pos] == 93 { // ']'
        if pos < len { pos += 1 }
        return AttrSelector(name: attrName, value: "", op: AttrMatchOp.exists)
    }

    var op = AttrMatchOp.exact
    if bytes[pos] == 94 && pos + 1 < len && bytes[pos + 1] == 61 { // '^='
        op = AttrMatchOp.prefix
        pos += 2
    } else if bytes[pos] == 36 && pos + 1 < len && bytes[pos + 1] == 61 { // '$='
        op = AttrMatchOp.suffix
        pos += 2
    } else if bytes[pos] == 42 && pos + 1 < len && bytes[pos + 1] == 61 { // '*='
        op = AttrMatchOp.contains
        pos += 2
    } else if bytes[pos] == 61 { // '='
        op = AttrMatchOp.exact
        pos += 1
    }

    while pos < len && isSpace(bytes[pos]) { pos += 1 }

    var val = ""
    if pos < len && (bytes[pos] == 34 || bytes[pos] == 39) { // quoted
        let q = bytes[pos]
        pos += 1
        let valStart = pos
        while pos < len && bytes[pos] != q { pos += 1 }
        val = strFrom(bytes, valStart, pos)
        if pos < len { pos += 1 }
    } else {
        let valStart = pos
        while pos < len && bytes[pos] != 93 && !isSpace(bytes[pos]) { pos += 1 }
        val = strFrom(bytes, valStart, pos)
    }

    while pos < len && bytes[pos] != 93 { pos += 1 }
    if pos < len { pos += 1 } // skip ']'

    return AttrSelector(name: attrName, value: val, op: op)
}

func bytesFrom(_ s: string) -> [uint8] {
    var out: [uint8] = []
    for b in s.utf8 { out.append(b) }
    return out
}

func strFrom(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    var chars: [CChar] = []
    var i = start
    while i < end {
        chars.append(CChar(truncatingIfNeeded: bytes[i]))
        i += 1
    }
    chars.append(0)
    return string(cString: chars)
}

func isSpace(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13
}

func isIdent(_ b: uint8) -> bool {
    return (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 45 || b == 95
}

func trim(_ s: string) -> string {
    let b = bytesFrom(s)
    if b.isEmpty { return "" }
    var st = 0
    while st < b.count && isSpace(b[st]) { st += 1 }
    var en = b.count
    while en > st && isSpace(b[en - 1]) { en -= 1 }
    return strFrom(b, st, en)
}

func splitByComma(_ s: string) -> [string] {
    var out: [string] = []
    var current: [uint8] = []
    var inQuotes = false
    var quoteChar: uint8 = 0

    for b in s.utf8 {
        if (b == 34 || b == 39) && (!inQuotes || b == quoteChar) {
            inQuotes = !inQuotes
            quoteChar = inQuotes ? b : 0
            current.append(b)
        } else if b == 44 && !inQuotes { // ','
            out.append(strFrom(current, 0, current.count))
            current = []
        } else {
            current.append(b)
        }
    }
    if !current.isEmpty {
        out.append(strFrom(current, 0, current.count))
    }
    return out
}
